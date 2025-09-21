import Testing
import x10Core
import x10Runtime
import x10Diagnostics

@Test
func strictBarriersThrowAndCount() async throws {
  Diagnostics.resetAll()
  do {
    try await withStrictBarriers {
      let t = Tensor<Float>.ones(shape: [2, 2])
      _ = try await t.materialize()
    }
    Issue.record("materialize did not throw under strict barriers")
  } catch let error as BarrierViolationError {
    #expect(error.opHint == "materialize")
    #expect(Diagnostics.strictBarrierViolations.value >= 1)
  }
}

@Test
func relaxedBarriersAllowMaterialize() async throws {
  Diagnostics.resetAll()
  let before = Diagnostics.forcedEvaluations.value
  let t = Tensor<Float>.ones(shape: [1])
  let result = try await t.materialize()
  #expect(result.shape == t.shape)
  #expect(Diagnostics.forcedEvaluations.value == before + 1)
  #expect(Diagnostics.strictBarrierViolations.value == 0)
}
