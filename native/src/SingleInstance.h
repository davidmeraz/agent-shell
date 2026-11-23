#pragma once

#include <QLocalServer>
#include <QObject>
#include <QString>

class SingleInstance : public QObject {
    Q_OBJECT

public:
    explicit SingleInstance(const QString &socketPath, QObject *parent = nullptr);
    ~SingleInstance() override;

    static QString defaultSocketPath();
    static bool sendCommand(const QString &socketPath,
                            const QString &command,
                            QString *replyOut = nullptr,
                            int timeoutMs = 400);

    bool listen();

signals:
    void commandReceived(const QString &command, QString *reply);

private:
    void handleConnection();

    QString m_socketPath;
    QLocalServer m_server;
};
