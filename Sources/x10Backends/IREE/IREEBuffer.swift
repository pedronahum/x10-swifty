import Foundation
import x10Core
import x10Runtime
import x10InteropDLPack

/// Backend-specific device buffer for IREE backend.
/// For the CLI path we store a host mirror (Data). Later we'll add DLPack/device aliases.
public struct IREEDeviceBuffer: Buffer, Sendable {
  public let shape: [Int]
  public let dtype: DType

  enum Storage: @unchecked Sendable {
    case host(Data)                 // host mirror
    case dlcap(DLPackCapsule)       // zero-copy alias via DLPack (future in-process path)
  }
  let storage: Storage

  // Internal initializer (backend use).
  init(shape: [Int], dtype: DType, storage: Storage) {
    self.shape = shape
    self.dtype = dtype
    self.storage = storage
  }

  // Convenience for host data.
  init(shape: [Int], dtype: DType, host: Data) {
    self.init(shape: shape, dtype: dtype, storage: .host(host))
  }

  // Convert host storage to the textual scalar list iree-run-module expects.
  // e.g. ["1","2","3","4","5","6"]
  func asScalarStringsForCLI() -> [String]? {
    switch storage {
    case .host(let data):
      switch dtype {
      case .f32:
        return data.withUnsafeBytes { buf in
          Array(buf.bindMemory(to: Float.self)).map { String(format: "%g", $0) }
        }
      case .f16, .bf16:
        // For CLI demos we usually upcast half to f32 textual values.
        return data.withUnsafeBytes { buf -> [String] in
          let words = Array(buf.bindMemory(to: UInt16.self))
          return words.map { _ in "0" } // simple placeholder if you aren't feeding half yet
        }
      case .i32:
        return data.withUnsafeBytes { buf in
          Array(buf.bindMemory(to: Int32.self)).map { String($0) }
        }
      case .i64:
        return data.withUnsafeBytes { buf in
          Array(buf.bindMemory(to: Int64.self)).map { String($0) }
        }
      case .f64:
        return data.withUnsafeBytes { buf in
          Array(buf.bindMemory(to: Double.self)).map { String(format: "%g", $0) }
        }
      }
    case .dlcap(_):
      return nil // for in-process runtime we won't go through CLI text
    }
  }
}
