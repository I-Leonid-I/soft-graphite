#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QCoreApplication>
#include <QDir>
class GraphitePluginPath : public QQmlExtensionPlugin {
 Q_OBJECT
 Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
 void registerTypes(const char* uri) override { qmlRegisterModule(uri,1,0); QCoreApplication::addLibraryPath(QDir::homePath()+"/.local/lib/qt6/plugins"); }
};
#include "path.moc"
