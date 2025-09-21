// Sources/x10Runtime/Compilation.swift

import Foundation
import x10Core
import x10Diagnostics

public struct BackendVersionInfo {
  public let kind: String
  public let version: String

  public init(kind: String, version: String) {
    self.kind = kind
    self.version = version
  }
}

public enum BackendVersioning {
  private static let queue = DispatchQueue(label: "x10.BackendVersioning")
  private static var resolvers: [(Any) -> BackendVersionInfo?] = []

  public static func register(_ resolver: @escaping (Any) -> BackendVersionInfo?) {
    queue.sync { resolvers.append(resolver) }
  }

  static func info(for backend: Any) -> BackendVersionInfo {
    let handlers = queue.sync { resolvers }
    for resolver in handlers.reversed() {
      if let info = resolver(backend) {
        return info
      }
    }
    let typeName = String(reflecting: type(of: backend)).lowercased()
    let kind: String
    if typeName.contains("iree") {
      kind = "iree"
    } else if typeName.contains("pjrt") {
      kind = "pjrt"
    } else {
      kind = "unknown"
    }
    return BackendVersionInfo(kind: kind, version: "dev")
  }
}

/// JIT front-end: compiles StableHLO with a Backend and caches Executables
/// using a stable key derived from (device, precision, flags, textual IR).
public enum JIT {
  /// Compile (or fetch from cache) an Executable for `stablehlo` on `backend`.
  /// - Behavior:
  ///   - If `options.device` is nil, we use `DeviceScope.current`.
  ///   - Cache key includes device, precision policy, flags and textual IR.
  ///   - On a cache miss, increments `Diagnostics.uncachedCompiles`.
  public static func compileCached<B: Backend>(
    _ stablehlo: StableHLOModule,
    with backend: B,
    options: CompileOptions = .init()
  ) async throws -> Executable {
    // Fill in default device if the caller didn’t specify one.
    var opts = options
    if opts.device == nil { opts.device = DeviceScope.current }

    // Key the cache by IR+options+device/bucketing.
    let info = BackendVersioning.info(for: backend)
    let backendKey = info.kind
    let packageVer = "dev"
    let versionSalt = "\(info.kind):\(info.version):\(packageVer)"

    let deviceKey = opts.device?.stableKey ?? "cpu:0"
    let precisionSignature = "a:\(precCode(opts.precision.activations))," +
                             "m:\(precCode(opts.precision.matmul))," +
                             "acc:\(precCode(opts.precision.accumulators))"
    let flagStr = opts.flags
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ";")

    let extraComponents = ["precision=\(precisionSignature)", "flags=\(flagStr)"]
    let concreteShape = opts.shapeHint ?? canonicalConcreteShape(from: stablehlo)

    let (key, irHash) = makeCacheKey(
      module: stablehlo,
      backendKey: backendKey,
      deviceKey: deviceKey,
      versionSalt: versionSalt,
      concreteShape: concreteShape,
      bucketing: opts.shapeBucketing,
      extraComponents: extraComponents
    )

    await ShapeProfiler.shared.note(
      irHash: irHash,
      policy: opts.shapeBucketing,
      concreteShape: concreteShape
    )

    if let hit = await ExecutableCache.shared.get(key) {
      return hit
    }

    Diagnostics.uncachedCompiles.inc()
    let exec = try backend.compile(stablehlo: stablehlo, options: opts)
    await ExecutableCache.shared.put(exec, for: key)

    if !opts.isWarmup && cacheWarmingEnabled() {
      let device = opts.device ?? Device.default
      let shapes = await ShapeProfiler.shared.topK(
        irHash: irHash,
        policy: opts.shapeBucketing,
        k: cacheWarmingTopK()
      )
      if !shapes.isEmpty {
        await CacheWarmer.shared.warm(
          module: stablehlo,
          backend: backend,
          device: device,
          policy: opts.shapeBucketing,
          shapes: shapes
        )
      }
    }
    return exec
  }

  // MARK: - Private helpers (kept inside the JIT type)

  /// Maps precision enums to short string codes used in the key.
  private static func precCode(_ p: PrecisionPolicy.Precision) -> String {
    switch p {
    case .f16:  return "f16"
    case .bf16: return "bf16"
    case .fp8:  return "fp8"
    case .fp32: return "f32"
    }
  }
}

// MARK: - Tiny stable hash (no external deps)

@inline(__always)
private func fnv1a64(_ s: String) -> String {
  var hash: UInt64 = 0xcbf29ce484222325
  let prime: UInt64 = 0x100000001b3
  for byte in s.utf8 {
    hash ^= UInt64(byte)
    hash &*= prime
  }
  // 16 hex chars; sufficient for a cache key fingerprint.
  return String(format: "%016llx", hash)
}

private func canonicalConcreteShape(from module: StableHLOModule) -> [Int] {
  guard let fn = module.functions.first else { return [] }
  if let arg = fn.args.first {
    return arg.shape.map { $0 ?? 0 }
  }
  if let result = fn.results.first {
    return result.shape.map { $0 ?? 0 }
  }
  return []
}

public func makeCacheKey(
  module: StableHLOModule,
  backendKey: String,
  deviceKey: String,
  versionSalt: String,
  concreteShape: [Int],
  bucketing: ShapeBucketingPolicy,
  extraComponents: [String] = []
) -> (ShapeKey, String) {
  let dimSpecs = resolveDimSpecs(for: concreteShape, using: bucketing)
  let dimSummary = dimSpecs.map(describeDimSpec).joined(separator: ",")

  var baseComponents: [String] = [
    "backend=\(backendKey)",
    "device=\(deviceKey)",
    "salt=\(versionSalt)",
    "ir={\(module.textual())}"
  ]
  baseComponents.append(contentsOf: extraComponents)
  let irHash = fnv1a64(baseComponents.joined(separator: "|"))

  var fingerprintComponents = baseComponents
  fingerprintComponents.append("dims=\(dimSummary)")
  let fingerprint = fnv1a64(fingerprintComponents.joined(separator: "|"))

  let key = ShapeKey(
    fingerprint: fingerprint,
    versionSalt: versionSalt,
    dimSpecs: dimSpecs,
    deviceKey: deviceKey,
    backendKey: backendKey
  )

  return (key, irHash)
}

private func resolveDimSpecs(for shape: [Int], using policy: ShapeBucketingPolicy) -> [DimSpec] {
  if policy.dims.isEmpty {
    return inferredDimSpecs(for: shape)
  }
  precondition(policy.dims.count == shape.count, "Shape bucketing policy rank mismatch")
  return zip(policy.dims, shape).map { spec, value in
    switch spec {
    case .any:
      return .any
    case .exact(let n):
      return value == n ? .exact(n) : .exact(value)
    case .bucket(let lo, let hi):
      precondition(lo <= value && value <= hi, "Dimension \(value) outside bucket [\(lo), \(hi)]")
      return .bucket(lo: lo, hi: hi)
    }
  }
}

private func inferredDimSpecs(for shape: [Int]) -> [DimSpec] {
  guard !shape.isEmpty else { return [] }
  if shape.count <= 2 {
    return shape.map { .exact($0) }
  }
  return shape.map { value in
    let lo = max(0, (value / 64) * 64)
    let hi = max(lo, ((value + 63) / 64) * 64)
    return .bucket(lo: lo, hi: hi)
  }
}

private func describeDimSpec(_ spec: DimSpec) -> String {
  switch spec {
  case .exact(let n):
    return "exact: \(n)"
  case .any:
    return "any"
  case .bucket(let lo, let hi):
    return "bucket:[\(lo),\(hi)]"
  }
}

private func cacheWarmingEnabled() -> Bool {
  ProcessInfo.processInfo.environment["X10_CACHE_WARMING"] == "1"
}

private func cacheWarmingTopK() -> Int {
  let env = ProcessInfo.processInfo.environment
  let raw = env["X10_CACHE_WARMING_TOPK"].flatMap(Int.init) ?? 3
  return max(1, raw)
}
