import Foundation
import x10Core
import x10Runtime


public final class PJRTBackendShim: Sendable {
  public init() {}
}

public struct PJRTBackend: Backend {
  public struct Dev: Hashable, Sendable { public let ordinal: Int; public init(_ i: Int) { ordinal = i } }

  public init() {}

  public func devices() throws -> [Dev] { [Dev(0)] }

  public func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    struct B: Buffer {}
    return B()
  }

  public func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer {
    struct B: Buffer {}
    return B()
  }

  public func fromDevice(_ buffer: Buffer) throws -> [UInt8] { return [] }

  public func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable {
    // TODO: call into real PJRT C-API
    return Executable()
  }
    
  public func execute(_ exec: Executable, inputs: [Buffer], stream: x10Runtime.Stream?) async throws -> [Buffer] {  
    return inputs // stub passthrough
  }

  public func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer { return b }

  public func stream(device: Dev) throws -> x10Runtime.Stream { x10Runtime.Stream() }
  public func event(device: Dev) throws -> x10Runtime.Event { x10Runtime.Event() }
}
