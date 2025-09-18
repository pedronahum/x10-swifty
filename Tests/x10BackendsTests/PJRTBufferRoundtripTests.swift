import Testing
import Foundation
import x10Core
import x10Runtime
import x10BackendsPJRT

@Test
func stubBufferRoundtripF32() throws {
  let be = PJRTBackend()
  let dev = try be.devices().first ?? .init(ordinal: 0)

  // Host payload
  let host: [Float] = [1,2,3,4,5,6]
  
  // Build Data directly from the host buffer (no C memcpy needed).
  let data = host.withUnsafeBufferPointer { Data(buffer: $0) }

  // toDevice / fromDevice
  let buf = try data.withUnsafeBytes {
    try be.toDevice($0, shape: [2,3], dtype: .f32, on: dev)
  }
  let back = try be.fromDevice(buf)

  #expect(back == Array(data))
}
