#include "windows_window_activator.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

#include <godot_cpp/core/class_db.hpp>

namespace godot {
namespace {

struct WindowSearchContext {
	std::wstring executable_path;
	std::vector<HWND> matches;
};

std::wstring normalize_path(std::wstring p_path) {
	std::replace(p_path.begin(), p_path.end(), L'/', L'\\');
	DWORD required_size = GetFullPathNameW(p_path.c_str(), 0, nullptr, nullptr);
	if (required_size > 0) {
		std::vector<wchar_t> buffer(required_size);
		if (GetFullPathNameW(p_path.c_str(), required_size, buffer.data(), nullptr) > 0) {
			p_path.assign(buffer.data());
		}
	}
	std::transform(p_path.begin(), p_path.end(), p_path.begin(), towlower);
	return p_path;
}

std::wstring executable_path_from_string(const String &p_executable_path) {
	const Char16String utf16_path = p_executable_path.utf16();
	return normalize_path(std::wstring(
			reinterpret_cast<const wchar_t *>(utf16_path.ptr())));
}

std::wstring process_path_for_window(HWND p_window) {
	DWORD process_id = 0;
	GetWindowThreadProcessId(p_window, &process_id);
	if (process_id == 0) {
		return {};
	}

	HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
	if (process == nullptr) {
		return {};
	}

	std::vector<wchar_t> buffer(32768);
	DWORD size = static_cast<DWORD>(buffer.size());
	std::wstring result;
	if (QueryFullProcessImageNameW(process, 0, buffer.data(), &size) != FALSE) {
		result.assign(buffer.data(), size);
	}
	CloseHandle(process);
	return normalize_path(result);
}

BOOL CALLBACK collect_matching_windows(HWND p_window, LPARAM p_parameter) {
	auto *context = reinterpret_cast<WindowSearchContext *>(p_parameter);
	if (!IsWindowVisible(p_window) || GetAncestor(p_window, GA_ROOT) != p_window) {
		return TRUE;
	}
	if (GetWindow(p_window, GW_OWNER) != nullptr) {
		return TRUE;
	}
	const LONG_PTR extended_style = GetWindowLongPtrW(p_window, GWL_EXSTYLE);
	if ((extended_style & WS_EX_TOOLWINDOW) != 0 || GetWindowTextLengthW(p_window) == 0) {
		return TRUE;
	}
	if (process_path_for_window(p_window) == context->executable_path) {
		context->matches.push_back(p_window);
	}
	return TRUE;
}

std::vector<HWND> find_windows(const std::wstring &p_executable_path) {
	WindowSearchContext context{ p_executable_path, {} };
	EnumWindows(collect_matching_windows, reinterpret_cast<LPARAM>(&context));
	return context.matches;
}

bool activate_window(HWND p_window) {
	if (IsIconic(p_window)) {
		ShowWindowAsync(p_window, SW_RESTORE);
	}

	const DWORD current_thread = GetCurrentThreadId();
	const DWORD target_thread = GetWindowThreadProcessId(p_window, nullptr);
	HWND foreground_window = GetForegroundWindow();
	const DWORD foreground_thread = foreground_window != nullptr
			? GetWindowThreadProcessId(foreground_window, nullptr)
			: 0;

	bool attached_foreground = false;
	bool attached_target = false;
	if (foreground_thread != 0 && foreground_thread != current_thread) {
		attached_foreground = AttachThreadInput(current_thread, foreground_thread, TRUE) != FALSE;
	}
	if (target_thread != 0 && target_thread != current_thread && target_thread != foreground_thread) {
		attached_target = AttachThreadInput(current_thread, target_thread, TRUE) != FALSE;
	}

	BringWindowToTop(p_window);
	SetForegroundWindow(p_window);
	SetActiveWindow(p_window);

	if (attached_target) {
		AttachThreadInput(current_thread, target_thread, FALSE);
	}
	if (attached_foreground) {
		AttachThreadInput(current_thread, foreground_thread, FALSE);
	}

	return GetForegroundWindow() == p_window;
}

} // namespace

void WindowsWindowActivator::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("focus_executable", "executable_path", "timeout_msec"),
			&WindowsWindowActivator::focus_executable,
			DEFVAL(750));
	ClassDB::bind_method(
			D_METHOD("is_executable_foreground", "executable_path"),
			&WindowsWindowActivator::is_executable_foreground);
	ClassDB::bind_method(
			D_METHOD("get_last_error"),
			&WindowsWindowActivator::get_last_error);
}

bool WindowsWindowActivator::focus_executable(
		const String &p_executable_path,
		int p_timeout_msec) {
	last_error = "";
	if (p_executable_path.is_empty()) {
		last_error = "Executable path is empty.";
		return false;
	}

	const std::wstring executable_path = executable_path_from_string(
			p_executable_path);
	const ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(
			std::max(0, p_timeout_msec));

	do {
		const std::vector<HWND> windows = find_windows(executable_path);
		for (HWND window : windows) {
			if (activate_window(window)) {
				return true;
			}
		}
		if (GetTickCount64() >= deadline) {
			break;
		}
		Sleep(25);
	} while (true);

	last_error = "No matching VS Code window could be activated.";
	return false;
}

bool WindowsWindowActivator::is_executable_foreground(
		const String &p_executable_path) const {
	if (p_executable_path.is_empty()) {
		return false;
	}
	HWND foreground_window = GetForegroundWindow();
	if (foreground_window == nullptr) {
		return false;
	}
	return process_path_for_window(foreground_window) ==
			executable_path_from_string(p_executable_path);
}

String WindowsWindowActivator::get_last_error() const {
	return last_error;
}

} // namespace godot
