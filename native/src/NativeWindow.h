#pragma once

#include <QQmlParserStatus>
#include <QQuickWindow>
#include <QSize>
#include <QtQml/qqmlregistration.h>

class NativeWindow : public QQuickWindow, public QQmlParserStatus {
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(int implicitWidth READ implicitWidth WRITE setImplicitWidth NOTIFY implicitWidthChanged)
    Q_PROPERTY(int implicitHeight READ implicitHeight WRITE setImplicitHeight NOTIFY implicitHeightChanged)
    Q_PROPERTY(QSize minimumSize READ minimumSize WRITE setMinimumSize NOTIFY minimumSizeChanged)
    Q_PROPERTY(QSize maximumSize READ maximumSize WRITE setMaximumSize NOTIFY maximumSizeChanged)
    Q_PROPERTY(bool backingWindowVisible READ isVisible NOTIFY backingWindowVisibleChanged)

public:
    explicit NativeWindow(QWindow *parent = nullptr);
    ~NativeWindow() override = default;

    int implicitWidth() const { return m_implicitWidth; }
    void setImplicitWidth(int value);

    int implicitHeight() const { return m_implicitHeight; }
    void setImplicitHeight(int value);

    QSize minimumSize() const { return m_minimumSize; }
    void setMinimumSize(const QSize &size);

    QSize maximumSize() const { return m_maximumSize; }
    void setMaximumSize(const QSize &size);

    Q_INVOKABLE void focusWindow();

    void classBegin() override;
    void componentComplete() override;

signals:
    void implicitWidthChanged();
    void implicitHeightChanged();
    void minimumSizeChanged();
    void maximumSizeChanged();
    void backingWindowVisibleChanged();
    void closed();

protected:
    bool event(QEvent *ev) override;

private:
    void applySizeConstraints(bool applyImplicit);

    static constexpr int kMaxWindowDimension = 16777215;

    int m_implicitWidth = 0;
    int m_implicitHeight = 0;
    QSize m_minimumSize{0, 0};
    QSize m_maximumSize{kMaxWindowDimension, kMaxWindowDimension};
    bool m_complete = true;
    bool m_applyingSize = false;
    bool m_userResizedWidth = false;
    bool m_userResizedHeight = false;
};
