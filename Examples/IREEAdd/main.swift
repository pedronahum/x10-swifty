import Foundation
import x10Core
import x10Runtime
import x10BackendsIREE
import x10BackendsSelect

@main
struct Main {
  static func main() throws {
    // Build tiny StableHLO: r = a + b  (f32[2,3])
    let shape = [2, 3]
    let dtype: DType = .f32

    let b = IRBuilder()
    let fn = b.function(
      name: "main",
      args: [("a", shape, dtype), ("b", shape, dtype)],
      results: [("r", shape, dtype)]
    ) { f in
      let a = f.args[0], bb = f.args[1], r = f.results[0]
      f.parameter(0, into: a)
      f.parameter(1, into: bb)
      f.add(a, bb, into: r)
      f.returnValues([r])
    }
    let m = StableHLOModule(functions: [fn])

    switch BackendPicker.choose() {
    case .iree:
      let be = IREEBackend()

      // Compile via backend (this tries iree-compile if found)
      let exec = try be.compile(stablehlo: m, options: .init(device: .cpu(0)))

      // Report tools + cached size
      let compilePath = IREECompileCLI.find()?.path ?? "nil"
      let runPath     = IREEExecuteCLI.find()?.path ?? "nil"
      var vmfb        = IREEExecutableRegistry.shared.getVMFB(id: exec.id)
      print("IREE status: compileCLI=\(compilePath), runCLI=\(runPath), cached=\(vmfb?.count ?? 0) bytes")

      // Fallback compile here if nothing cached (so we can surface errors immediately)
      if (vmfb == nil || vmfb?.isEmpty == true), IREECompileCLI.find() != nil {
        do {
          let vm = try IREECompileCLI.compileStableHLO(m.textual(), target: "llvm-cpu")
          vmfb = vm
          IREEExecutableRegistry.shared.put(id: exec.id, vmfb: vm, defaultDeviceOrdinal: 0)
          FileHandle.standardError.write(Data("[example] fallback compile succeeded (\(vm.count) bytes)\n".utf8))
        } catch {
          FileHandle.standardError.write(Data("[example] fallback compile failed: \(error)\n".utf8))
        }
      }

      // Run via CLI if present
      if let vm = vmfb, !vm.isEmpty {
        if IREEExecuteCLI.find() != nil {
          // a = [[1,2,3],[4,5,6]], b = [[4,5,6],[4,5,6]]
          let aTxt = IREEExecuteCLI.formatInput(shape: shape, dtypeToken: "f32",
                                                scalars: ["1","2","3","4","5","6"])
          let bTxt = IREEExecuteCLI.formatInput(shape: shape, dtypeToken: "f32",
                                                scalars: ["4","5","6","4","5","6"])

          let (outText, errText, code) = try IREEExecuteCLI.runVMFB(
            vmfb: vm, entry: "main", inputs: [aTxt, bTxt]
          )

          print("--- IREE run (exit=\(code)) ---")
          if !errText.isEmpty {
            FileHandle.standardError.write(Data((errText + "\n").utf8))
          }
          print(outText)
        } else {
          print("VMFB cached (\(vm.count) bytes) but iree-run-module not found.")
          print("Tip: export X10_IREE_RUN_BIN or add it to PATH.")
        }
      } else {
        print("VMFB not cached; see stderr for compile errors (set X10_IREE_VERBOSE=1 for backend logs).")
      }

    case .pjrt:
      print("This example is geared for IREE. Set X10_BACKEND=iree to use it.")
    }
  }
}
