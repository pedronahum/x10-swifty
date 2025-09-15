import Foundation
import x10Core

extension x10Core.Tensor {
  /// Placeholder barrier that would await device execution/materialization.
  public func materialize() async throws -> Self { self }
}
