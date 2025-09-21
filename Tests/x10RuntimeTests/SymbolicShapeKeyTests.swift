import Testing
import x10Core
import x10Runtime

@Test
func bucketedShapesProduceSameKey() {
  let module = StableHLOModule()
  let policy = ShapeBucketingPolicy(dims: [.bucket(lo: 192, hi: 256), .bucket(lo: 192, hi: 256), .exact(3)])
  let salt = "iree:1.0:dev"

  let keyA = makeCacheKey(
    module: module,
    backendKey: "iree",
    deviceKey: "cpu:0",
    versionSalt: salt,
    concreteShape: [224, 224, 3],
    bucketing: policy
  )

  let keyB = makeCacheKey(
    module: module,
    backendKey: "iree",
    deviceKey: "cpu:0",
    versionSalt: salt,
    concreteShape: [240, 240, 3],
    bucketing: policy
  )

  #expect(keyA == keyB)
}

@Test
func outOfBucketShapesProduceDifferentKey() {
  let module = StableHLOModule()
  let salt = "iree:1.0:dev"

  let keyA = makeCacheKey(
    module: module,
    backendKey: "iree",
    deviceKey: "cpu:0",
    versionSalt: salt,
    concreteShape: [224, 224, 3],
    bucketing: .default
  )

  let keyB = makeCacheKey(
    module: module,
    backendKey: "iree",
    deviceKey: "cpu:0",
    versionSalt: salt,
    concreteShape: [512, 512, 3],
    bucketing: .default
  )

  #expect(keyA != keyB)
}

@Test
func mixedExactAndBucketDimsBehave() {
  let module = StableHLOModule()
  let policy = ShapeBucketingPolicy(dims: [.exact(32), .bucket(lo: 128, hi: 256), .any])
  let salt = "pjrt:dev:dev"

  let keyA = makeCacheKey(
    module: module,
    backendKey: "pjrt",
    deviceKey: "gpu:0",
    versionSalt: salt,
    concreteShape: [32, 192, 64],
    bucketing: policy
  )

  let keyB = makeCacheKey(
    module: module,
    backendKey: "pjrt",
    deviceKey: "gpu:0",
    versionSalt: salt,
    concreteShape: [32, 200, 128],
    bucketing: policy
  )

  let keyC = makeCacheKey(
    module: module,
    backendKey: "pjrt",
    deviceKey: "gpu:0",
    versionSalt: salt,
    concreteShape: [64, 200, 128],
    bucketing: policy
  )

  #expect(keyA == keyB)
  #expect(keyA != keyC)
}
