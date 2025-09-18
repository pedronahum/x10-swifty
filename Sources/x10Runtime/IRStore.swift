import Foundation
import x10Core

enum IRStore {
  /// Whether to persist textual IR for the current compile.
  /// Enabled if options.debugIR == true OR env X10_DEBUG_IR is a truthy value.
  static func shouldWriteIR(_ options: CompileOptions) -> Bool {
    if options.debugIR { return true }
    if let v = ProcessInfo.processInfo.environment["X10_DEBUG_IR"] {
      let low = v.lowercased()
      if !(low.isEmpty || low == "0" || low == "false" || low == "no" || low == "off") { return true }
    }
    return false
  }

  /// Base cache directory (override with X10_IR_CACHE_DIR).
  static func baseDir() -> URL {
    if let override = ProcessInfo.processInfo.environment["X10_IR_CACHE_DIR"], !override.isEmpty {
      return URL(fileURLWithPath: override, isDirectory: true)
    }
    let fm = FileManager.default
    #if os(macOS)
      let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
    #else
      let base = (ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]).map {
        URL(fileURLWithPath: $0, isDirectory: true)
      } ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
    #endif
    return base.appendingPathComponent("x10-swifty", isDirectory: true)
  }

  /// Persist the textual StableHLO for diagnostics.
  static func write(text: String, keyFingerprint: String, backendName: String) {
    let fm = FileManager.default
    let backendFolder = backendName.replacingOccurrences(of: ".", with: "-")
    let dir = baseDir().appendingPathComponent(backendFolder, isDirectory: true)
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      let digest = fnv1a64hex(keyFingerprint)
      let url = dir.appendingPathComponent("\(digest).stablehlo")
      try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      // Best-effort: ignore write errors in debug IR path.
    }
  }

  // 64-bit FNV-1a hex digest (portable, dependency-free)
  private static func fnv1a64hex(_ s: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for b in s.utf8 { hash ^= UInt64(b); hash &*= prime }
    var x = hash
    var bytes = [UInt8](repeating: 0, count: 8)
    for i in 0..<8 { bytes[7 - i] = UInt8(x & 0xff); x >>= 8 }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}
