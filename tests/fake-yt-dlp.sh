#!/bin/zsh
set -euo pipefail

args="$*"
if [[ "$args" == *"--print %(title)s"* ]]; then
  if [[ "$args" == *"douyin.com"* ]]; then
    echo "抖音测试视频"
  else
    echo "B站测试视频"
  fi
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
  if [[ "$args" != *"nosub"* && "$args" != *"douyin.com"* ]]; then
    script_dir="${0:A:h}"
    cp "$script_dir/fixtures/bilibili-subtitle.json" "$destination/测试视频 [BVTEST].ai-zh.json"
  fi
  exit 0
fi

if [[ "$args" == *"-f wa"* ]]; then
  if [[ "$args" == *"douyin.com"* ]]; then
    truncate -s 4096 "$destination/抖音测试视频 [1234567890].m4a"
    echo "__TRAFFIC__1234567890|4096"
  else
    truncate -s 4096 "$destination/B站测试视频 [BVTEST].m4a"
    echo "__TRAFFIC__BVTEST|4096"
  fi
  exit 0
fi

exit 0
