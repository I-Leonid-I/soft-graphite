#include <QQmlExtensionPlugin>
#include <KSharedConfig>
#include <KConfigGroup>
#include <KConfigWatcher>
#include <QQmlEngine>
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QQuickItem>
#include <QQuickWindow>
#include <QGuiApplication>
#include <QApplication>
#include <QMenu>
#include <QStyle>
#include <QAbstractItemModel>
#include <QAction>
#include <QElapsedTimer>
#include <memory>
#include <QScreen>
#include <QCursor>
#include <QPointer>
#include <QPropertyAnimation>
#include <KWindowEffects>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusServiceWatcher>
#include <LayerShellQt/Window>
class PanelController : public QObject {
 Q_OBJECT
 Q_CLASSINFO("D-Bus Interface","org.leonid.GraphitePanel")
 Q_PROPERTY(qreal hiddenProgress READ hiddenProgress WRITE setHiddenProgress)
 Q_PROPERTY(qreal contentOpacity READ contentOpacity WRITE setContentOpacity)
 QPointer<QQuickWindow> win;
 QString role,lastGeometry;
 bool full=false,reveal=false,suppressed=false,applying=false,initialized=false;
 QPropertyAnimation motion;
 qreal contentAlpha=1;
 qreal contentOpacity()const{return contentAlpha;}
 void setContentOpacity(qreal a){contentAlpha=a;if(win)win->contentItem()->setOpacity(a);}
 qreal progress=0;
 QTimer settle;
 QPointer<QQuickItem> panelScene;
 bool menuMorph=false,finishingMorph=false,adjustingScene=false,originalClip=false;
 qreal visualMenuWidth=0,menuChrome=0;
 void keepSceneWidth(){
  if(!menuMorph||!panelScene||!win||adjustingScene)return;
  adjustingScene=true;
  const qreal width=menuChrome+visualMenuWidth;
  panelScene->setWidth(width);
  if(finishingMorph&&qAbs(win->width()-width)<1.5){
   menuMorph=false;finishingMorph=false;panelScene->setClip(originalClip);
   panelScene->setWidth(win->width());
  }
  adjustingScene=false;
 }
 static bool isToolTip(QWindow *w){return w && (w->type()==Qt::ToolTip || w->inherits("ToolTipDialog"));}
 bool popupOpen()const{for(auto w:QGuiApplication::allWindows())if(w!=win&&w->isVisible())for(auto p=w->transientParent();p;p=p->transientParent())if(p==win)return true;return false;}
 qreal hiddenProgress()const{return progress;}
 void setHiddenProgress(qreal value){
  const bool becameHidden=progress<1.0&&value>=1.0;
  progress=value;if(!win)return;
  auto content=win->contentItem();const qreal offset=(role=="dock"?1:-1)*win->height()*progress;
  content->setY(offset);content->setOpacity(contentAlpha);
  // Translate the panel artwork and its blur together; keep the native surface fixed.
  // Task destinations therefore remain attached to a live Wayland surface.
  QRegion mask;
  for(auto root:content->childItems())if(root->property("panelMask").isValid()){
   mask=qvariant_cast<QRegion>(root->property("panelMask"));
   mask.translate(root->property("floatingTranslucentItemOffset").toPoint());break;
  }
  if(mask.isEmpty())mask=QRegion(QRect(10,10,win->width()-20,win->height()-20));
  QRect input(0,0,win->width(),win->height());
  if(role=="dock")input.setTop(mask.boundingRect().top());else input.setBottom(mask.boundingRect().bottom());
  const QRegion bounds(QRect(0,0,win->width(),win->height()));
  mask=mask.translated(0,qRound(offset)).intersected(bounds);
  // Very thin blur regions cannot be downsampled by KWin on this GPU.
  const QRect blurBounds=mask.boundingRect();
  KWindowEffects::enableBlurBehind(win,blurBounds.width()>=16&&blurBounds.height()>=16,mask);
  const QRegion inputMask=QRegion(input).translated(0,qRound(offset)).intersected(bounds);
  win->setMask(inputMask.isEmpty()?QRegion(QRect(-2,-2,1,1)):inputMask);
  if(becameHidden)Q_EMIT fullyHidden();
 }
 void apply(){
  if(!win||applying)return;applying=true;
  auto layer=LayerShellQt::Window::get(win);
  const bool visible=!suppressed&&(!full||reveal||popupOpen());
  if(!win->isVisible())win->setVisible(true);
  if(suppressed){motion.stop();setHiddenProgress(1);if(layer)layer->setLayer(LayerShellQt::Window::LayerBottom);}
  else {
   // Already be above the client before its fullscreen transaction starts.
   // Our controller owns visibility; native Top would drop under fullscreen
   // for the first frames while the state report crosses D-Bus.
   if(layer)layer->setLayer((visible||progress<1.0)
     ? LayerShellQt::Window::LayerOverlay:LayerShellQt::Window::LayerBottom);
   const qreal target=visible?0.0:1.0;
   if(!initialized){setHiddenProgress(target);if(!visible&&layer)layer->setLayer(LayerShellQt::Window::LayerBottom);}
   else if(motion.state()!=QAbstractAnimation::Running||motion.endValue().toReal()!=target){
    // A reversal may happen before the first frame changes progress. Stop the
    // old animation even if we are already at the new target, or it will later
    // move the panel offscreen despite full=false.
    motion.stop();
    if(progress!=target){
     motion.setStartValue(progress);motion.setEndValue(target);
     motion.setDuration(qMax(60,qRound((visible?180:320)*qAbs(progress-target))));
     motion.setEasingCurve(visible?QEasingCurve::OutCubic:QEasingCurve::InOutCubic);motion.start();
    }else {setHiddenProgress(target);if(!visible&&layer)layer->setLayer(LayerShellQt::Window::LayerBottom);}
   }
  }
  initialized=true;applying=false;
 }

 void geometry(){
  if(!win||!win->screen())return;
  auto g=win->geometry();const QString n=win->screen()->name();
  const QString id=QString("%1,%2,%3,%4,%5").arg(n).arg(g.x()).arg(g.y()).arg(g.width()).arg(g.height());if(id==lastGeometry)return;lastGeometry=id;
  auto m=QDBusMessage::createMethodCall("org.leonid.SoftGraphite","/SoftGraphite","org.leonid.SoftGraphite","Geometry");m<<n<<role<<g.x()<<g.y()<<g.width()<<g.height();QDBusConnection::sessionBus().asyncCall(m);
 }
 bool eventFilter(QObject*o,QEvent*e)override{
  if(auto w=qobject_cast<QWindow*>(o);w&&w!=win&&e->type()==QEvent::Show&&role=="left"&&win&&win->isVisible()&&w->type()==Qt::Popup){
   auto p=w->transientParent();
   // Qt can reset QMenu's transient parent to its hidden source menu during popup().
   // Attach only the top-level app menu; submenus retain their visible menu parent.
   if((!p||!p->isVisible())&&w->x()>=win->x()&&w->x()<win->x()+win->width()&&w->y()>=win->y()&&w->y()<win->y()+win->height()+32)w->setTransientParent(win);
  }
  // Plasma's Wayland tooltips use a normal Qt window with the tooltip protocol
  // role. Use the actual tooltip class and its placement margin, not coordinates.
  if((role=="right"||role=="dock")&&win&&e->type()==QEvent::Show)
   if(auto w=qobject_cast<QWindow*>(o);w&&w->inherits("ToolTipDialog")&&win->geometry().contains(QCursor::pos()))w->setProperty("margin",8);
  if(role=="right"&&win&&e->type()==QEvent::Show)if(auto w=qobject_cast<QWindow*>(o);w&&isToolTip(w)){
   const auto cursor=QCursor::pos();
   if(win->geometry().contains(cursor)){
    bool open=false;
    for(auto popup:QGuiApplication::allWindows())if(popup!=w&&popup!=win&&popup->isVisible()&&!isToolTip(popup))
     for(auto parent=popup->transientParent();parent;parent=parent->transientParent())if(parent==win){open=true;break;}
    if(open){w->hide();return true;}
   }
  }
  if(qobject_cast<QWindow*>(o)&&(e->type()==QEvent::Show||e->type()==QEvent::Hide||e->type()==QEvent::ParentChange)){settle.start();}
  return false;
 }
 void dump(QQuickItem*i,QJsonArray&a,int depth,bool visibleOnly=false){if(!i||depth>30||(visibleOnly&&!i->isVisible()))return;auto p=i->mapToScene(QPointF());QJsonObject o{{"class",i->metaObject()->className()},{"name",i->objectName()},{"x",p.x()},{"y",p.y()},{"width",i->width()},{"height",i->height()},{"visible",i->isVisible()},{"enabled",i->isEnabled()},{"opacity",i->opacity()},{"implicitWidth",i->implicitWidth()},{"implicitHeight",i->implicitHeight()},{"z",i->z()},{"depth",depth}};for(auto prop:{"itemId","text","mainText","subText","phase","blend","transitionCount","displayedPid","visualWidth","measuredWidth","source","contentHeight","topPadding","bottomPadding","spacing","graphiteNaturalHeight"})if(i->property(prop).isValid())o[prop]=QJsonValue::fromVariant(i->property(prop));a.append(o);for(auto c:i->childItems())dump(c,a,depth+1,visibleOnly);}
public:
 PanelController(QQuickWindow*w,QString r,QObject*p):QObject(p),win(w),role(r){
  motion.setTargetObject(this);motion.setPropertyName("hiddenProgress");
  connect(&motion,&QPropertyAnimation::finished,this,[this]{if(win&&full&&!reveal&&progress==1)if(auto l=LayerShellQt::Window::get(win))l->setLayer(LayerShellQt::Window::LayerBottom);settle.start();});
  if(auto layer=LayerShellQt::Window::get(win))connect(layer,&LayerShellQt::Window::layerChanged,this,[this]{if(!applying)settle.start();});
  settle.setSingleShot(true);settle.setInterval(0);connect(&settle,&QTimer::timeout,this,[this]{apply();geometry();});
  qGuiApp->installEventFilter(this);
  connect(w,&QWindow::xChanged,this,[this]{settle.start();});connect(w,&QWindow::yChanged,this,[this]{settle.start();});connect(w,&QWindow::widthChanged,this,[this]{keepSceneWidth();settle.start();Q_EMIT menuViewportChanged();});connect(w,&QWindow::heightChanged,this,[this]{settle.start();});connect(w,&QWindow::screenChanged,this,[this]{settle.start();});
  QString path=QString("/SoftGraphitePanel/%1/%2").arg(role).arg(w->screen()?w->screen()->name().replace('-','_'):QString::number(quintptr(w)));
  QDBusConnection::sessionBus().registerObject(path,this,QDBusConnection::ExportAllSlots);
  connect(w,&QObject::destroyed,this,[this,path]{QDBusConnection::sessionBus().unregisterObject(path);deleteLater();});
  auto watcher=new QDBusServiceWatcher("org.leonid.SoftGraphite",QDBusConnection::sessionBus(),QDBusServiceWatcher::WatchForRegistration,this);connect(watcher,&QDBusServiceWatcher::serviceRegistered,this,[this]{lastGeometry.clear();geometry();});
  geometry();
 }
 void beginMenuMorph(QQuickItem*item){
  if(role!="left"||!win||!item)return;
  if(!panelScene){for(auto child:win->contentItem()->childItems())if(child->property("panelMask").isValid()){panelScene=child;break;}
   if(panelScene)connect(panelScene,&QQuickItem::widthChanged,this,[this]{keepSceneWidth();});
  }
  if(!panelScene)return;
  if(!menuMorph){menuChrome=win->width()-item->width();visualMenuWidth=item->width();originalClip=panelScene->clip();}
  menuMorph=true;finishingMorph=false;panelScene->setClip(true);keepSceneWidth();
 }
 void setMenuWidth(qreal width){if(!menuMorph)return;visualMenuWidth=width;keepSceneWidth();settle.start();}
 void finishMenuMorph(qreal width){if(!menuMorph)return;visualMenuWidth=width;finishingMorph=true;keepSceneWidth();settle.start();}
 bool contentIsHidden()const{return progress>=1.0;}
 bool menuSurfaceReady(qreal reserve)const{return !menuMorph || (win&&win->width()+1>=menuChrome+reserve);}
 Q_SIGNAL void menuViewportChanged();
 Q_SIGNAL void fullyHidden();
 void setContentAlpha(qreal value){setContentOpacity(qBound(0.0,value,1.0));}
 void configure(bool f,bool r,bool s){full=f;reveal=r;suppressed=s;apply();geometry();}
public slots:
#ifdef GRAPHITE_PANEL_QA
 // Explicit, bounded capture of this panel only; never runs during normal use.
 void CaptureFrames(QString directory){
  if(!win||role!="left")return;QDir().mkpath(directory);
  struct Frames { QVector<QImage> images;QJsonArray stats;QElapsedTimer clock; };
  auto frames=std::make_shared<Frames>();frames->clock.start();auto timer=new QTimer(this);
  connect(timer,&QTimer::timeout,this,[this,directory,frames,timer]{
   if(!win){timer->deleteLater();return;}
   frames->stats.append(QJsonObject{{"ms",frames->clock.elapsed()},{"width",win->width()},{"alpha",contentAlpha}});
   frames->images.append(win->grabWindow());
   if(frames->images.size()>=32){timer->stop();for(int n=0;n<frames->images.size();++n)frames->images[n].save(directory+QString("/%1.png").arg(n,2,10,QChar('0')));
    QFile f(directory+"/frames.json");if(f.open(QIODevice::WriteOnly))f.write(QJsonDocument(frames->stats).toJson());timer->deleteLater();}
  });timer->start(16);
 }
#endif
 QString State(){return QJsonDocument(QJsonObject{{"visualWidth",panelScene?panelScene->width():win?win->width():0},{"menuMorph",menuMorph},{"role",role},{"full",full},{"suppressed",suppressed},{"reveal",reveal},{"visible",win&&win->isVisible()&&progress<0.99},{"mapped",win&&win->isVisible()},{"opacity",win?win->contentItem()->opacity():0},{"hiddenProgress",progress},{"offset",win?win->contentItem()->y():0},{"layer",win?int(LayerShellQt::Window::get(win)->layer()):-1},{"popup",popupOpen()},{"geometry",lastGeometry}}).toJson(QJsonDocument::Compact);}
 QString MenuStyle(){QJsonArray a;for(auto w:QApplication::allWidgets())if(auto m=qobject_cast<QMenu*>(w);m&&m->isVisible()){QJsonArray actions;for(auto act:m->actions()){auto r=m->actionGeometry(act);actions.append(QJsonObject{{"text",act->text()},{"checked",act->isChecked()},{"checkable",act->isCheckable()},{"x",r.x()},{"y",r.y()},{"w",r.width()},{"h",r.height()}});}a.append(QJsonObject{{"style",m->style()->objectName()},{"font",m->font().toString()},{"actions",actions}});}return QJsonDocument(a).toJson(QJsonDocument::Compact);}
 QString Windows(){QJsonArray a;for(auto w:QGuiApplication::allWindows())a.append(QJsonObject{{"class",w->metaObject()->className()},{"name",w->objectName()},{"title",w->title()},{"visible",w->isVisible()},{"type",int(w->type())},{"parent",w->transientParent()?w->transientParent()->objectName():""},{"x",w->x()},{"y",w->y()},{"width",w->width()},{"height",w->height()}});return QJsonDocument(a).toJson(QJsonDocument::Compact);}
 QString PopupTree(){QJsonArray a;for(auto w:QGuiApplication::allWindows())if(w!=win&&w->isVisible()&&(w->objectName()=="popupWindow"||QString(w->metaObject()->className()).startsWith("NotificationPopup")))if(auto q=qobject_cast<QQuickWindow*>(w))dump(q->contentItem(),a,0,true);return QJsonDocument(a).toJson(QJsonDocument::Compact);}
 QString Tree(){QJsonArray a;if(win)dump(win->contentItem(),a,0);return QJsonDocument(a).toJson(QJsonDocument::Compact);}
};
// LNF applies defaults and palette as separate steps. Notify GTK only after the
// completed palette is available; no polling and no extra session process.
class GraphiteThemeSync : public QObject {
 KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
 KConfigWatcher::Ptr watcher = KConfigWatcher::create(config);
 QTimer settled;
public:
 explicit GraphiteThemeSync(QObject *parent) : QObject(parent) {
  settled.setSingleShot(true); settled.setInterval(120);
  connect(watcher.get(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &keys) {
   if (group.name() == QStringLiteral("KDE") && keys.contains("LookAndFeelPackage")) settled.start();
  });
  connect(&settled, &QTimer::timeout, this, [this] {
   config->reparseConfiguration();
   const QString mode = KConfigGroup(config,"KDE").readEntry("LookAndFeelPackage",QString());
   if(mode != QStringLiteral("org.leonid.softgraphite.dark") && mode != QStringLiteral("org.leonid.softgraphite.light")) return;
   const QString scheme = mode.endsWith(QStringLiteral(".dark")) ? QStringLiteral("SoftGraphite") : QStringLiteral("SoftGraphiteLight");
   KConfigGroup(config,"General").writeEntry("ColorScheme",scheme,KConfig::Persistent|KConfig::Notify);
   config->sync();
  });
  settled.start();
 }
};
class PanelTools:public QObject{Q_OBJECT
 QMap<QQuickWindow*,PanelController*> controllers;
public:
 PanelTools() {
  if (!qApp->property("graphiteThemeSyncInstalled").toBool()) {
   qApp->setProperty("graphiteThemeSyncInstalled",true);
   new GraphiteThemeSync(qApp);
  }
 }
 Q_SIGNAL void contentHidden();
 Q_SIGNAL void menuViewportChanged();
 Q_INVOKABLE bool menuSurfaceReady(QQuickItem*item,qreal width){return item&&item->window()&&controllers.contains(item->window())&&controllers[item->window()]->menuSurfaceReady(width);}
 Q_INVOKABLE void beginMenuMorph(QQuickItem*item){if(item&&item->window()&&controllers.contains(item->window()))controllers[item->window()]->beginMenuMorph(item);}
 Q_INVOKABLE void setMenuWidth(QQuickItem*item,qreal width){if(item&&item->window()&&controllers.contains(item->window()))controllers[item->window()]->setMenuWidth(width);}
 Q_INVOKABLE void finishMenuMorph(QQuickItem*item,qreal width){if(item&&item->window()&&controllers.contains(item->window()))controllers[item->window()]->finishMenuMorph(width);}
 Q_INVOKABLE bool contentIsHidden(QQuickItem*item){return item&&item->window()&&controllers.contains(item->window())&&controllers[item->window()]->contentIsHidden();}
 Q_INVOKABLE void setContentAlpha(QQuickItem*item,qreal alpha){if(item&&item->window()&&controllers.contains(item->window()))controllers[item->window()]->setContentAlpha(alpha);}
 // Detach presentation text from a live model that resets during focus changes.
 // Do not retain QAction pointers: they belong to the old application's menu.
 Q_INVOKABLE QVariantList menuSnapshot(QObject*object){
  QVariantList rows;auto model=qobject_cast<QAbstractItemModel*>(object);if(!model)return rows;
  const auto roles=model->roleNames();const int textRole=roles.key("activeMenu",-1),actionRole=roles.key("activeActions",-1);
  for(int row=0;row<model->rowCount();++row){auto idx=model->index(row,0);auto action=model->data(idx,actionRole).value<QAction*>();
   rows.append(QVariantMap{{"text",model->data(idx,textRole).toString()},{"visible",action&&action->isVisible()}});
  }return rows;
 }
 Q_INVOKABLE QRectF stableRect(QQuickItem*item,QRectF rect){if(item&&item->window())rect.translate(0,-item->window()->contentItem()->y());return rect;}
 Q_INVOKABLE void configure(QQuickItem*item,bool full,bool reveal,QString role,bool suppressed){if(!item||!item->window())return;auto w=item->window();if(!controllers.contains(w)){controllers[w]=new PanelController(w,role,this);connect(controllers[w],&PanelController::fullyHidden,this,&PanelTools::contentHidden);connect(controllers[w],&PanelController::menuViewportChanged,this,&PanelTools::menuViewportChanged);connect(w,&QObject::destroyed,this,[this,w]{controllers.remove(w);});}controllers[w]->configure(full,reveal,suppressed);}
};
class Plugin:public QQmlExtensionPlugin{Q_OBJECT Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:void registerTypes(const char*uri)override{qmlRegisterSingletonType<PanelTools>(uri,1,0,"PanelTools",[](QQmlEngine*,QJSEngine*)->QObject*{return new PanelTools;});}};
#include "panel-tools.moc"
