// SPDX-License-Identifier: GPL-2.0-or-later
#include <QCoreApplication>
#include <QtDBus>
#include <QSocketNotifier>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include <xcb/xcb.h>
#include <unistd.h>
#include <fcntl.h>
struct Layout { int id; QVariantMap properties; QList<QDBusVariant> children; };
Q_DECLARE_METATYPE(Layout)
QDBusArgument &operator<<(QDBusArgument &a,const Layout &v){a.beginStructure();a<<v.id<<v.properties<<v.children;a.endStructure();return a;}
const QDBusArgument &operator>>(const QDBusArgument &a,Layout &v){a.beginStructure();a>>v.id>>v.properties>>v.children;a.endStructure();return a;}
struct Properties { int id; QVariantMap properties; };
Q_DECLARE_METATYPE(Properties)
using PropertyList=QList<Properties>;
Q_DECLARE_METATYPE(PropertyList)
QDBusArgument &operator<<(QDBusArgument &a,const Properties &v){a.beginStructure();a<<v.id<<v.properties;a.endStructure();return a;}
const QDBusArgument &operator>>(const QDBusArgument &a,Properties &v){a.beginStructure();a>>v.id>>v.properties;a.endStructure();return a;}
class Menu : public QDBusVirtualObject {
 Q_OBJECT
 QHash<int,QJsonObject> nodes;
 QJsonArray tree;
 QByteArray input;
 uint revision=0,xid=0;
 bool available=false;
 QDBusConnection bus=QDBusConnection::sessionBus();
 QString path="/SoftGraphite/Menu";
 void send(QJsonObject value){auto bytes=QJsonDocument(value).toJson(QJsonDocument::Compact)+'\n';::write(STDOUT_FILENO,bytes.constData(),bytes.size());}
 void index(const QJsonArray &items){for(const auto &v:items){auto o=v.toObject();nodes[o["id"].toInt()]=o;index(o["children"].toArray());}}
 QVariantMap props(int id,const QStringList &names={})const {
  auto o=nodes.value(id);QVariantMap result;
  if(id==0){result["children-display"]="submenu";}
  else {result["label"]=o["label"].toString();result["enabled"]=o["enabled"].toBool(true);result["visible"]=o["visible"].toBool(true);
   if(o["type"]=="separator")result["type"]="separator";
   if(o.contains("children"))result["children-display"]="submenu";
   if(!o["accelerator"].toString().isEmpty()){
    QStringList keys=o["accelerator"].toString().split('+');
    for(auto &key:keys){if(key=="CmdOrCtrl"||key=="CommandOrControl"||key=="Ctrl")key="Control";else if(key=="Cmd"||key=="Command"||key=="Meta")key="Super";else if(key=="Enter")key="Return";}
    result["shortcut"]=QVariant::fromValue(QList<QStringList>{keys});
   }
   if(o["type"]=="checkbox"||o["type"]=="radio"){result["toggle-type"]=o["type"]=="radio"?"radio":"checkmark";result["toggle-state"]=o["checked"].toBool()?1:0;}
  }
  if(!names.isEmpty())for(auto it=result.begin();it!=result.end();)if(!names.contains(it.key()))it=result.erase(it);else ++it;
  return result;
 }
 Layout layout(int id,int depth,const QStringList &names)const {
  Layout result{id,props(id,names),{}};auto children=id==0?tree:nodes.value(id)["children"].toArray();
  if(depth!=0)for(const auto &v:children)result.children<<QDBusVariant(QVariant::fromValue(layout(v.toObject()["id"].toInt(),depth<0?-1:depth-1,names)));
  return result;
 }
 void xProperties(bool enable){
  auto *c=xcb_connect(nullptr,nullptr);if(xcb_connection_has_error(c)){xcb_disconnect(c);return;}
  auto atom=[&](const QByteArray &name){auto *r=xcb_intern_atom_reply(c,xcb_intern_atom(c,0,name.size(),name.constData()),nullptr);auto a=r?r->atom:XCB_ATOM_NONE;free(r);return a;};
  for(const auto &v:QList<QPair<QByteArray,QByteArray>>{{"_KDE_NET_WM_APPMENU_SERVICE_NAME",bus.baseService().toUtf8()},{"_KDE_NET_WM_APPMENU_OBJECT_PATH",path.toUtf8()}}){
   if(enable)xcb_change_property(c,XCB_PROP_MODE_REPLACE,xid,atom(v.first),atom("UTF8_STRING"),8,v.second.size(),v.second.constData());
   else xcb_delete_property(c,xid,atom(v.first));
  }xcb_flush(c);xcb_disconnect(c);
 }
 void registerMenu(){
  if(!xid||!bus.interface()->isServiceRegistered("com.canonical.AppMenu.Registrar"))return;
  auto msg=QDBusMessage::createMethodCall("com.canonical.AppMenu.Registrar","/com/canonical/AppMenu/Registrar","com.canonical.AppMenu.Registrar","RegisterWindow");msg<<xid<<QVariant::fromValue(QDBusObjectPath(path));bus.asyncCall(msg);
  xProperties(true);available=true;send({{"ready",true}});
 }
public:
 Menu(uint id):xid(id){
  qDBusRegisterMetaType<QList<QStringList>>();qDBusRegisterMetaType<Layout>();qDBusRegisterMetaType<Properties>();qDBusRegisterMetaType<PropertyList>();
  bus.registerVirtualObject(path,this);
  auto *watch=new QDBusServiceWatcher("com.canonical.AppMenu.Registrar",bus,QDBusServiceWatcher::WatchForOwnerChange,this);
  connect(watch,&QDBusServiceWatcher::serviceOwnerChanged,this,[this](const QString&,const QString&,const QString &owner){if(owner.isEmpty()){available=false;xProperties(false);send({{"ready",false}});}else registerMenu();});
  fcntl(STDIN_FILENO,F_SETFL,fcntl(STDIN_FILENO,F_GETFL)|O_NONBLOCK);
  auto *read=new QSocketNotifier(STDIN_FILENO,QSocketNotifier::Read,this);
  connect(read,&QSocketNotifier::activated,this,[this]{char data[16384];ssize_t n;while((n=::read(STDIN_FILENO,data,sizeof(data)))>0)input.append(data,n);if(n==0){QCoreApplication::quit();return;}
   int end;while((end=input.indexOf('\n'))>=0){auto line=input.left(end);input.remove(0,end+1);auto doc=QJsonDocument::fromJson(line);if(!doc.isObject())continue;auto next=doc.object()["items"].toArray();if(next==tree)continue;tree=next;nodes.clear();index(tree);++revision;auto msg=QDBusMessage::createSignal(path,"com.canonical.dbusmenu","LayoutUpdated");msg<<revision<<0;bus.send(msg);if(!available)registerMenu();}
  });
 }
 ~Menu(){if(available)xProperties(false);}
 QString introspect(const QString&)const override{return R"XML(<interface name="com.canonical.dbusmenu">
 <property name="Version" type="u" access="read"/><property name="TextDirection" type="s" access="read"/><property name="Status" type="s" access="read"/><property name="IconThemePath" type="as" access="read"/>
 <method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
 <method name="GetGroupProperties"><arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
 <method name="GetProperty"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
 <method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
 <method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
 <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
 <method name="AboutToShowGroup"><arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/></method>
 <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
 </interface>)XML";}
 bool handleMessage(const QDBusMessage &m,const QDBusConnection &connection) override {
  if(m.interface()=="org.freedesktop.DBus.Introspectable"&&m.member()=="Introspect"){connection.send(m.createReply(QString("<node>")+introspect(m.path())+"</node>"));return true;}
  if(m.interface()=="org.freedesktop.DBus.Peer"&&m.member()=="Ping"){connection.send(m.createReply());return true;}
  auto args=m.arguments();QList<QVariant> reply;
  const QMap<QString,int> arity{{"GetLayout",3},{"GetGroupProperties",2},{"GetProperty",2},{"Event",4},{"EventGroup",1},{"AboutToShow",1},{"AboutToShowGroup",1}};
  if(m.interface()=="com.canonical.dbusmenu"&&arity.contains(m.member())&&args.size()!=arity.value(m.member())){connection.send(m.createErrorReply(QDBusError::InvalidArgs,"Invalid menu arguments"));return true;}
  auto event=[this](int id,const QString &type){if(type=="clicked"&&nodes.contains(id))send({{"click",id}});};
  if(m.interface()=="org.freedesktop.DBus.Properties"){
   QVariantMap all{{"Version",3u},{"TextDirection","ltr"},{"Status","normal"},{"IconThemePath",QStringList{}}};
   if(m.member()=="GetAll")reply<<all;else if(m.member()=="Get")reply<<QVariant::fromValue(QDBusVariant(all.value(args.value(1).toString())));else return false;
  } else if(m.interface()=="com.canonical.dbusmenu") {
   if(m.member()=="GetLayout")reply<<revision<<QVariant::fromValue(layout(args[0].toInt(),args[1].toInt(),qdbus_cast<QStringList>(args[2])));
   else if(m.member()=="GetGroupProperties"){auto ids=qdbus_cast<QList<int>>(args[0]);if(ids.isEmpty())ids=nodes.keys();PropertyList values;auto names=qdbus_cast<QStringList>(args[1]);for(int id:ids)values<<Properties{id,props(id,names)};reply<<QVariant::fromValue(values);}
   else if(m.member()=="GetProperty")reply<<QVariant::fromValue(QDBusVariant(props(args[0].toInt()).value(args[1].toString())));
   else if(m.member()=="AboutToShow"){send({{"refresh",args[0].toInt()}});reply<<false;}
   else if(m.member()=="AboutToShowGroup"){send({{"refresh",0}});reply<<QVariant::fromValue(QList<int>{})<<QVariant::fromValue(QList<int>{});}
   else if(m.member()=="Event")event(args[0].toInt(),args[1].toString());
   else if(m.member()=="EventGroup"){const auto a=args[0].value<QDBusArgument>();a.beginArray();while(!a.atEnd()){int id;QString type;QDBusVariant data;uint time;a.beginStructure();a>>id>>type>>data>>time;a.endStructure();event(id,type);}a.endArray();reply<<QVariant::fromValue(QList<int>{});}
   else return false;
  }else return false;
  connection.send(m.createReply(reply));return true;
 }
};
int main(int argc,char **argv){QCoreApplication app(argc,argv);if(argc!=2)return 2;Menu menu(QString::fromLocal8Bit(argv[1]).toUInt());return app.exec();}
#include "menu-bridge.moc"
