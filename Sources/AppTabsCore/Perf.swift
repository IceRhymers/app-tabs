import Foundation
import os

/// Lightweight, opt-in perf tracing: set APPTABS_PERF=1 to log timings to stderr.
/// Zero overhead when the env var is unset (checked once at startup).
public enum Perf {
    public static let enabled = ProcessInfo.processInfo.environment["APPTABS_PERF"] == "1"

    public static func log(_ label: String, _ ms: Double, detail: String = "") {
        guard enabled else { return }
        let d = detail.isEmpty ? "" : " [\(detail)]"
        NSLog("PERF %@ %.2fms%@", label, ms, d as NSString)
    }
}
