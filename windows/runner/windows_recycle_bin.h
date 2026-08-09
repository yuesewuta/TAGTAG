#ifndef RUNNER_WINDOWS_RECYCLE_BIN_H_
#define RUNNER_WINDOWS_RECYCLE_BIN_H_

#include <windows.h>

#include <string>

namespace tagtag {

struct RecycleBinResult {
  HRESULT status;
  std::wstring token;
};

RecycleBinResult MoveToRecycleBin(const std::wstring& resource_path);

HRESULT RestoreFromRecycleBin(const std::wstring& token,
                              const std::wstring& destination_path);

}  // namespace tagtag

#endif  // RUNNER_WINDOWS_RECYCLE_BIN_H_
