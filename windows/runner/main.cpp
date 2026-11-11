#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  bool background_start = false;
  for (auto it = command_line_arguments.begin(); it != command_line_arguments.end();) {
    if (*it == "--notification-background") {
      background_start = true;
      it = command_line_arguments.erase(it);
    } else if (*it == "msix-args") {
      // The MSIX toast activator may launch the runner with this marker.
      // The notification plugin handles the actual activation payload.
      it = command_line_arguments.erase(it);
    } else {
      ++it;
    }
  }
  // A hidden ServicePro continues receiving notifications. Reopening the
  // Store app should restore that same session, not create two listeners.
  HANDLE single_instance = CreateMutexW(
      nullptr, TRUE, L"Local\\fullcoder47.ServicePro.NotificationInstance");
  if (single_instance && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"ServicePro");
    if (existing && !background_start) {
      PostMessageW(existing, WM_APP + 31, 0, 0);
      SetForegroundWindow(existing);
    }
    CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetQuitOnClose(true);
  window.EnableNotificationTray(true);
  window.StartHiddenInTray(background_start);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"ServicePro", origin, size)) {
    if (single_instance) CloseHandle(single_instance);
    return EXIT_FAILURE;
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance) CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
