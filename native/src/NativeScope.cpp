#include "NativeScope.h"

NativeScope::NativeScope(QObject *parent)
    : QObject(parent)
{
}

NativeScope::~NativeScope() = default;

QQmlListProperty<QObject> NativeScope::data()
{
    return QQmlListProperty<QObject>(this, nullptr, &appendData, &countData, &atData, &clearData);
}

void NativeScope::appendData(QQmlListProperty<QObject> *list, QObject *obj)
{
    auto *scope = qobject_cast<NativeScope *>(list->object);
    if (!scope || !obj) {
        return;
    }
    if (!obj->parent()) {
        obj->setParent(scope);
    }
    scope->m_data.append(obj);
}

qsizetype NativeScope::countData(QQmlListProperty<QObject> *list)
{
    auto *scope = qobject_cast<NativeScope *>(list->object);
    return scope ? scope->m_data.size() : 0;
}

QObject *NativeScope::atData(QQmlListProperty<QObject> *list, qsizetype index)
{
    auto *scope = qobject_cast<NativeScope *>(list->object);
    return (scope && index >= 0 && index < scope->m_data.size()) ? scope->m_data.at(index) : nullptr;
}

void NativeScope::clearData(QQmlListProperty<QObject> *list)
{
    auto *scope = qobject_cast<NativeScope *>(list->object);
    if (scope) {
        scope->m_data.clear();
    }
}
