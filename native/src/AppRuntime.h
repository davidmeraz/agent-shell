#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

class NativeApp : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString appDir READ appDir CONSTANT)
    Q_PROPERTY(qint64 processId READ processId CONSTANT)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString pythonExecutable READ pythonExecutable CONSTANT)
    Q_PROPERTY(QString backendEntry READ backendEntry CONSTANT)
    Q_PROPERTY(QString placementScript READ placementScript CONSTANT)
    Q_PROPERTY(QString initialWorkspace READ initialWorkspace CONSTANT)
    Q_PROPERTY(QString clipboardText READ clipboardText WRITE setClipboardText NOTIFY clipboardTextChanged)

public:
    static NativeApp *instance();
    static NativeApp *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    static void configure(const QString &appDir,
                          const QString &initialWorkspace,
                          const QString &appVersion);

    Q_INVOKABLE QString env(const QString &name) const;
    Q_INVOKABLE void focusInHyprland(const QString &windowTitle = QString()) const;

    QString appDir() const { return m_appDir; }
    qint64 processId() const;
    QString appVersion() const { return m_appVersion; }
    QString pythonExecutable() const;
    QString backendEntry() const;
    QString placementScript() const;
    QString initialWorkspace() const { return m_initialWorkspace; }

    QString clipboardText() const;
    void setClipboardText(const QString &text);

    void triggerActivate();
    void triggerToggle();
    void triggerQuit();

signals:
    void clipboardTextChanged();
    void activateRequested();
    void toggleRequested();
    void quitRequested();

private:
    explicit NativeApp(QObject *parent = nullptr);

    QString m_appDir;
    QString m_initialWorkspace;
    QString m_appVersion;
    bool m_offscreen = false;
    QString m_offscreenClipboard;
};
