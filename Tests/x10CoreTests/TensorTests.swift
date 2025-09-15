import Testing
@testable import x10Core

@Test
func tensorBasics() {
  let t = Tensor<Float>(shape: [2, 3], on: .gpu(0))
  #expect(t.shape == [2, 3])
  #expect(String(describing: t) == "Tensor<Float>(shape: [2, 3], device: gpu(0))")
}
