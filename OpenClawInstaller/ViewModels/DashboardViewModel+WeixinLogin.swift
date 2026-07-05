//
//  DashboardViewModel+WeixinLogin.swift
//  Weixin QR login flow extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation
import AppKit

extension DashboardViewModel {

    // MARK: - Weixin QR Login

    /// Start Weixin channel login by streaming `openclaw channels login --channel openclaw-weixin`.
    /// Uses `script` to wrap the command in a pseudo-terminal (PTY) so that openclaw
    /// flushes its output immediately instead of buffering it in a pipe.
    func loginWeixinChannel() {
        weixinLoginStatus = .waitingScan
        weixinQRImage = nil
        cancelWeixinLogin()

        // Debug logging — writes to /tmp/weixin_debug.log
        let _ = FileManager.default.createFile(atPath: "/tmp/weixin_debug.log", contents: nil)
        let debugLog = FileHandle(forWritingAtPath: "/tmp/weixin_debug.log")
        let dbgLock = NSLock()
        let dbg: @Sendable (String) -> Void = { msg in
            let line = "[\(Date())] \(msg)\n"
            dbgLock.lock()
            debugLog?.write(line.data(using: .utf8) ?? Data())
            dbgLock.unlock()
        }

        let enrichedPath = OpenClawService.buildEnrichedPath()
        dbg("PATH=\(enrichedPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c",
                             "openclaw channels login --channel openclaw-weixin 2>&1"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        weixinLoginProcess = process

        // Use readabilityHandler for non-blocking streaming
        let handle = pipe.fileHandleForReading
        let accumulatedLock = NSLock()
        var accumulated = ""

        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                dbg("readabilityHandler: empty data (EOF)")
                fileHandle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else {
                dbg("readabilityHandler: failed to decode \(data.count) bytes as UTF-8")
                return
            }

            accumulatedLock.lock()
            accumulated += chunk
            let current = accumulated
            accumulatedLock.unlock()

            dbg("chunk(\(data.count) bytes): \(chunk.prefix(200))")

            let cleaned = DashboardViewModel.stripAnsiCodes(current)

            // Check for success
            let lower = cleaned.lowercased()
            if lower.contains("successfully") || lower.contains("登录成功") || lower.contains("连接成功") {
                dbg("SUCCESS detected")
                DispatchQueue.main.async {
                    self?.weixinLoginStatus = .success
                    Task { [weak self] in
                        await self?.loadChannels()
                    }
                }
                return
            }

            // Try to parse QR
            let lines = cleaned.components(separatedBy: .newlines)
            let qrCharCount = cleaned.unicodeScalars.filter { "█▄▀".unicodeScalars.contains($0) }.count
            dbg("lines=\(lines.count), qrChars=\(qrCharCount)")

            if let qrImage = DashboardViewModel.parseAsciiQRCode(from: cleaned) {
                dbg("QR IMAGE PARSED OK, size=\(qrImage.size)")
                accumulatedLock.lock()
                accumulated = ""
                accumulatedLock.unlock()
                DispatchQueue.main.async {
                    self?.weixinQRImage = qrImage
                    self?.weixinLoginStatus = .waitingScan
                }
            } else {
                dbg("QR parse returned nil")
            }
        }

        // Start the process
        do {
            try process.run()
            dbg("Process started, pid=\(process.processIdentifier)")
        } catch {
            dbg("Failed to start process: \(error)")
            weixinLoginStatus = .failed("Failed to start login: \(error.localizedDescription)")
            return
        }

        // Monitor process termination
        process.terminationHandler = { [weak self] proc in
            dbg("Process terminated, status=\(proc.terminationStatus)")
            // Give readabilityHandler a moment to process remaining data
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self?.weixinLoginStatus != .success && self?.weixinQRImage == nil {
                    accumulatedLock.lock()
                    let finalAccum = accumulated
                    accumulatedLock.unlock()
                    dbg("Final accumulated length=\(finalAccum.count)")
                    dbg("Final accumulated content:\n\(String(finalAccum.prefix(2000)))")

                    let cleaned = DashboardViewModel.stripAnsiCodes(finalAccum)
                    if let qrImage = DashboardViewModel.parseAsciiQRCode(from: cleaned) {
                        dbg("Late QR parse succeeded!")
                        self?.weixinQRImage = qrImage
                        self?.weixinLoginStatus = .waitingScan
                    } else if proc.terminationStatus != 0 {
                        self?.weixinLoginStatus = .failed("Login process exited with code \(proc.terminationStatus)")
                    }
                }
                debugLog?.closeFile()
            }
        }
    }

    /// Cancel any in-progress Weixin login
    func cancelWeixinLogin() {
        if let process = weixinLoginProcess, process.isRunning {
            process.terminate()
        }
        weixinLoginProcess = nil
    }

    /// Reset Weixin login state
    func resetWeixinLogin() {
        cancelWeixinLogin()
        weixinQRImage = nil
        weixinLoginStatus = .idle
    }

    /// Strip ANSI escape codes from terminal output
    nonisolated static func stripAnsiCodes(_ text: String) -> String {
        // Cache compiled regex to avoid recompilation on every call
        // This is critical for performance when processing large amounts of terminal output
        let ansiRegex: NSRegularExpression
        if let cached = ansiRegexCache {
            ansiRegex = cached
        } else {
            // Match CSI sequences: ESC[ ... final_byte
            // Also match OSC sequences: ESC] ... BEL
            guard let regex = try? NSRegularExpression(
                pattern: "\u{1B}\\[[0-9;]*[a-zA-Z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}\\([A-Z]",
                options: []
            ) else { return text }
            ansiRegexCache = regex
            ansiRegex = regex
        }
        return ansiRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

    // Static cache for compiled ANSI regex
    nonisolated(unsafe) static var ansiRegexCache: NSRegularExpression?

    /// Parse ASCII QR code block from command output and render it as an NSImage
    nonisolated static func parseAsciiQRCode(from output: String) -> NSImage? {
        let lines = output.components(separatedBy: .newlines)

        // QR block characters used by qrcode-terminal (small mode)
        let qrBlockScalars: Set<Unicode.Scalar> = [
            "\u{2588}", // █ FULL BLOCK
            "\u{2580}", // ▀ UPPER HALF BLOCK
            "\u{2584}", // ▄ LOWER HALF BLOCK
        ]
        var qrLines: [String] = []
        var inQR = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if inQR { break }
                continue
            }
            // Count actual QR block characters (not spaces)
            let blockCount = trimmed.unicodeScalars.filter { qrBlockScalars.contains($0) }.count
            // A valid QR line has many block chars and only contains block chars + spaces
            let allQR = trimmed.unicodeScalars.allSatisfy { qrBlockScalars.contains($0) || $0 == " " }
            if allQR && blockCount >= 5 && trimmed.count > 10 {
                inQR = true
                qrLines.append(trimmed)
            } else if inQR {
                break
            }
        }

        guard qrLines.count >= 5 else { return nil }

        // Each character in the ASCII QR maps to a 1-wide x 2-tall pixel region:
        // "█" = both top and bottom black
        // "▀" = top black, bottom white
        // "▄" = top white, bottom black
        // " " = both white
        let cols = qrLines.map { $0.count }.max() ?? 0
        let rows = qrLines.count * 2  // Each text line = 2 pixel rows

        let pixelSize = 4  // Scale each module to 4x4 pixels
        let imgWidth = cols * pixelSize
        let imgHeight = rows * pixelSize

        guard imgWidth > 0, imgHeight > 0 else { return nil }

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: imgWidth,
            pixelsHigh: imgHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep = bitmapRep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx

        // Fill white background
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: imgWidth, height: imgHeight).fill()

        for (lineIdx, line) in qrLines.enumerated() {
            for (colIdx, char) in line.enumerated() {
                let topBlack: Bool
                let bottomBlack: Bool

                switch char {
                case "█":
                    topBlack = true; bottomBlack = true
                case "▀":
                    topBlack = true; bottomBlack = false
                case "▄":
                    topBlack = false; bottomBlack = true
                default:
                    topBlack = false; bottomBlack = false
                }

                // Note: NSImage coordinate system is flipped (0,0 = bottom-left)
                let x = colIdx * pixelSize

                if topBlack {
                    let y = imgHeight - (lineIdx * 2) * pixelSize - pixelSize
                    NSColor.black.setFill()
                    NSRect(x: x, y: y, width: pixelSize, height: pixelSize).fill()
                }
                if bottomBlack {
                    let y = imgHeight - (lineIdx * 2 + 1) * pixelSize - pixelSize
                    NSColor.black.setFill()
                    NSRect(x: x, y: y, width: pixelSize, height: pixelSize).fill()
                }
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: imgWidth, height: imgHeight))
        image.addRepresentation(rep)
        return image
    }
}
