package dev.jfronny.dbusmenu4j;

import java.lang.foreign.*;
import java.lang.invoke.*;

import static java.lang.foreign.MemoryLayout.PathElement.groupElement;
import static java.lang.foreign.MemorySegment.NULL;

public final class WaylandPanama {
    private WaylandPanama() {
        throw new UnsupportedOperationException();
    }

    private static final System.Logger LOG = System.getLogger("dbusmenu4j/wayland-panama");

    private static final ValueLayout.OfBoolean C_BOOL = (ValueLayout.OfBoolean) Linker.nativeLinker().canonicalLayouts().get("bool");
    private static final ValueLayout.OfByte C_CHAR =(ValueLayout.OfByte)Linker.nativeLinker().canonicalLayouts().get("char");
    private static final ValueLayout.OfShort C_SHORT = (ValueLayout.OfShort) Linker.nativeLinker().canonicalLayouts().get("short");
    private static final ValueLayout.OfInt C_INT = (ValueLayout.OfInt) Linker.nativeLinker().canonicalLayouts().get("int");
    private static final ValueLayout.OfLong C_LONG_LONG = (ValueLayout.OfLong) Linker.nativeLinker().canonicalLayouts().get("long long");
    private static final ValueLayout.OfFloat C_FLOAT = (ValueLayout.OfFloat) Linker.nativeLinker().canonicalLayouts().get("float");
    private static final ValueLayout.OfDouble C_DOUBLE = (ValueLayout.OfDouble) Linker.nativeLinker().canonicalLayouts().get("double");
    private static final AddressLayout C_POINTER = ((AddressLayout) Linker.nativeLinker().canonicalLayouts().get("void*"))
            .withTargetLayout(MemoryLayout.sequenceLayout(java.lang.Long.MAX_VALUE, C_CHAR));
    private static final ValueLayout.OfLong C_LONG = (ValueLayout.OfLong) Linker.nativeLinker().canonicalLayouts().get("long");
    private static final Linker nativeLinker = Linker.nativeLinker();
    private static final SymbolLookup loaderLookup = SymbolLookup.loaderLookup().or(nativeLinker.defaultLookup()).or(loadWaylandClient());

    private static SymbolLookup loadWaylandClient() {
        try {
            return SymbolLookup.libraryLookup("libwayland-client.so", Arena.global());
        } catch (IllegalArgumentException exc) {
            return SymbolLookup.libraryLookup("libwayland-client.so.0", Arena.global());
        }
    }

    private static MemorySegment org_kde_kwin_appmenu_interface;
    private static MemorySegment org_kde_kwin_appmenu_manager_interface;
    private static MethodHandle wl_proxy_get_version;
    private static MethodHandle wl_proxy_marshal_flags;
    private static MethodHandle wl_proxy_marshal_flags_1ptr;
    private static MethodHandle wl_proxy_marshal_flags_2ptr;
    private static MethodHandle wl_proxy_marshal_flags_registry_bind;
    private static MethodHandle wl_proxy_destroy;
    private static final int ORG_KDE_KWIN_APPMENU_MANAGER_CREATE = 0;
    private static final int ORG_KDE_KWIN_APPMENU_SET_ADDRESS = 0;
    private static final int ORG_KDE_KWIN_APPMENU_RELEASE = 1;
    private static final int WL_REGISTRY_BIND = (int)0L;
    private static final int WL_DISPLAY_GET_REGISTRY = 1;
    private static final int WL_MARSHAL_FLAG_DESTROY = 1 << 0;

    private static boolean isInitialized = false;
    public static void init(Long displayPtr) throws Throwable {
        if (isInitialized) {
            return;
        }
        if (displayPtr == null) {
            // Apparently, we are not using Wayland.
            isInitialized = true;
            return;
        }



        FunctionDescriptor wlProxyMarshalFlagsBase = FunctionDescriptor.of(C_POINTER, C_POINTER, C_INT, C_POINTER, C_INT, C_INT);
        FunctionDescriptor wlProxyMarshalFlags1ptr = wlProxyMarshalFlagsBase.appendArgumentLayouts(C_POINTER);
        FunctionDescriptor wlProxyMarshalFlags2ptr = wlProxyMarshalFlagsBase.appendArgumentLayouts(C_POINTER, C_POINTER);
        FunctionDescriptor wlProxyMarshalFlagsRegistryBind = wlProxyMarshalFlagsBase.appendArgumentLayouts(C_INT, C_POINTER, C_INT, C_POINTER);
        MemorySegment wlProxyMarshalFlags = loaderLookup.find("wl_proxy_marshal_flags").orElse(null);
        if (wlProxyMarshalFlags == null) {
            // Wayland is unavailable :(
            isInitialized = true;
            return;
        }
        wl_proxy_marshal_flags = Linker.nativeLinker().downcallHandle(wlProxyMarshalFlags, wlProxyMarshalFlagsBase);
        wl_proxy_marshal_flags_1ptr = Linker.nativeLinker().downcallHandle(wlProxyMarshalFlags, wlProxyMarshalFlags1ptr, Linker.Option.firstVariadicArg(wlProxyMarshalFlagsBase.argumentLayouts().size()));
        wl_proxy_marshal_flags_2ptr = Linker.nativeLinker().downcallHandle(wlProxyMarshalFlags, wlProxyMarshalFlags2ptr, Linker.Option.firstVariadicArg(wlProxyMarshalFlagsBase.argumentLayouts().size()));
        wl_proxy_marshal_flags_registry_bind = Linker.nativeLinker().downcallHandle(wlProxyMarshalFlags, wlProxyMarshalFlagsRegistryBind, Linker.Option.firstVariadicArg(wlProxyMarshalFlagsBase.argumentLayouts().size()));



        FunctionDescriptor wlProxyGetVersionDescriptor = FunctionDescriptor.of(C_INT, C_POINTER);
        MemorySegment wlProxyGetVersion = loaderLookup.findOrThrow("wl_proxy_get_version");
        wl_proxy_get_version = Linker.nativeLinker().downcallHandle(wlProxyGetVersion, wlProxyGetVersionDescriptor);



        FunctionDescriptor wlProxyDestroyDescriptor = FunctionDescriptor.ofVoid(C_POINTER);
        MemorySegment wlProxyDestroy = loaderLookup.findOrThrow("wl_proxy_destroy");
        wl_proxy_destroy = Linker.nativeLinker().downcallHandle(wlProxyDestroy, wlProxyDestroyDescriptor);



        GroupLayout wlMessageLayout = MemoryLayout.structLayout(
                C_POINTER.withName("name"),
                C_POINTER.withName("signature"),
                C_POINTER.withName("types")
        );
        GroupLayout wlInterfaceLayout = MemoryLayout.structLayout(
                C_POINTER.withName("name"),
                C_INT.withName("version"),
                C_INT.withName("method_count"),
                C_POINTER.withName("methods"),
                C_INT.withName("event_count"),
                MemoryLayout.paddingLayout(4),
                C_POINTER.withName("events")
        );

        MemorySegment appmenu_types = Arena.global().allocate(C_POINTER, 4);
        appmenu_types.setAtIndex(C_POINTER, 0, NULL);
        appmenu_types.setAtIndex(C_POINTER, 1, NULL);
        appmenu_types.setAtIndex(C_POINTER, 3, loaderLookup.findOrThrow("wl_surface_interface"));



        MemorySegment org_kde_kwin_appmenu_requests = Arena.global().allocate(wlMessageLayout, 2);
        wlMessageLayout.varHandle(groupElement("name")).set(org_kde_kwin_appmenu_requests, 0, Arena.global().allocateFrom("set_address"));
        wlMessageLayout.varHandle(groupElement("signature")).set(org_kde_kwin_appmenu_requests, 0, Arena.global().allocateFrom("ss"));
        wlMessageLayout.varHandle(groupElement("types")).set(org_kde_kwin_appmenu_requests, 0, appmenu_types);
        wlMessageLayout.varHandle(groupElement("name")).set(org_kde_kwin_appmenu_requests, wlMessageLayout.byteSize(), Arena.global().allocateFrom("release"));
        wlMessageLayout.varHandle(groupElement("signature")).set(org_kde_kwin_appmenu_requests, wlMessageLayout.byteSize(), Arena.global().allocateFrom(""));
        wlMessageLayout.varHandle(groupElement("types")).set(org_kde_kwin_appmenu_requests, wlMessageLayout.byteSize(), appmenu_types);



        org_kde_kwin_appmenu_interface = Arena.global().allocate(wlInterfaceLayout);
        wlInterfaceLayout.varHandle(groupElement("name")).set(org_kde_kwin_appmenu_interface, 0, Arena.global().allocateFrom("org_kde_kwin_appmenu"));
        wlInterfaceLayout.varHandle(groupElement("version")).set(org_kde_kwin_appmenu_interface, 0, 1);
        wlInterfaceLayout.varHandle(groupElement("method_count")).set(org_kde_kwin_appmenu_interface, 0, 2);
        wlInterfaceLayout.varHandle(groupElement("methods")).set(org_kde_kwin_appmenu_interface, 0, org_kde_kwin_appmenu_requests);
        wlInterfaceLayout.varHandle(groupElement("event_count")).set(org_kde_kwin_appmenu_interface, 0, 0);
        wlInterfaceLayout.varHandle(groupElement("events")).set(org_kde_kwin_appmenu_interface, 0, NULL);
        appmenu_types.setAtIndex(C_POINTER, 2, org_kde_kwin_appmenu_interface);



        MemorySegment org_kde_kwin_appmenu_manager_requests = Arena.global().allocate(wlMessageLayout);
        wlMessageLayout.varHandle(groupElement("name")).set(org_kde_kwin_appmenu_manager_requests, 0, Arena.global().allocateFrom("create"));
        wlMessageLayout.varHandle(groupElement("signature")).set(org_kde_kwin_appmenu_manager_requests, 0, Arena.global().allocateFrom("no"));
        wlMessageLayout.varHandle(groupElement("types")).set(org_kde_kwin_appmenu_manager_requests, 0, appmenu_types.asSlice(2 * C_POINTER.byteSize()));



        org_kde_kwin_appmenu_manager_interface = Arena.global().allocate(wlInterfaceLayout);
        wlInterfaceLayout.varHandle(groupElement("name")).set(org_kde_kwin_appmenu_manager_interface, 0, Arena.global().allocateFrom("org_kde_kwin_appmenu_manager"));
        wlInterfaceLayout.varHandle(groupElement("version")).set(org_kde_kwin_appmenu_manager_interface, 0, 1);
        wlInterfaceLayout.varHandle(groupElement("method_count")).set(org_kde_kwin_appmenu_manager_interface, 0, 1);
        wlInterfaceLayout.varHandle(groupElement("methods")).set(org_kde_kwin_appmenu_manager_interface, 0, org_kde_kwin_appmenu_manager_requests);
        wlInterfaceLayout.varHandle(groupElement("event_count")).set(org_kde_kwin_appmenu_manager_interface, 0, 0);
        wlInterfaceLayout.varHandle(groupElement("events")).set(org_kde_kwin_appmenu_manager_interface, 0, NULL);



        MemorySegment wl_display = MemorySegment.ofAddress(displayPtr);
        MemorySegment wl_registry_interface = loaderLookup.findOrThrow("wl_registry_interface");
        // Soft Graphite fix: the toolkit thread dispatches the display's default queue
        // concurrently. A registry created there can lose its global events before the
        // listener below is attached, so the appmenu manager was never bound. Use a
        // private queue through a display wrapper, as libwayland recommends.
        MemorySegment queue = (MemorySegment) nativeLinker.downcallHandle(loaderLookup.findOrThrow("wl_display_create_queue"),
                FunctionDescriptor.of(C_POINTER, C_POINTER)).invoke(wl_display);
        MemorySegment displayWrapper = (MemorySegment) nativeLinker.downcallHandle(loaderLookup.findOrThrow("wl_proxy_create_wrapper"),
                FunctionDescriptor.of(C_POINTER, C_POINTER)).invoke(wl_display);
        nativeLinker.downcallHandle(loaderLookup.findOrThrow("wl_proxy_set_queue"),
                FunctionDescriptor.ofVoid(C_POINTER, C_POINTER)).invoke(displayWrapper, queue);
        MemorySegment wlRegistry = (MemorySegment) wl_proxy_marshal_flags_1ptr.invoke(displayWrapper, WL_DISPLAY_GET_REGISTRY, wl_registry_interface, wl_proxy_get_version.invoke(displayWrapper), 0, NULL);
        nativeLinker.downcallHandle(loaderLookup.findOrThrow("wl_proxy_wrapper_destroy"),
                FunctionDescriptor.ofVoid(C_POINTER)).invoke(displayWrapper);
        if (wlRegistry == null || wlRegistry.equals(NULL)) {
            throw new IllegalStateException("Failed to get wl_registry from display pointer");
        }



        GroupLayout wlRegistryListenerLayout = MemoryLayout.structLayout(
                C_POINTER.withName("global"),
                C_POINTER.withName("global_remove")
        ).withName("wl_registry_listener");
        VarHandle globalHandle = wlRegistryListenerLayout.varHandle(groupElement("global"));
        FunctionDescriptor globalDescriptor = FunctionDescriptor.ofVoid(C_POINTER, C_POINTER, C_INT, C_POINTER, C_INT);
        VarHandle globalRemoveHandle = wlRegistryListenerLayout.varHandle(groupElement("global_remove"));
        FunctionDescriptor globalRemoveDescriptor = FunctionDescriptor.ofVoid(C_POINTER, C_POINTER, C_INT);
        MemorySegment wlRegistryListener = Arena.global().allocate(wlRegistryListenerLayout);
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        MethodHandle globalMH = lookup.findStatic(WaylandPanama.class, "registryGlobal", MethodType.methodType(void.class, MemorySegment.class, MemorySegment.class, int.class, MemorySegment.class, int.class));
        globalHandle.set(wlRegistryListener, 0, nativeLinker.upcallStub(globalMH, globalDescriptor, Arena.global()));
        MethodHandle globalRemoveMH = lookup.findStatic(WaylandPanama.class, "registryGlobalRemove", MethodType.methodType(void.class, MemorySegment.class, MemorySegment.class, int.class));
        globalRemoveHandle.set(wlRegistryListener, 0, nativeLinker.upcallStub(globalRemoveMH, globalRemoveDescriptor, Arena.global()));



        FunctionDescriptor wlRegistryAddListenerDescriptor = FunctionDescriptor.of(C_INT, C_POINTER, C_POINTER, C_POINTER);
        MemorySegment wlRegistryAddListener = loaderLookup.findOrThrow("wl_proxy_add_listener");
        nativeLinker.downcallHandle(wlRegistryAddListener, wlRegistryAddListenerDescriptor)
                .invoke(wlRegistry, wlRegistryListener, NULL);



        FunctionDescriptor wlDisplayRoundtripDescriptor = FunctionDescriptor.of(C_INT, C_POINTER, C_POINTER);
        MemorySegment wlDisplayRoundtrip = loaderLookup.findOrThrow("wl_display_roundtrip_queue");
        int roundtripResult = (int) nativeLinker.downcallHandle(wlDisplayRoundtrip, wlDisplayRoundtripDescriptor)
                .invoke(wl_display, queue);
        if (roundtripResult < 0) {
            throw new RuntimeException("Failed to roundtrip");
        }
        // The bound manager outlives the registry; nobody dispatches the private queue later.
        wl_proxy_destroy.invoke(wlRegistry);

        isInitialized = true;
    }

    // Present in the published 1.4.1 jar (used by its settings page), absent from the tag source.
    public static boolean isInitialized() {
        return isInitialized;
    }

    public static void ensureInitialized() {
        if (!isInitialized) {
            throw new IllegalStateException("PeerMenuExport must be initialized with PeerMenuExport.init before exporting a menu (and also before showing any UI)");
        }
    }

    private static MemorySegment org_kde_kwin_appmenu_manager;
    private static void registryGlobal(MemorySegment data, MemorySegment registry, int name, MemorySegment interfaceName, int version) {
        String interfaceNameString = interfaceName.getString(0);
        try {
            switch (interfaceNameString) {
                case "org_kde_kwin_appmenu_manager" -> org_kde_kwin_appmenu_manager = (MemorySegment) wl_proxy_marshal_flags_registry_bind.invoke(registry, WL_REGISTRY_BIND, org_kde_kwin_appmenu_manager_interface, 1, 0, name, interfaceName, 1, NULL);
                default -> LOG.log(System.Logger.Level.DEBUG, "Ignoring interface:" + interfaceNameString);
            }
        } catch (Throwable e) {
            LOG.log(System.Logger.Level.ERROR, "Failed to bind interface: " + interfaceNameString, e);
        }
    }

    private static void registryGlobalRemove(MemorySegment data, MemorySegment registry, int name) {
        LOG.log(System.Logger.Level.INFO, "registryGlobalRemove");
    }

    private static MemorySegment org_kde_kwin_appmenu_manager_create(MemorySegment org_kde_kwin_appmenu_manager, MemorySegment surface) throws Throwable {
        return (MemorySegment) wl_proxy_marshal_flags_2ptr.invoke(org_kde_kwin_appmenu_manager,
                ORG_KDE_KWIN_APPMENU_MANAGER_CREATE, org_kde_kwin_appmenu_interface, wl_proxy_get_version.invoke(org_kde_kwin_appmenu_manager), 0, NULL, surface);
    }

    private static void org_kde_kwin_appmenu_set_address(MemorySegment org_kde_kwin_appmenu, MemorySegment service_name, MemorySegment object_path) throws Throwable {
        wl_proxy_marshal_flags_2ptr.invoke(org_kde_kwin_appmenu,
                ORG_KDE_KWIN_APPMENU_SET_ADDRESS, NULL, wl_proxy_get_version.invoke(org_kde_kwin_appmenu), 0, service_name, object_path);
    }

    private static void org_kde_kwin_appmenu_release(MemorySegment org_kde_kwin_appmenu) throws Throwable {
        wl_proxy_marshal_flags.invoke(org_kde_kwin_appmenu,
                ORG_KDE_KWIN_APPMENU_RELEASE, NULL, wl_proxy_get_version.invoke(org_kde_kwin_appmenu), WL_MARSHAL_FLAG_DESTROY);
    }

    private static void org_kde_kwin_appmenu_destroy(MemorySegment org_kde_kwin_appmenu) throws Throwable {
        wl_proxy_destroy.invoke(org_kde_kwin_appmenu);
    }

    public static boolean isMenuSupported() {
        ensureInitialized();
        return org_kde_kwin_appmenu_manager != null;
    }

    public static long createMenu(long wlSurfacePtr) {
        ensureInitialized();
        if (org_kde_kwin_appmenu_manager == null) {
            throw new RuntimeException("Appmenu manager not initialized");
        }
        MemorySegment result;
        try {
            result = org_kde_kwin_appmenu_manager_create(org_kde_kwin_appmenu_manager, MemorySegment.ofAddress(wlSurfacePtr));
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
        return result.address();
    }

    public static void destroyMenu(long menuPtr) {
        ensureInitialized();
        try {
            org_kde_kwin_appmenu_release(MemorySegment.ofAddress(menuPtr));
            org_kde_kwin_appmenu_destroy(MemorySegment.ofAddress(menuPtr));
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    public static void setMenuAddress(long menuPtr, String serviceName, String objectPath) {
        try (Arena scoped = Arena.ofConfined()) {
            MemorySegment serviceNamePtr = scoped.allocateFrom(serviceName);
            MemorySegment objectPathPtr = scoped.allocateFrom(objectPath);
            org_kde_kwin_appmenu_set_address(MemorySegment.ofAddress(menuPtr), serviceNamePtr, objectPathPtr);
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }
}
