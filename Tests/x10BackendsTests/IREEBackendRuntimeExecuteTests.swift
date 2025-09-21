import Testing
import Foundation
import x10Core
import x10Runtime
import x10BackendsIREE
import x10Diagnostics

@Test
func ireeBackendRuntimeExecutesAddWhenEnabled() async throws {
  // This test only runs when explicitly requested and the runtime shim is ready.
  guard IREECompileCLI.find() != nil else {
    Issue.record("iree-compile not available; cannot build VMFB for runtime test")
    return
  }
  guard IREEExecuteCLI.find() != nil else {
    Issue.record("iree-run-module not available; cannot compare outputs")
    return
  }
  guard IREEBackend.isReal else { return }

  let runtimeBefore = Diagnostics.executeCallsIreeRuntime.value
  let cliBefore = Diagnostics.executeCallsIreeCLI.value

  // Build tiny StableHLO: r = a + b  (f32[2,3])
  let builder = IRBuilder()
  let fn = builder.function(
    name: "main",
    args: [("a", [2, 3], .f32), ("b", [2, 3], .f32)],
    results: [("r", [2, 3], .f32)]
  ) { f in
    let a = f.args[0], bb = f.args[1], r = f.results[0]
    f.parameter(0, into: a)
    f.parameter(1, into: bb)
    f.add(a, bb, into: r)
    f.returnValues([r])
  }
  let module = StableHLOModule(functions: [fn])

  let backend = IREEBackend()
  let options = CompileOptions(device: .cpu(0), flags: ["iree_runtime": "true"])
  let exec = try backend.compile(stablehlo: module, options: options)

  // Prepare inputs on host
  let a: [Float] = [1, 2, 3, 4, 5, 6]
  let b: [Float] = [4, 5, 6, 4, 5, 6]
  let bufA: Buffer = try a.withUnsafeBytes { bytes in
    try backend.toDevice(bytes, shape: [2, 3], dtype: .f32, on: .init(ordinal: 0))
  }
  let bufB: Buffer = try b.withUnsafeBytes { bytes in
    try backend.toDevice(bytes, shape: [2, 3], dtype: .f32, on: .init(ordinal: 0))
  }

  // Execute via in-process runtime
  let outputs = try await backend.execute(exec, inputs: [bufA, bufB], stream: nil)
  #expect(outputs.count == 1)

  let runtimeBytes = try backend.fromDevice(outputs[0])
  let runtimeFloats: [Float] = runtimeBytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  #expect(runtimeFloats == [5, 7, 9, 8, 10, 12])

  #expect(Diagnostics.executeCallsIreeRuntime.value == runtimeBefore + 1)

  guard let vmfb = IREEExecutableRegistry.shared.getVMFB(id: exec.id) else {
    Issue.record("VMFB missing from registry")
    return
  }

  let aTxt = IREEExecuteCLI.formatInput(shape: [2, 3], dtypeToken: "f32",
                                        scalars: ["1","2","3","4","5","6"])
  let bTxt = IREEExecuteCLI.formatInput(shape: [2, 3], dtypeToken: "f32",
                                        scalars: ["4","5","6","4","5","6"])
  let cliResult = try IREEExecuteCLI.runAndParse(vmfb: vmfb, entry: "main", inputs: [aTxt, bTxt])
  let cliFloats = cliResult.scalars.map { Float($0) }
  let cliBytes: [UInt8] = cliFloats.withUnsafeBufferPointer { buffer in
    Array(UnsafeRawBufferPointer(buffer))
  }

  #expect(cliBytes == runtimeBytes)
  #expect(Diagnostics.executeCallsIreeCLI.value == cliBefore)
}
