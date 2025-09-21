import Testing
import Foundation
import x10Core
import Darwin
import x10Runtime
import x10Diagnostics

@Test
func cacheIsPerDeviceByExecutableIdentity() async throws {
  // Ensure a clean slate for this test only.
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

  // Build a tiny StableHLO: r = a + b  (f32[2,3])
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

  // Use a deterministic dummy backend for the cache test.
  struct DummyBackend: Backend {
    struct Dev: Hashable, Sendable { let ordinal: Int }
    static var compileCount = 0
    func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
    func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
    func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer { struct B: Buffer {}; return B() }
    func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }
    func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
      Self.compileCount += 1
      return Executable()
    }
    func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] { inputs }
    func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
    func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
    func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
  }
  let be = DummyBackend()
  DummyBackend.compileCount = 0

  // Make the device explicit to avoid ambient-state drift.
  let cpu = CompileOptions(device: .cpu(0))
  let gpu = CompileOptions(device: .gpu(0))

  // Same device + same shapes => only one compile
  _ = try await JIT.compileCached(m, with: be, options: cpu)
  let afterFirstCPU = DummyBackend.compileCount
  #expect(afterFirstCPU == 1)
  _ = try await JIT.compileCached(m, with: be, options: cpu)
  #expect(DummyBackend.compileCount == afterFirstCPU)

  // Same GPU device twice => only one additional compile
  _ = try await JIT.compileCached(m, with: be, options: gpu)
  let afterFirstGPU = DummyBackend.compileCount
  #expect(afterFirstGPU == afterFirstCPU + 1)
  _ = try await JIT.compileCached(m, with: be, options: gpu)
  #expect(DummyBackend.compileCount == afterFirstGPU)

  // Different devices triggered two separate compilations
  #expect(afterFirstGPU == 2)
}
