import Foundation

/// The Mac app photographs itself for its manual and its store page
/// (Sources/Mac/Support/ScreenshotMode.swift). iOS takes its pictures from the
/// simulator instead, so here the mode is never on and its notes go nowhere.
enum ScreenshotMode {
    static var isActive: Bool { false }
    static func note(_ line: String) { }
}
