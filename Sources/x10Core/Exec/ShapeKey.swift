public struct ShapeKey: Hashable, Sendable {
  public let fingerprint: String
  public let versionSalt: String
  public let dimSpecs: [DimSpec]
  public let deviceKey: String
  public let backendKey: String

  public init(
    fingerprint: String,
    versionSalt: String = "",
    dimSpecs: [DimSpec] = [],
    deviceKey: String = "",
    backendKey: String = ""
  ) {
    self.fingerprint = fingerprint
    self.versionSalt = versionSalt
    self.dimSpecs = dimSpecs
    self.deviceKey = deviceKey
    self.backendKey = backendKey
  }
}
