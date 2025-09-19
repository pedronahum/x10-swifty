import Testing
import Foundation
import x10Core
import x10InteropDLPack

@Test
func hostRoundtripIfAvailable() throws {
  if !DLPack.isAvailable { return } // safe no-op on CI or dev machines

  // Prepare host bytes for [2,3] f32
  let scalars: [Float] = [1,2,3,4,5,6]
  let data = scalars.withUnsafeBufferPointer { Data(buffer: $0) }

  let cap = try data.withUnsafeBytes {
    try DLPackHost.wrapHostCopy(bytes: $0, shape: [2,3], dtype: .f32, device: .cpu(0))
  }
  let back = try DLPackHost.toHostData(cap)
  #expect(back == data)
}
