import Testing
@testable import x10Core
@testable import x10Runtime
@testable import x10Diagnostics

@Test
func barrierIncrementsCounter() async throws {
  let before = Diagnostics.forcedEvaluations.value
  let t = Tensor<Float>(shape: [1], on: .cpu(0))
  _ = try await t.materialize()
  #expect(Diagnostics.forcedEvaluations.value >= before + 1)
}
