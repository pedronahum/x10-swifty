import Testing
@testable import x10Core
@testable import x10Runtime

private struct CountingBackend: Backend {
  struct Dev: Hashable, Sendable { let ordinal: Int }
  static var compileCount = 0

  func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
  func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
  func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
  func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }

  func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    CountingBackend.compileCount += 1
    return Executable()
  }

  func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] { inputs }
  func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
  func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
}

@Test
func cacheMissThenHit() async throws {
  // Make state deterministic for this test
  CountingBackend.compileCount = 0
  await ExecutableCache.shared.clear()

  let prevWarm = ProcessInfo.processInfo.environment["X10_CACHE_WARMING"]
  if prevWarm == nil {
    unsetenv("X10_CACHE_WARMING")
  }
  setenv("X10_CACHE_WARMING", "0", 1)
  defer {
    if let prevWarm {
      setenv("X10_CACHE_WARMING", prevWarm, 1)
    } else {
      unsetenv("X10_CACHE_WARMING")
    }
  }

  // Build tiny IR
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

  // First is a miss (compile called), second is a hit (no compile)
  let be = CountingBackend()
  _ = try await JIT.compileCached(m, with: be)
  _ = try await JIT.compileCached(m, with: be)

  #expect(CountingBackend.compileCount == 1)
}
