#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

#include "tagtag_entrypoint_protocol.h"

namespace {

HWND FindMainWindow() {
  return FindWindow(tagtag::kMainWindowClassName, tagtag::kMainWindowTitle);
}

std::wstring QuoteForCommandLine(const std::wstring& argument) {
  std::wstring quoted = L"\"";
  size_t slash_count = 0;
  for (const wchar_t character : argument) {
    if (character == L'\\') {
      ++slash_count;
      continue;
    }
    if (character == L'\"') {
      quoted.append(slash_count * 2 + 1, L'\\');
    } else {
      quoted.append(slash_count, L'\\');
    }
    quoted.push_back(character);
    slash_count = 0;
  }
  quoted.append(slash_count * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

std::wstring MainExecutablePath() {
  std::vector<wchar_t> path(MAX_PATH);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) {
    return {};
  }
  std::wstring executable(path.data(), length);
  const size_t separator = executable.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  return executable.substr(0, separator + 1) + L"tagtag.exe";
}

bool LaunchTagTag(const std::vector<std::wstring>& paths) {
  const std::wstring executable = MainExecutablePath();
  if (executable.empty()) {
    return false;
  }
  std::wstring command_line = QuoteForCommandLine(executable) + L" --quick-tag";
  for (const std::wstring& path : paths) {
    command_line += L" ";
    command_line += QuoteForCommandLine(path);
  }
  std::vector<wchar_t> mutable_command_line(command_line.begin(),
                                             command_line.end());
  mutable_command_line.push_back(L'\0');

  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  if (CreateProcessW(executable.c_str(), mutable_command_line.data(), nullptr,
                     nullptr, FALSE, 0, nullptr, nullptr, &startup_info,
                     &process_info) == FALSE) {
    return false;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return true;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE previous_instance,
                      wchar_t* command_line, int show_command) {
  const std::vector<std::wstring> paths = tagtag::QuickTagPathsFromCommandLine();
  if (paths.empty()) {
    return EXIT_FAILURE;
  }

  const HWND existing_window = FindMainWindow();
  if (existing_window != nullptr &&
      tagtag::SendExplorerPaths(existing_window, paths)) {
    return EXIT_SUCCESS;
  }
  return LaunchTagTag(paths) ? EXIT_SUCCESS : EXIT_FAILURE;
}
