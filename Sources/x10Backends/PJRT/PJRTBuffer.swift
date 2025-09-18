import Foundation
import x10Core
import x10Runtime   // <-- Buffer lives here

/// Backend-specific device buffer for the PJRT backend.
/// In stub mode, this just holds host-side bytes so we can roundtrip data in tests.
public struct PJRTDeviceBuffer: Buffer, Sendable {
  public let shape: [Int]
  public let dtype: DType

  // Internal storage variants for now; we don't expose them publicly.
  // Conform to Sendable since PJRTDeviceBuffer is Sendable.
  // PJRT handles are owned on the C/runtime side; we never share them unsafely
  // across tasks from Swift. Mark unchecked to satisfy Swift 6 Sendable checks.
  enum Storage: @unchecked Sendable {
    case stub(Data)            // host mirror (stub path)
    case handle(OpaquePointer) // placeholder for future PJRT_Buffer
  }

  let storage: Storage

  // Internal initializer (no need to expose publicly yet).
  init(shape: [Int], dtype: DType, storage: Storage) {
    self.shape = shape
    self.dtype = dtype
    self.storage = storage
  }
}

// MARK: - helpers (internal)
@inlinable func _byteCount(of dtype: DType) -> Int {
  switch dtype {
  case .f16, .bf16: return 2
  case .f32, .i32:  return 4
  case .f64, .i64:  return 8
  }
}

@inlinable func _numElements(_ shape: [Int]) -> Int {
  shape.reduce(1, *)
}
