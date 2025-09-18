import Foundation
import x10Core
import x10Runtime
import x10BackendsPJRT
import x10Diagnostics

@main
struct Demo {
  static func main() async throws {
    Diagnostics.resetAll()

    // Build a tiny StableHLO-like module: r = a + b
    let b = IRBuilder()
    let fn = b.function(
      name: "add",
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
    print("--- IR ---")
    print(m.textual())

    let be = PJRTBackend()

    // First compile: cache miss (+1 counter)
    let e1 = try await JIT.compileCached(m, with: be)
    // Second compile: cache hit (+0)
    let e2 = try await JIT.compileCached(m, with: be)

    print("exec ids: \(e1.id) / \(e2.id)  (same? \(e1 == e2))")
    print("diagnostics: uncached_compiles=\(Diagnostics.uncachedCompiles.value), forced_evaluations=\(Diagnostics.forcedEvaluations.value)")
  }
}
