import Foundation
import x10Core
import x10Runtime
import PJRTC
import x10InteropDLPack   // NEW

public struct PJRTBackend: Backend {
  public struct Dev: Hashable, Sendable {
    public let ordinal: Int
    public init(ordinal: Int) { self.ordinal = ordinal }
  }

    /// Map a high-level Device to a backend ordinal. (Both cpu/gpu use index today.)
  private func deviceOrdinal(_ d: Device?) -> Int32 {
    guard let d = d else { return 0 }
    switch d {
    case .cpu(let n): return Int32(n)
    case .gpu(let n): return Int32(n)
    }
  }

  // Helpers
  @inline(__always) fileprivate func _byteCount(of dtype: DType) -> Int {
    switch dtype {
    case .f16, .bf16: return 2
    case .f32, .i32:  return 4
    case .i64:        return 8
    case .f64:        return 8
    }
  }


  // === memory / transfer stubs (satisfy Backend protocol) ===
    // === memory / transfer (stub today) ===

  public func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    let nbytes = _numElements(shape) * _byteCount(of: dtype)
    let data = Data(count: nbytes)
    return PJRTDeviceBuffer(shape: shape, dtype: dtype, storage: .stub(data))
  }

  public func toDevice(_ host: UnsafeRawBufferPointer,
                       shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    let expected = _numElements(shape) * _byteCount(of: dtype)
    let count = min(expected, host.count)
    let data = Data(bytes: host.baseAddress!, count: count)
    return PJRTDeviceBuffer(shape: shape, dtype: dtype, storage: .stub(data))
  }

  public func fromDevice(_ buffer: Buffer) throws -> [UInt8] {
    if let b = buffer as? PJRTDeviceBuffer {
      switch b.storage {
      case .stub(let data):
        return Array(data)
      case .dlcap(let cap):
        // Copy out via shim (still zero-copy alias internally; copy only for host inspection)
        let n = _numElements(b.shape) * _byteCount(of: b.dtype)
        var out = Data(count: n)
        var written32: Int32 = 0
        let ok = out.withUnsafeMutableBytes { mb -> Int32 in
          x10_dlpack_to_host_copy(cap.raw, mb.baseAddress, mb.count, &written32)
        }
        guard ok == 1, Int(written32) == n else {
          return Array(out.prefix(max(0, Int(written32))))
        }
        return Array(out)

      case .handle(_):
        return [] // not implemented yet
      }
    }
    return []
  }


  


  public init() {}

  public func devices() throws -> [Dev] {
    _ = x10_pjrt_load(nil as UnsafePointer<CChar>?)

    var client: x10_pjrt_client_t? = nil
    guard x10_pjrt_client_create(&client) == 1, let c = client else { return [] }
    defer { x10_pjrt_client_destroy(c) }

    var count: Int32 = 0
    guard x10_pjrt_client_device_count(c, &count) == 1 else { return [] }
    return (0..<Int(count)).map { Dev(ordinal: $0) }
  }

  public func deviceDescription(_ d: Dev) -> String {
    var buf = [CChar](repeating: 0, count: 64)
    let need = x10_pjrt_device_description(Int32(d.ordinal), &buf, buf.count)
    if need + 1 > buf.count {
      buf = [CChar](repeating: 0, count: need + 1)
      _ = x10_pjrt_device_description(Int32(d.ordinal), &buf, buf.count)
    }
    return String(cString: buf)
  }

  // === compile/execute via shim (stub or real) ===
    public func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    _ = x10_pjrt_load(nil as UnsafePointer<CChar>?)

    var client: x10_pjrt_client_t? = nil
    guard x10_pjrt_client_create(&client) == 1, let c = client else {
      return Executable()
    }
    defer { x10_pjrt_client_destroy(c) }

    let text = stablehlo.textual()
    let optsJSON = options.toJSON()

    var execHandle: x10_pjrt_executable_t? = nil
    let ok: Int32 = text.utf8CString.withUnsafeBufferPointer { p in
      optsJSON.utf8CString.withUnsafeBufferPointer { o in
        x10_pjrt_compile_stablehlo(
          c,
          p.baseAddress, p.count - 1,
          o.baseAddress,                     // JSON string (nul-terminated)
          &execHandle)
      }
    }

    let exec = Executable()
    if ok == 1, let eh = execHandle {
      let ord = deviceOrdinal(options.device)
      PJRTExecutableRegistry.shared.put(id: exec.id, handle: eh, defaultDeviceOrdinal: ord)
    }
    return exec
  }



  public func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] {
    if let entry = PJRTExecutableRegistry.shared.getEntry(exec.id) {
      _ = x10_pjrt_execute(entry.handle, entry.defaultDeviceOrdinal)
    }
    return inputs // stub passthrough for now
  }


  public func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  public func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
  public func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
}
