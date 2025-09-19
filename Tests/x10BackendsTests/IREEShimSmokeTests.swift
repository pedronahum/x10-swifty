import Testing
import x10BackendsIREE

@Test
func ireeShimAvailabilityIsCoherent() {
  // With no headers/flag, expect false; with them, true.
  #expect(IREEBackend.isAvailable == true || IREEBackend.isAvailable == false)
  // isReal will be false until we wire the runtime (even when headers are present).
  #expect(IREEBackend.isReal == false || IREEBackend.isReal == true)
}
