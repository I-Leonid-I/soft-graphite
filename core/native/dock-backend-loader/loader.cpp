#include <QQmlExtensionPlugin>
#include <QLibrary>
#include <QtQml>
class GraphiteBackendLoader : public QQmlExtensionPlugin {
 Q_OBJECT
 Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
 void registerTypes(const char *uri) override {
  static QLibrary library(QStringLiteral("/usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so"));
  library.setLoadHints(QLibrary::PreventUnloadHint);
  if (!library.load()) qFatal("Cannot load native task manager: %s",qPrintable(library.errorString()));
  qmlRegisterModule(uri,1,0);
 }
};
#include "loader.moc"
