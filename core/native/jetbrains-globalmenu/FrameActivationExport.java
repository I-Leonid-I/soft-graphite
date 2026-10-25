package dev.softgraphite.globalmenu;

import com.intellij.ide.AppLifecycleListener;
import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.wm.IdeFrame;
import dev.jfronny.globalmenu.GlobalMenuService;

import javax.swing.JFrame;
import java.awt.AWTEvent;
import java.awt.Toolkit;
import java.awt.event.WindowEvent;
import java.util.List;

/**
 * Soft Graphite replacement for the Global Menu plugin's ApplicationActivationListener: export
 * the menu whenever an IDE frame becomes the active window. IDEA does not fire application
 * activation for the first project frame (the splash already made the app active) or when
 * switching between two IDE frames, so those windows showed no menu in the top panel. The
 * upstream registration is disabled in plugin.xml: two services unexported each other's menus.
 */
public final class FrameActivationExport implements AppLifecycleListener {
    private static GlobalMenuService service;

    @Override
    public void appFrameCreated(List<String> commandLineArgs) {
        Toolkit.getDefaultToolkit().addAWTEventListener(event -> {
            if (event.getID() != WindowEvent.WINDOW_ACTIVATED) return;
            if (!(event.getSource() instanceof IdeFrame frame) || !(frame instanceof JFrame)) return;
            try {
                if (service == null) service = new GlobalMenuService(ApplicationManager.getApplication());
                service.applicationActivated(frame);
            } catch (Throwable ignored) {
                // Same outcome as upstream: the menu appears on the next application activation.
            }
        }, AWTEvent.WINDOW_EVENT_MASK);
    }
}
