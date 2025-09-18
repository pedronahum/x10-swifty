import Testing
@testable import x10Core

@Test
func textualIRIncludesOpsAndShapes() {
  let b = IRBuilder()
  let fn = b.function(
    name: "main",
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
  let text = m.textual()
  #expect(text.contains("func @main"))
  #expect(text.contains("stablehlo.parameter 0"))
  #expect(text.contains("stablehlo.add"))
  #expect(text.contains("f32[2,3]"))
}
