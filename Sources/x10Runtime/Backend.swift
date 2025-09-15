import Foundation
import x10Core 

public protocol Buffer: Sendable {}

public protocol Backend: Sendable {
  associatedtype DeviceId: Hashable & Sendable

  func devices() throws -> [DeviceId]

  func allocate(shape: [Int], dtype: DType, on: DeviceId) throws -> Buffer
  func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: DeviceId) throws -> Buffer
  func fromDevice(_ buffer: Buffer) throws -> [UInt8]

  func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable
  func execute(_ exec: Executable, inputs: [Buffer], stream: Stream?) async throws -> [Buffer]

  func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer

  func stream(device: DeviceId) throws -> Stream
  func event(device: DeviceId) throws -> Event
}

public struct CompileOptions: Sendable {
  public init() {}
}

public struct Stream: Sendable { public init() {} }
public struct Event: Sendable { public init() {} }

public enum ReduceOp { case add, max }
public struct CollectiveGroup: Sendable {
  public init() {}
}
