import Testing
@testable import x10Core
@testable import x10Runtime

private struct CapturingBackend: Backend {
  struct Dev: Hashable, Sendable { let ordinal: Int }
  static var lastOptions: CompileOptions?

  func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
  func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
  func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
  func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }

  func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    Self.lastOptions = options
    return Executable()
  }

  func execute(_ exec: Executable, inputs: [Buffer], stream: Stream?) async throws -> [Buffer] { inputs }
  func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  func stream(device: Dev) throws -> Stream { Stream() }
  func event(device: Dev) throws -> Event { Event() }
}

@Test
func compileCachedPicksUpDeviceScopeWhenUnset() async throws {
  // Build trivial IR
  let b = IRBuilder()
  let fn = b.function(name: "id",
                      args: [("a", [1], .f32)],
                      results: [("r", [1], .f32)]) { f in
    let a = f.args[0], r = f.results[0]
    f.parameter(0, into: a)
    f.add(a, a, into: r) // any op
    f.returnValues([r])
  }
  let m = StableHLOModule(functions: [fn])

  // Run under a non-default device
  let be = CapturingBackend()
  let exec = try await withDevice(.gpu(0)) {
    try await JIT.compileCached(m, with: be)  // no explicit options
  }
  #expect(exec.id != Executable().id) // new random id

  // Verify the device flowed into backend.compile options
  #expect(CapturingBackend.lastOptions?.device == .gpu(0))
}
