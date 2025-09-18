// Sources/x10Core/Device/Device+StableKey.swift

extension Device {
  /// Stable, backend-agnostic identifier for cache keys and filenames.
  public var stableKey: String {
    switch self {
    case .cpu(let n): return "cpu:\(n)"
    case .gpu(let n): return "gpu:\(n)"
    }
  }
}
