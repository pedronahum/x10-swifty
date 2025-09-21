// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "x10-swifty",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "x10Core", targets: ["x10Core"]),
    .library(name: "x10Runtime", targets: ["x10Runtime"]),
    .library(name: "x10BackendsSelect", targets: ["x10BackendsSelect"]),
    .library(name: "x10InteropDLPackC", targets: ["x10InteropDLPackC"]),
    .library(name: "x10InteropDLPack", targets: ["x10InteropDLPack"]),
    .library(name: "x10BackendsPJRT", targets: ["x10BackendsPJRT"]),
    .library(name: "x10BackendsIREE", targets: ["x10BackendsIREE"]),
    .library(name: "x10Diagnostics", targets: ["x10Diagnostics"]),
    .library(name: "x10AdaptersTFEager", targets: ["x10AdaptersTFEager"]),
    .executable(name: "x10ExampleBasics", targets: ["x10ExampleBasics"]),
    .executable(name: "x10ExampleIREEAdd", targets: ["x10ExampleIREEAdd"]),

  ],
  dependencies: [
    // Macro package intentionally omitted in the bootstrap to avoid toolchain pinning.
    .package(url: "https://github.com/swiftlang/swift-testing", branch: "main"),

  ],
  targets: [
    .target(
      name: "x10Core",
      path: "Sources/x10Core"),
    
    .target(
      name: "PJRTC",
      path: "Sources/x10Backends/PJRTC",
      publicHeadersPath: "include",
      cSettings: [
        .define("X10_PJRT_DLOPEN") // enable dlopen-based loader
      ],
      linkerSettings: [
        .linkedLibrary("dl", .when(platforms: [.linux])) // needed for dlopen on Linux
      ]
    ),

     .target(
      name: "x10InteropDLPackC",
      path: "Sources/x10InteropDLPackC",
      sources: ["x10_dlpack_shim.c"],   
      publicHeadersPath: "include",
      cSettings: [
        .define("X10_HAVE_DLPACK_HEADERS"),                             // <— turn real DLPack on
        .headerSearchPath("include/third_party/dlpack/include")         // <— adjust if needed
      ]
    ),

     // Swift wrapper
    .target(
      name: "x10InteropDLPack",
      dependencies: ["x10Core", "x10InteropDLPackC"],
      path: "Sources/x10InteropDLPack"
    ),

    .target(
      name: "x10Runtime",
      dependencies: ["x10Core", "x10Diagnostics"],
      path: "Sources/x10Runtime"),
    .target(
      name: "x10BackendsPJRT",
      dependencies: ["x10Core", "x10Runtime", "PJRTC", "x10InteropDLPack"],
      path: "Sources/x10Backends/PJRT"
    ),

    // C shim for IREE (guarded)
    .target(
      name: "X10IREEC",
      path: "Sources/x10Backends/IREEC",
      sources: ["x10_iree_shim.c"],
      publicHeadersPath: "include",
      cSettings: [
        // Enable later when you have IREE headers on the include path:
        .define("X10_IREE_HAVE_HEADERS"),
        .headerSearchPath("include/third_party/iree")
      ]
    ),
      // Swift wrapper
    .target(
      name: "x10BackendsIREE",
      dependencies: ["x10Core", "x10Runtime", "X10IREEC", "x10InteropDLPackC"],
      path: "Sources/x10Backends/IREE"),

    .target(
      name: "x10BackendsSelect",
      dependencies: ["x10Core", "x10Runtime", "x10BackendsPJRT", "x10BackendsIREE"],
      path: "Sources/x10BackendsSelect"
    ),

    .target(
      name: "x10Diagnostics",
      dependencies: ["x10Core"],
      path: "Sources/x10Diagnostics"),
    
    .target(
      name: "x10AdaptersTFEager",
      dependencies: ["x10Core", "x10Runtime"],
      path: "Sources/x10Adapters/TFEager"),
      .testTarget(
      name: "x10CoreTests",
      dependencies: [
        "x10Core",
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/x10CoreTests"
    ),
    .testTarget(
      name: "x10RuntimeTests",
      dependencies: [
        "x10Core",
        "x10Runtime",
        "x10Diagnostics",
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/x10RuntimeTests"
    ),
    .testTarget(
      name: "x10BackendsTests",
      dependencies: [
        "x10Core",
        "x10Runtime",
        "x10BackendsPJRT",
        "x10BackendsIREE",
        "x10BackendsSelect",
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/x10BackendsTests"
    ),
    .executableTarget(
      name: "x10ExampleBasics",
      dependencies: ["x10Core", "x10Runtime"],
      path: "Examples/01-basics"),
    .executableTarget(
      name: "x10ExampleIRCache",
      dependencies: ["x10Core", "x10Runtime", "x10BackendsPJRT", "x10Diagnostics"],
      path: "Examples/02-ir-and-cache"
    ),
    .executableTarget(
      name: "x10ExamplePJRTDevices",
      dependencies: ["x10BackendsPJRT"],
      path: "Examples/03-pjrt-devices"
    ),
    
   

   

    // Optional tests (see file below)
    .testTarget(
      name: "x10InteropDLPackTests",
      dependencies: [
        "x10InteropDLPack",
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/x10InteropDLPackTests"
    ),

    .executableTarget(
      name: "x10ExampleIREEAdd",
      dependencies: [
        "x10Core",
        "x10Runtime",
        "x10BackendsIREE",
        "x10BackendsSelect"
      ],
      path: "Examples/IREEAdd"
    ),



  ]
)
