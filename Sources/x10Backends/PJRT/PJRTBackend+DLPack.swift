import Foundation
import x10Core
import x10Runtime
import x10InteropDLPack

extension PJRTBackend {
  /// Import a DLPack capsule as a zero-copy alias (CPU).
  public func importDLPack(_ cap: DLPackCapsule) throws -> PJRTDeviceBuffer {
    if let buf = PJRTDeviceBuffer(fromDLPack: cap) { return buf }
    throw NSError(domain: "PJRT", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot import DLPack capsule (non-CPU or unsupported dtype)"])
  }

  /// Export a PJRT buffer to DLPack.
  /// - Zero-copy if the buffer is already a DLPack alias (returns a retained capsule).
  /// - Copying fallback if the buffer is a host Data mirror.
  public func exportDLPack(_ buf: PJRTDeviceBuffer, device: Device = .cpu(0)) throws -> DLPackCapsule {
    switch buf.storage {
    case .dlcap(let cap):
      return DLPack.retain(cap) // zero-copy
    case .stub(let data):
      // Fallback: allocate and copy (not zero-copy).
      let nbytes = data.count
      let ptr = UnsafeMutableRawPointer.allocate(byteCount: nbytes, alignment: MemoryLayout<UInt8>.alignment)
      _ = data.withUnsafeBytes { src in
        memcpy(ptr, src.baseAddress!, nbytes)
      }
      return try DLPack.wrapHostBufferFree(ptr: ptr, shape: buf.shape, dtype: buf.dtype)
    case .handle(_):
      throw NSError(domain: "PJRT", code: 2, userInfo: [NSLocalizedDescriptionKey: "export from device handle not implemented yet"])
    }
  }


}
