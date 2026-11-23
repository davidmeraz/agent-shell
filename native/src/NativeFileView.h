#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlParserStatus>
#include <QString>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class NativeFileView : public QObject, public QQmlParserStatus {
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool blockLoading READ blockLoading WRITE setBlockLoading NOTIFY blockLoadingChanged)
    Q_PROPERTY(bool printErrors READ printErrors WRITE setPrintErrors NOTIFY printErrorsChanged)
    Q_PROPERTY(bool watchChanges READ watchChanges WRITE setWatchChanges NOTIFY watchChangesChanged)

public:
    explicit NativeFileView(QObject *parent = nullptr);
    ~NativeFileView() override = default;

    QString path() const { return m_path; }
    void setPath(const QString &path);

    bool blockLoading() const { return m_blockLoading; }
    void setBlockLoading(bool block);

    bool printErrors() const { return m_printErrors; }
    void setPrintErrors(bool enabled);

    bool watchChanges() const { return m_watchChanges; }
    void setWatchChanges(bool watch);

    Q_INVOKABLE QString text();
    Q_INVOKABLE void reload();

    void classBegin() override;
    void componentComplete() override;

signals:
    void pathChanged();
    void blockLoadingChanged();
    void printErrorsChanged();
    void watchChangesChanged();
    void loaded();
    void fileChanged();

private:
    bool readFileContents(QString *outText) const;
    void syncWatcher();
    void handleWatchEvent();

    QString m_path;
    QString m_cachedText;
    bool m_blockLoading = false;
    bool m_printErrors = true;
    bool m_watchChanges = false;
    bool m_loaded = false;
    bool m_complete = true;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
