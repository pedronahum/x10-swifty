import Foundation
import x10Core
import x10InteropIREEC

enum IREEVMError: Error, LocalizedError {
  case runtime(String)

  var errorDescription: String? {
    switch self {
    case .runtime(let message): return message
    }
  }
}

/// Thin Swift wrapper over the C runtime shim. Not thread-safe yet but keeps the
/// lifetime and memory management ergonomic for the backend.
final class IREEVM {
  struct TensorInput {
    let shape: [Int]
    let dtype: DType
    let data: Data
  }

  struct TensorOutput {
    let shape: [Int]
    let dtype: DType
    let data: Data
  }

  private static var runtimeProbed = false
  private static var runtimeReady = false
  private static let probeLock = NSLock()

  private static func ensureRuntimeLoaded() -> Bool {
    probeLock.lock()
    defer { probeLock.unlock() }
    if runtimeProbed {
      return runtimeReady
    }
    runtimeProbed = true
    runtimeReady = x10_iree_runtime_load(nil) == 1
    return runtimeReady
  }

  static func isRuntimeReady() -> Bool {
    return ensureRuntimeLoaded()
  }

  private var handle: OpaquePointer?

  init(vmfb: Data) throws {
    guard Self.ensureRuntimeLoaded() else {
      throw IREEVMError.runtime(Self.lastErrorOr("failed to load IREE runtime"))
    }

    var created: OpaquePointer?
    let ok = vmfb.withUnsafeBytes { bytes -> Bool in
      guard let base = bytes.baseAddress else { return false }
      return x10_iree_vm_create_from_vmfb(base, bytes.count, &created) == 1
    }
    guard ok, let handle = created else {
      throw IREEVMError.runtime(Self.lastErrorOr("x10_iree_vm_create_from_vmfb failed"))
    }
    self.handle = handle
  }

  deinit {
    if let handle { x10_iree_vm_destroy(handle) }
  }

  func invoke(entry: String, inputs: [TensorInput]) throws -> [TensorOutput] {
    guard let handle else {
      throw IREEVMError.runtime("runtime handle released")
    }

    var cInputs: [x10_iree_runtime_tensor_t] = []
    cInputs.reserveCapacity(inputs.count)

    var shapePointers: [UnsafeMutablePointer<Int64>?] = []
    shapePointers.reserveCapacity(inputs.count)
    var shapeCounts: [Int] = []
    shapeCounts.reserveCapacity(inputs.count)

    var dataPointers: [UnsafeMutableRawPointer?] = []
    dataPointers.reserveCapacity(inputs.count)

    defer {
      for (ptr, count) in zip(shapePointers, shapeCounts) {
        guard let ptr else { continue }
        if count > 0 { ptr.deinitialize(count: count) }
        ptr.deallocate()
      }
      for ptr in dataPointers { ptr?.deallocate() }
    }

    for tensor in inputs {
      guard let cDType = Self.map(dtype: tensor.dtype) else {
        throw IREEVMError.runtime("unsupported dtype: \(tensor.dtype)")
      }
      let rank = Int32(tensor.shape.count)
      let shapePtr: UnsafeMutablePointer<Int64>?
      if rank > 0 {
        let ptr = UnsafeMutablePointer<Int64>.allocate(capacity: Int(rank))
        for (i, dim) in tensor.shape.enumerated() {
          ptr[i] = Int64(dim)
        }
        shapePtr = ptr
      } else {
        shapePtr = nil
      }
      shapePointers.append(shapePtr)
      shapeCounts.append(Int(rank))

      let byteCount = tensor.data.count
      let dataPtr: UnsafeMutableRawPointer?
      if byteCount > 0 {
        dataPtr = UnsafeMutableRawPointer.allocate(byteCount: byteCount,
                                                   alignment: MemoryLayout<UInt8>.alignment)
        tensor.data.copyBytes(to: dataPtr!.assumingMemoryBound(to: UInt8.self), count: byteCount)
      } else {
        dataPtr = nil
      }
      dataPointers.append(dataPtr)

      let cTensor = x10_iree_runtime_tensor_t(
        dtype: cDType,
        shape: shapePtr,
        rank: rank,
        data: dataPtr,
        byte_length: byteCount)
      cInputs.append(cTensor)
    }

    var resultsPtr: UnsafeMutablePointer<x10_iree_runtime_result_t>? = nil
    var resultCount: Int32 = 0
    let ok = entry.withCString { fnName in
      cInputs.withUnsafeMutableBufferPointer { buffer in
        x10_iree_vm_invoke(handle, fnName, buffer.baseAddress, Int32(buffer.count),
                           &resultsPtr, &resultCount) == 1
      }
    }

    guard ok, let rawResults = resultsPtr else {
      throw IREEVMError.runtime(Self.lastErrorOr("x10_iree_vm_invoke failed"))
    }

    var outputs: [TensorOutput] = []
    outputs.reserveCapacity(Int(resultCount))

    for idx in 0..<Int(resultCount) {
      let result = rawResults[idx]
      guard let dtype = Self.map(cType: result.dtype) else {
        x10_iree_runtime_free_results(rawResults, resultCount)
        throw IREEVMError.runtime("unsupported output dtype")
      }

      let shape: [Int]
      if let shapePtr = result.shape, result.rank > 0 {
        let count = Int(result.rank)
        let buffer = UnsafeBufferPointer(start: shapePtr, count: count)
        shape = buffer.map { Int($0) }
      } else {
        shape = []
      }

      let data: Data
      if let dataPtr = result.data, result.byte_length > 0 {
        data = Data(bytes: dataPtr, count: Int(result.byte_length))
      } else {
        data = Data()
      }

      outputs.append(TensorOutput(shape: shape, dtype: dtype, data: data))
    }

    x10_iree_runtime_free_results(rawResults, resultCount)
    return outputs
  }

  private static func lastErrorOr(_ fallback: String) -> String {
    guard let cStr = x10_iree_runtime_last_error() else { return fallback }
    let message = String(cString: cStr)
    return message.isEmpty ? fallback : message
  }

  private static func map(dtype: DType) -> x10_iree_dtype_t? {
    switch dtype {
    case .f16:  return X10_IREE_DTYPE_F16
    case .bf16: return X10_IREE_DTYPE_BF16
    case .f32:  return X10_IREE_DTYPE_F32
    case .f64:  return X10_IREE_DTYPE_F64
    case .i32:  return X10_IREE_DTYPE_I32
    case .i64:  return X10_IREE_DTYPE_I64
    }
  }

  private static func map(cType: x10_iree_dtype_t) -> DType? {
    switch cType {
    case X10_IREE_DTYPE_F16: return .f16
    case X10_IREE_DTYPE_BF16: return .bf16
    case X10_IREE_DTYPE_F32: return .f32
    case X10_IREE_DTYPE_F64: return .f64
    case X10_IREE_DTYPE_I32: return .i32
    case X10_IREE_DTYPE_I64: return .i64
    default: return nil
    }
  }
}
