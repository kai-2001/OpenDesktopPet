#include "windows_display_recovery_monitor.h"

#include <godot_cpp/core/class_db.hpp>

#include <chrono>

namespace godot {
namespace {

constexpr wchar_t WINDOW_CLASS_NAME[] = L"OpenDesktopPetDisplayRecoveryMonitor";

using RegisterSuspendResumeNotificationFunction = HPOWERNOTIFY(WINAPI *)(HANDLE, DWORD);
using UnregisterSuspendResumeNotificationFunction = WINBOOL(WINAPI *)(HPOWERNOTIFY);

void set_startup_result(
		std::mutex &p_mutex,
		std::condition_variable &p_condition,
		bool &r_complete,
		bool &r_succeeded,
		DWORD &r_error,
		bool p_succeeded,
		DWORD p_error) {
	{
		std::lock_guard<std::mutex> lock(p_mutex);
		r_complete = true;
		r_succeeded = p_succeeded;
		r_error = p_error;
	}
	p_condition.notify_one();
}

} // namespace

void WindowsDisplayRecoveryMonitor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start"), &WindowsDisplayRecoveryMonitor::start);
	ClassDB::bind_method(D_METHOD("stop"), &WindowsDisplayRecoveryMonitor::stop);
	ClassDB::bind_method(D_METHOD("poll_events"), &WindowsDisplayRecoveryMonitor::poll_events);
	ClassDB::bind_method(D_METHOD("get_last_error"), &WindowsDisplayRecoveryMonitor::get_last_error);
}

WindowsDisplayRecoveryMonitor::~WindowsDisplayRecoveryMonitor() {
	stop();
}

bool WindowsDisplayRecoveryMonitor::start() {
	if (message_thread.joinable()) {
		std::lock_guard<std::mutex> lock(startup_mutex);
		return startup_succeeded;
	}

	pending_system_resume.store(false);
	system_was_suspended.store(false);
	startup_complete = false;
	startup_succeeded = false;
	startup_error = ERROR_SUCCESS;
	last_error = String();

	BOOL screensaver_running = FALSE;
	if (SystemParametersInfoW(SPI_GETSCREENSAVERRUNNING, 0, &screensaver_running, 0) != FALSE) {
		screen_saver_was_running = screensaver_running != FALSE;
		screen_saver_state_initialized = true;
	} else {
		screen_saver_state_initialized = false;
	}

	{
		std::lock_guard<std::mutex> lock(startup_mutex);
		message_thread = std::thread(&WindowsDisplayRecoveryMonitor::_message_thread_main, this);
	}

	std::unique_lock<std::mutex> lock(startup_mutex);
	const bool finished = startup_condition.wait_for(
			lock,
			std::chrono::seconds(5),
			[this]() { return startup_complete; });
	if (!finished) {
		startup_error = WAIT_TIMEOUT;
		last_error = "Timed out while starting the Windows power-event listener.";
		lock.unlock();
		stop();
		return false;
	}

	if (!startup_succeeded) {
		const DWORD error = startup_error;
		last_error = String("Windows power-event listener could not start (Win32 error ")
				+ String::num_int64(error) + String(").");
	}
	return startup_succeeded;
}

void WindowsDisplayRecoveryMonitor::stop() {
	if (!message_thread.joinable()) {
		return;
	}
	const DWORD thread_id = message_thread_id.load();
	if (thread_id != 0) {
		PostThreadMessageW(thread_id, WM_QUIT, 0, 0);
	}
	message_thread.join();
	message_thread_id.store(0);
}

Dictionary WindowsDisplayRecoveryMonitor::poll_events() {
	Dictionary events;
	bool screensaver_started = false;
	bool screensaver_ended = false;
	BOOL screensaver_running = FALSE;
	if (SystemParametersInfoW(SPI_GETSCREENSAVERRUNNING, 0, &screensaver_running, 0) != FALSE) {
		const bool is_running = screensaver_running != FALSE;
		if (screen_saver_state_initialized) {
			screensaver_started = !screen_saver_was_running && is_running;
			screensaver_ended = screen_saver_was_running && !is_running;
		}
		screen_saver_was_running = is_running;
		screen_saver_state_initialized = true;
	}

	events["screensaver_started"] = screensaver_started;
	events["screensaver_ended"] = screensaver_ended;
	events["system_resumed"] = pending_system_resume.exchange(false);
	events["system_was_suspended"] = system_was_suspended.exchange(false);
	return events;
}

String WindowsDisplayRecoveryMonitor::get_last_error() const {
	return last_error;
}

LRESULT CALLBACK WindowsDisplayRecoveryMonitor::_window_proc(
		HWND p_window,
		UINT p_message,
		WPARAM p_wparam,
		LPARAM p_lparam) {
	WindowsDisplayRecoveryMonitor *monitor = reinterpret_cast<WindowsDisplayRecoveryMonitor *>(
			GetWindowLongPtrW(p_window, GWLP_USERDATA));

	if (p_message == WM_NCCREATE) {
		const CREATESTRUCTW *create_struct = reinterpret_cast<const CREATESTRUCTW *>(p_lparam);
		monitor = static_cast<WindowsDisplayRecoveryMonitor *>(create_struct->lpCreateParams);
		SetWindowLongPtrW(p_window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(monitor));
	}

	if (monitor != nullptr && p_message == WM_POWERBROADCAST) {
		monitor->_handle_power_message(p_wparam);
		return TRUE;
	}

	return DefWindowProcW(p_window, p_message, p_wparam, p_lparam);
}

void WindowsDisplayRecoveryMonitor::_message_thread_main() {
	MSG queue_message;
	PeekMessageW(&queue_message, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
	message_thread_id.store(GetCurrentThreadId());

	WNDCLASSEXW window_class = {};
	window_class.cbSize = sizeof(window_class);
	window_class.lpfnWndProc = &WindowsDisplayRecoveryMonitor::_window_proc;
	window_class.hInstance = GetModuleHandleW(nullptr);
	window_class.lpszClassName = WINDOW_CLASS_NAME;
	if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
		set_startup_result(startup_mutex, startup_condition, startup_complete,
				startup_succeeded, startup_error, false, GetLastError());
		return;
	}

	HWND window = CreateWindowExW(
			0,
			WINDOW_CLASS_NAME,
			WINDOW_CLASS_NAME,
			WS_POPUP,
			0, 0, 0, 0,
			nullptr,
			nullptr,
			GetModuleHandleW(nullptr),
			this);
	if (window == nullptr) {
		set_startup_result(startup_mutex, startup_condition, startup_complete,
				startup_succeeded, startup_error, false, GetLastError());
		return;
	}

	HMODULE user32 = GetModuleHandleW(L"user32.dll");
	if (user32 == nullptr) {
		const DWORD error = GetLastError();
		DestroyWindow(window);
		set_startup_result(startup_mutex, startup_condition, startup_complete,
				startup_succeeded, startup_error, false, error);
		return;
	}
	const auto register_notification = reinterpret_cast<RegisterSuspendResumeNotificationFunction>(
		GetProcAddress(user32, "RegisterSuspendResumeNotification"));
	if (register_notification == nullptr) {
		const DWORD error = GetLastError();
		DestroyWindow(window);
		set_startup_result(startup_mutex, startup_condition, startup_complete,
				startup_succeeded, startup_error, false, error);
		return;
	}

	HPOWERNOTIFY notification = register_notification(window, DEVICE_NOTIFY_WINDOW_HANDLE);
	if (notification == nullptr) {
		const DWORD error = GetLastError();
		DestroyWindow(window);
		set_startup_result(startup_mutex, startup_condition, startup_complete,
				startup_succeeded, startup_error, false, error);
		return;
	}

	set_startup_result(startup_mutex, startup_condition, startup_complete,
			startup_succeeded, startup_error, true, ERROR_SUCCESS);

	MSG message;
	while (GetMessageW(&message, nullptr, 0, 0) > 0) {
		TranslateMessage(&message);
		DispatchMessageW(&message);
	}

	const auto unregister_notification = reinterpret_cast<UnregisterSuspendResumeNotificationFunction>(
		GetProcAddress(user32, "UnregisterSuspendResumeNotification"));
	if (unregister_notification != nullptr) {
		unregister_notification(notification);
	}
	DestroyWindow(window);
}

void WindowsDisplayRecoveryMonitor::_handle_power_message(WPARAM p_event) {
	switch (p_event) {
		case PBT_APMSUSPEND:
			system_was_suspended.store(true);
			break;
		case PBT_APMRESUMECRITICAL:
		case PBT_APMRESUMESUSPEND:
		case PBT_APMRESUMESTANDBY:
		case PBT_APMRESUMEAUTOMATIC:
			pending_system_resume.store(true);
			break;
		default:
			break;
	}
}

} // namespace godot
