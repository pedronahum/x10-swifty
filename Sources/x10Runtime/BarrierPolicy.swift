import Foundation
import x10Core

public struct BarrierPolicy: Sendable {
  public var strict: Bool
  public init(strict: Bool = false) { self.strict = strict }
}

public enum BarrierError: Error, CustomStringConvertible, Sendable {
  case strictBarrier(file: StaticString, line: UInt, backtrace: [String])
  public var description: String {
    switch self {
    case .strictBarrier(let file, let line, let bt):
      return "Strict barrier violation at \(file):\(line)\n" + bt.joined(separator: "\n")
    }
  }
}

public enum BarrierScope {
  @TaskLocal public static var policy = BarrierPolicy()
}

@inlinable
public func withStrictBarriers<T>(
  _ enabled: Bool, _ body: () async throws -> T
) async rethrows -> T {
  try await BarrierScope.$policy.withValue(.init(strict: enabled)) { try await body() }
}
