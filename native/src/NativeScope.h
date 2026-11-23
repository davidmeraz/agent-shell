#pragma once

#include <QList>
#include <QObject>
#include <QQmlListProperty>
#include <QtQml/qqmlregistration.h>

class NativeScope : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_CLASSINFO("DefaultProperty", "data")
    Q_PROPERTY(QQmlListProperty<QObject> data READ data)

public:
    explicit NativeScope(QObject *parent = nullptr);
    ~NativeScope() override;

    QQmlListProperty<QObject> data();

private:
    static void appendData(QQmlListProperty<QObject> *list, QObject *obj);
    static qsizetype countData(QQmlListProperty<QObject> *list);
    static QObject *atData(QQmlListProperty<QObject> *list, qsizetype index);
    static void clearData(QQmlListProperty<QObject> *list);

    QList<QObject *> m_data;
};
