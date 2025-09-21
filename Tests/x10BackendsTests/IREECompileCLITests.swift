import Testing
import Foundation
import x10Core
import x10Runtime
import x10BackendsIREE

@Test
func ireeCLICompilesAndStoresVMFBIfAvailable() throws {
  // Skip if the CLI is not present on this machine/CI job.
  guard IREECompileCLI.find() != nil else { return }

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

  // Compile with IREE (CPU default: llvm-cpu)
  let be = IREEBackend()
  let exec = try be.compile(stablehlo: m, options: .init(device: .cpu(0)))

  // Verify the registry captured a non-empty vmfb blob.
  let vmfb = IREEExecutableRegistry.shared.getVMFB(id: exec.id)
  #expect(vmfb != nil)
  #expect((vmfb?.count ?? 0) > 0)
}
