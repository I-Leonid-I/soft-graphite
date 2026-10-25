cmake_minimum_required(VERSION 3.28)

project(appmenu-gtk-module-wayland)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(DBUSMENU_GTK3 REQUIRED IMPORTED_TARGET dbusmenu-gtk3-0.4)
pkg_check_modules(DBUSMENU_GLIB REQUIRED IMPORTED_TARGET dbusmenu-glib-0.4)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(GMODULE REQUIRED IMPORTED_TARGET gmodule-2.0)
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)

set(CMAKE_C_STANDARD 11)

set(SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src")
set(LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
set(GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/wayland/generated")

add_library(appmenu-gtk-module-wayland  SHARED
    "${SRC_DIR}/appmenu-gtk-module.c"
    "${SRC_DIR}/datastructs.c"
    "${SRC_DIR}/hijack.c"
    "${SRC_DIR}/support.c"
    "${SRC_DIR}/blacklist.c"
    "${SRC_DIR}/platform.c"
    "${GENERATED_DIR}/appmenu.c"
    "${LIB_DIR}/unity-gtk-menu-item.c"
    "${LIB_DIR}/unity-gtk-menu-shell.c"
    "${LIB_DIR}/unity-gtk-action-group.c"
    "${LIB_DIR}/unity-gtk-action.c"
    "${LIB_DIR}/unity-gtk-menu-section.c"
)

target_include_directories(appmenu-gtk-module-wayland PRIVATE "${GENERATED_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/lib")
target_link_libraries(appmenu-gtk-module-wayland PkgConfig::GTK3 PkgConfig::DBUSMENU_GTK3 PkgConfig::DBUSMENU_GLIB PkgConfig::WAYLAND_CLIENT PkgConfig::GMODULE PkgConfig::X11)
target_link_options(appmenu-gtk-module-wayland PRIVATE "LINKER:-z,defs")
set_target_properties(appmenu-gtk-module-wayland PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE INSTALL_RPATH "$ORIGIN/../..")

option(BUILD_TESTS "Build test applications" OFF)

if(BUILD_TESTS)
    set(TEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")

    add_executable(unity-gtk-menu-tester "${TEST_DIR}/demos/unity-gtk-menu-tester.c")
    target_link_libraries(unity-gtk-menu-tester PkgConfig::GTK3)
endif()
