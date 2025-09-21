// Sources/x10Runtime/Compilation.swift

import Foundation
import x10Core
import x10Diagnostics

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

    // Key the cache by IR+options+device.
    let key = makeCacheKey(stablehlo, backend: backend, options: opts)

    if let hit = await ExecutableCache.shared.get(key) {
      return hit
    }

    Diagnostics.uncachedCompiles.inc()
    let exec = try backend.compile(stablehlo: stablehlo, options: opts)
    await ExecutableCache.shared.put(exec, for: key)
    return exec
  }

  // MARK: - Private helpers (kept inside the JIT type)

  /// Builds a stable cache key from the IR and options, then hashes it.
  private static func makeCacheKey<B: Backend>(
    _ module: StableHLOModule,
    backend: B,
    options: CompileOptions
  ) -> ShapeKey {
    // IR as printed today (tests already rely on textual() output elsewhere).
    let ir = module.textual()

    // Device identity (e.g., "cpu:0"/"gpu:0"), see Device+StableKey.swift.
    let deviceKey = options.device?.stableKey ?? "cpu:0"

    // Precision policy as terse triplet.
    let prec = "a:\(precCode(options.precision.activations))," +
               "m:\(precCode(options.precision.matmul))," +
               "acc:\(precCode(options.precision.accumulators))"

    // Flags stabilized by sorting keys.
    let flagStr = options.flags
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ";")

    // Compose a single string and hash it for a compact fingerprint.
    let composed = [
      "backend=\(String(describing: type(of: backend)))",
      "device=\(deviceKey)",
      "precision=\(prec)",
      "flags=\(flagStr)",
      "ir={\(ir)}"
    ].joined(separator: "|")

    let fp = fnv1a64(composed)
    return ShapeKey(fingerprint: fp)
  }

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
