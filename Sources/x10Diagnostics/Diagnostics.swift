import Foundation

public struct Counter: Sendable {
  public let name: String
  public private(set) var value: UInt64 = 0

  public init(_ name: String) { self.name = name }
  public mutating func inc(_ v: UInt64 = 1) { value &+= v }
  public mutating func reset() { value = 0 }
}

public enum Diagnostics {
  // Counters highlighted in the deep-dive (barrier & uncached compiles).
  public static var forcedEvaluations = Counter("forced_evaluations")
  public static var uncachedCompiles = Counter("uncached_compiles")

  @inlinable
  public static func resetAll() {
    forcedEvaluations.reset()
    uncachedCompiles.reset()
  }
}
