// SPDX-License-Identifier: LGPL-2.0-or-later
#include <KPluginFactory>
#include <KPluginMetaData>
#include <Plasma/Applet>
static QObject *createNativeTray(QWidget *,QObject *parent,const KPluginMetaData &data,const QVariantList &args) {
 auto loaded=KPluginFactory::loadFactory(KPluginMetaData(QStringLiteral("plasma/applets/org.kde.plasma.systemtray")));
 if(!loaded.plugin)return nullptr;
 const auto old=loaded.plugin->metaData();
 loaded.plugin->setMetaData(data);
 auto *applet=loaded.plugin->create<Plasma::Applet>(parent,args);
 loaded.plugin->setMetaData(old);
 return applet;
}
K_PLUGIN_FACTORY_WITH_JSON(SoftGraphiteTrayFactory,"metadata.json",registerPlugin<Plasma::Applet>(createNativeTray);)
#include "factory.moc"
