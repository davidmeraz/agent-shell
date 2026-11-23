#include "SingleInstance.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocalSocket>
#include <QStandardPaths>
#include <unistd.h>

SingleInstance::SingleInstance(const QString &socketPath, QObject *parent)
    : QObject(parent)
    , m_socketPath(socketPath)
{
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    connect(&m_server, &QLocalServer::newConnection, this, &SingleInstance::handleConnection);
}

SingleInstance::~SingleInstance()
{
    if (m_server.isListening()) {
        m_server.close();
    }
}

QString SingleInstance::defaultSocketPath()
{
    QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty() || !QDir(runtimeDir).exists()) {
        runtimeDir = QDir::tempPath();
    }
    return QDir(runtimeDir).filePath(QStringLiteral("agent-shell-%1.ipc").arg(static_cast<qulonglong>(::getuid())));
}

bool SingleInstance::sendCommand(const QString &socketPath,
                                 const QString &command,
                                 QString *replyOut,
                                 int timeoutMs)
{
    QLocalSocket socket;
    socket.connectToServer(socketPath, QIODevice::ReadWrite);
    if (!socket.waitForConnected(timeoutMs)) {
        return false;
    }
    socket.write(command.toUtf8() + '\n');
    while (socket.bytesToWrite() > 0) {
        if (!socket.waitForBytesWritten(timeoutMs)) {
            return false;
        }
    }
    if (socket.waitForReadyRead(timeoutMs)) {
        const QByteArray raw = socket.readAll().trimmed();
        if (replyOut) {
            *replyOut = QString::fromUtf8(raw);
        }
    }
    socket.disconnectFromServer();
    return true;
}

bool SingleInstance::listen()
{
    const QFileInfo info(m_socketPath);
    QDir().mkpath(info.absolutePath());
    QLocalServer::removeServer(m_socketPath);
    QFile::remove(m_socketPath);
    return m_server.listen(m_socketPath);
}

void SingleInstance::handleConnection()
{
    while (QLocalSocket *client = m_server.nextPendingConnection()) {
        auto processClient = [this, client]() {
            if (!client->canReadLine()) {
                return;
            }
            const QString command = QString::fromUtf8(client->readLine()).trimmed();
            QString reply = QStringLiteral("ok");
            emit commandReceived(command, &reply);
            client->write(reply.toUtf8() + '\n');
            client->flush();
            client->disconnectFromServer();
        };
        connect(client, &QLocalSocket::readyRead, this, processClient);
        connect(client, &QLocalSocket::disconnected, client, &QLocalSocket::deleteLater);
        if (client->bytesAvailable() > 0) {
            processClient();
        }
    }
}
