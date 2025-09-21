import Foundation
import x10Core

public struct CachePolicy: Sendable {
  public var maxEntries: Int
  public var maxBytes: Int

  public init(maxEntries: Int, maxBytes: Int) {
    self.maxEntries = max(1, maxEntries)
    self.maxBytes = max(1, maxBytes)
  }

  public static func fromEnvironment(_ env: [String: String]) -> CachePolicy {
    let defaultEntries = 256
    let defaultBytes = 64 * 1024 * 1024
    let rawEntries = env["X10_CACHE_MAX_ENTRIES"].flatMap(Int.init)
      ?? env["X10_CACHE_CAPACITY"].flatMap(Int.init)
    let entries = (rawEntries ?? defaultEntries).clamped(min: 1)

    let rawBytes = env["X10_CACHE_MAX_BYTES"].flatMap(Int.init)
    let bytes = (rawBytes ?? defaultBytes).clamped(min: 1)
    return CachePolicy(maxEntries: entries, maxBytes: bytes)
  }
}

public struct ExecRecord: Sendable {
  public let exec: Executable
  public let cost: Int
  public var prev: ShapeKey?
  public var next: ShapeKey?

  public init(exec: Executable, cost: Int, prev: ShapeKey? = nil, next: ShapeKey? = nil) {
    self.exec = exec
    self.cost = cost
    self.prev = prev
    self.next = next
  }
}

public actor ExecutableCache {
  public typealias CostResolver = (Executable) -> Int?

  public static let shared = ExecutableCache()

  private var table: [ShapeKey: ExecRecord] = [:]
  private var head: ShapeKey?
  private var tail: ShapeKey?
  private var totalCost: Int = 0
  private let policy: CachePolicy
  private var costResolvers: [CostResolver] = []

  public init(policy: CachePolicy = CachePolicy.fromEnvironment(ProcessInfo.processInfo.environment)) {
    self.policy = policy
  }

  // MARK: - Cost resolvers

  public nonisolated static func registerCostResolver(_ resolver: @escaping CostResolver) {
    Task { await ExecutableCache.shared.registerCostResolver(resolver) }
  }

  public func registerCostResolver(_ resolver: @escaping CostResolver) {
    costResolvers.append(resolver)
  }

  // MARK: - Public API

  public func get(_ key: ShapeKey) -> Executable? {
    guard let record = table[key] else { return nil }
    moveToHead(key, record: record)
    return record.exec
  }

  public func put(_ exec: Executable, for key: ShapeKey) {
    let cost = estimateCost(for: exec)

    if let existing = table[key] {
      removeNode(key, record: existing, subtractCost: true)
    }

    let record = ExecRecord(exec: exec, cost: cost)
    insertAtHead(key, record: record)
    totalCost += cost
    enforcePolicy()
  }

  public func clear() {
    table.removeAll()
    head = nil
    tail = nil
    totalCost = 0
  }

  // MARK: - Internal helpers

  private func estimateCost(for exec: Executable) -> Int {
    for resolver in costResolvers.reversed() {
      if let value = resolver(exec), value > 0 {
        return value
      }
    }
    return 1
  }

  private func moveToHead(_ key: ShapeKey, record: ExecRecord) {
    guard head != key else { return }
    removeNode(key, record: record, subtractCost: false)
    insertAtHead(key, record: record)
  }

  private func insertAtHead(_ key: ShapeKey, record: ExecRecord) {
    var mutable = record
    mutable.prev = nil
    mutable.next = head
    table[key] = mutable

    if let headKey = head {
      updatePrev(of: headKey, to: key)
    }

    head = key
    if tail == nil {
      tail = key
    }
  }

  private func removeNode(_ key: ShapeKey, record: ExecRecord, subtractCost: Bool) {
    let prev = record.prev
    let next = record.next

    if let prevKey = prev {
      updateNext(of: prevKey, to: next)
    } else {
      head = next
    }

    if let nextKey = next {
      updatePrev(of: nextKey, to: prev)
    } else {
      tail = prev
    }

    if subtractCost {
      totalCost -= record.cost
    }

    table.removeValue(forKey: key)
  }

  private func updatePrev(of key: ShapeKey, to value: ShapeKey?) {
    guard var record = table[key] else { return }
    record.prev = value
    table[key] = record
  }

  private func updateNext(of key: ShapeKey, to value: ShapeKey?) {
    guard var record = table[key] else { return }
    record.next = value
    table[key] = record
  }

  private func enforcePolicy() {
    while table.count > policy.maxEntries || totalCost > policy.maxBytes {
      guard let tailKey = tail, let record = table[tailKey] else { break }
      removeNode(tailKey, record: record, subtractCost: true)
    }
  }
}

private extension Comparable {
  func clamped(min: Self) -> Self { self < min ? min : self }
}
