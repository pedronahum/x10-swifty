import Foundation
import x10Core
import x10Runtime

extension IREEBackend {
  private static let _cacheRegistration: Void = {
    ExecutableCache.registerCostResolver { exec in
      guard let vmfb = IREEExecutableRegistry.shared.getVMFB(id: exec.id) else { return nil }
      return vmfb.count
    }

    BackendVersioning.register { backend in
      guard backend is IREEBackend else { return nil }
      return BackendVersionInfo(kind: "iree", version: Self.cliVersionString())
    }
  }()

  static func ensureCacheRegistration() {
    _ = _cacheRegistration
  }

  private static func cliVersionString() -> String {
    struct Holder {
      static let value: String = {
        guard let tool = IREECompileCLI.find()?.url else { return "unavailable" }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
          try process.run()
        } catch {
          return "unavailable"
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
          return "unknown"
        }
        return text
      }()
    }
    return Holder.value
  }
}
