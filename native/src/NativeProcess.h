#pragma once

#include <QByteArray>
#include <QObject>
#include <QProcess>
#include <QQmlParserStatus>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class LineParser : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit LineParser(QObject *parent = nullptr);
    ~LineParser() override = default;

    void feed(const QByteArray &chunk);
    void flush();
    void reset();

signals:
    void read(const QString &data);

private:
    QByteArray m_buffer;
};

class NativeProcess : public QObject, public QQmlParserStatus {
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(QStringList command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(QString workingDirectory READ workingDirectory WRITE setWorkingDirectory NOTIFY workingDirectoryChanged)
    Q_PROPERTY(bool stdinEnabled READ stdinEnabled WRITE setStdinEnabled NOTIFY stdinEnabledChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(LineParser *output READ outputParser WRITE setOutputParser NOTIFY outputChanged)
    Q_PROPERTY(LineParser *errorOutput READ errorOutputParser WRITE setErrorOutputParser NOTIFY errorOutputChanged)

public:
    explicit NativeProcess(QObject *parent = nullptr);
    ~NativeProcess() override;

    QStringList command() const { return m_command; }
    void setCommand(const QStringList &cmd);

    QString workingDirectory() const { return m_workingDirectory; }
    void setWorkingDirectory(const QString &dir);

    bool stdinEnabled() const { return m_stdinEnabled; }
    void setStdinEnabled(bool enabled);

    bool running() const { return m_running; }
    void setRunning(bool shouldRun);

    LineParser *outputParser() const { return m_outputParser; }
    void setOutputParser(LineParser *parser);

    LineParser *errorOutputParser() const { return m_errorOutputParser; }
    void setErrorOutputParser(LineParser *parser);

    Q_INVOKABLE void write(const QString &data);

    void classBegin() override;
    void componentComplete() override;

signals:
    void commandChanged();
    void workingDirectoryChanged();
    void stdinEnabledChanged();
    void runningChanged();
    void outputChanged();
    void errorOutputChanged();
    void exited(int exitCode, int exitStatus);

private:
    void startProcess();
    void stopProcess(bool silent);

    QStringList m_command;
    QString m_workingDirectory;
    bool m_stdinEnabled = false;
    bool m_running = false;
    bool m_desiredRunning = false;
    bool m_complete = true;
    LineParser *m_outputParser = nullptr;
    LineParser *m_errorOutputParser = nullptr;
    QProcess *m_process = nullptr;
};
