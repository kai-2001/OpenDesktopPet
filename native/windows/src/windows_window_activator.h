#ifndef OPEN_DESKTOP_PET_WINDOWS_WINDOW_ACTIVATOR_H
#define OPEN_DESKTOP_PET_WINDOWS_WINDOW_ACTIVATOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class WindowsWindowActivator : public RefCounted {
	GDCLASS(WindowsWindowActivator, RefCounted)

protected:
	static void _bind_methods();

public:
	bool focus_executable(const String &p_executable_path, int p_timeout_msec = 750);
	bool is_executable_foreground(const String &p_executable_path) const;
	String get_last_error() const;

private:
	String last_error;
};

} // namespace godot

#endif
