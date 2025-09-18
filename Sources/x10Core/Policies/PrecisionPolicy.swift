public struct PrecisionPolicy: Sendable {
  public enum Precision: Sendable {
    case f16, bf16, fp8, fp32
  }

  public var activations: Precision
  public var matmul: Precision
  public var accumulators: Precision

  public init(
    activations: Precision = .bf16,
    matmul: Precision      = .bf16,
    accumulators: Precision = .fp32
  ) {
    self.activations = activations
    self.matmul = matmul
    self.accumulators = accumulators
  }
}
