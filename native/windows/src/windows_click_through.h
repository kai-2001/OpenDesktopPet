#ifndef OPEN_DESKTOP_PET_WINDOWS_CLICK_THROUGH_H
#define OPEN_DESKTOP_PET_WINDOWS_CLICK_THROUGH_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class WindowsClickThrough : public RefCounted {
	GDCLASS(WindowsClickThrough, RefCounted)

protected:
	static void _bind_methods();

public:
	bool set_click_through(int64_t p_window_handle, bool p_enabled);
	bool is_click_through(int64_t p_window_handle) const;
	bool set_opacity(int64_t p_window_handle, int p_alpha);
	String get_last_error() const;

private:
	String last_error;
};

} // namespace godot

#endif
