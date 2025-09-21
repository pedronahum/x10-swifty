

public extension DType {
  var ireeToken: String {
    switch self {
    case .f16: return "f16"
    case .bf16: return "bf16"
    case .f32: return "f32"
    case .f64: return "f64"
    case .i32: return "i32"
    case .i64: return "i64"
    }
  }

  static func fromIREE(token: String) -> DType? {
    switch token {
    case "f16": return .f16
    case "bf16": return .bf16
    case "f32": return .f32
    case "f64": return .f64
    case "i32": return .i32
    case "i64": return .i64
    default: return nil
    }
  }

  var byteWidth: Int {
    switch self {
    case .f16, .bf16: return 2
    case .f32, .i32:  return 4
    case .i64, .f64:  return 8
    }
  }
}
