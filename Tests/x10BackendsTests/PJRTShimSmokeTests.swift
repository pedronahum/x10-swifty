import Testing
import PJRTC

@Test
func shimIsAvailableAndLikelyStub() {
  #expect(x10_pjrt_is_available() == 1)
  // On most dev machines without PJRT installed this will be 0; if someone sets it up, it can be 1.
  #expect(x10_pjrt_is_real() == 0 || x10_pjrt_is_real() == 1)
}
