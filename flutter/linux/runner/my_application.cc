#include "my_application.h"

#include <cstring>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The app's own channel (org.uwuapps.board/desktop, lib/desktop/runner.dart): here, only native
  // glass's window (lib/desktop/backdrop.dart).
  FlMethodChannel* channel;
  GtkWindow* window;
  // Whether the compositor blurs behind a see-through window, and whether it's asked to now.
  gboolean can_blur;
  gboolean blur_on;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Native glass on Linux: a see-through window, with the compositor asked to blur what's behind
// it. Deepin's (DDE's) and KDE's window managers do, under X11, when told by a property on the
// window. Elsewhere (COSMIC, GNOME, any Wayland session) the window stays solid and the app
// frosts its own glass inside it.
static gboolean desktop_blurs(GtkWindow* window) {
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (!GDK_IS_X11_SCREEN(screen) || !gdk_screen_is_composited(screen)) return FALSE;
  if (gdk_screen_get_rgba_visual(screen) == nullptr) return FALSE;
  const gchar* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  if (desktop == nullptr) return FALSE;
  g_autofree gchar* name = g_ascii_strup(desktop, -1);
  return strstr(name, "DEEPIN") != nullptr || strstr(name, "DDE") != nullptr || strstr(name, "KDE") != nullptr;
#else
  return FALSE;
#endif
}

// The blur's properties on the window, or none: KDE's (empty, for the whole window), and
// Deepin's own, which names the region, so it's set again whenever the window changes size.
static void update_blur(MyApplication* self) {
#ifdef GDK_WINDOWING_X11
  if (self->window == nullptr) return;
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(self->window));
  if (gdk_window == nullptr || !GDK_IS_X11_WINDOW(gdk_window)) return;
  GdkAtom kde = gdk_atom_intern_static_string("_KDE_NET_WM_BLUR_BEHIND_REGION");
  GdkAtom deepin = gdk_atom_intern_static_string("_NET_WM_DEEPIN_BLUR_REGION_ROUNDED");
  if (!self->blur_on) {
    gdk_property_delete(gdk_window, kde);
    gdk_property_delete(gdk_window, deepin);
    return;
  }
  GdkAtom cardinal = gdk_atom_intern_static_string("CARDINAL");
  gulong whole[1] = {0};
  gdk_property_change(gdk_window, kde, cardinal, 32, GDK_PROP_MODE_REPLACE,
                      reinterpret_cast<const guchar*>(whole), 0);
  const int scale = gdk_window_get_scale_factor(gdk_window);
  // x, y, width, height, and the corners' x and y radii, in the screen's pixels.
  gulong region[6] = {0, 0, static_cast<gulong>(gdk_window_get_width(gdk_window) * scale),
                      static_cast<gulong>(gdk_window_get_height(gdk_window) * scale), 0, 0};
  gdk_property_change(gdk_window, deepin, cardinal, 32, GDK_PROP_MODE_REPLACE,
                      reinterpret_cast<const guchar*>(region), 6);
#endif
}

static gboolean window_configured_cb(GtkWidget* widget, GdkEvent* event, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->blur_on) update_blur(self);
  return FALSE;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "setBackdrop") == 0) {
    const gchar* kind = "none";
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "kind");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) kind = fl_value_get_string(value);
    }
    self->blur_on = self->can_blur && strcmp(kind, "none") != 0;
    update_blur(self);
    g_autoptr(FlValue) result = fl_value_new_bool(self->blur_on);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // The app draws its own title bar (lib/desktop/chrome.dart), so no header bar here.
  gtk_window_set_title(window, "uwuBoard");

  gtk_window_set_default_size(window, 1120, 760);

  // A window with an alpha channel, where the compositor can blur behind it: before it's
  // realised, as the visual can't change after.
  self->window = window;
  self->can_blur = desktop_blurs(window);
  if (self->can_blur) {
    gtk_widget_set_visual(GTK_WIDGET(window), gdk_screen_get_rgba_visual(gtk_window_get_screen(window)));
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
    g_signal_connect(window, "configure-event", G_CALLBACK(window_configured_cb), self);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Black, or see-through where native glass can show the blurred desktop: the app paints its
  // own page over it either way, except in native glass.
  gdk_rgba_parse(&background_color, self->can_blur ? "rgba(0,0,0,0)" : "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
                                        "org.uwuapps.board/desktop", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self, nullptr);
  // Each desktop widget is a window with an engine of its own: it gets the same plugins.
  desktop_multi_window_plugin_set_window_created_callback([](FlPluginRegistry* registry) {
    fl_register_plugins(registry);
  });

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->channel);
  self->window = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
