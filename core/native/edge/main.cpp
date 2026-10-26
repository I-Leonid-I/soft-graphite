#include <QGuiApplication>
#include <QScreen>
#include <QSaveFile>
#include <QFile>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonDocument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QTimer>
#include <QRasterWindow>
#include <QPainter>
#include <QSurfaceFormat>
#include <LayerShellQt/Window>
class SnapPreview:public QRasterWindow {
protected:
 void paintEvent(QPaintEvent*) override {QPainter p(this);p.setCompositionMode(QPainter::CompositionMode_Source);p.fillRect(QRect(QPoint(),size()),Qt::transparent);p.setCompositionMode(QPainter::CompositionMode_SourceOver);p.setRenderHint(QPainter::Antialiasing);p.setPen(QPen(QColor(184,198,214,150),1.4));p.setBrush(QColor(110,125,145,46));p.drawRoundedRect(QRectF(5,5,width()-10,height()-10),14,14);}
public:
 SnapPreview(){setFlags(Qt::Tool|Qt::FramelessWindowHint|Qt::WindowTransparentForInput|Qt::WindowDoesNotAcceptFocus);QSurfaceFormat f=format();f.setAlphaBufferSize(8);setFormat(f);setTitle("Soft Graphite snap preview");auto l=LayerShellQt::Window::get(this);l->setScope("soft-graphite-snap-preview");l->setLayer(LayerShellQt::Window::LayerOverlay);l->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);l->setExclusiveZone(-1);l->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)|LayerShellQt::Window::AnchorLeft);}
 void present(QScreen*screen,QRect rect){auto l=LayerShellQt::Window::get(this);if(this->screen()!=screen){hide();setScreen(screen);l->setScreen(screen);}l->setMargins(QMargins(rect.x()-screen->geometry().x(),rect.y()-screen->geometry().y(),0,0));l->setDesiredSize(rect.size());resize(rect.size());show();requestUpdate();}
};
class Bridge:public QObject {
 Q_OBJECT
 Q_CLASSINFO("D-Bus Interface","org.leonid.SoftGraphite")
 Q_PROPERTY(QString uiState READ UiState)
 struct ScreenState {QString target,appName;int frontPid=0;bool modeKnown=false,full=false,capture=false;QRect bounds,left,right,dock;};
 QString state,ui,base,persisted;
 QJsonArray restoreWindows;
 QMap<QString,ScreenState> screens;
 QMap<QString,bool> flags;
 QMap<QString,QTimer*> timers;
 QTimer saveTimer;
 QTimer panelTimer;
 SnapPreview preview;QString previewOutput,previewKind;QRect previewRect;
 QPoint pointer;
 quint64 pointerCalls=0,publishes=0,writes=0;
 QString flagKey(const QString&n,const QString&r){return n+"/"+r;}
 void publish(){
  QJsonArray a;for(auto it=screens.cbegin();it!=screens.cend();++it){const auto&s=it.value();a.append(QJsonObject{{"name",it.key()},{"appName",s.appName},{"pid",s.frontPid},{"x",s.bounds.x()},{"y",s.bounds.y()},{"width",s.bounds.width()},{"height",s.bounds.height()},{"full",s.full},{"capture",s.capture},{"left",flags.value(flagKey(it.key(),"left"))},{"right",flags.value(flagKey(it.key(),"right"))},{"bottom",flags.value(flagKey(it.key(),"bottom"))}});}
  const QString next=QJsonDocument(a).toJson(QJsonDocument::Compact);if(next==ui)return;ui=next;++publishes;
  auto m=QDBusMessage::createSignal("/SoftGraphite","org.freedesktop.DBus.Properties","PropertiesChanged");m<<QString("org.leonid.SoftGraphite")<<QVariantMap{{"uiState",ui}}<<QStringList{};QDBusConnection::sessionBus().send(m);
 }
 void panelMode(QString){panelTimer.start();}
 void applyPanelMode(){
  // The controller alone owns fullscreen hiding. Plasma's DodgeWindows would
  // independently hide the dock behind a large but still windowed application.
  // Deferred and write-only-on-change: setting hiding while plasmashell starts
  // or rebuilds panels after a screen hotplug crashes it (KConfigGroup::parent).
  QString code="[46,49,23,67,70,65].forEach(id=>{var p=panelById(id);if(p&&p.hiding!='windowsgobelow')p.hiding='windowsgobelow';});";
  auto m=QDBusMessage::createMethodCall("org.kde.plasmashell","/PlasmaShell","org.kde.PlasmaShell","evaluateScript");m<<code;QDBusConnection::sessionBus().asyncCall(m);
 }
 void hold(QString n,QString role,bool trigger,bool inside){
  const auto k=flagKey(n,role);
  if(trigger){if(!flags.value(k)){flags[k]=true;}if(timers.contains(k))timers[k]->stop();}
  else if(flags.value(k)&&inside){if(timers.contains(k))timers[k]->stop();}
  else if(flags.value(k)){
   if(!timers.contains(k)){auto t=new QTimer(this);t->setSingleShot(true);t->setInterval(role=="bottom"?500:350);timers[k]=t;connect(t,&QTimer::timeout,this,[this,k]{flags[k]=false;publish();});}
   if(!timers[k]->isActive())timers[k]->start();
  }
 }
 QJsonObject rect(QRect r)const{return {{"x",r.x()},{"y",r.y()},{"width",r.width()},{"height",r.height()}};}
 QRect fromRect(QJsonObject o){return {o["x"].toInt(),o["y"].toInt(),o["width"].toInt(),o["height"].toInt()};}
 QJsonObject panelState()const{QJsonObject p;for(auto it=screens.cbegin();it!=screens.cend();++it)p[it.key()]=QJsonObject{{"left",rect(it->left)},{"right",rect(it->right)},{"dock",rect(it->dock)}};return p;}
 void scheduleSave(){saveTimer.start();}
 void save(){auto bytes=QJsonDocument(QJsonObject{{"windows",restoreWindows},{"panels",panelState()}}).toJson(QJsonDocument::Compact);if(bytes==persisted.toUtf8())return;QSaveFile f(base+"/session-state.json");if(f.open(QIODevice::WriteOnly)){f.write(bytes);if(f.commit()){persisted=QString::fromUtf8(bytes);++writes;}}}
 void refreshScreens(){for(auto s:qGuiApp->screens())screens[s->name()].bounds=s->geometry();QStringList names;for(auto s:qGuiApp->screens())names<<s->name();for(auto n:screens.keys())if(!names.contains(n))screens.remove(n);}
public:
 Bridge(QString path):base(path){
  refreshScreens();QFile f(base+"/session-state.json");if(f.open(QIODevice::ReadOnly)){state=QString::fromUtf8(f.readAll());auto o=QJsonDocument::fromJson(state.toUtf8()).object();restoreWindows=o["windows"].toArray();auto p=o["panels"].toObject();for(auto n:screens.keys()){screens[n].left=fromRect(p[n].toObject()["left"].toObject());screens[n].right=fromRect(p[n].toObject()["right"].toObject());screens[n].dock=fromRect(p[n].toObject()["dock"].toObject());}}
  saveTimer.setSingleShot(true);saveTimer.setInterval(500);connect(&saveTimer,&QTimer::timeout,this,&Bridge::save);
  panelTimer.setSingleShot(true);panelTimer.setInterval(3000);connect(&panelTimer,&QTimer::timeout,this,&Bridge::applyPanelMode);
  auto w=new QDBusServiceWatcher("org.kde.plasmashell",QDBusConnection::sessionBus(),QDBusServiceWatcher::WatchForRegistration,this);connect(w,&QDBusServiceWatcher::serviceRegistered,this,[this]{for(auto it=screens.begin();it!=screens.end();++it)panelMode(it.key());});
  connect(qGuiApp,&QGuiApplication::screenAdded,this,[this]{refreshScreens();publish();});connect(qGuiApp,&QGuiApplication::screenRemoved,this,[this]{refreshScreens();publish();});
  publish();
 }
 QString UiState()const{return ui;}
public slots:
 QString Update(QString data){
  auto o=QJsonDocument::fromJson(data.toUtf8()).object();if(!o.contains("screens"))return PointerConfig();state=data;refreshScreens();
  for(auto v:o["screens"].toArray()){auto r=v.toObject();const QString n=r["name"].toString();auto&s=screens[n];s.target=r["fullscreen"].toString();s.appName=r["appName"].toString();s.frontPid=r["pid"].toInt();const bool capture=r["capture"].toBool();const bool full=!s.target.isEmpty()||capture;if(!s.modeKnown||s.full!=full||s.capture!=capture){if(!s.modeKnown)panelMode(n);s.modeKnown=true;s.full=full;s.capture=capture;if(capture)preview.hide();for(auto role:{"left","right","bottom"}){auto k=flagKey(n,role);flags[k]=false;if(timers.contains(k))timers[k]->stop();}}}
  QJsonArray a;for(auto v:o["windows"].toArray()){auto w=v.toObject();if(w.contains("restore"))a.append(QJsonObject{{"id",w["id"]},{"restore",w["restore"]},{"snapRestore",w["snapRestore"]}});}if(a!=restoreWindows){restoreWindows=a;scheduleSave();}
  publish();return PointerConfig();
 }
 void Geometry(QString n,QString role,int x,int y,int w,int h){
  if(!screens.contains(n)||w<=0||h<=0)return;auto&s=screens[n];QRect r(x,y,w,h);QRect*target=role=="dock"?&s.dock:role=="left"?&s.left:role=="right"?&s.right:nullptr;if(!target||*target==r)return;*target=r;scheduleSave();
 }
 void Preview(QString output,QString kind,int x,int y,int width,int height){
  previewOutput=output;previewKind=kind;previewRect=QRect(x,y,width,height);
  if(kind.isEmpty()||width<=0||height<=0||screens.value(output).capture){preview.hide();return;}
  for(auto screen:qGuiApp->screens())if(screen->name()==output){preview.present(screen,previewRect);return;}
 }
 QString PreviewState()const{return QJsonDocument(QJsonObject{{"output",previewOutput},{"kind",previewKind},{"visible",preview.isVisible()},{"rect",rect(previewRect)}}).toJson(QJsonDocument::Compact);}
 QString PointerConfig()const{QJsonArray a;for(auto it=screens.cbegin();it!=screens.cend();++it){auto o=rect(it->bounds);o["name"]=it.key();o["full"]=it->full&&!it->capture;o["capture"]=it->capture;o["target"]=it->target;o["left"]=rect(it->left);o["right"]=rect(it->right);o["dock"]=rect(it->dock);a.append(o);}return QJsonDocument(a).toJson(QJsonDocument::Compact);}
 QString State()const{return state;}
 QString Stats()const{return QJsonDocument(QJsonObject{{"pointerCalls",double(pointerCalls)},{"publishes",double(publishes)},{"writes",double(writes)}}).toJson(QJsonDocument::Compact);}
 QString PointerState()const{return QString("%1,%2").arg(pointer.x()).arg(pointer.y());}
 void ObservePointer(int x,int y){pointer={x,y};}
 void Pointer(int x,int y){
  ++pointerCalls;pointer={x,y};for(auto it=screens.cbegin();it!=screens.cend();++it){auto&s=it.value();bool on=s.full&&!s.capture&&s.bounds.contains(pointer);int lx=x-s.bounds.x(),ly=y-s.bounds.y();
   hold(it.key(),"left",on&&lx<16&&ly<12,on&&s.left.adjusted(0,0,0,16).contains(pointer));
   hold(it.key(),"right",on&&lx>=s.bounds.width()-32&&ly<24,on&&s.right.adjusted(0,0,0,16).contains(pointer));
   const auto dock=s.dock.adjusted(10,0,-10,0);hold(it.key(),"bottom",on&&ly>=s.bounds.height()-12&&x>=dock.left()&&x<=dock.right(),on&&s.dock.contains(pointer));
  }publish();
 }
 void Action(QString output,QString action){
  if(action!="restore"&&action!="minimize"&&action!="close")return;if(screens.value(output).capture)return;QString id=screens.value(output).target;if(id.isEmpty())return;
  QString literal=QString::fromUtf8(QJsonDocument(QJsonArray{id,action}).toJson(QJsonDocument::Compact));
  QString code="var a="+literal+";var w=workspace.windowList().find(w=>String(w.internalId)===a[0]);if(w){if(a[1]==='close')w.closeWindow();else if(a[1]==='minimize')w.minimized=true;else{if(w.fullScreen)w.fullScreen=false;else w.setMaximize(false,false);workspace.activeWindow=w;}}";
  QFile f(base+"/action.js");if(!f.open(QIODevice::WriteOnly))return;f.write(code.toUtf8());f.close();QDBusInterface scripts("org.kde.KWin","/Scripting","org.kde.kwin.Scripting");scripts.call("unloadScript","soft-graphite-action");QDBusReply<int> r=scripts.call("loadScript",f.fileName(),"soft-graphite-action");if(r.isValid()&&r.value()>=0)scripts.call("start");
 }
 void Restore(QString output){Action(output,"restore");}
};
int main(int argc,char**argv){QGuiApplication app(argc,argv);app.setApplicationName("soft-graphite-edge");app.setQuitOnLastWindowClosed(false);if(argc<2)return 2;Bridge b(QString::fromLocal8Bit(argv[1]));auto bus=QDBusConnection::sessionBus();if(!bus.registerService("org.leonid.SoftGraphite"))return 1;bus.registerObject("/SoftGraphite",&b,QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllProperties);return app.exec();}
#include "main.moc"
