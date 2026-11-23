#include "AppRuntime.h"
#include "SingleInstance.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QSurfaceFormat>
#include <QUrl>

#include <iostream>

#ifndef AGENT_SHELL_INSTALL_DATADIR
#define AGENT_SHELL_INSTALL_DATADIR "/usr/share/agent-shell"
#endif

namespace {

bool hasUiEntry(const QString &dirPath)
{
    if (dirPath.isEmpty()) {
        return false;
    }
    const QDir dir(dirPath);
    return dir.exists(QStringLiteral("ui/ChatWindow.qml"));
}

QString resolveAppDir(const QString &qmlOverride)
{
    const QString envDir = qEnvironmentVariable("AGENT_SHELL_APP_DIR");
    if (!envDir.isEmpty() && QDir(envDir).exists()) {
        return QDir(envDir).absolutePath();
    }

    const QString exeDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        QDir(exeDir).filePath(QStringLiteral("..")),
        exeDir,
        QDir(exeDir).filePath(QStringLiteral("../share/agent-shell/app")),
        QDir(exeDir).filePath(QStringLiteral("../share/agent-shell")),
        QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
            .filePath(QStringLiteral("agent-shell/app")),
        QStringLiteral(AGENT_SHELL_INSTALL_DATADIR),
    };

    for (const QString &candidate : candidates) {
        const QString clean = QDir(candidate).canonicalPath();
        if (!clean.isEmpty() && hasUiEntry(clean)) {
            return clean;
        }
    }

    if (!qmlOverride.isEmpty()) {
        return QFileInfo(qmlOverride).absolutePath();
    }
    return exeDir;
}

QString resolveInitialWorkspace(const QString &cliWorkspace)
{
    if (!cliWorkspace.isEmpty()) {
        return QDir(cliWorkspace).absolutePath();
    }
    const QString envWorkspace = qEnvironmentVariable("AGENT_SHELL_WORKSPACE");
    if (!envWorkspace.isEmpty()) {
        return QDir(envWorkspace).absolutePath();
    }
    const QString cwd = QDir::currentPath();
    if (cwd == QStringLiteral("/") || cwd.startsWith(QStringLiteral("/usr/"))) {
        return QDir::homePath();
    }
    return cwd;
}

QIcon resolveAppIcon(const QString &appDir)
{
    QIcon icon = QIcon::fromTheme(QStringLiteral("agent-shell"));
    if (!icon.isNull()) {
        return icon;
    }
    const QStringList paths = {
        QDir(appDir).filePath(QStringLiteral("agent-shell.svg")),
        QDir(appDir).filePath(QStringLiteral("packaging/arch/agent-shell.svg")),
    };
    for (const QString &path : paths) {
        if (QFileInfo::exists(path)) {
            return QIcon(path);
        }
    }
    return {};
}

} // namespace

int main(int argc, char *argv[])
{
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);

    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("Basic"));
    }

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("agent-shell"));
    // Evita que Qt añada " — <app>" al título Wayland (requerido por place-text-viewer.py y la estética limpia).
    QGuiApplication::setApplicationDisplayName(QString());
    QGuiApplication::setOrganizationName(QStringLiteral("agent-shell"));
    QGuiApplication::setApplicationVersion(QStringLiteral(AGENT_SHELL_VERSION));
    // Identidad Wayland propia (xdg_toplevel app_id = "agent-shell") para Hyprland y Gema.
    QGuiApplication::setDesktopFileName(QStringLiteral("agent-shell"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Agent Shell · Cliente nativo Qt6/Wayland integrado con Hyprland y Gema"));
    parser.addHelpOption();
    parser.addVersionOption();

    const QCommandLineOption toggleOpt({QStringLiteral("t"), QStringLiteral("toggle")},
                                       QStringLiteral("Alterna la visibilidad de Agent Shell (o lo inicia si no está abierto)."));
    const QCommandLineOption focusOpt({QStringLiteral("f"), QStringLiteral("focus")},
                                      QStringLiteral("Enfoca la instancia activa (o inicia una nueva)."));
    const QCommandLineOption quitOpt({QStringLiteral("q"), QStringLiteral("quit")},
                                     QStringLiteral("Cierra limpiamente la instancia en ejecución."));
    const QCommandLineOption statusOpt(QStringLiteral("status"),
                                       QStringLiteral("Muestra el estado de la instancia en formato JSON."));
    const QCommandLineOption workspaceOpt({QStringLiteral("w"), QStringLiteral("workspace")},
                                          QStringLiteral("Directorio de trabajo inicial."),
                                          QStringLiteral("dir"));
    const QCommandLineOption qmlOpt(QStringLiteral("qml"),
                                    QStringLiteral("Archivo QML de entrada personalizado (pruebas/desarrollo)."),
                                    QStringLiteral("path"));
    const QCommandLineOption noSingleOpt(QStringLiteral("no-single-instance"),
                                         QStringLiteral("Permite ejecutar una instancia aislada sin IPC."));

    parser.addOption(toggleOpt);
    parser.addOption(focusOpt);
    parser.addOption(quitOpt);
    parser.addOption(statusOpt);
    parser.addOption(workspaceOpt);
    parser.addOption(qmlOpt);
    parser.addOption(noSingleOpt);
    parser.process(app);

    const QString qmlOverride = parser.value(qmlOpt);
    const QString appDir = resolveAppDir(qmlOverride);
    const QString initialWorkspace = resolveInitialWorkspace(parser.value(workspaceOpt));
    const QString socketPath = SingleInstance::defaultSocketPath();

    if (parser.isSet(statusOpt)) {
        QString reply;
        if (SingleInstance::sendCommand(socketPath, QStringLiteral("status"), &reply)) {
            std::cout << reply.toStdString() << '\n';
            return 0;
        }
        QJsonObject offline;
        offline.insert(QStringLiteral("running"), false);
        offline.insert(QStringLiteral("version"), QStringLiteral(AGENT_SHELL_VERSION));
        offline.insert(QStringLiteral("app_dir"), appDir);
        std::cout << QJsonDocument(offline).toJson(QJsonDocument::Compact).toStdString() << '\n';
        return 0;
    }

    if (parser.isSet(quitOpt)) {
        SingleInstance::sendCommand(socketPath, QStringLiteral("quit"));
        return 0;
    }

    const bool useSingleInstance = !parser.isSet(noSingleOpt) && qmlOverride.isEmpty();
    if (useSingleInstance) {
        const QString ipcCmd = parser.isSet(toggleOpt)
            ? QStringLiteral("toggle")
            : QStringLiteral("activate");
        QString reply;
        if (SingleInstance::sendCommand(socketPath, ipcCmd, &reply)) {
            return 0;
        }
    }

    NativeApp::configure(appDir, initialWorkspace, QStringLiteral(AGENT_SHELL_VERSION));
    app.setWindowIcon(resolveAppIcon(appDir));

    SingleInstance singleInstance(socketPath);
    if (useSingleInstance) {
        if (singleInstance.listen()) {
            QObject::connect(&singleInstance, &SingleInstance::commandReceived, &app,
                             [&appDir](const QString &cmd, QString *reply) {
                if (cmd == QStringLiteral("toggle")) {
                    NativeApp::instance()->triggerToggle();
                    *reply = QStringLiteral("toggled");
                } else if (cmd == QStringLiteral("quit")) {
                    NativeApp::instance()->triggerQuit();
                    *reply = QStringLiteral("quitting");
                } else if (cmd == QStringLiteral("status")) {
                    QJsonObject st;
                    st.insert(QStringLiteral("running"), true);
                    st.insert(QStringLiteral("pid"), static_cast<qint64>(QCoreApplication::applicationPid()));
                    st.insert(QStringLiteral("version"), QStringLiteral(AGENT_SHELL_VERSION));
                    st.insert(QStringLiteral("app_dir"), appDir);
                    st.insert(QStringLiteral("app_id"), QGuiApplication::desktopFileName());
                    *reply = QString::fromUtf8(QJsonDocument(st).toJson(QJsonDocument::Compact));
                } else {
                    NativeApp::instance()->triggerActivate();
                    *reply = QStringLiteral("activated");
                }
            });
        }
    }

    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/"));
    engine.addImportPath(QCoreApplication::applicationDirPath());
    engine.addImportPath(appDir);

    const QString entryPath = qmlOverride.isEmpty()
        ? QDir(appDir).filePath(QStringLiteral("shell.qml"))
        : QFileInfo(qmlOverride).absoluteFilePath();

    if (!QFileInfo::exists(entryPath)) {
        std::cerr << "Agent Shell: no se encontró el punto de entrada QML: "
                  << entryPath.toStdString() << '\n';
        return 1;
    }

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);

    engine.load(QUrl::fromLocalFile(entryPath));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    return app.exec();
}
