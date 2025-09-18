import Foundation
import x10BackendsPJRT

@main
struct Devices {
  static func main() throws {
    let be = PJRTBackend()
    let devs = try be.devices()
    print("PJRT available devices: \(devs.count)")
    for d in devs {
      print("  [\(d.ordinal)] \(be.deviceDescription(d))")
    }
    print("Tip: X10_PJRT_STUB_DEVICE_COUNT=4 swift run x10ExamplePJRTDevices")
  }
}
