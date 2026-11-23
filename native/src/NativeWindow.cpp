#include "NativeWindow.h"

#include <QEvent>
#include <algorithm>

NativeWindow::NativeWindow(QWindow *parent)
    : QQuickWindow(parent)
{
    setFlags(Qt::Window | Qt::FramelessWindowHint);
    setColor(Qt::transparent);

    connect(this, &QWindow::visibleChanged, this, &NativeWindow::backingWindowVisibleChanged);
    connect(this, &QWindow::widthChanged, this, [this](int) {
        if (!m_applyingSize && m_complete && isVisible()) {
            m_userResizedWidth = true;
        }
    });
    connect(this, &QWindow::heightChanged, this, [this](int) {
        if (!m_applyingSize && m_complete && isVisible()) {
            m_userResizedHeight = true;
        }
    });
}

void NativeWindow::classBegin()
{
    m_complete = false;
}

void NativeWindow::componentComplete()
{
    m_complete = true;
    applySizeConstraints(true);
}

void NativeWindow::setImplicitWidth(int value)
{
    const int clamped = std::max(0, value);
    if (m_implicitWidth == clamped) {
        return;
    }
    m_implicitWidth = clamped;
    emit implicitWidthChanged();
    if (m_complete) {
        applySizeConstraints(true);
    }
}

void NativeWindow::setImplicitHeight(int value)
{
    const int clamped = std::max(0, value);
    if (m_implicitHeight == clamped) {
        return;
    }
    m_implicitHeight = clamped;
    emit implicitHeightChanged();
    if (m_complete) {
        applySizeConstraints(true);
    }
}

void NativeWindow::setMinimumSize(const QSize &size)
{
    const QSize normalized(std::max(0, size.width()), std::max(0, size.height()));
    if (m_minimumSize == normalized) {
        return;
    }
    m_minimumSize = normalized;
    emit minimumSizeChanged();
    if (m_complete) {
        applySizeConstraints(false);
    }
}

void NativeWindow::setMaximumSize(const QSize &size)
{
    const int maxW = size.width() > 0 ? std::min(size.width(), kMaxWindowDimension) : kMaxWindowDimension;
    const int maxH = size.height() > 0 ? std::min(size.height(), kMaxWindowDimension) : kMaxWindowDimension;
    const QSize normalized(maxW, maxH);
    if (m_maximumSize == normalized) {
        return;
    }
    m_maximumSize = normalized;
    emit maximumSizeChanged();
    if (m_complete) {
        applySizeConstraints(false);
    }
}

void NativeWindow::applySizeConstraints(bool applyImplicit)
{
    const int minW = std::max(0, m_minimumSize.width());
    const int minH = std::max(0, m_minimumSize.height());
    const int maxW = std::max(minW, m_maximumSize.width() > 0 ? m_maximumSize.width() : kMaxWindowDimension);
    const int maxH = std::max(minH, m_maximumSize.height() > 0 ? m_maximumSize.height() : kMaxWindowDimension);

    m_applyingSize = true;

    // Evita cruces temporales min > max durante actualizaciones reactivas de bindings.
    if (minW > maximumWidth()) {
        setMaximumWidth(maxW);
    }
    if (minH > maximumHeight()) {
        setMaximumHeight(maxH);
    }
    setMinimumWidth(minW);
    setMinimumHeight(minH);
    setMaximumWidth(maxW);
    setMaximumHeight(maxH);

    int targetW = width();
    int targetH = height();

    if ((applyImplicit || targetW <= 0) && !m_userResizedWidth && m_implicitWidth > 0) {
        targetW = m_implicitWidth;
    }
    if ((applyImplicit || targetH <= 0) && !m_userResizedHeight && m_implicitHeight > 0) {
        targetH = m_implicitHeight;
    }

    if (minW == maxW && minW > 0) {
        targetW = minW;
    } else if (targetW > 0) {
        targetW = std::clamp(targetW, minW, maxW);
    }

    if (minH == maxH && minH > 0) {
        targetH = minH;
    } else if (targetH > 0) {
        targetH = std::clamp(targetH, minH, maxH);
    }

    if (targetW > 0 && targetH > 0 && (targetW != width() || targetH != height())) {
        resize(targetW, targetH);
    }

    m_applyingSize = false;
}

void NativeWindow::focusWindow()
{
    if (!isVisible()) {
        show();
    }
    raise();
    requestActivate();
}

bool NativeWindow::event(QEvent *ev)
{
    if (ev->type() == QEvent::Close) {
        hide();
        ev->accept();
        emit closed();
        return true;
    }
    return QQuickWindow::event(ev);
}
