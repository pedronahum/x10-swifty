import Testing
import x10InteropDLPack

@Test
func dlpackAvailabilityBehaves() {
  if DLPack.isAvailable {
    // When compiled with real headers, availability is true and lastError is nil/empty.
    #expect(DLPack.isAvailable == true)
    #expect(DLPack.lastError == nil || DLPack.lastError == "")
  } else {
    // When compiled without headers/flag, availability is false.
    #expect(DLPack.isAvailable == false)
  }
}
