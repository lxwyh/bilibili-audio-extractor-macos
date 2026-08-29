import AppKit
import AVFoundation
import Foundation
import Darwin

enum ExtractMode: Int {
    case automatic = 0
    case subtitlesOnly = 1
    case audioOnly = 2
}

enum VideoPlatform: String {
    case bilibili = "Bilibili"
    case douyin = "抖音"

    var fallbackTitle: String { "\(rawValue) 提取结果" }
}

struct VideoInput {
    let url: String
    let platform: VideoPlatform

    static func parse(_ raw: String) -> VideoInput? {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>]+", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range, in: raw) else { return nil }

        let trailing = CharacterSet(charactersIn: "，。！？；：、）》】」』'\".,!?;:)]}")
        let candidate = String(raw[range]).trimmingCharacters(in: trailing)
        guard let parsed = URL(string: candidate), let host = parsed.host?.lowercased() else { return nil }

        if host == "bilibili.com" || host.hasSuffix(".bilibili.com")
            || host == "b23.tv" || host.hasSuffix(".b23.tv") {
            return VideoInput(url: candidate, platform: .bilibili)
        }
        if host == "douyin.com" || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com" || host.hasSuffix(".iesdouyin.com") {
            return VideoInput(url: candidate, platform: .douyin)
        }
        return nil
    }
}

struct TranscriptCue {
    let start: Double
    let end: Double
    let text: String
}

enum TranscriptParser {
    static func parse(url: URL) -> [TranscriptCue] {
        let name = url.lastPathComponent.lowercased()
        guard let data = try? Data(contentsOf: url) else { return [] }
        if name.hasSuffix(".json") { return parseJSON(data) }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        if name.hasSuffix(".ass") || name.hasSuffix(".ssa") { return parseASS(text) }
        return parseTimedText(text)
    }

    private static func parseJSON(_ data: Data) -> [TranscriptCue] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        if let body = root["body"] as? [[String: Any]] {
            return body.compactMap { item in
                guard let content = item["content"] as? String else { return nil }
                let start = number(item["from"])
                let end = max(number(item["to"]), start + 0.5)
                return TranscriptCue(start: start, end: end, text: clean(content))
            }.filter { !$0.text.isEmpty }
        }

        if let events = root["events"] as? [[String: Any]] {
            return events.compactMap { event in
                guard let segments = event["segs"] as? [[String: Any]] else { return nil }
                let content = segments.compactMap { $0["utf8"] as? String }.joined()
                let start = number(event["tStartMs"]) / 1000
                let duration = max(number(event["dDurationMs"]) / 1000, 0.5)
                return TranscriptCue(start: start, end: start + duration, text: clean(content))
            }.filter { !$0.text.isEmpty }
        }
        return []
    }

    private static func parseTimedText(_ text: String) -> [TranscriptCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [TranscriptCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = lines[timeIndex].components(separatedBy: "-->")
            guard sides.count == 2 else { continue }
            let start = parseTime(sides[0])
            let end = parseTime(sides[1].components(separatedBy: " ").first ?? sides[1])
            let content = lines.dropFirst(timeIndex + 1).map(clean).filter { !$0.isEmpty }.joined(separator: " ")
            if !content.isEmpty { cues.append(TranscriptCue(start: start, end: max(end, start + 0.5), text: content)) }
        }
        return deduplicate(cues)
    }

    private static func parseASS(_ text: String) -> [TranscriptCue] {
        var cues: [TranscriptCue] = []
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("Dialogue:") {
            let payload = String(line.dropFirst("Dialogue:".count)).trimmingCharacters(in: .whitespaces)
            let parts = payload.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard parts.count == 10 else { continue }
            let start = parseTime(String(parts[1]))
            let end = parseTime(String(parts[2]))
            let content = clean(String(parts[9]).replacingOccurrences(of: "\\N", with: " "))
            if !content.isEmpty { cues.append(TranscriptCue(start: start, end: max(end, start + 0.5), text: content)) }
        }
        return deduplicate(cues)
    }

    static func plainText(_ cues: [TranscriptCue]) -> String {
        deduplicate(cues).map(\.text).joined(separator: "\n") + (cues.isEmpty ? "" : "\n")
    }

    static func srt(_ cues: [TranscriptCue]) -> String {
        deduplicate(cues).enumerated().map { index, cue in
            "\(index + 1)\n\(formatTime(cue.start)) --> \(formatTime(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    private static func deduplicate(_ cues: [TranscriptCue]) -> [TranscriptCue] {
        var result: [TranscriptCue] = []
        for cue in cues.sorted(by: { $0.start < $1.start }) {
            if result.last?.text != cue.text { result.append(cue) }
        }
        return result
    }

    private static func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func parseTime(_ raw: String) -> Double {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts.first ?? 0
    }

    private static func formatTime(_ seconds: Double) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let secs = (milliseconds % 60_000) / 1000
        let ms = milliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, ms)
    }

    private static func clean(_ raw: String) -> String {
        var value = raw
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\{[^}]+\\}", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "&nbsp;", with: " ")
        value = value.replacingOccurrences(of: "&amp;", with: "&")
        value = value.replacingOccurrences(of: "&lt;", with: "<")
        value = value.replacingOccurrences(of: "&gt;", with: ">")
        value = value.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ProcessRunner {
    private let executable: URL
    init(executable: URL) { self.executable = executable }

    func run(arguments: [String], onLine: @escaping (String) -> Void) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var collected = ""
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock(); collected += chunk; lock.unlock()
            for line in chunk.components(separatedBy: .newlines) where !line.isEmpty { onLine(line) }
        }
        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        if let chunk = String(data: rest, encoding: .utf8), !chunk.isEmpty {
            lock.lock(); collected += chunk; lock.unlock()
            for line in chunk.components(separatedBy: .newlines) where !line.isEmpty { onLine(line) }
        }
        return (process.terminationStatus, collected)
    }
}

final class ExtractorService {
    private let fileManager = FileManager.default
    private let runner: ProcessRunner

    init(executable: URL) { runner = ProcessRunner(executable: executable) }

    func extract(url: String, platform: VideoPlatform, destination: URL, mode: ExtractMode, allParts: Bool,
                 browser: String?, log: @escaping (String) -> Void) throws -> URL {
        let jobURL = fileManager.temporaryDirectory.appendingPathComponent("MediaExtractor-\(UUID().uuidString)")
        try fileManager.createDirectory(at: jobURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: jobURL) }

        let common = commonArguments(allParts: allParts, browser: browser)
        log("正在读取视频信息…")
        let metadata = try runner.run(arguments: common + ["--skip-download", "--print", "%(title)s", url], onLine: log)
        guard metadata.0 == 0 else {
            throw NSError(domain: "Extractor", code: 2, userInfo: [NSLocalizedDescriptionKey: friendlyError(metadata.1, platform: platform)])
        }
        let title = metadata.1.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("[") }) ?? platform.fallbackTitle
        let contentID: String
        switch platform {
        case .bilibili: contentID = firstMatch(in: url, pattern: "BV[0-9A-Za-z]+") ?? ""
        case .douyin: contentID = firstMatch(in: url, pattern: "(?<=/video/)[0-9]+") ?? ""
        }
        let folderBase = sanitize(title, fallback: platform.fallbackTitle) + (contentID.isEmpty ? "" : " [\(contentID)]")
        let finalFolder = uniqueFolder(parent: destination, base: folderBase)

        var foundTranscript = false
        if mode != .audioOnly {
            log("正在检查并提取 \(platform.rawValue) 现成字幕（不会下载视频）…")
            let subtitleArgs = common + [
                "--skip-download", "--write-subs", "--sub-langs", "all",
                "--write-info-json", "-P", jobURL.path,
                "-o", "%(title).120B [%(id)s].%(ext)s", url
            ]
            _ = try runner.run(arguments: subtitleArgs, onLine: log)
            let candidates = transcriptFiles(in: jobURL)
            let parsed = candidates.map { ($0, TranscriptParser.parse(url: $0)) }.filter { !$0.1.isEmpty }
            if !parsed.isEmpty {
                try fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)
                foundTranscript = true
                let ordered = parsed.sorted { score($0.0, cues: $0.1) > score($1.0, cues: $1.1) }
                let selected = allParts ? ordered : [ordered[0]]
                var combined: [TranscriptCue] = []
                var plainSections: [String] = []
                for (index, pair) in selected.enumerated() {
                    let label = pair.0.deletingPathExtension().lastPathComponent
                    if selected.count > 1 { plainSections.append("===== \(label) =====") }
                    plainSections.append(TranscriptParser.plainText(pair.1).trimmingCharacters(in: .whitespacesAndNewlines))
                    let offset = combined.last?.end ?? 0
                    let shifted = index == 0 ? pair.1 : pair.1.map {
                        TranscriptCue(start: $0.start + offset, end: $0.end + offset, text: $0.text)
                    }
                    combined.append(contentsOf: shifted)
                    let rawTarget = finalFolder.appendingPathComponent(pair.0.lastPathComponent)
                    try? fileManager.copyItem(at: pair.0, to: rawTarget)
                }
                try plainSections.joined(separator: "\n\n").appending("\n")
                    .write(to: finalFolder.appendingPathComponent("完整逐字稿.txt"), atomically: true, encoding: .utf8)
                try TranscriptParser.srt(combined)
                    .write(to: finalFolder.appendingPathComponent("带时间戳字幕.srt"), atomically: true, encoding: .utf8)
                log("已生成完整逐字稿和 SRT 字幕。")
            }
        }

        if !foundTranscript && mode != .subtitlesOnly {
            if platform == .douyin {
                log("没有找到可用字幕，优先请求抖音独立音频流…")
                log("若该视频不提供独立音频，将下载最低质量带音频文件并在本机剥离音轨。")
            } else {
                log("没有找到可用字幕，开始下载最低码率纯音频…")
            }
            let format = platform == .douyin ? "wa/w[acodec!=none]" : "wa"
            let audioArgs = common + [
                "-f", format, "-P", jobURL.path,
                "-o", "%(title).120B [%(id)s].%(ext)s", url
            ]
            let result = try runner.run(arguments: audioArgs, onLine: log)
            guard result.0 == 0 else { throw NSError(domain: "Extractor", code: 4, userInfo: [NSLocalizedDescriptionKey: friendlyError(result.1, platform: platform)]) }
            let audioFiles = mediaFiles(in: jobURL)
            guard !audioFiles.isEmpty else { throw NSError(domain: "Extractor", code: 5, userInfo: [NSLocalizedDescriptionKey: "音频下载完成，但没有找到输出文件。请更新应用内的 yt-dlp 后重试。"]) }
            try fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)
            for file in audioFiles {
                if platform == .douyin && file.pathExtension.lowercased() == "mp4" {
                    let target = uniqueFile(in: finalFolder, base: file.deletingPathExtension().lastPathComponent, extension: "m4a")
                    log("正在本机剥离音轨：\(target.lastPathComponent)")
                    try exportAudio(from: file, to: target)
                } else {
                    let target = uniqueFile(in: finalFolder, base: file.deletingPathExtension().lastPathComponent,
                                            extension: file.pathExtension)
                    try fileManager.moveItem(at: file, to: target)
                }
            }
            log("已保存最低码率纯音频。")
        }

        if !foundTranscript && mode == .subtitlesOnly {
            throw NSError(domain: "Extractor", code: 3, userInfo: [NSLocalizedDescriptionKey: "这个视频没有可提取的字幕。可以改用“自动”或“仅低码率音频”。"])
        }

        try fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)
        let info = """
        来源：\(url)
        标题：\(title)
        提取时间：\(ISO8601DateFormatter().string(from: Date()))
        结果：\(foundTranscript ? "字幕与逐字稿" : "最低码率纯音频")

        本工具只处理用户有权访问和使用的内容。
        """
        try info.write(to: finalFolder.appendingPathComponent("视频信息.txt"), atomically: true, encoding: .utf8)
        return finalFolder
    }

    private func commonArguments(allParts: Bool, browser: String?) -> [String] {
        var args = ["--newline", "--no-warnings"]
        args.append(allParts ? "--yes-playlist" : "--no-playlist")
        if let browser, !browser.isEmpty { args += ["--cookies-from-browser", browser] }
        return args
    }

    private func transcriptFiles(in folder: URL) -> [URL] {
        let extensions = Set(["json", "srt", "vtt", "ass", "ssa", "lrc"])
        return files(in: folder).filter {
            extensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasSuffix(".info.json")
        }
    }

    private func mediaFiles(in folder: URL) -> [URL] {
        let extensions = Set(["m4a", "aac", "mp3", "mp4", "webm", "ogg", "opus", "wav"])
        return files(in: folder).filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    private func files(in folder: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func score(_ url: URL, cues: [TranscriptCue]) -> Int {
        let name = url.lastPathComponent.lowercased()
        var value = cues.count
        if name.contains("ai-zh") || name.contains("zh-cn") || name.contains("zh-hans") { value += 1_000_000 }
        else if name.contains("zh") { value += 500_000 }
        return value
    }

    private func uniqueFolder(parent: URL, base: String) -> URL {
        var candidate = parent.appendingPathComponent(base)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base) (\(index))")
            index += 1
        }
        return candidate
    }

    private func sanitize(_ value: String, fallback: String) -> String {
        var clean = value.replacingOccurrences(of: "[/:*?\"<>|]", with: "-", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 100 { clean = String(clean.prefix(100)) }
        return clean.isEmpty ? fallback : clean
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private func friendlyError(_ output: String, platform: VideoPlatform) -> String {
        let lower = output.lowercased()
        if lower.contains("fresh cookies") && platform == .douyin {
            return "抖音需要最新 Cookie。请先用 Chrome、Safari、Firefox 或 Edge 打开一次该抖音视频，再在应用中选择同一浏览器后重试。"
        }
        if lower.contains("login") || lower.contains("cookie") || lower.contains("会员") || lower.contains("登录") {
            return "该内容可能需要登录或最新 Cookie。请在浏览器打开并登录 \(platform.rawValue)，再在应用中选择对应浏览器后重试。"
        }
        if lower.contains("requested format is not available") && platform == .douyin {
            return "这个抖音视频没有可下载的音频格式。请先在浏览器确认视频能正常播放，并选择该浏览器的登录状态后重试。"
        }
        if lower.contains("unsupported url") { return "无法识别该链接。请粘贴 Bilibili、b23.tv、douyin.com 或 v.douyin.com 视频链接。" }
        if lower.contains("412") && platform == .bilibili {
            return "Bilibili 启动了访问风控（HTTP 412）。请先在 Chrome、Safari 或 Firefox 登录 Bilibili，然后在应用的“登录状态”中选择该浏览器再重试。也可以稍后更换网络重试。"
        }
        if lower.contains("403") { return "\(platform.rawValue) 拒绝了请求。请先在浏览器确认视频能播放，并选择同一浏览器的登录状态后重试。" }
        return output.components(separatedBy: .newlines).suffix(6).joined(separator: "\n")
    }

    private func uniqueFile(in folder: URL, base: String, extension ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(index))").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    private func exportAudio(from source: URL, to destination: URL) throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "Extractor", code: 6, userInfo: [NSLocalizedDescriptionKey: "macOS 无法读取这个抖音媒体文件的音轨。"])
        }
        session.outputURL = destination
        session.outputFileType = .m4a
        session.shouldOptimizeForNetworkUse = true
        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously { semaphore.signal() }
        semaphore.wait()
        guard session.status == .completed else {
            try? fileManager.removeItem(at: destination)
            throw NSError(domain: "Extractor", code: 7, userInfo: [NSLocalizedDescriptionKey:
                session.error?.localizedDescription ?? "从抖音媒体文件剥离音轨失败。"])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let urlField = NSTextField()
    private let pathField = NSTextField()
    private let modePopup = NSPopUpButton()
    private let browserPopup = NSPopUpButton()
    private let allParts = NSButton(checkboxWithTitle: "处理全部分P", target: nil, action: nil)
    private let startButton = NSButton(title: "开始提取", target: nil, action: nil)
    private let openButton = NSButton(title: "打开结果", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private let progress = NSProgressIndicator()
    private let logView = NSTextView()
    private var lastOutput: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildUI()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于视频字幕音频提取器", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出视频字幕音频提取器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 570),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "视频字幕音频提取器"
        window.center()
        window.isReleasedWhenClosed = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -18)
        ])

        let heading = NSTextField(labelWithString: "粘贴 Bilibili 或抖音链接/分享文本，优先提取字幕；否则只保存音频。")
        heading.font = .systemFont(ofSize: 15, weight: .medium)
        root.addArrangedSubview(heading)

        root.addArrangedSubview(label("视频链接或分享文本"))
        urlField.placeholderString = "Bilibili / b23.tv / douyin.com / v.douyin.com"
        urlField.font = .systemFont(ofSize: 14)
        urlField.isEditable = true
        urlField.isSelectable = true
        urlField.usesSingleLineMode = true
        stretch(urlField, in: root)

        let optionRow = NSStackView()
        optionRow.orientation = .horizontal; optionRow.spacing = 16; optionRow.alignment = .centerY
        optionRow.addArrangedSubview(label("提取方式"))
        modePopup.addItems(withTitles: ["自动：优先字幕，无字幕则音频", "仅提取字幕", "仅提取低码率音频"])
        optionRow.addArrangedSubview(modePopup)
        optionRow.addArrangedSubview(allParts)
        root.addArrangedSubview(optionRow)

        let browserRow = NSStackView()
        browserRow.orientation = .horizontal; browserRow.spacing = 16; browserRow.alignment = .centerY
        browserRow.addArrangedSubview(label("登录状态"))
        browserPopup.addItems(withTitles: ["不使用浏览器登录状态", "Chrome", "Safari", "Firefox", "Edge"])
        browserRow.addArrangedSubview(browserPopup)
        let browserHint = NSTextField(labelWithString: "抖音通常需要最新 Cookie；先在浏览器打开视频，再选择同一浏览器。")
        browserHint.textColor = .secondaryLabelColor
        browserHint.font = .systemFont(ofSize: 11)
        browserRow.addArrangedSubview(browserHint)
        root.addArrangedSubview(browserRow)

        root.addArrangedSubview(label("保存位置"))
        let pathRow = NSStackView()
        pathRow.orientation = .horizontal; pathRow.spacing = 8
        pathField.stringValue = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
        pathField.isEditable = false
        pathField.lineBreakMode = .byTruncatingMiddle
        let choose = NSButton(title: "选择…", target: self, action: #selector(chooseFolder))
        pathRow.addArrangedSubview(pathField); pathRow.addArrangedSubview(choose)
        pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        stretch(pathRow, in: root)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal; actionRow.spacing = 10; actionRow.alignment = .centerY
        startButton.target = self; startButton.action = #selector(startExtraction); startButton.keyEquivalent = "\r"
        openButton.target = self; openButton.action = #selector(openResult); openButton.isEnabled = false
        progress.style = .spinning; progress.controlSize = .small
        actionRow.addArrangedSubview(startButton); actionRow.addArrangedSubview(openButton); actionRow.addArrangedSubview(progress)
        actionRow.addArrangedSubview(statusLabel)
        root.addArrangedSubview(actionRow)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        logView.isEditable = false; logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = logView
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 245).isActive = true
        stretch(scroll, in: root)

        let footer = NSTextField(labelWithString: "处理全部在本机完成。请仅提取你有权访问和使用的内容。")
        footer.textColor = .secondaryLabelColor; footer.font = .systemFont(ofSize: 11)
        root.addArrangedSubview(footer)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(urlField)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12, weight: .semibold)
        return field
    }

    private func stretch(_ view: NSView, in stack: NSStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "选择保存位置"
        if panel.runModal() == .OK, let url = panel.url { pathField.stringValue = url.path }
    }

    @objc private func openResult() {
        if let lastOutput { NSWorkspace.shared.open(lastOutput) }
    }

    @objc private func startExtraction() {
        let rawInput = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let videoInput = VideoInput.parse(rawInput) else {
            showError("请粘贴有效的 Bilibili、b23.tv、douyin.com 或 v.douyin.com 视频链接，也可以直接粘贴含链接的抖音分享文本。")
            return
        }
        guard FileManager.default.fileExists(atPath: pathField.stringValue) else {
            showError("保存目录不存在，请重新选择。")
            return
        }
        guard let executable = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) else {
            showError("应用资源不完整：缺少 yt-dlp。请重新下载应用。")
            return
        }

        setBusy(true)
        logView.string = ""
        appendLog("已识别平台：\(videoInput.platform.rawValue)")
        appendLog("开始处理：\(videoInput.url)")
        let mode = ExtractMode(rawValue: modePopup.indexOfSelectedItem) ?? .automatic
        let destination = URL(fileURLWithPath: pathField.stringValue, isDirectory: true)
        let browserMap: [Int: String?] = [0: nil, 1: "chrome", 2: "safari", 3: "firefox", 4: "edge"]
        let browser = browserMap[browserPopup.indexOfSelectedItem] ?? nil
        let processAll = allParts.state == .on

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let service = ExtractorService(executable: executable)
                let folder = try service.extract(url: videoInput.url, platform: videoInput.platform,
                                                 destination: destination, mode: mode,
                                                 allParts: processAll, browser: browser ?? nil) { line in
                    DispatchQueue.main.async { self.appendLog(line) }
                }
                DispatchQueue.main.async {
                    self.lastOutput = folder
                    self.openButton.isEnabled = true
                    self.statusLabel.stringValue = "完成"
                    self.appendLog("完成：\(folder.path)")
                    self.setBusy(false)
                    NSSound(named: "Glass")?.play()
                }
            } catch {
                DispatchQueue.main.async {
                    self.setBusy(false)
                    self.statusLabel.stringValue = "失败"
                    self.appendLog("错误：\(error.localizedDescription)")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        startButton.isEnabled = !busy; modePopup.isEnabled = !busy; browserPopup.isEnabled = !busy
        allParts.isEnabled = !busy; urlField.isEnabled = !busy
        busy ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        if busy { statusLabel.stringValue = "处理中…" }
    }

    private func appendLog(_ line: String) {
        logView.textStorage?.append(NSAttributedString(string: line + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]))
        logView.scrollToEndOfDocument(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "无法完成操作"; alert.informativeText = message
        alert.runModal()
    }
}

if CommandLine.arguments.count >= 6 && CommandLine.arguments[1] == "--integration-test" {
    let executable = URL(fileURLWithPath: CommandLine.arguments[2])
    let destination = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let testURL = CommandLine.arguments[4]
    let mode = ExtractMode(rawValue: Int(CommandLine.arguments[5]) ?? 0) ?? .automatic
    guard let input = VideoInput.parse(testURL) else {
        fputs("integration-test error: unsupported test URL\n", stderr)
        exit(2)
    }
    do {
        let folder = try ExtractorService(executable: executable).extract(
            url: input.url, platform: input.platform, destination: destination,
            mode: mode, allParts: false, browser: nil,
            log: { print($0) }
        )
        print("output=\(folder.path)")
        exit(0)
    } catch {
        fputs("integration-test error: \(error.localizedDescription)\n", stderr)
        exit(3)
    }
} else if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--parse-input" {
    if let input = VideoInput.parse(CommandLine.arguments[2]) {
        print("platform=\(input.platform.rawValue)")
        print("url=\(input.url)")
        exit(0)
    }
    fputs("unsupported input\n", stderr)
    exit(2)
} else if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--parse-file" {
    let input = URL(fileURLWithPath: CommandLine.arguments[2])
    let cues = TranscriptParser.parse(url: input)
    print("cues=\(cues.count)")
    print(TranscriptParser.plainText(cues), terminator: "")
    exit(cues.isEmpty ? 2 : 0)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
