#include "windows_ime_char_repair.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <commctrl.h>

#include <godot_cpp/core/class_db.hpp>

namespace godot {
namespace {

constexpr UINT_PTR SUBCLASS_ID = 0x4f445049; // "ODPI"

struct RepairState {
	// Scan code of a key-down whose WM_CHAR may still follow; 0 when none.
	UINT pending_key_scan = 0;
	bool composing = false;
};

UINT scan_code(LPARAM p_lparam) {
	return static_cast<UINT>((p_lparam >> 16) & 0xFF);
}

// Godot checks WM_CHAR against KeyMappingWindows::is_extended_key(), which
// compares virtual-key codes. These characters share their code points with
// VK_PRIOR..VK_DOWN, VK_INSERT and VK_DELETE, so Godot skips them.
bool is_dropped_character(WPARAM p_character) {
	return (p_character >= 0x21 && p_character <= 0x28) || p_character == 0x2D || p_character == 0x2E;
}

LRESULT CALLBACK repair_window_proc(
		HWND p_window,
		UINT p_message,
		WPARAM p_wparam,
		LPARAM p_lparam,
		UINT_PTR p_subclass_id,
		DWORD_PTR p_reference_data) {
	RepairState *state = reinterpret_cast<RepairState *>(p_reference_data);
	switch (p_message) {
		case WM_KEYDOWN:
		case WM_SYSKEYDOWN:
			// Godot ignores key-downs while composing; they cannot carry a character.
			state->pending_key_scan = state->composing ? 0 : scan_code(p_lparam);
			break;
		case WM_KEYUP:
		case WM_SYSKEYUP:
			state->pending_key_scan = 0;
			break;
		case WM_IME_STARTCOMPOSITION:
			state->composing = true;
			state->pending_key_scan = 0;
			break;
		case WM_IME_ENDCOMPOSITION:
			state->composing = false;
			state->pending_key_scan = 0;
			break;
		case WM_CHAR: {
			// A character translated from a key-down is delivered by that key-down,
			// so only text without one (committed by an IME) needs repair.
			const bool from_key = state->pending_key_scan != 0 && state->pending_key_scan == scan_code(p_lparam);
			state->pending_key_scan = 0;
			if (!from_key && !state->composing && is_dropped_character(p_wparam)) {
				// Godot takes the character for a key-down from the WM_CHAR right
				// after it, without the extended-key check. VK_PROCESSKEY is the key
				// an IME reports, and maps to no Godot action.
				DefSubclassProc(p_window, WM_KEYDOWN, VK_PROCESSKEY, 0);
			}
		} break;
		case WM_NCDESTROY:
			RemoveWindowSubclass(p_window, &repair_window_proc, p_subclass_id);
			delete state;
			return DefSubclassProc(p_window, p_message, p_wparam, p_lparam);
		default:
			break;
	}
	return DefSubclassProc(p_window, p_message, p_wparam, p_lparam);
}

} // namespace

void WindowsImeCharRepair::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "window_handle"), &WindowsImeCharRepair::attach);
	ClassDB::bind_method(D_METHOD("is_attached", "window_handle"), &WindowsImeCharRepair::is_attached);
	ClassDB::bind_method(D_METHOD("get_last_error"), &WindowsImeCharRepair::get_last_error);
}

bool WindowsImeCharRepair::attach(int64_t p_window_handle) {
	last_error = "";
	HWND window = reinterpret_cast<HWND>(p_window_handle);
	if (window == nullptr || !IsWindow(window)) {
		last_error = "The window handle is not valid.";
		return false;
	}
	if (is_attached(p_window_handle)) {
		return true;
	}
	RepairState *state = new RepairState();
	if (!SetWindowSubclass(window, &repair_window_proc, SUBCLASS_ID, reinterpret_cast<DWORD_PTR>(state))) {
		delete state;
		last_error = "SetWindowSubclass failed.";
		return false;
	}
	return true;
}

bool WindowsImeCharRepair::is_attached(int64_t p_window_handle) const {
	HWND window = reinterpret_cast<HWND>(p_window_handle);
	DWORD_PTR reference_data = 0;
	return window != nullptr && IsWindow(window) && GetWindowSubclass(window, &repair_window_proc, SUBCLASS_ID, &reference_data);
}

String WindowsImeCharRepair::get_last_error() const {
	return last_error;
}

} // namespace godot
