import Testing
@testable import x10Core

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Test
func deviceParsesFromString() {
  #expect(Device(parse: "cpu:0") == .cpu(0))
  #expect(Device(parse: "gpu:2") == .gpu(2))
  #expect(Device(parse: "tpu:0") == nil)
  #expect(Device(parse: "gpu") == nil)
}

@Test
func defaultDeviceHonorsEnv() {
  setenv("X10_DEFAULT_DEVICE", "gpu:0", 1)
  defer { unsetenv("X10_DEFAULT_DEVICE") }
  #expect(Device.default == .gpu(0))
}
