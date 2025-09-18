import Testing
@testable import x10Core
@testable import x10Runtime
@testable import x10BackendsPJRT

@Test
func compileCachedReturnsSameExecutableForSameShapes() async throws {
  let be = PJRTBackend()

  let b = IRBuilder()
  let fn = b.function(
    name: "add",
    args: [("a", [2, 3], .f32), ("b", [2, 3], .f32)],
    results: [("r", [2, 3], .f32)]
  ) { f in
    let a = f.args[0], b = f.args[1], r = f.results[0]
    f.parameter(0, into: a)
    f.parameter(1, into: b)
    f.add(a, b, into: r)
    f.returnValues([r])
  }
  let m = StableHLOModule(functions: [fn])

  let e1 = try await JIT.compileCached(m, with: be)
  let e2 = try await JIT.compileCached(m, with: be)
  #expect(e1 == e2)
}
