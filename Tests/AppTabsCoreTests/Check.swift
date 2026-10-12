import Foundation

/// Tiny assertion harness (CLT ships no XCTest/Swift Testing, so we roll our own).
/// All checks run on the main actor (the test runner is @MainActor throughout).
@MainActor
enum Check {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ name: String, file: String = #fileID, line: Int = #line) {
        if condition {
            passes += 1
            print("  ok - \(name)")
        } else {
            failures += 1
            print("  FAIL - \(name) (\(file):\(line))")
        }
    }

    static func equal<T: Equatable>(_ a: T, _ b: T, _ name: String, file: String = #fileID, line: Int = #line) {
        expect(a == b, "\(name) — expected \(b), got \(a)", file: file, line: line)
    }

    static func finish() -> Int32 {
        print("\n\(passes) passed, \(failures) failed")
        return failures == 0 ? 0 : 1
    }
}
