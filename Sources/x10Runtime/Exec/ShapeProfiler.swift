import Foundation
import x10Core

public actor ShapeProfiler {
  public static let shared = ShapeProfiler()

  private struct Entry: Hashable {
    let irHash: String
    let policy: ShapeBucketingPolicy
  }

  private var histo: [Entry: [ [Int]: Int ]] = [:]

  public func note(irHash: String, policy: ShapeBucketingPolicy, concreteShape: [Int]) {
    let entry = Entry(irHash: irHash, policy: policy)
    var bucket = histo[entry] ?? [:]
    bucket[concreteShape, default: 0] += 1
    histo[entry] = bucket
  }

  public func topK(irHash: String, policy: ShapeBucketingPolicy, k: Int) -> [[Int]] {
    guard k > 0 else { return [] }
    let entry = Entry(irHash: irHash, policy: policy)
    guard let bucket = histo[entry] else { return [] }
    return bucket
      .sorted { $0.value > $1.value }
      .prefix(k)
      .map { $0.key }
  }

  public func reset() {
    histo.removeAll()
  }
}
