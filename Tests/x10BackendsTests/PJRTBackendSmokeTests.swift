import Testing
@testable import x10BackendsPJRT

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Test
func stubDeviceCountHonorsEnv() throws {
  setenv("X10_PJRT_STUB_DEVICE_COUNT", "3", 1)
  defer { unsetenv("X10_PJRT_STUB_DEVICE_COUNT") }

  let be = PJRTBackend()
  let devs = try be.devices()
  #expect(devs.count == 3)
}
