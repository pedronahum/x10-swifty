import Foundation

public struct BarrierPolicy: Sendable {
  public var strict: Bool
  public var captureBacktrace: Bool

  public init(strict: Bool = false, captureBacktrace: Bool = true) {
    self.strict = strict
    self.captureBacktrace = captureBacktrace
  }

  public static let `default` = BarrierPolicy(strict: false, captureBacktrace: true)
}

public struct BarrierViolationError: Error, CustomStringConvertible, Sendable {
  public let site: (file: StaticString, line: UInt)
  public let opHint: String
  public let backtrace: [String]?

  public init(site: (file: StaticString, line: UInt), opHint: String, backtrace: [String]?) {
    self.site = site
    self.opHint = opHint
    self.backtrace = backtrace
  }

  public var description: String {
    var lines: [String] = ["Barrier violation during \(opHint) at \(site.file):\(site.line)"]
    if let bt = backtrace, !bt.isEmpty {
      lines.append("Backtrace:")
      lines.append(contentsOf: bt)
    }
    return lines.joined(separator: "\n")
  }
}

public enum BarrierPolicyScope {
  @TaskLocal public static var BarrierPolicyCurrent: BarrierPolicy = .default
}

@inlinable
public func withStrictBarriers<T>(_ body: () async throws -> T) async rethrows -> T {
  let policy = BarrierPolicy(strict: true, captureBacktrace: BarrierPolicy.default.captureBacktrace)
  return try await BarrierPolicyScope.$BarrierPolicyCurrent.withValue(policy) {
    try await body()
  }
}
