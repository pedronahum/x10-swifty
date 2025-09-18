import x10Core

public enum CacheWarm {
  /// Fire-and-forget warmup compiles. Safe no-op if entries are already cached.
  public static func schedule<B: Backend>(
    _ modules: [StableHLOModule], backend: B, options: CompileOptions = .init()
  ) {
    Task.detached {
      for m in modules { _ = try? await JIT.compileCached(m, with: backend, options: options) }
    }
  }
}
