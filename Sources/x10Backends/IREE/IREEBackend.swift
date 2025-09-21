import Foundation
import x10Core
import x10Runtime
import x10Diagnostics
import x10InteropDLPack   // for DLPack copy-out in fromDevice

/// IREE backend (CLI-backed).
/// - `compile`: StableHLO -> VMFB via `iree-compile`, cached in `IREEExecutableRegistry`.
/// - `execute`: runs VMFB via `iree-run-module` and returns an output buffer.
/// - Buffers: `IREEDeviceBuffer` (host mirror for CLI path; DLPack support for in-process path later).
public struct IREEBackend: Backend {
  // MARK: - Device model

  public struct Dev: Hashable, Sendable {
    public let ordinal: Int
    public init(ordinal: Int) { self.ordinal = ordinal }
  }

  public init() { Self.ensureCacheRegistration() }

  public func devices() throws -> [Dev] { [Dev(ordinal: 0)] }
  public func deviceDescription(_ d: Dev) -> String { "cpu:\(d.ordinal) (iree-cli)" }

  // MARK: - Helpers

  @inline(__always) private func _numElements(_ dims: [Int]) -> Int { dims.reduce(1, *) }

  @inline(__always) private func _byteCount(of dtype: DType) -> Int {
    switch dtype {
    case .f16, .bf16: return 2
    case .f32, .i32:  return 4
    case .i64, .f64:  return 8
    }
  }

  @inline(__always) private func _token(for dtype: DType) -> String {
    switch dtype {
    case .f16:  return "f16"
    case .bf16: return "bf16"
    case .f32:  return "f32"
    case .f64:  return "f64"
    case .i32:  return "i32"
    case .i64:  return "i64"
    }
  }

  @inline(__always) private func _dtype(from token: String) -> DType? {
    switch token {
    case "f16": return .f16
    case "bf16": return .bf16
    case "f32": return .f32
    case "f64": return .f64
    case "i32": return .i32
    case "i64": return .i64
    default: return nil
    }
  }

  // MARK: - Memory & transfer

  public func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    let n = _numElements(shape) * _byteCount(of: dtype)
    return IREEDeviceBuffer(shape: shape, dtype: dtype, host: Data(count: n))
  }

  public func toDevice(_ host: UnsafeRawBufferPointer,
                       shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    let n = _numElements(shape) * _byteCount(of: dtype)
    let count = min(n, host.count)
    let data = Data(bytes: host.baseAddress!, count: count)
    return IREEDeviceBuffer(shape: shape, dtype: dtype, host: data)
  }

  public func fromDevice(_ buffer: Buffer) throws -> [UInt8] {
    guard let b = buffer as? IREEDeviceBuffer else { return [] }
    switch b.storage {
    case .host(let data):
      return Array(data)

    case .dlcap(let cap):
      // Copy out via DLPack shim (alias stays zero-copy internally; copy is for host inspection).
      var written32: Int32 = 0
      guard x10_dlpack_to_host_copy(cap.raw, nil, 0, &written32) == 1 else { return [] }
      var out = Data(count: Int(written32))
      let _ = out.withUnsafeMutableBytes { mb in
        x10_dlpack_to_host_copy(cap.raw, mb.baseAddress, mb.count, &written32)
      }
      return Array(out)
    }
  }

  // MARK: - Compile (StableHLO -> VMFB via IREE CLI)

  public func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    // Backend target: explicit flag → env → default
    let target: String = options.flags["iree_target"]
      ?? ProcessInfo.processInfo.environment["X10_IREE_TARGET"]
      ?? "llvm-cpu" // default to CPU; set env/flag to "metal" or "vulkan-spirv" as desired

    // StableHLO textual; should be a proper MLIR module with `func.func @main`
    let text = stablehlo.textual()

    // Ensure CLI is present
    guard IREECompileCLI.find() != nil else {
      throw NSError(domain: "IREE", code: 7001,
                    userInfo: [NSLocalizedDescriptionKey:
                      "iree-compile not available (set X10_IREE_PREFIX / X10_IREE_BIN)"])
    }

    // Compile
    let vmfb = try IREECompileCLI.compileStableHLO(text, target: target)

    // Cache artifact for the executable
    let exec = Executable()
    let preferRuntime = Self.runtimeFlagEnabled(options.flags["iree_runtime"])
    IREEExecutableRegistry.shared.put(id: exec.id, vmfb: vmfb, defaultDeviceOrdinal: 0, preferRuntime: preferRuntime)
    return exec
  }

  // MARK: - Execute (VMFB via iree-run-module)

  public func execute(
    _ exec: Executable,
    inputs: [Buffer],
    stream: x10Runtime.Stream?   // <— fully-qualified to avoid Foundation.Stream clash
  ) async throws -> [Buffer] {
    // Retrieve cached VMFB
    guard let vmfb = IREEExecutableRegistry.shared.getVMFB(id: exec.id) else {
      throw NSError(domain: "IREE", code: 7101,
                    userInfo: [NSLocalizedDescriptionKey:
                      "VMFB not found for exec \(exec.id). Did you call compile()?"])
    }

    let env = ProcessInfo.processInfo.environment
    if env["X10_IREE_DISABLE"] == "1" {
      return try cliExecute(vmfb: vmfb, inputs: inputs)
    }

    let runtimeRequested = Self.runtimeFlagEnabled(env["X10_IREE_RUNTIME"]) ||
      IREEExecutableRegistry.shared.shouldPreferRuntime(id: exec.id)

    if runtimeRequested {
      do {
        return try runtimeExecute(vmfb: vmfb, entry: "main", inputs: inputs)
      } catch let error as NSError where error.domain == "IREE" && error.code == 7110 {
        if env["X10_IREE_VERBOSE"] == "1" {
          let message = "[IREE] runtime unavailable (\(error.localizedDescription)); falling back to CLI\n"
          FileHandle.standardError.write(Data(message.utf8))
        }
      }
    }

    return try cliExecute(vmfb: vmfb, inputs: inputs)
  }

  private func cliExecute(vmfb: Data, inputs: [Buffer]) throws -> [Buffer] {
    // Ensure runner exists
    guard IREEExecuteCLI.find() != nil else {
      throw NSError(domain: "IREE", code: 7102,
                    userInfo: [NSLocalizedDescriptionKey:
                      "iree-run-module not available (set X10_IREE_PREFIX / X10_IREE_RUN_BIN)"])
    }
    // Convert inputs to CLI text: one --input=... flag per tensor.
    let cliInputs: [String] = try inputs.map { anyBuf in
      if let ib = anyBuf as? IREEDeviceBuffer, let scalars = ib.asScalarStringsForCLI() {
        return IREEExecuteCLI.formatInput(shape: ib.shape, dtypeToken: _token(for: ib.dtype), scalars: scalars)
      } else {
        // Fallback: copy to host and encode scalars based on dtype
        let raw = try fromDevice(anyBuf)
        let shape: [Int]
        let dtype: DType
        if let ib = anyBuf as? IREEDeviceBuffer {
          shape = ib.shape; dtype = ib.dtype
        } else {
          shape = [raw.count / MemoryLayout<Float>.stride]
          dtype = .f32
        }

        func scalars<T>(_ type: T.Type, _ f: (T) -> String = { "\($0)" }) -> [String] {
          raw.withUnsafeBytes { Array($0.bindMemory(to: T.self)).map(f) }
        }

        switch dtype {
        case .f32:
          let vals: [Float] = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
          return IREEExecuteCLI.formatInput(shape: shape, dtypeToken: "f32",
                                            scalars: vals.map { String(format: "%g", $0) })
        case .f64:
          return IREEExecuteCLI.formatInput(shape: shape, dtypeToken: "f64", scalars: scalars(Double.self))
        case .i32:
          return IREEExecuteCLI.formatInput(shape: shape, dtypeToken: "i32", scalars: scalars(Int32.self))
        case .i64:
          return IREEExecuteCLI.formatInput(shape: shape, dtypeToken: "i64", scalars: scalars(Int64.self))
        case .f16, .bf16:
          // For CLI input we don't serialize half scalars yet; fill zeros of correct length.
          return IREEExecuteCLI.formatInput(shape: shape, dtypeToken: _token(for: dtype),
                                            scalars: Array(repeating: "0", count: _numElements(shape)))
        }
      }
    }

    // Run & parse first result tensor
    let res = try IREEExecuteCLI.runAndParse(vmfb: vmfb, entry: "main", inputs: cliInputs)

    // Map dtype token
    guard let outDType = _dtype(from: res.dtypeToken) else {
      throw NSError(domain: "IREE", code: 7103,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported output dtype: \(res.dtypeToken)"])
    }

    // Pack scalars back into bytes
    let outData: Data
    switch outDType {
    case .f32:
      var arr = res.scalars.map { Float($0) }
      outData = Data(bytes: &arr, count: arr.count * MemoryLayout<Float>.stride)
    case .f64:
      var arr = res.scalars.map { Double($0) }
      outData = Data(bytes: &arr, count: arr.count * MemoryLayout<Double>.stride)
    case .i32:
      var arr = res.scalars.map { Int32($0) }
      outData = Data(bytes: &arr, count: arr.count * MemoryLayout<Int32>.stride)
    case .i64:
      var arr = res.scalars.map { Int64($0) }
      outData = Data(bytes: &arr, count: arr.count * MemoryLayout<Int64>.stride)
    case .f16, .bf16:
      // CLI path: we don't parse half textual scalars yet—return zeroed bytes with correct size.
      outData = Data(count: _numElements(res.shape) * 2)
    }

    let outBuf = IREEDeviceBuffer(shape: res.shape, dtype: outDType, host: outData)
    Diagnostics.executeCallsIreeCLI.inc()
    return [outBuf]
  }

  public func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  public func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }  // fully-qualified
  public func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }     // fully-qualified
}

private extension IREEBackend {
  static func runtimeFlagEnabled(_ value: String?) -> Bool {
    guard let value = value else { return false }
    switch value.lowercased() {
    case "1", "true", "yes", "y", "on": return true
    default: return false
    }
  }

  func runtimeExecute(vmfb: Data, entry: String, inputs: [Buffer]) throws -> [Buffer] {
    guard IREEVM.isRuntimeReady() else {
      throw NSError(domain: "IREE", code: 7110,
                    userInfo: [NSLocalizedDescriptionKey:
                      "IREE runtime shim not available (set X10_IREE_RUNTIME_LIB)"])
    }

    let vm = try IREEVM(vmfb: vmfb)
    let prepared = try inputs.map { try runtimeInput(from: $0) }
    let outputs = try vm.invoke(entry: entry, inputs: prepared)
    Diagnostics.executeCallsIreeRuntime.inc()
    return outputs.map { IREEDeviceBuffer(shape: $0.shape, dtype: $0.dtype, host: $0.data) }
  }

  func runtimeInput(from buffer: Buffer) throws -> IREEVM.TensorInput {
    guard let ib = buffer as? IREEDeviceBuffer else {
      throw NSError(domain: "IREE", code: 7111,
                    userInfo: [NSLocalizedDescriptionKey: "Expected IREEDeviceBuffer input"])
    }

    let data: Data
    switch ib.storage {
    case .host(let hostData):
      data = hostData
    case .dlcap:
      let raw = try fromDevice(buffer)
      data = Data(raw)
    }

    return IREEVM.TensorInput(shape: ib.shape, dtype: ib.dtype, data: data)
  }
}
