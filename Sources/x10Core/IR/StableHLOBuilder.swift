public struct StableHLOModule {
  public init() {}
}

public struct IRBuilder {
  public init() {}
  public mutating func buildPlaceholder() -> StableHLOModule { StableHLOModule() }
}
