import Foundation
import x10Core

public actor CacheWarmer {
  public static let shared = CacheWarmer()

  public func warm(
    module: StableHLOModule,
    backend: some Backend,
    device: Device,
    policy: ShapeBucketingPolicy,
    shapes: [[Int]]
  ) async {
    let uniqueShapes = Array(Set(shapes))
    guard !uniqueShapes.isEmpty else { return }
    for shape in uniqueShapes {
      var options = CompileOptions(
        device: device,
        shapeBucketing: policy,
        shapeHint: shape,
        isWarmup: true
      )
      options.flags = [:]
      _ = try? await JIT.compileCached(module, with: backend, options: options)
    }
  }
}
