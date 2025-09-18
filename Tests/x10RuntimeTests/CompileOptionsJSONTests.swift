import Testing
@testable import x10Core
@testable import x10Runtime

@Test
func compileOptionsJSONContainsDevicePrecisionAndFlags() {
  let opt = CompileOptions(
    device: .gpu(1),
    precision: .init(activations: .bf16, matmul: .bf16, accumulators: .fp32),
    debugIR: true,
    enableProfiling: false,
    flags: ["alpha": "1", "beta": "x"]
  )
  let json = opt.toJSON()
  #expect(json.contains("\"device\":\"gpu:1\""))
  #expect(json.contains("\"activations\":\"bf16\""))
  #expect(json.contains("\"matmul\":\"bf16\""))
  #expect(json.contains("\"accumulators\":\"fp32\""))
  #expect(json.contains("\"debugIR\":true"))
  #expect(json.contains("\"flags\""))
  #expect(json.contains("\"alpha\":\"1\""))
  #expect(json.contains("\"beta\":\"x\""))
}
