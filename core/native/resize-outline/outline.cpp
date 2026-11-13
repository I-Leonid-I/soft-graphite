// SPDX-License-Identifier: GPL-2.0-or-later
#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <workspace.h>
#include <window.h>
#include <core/output.h>
#include <input_event.h>
#include <QPointer>
#include <QTimer>
#include <QKeyEvent>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QJsonDocument>
#include <QJsonObject>
#include <cmath>
#include "column-resize.h"
namespace KWin {
class GraphiteOutline final : public Effect {
 Q_OBJECT
 Q_CLASSINFO("D-Bus Interface", "org.leonid.GraphiteOutline")
 QPointer<Window> target;
 QRectF original, pending, requested;
 QJsonObject columns;
 QPointF origin, last;
 Gravity gravity{}; // value-initialised (Gravity::None); KWin 6.8 headers made the old initialiser ambiguous
 QTimer previewTimer;
 bool capturing=false, keyboard=false;
 int commits=0, cancellations=0, updates=0;
 static constexpr int resizeRole=120901;
 bool left()const{return gravity==Gravity::Left||gravity==Gravity::TopLeft||gravity==Gravity::BottomLeft;}
 bool right()const{return gravity==Gravity::Right||gravity==Gravity::TopRight||gravity==Gravity::BottomRight;}
 bool top()const{return gravity==Gravity::Top||gravity==Gravity::TopLeft||gravity==Gravity::TopRight;}
 bool bottom()const{return gravity==Gravity::Bottom||gravity==Gravity::BottomLeft||gravity==Gravity::BottomRight;}
 void preview(bool visible){
  auto m=QDBusMessage::createMethodCall("org.leonid.SoftGraphite","/SoftGraphite","org.leonid.SoftGraphite","Preview");
  const QRect r=visible?pending.toAlignedRect():QRect();
  m<<QString(visible&&target?target->output()->name():QString())<<QString(visible?"resize":"")<<r.x()<<r.y()<<r.width()<<r.height();
  QDBusConnection::sessionBus().asyncCall(m);
 }
 void change(QPointF position){
  if(!capturing||!target)return;last=position;
  const QPointF delta=position-origin;
  QSizeF size(original.width()+(right()?delta.x():left()?-delta.x():0),original.height()+(bottom()?delta.y():top()?-delta.y():0));
  if(columns.isEmpty())size=target->constrainFrameSize(QSizeF(qMax(100.0,size.width()),qMax(60.0,size.height())));
  QRectF r=original;r.setWidth(size.width());r.setHeight(size.height());
  if(left())r.moveRight(original.right());if(top())r.moveBottom(original.bottom());
  r=QRectF(r.toRect());
  // Resizing one axis must not round the other axis on fractional outputs.
  if(!left()&&!right()){r.setX(original.x());r.setWidth(original.width());}
  if(!top()&&!bottom()){r.setY(original.y());r.setHeight(original.height());}
  if(!columns.isEmpty()){
   const qreal base=columns["base"].toDouble(),total=columns["total"].toDouble();
   // Only the physical screen edges limit the preview. Application limits
   // resolve the released rectangle once, before any real configure.
   r=SoftGraphite::resolveColumn(original,r,columns["side"].toInt(),base,13,total-13);
  }
  if(r==pending)return;requested=r;pending=r;++updates;if(!previewTimer.isActive())previewTimer.start();
 }
 void finish(bool commit){
  if(!capturing)return;
  if(commit&&!columns.isEmpty())pending=SoftGraphite::resolveColumn(original,pending,columns["side"].toInt(),columns["base"].toDouble(),columns["low"].toDouble(),columns["high"].toDouble());
  columns={};capturing=false;previewTimer.stop();preview(false);
  effects->stopMouseInterception(this);if(keyboard){effects->ungrabKeyboard();keyboard=false;}
  const QPointer<Window> w=target;target.clear();
  if(commit&&w&&!w->isDeleted()&&pending!=original){
   ++commits;w->effectWindow()->setData(resizeRole,true);
   // A previewed resize out of maximization must also leave its state, so the
   // edge panels and the next restore action match the committed rectangle.
   if(w->requestedMaximizeMode()!=MaximizeRestore)w->setMaximize(false,false);
   if(w->quickTileMode()!=QuickTileMode())w->setQuickTileMode(QuickTileMode(),pending.center());
   w->moveResize(RectF(pending));
   QTimer::singleShot(800,this,[w]{if(w&&!w->isDeleted())w->effectWindow()->setData(resizeRole,QVariant());});
  }else ++cancellations;
 }
 void begin(Window *w,QRectF initial,QPointF anchor,Gravity edge){
  if(capturing||!w||w->isDeleted()||!w->isNormalWindow()||!w->isInteractiveResize()||w->isFullScreen()||effects->hasActiveFullScreenEffect()||effects->isMouseInterception()||effects->isScreenLocked())return;
  if(!effects->grabKeyboard(this))return;keyboard=true;
  target=w;original=initial;pending=original;requested=original;columns={};gravity=edge;origin=anchor;last=origin;
  w->cancelInteractiveMoveResize();
  if(!target||target->isDeleted()){effects->ungrabKeyboard();keyboard=false;return;}
  capturing=true;
  Qt::CursorShape shape=(left()||right())&&(top()||bottom())?((left()&&top())||(right()&&bottom())?Qt::SizeFDiagCursor:Qt::SizeBDiagCursor):((left()||right())?Qt::SizeHorCursor:Qt::SizeVerCursor);
  effects->startMouseInterception(this,shape);change(effects->cursorPos());preview(true);
 }
 void watch(Window *w){
  connect(w,&Window::interactiveMoveResizeStarted,this,[this,w]{
   if(!w->isInteractiveResize())return;
   const QPointer<Window> guard=w;
   const QRectF initial(w->moveResizeGeometry());const auto anchor=w->interactiveMoveResizeAnchor();const auto edge=w->interactiveMoveResizeGravity();
   if(guard)begin(guard,initial,anchor,edge);
  });
 }
public:
 GraphiteOutline(){
  previewTimer.setInterval(16);previewTimer.setSingleShot(true);connect(&previewTimer,&QTimer::timeout,this,[this]{if(capturing)preview(true);});
  for(auto w:workspace()->windows())watch(w);
  connect(workspace(),&Workspace::windowAdded,this,&GraphiteOutline::watch);
  connect(workspace(),&Workspace::windowRemoved,this,[this](Window*w){if(target==w)finish(false);});
  connect(effects,&EffectsHandler::screenAboutToLock,this,[this]{finish(false);});
  connect(effects,&EffectsHandler::virtualScreenGeometryChanged,this,[this]{finish(false);});
  QDBusConnection::sessionBus().registerObject("/SoftGraphiteResize",this,QDBusConnection::ExportAllSlots);
 }
 ~GraphiteOutline()override{finish(false);QDBusConnection::sessionBus().unregisterObject("/SoftGraphiteResize");}
 bool isActive()const override{return capturing;}
 void pointerMotion(PointerMotionEvent*e)override{change(e->position);}
 void pointerButton(PointerButtonEvent*e)override{if(capturing&&e->state==PointerButtonState::Released&&e->buttons==Qt::NoButton){change(e->position);finish(true);}}
 void grabbedKeyboardEvent(QKeyEvent*e)override{
  if(!capturing||e->type()!=QEvent::KeyPress)return;
  if(e->key()==Qt::Key_Escape){finish(false);return;}
  if(e->key()==Qt::Key_Return||e->key()==Qt::Key_Enter){finish(true);return;}
  const int step=(e->modifiers()&Qt::ControlModifier)?1:8;
  QPointF p=last;if(e->key()==Qt::Key_Left)p.rx()-=step;else if(e->key()==Qt::Key_Right)p.rx()+=step;else if(e->key()==Qt::Key_Up)p.ry()-=step;else if(e->key()==Qt::Key_Down)p.ry()+=step;else return;change(p);
 }
public Q_SLOTS:
 void Columns(QString data){
  // Script callbacks can arrive synchronously before our Started connection.
  // Defer this one event, then validate its window id against the capture.
  if(!capturing){QTimer::singleShot(0,this,[this,data]{if(capturing)Columns(data);});return;}
  if(!target)return;
  const auto o=QJsonDocument::fromJson(data.toUtf8()).object();
  if(o.isEmpty()){columns={};change(last);preview(true);return;}
  const auto a=o["original"].toObject(),l=o["left"].toObject(),r=o["right"].toObject();
  const auto near=[](qreal x,qreal y){return qAbs(x-y)<1.1;};
  const int side=o["side"].toInt(-1);
  const qreal base=l["x"].toDouble()-8,total=r["x"].toDouble()+r["width"].toDouble()+8-base;
  const qreal low=o["low"].toDouble(),high=o["high"].toDouble();
  if(!o["freeDivider"].toBool()||o["windowId"].toString()!=target->internalId().toString()||o["output"].toString()!=target->output()->name())return;
  if(!near(a["x"].toDouble(),original.x())||!near(a["y"].toDouble(),original.y())||!near(a["width"].toDouble(),original.width())||!near(a["height"].toDouble(),original.height()))return;
  if(!((side==0&&gravity==Gravity::Right)||(side==1&&gravity==Gravity::Left)))return;
  if(!o["low"].isDouble()||!o["high"].isDouble()||!std::isfinite(total)||total<=26||low<12||high>total-12||low>high)return;
  columns=o;columns["base"]=base;columns["total"]=total;change(last);preview(true);
 }
 QString State()const{auto rect=[](QRectF r){return QJsonObject{{"x",r.x()},{"y",r.y()},{"width",r.width()},{"height",r.height()}};};return QJsonDocument(QJsonObject{{"active",capturing},{"freeColumns",!columns.isEmpty()},{"requested",rect(requested)},{"windowId",target?target->internalId().toString():QString()},{"originX",origin.x()},{"originY",origin.y()},{"original",rect(original)},{"target",rect(pending)},{"commits",commits},{"cancellations",cancellations},{"previewUpdates",updates}}).toJson(QJsonDocument::Compact);}
};
KWIN_EFFECT_FACTORY_SUPPORTED(GraphiteOutline,"metadata.json",return true;)
}
#include "outline.moc"
