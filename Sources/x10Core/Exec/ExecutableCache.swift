import Foundation

public actor ExecutableCache {
  public static let shared = ExecutableCache()

  private var table: [ShapeKey: Executable] = [:]
  private var order: [ShapeKey] = []              // MRU at the end
  private let capacity: Int?

  public init(capacity: Int? = nil) {
    if let c = capacity { self.capacity = max(1, c) }
    else if let env = ProcessInfo.processInfo.environment["X10_CACHE_CAPACITY"], let c = Int(env) {
      self.capacity = max(1, c)
    } else {
      self.capacity = nil // unbounded
    }
  }

  public func get(_ key: ShapeKey) -> Executable? {
    guard let v = table[key] else { return nil }
    if let i = order.firstIndex(of: key) { order.remove(at: i) }
    order.append(key)
    return v
  }

  public func put(_ exec: Executable, for key: ShapeKey) {
    table[key] = exec
    if let i = order.firstIndex(of: key) { order.remove(at: i) }
    order.append(key)
    evictIfNeeded()
  }

  public func clear() { table.removeAll(); order.removeAll() }

  private func evictIfNeeded() {
    guard let cap = capacity else { return }
    while order.count > cap {
      let k = order.removeFirst()
      _ = table.removeValue(forKey: k)
    }
  }
}
