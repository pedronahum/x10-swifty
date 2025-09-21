import Foundation

public extension IREEBackend {
  /// True when we can both compile **and** execute via CLI tools.
  /// You can force-disable via `X10_IREE_DISABLE=1`.
  static var isAvailable: Bool {
    if ProcessInfo.processInfo.environment["X10_IREE_DISABLE"] == "1" { return false }
    return IREECompileCLI.find() != nil && IREEExecuteCLI.find() != nil
  }

  /// True when an in‑process IREE runtime is linked/enabled.
  /// We’ll wire this up when we add the runtime shim; for now it’s `false`.
  /// If you later define `X10_IREE_HAVE_HEADERS` in SwiftPM settings, this will flip to `true`.
  static var isReal: Bool {
    if ProcessInfo.processInfo.environment["X10_IREE_DISABLE"] == "1" { return false }
    return IREEVM.isRuntimeReady()
  }

  /// Human‑readable probe summary (handy in logs/tests).
  static var availabilityDetail: String {
    let haveCompile = IREECompileCLI.find() != nil
    let haveRun     = IREEExecuteCLI.find() != nil
    let _ = ProcessInfo.processInfo.environment["X10_IREE_RUNTIME"] == "1"
    let haveRuntime = IREEVM.isRuntimeReady()
    let disabled    = ProcessInfo.processInfo.environment["X10_IREE_DISABLE"] == "1"
    return "compileCLI=\(haveCompile) runCLI=\(haveRun) runtime=\(haveRuntime) disabled=\(disabled)"
  }
}
