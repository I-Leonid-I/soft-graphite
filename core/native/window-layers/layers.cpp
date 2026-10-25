// SPDX-License-Identifier: GPL-2.0-or-later
#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <workspace.h>
#include <window.h>
#include <scene/windowitem.h>
#include <input.h>
#include <input_event.h>
#include <input_event_spy.h>
#include <pointer_input.h>
#include <wayland_server.h>
#include <wayland/seat.h>
#include <QPointer>
#include <QDBusConnection>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

namespace KWin {
struct OverlayPair { QPointer<Window> below, above; };

// A relationship between two windows, never a global keep-above flag.
class GraphiteLayers final : public Effect, public InputEventSpy {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.leonid.GraphiteLayers")
    QList<OverlayPair> pairs;
    QList<OverlayPair> shellPairs;
    QPointer<Window> dragging;
    bool restoringFocus = false;
    QPointer<Window> launchSource;
    QString launchApp, launchClass;
    QTimer launchExpiry;
    bool changing = false;
    bool pruneQueued = false;

    bool usable(Window *w, bool includeMinimizeAnimation = false) const {
        return w && !w->isDeleted()
            && (w->isShown() || (includeMinimizeAnimation && w->isMinimized()
                && w->windowItem() && w->windowItem()->isVisible()))
            && w->isOnCurrentDesktop() && w->isOnCurrentActivity()
            && (w->isNormalWindow() || w->isDialog())
            && w->resourceClass() != "soft-graphite-edge" && w->resourceClass() != "org.kde.spectacle";
    }
    bool overlap(Window *a, Window *b) const {
        return QRectF(a->frameGeometry()).intersects(QRectF(b->frameGeometry()));
    }
    bool expanded(Window *w) const {
        // Browsers use borderless native maximization to keep their address bar.
        return w && (w->isFullScreen() || (w->maximizeMode()==MaximizeFull && w->noBorder()));
    }
    QList<QPointer<Window>> overlaysFor(Window *target) const {
        QList<QPointer<Window>> overlays;
        const auto order=workspace()->stackingOrder();
        const int targetIndex=order.indexOf(target);
        if(targetIndex<0)return overlays;
        for(int i=order.size()-1;i>targetIndex;--i) {
            auto *w=order[i];
            // Fullscreen peers are backgrounds, not floating overlays. Keep them
            // mapped when switching: unmapping a true-fullscreen XWayland
            // Chromium/Electron surface can restore an empty client buffer.
            if(!usable(w) || expanded(w) || !w->isMinimizable() || w->output()!=target->output() || !overlap(w,target))continue;
            // Keep the selected application's own dialogs accessible.
            if(w->allMainWindows().contains(target) || target->allMainWindows().contains(w))continue;
            overlays.append(QPointer<Window>(w));
        }
        return overlays;
    }
    bool dataDragActive() const {
        // KWin focuses surfaces under the pointer while dragging data, including
        // the fullscreen background between a revealed dock and a floating app.
        // That is drop-target discovery, not a request to minimize overlays.
        // Query the compositor's actual drag lifetime: no polling or deadline.
        const auto *server = waylandServer();
        return server && server->seat() && server->seat()->isDrag();
    }
    bool focusFullscreen(Window *target, const QList<QPointer<Window>> &overlays) {
        if (!usable(target) || !expanded(target) || dragging || dataDragActive() || effects->isScreenLocked()) return false;
        if(overlays.isEmpty())return false;
        clearLaunch();
        StackingUpdatesBlocker blocker(workspace());
        // Focus first so minimizing overlays does not activate an unrelated app.
        workspace()->activateWindow(target,true);
        for(const auto &w:overlays)if(w && usable(w) && !expanded(w) && w->output()==target->output() && overlap(w,target))w->setMinimized(true);
        workspace()->activateWindow(target,true);
        prune();
        return true;
    }
    void add(Window *below, Window *above) {
        if (below == above || !usable(below) || !usable(above) || !expanded(below) || expanded(above)) return;
        // Borderless maximized browsers are the same backdrop layer as true
        // fullscreen clients; neither should cover a floating drop target.
        // KWin already owns all transient constraints; never remove one of those.
        if (above->allMainWindows().contains(below) || below->allMainWindows().contains(above)) return;
        for (const auto &pair : pairs) if (pair.below == below && pair.above == above) return;
        pairs.append(OverlayPair{below, above});
        workspace()->constrain(below, above);
    }
    void schedulePrune() {
        // Visibility briefly falls before the minimize effect acquires its
        // visible reference. Inspect after that transaction, once per turn.
        if (pruneQueued) return;
        pruneQueued = true;
        QTimer::singleShot(0, this, [this] { pruneQueued = false; prune(); });
    }
    void prune() {
        if (changing) return;
        changing = true;
        // Keep the local stacking relation while a minimized window is still
        // being painted by an effect; release it as soon as painting ends.
        StackingUpdatesBlocker blocker(workspace());
        for (int i = pairs.size()-1; i >= 0; --i) {
            const auto pair = pairs[i];
            if (!usable(pair.below) || !usable(pair.above, true) || !expanded(pair.below)
                || expanded(pair.above) || (pair.above != dragging && !overlap(pair.below, pair.above))) {
                pairs.removeAt(i);
                if (pair.below && pair.above) workspace()->unconstrain(pair.below, pair.above);
            }
        }
        changing = false;
    }
    void beginDrag(Window *w) {
        if (!usable(w) || !w->isInteractiveMove() || w->isFullScreen()) return;
        dragging = w;
        StackingUpdatesBlocker blocker(workspace());
        // Prepare before the first pixel crosses an output edge. No per-motion scan.
        for (auto *other : workspace()->windows()) add(other, w);
    }
    void finishDrag(Window *w) {
        if (dragging != w) return;
        dragging.clear();
        prune(); // Keep only fullscreen windows actually underneath the dropped window.
    }
    bool shellPopup(Window *w) const {
        if(!w || w->isDeleted() || !w->isShown() || !w->isOnCurrentDesktop() || w->isDock() || w->isDesktop()) return false;
        const auto app=w->resourceClass();
        return w->wantsInput() && (app=="org.kde.plasmashell" || app=="org.kde.krunner" || app=="krunner");
    }
    void syncShellLayers() {
        StackingUpdatesBlocker blocker(workspace());
        for(int i=shellPairs.size()-1;i>=0;--i) {
            const auto pair=shellPairs[i];
            if(!pair.below || !shellPopup(pair.above) || pair.below->output()!=pair.above->output()) {
                shellPairs.removeAt(i);
                if(pair.below && pair.above)workspace()->unconstrain(pair.below,pair.above);
            }
        }
        for(auto *popup:workspace()->windows())if(shellPopup(popup)) {
            for(auto *panel:workspace()->windows())if(panel->isDock() && panel->resourceClass()=="plasmashell" && panel->output()==popup->output()) {
                if(popup->allMainWindows().contains(panel))continue;
                bool exists=false;for(const auto &pair:shellPairs)if(pair.below==panel&&pair.above==popup){exists=true;break;}
                if(!exists){shellPairs.append(OverlayPair{panel,popup});workspace()->constrain(panel,popup);}
            }
        }
    }
    void activated(Window *w, bool allowRestore = true) {
        syncShellLayers();
        if(allowRestore && !restoringFocus && !dataDragActive() && usable(w) && expanded(w)) {
            const auto overlays=overlaysFor(w);
            if(!overlays.isEmpty()) QTimer::singleShot(0,this,[this,target=QPointer<Window>(w),overlays]{
                // Only the committed focus counts; Alt+Tab previews/cancellation
                // and transient intermediate activations must not minimize windows.
                if(target && workspace()->activeWindow()==target && !restoringFocus) {
                    restoringFocus=true;focusFullscreen(target,overlays);restoringFocus=false;
                }
            });
        }
        if (launchSource && w && w != launchSource && !launchMatches(w)) clearLaunch();
        if (!usable(w) || expanded(w)) return;
        StackingUpdatesBlocker blocker(workspace());
        for (auto *other : workspace()->windows()) if (overlap(other,w)) add(other,w);
    }
    bool launchMatches(Window *w) const {
        return w && ((!launchApp.isEmpty() && w->desktopFileName() == launchApp)
            || (!launchClass.isEmpty() && w->resourceClass().compare(launchClass,Qt::CaseInsensitive)==0));
    }
    void clearLaunch() { launchSource.clear(); launchApp.clear(); launchClass.clear(); launchExpiry.stop(); }
    void presentBrowser(Window *w) {
        if (!launchSource || !launchMatches(w)) return;
        if (workspace()->activeWindow()!=launchSource && workspace()->activeWindow()!=w) {clearLaunch();return;}
        clearLaunch();
        w->setMinimized(false);
        workspace()->activateWindow(w,true);
        activated(w);
    }
    void watch(Window *w) {
        connect(w, &Window::interactiveMoveResizeStarted, this, [this,w]{beginDrag(w);});
        connect(w, &Window::interactiveMoveResizeFinished, this, [this,w]{finishDrag(w);});
        connect(w, &Window::frameGeometryChanged, this, [this,w]{if(w != dragging && !pairs.isEmpty()) prune();});
        connect(w, &Window::fullScreenChanged, this, &GraphiteLayers::prune);
        connect(w, &Window::maximizedChanged, this, &GraphiteLayers::prune);
        connect(w, &Window::decorationPolicyChanged, this, &GraphiteLayers::prune);
        connect(w, &Window::minimizedChanged, this, &GraphiteLayers::schedulePrune);
        if (w->windowItem()) connect(w->windowItem(), &Item::visibleChanged, this, &GraphiteLayers::schedulePrune);
        connect(w, &Window::hiddenChanged, this, &GraphiteLayers::schedulePrune);
        connect(w, &Window::hiddenChanged, this, &GraphiteLayers::syncShellLayers);
        if(w->isDock() || w->resourceClass()=="org.kde.plasmashell" || w->resourceClass().contains("krunner"))
            QTimer::singleShot(0,this,&GraphiteLayers::syncShellLayers);
        connect(w, &Window::desktopsChanged, this, &GraphiteLayers::prune);
        // New browser windows are matched only during an explicit URL launch.
        if (launchSource && launchMatches(w)) QTimer::singleShot(0,this,[this,w=QPointer<Window>(w)]{if(w)presentBrowser(w);});
    }
public:
    GraphiteLayers() {
        for (auto *w : workspace()->windows()) watch(w);
        connect(workspace(), &Workspace::windowAdded, this, &GraphiteLayers::watch);
        connect(workspace(), &Workspace::windowRemoved, this, [this](Window *w){if(dragging==w)dragging.clear();prune();syncShellLayers();});
        connect(workspace(), &Workspace::currentDesktopChanged, this, [this]{prune();});
        connect(workspace(), &Workspace::currentActivityChanged, this, [this]{prune();clearLaunch();});
        connect(workspace(), &Workspace::windowActivated, this, [this](Window *w){activated(w);});
        launchExpiry.setSingleShot(true);launchExpiry.setInterval(4000);
        connect(&launchExpiry,&QTimer::timeout,this,&GraphiteLayers::clearLaunch);
        connect(effects, &EffectsHandler::tabBoxClosed, this, [this]{
            // Capture before KWin raises a borderless maximized browser. After
            // activation those overlays may already be below it in the stack.
            const auto selected=effects->currentTabBoxWindow();
            QPointer<Window> target=selected ? selected->window() : nullptr;
            if(dataDragActive() || !usable(target) || !expanded(target) || workspace()->activeWindow()==target)return;
            const auto overlays=overlaysFor(target);
            if(overlays.isEmpty())return;
            QTimer::singleShot(0,this,[this,target,overlays]{
                if(target && workspace()->activeWindow()==target && !restoringFocus) {
                    restoringFocus=true;focusFullscreen(target,overlays);restoringFocus=false;
                }
            });
        });
        activated(workspace()->activeWindow(),false);
        input()->installInputEventSpy(this);
        QDBusConnection::sessionBus().registerObject("/SoftGraphiteLayers", this, QDBusConnection::ExportAllSlots);
    }
    ~GraphiteLayers() override {
        input()->uninstallInputEventSpy(this);
        StackingUpdatesBlocker blocker(workspace());
        for (const auto &pair : pairs) if (pair.below && pair.above) workspace()->unconstrain(pair.below, pair.above);
        for(const auto &pair:shellPairs)if(pair.below&&pair.above)workspace()->unconstrain(pair.below,pair.above);
        QDBusConnection::sessionBus().unregisterObject("/SoftGraphiteLayers");
    }
    bool isActive() const override { return false; } // No rendering or polling.
    void pointerMotion(PointerMotionEvent *event) override {
        workspace()->setActiveOutput(event->position);
    }
    void pointerButton(PointerButtonEvent *event) override {
        if(event->state==PointerButtonState::Pressed) {
            workspace()->setActiveOutput(event->position);
        }
        if(event->button!=Qt::LeftButton || event->state!=PointerButtonState::Pressed
            || event->modifiers!=Qt::NoModifier || dataDragActive() || input()->isSelectingWindow()
            || effects->isScreenLocked() || effects->activeFullScreenEffect())return;
        // Pointer focus can still refer to the client during a panel enter.
        // Hit-test the actual input surface so a dock click is handled only once.
        QPointer<Window> target=input()->findToplevel(event->position);
        if(!usable(target) || !expanded(target))return;
        const auto overlays=overlaysFor(target);
        if(overlays.isEmpty())return;
        // Run after native click dispatch; never consume the application's click.
        QTimer::singleShot(0,this,[this,target,overlays]{if(target)focusFullscreen(target,overlays);});
    }
    void touchDown(TouchDownEvent *event) override {
        workspace()->setActiveOutput(event->pos);
    }
public Q_SLOTS:
    bool FocusFullscreen(const QStringList &ids) {
        // The dock supplies only window IDs belonging to its own task/monitor.
        const auto order=workspace()->stackingOrder();
        for(auto it=order.crbegin();it!=order.crend();++it)
            if(ids.contains((*it)->internalId().toString()) && usable(*it) && expanded(*it))return focusFullscreen(*it,overlaysFor(*it));
        return false;
    }
    void RestoreOverlayState(const QString &state) {
        // Carry live relationships across a hot update; stale IDs are ignored.
        const auto list=QJsonDocument::fromJson(state.toUtf8()).object()["pairs"].toArray();
        StackingUpdatesBlocker blocker(workspace());
        for(const auto &entry:list) {
            auto pair=entry.toObject();Window *below=nullptr,*above=nullptr;
            for(auto *w:workspace()->windows()) {
                if(w->internalId().toString()==pair["below"].toString())below=w;
                if(w->internalId().toString()==pair["above"].toString())above=w;
            }
            if(below&&above&&overlap(below,above))add(below,above);
        }
    }
    void PrepareBrowserOpen(const QString &desktopFile, const QString &wmClass) {
        clearLaunch();
        auto *source=workspace()->activeWindow();
        // An explicit external URL is a focus request in windowed mode too,
        // including when source and browser are on different outputs.
        if (!usable(source) || effects->isScreenLocked()
            || (desktopFile.isEmpty()&&wmClass.isEmpty())) return;
        launchSource=source;launchApp=desktopFile;launchClass=wmClass;launchExpiry.start();
        Window *target=nullptr;
        for(auto *w:workspace()->stackingOrder()) if(launchMatches(w)&&w->isNormalWindow()) {
            if(!target || w->output()==source->output()) target=w;
        }
        if(target) presentBrowser(target);
    }
    QString State() const {
        QJsonArray list;
        for (const auto &pair : pairs) if(pair.below && pair.above)
            list.append(QJsonObject{{"below",pair.below->internalId().toString()},{"above",pair.above->internalId().toString()}});
        QJsonArray shell;for(const auto &pair:shellPairs)if(pair.below&&pair.above)shell.append(QJsonObject{{"panel",pair.below->internalId().toString()},{"popup",pair.above->internalId().toString()}});
        return QJsonDocument(QJsonObject{{"dataDragActive",dataDragActive()},{"shellPairs",shell},{"dragging",dragging ? dragging->internalId().toString() : QString()}, {"pairs",list}}).toJson(QJsonDocument::Compact);
    }
};
KWIN_EFFECT_FACTORY_SUPPORTED(GraphiteLayers,"metadata.json",return true;)
}
#include "layers.moc"
