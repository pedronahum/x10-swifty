import Foundation
import x10BackendsPJRT
import x10BackendsIREE

public enum BackendKind: String {
  case pjrt, iree
}

public enum SelectedBackend {
  case pjrt(PJRTBackend)
  case iree(IREEBackend)
}

public enum BackendPicker {
  /// Decide from (1) options.flags["backend"], (2) env X10_BACKEND, (3) availability.
  public static func choose(kindOverride: String? = nil) -> BackendKind {
    let env = ProcessInfo.processInfo.environment
    let raw = kindOverride?.lowercased()
      ?? env["X10_BACKEND"]?.lowercased()

    let runtimeRequested = isTruthy(env["X10_IREE_RUNTIME"]) && IREEBackend.isReal

    switch raw {
    case "iree": return .iree
    case "pjrt": return .pjrt
    case .none:
      if runtimeRequested { return .iree }
      // Heuristic default: prefer IREE when available (for edge/AOT), else PJRT.
      return IREEBackend.isAvailable ? .iree : .pjrt
    default:
      return .pjrt
    }
  }

  /// Construct a backend instance of the chosen kind.
  public static func make(_ kind: BackendKind? = nil) -> SelectedBackend {
    switch kind ?? choose() {
    case .iree: return .iree(IREEBackend())
    case .pjrt: return .pjrt(PJRTBackend())
    }
  }

  private static func isTruthy(_ value: String?) -> Bool {
    guard let value = value else { return false }
    switch value.lowercased() {
    case "1", "true", "yes", "y", "on": return true
    default: return false
    }
  }
}
