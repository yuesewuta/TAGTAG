#include "tagtag_entrypoint_protocol.h"

#include <shellapi.h>

namespace tagtag {

std::vector<std::wstring> QuickTagPathsFromCommandLine() {
  int argument_count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr) {
    return {};
  }

  std::vector<std::wstring> paths;
  bool collecting_paths = false;
  for (int index = 1; index < argument_count; ++index) {
    if (!collecting_paths) {
      collecting_paths = wcscmp(arguments[index], L"--quick-tag") == 0;
      continue;
    }
    if (arguments[index][0] != L'\0') {
      paths.emplace_back(arguments[index]);
    }
  }

  LocalFree(arguments);
  return paths;
}

bool SendExplorerPaths(HWND window, const std::vector<std::wstring>& paths) {
  if (window == nullptr || paths.empty()) {
    return false;
  }

  std::vector<wchar_t> payload;
  for (const std::wstring& path : paths) {
    if (path.empty()) {
      return false;
    }
    payload.insert(payload.end(), path.begin(), path.end());
    payload.push_back(L'\0');
  }
  payload.push_back(L'\0');

  COPYDATASTRUCT copy_data{};
  copy_data.dwData = kExplorerPathsCopyDataId;
  copy_data.cbData = static_cast<DWORD>(payload.size() * sizeof(wchar_t));
  copy_data.lpData = payload.data();
  DWORD_PTR ignored_result = 0;
  return SendMessageTimeoutW(window, WM_COPYDATA, 0,
                             reinterpret_cast<LPARAM>(&copy_data),
                             SMTO_ABORTIFHUNG | SMTO_BLOCK, 1000,
                             &ignored_result) != 0;
}

}  // namespace tagtag
