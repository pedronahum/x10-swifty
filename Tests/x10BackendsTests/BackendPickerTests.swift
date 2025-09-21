import Testing
import x10BackendsSelect

@Test
func pickerReturnsSupportedKind() {
  let k = BackendPicker.choose()
  #expect(k == .iree || k == .pjrt)
}
