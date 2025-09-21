import Foundation
import x10Core
import x10Runtime
import x10InteropDLPack

/// Backend-specific device buffer for PJRT backend.
/// In stub mode, this can be a host alias (DLPack) or a host mirror (Data).
public struct PJRTDeviceBuffer: Buffer, Sendable {
  public let shape: [Int]
  public let dtype: DType

  enum Storage: @unchecked Sendable {
    case stub(Data)                 // host mirror (copy-based)
    case dlcap(DLPackCapsule)       // zero-copy alias to host memory via DLPack
    case handle(OpaquePointer)      // placeholder for a future PJRT_Buffer
  }
  let storage: Storage

  // INTERNAL initializer: used by the backend only.
  init(shape: [Int], dtype: DType, storage: Storage) {
    self.shape = shape
    self.dtype = dtype
    self.storage = storage
  }

  // Public convenience for zero-copy import from a DLPack capsule.
  public init?(fromDLPack cap: DLPackCapsule) {
    guard let info = DLPack.basicInfo(cap), info.deviceType == 1 /*kDLCPU*/ else { return nil }
    guard let shp = DLPack.shape(cap) else { return nil }
    // Map dtype
    let dt: DType
    switch (info.code, info.bits) {
    case (2, 32): dt = .f32
    case (2, 16): dt = .f16
    case (4, 16): dt = .bf16
    case (0, 32): dt = .i32
    case (0, 64): dt = .i64
    default: return nil
    }
    self.shape = shp
    self.dtype = dt
    self.storage = .dlcap(DLPack.retain(cap))
  }
}


@inlinable func _numElements(_ shape: [Int]) -> Int {
  shape.reduce(1, *)
}
