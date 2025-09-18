import Testing
@testable import x10Core
@testable import x10Runtime

private struct DummyBackend: Backend {
  struct Dev: Hashable, Sendable { let ordinal: Int }
  func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
  func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
  func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
  func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }
  func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable { Executable() }
  func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] { inputs }
  func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
  func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
}

@Test
func cacheIsPerDeviceByExecutableIdentity() async throws {
  await ExecutableCache.shared.clear()

  // Build tiny IR: r = a + b  (shape [2,3], f32)
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
  let be = DummyBackend()

  // Explicit CPU → miss then hit (same id)
  let eCPU1 = try await JIT.compileCached(m, with: be, options: .init(device: .cpu(0)))
  let eCPU2 = try await JIT.compileCached(m, with: be, options: .init(device: .cpu(0)))
  #expect(eCPU1 == eCPU2)

  // Explicit GPU → miss then hit (same id)
  let eGPU1 = try await JIT.compileCached(m, with: be, options: .init(device: .gpu(0)))
  let eGPU2 = try await JIT.compileCached(m, with: be, options: .init(device: .gpu(0)))
  #expect(eGPU1 == eGPU2)

  // Different device ⇒ different cache entry / executable identity
  #expect(eCPU1 != eGPU1)
}
