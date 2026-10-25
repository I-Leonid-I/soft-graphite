#include <QCoreApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QTemporaryDir>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
int main(int argc,char **argv) {
    QTemporaryDir dir;
    qputenv("XDG_CONFIG_HOME",dir.path().toUtf8());
    QCoreApplication app(argc,argv);
    QQmlEngine first,second;
    QByteArray qml="import \"file:"+QDir::homePath().toUtf8()+"/.local/share/plasma/plasmoids/org.leonid.softgraphite.dock/contents/ui/launchersync\"\nLauncherLink {}";
    const auto base=QUrl::fromLocalFile(QDir::currentPath()+"/backend-test.qml");
    QQmlComponent a(&first),b(&second);a.setData(qml,base);b.setData(qml,base);
    auto one=a.create(),two=b.create();
    if(!one||!two){qCritical()<<a.errors()<<b.errors();return 1;}
    auto publish=[](QObject *link,const QStringList &pins){return QMetaObject::invokeMethod(link,"publish",Q_ARG(QStringList,pins));};
    auto check=[&](const QStringList &pins){return one->property("launchers").toStringList()==pins&&two->property("launchers").toStringList()==pins;};
    QStringList pins{"applications:org.kde.dolphin.desktop","applications:org.kde.konsole.desktop"};
    if(!publish(one,pins)||!check(pins))return 2;
    pins.append("applications:firefox.desktop");if(!publish(two,pins)||!check(pins))return 3;
    pins.move(2,0);if(!publish(one,pins)||!check(pins))return 4;
    pins.removeFirst();if(!publish(two,pins)||!check(pins))return 5;
    if(!publish(one,{})||!check({}))return 6;
    // A newly created dock must inherit intentional emptiness, not its defaults.
    auto third=b.create();QStringList restored;
    if(!QMetaObject::invokeMethod(third,"initialize",Q_RETURN_ARG(QStringList,restored),Q_ARG(QStringList,pins))||!restored.isEmpty())return 7;
    if(!publish(two,pins)||!check(pins))return 8;
    const auto before=QFileInfo(dir.path()+"/softgraphite-dockrc").lastModified();
    publish(one,pins);const auto after=QFileInfo(dir.path()+"/softgraphite-dockrc").lastModified();
    if(before!=after)return 9;
    qInfo()<<"PASS: two independent QML engines, pin/unpin/order/empty-list/new-dock initialization, idempotent updates.";
    delete third;delete two;delete one;
}
