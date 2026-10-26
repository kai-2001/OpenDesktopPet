#ifndef OPEN_DESKTOP_PET_WINDOWS_IME_CHAR_REPAIR_H
#define OPEN_DESKTOP_PET_WINDOWS_IME_CHAR_REPAIR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Godot 4.6 drops the characters ! " # $ % & ' ( - . when an IME commits them
// (godotengine/godot#74043). This repairs one native window's input.
class WindowsImeCharRepair : public RefCounted {
	GDCLASS(WindowsImeCharRepair, RefCounted)

protected:
	static void _bind_methods();

public:
	bool attach(int64_t p_window_handle);
	bool is_attached(int64_t p_window_handle) const;
	String get_last_error() const;

private:
	String last_error;
};

} // namespace godot

#endif
