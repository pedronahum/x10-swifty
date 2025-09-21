import Testing
import Foundation
import x10Core
import x10Runtime
import x10BackendsPJRT
import x10InteropDLPack

@Test
func pjrtDLPackZeroCopyHostAlias() throws {
  // Only run if DLPack shim is available. (If you used a flag, check it here.)
  #expect(DLPack.isAvailable)

  // Create a malloc'ed buffer and fill with 6 f32 values.
  let scalars: [Float] = [1,2,3,4,5,6]
  let nbytes = scalars.count * MemoryLayout<Float>.stride
  let ptr = UnsafeMutableRawPointer.allocate(byteCount: nbytes, alignment: MemoryLayout<Float>.alignment)
  defer { /* ownership moves to the capsule; no free here */ }
  _ = scalars.withUnsafeBytes { src in memcpy(ptr, src.baseAddress!, nbytes) }

  // Wrap into a DLPack capsule that will free() the memory upon dispose.
  let cap = try DLPack.wrapHostBufferFree(ptr: ptr, shape: [2,3], dtype: .f32)

  // Import into PJRT as a zero-copy alias.
  let be = PJRTBackend()
  let buf = try be.importDLPack(cap)

  // Export back to DLPack: should be zero-copy and expose the same data pointer.
  let cap2 = try be.exportDLPack(buf)
  defer {
    DLPack.dispose(cap2)
    DLPack.dispose(cap) // this will free(ptr) when refcount reaches 0
  }

  // Pointer identity proves zero-copy aliasing in/out.
  let p1 = DLPack.dataPointer(cap)
  let p2 = DLPack.dataPointer(cap2)
  #expect(p1 != nil && p1 == p2)

  // Sanity: reading back via fromDevice produces the same bytes.
  let raw = try be.fromDevice(buf)
  #expect(raw.count == nbytes)
  let back: [Float] = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  #expect(back == scalars)
}
