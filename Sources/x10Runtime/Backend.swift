import Foundation
import x10Core 


// === Core backend surface types ===

/// Opaque handle to device-resident memory.
public protocol Buffer: Sendable {}

/// Collective reduction operation kinds (extend as needed).
public enum ReduceOp: Sendable { case sum, max, min }

/// Communicator / device group descriptor for collectives.
public struct CollectiveGroup: Sendable { public init() {} }

// If you don't already have these in this file, keep them here:
public struct Stream: Sendable { public init() {} }
public struct Event: Sendable { public init() {} }

/// Options that influence backend compilation (stable shape of API).
public struct CompileOptions: Sendable {
  /// Preferred device for the compiled program (nil ⇒ backend default).
  public var device: Device?

  /// Numeric precision policy (activations / matmul / accumulators).
  public var precision: PrecisionPolicy

  /// Shape bucketing behavior used when deriving cache keys.
  public var shapeBucketing: ShapeBucketingPolicy

  /// Optional concrete shape hint (for cache warmers or profilers).
  public var shapeHint: [Int]?

  /// Internal knob to prevent recursive cache warming.
  public var isWarmup: Bool

  /// Emit IR/text dumps useful for debugging.
  public var debugIR: Bool

  /// Enable backend profiling if supported.
  public var enableProfiling: Bool

  /// Extra backend-specific flags (stringly-typed; stable escape hatch).
  public var flags: [String: String]

  public init(
    device: Device? = nil,
    precision: PrecisionPolicy = .init(),
    shapeBucketing: ShapeBucketingPolicy = .default,
    shapeHint: [Int]? = nil,
    debugIR: Bool = false,
    enableProfiling: Bool = false,
    flags: [String: String] = [:],
    isWarmup: Bool = false
  ) {
    self.device = device
    self.precision = precision
    self.shapeBucketing = shapeBucketing
    self.shapeHint = shapeHint
    self.isWarmup = isWarmup
    self.debugIR = debugIR
    self.enableProfiling = enableProfiling
    self.flags = flags
  }
}

/// Backends implement compile/execute and (optionally) collectives.
public protocol Backend: Sendable {
  associatedtype Dev: Hashable & Sendable

  func devices() throws -> [Dev]

  func allocate(shape: [Int], dtype: DType, on: Dev) throws -> Buffer
  func toDevice(_ host: UnsafeRawBufferPointer, shape: [Int], dtype: DType, on: Dev) throws -> Buffer
  func fromDevice(_ buffer: Buffer) throws -> [UInt8]

  func compile(stablehlo: StableHLOModule, options: CompileOptions) throws -> Executable
  func execute(_ exec: Executable, inputs: [Buffer], stream: Stream?) async throws -> [Buffer]

  func allReduce(_ b: Buffer, op: ReduceOp, group: CollectiveGroup) async throws -> Buffer

  func stream(device: Dev) throws -> Stream
  func event(device: Dev) throws -> Event
}
