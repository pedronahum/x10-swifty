import Testing
import x10Core

@Test
func versionSaltDifferentiatesShapeKeys() {
  let fingerprint = "abc123"
  let key1 = ShapeKey(fingerprint: fingerprint, versionSalt: "iree:v1:dev")
  let key2 = ShapeKey(fingerprint: fingerprint, versionSalt: "pjrt:v1:dev")

  #expect(key1 != key2)
  let set = Set([key1, key2])
  #expect(set.count == 2)
}
