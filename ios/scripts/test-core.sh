#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_developer_path="$(xcode-select -p)"
if [[ "$task_developer_path" == */CommandLineTools ]] && [[ -d "$task_developer_path/Library/Developer/Frameworks/Testing.framework" ]]; then
  exec swift test --package-path "$task_root" \
    -Xswiftc "-F$task_developer_path/Library/Developer/Frameworks" \
    -Xlinker "-F$task_developer_path/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$task_developer_path/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$task_developer_path/Library/Developer/usr/lib" "$@"
else
  exec swift test --package-path "$task_root" "$@"
fi
