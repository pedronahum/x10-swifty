import Foundation
import x10Core
import x10Diagnostics

extension x10Core.Tensor {
  /// Explicit evaluation point (modern stand-in for LazyTensorBarrier()).
  public func materialize(
    file: StaticString = #fileID, line: UInt = #line
  ) async throws -> Self {
    let policy = BarrierPolicyScope.BarrierPolicyCurrent
    if policy.strict {
      Diagnostics.strictBarrierViolations.inc()
      let bt = policy.captureBacktrace ? Thread.callStackSymbols : nil
      throw BarrierViolationError(site: (file, line), opHint: "materialize", backtrace: bt)
    }
    Diagnostics.forcedEvaluations.inc()
    return self // stub: real path will await device work
  }

  /// Async host read; returns host bytes. Keeps the API non-blocking by default.
  public func materializeHost(
    file: StaticString = #fileID, line: UInt = #line
  ) async throws -> Data {
    let policy = BarrierPolicyScope.BarrierPolicyCurrent
    if policy.strict {
      Diagnostics.strictBarrierViolations.inc()
      let bt = policy.captureBacktrace ? Thread.callStackSymbols : nil
      throw BarrierViolationError(site: (file, line), opHint: "materializeHost", backtrace: bt)
    }
    Diagnostics.forcedEvaluations.inc()
    return Data() // stub: wire to backend.fromDevice(_) later
  }
}
