import x10Core

public enum DeviceScope {
  #if swift(>=5.7)
  @TaskLocal public static var current: Device = .default
  #else
  public static var current: Device = .default
  #endif
}

/// Synchronous bodies (you already have this)
@inlinable
public func withDevice<T>(_ device: Device, _ body: () throws -> T) rethrows -> T {
  #if swift(>=5.7)
  return try DeviceScope.$current.withValue(device) { try body() }
  #else
  let old = DeviceScope.current
  DeviceScope.current = device
  defer { DeviceScope.current = old }
  return try body()
  #endif
}

/// **NEW**: Async bodies
@inlinable
public func withDevice<T>(_ device: Device, _ body: () async throws -> T) async rethrows -> T {
  #if swift(>=5.7)
  return try await DeviceScope.$current.withValue(device) { try await body() }
  #else
  let old = DeviceScope.current
  DeviceScope.current = device
  defer { DeviceScope.current = old }
  return try await body()
  #endif
}
