import Testing
import Foundation
import x10Core
import x10Runtime
import x10BackendsIREE

@Test
func ireeCLIRunProducesExpectedSumIfAvailable() throws {
  // Only run this on machines where both compile and run tools are present.
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

  // Compile with IREE backend (CPU default: llvm-cpu)
  let be = IREEBackend()
  let exec = try be.compile(stablehlo: m, options: .init(device: .cpu(0)))
  guard let vmfb = IREEExecutableRegistry.shared.getVMFB(id: exec.id) else {
    Issue.record("VMFB not found in registry; check IREE CLI availability")
    return
  }

  // Prepare inputs: a = [1..6], b = [4 5 6 4 5 6]
  let aTxt = IREEExecuteCLI.formatInput(shape: [2,3], dtypeToken: "f32",
                                        scalars: ["1","2","3","4","5","6"])
  let bTxt = IREEExecuteCLI.formatInput(shape: [2,3], dtypeToken: "f32",
                                        scalars: ["4","5","6","4","5","6"])

  // Execute and parse
  let res = try IREEExecuteCLI.runAndParse(vmfb: vmfb, entry: "main", inputs: [aTxt, bTxt])

  #expect(res.shape == [2,3])
  #expect(res.dtypeToken == "f32")
  // Expected sums: [5 7 9][8 10 12]
  #expect(res.scalars.count == 6)
  let expected: [Double] = [5,7,9,8,10,12]
  for (lhs, rhs) in zip(res.scalars, expected) {
    #expect(abs(lhs - rhs) < 1e-6)
  }
}
