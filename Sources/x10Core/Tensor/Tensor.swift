import Foundation

public enum Device: Sendable, Equatable, CustomStringConvertible {
  case cpu(Int)     // index
  case gpu(Int)     // index

  public static var `default`: Device { .cpu(0) }
  public var description: String {
    switch self {
    case .cpu(let i): return "cpu(\(i))"
    case .gpu(let i): return "gpu(\(i))"
    }
  }
}

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

  public var description: String {
    "Tensor<\(Scalar.self)>(shape: \(shape), device: \(device))"
  }
}

public enum DType: Sendable {
  case f16, bf16, f32, f64, i32, i64
}
