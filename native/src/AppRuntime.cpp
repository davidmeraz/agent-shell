#include "AppRuntime.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJSEngine>
#include <QProcess>
#include <QQmlEngine>
#include <QStandardPaths>

namespace {
QString g_configuredAppDir;
QString g_configuredWorkspace;
QString g_configuredVersion;
} // namespace

NativeApp::NativeApp(QObject *parent)
    : QObject(parent)
    , m_appDir(g_configuredAppDir)
    , m_initialWorkspace(g_configuredWorkspace)
    , m_appVersion(g_configuredVersion)
    , m_offscreen(QGuiApplication::platformName() == QStringLiteral("offscreen"))
{
    if (auto *cb = QGuiApplication::clipboard()) {
        connect(cb, &QClipboard::dataChanged, this, &NativeApp::clipboardTextChanged);
    }
}

NativeApp *NativeApp::instance()
{
    static NativeApp *singleton = nullptr;
    if (!singleton) {
        singleton = new NativeApp(QCoreApplication::instance());
        QJSEngine::setObjectOwnership(singleton, QJSEngine::CppOwnership);
    }
    return singleton;
}

NativeApp *NativeApp::create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
{
    Q_UNUSED(qmlEngine)
    Q_UNUSED(jsEngine)
    return instance();
}

void NativeApp::configure(const QString &appDir,
                          const QString &initialWorkspace,
                          const QString &appVersion)
{
    g_configuredAppDir = appDir;
    g_configuredWorkspace = initialWorkspace;
    g_configuredVersion = appVersion;
}

QString NativeApp::env(const QString &name) const
{
    if (name.isEmpty()) {
        return {};
    }
    return qEnvironmentVariable(name.toUtf8().constData());
}

qint64 NativeApp::processId() const
{
    return QCoreApplication::applicationPid();
}

QString NativeApp::pythonExecutable() const
{
    const QString overridePy = qEnvironmentVariable("AGENT_SHELL_PYTHON");
    if (!overridePy.isEmpty()) {
        return overridePy;
    }
    if (!m_appDir.isEmpty()) {
        const QString venvPy = QDir(m_appDir).filePath(QStringLiteral(".venv/bin/python"));
        if (QFileInfo(venvPy).isExecutable()) {
            return venvPy;
        }
    }
    const QString sysPy = QStandardPaths::findExecutable(QStringLiteral("python3"));
    return sysPy.isEmpty() ? QStringLiteral("/usr/bin/python3") : sysPy;
}

QString NativeApp::backendEntry() const
{
    const QString overrideEntry = qEnvironmentVariable("AGENT_SHELL_BACKEND_ENTRY");
    if (!overrideEntry.isEmpty()) {
        return overrideEntry;
    }
    return QDir(m_appDir).filePath(QStringLiteral("backend/main.py"));
}

QString NativeApp::placementScript() const
{
    const QString overrideScript = qEnvironmentVariable("AGENT_SHELL_PLACEMENT_SCRIPT");
    if (!overrideScript.isEmpty()) {
        return overrideScript;
    }
    return QDir(m_appDir).filePath(QStringLiteral("scripts/place-text-viewer.py"));
}

QString NativeApp::clipboardText() const
{
    if (m_offscreen) {
        return m_offscreenClipboard;
    }
    if (auto *cb = QGuiApplication::clipboard()) {
        return cb->text(QClipboard::Clipboard);
    }
    return {};
}

void NativeApp::setClipboardText(const QString &text)
{
    if (m_offscreen) {
        if (m_offscreenClipboard == text) {
            return;
        }
        m_offscreenClipboard = text;
        if (auto *cb = QGuiApplication::clipboard()) {
            cb->setText(text, QClipboard::Clipboard);
        }
        emit clipboardTextChanged();
        return;
    }
    if (auto *cb = QGuiApplication::clipboard()) {
        cb->setText(text, QClipboard::Clipboard);
        emit clipboardTextChanged();
    }
}

void NativeApp::focusInHyprland(const QString &windowTitle) const
{
    if (m_offscreen || qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")) {
        return;
    }
    const QString hyprctl = QStandardPaths::findExecutable(QStringLiteral("hyprctl"));
    if (hyprctl.isEmpty()) {
        return;
    }
    const QString selector = windowTitle.isEmpty()
        ? QStringLiteral("pid:%1").arg(processId())
        : QStringLiteral("pid:%1").arg(processId());
    QProcess::startDetached(hyprctl, {QStringLiteral("dispatch"), QStringLiteral("focuswindow"), selector});
}

void NativeApp::triggerActivate()
{
    emit activateRequested();
}

void NativeApp::triggerToggle()
{
    emit toggleRequested();
}

void NativeApp::triggerQuit()
{
    emit quitRequested();
}
