import Testing
import Dispatch
@testable import x10Core
@testable import x10Runtime

final class CountingBackend: Backend {
  struct Dev: Hashable, Sendable { let ordinal: Int }

  private let queue = DispatchQueue(label: "counting-backend")
  private var _compileCount: Int = 0

  var compileCount: Int { queue.sync { _compileCount } }

  func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
  func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer { StubBuffer() }
  func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer { StubBuffer() }
  func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }

  func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    queue.sync { _compileCount += 1 }
    return Executable()
  }

  func execute(_ exec: Executable, inputs: [Buffer], stream: Stream?) async throws -> [Buffer] { inputs }
  func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  func stream(device: Dev) throws -> Stream { Stream() }
  func event(device: Dev) throws -> Event { Event() }

  private struct StubBuffer: Buffer {}
}

@Test
func cacheWarmingPrimesTopShapes() async throws {
  Diagnostics.resetAll()
  await ExecutableCache.shared.clear()
  await ShapeProfiler.shared.reset()

  BackendVersioning.register { backend in
    if backend is CountingBackend { return BackendVersionInfo(kind: "counting", version: "dev") }
    return nil
  }

  let backend = CountingBackend()
  let builder = IRBuilder()
  let fn = builder.function(
    name: "main",
    args: [("a", [nil], .f32)],
    results: [("r", [nil], .f32)]
  ) { f in
    let a = f.args[0], r = f.results[0]
    f.parameter(0, into: a)
    f.returnValues([r])
  }
  let module = StableHLOModule(functions: [fn])
  let policy = ShapeBucketingPolicy.default
  let device = Device.cpu(0)

  let info = BackendVersioning.info(for: backend)
  let versionSalt = "\(info.kind):\(info.version):dev"
  let deviceKey = device.stableKey
  let backendKey = info.kind

  let shapesToRecord = [[8], [8], [16], [32]]
  for shape in shapesToRecord {
    let (_, irHash) = makeCacheKey(
      module: module,
      backendKey: backendKey,
      deviceKey: deviceKey,
      versionSalt: versionSalt,
      concreteShape: shape,
      bucketing: policy,
      extraComponents: []
    )
    await ShapeProfiler.shared.note(irHash: irHash, policy: policy, concreteShape: shape)
  }

  let (_, entryHash) = makeCacheKey(
    module: module,
    backendKey: backendKey,
    deviceKey: deviceKey,
    versionSalt: versionSalt,
    concreteShape: shapesToRecord[0],
    bucketing: policy,
    extraComponents: []
  )

  let top = await ShapeProfiler.shared.topK(irHash: entryHash, policy: policy, k: 2)
  #expect(top.count == 2)

  await ExecutableCache.shared.clear()

  let preWarm = backend.compileCount
  await CacheWarmer.shared.warm(
    module: module,
    backend: backend,
    device: device,
    policy: policy,
    shapes: top
  )
  let postWarm = backend.compileCount
  #expect(postWarm == preWarm + top.count)

  for shape in top {
    let before = backend.compileCount
    var options = CompileOptions(
      device: device,
      shapeBucketing: policy,
      shapeHint: shape
    )
    _ = try await JIT.compileCached(module, with: backend, options: options)
    #expect(backend.compileCount == before)
  }
}
