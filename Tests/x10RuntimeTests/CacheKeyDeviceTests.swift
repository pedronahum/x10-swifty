import Foundation
import Testing
import x10Core
import x10Runtime
import x10Diagnostics

@Test
func cacheIsPerDeviceByExecutableIdentity() async throws {
  Diagnostics.resetAll()
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

  struct DummyBackend: Backend {
    struct Dev: Hashable, Sendable { let ordinal: Int }
    func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
    func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer { StubBuffer() }
    func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer { StubBuffer() }
    func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }
    func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable { Executable() }
    func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] { inputs }
    func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
    func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
    func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }

    private struct StubBuffer: Buffer {}
  }
  let be = DummyBackend()

  let builder = IRBuilder()
  let fn = builder.function(
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
  let module = StableHLOModule(functions: [fn])

  let cpuOptions = CompileOptions(device: .cpu(0))
  let gpuOptions = CompileOptions(device: .gpu(0))

  let eCPU1 = try await JIT.compileCached(module, with: be, options: cpuOptions)
  let eCPU2 = try await JIT.compileCached(module, with: be, options: cpuOptions)
  #expect(eCPU1 == eCPU2)

  await ExecutableCache.shared.clear()
  Diagnostics.resetAll()

  let eGPU1 = try await JIT.compileCached(module, with: be, options: gpuOptions)
  let eGPU2 = try await JIT.compileCached(module, with: be, options: gpuOptions)
  #expect(eGPU1 == eGPU2)

  await ExecutableCache.shared.clear()
  Diagnostics.resetAll()

  let eCPU1Again = try await JIT.compileCached(module, with: be, options: cpuOptions)
  #expect(eCPU1 != eGPU1)
  #expect(eCPU1Again != eGPU1)
}
