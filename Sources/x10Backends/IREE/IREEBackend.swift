import Foundation
import x10Core
import x10Runtime

/// Early IREE backend stub. Real path will be guarded behind a small C shim.
public struct IREEBackend: Backend {
  public struct Dev: Hashable, Sendable {
    public let ordinal: Int
    public init(ordinal: Int) { self.ordinal = ordinal }
  }

  public init() {}

  public func devices() throws -> [Dev] {
    let n = (ProcessInfo.processInfo.environment["X10_IREE_STUB_DEVICE_COUNT"]).flatMap(Int.init) ?? 1
    return (0..<n).map { Dev(ordinal: $0) }
  }

  public func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    struct B: Buffer {}; return B()
  }

  public func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    struct B: Buffer {}; return B()
  }

  public func fromDevice(_ buffer: Buffer) throws -> [UInt8] { [] }

  public func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    // Real path: iree-compile to VM bytecode (AOT) or JIT via runtime API.
    return Executable()
  }

  public func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] {
    inputs // stub
  }

  public func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { b }
  public func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
  public func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
}
