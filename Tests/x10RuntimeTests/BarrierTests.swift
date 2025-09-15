import Testing
@testable import x10Core
@testable import x10Runtime

@Test
func materializeReturnsSameShape() async throws {
  let t = Tensor<Float>(shape: [1], on: .cpu(0))
  let r = try await t.materialize()
  #expect(r.shape == [1])
}
