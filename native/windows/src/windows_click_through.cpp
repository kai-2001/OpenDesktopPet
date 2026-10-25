#include "windows_click_through.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void WindowsClickThrough::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("set_click_through", "window_handle", "enabled"),
			&WindowsClickThrough::set_click_through);
	ClassDB::bind_method(
			D_METHOD("is_click_through", "window_handle"),
			&WindowsClickThrough::is_click_through);
	ClassDB::bind_method(
			D_METHOD("set_opacity", "window_handle", "alpha"),
			&WindowsClickThrough::set_opacity);
	ClassDB::bind_method(
			D_METHOD("get_last_error"),
			&WindowsClickThrough::get_last_error);
}

bool WindowsClickThrough::set_click_through(int64_t p_window_handle, bool p_enabled) {
	last_error = "";
	HWND window = reinterpret_cast<HWND>(p_window_handle);
	if (window == nullptr || !IsWindow(window)) {
		last_error = "The window handle is not valid.";
		return false;
	}
	const LONG_PTR current_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
	// Windows only lets clicks fall through to other processes when a window is
	// both layered and transparent. The layered bit stays on so toggling input
	// never recreates the redirection surface; Godot may still drop it when it
	// rebuilds the window style, so it is restored here on every call.
	LONG_PTR desired_style = current_style | WS_EX_LAYERED;
	if (p_enabled) {
		desired_style |= WS_EX_TRANSPARENT;
	} else {
		desired_style &= ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT);
	}
	if (desired_style == current_style) {
		return true;
	}
	SetLastError(0);
	if (SetWindowLongPtrW(window, GWL_EXSTYLE, desired_style) == 0 && GetLastError() != 0) {
		last_error = "SetWindowLongPtrW failed.";
		return false;
	}
	if ((current_style & WS_EX_LAYERED) == 0) {
		// A newly layered window is not drawn until its attributes are set.
		if (!SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA)) {
			last_error = "SetLayeredWindowAttributes failed.";
			return false;
		}
	}
	return true;
}

bool WindowsClickThrough::is_click_through(int64_t p_window_handle) const {
	HWND window = reinterpret_cast<HWND>(p_window_handle);
	if (window == nullptr || !IsWindow(window)) {
		return false;
	}
	const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
	return (style & WS_EX_LAYERED) != 0 && (style & WS_EX_TRANSPARENT) != 0;
}

bool WindowsClickThrough::set_opacity(int64_t p_window_handle, int p_alpha) {
	last_error = "";
	HWND window = reinterpret_cast<HWND>(p_window_handle);
	if (window == nullptr || !IsWindow(window)) {
		last_error = "The window handle is not valid.";
		return false;
	}
	// Whole-window opacity needs the layered style; keep it, as above.
	const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
	if ((style & WS_EX_LAYERED) == 0) {
		SetLastError(0);
		if (SetWindowLongPtrW(window, GWL_EXSTYLE, style | WS_EX_LAYERED) == 0 && GetLastError() != 0) {
			last_error = "SetWindowLongPtrW failed.";
			return false;
		}
	}
	const BYTE alpha = static_cast<BYTE>(p_alpha < 0 ? 0 : (p_alpha > 255 ? 255 : p_alpha));
	if (!SetLayeredWindowAttributes(window, 0, alpha, LWA_ALPHA)) {
		last_error = "SetLayeredWindowAttributes failed.";
		return false;
	}
	return true;
}

String WindowsClickThrough::get_last_error() const {
	return last_error;
}

} // namespace godot
