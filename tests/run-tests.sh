#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
executable="${1:-$project_dir/dist/视频字幕音频提取器.app/Contents/MacOS/BiliAudioExtractor}"
test_dir="$(mktemp -d)"
trap '/bin/rm -rf "$test_dir"' EXIT

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    echo "断言失败：未找到 $expected"
    echo "$output"
    exit 1
  fi
}

bili_input="$($executable --parse-input 'https://www.bilibili.com/video/BV1TEST')"
assert_contains "$bili_input" "platform=Bilibili"

douyin_input="$($executable --parse-input '7.23 复制打开抖音，看看视频 https://v.douyin.com/AbCd123/，更多内容。')"
assert_contains "$douyin_input" "platform=抖音"
assert_contains "$douyin_input" "url=https://v.douyin.com/AbCd123/"

if "$executable" --parse-input 'https://www.youtube.com/watch?v=test' >/dev/null 2>&1; then
  echo "断言失败：不应接受未支持的平台"
  exit 1
fi

parser_output="$($executable --parse-file "$script_dir/fixtures/sample.vtt")"
assert_contains "$parser_output" "cues="

bili_output="$($executable --integration-test "$script_dir/fake-yt-dlp.sh" "$test_dir" 'https://www.bilibili.com/video/BVTEST' 0)"
assert_contains "$bili_output" "完整逐字稿"

douyin_output="$($executable --integration-test "$script_dir/fake-yt-dlp.sh" "$test_dir" 'https://www.douyin.com/video/1234567890?nosub=1' 2)"
assert_contains "$douyin_output" "已保存最低码率纯音频"

audio_count="$(find "$test_dir" -name '*.m4a' -type f | wc -l | tr -d ' ')"
if [[ "$audio_count" -lt 1 ]]; then
  echo "断言失败：抖音音频输出不存在"
  exit 1
fi

echo "全部测试通过"
