import Foundation

public struct Counter: Sendable {
  public let name: String
  public private(set) var value: UInt64 = 0
  public init(_ name: String) { self.name = name }
  public mutating func inc(_ v: UInt64 = 1) { value += v }
}

public enum Diagnostics {
  public static var forcedEvaluations = Counter("forced_evaluations")
  public static var uncachedCompiles = Counter("uncached_compiles")
}
