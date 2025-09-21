import Testing
import Foundation
import x10Core
@testable import x10Runtime

@Test
func cacheEvictsLeastRecentlyUsedEntries() async throws {
  let policy = CachePolicy(maxEntries: 3, maxBytes: 1024)
  let cache = ExecutableCache(policy: policy)

  let keys = (0..<5).map { idx in
    ShapeKey(fingerprint: "key-\(idx)", versionSalt: "salt")
  }

  for key in keys {
    let exec = Executable()
    await cache.put(exec, for: key)
  }

  // Only the last three inserted keys should remain
  for (index, key) in keys.enumerated() {
    if index >= 2 {
      #expect(await cache.get(key) != nil)
    } else {
      #expect(await cache.get(key) == nil)
    }
  }
}

@Test
func cacheRespectsByteBudgetWithCustomCosts() async throws {
  let policy = CachePolicy(maxEntries: 10, maxBytes: 90)
  let cache = ExecutableCache(policy: policy)

  var costTable: [UUID: Int] = [:]
  await cache.registerCostResolver { exec in costTable[exec.id] }

  func insert(cost: Int, key label: String) async -> ShapeKey {
    let exec = Executable()
    costTable[exec.id] = cost
    let key = ShapeKey(fingerprint: label, versionSalt: "salt")
    await cache.put(exec, for: key)
    return key
  }

  let k1 = await insert(cost: 60, key: "a")
  let k2 = await insert(cost: 40, key: "b")
  let k3 = await insert(cost: 20, key: "c")

  // Cache should have evicted the oldest entries until byte limit satisfied.
  #expect(await cache.get(k3) != nil)
  #expect(await cache.get(k2) != nil)
  #expect(await cache.get(k1) == nil)
}
