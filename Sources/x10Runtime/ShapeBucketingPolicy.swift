import x10Core

public struct ShapeBucketingPolicy: Sendable, Hashable {
  public var dims: [DimSpec]

  public init(dims: [DimSpec]) {
    self.dims = dims
  }

  public static let `default` = ShapeBucketingPolicy(dims: [])
}
