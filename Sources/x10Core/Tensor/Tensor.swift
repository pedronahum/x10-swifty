import Foundation

// MARK: - Device

public enum Device: Sendable, Equatable, CustomStringConvertible {
  case cpu(Int)   // index
  case gpu(Int)   // index

  /// Default device can be overridden via env var: `X10_DEFAULT_DEVICE=cpu:0` or `gpu:1`.
  public static var `default`: Device {
    if let s = ProcessInfo.processInfo.environment["X10_DEFAULT_DEVICE"],
       let d = Device(parse: s) {
      return d
    }
    return .cpu(0)
  }

  /// Parses strings like "cpu:0" or "gpu:1".
  public init?(parse s: String) {
    let parts = s.split(separator: ":")
    guard parts.count == 2, let idx = Int(parts[1]) else { return nil }
    switch parts[0].lowercased() {
    case "cpu": self = .cpu(idx)
    case "gpu": self = .gpu(idx)
    default: return nil
    }
  }

  /// Optional convenience.
  public static func parse(_ s: String) -> Device? { Self.init(parse: s) }

  public var description: String {
    switch self {
    case .cpu(let i): return "cpu(\(i))"
    case .gpu(let i): return "gpu(\(i))"
    }
  }
}

// MARK: - Tensor

public struct Tensor<Scalar>: Sendable, CustomStringConvertible {
  public let shape: [Int]
  public let device: Device

  // Placeholder handle — in a real system this would be a device buffer.
  @usableFromInline
  var _id: UUID = UUID()

  public init(shape: [Int], on device: Device = .default) {
    self.shape = shape
    self.device = device
  }

  /// Convenience constructors (host-side placeholders for now).
  public static func zeros(shape: [Int], on device: Device = .default) -> Tensor<Scalar> {
    Tensor(shape: shape, on: device)
  }
  public static func ones(shape: [Int], on device: Device = .default) -> Tensor<Scalar> {
    Tensor(shape: shape, on: device)
  }

  public var description: String {
    "Tensor<\(Scalar.self)>(shape: \(shape), device: \(device))"
  }
}

// MARK: - DType

public enum DType: Sendable {
  case f16, bf16, f32, f64, i32, i64
}
