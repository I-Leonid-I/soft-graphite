#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <dbus/dbus.h>
#include <xcb/xcb.h>

static xcb_connection_t *x_conn = NULL;
static xcb_atom_t atom_service = XCB_ATOM_NONE;
static xcb_atom_t atom_path = XCB_ATOM_NONE;
static xcb_atom_t atom_client_list = XCB_ATOM_NONE;
static xcb_window_t root_win = 0;
static DBusConnection *call_bus = NULL;

static xcb_atom_t get_atom(xcb_connection_t *c, const char *name) {
    xcb_intern_atom_cookie_t cookie = xcb_intern_atom(c, 0, strlen(name), name);
    xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(c, cookie, NULL);
    xcb_atom_t a = reply ? reply->atom : XCB_ATOM_NONE;
    free(reply);
    return a;
}

static void init_xcb(void) {
    if (x_conn && !xcb_connection_has_error(x_conn)) return;
    if (x_conn) xcb_disconnect(x_conn);

    x_conn = xcb_connect(NULL, NULL);
    if (!x_conn || xcb_connection_has_error(x_conn)) {
        x_conn = NULL;
        return;
    }
    const xcb_setup_t *setup = xcb_get_setup(x_conn);
    xcb_screen_iterator_t iter = xcb_setup_roots_iterator(setup);
    if (iter.rem > 0) {
        root_win = iter.data->root;
    }
    atom_service = get_atom(x_conn, "_KDE_NET_WM_APPMENU_SERVICE_NAME");
    atom_path = get_atom(x_conn, "_KDE_NET_WM_APPMENU_OBJECT_PATH");
    atom_client_list = get_atom(x_conn, "_NET_CLIENT_LIST");
}

static void set_window_menu(uint32_t xid, const char *service, const char *path) {
    init_xcb();
    if (!x_conn || !service || !path || !*service || !*path) return;

    xcb_change_property(x_conn, XCB_PROP_MODE_REPLACE, xid, atom_service, XCB_ATOM_STRING, 8, strlen(service), service);
    xcb_change_property(x_conn, XCB_PROP_MODE_REPLACE, xid, atom_path, XCB_ATOM_STRING, 8, strlen(path), path);
    xcb_flush(x_conn);
}

static void unset_window_menu(uint32_t xid) {
    init_xcb();
    if (!x_conn) return;

    xcb_delete_property(x_conn, xid, atom_service);
    xcb_delete_property(x_conn, xid, atom_path);
    xcb_flush(x_conn);
}

static void check_existing_windows(void) {
    if (!call_bus) return;
    init_xcb();
    if (!x_conn || !root_win || !atom_client_list) return;

    xcb_get_property_cookie_t cookie = xcb_get_property(x_conn, 0, root_win, atom_client_list, XCB_ATOM_WINDOW, 0, 2048);
    xcb_get_property_reply_t *reply = xcb_get_property_reply(x_conn, cookie, NULL);
    if (!reply) return;

    int num_windows = xcb_get_property_value_length(reply) / sizeof(xcb_window_t);
    xcb_window_t *windows = (xcb_window_t *)xcb_get_property_value(reply);

    for (int i = 0; i < num_windows; i++) {
        uint32_t xid = windows[i];
        DBusMessage *msg = dbus_message_new_method_call(
            "com.canonical.AppMenu.Registrar",
            "/com/canonical/AppMenu/Registrar",
            "com.canonical.AppMenu.Registrar",
            "GetMenuForWindow"
        );
        if (!msg) continue;
        dbus_message_append_args(msg, DBUS_TYPE_UINT32, &xid, DBUS_TYPE_INVALID);

        DBusError err;
        dbus_error_init(&err);
        DBusMessage *reply_msg = dbus_connection_send_with_reply_and_block(call_bus, msg, 400, &err);
        dbus_message_unref(msg);

        if (reply_msg) {
            const char *service = NULL;
            const char *path = NULL;
            if (dbus_message_get_args(reply_msg, &err, DBUS_TYPE_STRING, &service, DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_INVALID)) {
                if (service && path && strlen(service) > 0 && strlen(path) > 0) {
                    set_window_menu(xid, service, path);
                }
            }
            dbus_message_unref(reply_msg);
        }
        dbus_error_free(&err);
    }
    free(reply);
}

int main(void) {
    // Default SIGTERM/SIGINT handling: the process holds nothing that needs cleanup,
    // and it lets the loop below block without a wake-up timer.
    signal(SIGPIPE, SIG_IGN);

    init_xcb();

    DBusError err;
    dbus_error_init(&err);

    // Call bus for standard method calls (GetMenuForWindow)
    call_bus = dbus_bus_get_private(DBUS_BUS_SESSION, &err);
    if (!call_bus || dbus_error_is_set(&err)) {
        fprintf(stderr, "appmenu-bridge: call_bus error: %s\n", err.message ? err.message : "unknown");
        return 1;
    }

    // Monitor bus for capturing RegisterWindow calls
    dbus_error_init(&err);
    DBusConnection *mon_bus = dbus_bus_get_private(DBUS_BUS_SESSION, &err);
    if (!mon_bus || dbus_error_is_set(&err)) {
        fprintf(stderr, "appmenu-bridge: mon_bus error: %s\n", err.message ? err.message : "unknown");
        return 1;
    }

    // Populate existing windows on startup
    check_existing_windows();

    // Register monitor
    DBusMessage *mon_msg = dbus_message_new_method_call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus.Monitoring",
        "BecomeMonitor"
    );
    if (!mon_msg) return 1;

    const char *rules[] = {
        "type='method_call',interface='com.canonical.AppMenu.Registrar',member='RegisterWindow'",
        "type='method_call',interface='com.canonical.AppMenu.Registrar',member='UnregisterWindow'",
        "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='com.canonical.AppMenu.Registrar'"
    };
    int num_rules = sizeof(rules) / sizeof(rules[0]);
    uint32_t flags = 0;

    DBusMessageIter iter, arr_iter;
    dbus_message_iter_init_append(mon_msg, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &arr_iter);
    for (int i = 0; i < num_rules; i++) {
        dbus_message_iter_append_basic(&arr_iter, DBUS_TYPE_STRING, &rules[i]);
    }
    dbus_message_iter_close_container(&iter, &arr_iter);
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &flags);

    DBusMessage *mon_reply = dbus_connection_send_with_reply_and_block(mon_bus, mon_msg, 2000, &err);
    dbus_message_unref(mon_msg);
    if (!mon_reply || dbus_error_is_set(&err)) {
        fprintf(stderr, "appmenu-bridge: BecomeMonitor failed: %s\n", err.message ? err.message : "unknown");
        return 1;
    }
    dbus_message_unref(mon_reply);

    while (dbus_connection_read_write_dispatch(mon_bus, -1)) {
        DBusMessage *msg;
        while ((msg = dbus_connection_pop_message(mon_bus)) != NULL) {
            if (dbus_message_is_method_call(msg, "com.canonical.AppMenu.Registrar", "RegisterWindow")) {
                const char *sender = dbus_message_get_sender(msg);
                uint32_t xid = 0;
                const char *path = NULL;
                DBusError arg_err;
                dbus_error_init(&arg_err);
                if (dbus_message_get_args(msg, &arg_err, DBUS_TYPE_UINT32, &xid, DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_INVALID)) {
                    if (sender && path && xid) {
                        set_window_menu(xid, sender, path);
                    }
                }
                dbus_error_free(&arg_err);
            } else if (dbus_message_is_method_call(msg, "com.canonical.AppMenu.Registrar", "UnregisterWindow")) {
                uint32_t xid = 0;
                DBusError arg_err;
                dbus_error_init(&arg_err);
                if (dbus_message_get_args(msg, &arg_err, DBUS_TYPE_UINT32, &xid, DBUS_TYPE_INVALID)) {
                    if (xid) {
                        unset_window_menu(xid);
                    }
                }
                dbus_error_free(&arg_err);
            } else if (dbus_message_is_signal(msg, "org.freedesktop.DBus", "NameOwnerChanged")) {
                const char *name = NULL, *old_owner = NULL, *new_owner = NULL;
                DBusError arg_err;
                dbus_error_init(&arg_err);
                if (dbus_message_get_args(msg, &arg_err, DBUS_TYPE_STRING, &name, DBUS_TYPE_STRING, &old_owner, DBUS_TYPE_STRING, &new_owner, DBUS_TYPE_INVALID)) {
                    if (new_owner && strlen(new_owner) > 0) {
                        check_existing_windows();
                    }
                }
                dbus_error_free(&arg_err);
            }
            dbus_message_unref(msg);
        }
    }

    if (x_conn) xcb_disconnect(x_conn);
    if (call_bus) { dbus_connection_close(call_bus); dbus_connection_unref(call_bus); }
    if (mon_bus) { dbus_connection_close(mon_bus); dbus_connection_unref(mon_bus); }
    return 0;
}
