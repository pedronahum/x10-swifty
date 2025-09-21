import Foundation
import x10Core
@_exported import x10InteropDLPackC

// MARK: - Capsule handle

/// Thin, value-semantic handle around the C capsule pointer.
/// Lifetime is managed explicitly via `DLPack.retain` / `DLPack.dispose`.
public struct DLPackCapsule: Equatable, @unchecked Sendable {
  public let raw: x10_dl_capsule_t?   // UnsafeMutablePointer<x10_dl_capsule>
  public init(raw: x10_dl_capsule_t?) { self.raw = raw }
  public static func == (lhs: DLPackCapsule, rhs: DLPackCapsule) -> Bool { lhs.raw == rhs.raw }
}

// MARK: - Type & device mapping utilities

public enum DLPackTypeCode: Int32 { case int = 0, uint = 1, float = 2, bfloat = 4 }

/// Map Swift `DType` → DLPack (code/bits/lanes).
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

/// Map x10 `Device` → DLPack (device_type/device_id).
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

// MARK: - Zero-copy helpers (capsule lifetime, metadata, aliasing)

public enum DLPack {
  /// Whether the C shim reports DLPack support is compiled in.
  public static var isAvailable: Bool { x10_dlpack_is_available() == 1 }

  /// Last error message from the C shim (if any).
  public static var lastError: String? {
    guard let c = x10_dlpack_last_error() else { return nil }
    return String(cString: c)
  }

  /// Increase the capsule's internal refcount and return a handle to the same capsule.
  @discardableResult
  public static func retain(_ cap: DLPackCapsule) -> DLPackCapsule {
    guard let p = cap.raw else { return cap }
    return DLPackCapsule(raw: x10_dlpack_retain(p))
  }

  /// Decrease the capsule's internal refcount and dispose if it reaches 0.
  public static func dispose(_ cap: DLPackCapsule) {
    if let p = cap.raw { x10_dlpack_dispose(p) }
  }

  /// Zero-copy: wrap a **malloc'ed** host buffer as a DLPack capsule that will `free()` the buffer on dispose.
  /// The memory must be heap-allocated and not used after passing ownership here.
  public static func wrapHostBufferFree(
    ptr: UnsafeMutableRawPointer,
    shape: [Int],
    dtype: DType
  ) throws -> DLPackCapsule {
    guard isAvailable else { throw DLPackError.notAvailable(lastError ?? "") }
    guard let t = dlType(for: dtype) else { throw DLPackError.invalid("unsupported dtype") }
    let dims64 = shape.map(Int64.init)
    let cap = dims64.withUnsafeBufferPointer { sp -> x10_dl_capsule_t? in
      x10_dlpack_wrap_host_buffer_free(
        ptr,
        sp.baseAddress,
        Int32(dims64.count),
        t.code, t.bits, t.lanes
      )
    }
    guard let c = cap else { throw DLPackError.cFailure(lastError ?? "wrapHostBufferFree failed") }
    return DLPackCapsule(raw: c)
  }

  /// Minimal metadata about the tensor.
  public struct Info: Sendable {
    public let deviceType: Int32, deviceId: Int32
    public let code: Int32, bits: Int32, lanes: Int32
    public let ndim: Int32
  }

  /// Return basic info (device, dtype, ndim) for a capsule.
  public static func basicInfo(_ cap: DLPackCapsule) -> Info? {
    guard let raw = cap.raw else { return nil }
    var dt: Int32 = 0, di: Int32 = 0, c: Int32 = 0, b: Int32 = 0, l: Int32 = 0, n: Int32 = 0
    guard x10_dlpack_basic_info(raw, &dt, &di, &c, &b, &l, &n) == 1 else { return nil }
    return Info(deviceType: dt, deviceId: di, code: c, bits: b, lanes: l, ndim: n)
  }

  /// Copy the shape out of the capsule (no allocation in C; this allocates a Swift array).
  public static func shape(_ cap: DLPackCapsule) -> [Int]? {
    guard let inf = basicInfo(cap), let raw = cap.raw else { return nil }
    var tmp = [Int64](repeating: 0, count: Int(inf.ndim))
    let got = x10_dlpack_shape(raw, &tmp, Int32(tmp.count))
    guard got == inf.ndim else { return nil }
    return tmp.map { Int($0) }
  }

  /// Borrow the data pointer from the capsule (zero-copy read access).
  public static func dataPointer(_ cap: DLPackCapsule) -> UnsafeMutableRawPointer? {
    guard let raw = cap.raw else { return nil }
    var ptr: UnsafeMutableRawPointer?
    guard x10_dlpack_data_ptr(raw, &ptr, nil) == 1 else { return nil }
    return ptr
  }
}

// MARK: - Copy helpers (portable, for when zero-copy isn’t possible)

public enum DLPackHost {
  /// Wrap a **copy** of a host buffer into a DLPack capsule (device metadata included).
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
      throw DLPackError.cFailure(DLPack.lastError ?? "wrapHostCopy failed")
    }
    return DLPackCapsule(raw: c)
  }

  public static func toHostData(_ cap: DLPackCapsule) throws -> Data {
    guard DLPack.isAvailable else { throw DLPackError.notAvailable(DLPack.lastError ?? "") }
    guard let ptr = cap.raw else { throw DLPackError.invalid("null capsule") }

    // Probe required size (C wants Int32*).
    var written32: Int32 = 0
    guard x10_dlpack_to_host_copy(ptr, nil, 0, &written32) == 1 else {
      throw DLPackError.cFailure(DLPack.lastError ?? "probe failed")
    }
    let need = Int(written32)

    var out = Data(count: need)
    var writtenAgain32: Int32 = 0
    let ok = out.withUnsafeMutableBytes { mb -> Int32 in
      x10_dlpack_to_host_copy(ptr, mb.baseAddress, mb.count, &writtenAgain32)
    }
    guard ok == 1, Int(writtenAgain32) == need else {
      throw DLPackError.cFailure(DLPack.lastError ?? "copy failed (wrote \(writtenAgain32), need \(need))")
    }
    return out
  }

}
