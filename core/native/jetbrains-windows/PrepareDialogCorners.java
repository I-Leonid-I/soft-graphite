import java.lang.classfile.*;
import java.lang.constant.*;
import java.nio.file.*;

// Preserve native popup rounding; only let KWin round server-decorated dialogs.
public final class PrepareDialogCorners {
    public static void main(String[] args) throws Exception {
        var cf = ClassFile.of();
        var model = cf.parse(Files.readAllBytes(Path.of(args[0])));
        var wrapper = ClassDesc.of("com.intellij.openapi.ui.DialogWrapper");
        var window = ClassDesc.of("java.awt.Window");
        var dialog = ClassDesc.of("java.awt.Dialog");
        int[] count = {0};
        byte[] result = cf.transformClass(model, (builder, element) -> {
            if (element instanceof MethodModel method && method.methodName().equalsString("configure") &&
                method.methodType().equalsString("(Lcom/intellij/openapi/ui/DialogWrapper;)V")) {
                count[0]++;
                builder.transformMethod(method, (mb, member) -> {
                    if (member instanceof CodeModel oldCode) mb.withCode(code -> {
                        var original = code.newLabel();
                        code.aload(0).invokevirtual(wrapper, "getWindow", MethodTypeDesc.of(window));
                        code.instanceOf(dialog).ifeq(original);
                        code.aload(0).invokevirtual(wrapper, "getWindow", MethodTypeDesc.of(window));
                        code.checkcast(dialog).invokevirtual(dialog, "isUndecorated", MethodTypeDesc.of(ConstantDescs.CD_boolean));
                        code.ifne(original).return_().labelBinding(original);
                        code.transform(oldCode, CodeTransform.ACCEPT_ALL);
                    });
                    else mb.with(member);
                });
            } else builder.with(element);
        });
        if (count[0] != 1) throw new IllegalStateException("Unexpected dialog API");
        if (!cf.verify(result).isEmpty()) throw new IllegalStateException(cf.verify(result).toString());
        Files.write(Path.of(args[1]), result);
        System.out.println("Verified: decorated dialogs keep square client tops; popups unchanged.");
    }
}
