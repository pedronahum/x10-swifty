import Foundation
import x10Core
import PJRTC

/// Thread-safe table mapping public Executable.id -> PJRT executable handle + default device ordinal.
final class PJRTExecutableRegistry {
  static let shared = PJRTExecutableRegistry()

  struct Entry {
    let handle: x10_pjrt_executable_t
    let defaultDeviceOrdinal: Int32
  }

  private let q = DispatchQueue(label: "x10.pjrt.exec.registry")
  private var table: [UUID: Entry] = [:]

  func put(id: UUID, handle: x10_pjrt_executable_t, defaultDeviceOrdinal: Int32) {
    q.sync { table[id] = Entry(handle: handle, defaultDeviceOrdinal: defaultDeviceOrdinal) }
  }

  func getEntry(_ id: UUID) -> Entry? {
    q.sync { table[id] }
  }

  func getHandle(_ id: UUID) -> x10_pjrt_executable_t? {
    q.sync { table[id]?.handle }
  }

  func remove(_ id: UUID) {
    q.sync {
      if let e = table.removeValue(forKey: id) { x10_pjrt_executable_destroy(e.handle) }
    }
  }

  /// For tests/debugging.
  func clear() {
    q.sync {
      for (_, e) in table { x10_pjrt_executable_destroy(e.handle) }
      table.removeAll()
    }
  }
}
