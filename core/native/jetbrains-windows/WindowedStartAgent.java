import java.io.InputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Suppress saved IDEA frame maximization before mapping, never resize a live window. */
public final class WindowedStartAgent {
    private static final Map<String, String[]> PATCHES = Map.of(
        "com/intellij/openapi/wm/impl/FrameInfo", new String[]{
            "eb6132d9bef4fbf682ef382d3f1f13ba30b9c3f8cd8c6e3bbd3a35e7e3025646", "FrameInfo.windowed.class"},
        "com/intellij/ui/WindowRoundedCornersManager", new String[]{
            "021fe9d821d2affbe1c219e0e4b808a07073e3681c79d565eb086f3ea81a9135", "WindowRoundedCornersManager.system.class"}
    );

    public static void premain(String options, Instrumentation instrumentation) {
        // Fail open on an unknown IDE build. Do not touch AWT or build-tool JVMs.
        var pending = ConcurrentHashMap.newKeySet();
        pending.addAll(PATCHES.keySet());
        instrumentation.addTransformer(new ClassFileTransformer() {
            @Override
            public byte[] transform(ClassLoader loader, String name, Class<?> redefined,
                                    ProtectionDomain domain, byte[] original) {
                if (name == null || !pending.remove(name)) return null;
                if (pending.isEmpty()) instrumentation.removeTransformer(this);
                String[] patch = PATCHES.get(name);
                try {
                    String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(original));
                    if (!patch[0].equals(hash)) {
                        System.err.println("[Soft Graphite] IDEA adapter skipped: unverified " + name + " version.");
                        return null;
                    }
                    try (InputStream data = WindowedStartAgent.class.getResourceAsStream("/" + patch[1])) {
                        if (data == null) throw new IllegalStateException("Missing verified class resource");
                        byte[] patched = data.readAllBytes();
                        System.err.println("[Soft Graphite] Pre-display window policy applied: " + name);
                        return patched;
                    }
                } catch (Exception | LinkageError error) {
                    System.err.println("[Soft Graphite] IDEA windowed-start adapter skipped: " + error.getClass().getSimpleName());
                    return null;
                }
            }
        });
    }
}
