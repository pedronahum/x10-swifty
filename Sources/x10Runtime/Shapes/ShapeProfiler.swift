import x10Core
import Foundation

public actor ShapeProfiler {
  public static let shared = ShapeProfiler()
  private var counts: [String: Int] = [:] // fingerprint -> hits

  public func record(_ key: ShapeKey) { counts[key.fingerprint, default: 0] += 1 }

  /// Naive top-N; pluggable later with ML-based predictors.
  public func topFingerprints(_ k: Int = 5) -> [String] {
    counts.sorted { $0.value > $1.value }.prefix(k).map { $0.key }
  }
}
