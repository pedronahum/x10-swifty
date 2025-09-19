import Foundation
import x10Core
import x10Runtime
import X10IREEC

/// Early IREE backend stub. Real path will be guarded behind the C shim.
public struct IREEBackend: Backend {
  public struct Dev: Hashable, Sendable {
    public let ordinal: Int
    public init(ordinal: Int) { self.ordinal = ordinal }
  }

  public init() {}

  /// True if the build is configured with IREE headers (feature flag on).
  public static var isAvailable: Bool { x10_iree_is_available() == 1 }

  /// Later we’ll return true when the dynamic/runtime path is actually resolved.
  public static var isReal: Bool { x10_iree_is_real() == 1 }

  public func devices() throws -> [Dev] {
    // Keep stub device enumeration deterministic for tests.
    let n = (ProcessInfo.processInfo.environment["X10_IREE_STUB_DEVICE_COUNT"]).flatMap(Int.init) ?? 1
    return (0..<n).map { Dev(ordinal: $0) }
  }

  // === memory / transfer (placeholder today) ===
  public func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    struct B: Buffer {}; return B()
  }
  public func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    struct B: Buffer {}; return B()
  }
  public func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }

  // === compile / execute ===
  public func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    // Later: pass target backend (e.g., "metal", "vulkan", "llvm-cpu") via options.flags["iree_target"]
    _ = x10_iree_load(nil)
    let text = stablehlo.textual()
    var size: Int = 0
    let ok = text.utf8CString.withUnsafeBufferPointer { p -> Int32 in
      x10_iree_compile_stablehlo_to_vmfb(p.baseAddress, Int32(p.count - 1), nil, nil, 0, &size)
    }
    // For now we don't store vmfb bytes; just return a fresh Executable.
    _ = ok; _ = size
    return Executable()
  }

  public func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] {
    inputs // stub
  }

  public func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  public func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
  public func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
}
