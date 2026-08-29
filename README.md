# B站字幕音频提取器

一个完全在本机运行的 macOS 小工具：粘贴 Bilibili 链接，优先下载现成字幕并整理为 TXT/SRT；没有字幕时，只下载最低码率纯音频。

版本 1.0.1 已补充标准 macOS“编辑”菜单，链接输入框支持 `⌘C`、`⌘V`、`⌘X`、`⌘A`、撤销和重做。

## 工作方式

1. 自动模式先请求 Bilibili 的字幕数据，不下载视频。
2. 如果找到字幕，输出 `完整逐字稿.txt`、`带时间戳字幕.srt` 和原始字幕文件。
3. 如果没有字幕，下载最低码率纯音频，便于上传到 NotebookLM、腾讯或其他转写工具。
4. 选择“仅字幕”时，没有字幕就停止，不消耗音频流量。

## 使用

1. 双击 `B站字幕音频提取器.app`。
2. 粘贴 `https://www.bilibili.com/video/BV…` 或 `b23.tv` 链接。
3. 选择提取方式和保存目录。
4. 公开内容通常不需要浏览器登录状态。确实需要登录时，先在浏览器登录 Bilibili，再在应用内选择对应浏览器。

如果出现 `HTTP 412`，这是 Bilibili 的访问风控，不代表应用损坏。请先在浏览器登录 Bilibili，再在应用中选择该浏览器；若仍失败，可稍后更换网络重试。

## 从源码构建

要求：Apple Silicon Mac、macOS 13 或更高版本，以及 Apple Command Line Tools。

```bash
chmod +x build.sh
./build.sh
```

构建脚本会在缺失时从 yt-dlp 官方 GitHub Releases 下载通用 macOS 可执行文件，然后生成：

```text
dist/B站字幕音频提取器.app
dist/B站字幕音频提取器.zip
dist/使用说明.md
```

构建产物采用本地 ad-hoc 签名，没有 Apple Developer ID 公证。

## 项目结构

- `App.swift`：原生 AppKit 界面、提取流程与字幕清洗。
- `Info.plist`：macOS 应用元数据。
- `make_icon.swift`：应用图标生成器。
- `build.sh`：依赖下载、编译、签名与打包。
- `tests/`：字幕解析和提取流程测试素材。
- `THIRD_PARTY_NOTICES.md`：第三方组件声明。

## 注意

- 应用内置 yt-dlp，不需要 Homebrew、Python 或 FFmpeg。
- 最低支持 macOS 13。
- 浏览器 Cookie 仅由本机 yt-dlp 读取，不会被本应用保存或上传。
- 只处理你有权访问和使用的内容，不用于绕过付费、DRM 或其他访问限制。
