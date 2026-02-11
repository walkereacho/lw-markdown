import os.signpost
import QuartzCore

/// Centralized os_signpost instrumentation for profiling in Instruments.
///
/// ## Usage
/// Open the app in Instruments with the "Logging" template.
/// Filter by subsystem "com.markdowneditor" to see all signpost intervals.
///
/// For terminal output, run and observe stderr for timing summary:
/// ```
/// .build/debug/MarkdownEditor --test-file Tests/Fixtures/perf-5000.md 2>&1 | grep PERF
/// ```
///
/// ## Categories
/// - **Rendering**: draw() calls and element-specific renderers
/// - **Parsing**: MarkdownParser token generation
/// - **Layout**: Fragment creation, active paragraph switching, invalidation
/// - **Editing**: Full edit cycle, font application
enum Signposts {
    static let subsystem = "com.markdowneditor"

    // MARK: - Log Handles

    static let rendering = OSLog(subsystem: subsystem, category: "Rendering")
    static let layout    = OSLog(subsystem: subsystem, category: "Layout")
    static let editing   = OSLog(subsystem: subsystem, category: "Editing")

    // MARK: - Signpost Names (Rendering)

    static let draw = StaticString("draw")
    static let highlightr = StaticString("highlightr")
    static let ctFramesetter = StaticString("ctFramesetter")

    // MARK: - Signpost Names (Layout)

    static let fragmentCreation = StaticString("fragmentCreation")
    static let activeParagraphSwitch = StaticString("activeParagraphSwitch")
    static let invalidateParagraph = StaticString("invalidateParagraph")
    static let blockContextUpdate = StaticString("blockContextUpdate")
    static let initAfterContentLoad = StaticString("initAfterContentLoad")

    // MARK: - Signpost Names (Editing)

    static let textDidChange = StaticString("textDidChange")
    static let willProcessEditing = StaticString("willProcessEditing")
}

/// Lightweight timing collector that prints a summary to stderr.
/// Accumulates timing data per operation and prints on demand.
/// Thread-safe via a serial queue.
final class PerfTimer {
    static let shared = PerfTimer()

    private struct Stats {
        var count: Int = 0
        var totalMs: Double = 0
        var minMs: Double = .greatestFiniteMagnitude
        var maxMs: Double = 0
    }

    private var stats: [String: Stats] = [:]
    private let queue = DispatchQueue(label: "com.markdowneditor.perftimer")
    private var startTime: CFAbsoluteTime = 0

    private init() {
        startTime = CFAbsoluteTimeGetCurrent()
    }

    /// Record a timing measurement.
    func record(_ name: String, ms: Double) {
        queue.async { [self] in
            var s = stats[name] ?? Stats()
            s.count += 1
            s.totalMs += ms
            s.minMs = min(s.minMs, ms)
            s.maxMs = max(s.maxMs, ms)
            stats[name] = s
        }
    }

    /// Measure a block and record it.
    func measure<T>(_ name: String, block: () -> T) -> T {
        let start = CACurrentMediaTime()
        let result = block()
        let elapsed = (CACurrentMediaTime() - start) * 1000
        record(name, ms: elapsed)
        return result
    }

    /// Print timing summary to stderr and append to log file.
    func printSummary(label: String = "unknown") {
        queue.async { [self] in
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            var lines: [String] = []

            let timestamp = ISO8601DateFormatter().string(from: Date())
            lines.append(String(format: "\n[PERF] ===== %@ | %@ (%.2fs since launch) =====", timestamp, label, elapsed))

            let sorted = stats.sorted { $0.value.totalMs > $1.value.totalMs }
            lines.append("[PERF] " + "Operation".padding(toLength: 30, withPad: " ", startingAt: 0)
                + "Count".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "Total(ms)".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "Avg(ms)".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "Min(ms)".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "Max(ms)")
            lines.append("[PERF] " + String(repeating: "-", count: 86))

            for (name, s) in sorted {
                let avg = s.count > 0 ? s.totalMs / Double(s.count) : 0
                lines.append("[PERF] " + name.padding(toLength: 30, withPad: " ", startingAt: 0)
                    + String(s.count).padding(toLength: 8, withPad: " ", startingAt: 0)
                    + String(format: "%-12.2f%-12.3f%-12.3f%-12.3f", s.totalMs, avg, s.minMs, s.maxMs))
            }
            lines.append("[PERF] " + String(repeating: "=", count: 86) + "\n")

            let output = lines.joined(separator: "\n")

            // Print to stderr
            fputs(output + "\n", stderr)

            // Append to log file
            let logPath = "/tmp/markdowneditor-perf.log"
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: logPath) {
                fileManager.createFile(atPath: logPath, contents: nil)
            }
            if let handle = FileHandle(forWritingAtPath: logPath),
               let data = (output + "\n").data(using: .utf8) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }

    /// Reset all stats.
    func reset() {
        queue.async { [self] in
            stats.removeAll()
            startTime = CFAbsoluteTimeGetCurrent()
        }
    }
}
