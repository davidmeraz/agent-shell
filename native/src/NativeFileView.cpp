#include "NativeFileView.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>

NativeFileView::NativeFileView(QObject *parent)
    : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(30);

    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &) {
        m_debounce.start();
    });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
        m_debounce.start();
    });
    connect(&m_debounce, &QTimer::timeout, this, &NativeFileView::handleWatchEvent);
}

void NativeFileView::classBegin()
{
    m_complete = false;
}

void NativeFileView::componentComplete()
{
    m_complete = true;
    reload();
    syncWatcher();
}

void NativeFileView::setPath(const QString &path)
{
    if (m_path == path) {
        return;
    }
    m_path = path;
    m_loaded = false;
    emit pathChanged();
    if (m_complete) {
        reload();
        syncWatcher();
    }
}

void NativeFileView::setBlockLoading(bool block)
{
    if (m_blockLoading == block) {
        return;
    }
    m_blockLoading = block;
    emit blockLoadingChanged();
}

void NativeFileView::setPrintErrors(bool enabled)
{
    if (m_printErrors == enabled) {
        return;
    }
    m_printErrors = enabled;
    emit printErrorsChanged();
}

void NativeFileView::setWatchChanges(bool watch)
{
    if (m_watchChanges == watch) {
        return;
    }
    m_watchChanges = watch;
    emit watchChangesChanged();
    if (m_complete) {
        syncWatcher();
    }
}

bool NativeFileView::readFileContents(QString *outText) const
{
    if (m_path.isEmpty()) {
        return false;
    }
    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (m_printErrors) {
            qWarning().noquote() << "NativeFileView: no se pudo abrir" << m_path << ":" << file.errorString();
        }
        return false;
    }
    *outText = QString::fromUtf8(file.readAll());
    return true;
}

QString NativeFileView::text()
{
    if (!m_loaded && !m_path.isEmpty()) {
        QString fresh;
        if (readFileContents(&fresh)) {
            m_cachedText = fresh;
            m_loaded = true;
        }
    }
    return m_cachedText;
}

void NativeFileView::reload()
{
    QString fresh;
    if (readFileContents(&fresh)) {
        m_cachedText = fresh;
        m_loaded = true;
        emit loaded();
    } else {
        m_cachedText.clear();
        m_loaded = false;
    }
}

void NativeFileView::syncWatcher()
{
    const QStringList watchedFiles = m_watcher.files();
    if (!watchedFiles.isEmpty()) {
        m_watcher.removePaths(watchedFiles);
    }
    const QStringList watchedDirs = m_watcher.directories();
    if (!watchedDirs.isEmpty()) {
        m_watcher.removePaths(watchedDirs);
    }

    if (!m_watchChanges || m_path.isEmpty()) {
        return;
    }

    const QFileInfo info(m_path);
    const QString parentDir = info.absolutePath();
    if (QDir(parentDir).exists()) {
        m_watcher.addPath(parentDir);
    }
    if (info.exists()) {
        m_watcher.addPath(info.absoluteFilePath());
    }
}

void NativeFileView::handleWatchEvent()
{
    if (!m_watchChanges || m_path.isEmpty()) {
        return;
    }

    // Re-suscribe el archivo tras escrituras atómicas (rename / os.replace de Gema).
    const QFileInfo info(m_path);
    const QString absFile = info.absoluteFilePath();
    if (info.exists() && !m_watcher.files().contains(absFile)) {
        m_watcher.addPath(absFile);
    }

    QString fresh;
    if (!readFileContents(&fresh)) {
        return;
    }
    if (!m_loaded || fresh != m_cachedText) {
        m_cachedText = fresh;
        m_loaded = true;
        emit fileChanged();
    }
}
