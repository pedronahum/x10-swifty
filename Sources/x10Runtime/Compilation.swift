import x10Core
import x10Diagnostics
import Foundation

public enum JIT {
  /// Keep the original shape-only key if callers really need it elsewhere.
  public static func key(for module: StableHLOModule) -> ShapeKey {
    ShapeKey(module: module)
  }

  public static func compile<B: Backend>(
    _ module: StableHLOModule,
    with backend: B,
    options: CompileOptions = .init()
  ) throws -> Executable {
    try backend.compile(stablehlo: module, options: options)
  }

  public static func compileCached<B: Backend>(
    _ module: StableHLOModule,
    with backend: B,
    options: CompileOptions = .init()
  ) async throws -> Executable {
    // 1) Ensure options carry the current device (task-local default).
    var opts = options
    if opts.device == nil { opts.device = DeviceScope.current }

    // 2) Build a richer cache key that includes backend, device & precision.
    let cacheKey = makeCacheKey(module, backend: backend, options: opts)

    if let hit = await ExecutableCache.shared.get(cacheKey) { return hit }

    // 3) Miss: optionally write IR to disk for debugging.
    if IRStore.shouldWriteIR(opts) {
      IRStore.write(text: module.textual(),
                    keyFingerprint: cacheKey.fingerprint,
                    backendName: String(reflecting: B.self))
    }

    Diagnostics.uncachedCompiles.inc()
    let exec = try backend.compile(stablehlo: module, options: opts)
    await ExecutableCache.shared.put(exec, for: cacheKey)
    return exec
  }

  // MARK: - Private helpers

  private static func makeCacheKey<B: Backend>(
  _ module: StableHLOModule,
  backend: B,
  options: CompileOptions
) -> ShapeKey {
  var parts: [String] = []
  let cacheVersion = ProcessInfo.processInfo.environment["X10_CACHE_VERSION"] ?? "v1"
  parts.append("ver:\(cacheVersion)")
  parts.append("be:\(String(reflecting: B.self))")
  parts.append("shape:\(ShapeKey(module: module).fingerprint)")
  parts.append("dev:\(options.device?.stableKey ?? "-")")
  let p = options.precision
  parts.append("prec:\(precCode(p.activations))/\(precCode(p.matmul))/\(precCode(p.accumulators))")
  if !options.flags.isEmpty {
    let flags = options.flags.sorted { $0.key < $1.key }
                             .map { "\($0.key)=\($0.value)" }
                             .joined(separator: ",")
    parts.append("flags:\(flags)")
  }
  return ShapeKey(fingerprint: parts.joined(separator: "|"))
}

  private static func precCode(_ p: PrecisionPolicy.Precision) -> String {
    switch p {
    case .f16: return "f16"
    case .bf16: return "bf16"
    case .fp8: return "fp8"
    case .fp32: return "fp32"
    }
  }
}
