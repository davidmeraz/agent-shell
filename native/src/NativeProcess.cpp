#include "NativeProcess.h"

LineParser::LineParser(QObject *parent)
    : QObject(parent)
{
}

void LineParser::feed(const QByteArray &chunk)
{
    if (chunk.isEmpty()) {
        return;
    }
    m_buffer.append(chunk);
    qsizetype newline = m_buffer.indexOf('\n');
    while (newline >= 0) {
        QByteArray line = m_buffer.left(newline);
        if (line.endsWith('\r')) {
            line.chop(1);
        }
        m_buffer.remove(0, newline + 1);
        emit read(QString::fromUtf8(line));
        newline = m_buffer.indexOf('\n');
    }
}

void LineParser::flush()
{
    if (m_buffer.isEmpty()) {
        return;
    }
    QByteArray line = m_buffer;
    if (line.endsWith('\r')) {
        line.chop(1);
    }
    m_buffer.clear();
    emit read(QString::fromUtf8(line));
}

void LineParser::reset()
{
    m_buffer.clear();
}

NativeProcess::NativeProcess(QObject *parent)
    : QObject(parent)
{
}

NativeProcess::~NativeProcess()
{
    stopProcess(true);
}

void NativeProcess::classBegin()
{
    m_complete = false;
}

void NativeProcess::componentComplete()
{
    m_complete = true;
    if (m_desiredRunning && !m_running) {
        startProcess();
    }
}

void NativeProcess::setCommand(const QStringList &cmd)
{
    if (m_command == cmd) {
        return;
    }
    m_command = cmd;
    emit commandChanged();
}

void NativeProcess::setWorkingDirectory(const QString &dir)
{
    if (m_workingDirectory == dir) {
        return;
    }
    m_workingDirectory = dir;
    emit workingDirectoryChanged();
}

void NativeProcess::setStdinEnabled(bool enabled)
{
    if (m_stdinEnabled == enabled) {
        return;
    }
    m_stdinEnabled = enabled;
    emit stdinEnabledChanged();
}

void NativeProcess::setOutputParser(LineParser *parser)
{
    if (m_outputParser == parser) {
        return;
    }
    m_outputParser = parser;
    emit outputChanged();
}

void NativeProcess::setErrorOutputParser(LineParser *parser)
{
    if (m_errorOutputParser == parser) {
        return;
    }
    m_errorOutputParser = parser;
    emit errorOutputChanged();
}

void NativeProcess::setRunning(bool shouldRun)
{
    m_desiredRunning = shouldRun;
    if (!m_complete) {
        return;
    }
    if (shouldRun) {
        if (!m_running) {
            startProcess();
        }
    } else {
        stopProcess(false);
    }
}

void NativeProcess::write(const QString &data)
{
    if (!m_process || !m_running || !m_stdinEnabled) {
        return;
    }
    m_process->write(data.toUtf8());
}

void NativeProcess::startProcess()
{
    if (m_command.isEmpty() || m_command.first().isEmpty()) {
        return;
    }
    stopProcess(true);

    if (m_outputParser) {
        m_outputParser->reset();
    }
    if (m_errorOutputParser) {
        m_errorOutputParser->reset();
    }

    auto *proc = new QProcess(this);
    m_process = proc;
    if (!m_workingDirectory.isEmpty()) {
        proc->setWorkingDirectory(m_workingDirectory);
    }

    connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
        if (proc != m_process) {
            return;
        }
        const QByteArray bytes = proc->readAllStandardOutput();
        if (m_outputParser) {
            m_outputParser->feed(bytes);
        }
    });

    connect(proc, &QProcess::readyReadStandardError, this, [this, proc]() {
        if (proc != m_process) {
            return;
        }
        const QByteArray bytes = proc->readAllStandardError();
        if (m_errorOutputParser) {
            m_errorOutputParser->feed(bytes);
        }
    });

    connect(proc, &QProcess::finished, this, [this, proc](int exitCode, QProcess::ExitStatus status) {
        if (proc != m_process) {
            proc->deleteLater();
            return;
        }
        if (m_outputParser) {
            m_outputParser->feed(proc->readAllStandardOutput());
            m_outputParser->flush();
        }
        if (m_errorOutputParser) {
            m_errorOutputParser->feed(proc->readAllStandardError());
            m_errorOutputParser->flush();
        }
        m_process = nullptr;
        proc->deleteLater();
        const bool wasRunning = m_running;
        m_running = false;
        m_desiredRunning = false;
        if (wasRunning) {
            emit runningChanged();
        }
        emit exited(exitCode, static_cast<int>(status));
    });

    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError error) {
        if (proc != m_process || error != QProcess::FailedToStart) {
            return;
        }
        if (m_errorOutputParser) {
            m_errorOutputParser->feed(proc->errorString().toUtf8() + '\n');
        }
        m_process = nullptr;
        proc->deleteLater();
        const bool wasRunning = m_running;
        m_running = false;
        m_desiredRunning = false;
        if (wasRunning) {
            emit runningChanged();
        }
        emit exited(-1, 1);
    });

    m_running = true;
    emit runningChanged();

    const QString program = m_command.first();
    const QStringList args = m_command.mid(1);
    proc->start(program, args, m_stdinEnabled ? QIODevice::ReadWrite : QIODevice::ReadOnly);
    if (!m_stdinEnabled) {
        proc->closeWriteChannel();
    }
}

void NativeProcess::stopProcess(bool silent)
{
    if (!m_process) {
        if (m_running) {
            m_running = false;
            if (!silent) {
                emit runningChanged();
            }
        }
        return;
    }

    QProcess *proc = m_process;
    m_process = nullptr;
    proc->disconnect(this);

    if (proc->state() != QProcess::NotRunning) {
        proc->closeWriteChannel();
        proc->terminate();
        if (!proc->waitForFinished(400)) {
            proc->kill();
            proc->waitForFinished(400);
        }
    }
    delete proc;

    if (m_running) {
        m_running = false;
        if (!silent) {
            emit runningChanged();
        }
    }
}
