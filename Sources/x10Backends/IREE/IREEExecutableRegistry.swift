import Foundation
import x10Core

/// Minimal in-process store for compiled IREE artifacts keyed by Executable.id.
/// This mirrors the PJRT registry shape and keeps the Swift surface stable.
public final class IREEExecutableRegistry {
  public static let shared = IREEExecutableRegistry()
  private let lock = NSLock()
  private var blobs: [UUID: Data] = [:]
  private var device: [UUID: Int] = [:]
  private var prefersRuntime: [UUID: Bool] = [:]

  public func put(id: UUID, vmfb: Data, defaultDeviceOrdinal: Int, preferRuntime: Bool = false) {
    lock.lock(); defer { lock.unlock() }
    blobs[id] = vmfb
    device[id] = defaultDeviceOrdinal
    prefersRuntime[id] = preferRuntime
  }

  public func getVMFB(id: UUID) -> Data? {
    lock.lock(); defer { lock.unlock() }
    return blobs[id]
  }

  public func getDeviceOrdinal(id: UUID) -> Int? {
    lock.lock(); defer { lock.unlock() }
    return device[id]
  }

  public func shouldPreferRuntime(id: UUID) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return prefersRuntime[id] ?? false
  }

  public func clear() {
    lock.lock(); defer { lock.unlock() }
    blobs.removeAll(); device.removeAll(); prefersRuntime.removeAll()
  }
}
