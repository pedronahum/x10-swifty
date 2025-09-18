public struct ShapeKey: Hashable, Sendable {
  public let fingerprint: String
  public init(fingerprint: String) { self.fingerprint = fingerprint }

  public init(module m: StableHLOModule) {
    var parts: [String] = []
    for f in m.functions {
      parts.append("fn:\(f.name)")
      parts.append("args:\(f.args.map(Self.sig).joined(separator: ";"))")
      parts.append("rets:\(f.results.map(Self.sig).joined(separator: ";"))")
    }
    self.fingerprint = parts.joined(separator: "|")
  }

  private static func sig(_ v: StableHLOModule.Value) -> String {
    let dtype = Self.dtypeCode(v.dtype)
    let dims = v.shape.map { $0.map(String.init) ?? "?" }.joined(separator: ",")
    return "\(dtype)[\(dims)]"
  }

  private static func dtypeCode(_ d: DType) -> String {
    switch d {
    case .f16: return "f16"
    case .bf16: return "bf16"
    case .f32: return "f32"
    case .f64: return "f64"
    case .i32: return "i32"
    case .i64: return "i64"
    }
  }
}
