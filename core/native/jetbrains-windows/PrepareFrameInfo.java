import java.lang.classfile.*;
import java.nio.file.*;

// Build-time only: keep the installed class version and metadata unchanged.
public final class PrepareFrameInfo {
    public static void main(String[] args) throws Exception {
        var cf = ClassFile.of();
        var model = cf.parse(Files.readAllBytes(Path.of(args[0])));
        int[] changed = {0};
        byte[] result = cf.transformClass(model, (builder, element) -> {
            if (element instanceof MethodModel method &&
                ((method.methodName().equalsString("getExtendedState") && method.methodType().equalsString("()I")) ||
                 (method.methodName().equalsString("getFullScreen") && method.methodType().equalsString("()Z")))) {
                changed[0]++;
                builder.transformMethod(method, (mb, member) -> {
                    if (member instanceof CodeModel) mb.withCode(code -> code.iconst_0().ireturn());
                    else mb.with(member);
                });
            } else builder.with(element);
        });
        if (changed[0] != 2) throw new IllegalStateException("Unexpected FrameInfo API");
        var errors = cf.verify(result);
        if (!errors.isEmpty()) throw new IllegalStateException(errors.toString());
        Files.write(Path.of(args[1]), result);
        System.out.println("Verified: only the two persisted-state getters were replaced.");
    }
}
