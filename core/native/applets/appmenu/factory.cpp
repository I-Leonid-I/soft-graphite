// SPDX-License-Identifier: LGPL-2.0-or-later
#include <KPluginFactory>
#include <KPluginMetaData>
#include <Plasma/Applet>
static QObject *createNativeMenu(QWidget *,QObject *parent,const KPluginMetaData &data,const QVariantList &args) {
 auto loaded=KPluginFactory::loadFactory(KPluginMetaData(QStringLiteral("plasma/applets/org.kde.plasma.appmenu")));
 if(!loaded.plugin)return nullptr;
 const auto old=loaded.plugin->metaData();
 loaded.plugin->setMetaData(data);
 auto *applet=loaded.plugin->create<Plasma::Applet>(parent,args);
 loaded.plugin->setMetaData(old);
 return applet;
}
K_PLUGIN_FACTORY_WITH_JSON(SoftGraphiteMenuFactory,"metadata.json",registerPlugin<Plasma::Applet>(createNativeMenu);)
#include "factory.moc"
