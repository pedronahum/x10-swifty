import Foundation
import x10Core
import X10DLPACKC

public enum DLPack {
  public static var isAvailable: Bool { x10_dlpack_is_available() == 1 }
  public static var lastError: String? {
    let c = x10_dlpack_last_error()
    return c != nil ? String(cString: c!) : nil
  }
}

/// Hold the **typed, mutable C pointer** so we can call the shim without casts.
public final class DLPackCapsule: @unchecked Sendable, Equatable {
  let raw: x10_dl_capsule_t?   // <- UnsafeMutablePointer<x10_dl_capsule>

  public init(raw: x10_dl_capsule_t?) { self.raw = raw }

  deinit {
    if let p = raw {
      _ = x10_dlpack_dispose(p)
    }
  }

  public static func == (lhs: DLPackCapsule, rhs: DLPackCapsule) -> Bool { lhs.raw == rhs.raw }
}

// MARK: - Type & device mapping

public enum DLPackTypeCode: Int32 { case int = 0, uint = 1, float = 2, bfloat = 4 }

@inlinable public func dlType(for dtype: DType) -> (code: Int32, bits: Int32, lanes: Int32)? {
  switch dtype {
  case .i32:  return (DLPackTypeCode.int.rawValue,    32, 1)
  case .i64:  return (DLPackTypeCode.int.rawValue,    64, 1)
  case .f16:  return (DLPackTypeCode.float.rawValue,  16, 1)
  case .bf16: return (DLPackTypeCode.bfloat.rawValue, 16, 1)
  case .f32:  return (DLPackTypeCode.float.rawValue,  32, 1)
  case .f64:  return (DLPackTypeCode.float.rawValue,  64, 1)
  }
}

public enum DLPackDeviceType: Int32 { case cpu = 1, cuda = 2, vulkan = 7, metal = 8, rocm = 10 }

@inlinable public func dlDevice(for device: Device) -> (type: Int32, id: Int32) {
  switch device {
  case .cpu(let n): return (DLPackDeviceType.cpu.rawValue, Int32(n))
  case .gpu(let n):
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      return (DLPackDeviceType.metal.rawValue, Int32(n))
    #else
      return (DLPackDeviceType.vulkan.rawValue, Int32(n))
    #endif
  }
}

public enum DLPackError: Error, CustomStringConvertible, Sendable {
  case notAvailable(String)
  case invalid(String)
  case cFailure(String)
  public var description: String {
    switch self {
    case .notAvailable(let s): return "DLPack not available: \(s)"
    case .invalid(let s): return "Invalid DLPack usage: \(s)"
    case .cFailure(let s): return "DLPack C error: \(s)"
    }
  }
}

// MARK: - Host copy helpers

public enum DLPackHost {
  /// Create a capsule by copying a host buffer. Compatible with any device type.
  public static func wrapHostCopy(
    bytes: UnsafeRawBufferPointer,
    shape: [Int],
    dtype: DType,
    device: Device
  ) throws -> DLPackCapsule {
    guard DLPack.isAvailable else { throw DLPackError.notAvailable(DLPack.lastError ?? "") }
    guard let t = dlType(for: dtype) else { throw DLPackError.invalid("unsupported dtype") }
    let dev = dlDevice(for: device)

    var cap: x10_dl_capsule_t? = nil
    let ok = shape.map(Int64.init).withUnsafeBufferPointer { shp -> Int32 in
      x10_dlpack_wrap_host_copy(
        bytes.baseAddress, bytes.count,
        shp.baseAddress, Int32(shape.count),
        t.code, t.bits, t.lanes,
        dev.type, dev.id,
        &cap)
    }
    guard ok == 1, let c = cap else {
      throw DLPackError.cFailure(DLPack.lastError ?? "wrap failed")
    }
    return DLPackCapsule(raw: c)
  }

  /// Copy tensor bytes back to a Data blob.
  public static func toHostData(_ cap: DLPackCapsule) throws -> Data {
    guard DLPack.isAvailable else { throw DLPackError.notAvailable(DLPack.lastError ?? "") }
    guard let ptr = cap.raw else { throw DLPackError.invalid("null capsule") }

    // Probe size
    var written: Int = 0
    guard x10_dlpack_to_host_copy(ptr, nil, 0, &written) == 1 else {
      throw DLPackError.cFailure(DLPack.lastError ?? "probe failed")
    }

    var out = Data(count: written)
    let ok = out.withUnsafeMutableBytes { mb -> Int32 in
      x10_dlpack_to_host_copy(ptr, mb.baseAddress, mb.count, &written)
    }
    guard ok == 1, written == out.count else {
      throw DLPackError.cFailure(DLPack.lastError ?? "copy failed")
    }
    return out
  }
}
