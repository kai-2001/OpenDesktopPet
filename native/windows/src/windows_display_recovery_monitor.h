#ifndef OPEN_DESKTOP_PET_WINDOWS_DISPLAY_RECOVERY_MONITOR_H
#define OPEN_DESKTOP_PET_WINDOWS_DISPLAY_RECOVERY_MONITOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace godot {

class WindowsDisplayRecoveryMonitor : public RefCounted {
	GDCLASS(WindowsDisplayRecoveryMonitor, RefCounted)

protected:
	static void _bind_methods();

public:
	~WindowsDisplayRecoveryMonitor();

	bool start();
	void stop();
	Dictionary poll_events();
	String get_last_error() const;

private:
	static LRESULT CALLBACK _window_proc(HWND p_window, UINT p_message, WPARAM p_wparam, LPARAM p_lparam);
	void _message_thread_main();
	void _handle_power_message(WPARAM p_event);

	std::thread message_thread;
	std::mutex startup_mutex;
	std::condition_variable startup_condition;
	std::atomic<DWORD> message_thread_id{ 0 };
	std::atomic<bool> pending_system_resume{ false };
	std::atomic<bool> system_was_suspended{ false };
	bool startup_complete = false;
	bool startup_succeeded = false;
	DWORD startup_error = ERROR_SUCCESS;
	bool screen_saver_state_initialized = false;
	bool screen_saver_was_running = false;
	String last_error;
};

} // namespace godot

#endif
