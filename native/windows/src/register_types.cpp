#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/godot.hpp>

#include "windows_window_activator.h"

using namespace godot;

void initialize_open_desktop_pet_windows(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(WindowsWindowActivator);
}

void uninitialize_open_desktop_pet_windows(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT open_desktop_pet_windows_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_object(
			p_get_proc_address,
			p_library,
			r_initialization);
	init_object.register_initializer(initialize_open_desktop_pet_windows);
	init_object.register_terminator(uninitialize_open_desktop_pet_windows);
	init_object.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
}
