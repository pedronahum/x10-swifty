import Foundation
import x10Core
import x10Diagnostics

extension x10Core.Tensor {
  /// Explicit evaluation point (modern stand-in for LazyTensorBarrier()).
  public func materialize(
    file: StaticString = #fileID, line: UInt = #line
  ) async throws -> Self {
    if BarrierScope.policy.strict {
      throw BarrierError.strictBarrier(file: file, line: line, backtrace: Thread.callStackSymbols)
    }
    Diagnostics.forcedEvaluations.inc()
    return self // stub: real path will await device work
  }

  /// Async host read; returns host bytes. Keeps the API non-blocking by default.
  public func materializeHost(
    file: StaticString = #fileID, line: UInt = #line
  ) async throws -> Data {
    if BarrierScope.policy.strict {
      throw BarrierError.strictBarrier(file: file, line: line, backtrace: Thread.callStackSymbols)
    }
    Diagnostics.forcedEvaluations.inc()
    return Data() // stub: wire to backend.fromDevice(_) later
  }
}
