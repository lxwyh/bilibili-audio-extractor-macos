#!/bin/zsh
set -euo pipefail

args="$*"
if [[ "$args" == *"--print %(title)s"* ]]; then
  echo "测试视频"
  exit 0
fi

destination=""
arguments=("$@")
for ((index = 1; index <= ${#arguments}; index++)); do
  if [[ "${arguments[$index]}" == "-P" ]]; then
    destination="${arguments[$((index + 1))]}"
    break
  fi
done

mkdir -p "$destination"
if [[ "$args" == *"--write-subs"* ]]; then
  if [[ "$args" != *"nosub"* ]]; then
    script_dir="${0:A:h}"
    cp "$script_dir/fixtures/bilibili-subtitle.json" "$destination/测试视频 [BVTEST].ai-zh.json"
  fi
  exit 0
fi

if [[ "$args" == *"-f wa"* ]]; then
  touch "$destination/测试视频 [BVTEST].m4a"
  exit 0
fi

exit 0
