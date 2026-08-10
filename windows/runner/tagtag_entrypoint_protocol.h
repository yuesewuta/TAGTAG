#ifndef RUNNER_TAGTAG_ENTRYPOINT_PROTOCOL_H_
#define RUNNER_TAGTAG_ENTRYPOINT_PROTOCOL_H_

#include <windows.h>

#include <string>
#include <vector>

namespace tagtag {

constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kMainWindowTitle[] = L"tagtag";
constexpr ULONG_PTR kExplorerPathsCopyDataId = 0x54475450;

std::vector<std::wstring> QuickTagPathsFromCommandLine();
bool SendExplorerPaths(HWND window, const std::vector<std::wstring>& paths);

}  // namespace tagtag

#endif  // RUNNER_TAGTAG_ENTRYPOINT_PROTOCOL_H_
