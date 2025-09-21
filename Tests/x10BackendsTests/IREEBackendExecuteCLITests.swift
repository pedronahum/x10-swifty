import Testing
import Foundation
import x10Core
import x10Runtime
import x10BackendsIREE

@Test
func ireeBackendExecuteAddIfCLIAvailable() async throws {
  // Skip on machines without CLI tools
  guard IREECompileCLI.find() != nil, IREEExecuteCLI.find() != nil else { return }

  // Build tiny StableHLO: r = a + b  (f32[2,3])
  let b = IRBuilder()
  let fn = b.function(
    name: "main",
    args: [("a", [2, 3], .f32), ("b", [2, 3], .f32)],
    results: [("r", [2, 3], .f32)]
  ) { f in
    let a = f.args[0], bb = f.args[1], r = f.results[0]
    f.parameter(0, into: a)
    f.parameter(1, into: bb)
    f.add(a, bb, into: r)
    f.returnValues([r])
  }
  let m = StableHLOModule(functions: [fn])

  let be = IREEBackend()
  let exec = try be.compile(stablehlo: m, options: .init(device: .cpu(0)))

  // Prepare inputs
  let a: [Float] = [1, 2, 3, 4, 5, 6]
  let b2: [Float] = [4, 5, 6, 4, 5, 6]
  let aBuf: Buffer = try a.withUnsafeBytes { ab in
    try be.toDevice(ab, shape: [2, 3], dtype: .f32, on: .init(ordinal: 0))
  }
  let bBuf: Buffer = try b2.withUnsafeBytes { bb in
    try be.toDevice(bb, shape: [2, 3], dtype: .f32, on: .init(ordinal: 0))
  }
  // Execute
  let outs = try await be.execute(exec, inputs: [aBuf, bBuf], stream: nil)
  #expect(outs.count == 1)

  // Inspect host bytes
  let raw = try be.fromDevice(outs[0])
  let out: [Float] = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  #expect(out == [5, 7, 9, 8, 10, 12])
}
