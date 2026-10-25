import java.awt.Rectangle;
import java.lang.reflect.*;

/** Exercises the actual installed IDEA class, not a substitute. */
public final class CheckFrameInfo {
    public static void main(String[] args) throws Exception {
        boolean adapted = Boolean.parseBoolean(args[0]);
        Class<?> cls = Class.forName("com.intellij.openapi.wm.impl.FrameInfo");
        Object info = cls.getConstructor().newInstance();
        cls.getMethod("setExtendedState", int.class).invoke(info, 6);
        cls.getMethod("setFullScreen", boolean.class).invoke(info, true);
        Rectangle bounds = new Rectangle(2180, 120, 1200, 780);
        cls.getMethod("setBounds", Rectangle.class).invoke(info, bounds);
        int state = (int) cls.getMethod("getExtendedState").invoke(info);
        boolean fullscreen = (boolean) cls.getMethod("getFullScreen").invoke(info);
        if (state != (adapted ? 0 : 6) || fullscreen != !adapted)
            throw new AssertionError("Incorrect restored state: " + state + ", " + fullscreen);
        if (!bounds.equals(cls.getMethod("getBounds").invoke(info))) throw new AssertionError("Bounds changed");
        // Copying persisted state bypasses setters in some BaseState paths.
        Object copy = cls.getConstructor().newInstance();
        Method copyMethod = java.util.Arrays.stream(cls.getMethods())
                .filter(m -> m.getName().equals("copyFrom") && m.getParameterCount() == 1).findFirst().orElseThrow();
        copyMethod.invoke(copy, info);
        if ((int) cls.getMethod("getExtendedState").invoke(copy) != state ||
            (boolean) cls.getMethod("getFullScreen").invoke(copy) != fullscreen ||
            !bounds.equals(cls.getMethod("getBounds").invoke(copy))) throw new AssertionError("Copy changed state/bounds");
        System.out.println("PASS installed IDEA FrameInfo: saved state=" + state + ", fullScreen=" + fullscreen + ", bounds/copy preserved");
    }
}
