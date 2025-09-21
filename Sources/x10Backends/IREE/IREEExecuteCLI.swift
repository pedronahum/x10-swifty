import Foundation

public enum IREEExecuteCLI {

  // MARK: - Types

  public struct Tool {
    public let url: URL
    public var path: String { url.path }
  }

  public struct Result {
    public let shape: [Int]
    public let dtypeToken: String
    public let scalars: [Double]
  }

  // MARK: - Locator

  /// Finds `iree-run-module` via:
  /// 1) $X10_IREE_RUN_BIN, 2) $X10_IREE_PREFIX/bin/iree-run-module, 3) PATH
  public static func find() -> Tool? {
    let env = ProcessInfo.processInfo.environment

    if let override = env["X10_IREE_RUN_BIN"], !override.isEmpty {
      let u = URL(fileURLWithPath: override)
      if FileManager.default.isExecutableFile(atPath: u.path) { return Tool(url: u) }
    }

    if let prefix = env["X10_IREE_PREFIX"], !prefix.isEmpty {
      let candidate = URL(fileURLWithPath: prefix)
        .appendingPathComponent("bin")
        .appendingPathComponent("iree-run-module")
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return Tool(url: candidate)
      }
    }

    // PATH lookup
    let which = URL(fileURLWithPath: "/usr/bin/which")
    if FileManager.default.isExecutableFile(atPath: which.path) {
      let p = Process()
      p.executableURL = which
      p.arguments = ["iree-run-module"]
      let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
      try? p.run(); p.waitUntilExit()
      if p.terminationStatus == 0 {
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
          return Tool(url: URL(fileURLWithPath: s))
        }
      }
    }

    return nil
  }

  // MARK: - Input formatting

  /// Produces an `--input=` argument value for `iree-run-module`:
  /// e.g. "2x3xf32=1 2 3 4 5 6"
  public static func formatInput(shape: [Int], dtypeToken: String, scalars: [String]) -> String {
    let shapeTok = shape.map(String.init).joined(separator: "x")
    let values = scalars.joined(separator: " ")
    return "\(shapeTok)x\(dtypeToken)=\(values)"
  }

  // MARK: - Run & parse (structured)

  public static func runAndParse(vmfb: Data, entry: String, inputs: [String]) throws -> Result {
    guard let tool = find() else {
      throw error("iree-run-module not found; set X10_IREE_PREFIX or X10_IREE_RUN_BIN")
    }

    // Write module to temp file.
    let tmp = FileManager.default.temporaryDirectory
    let modURL = tmp.appendingPathComponent(UUID().uuidString).appendingPathExtension("vmfb")
    try vmfb.write(to: modURL)

    // Build arguments
    var args: [String] = []
    let device = ProcessInfo.processInfo.environment["X10_IREE_RUN_DEVICE"] ?? "local-task"
    args.append(contentsOf: ["--device=\(device)"])
    args.append("--function=\(entry)")
    args.append("--module=\(modURL.path)")
    for v in inputs { args.append("--input=\(v)") }

    // Allow extra flags via env.
    if let extra = ProcessInfo.processInfo.environment["X10_IREE_RUN_EXTRA_FLAGS"], !extra.isEmpty {
      let parts = extra.split(separator: " ").map(String.init)
      args.insert(contentsOf: parts, at: 0)
    }

    // Run with safe draining & timeout.
    let timeout = (ProcessInfo.processInfo.environment["X10_IREE_TIMEOUT_SEC"]).flatMap(Int.init) ?? 20
    let (status, stdout, stderr) = try run(tool.url, args: args, timeoutSeconds: timeout)

    if ProcessInfo.processInfo.environment["X10_IREE_VERBOSE"] == "1" {
      FileHandle.standardError.write(Data("[IREE] iree-run-module status=\(status)\n".utf8))
      if !stderr.isEmpty { FileHandle.standardError.write(Data(stderr.utf8)) }
      if !stdout.isEmpty { FileHandle.standardError.write(Data(stdout.utf8)) }
    }

    // Clean up temp file
    try? FileManager.default.removeItem(at: modURL)

    guard status == 0 else {
      throw error("iree-run-module failed: \(firstLine(stderr).map { String($0) } ?? "unknown error")")
    }

    // Parse a line like: "2x3xf32=[1 2 3][4 5 6]" or "2x3xf32=1 2 3 4 5 6"
    let hay = stdout + "\n" + stderr
    guard let line = hay
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .first(where: { $0.contains("xf32=") || $0.contains("xi32=") || $0.contains("xi64=") || $0.contains("xbf16=") || $0.contains("xf16=") || $0.contains("xf64=") })
    else {
      throw error("unable to parse result tensor from iree-run-module output")
    }

    // Split before '='
    guard let eq = line.firstIndex(of: "=") else { throw error("malformed result line: \(line)") }
    let lhs = String(line[..<eq]).trimmingCharacters(in: .whitespaces)    // e.g. "2x3xf32"
    let rhs = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

    // LHS: parse shape+dtype
    guard let xIdx = lhs.lastIndex(of: "x") else { throw error("malformed type token: \(lhs)") }
    let dtypeToken = String(lhs[lhs.index(after: xIdx)...])                // "f32", "i32", etc.
    let shapePart = String(lhs[..<xIdx])                                   // "2x3x"
    let dims = shapePart.split(separator: "x").compactMap { Int($0) }

    // RHS: parse values (either space-separated or bracket groups)
    let valueString = rhs.replacingOccurrences(of: "[", with: " ")
                          .replacingOccurrences(of: "]", with: " ")
    let scalars = valueString.split(whereSeparator: { $0.isWhitespace || $0 == "," })
                             .compactMap { Double($0) }

    return Result(shape: dims, dtypeToken: dtypeToken, scalars: scalars)
  }

  // MARK: - Back-compat raw runner (stdout, stderr, status)

  /// Compatibility wrapper for older example code expecting raw output.
  /// Prefer `runAndParse` for structured results.
  public static func runVMFB(vmfb: Data, entry: String, inputs: [String]) throws -> (String, String, Int32) {
    guard let tool = find() else {
      throw error("iree-run-module not found; set X10_IREE_PREFIX or X10_IREE_RUN_BIN")
    }

    // Write module to temp file.
    let tmp = FileManager.default.temporaryDirectory
    let modURL = tmp.appendingPathComponent(UUID().uuidString).appendingPathExtension("vmfb")
    try vmfb.write(to: modURL)

    // Build arguments
    var args: [String] = []
    let device = ProcessInfo.processInfo.environment["X10_IREE_RUN_DEVICE"] ?? "local-task"
    args.append(contentsOf: ["--device=\(device)"])
    args.append("--function=\(entry)")
    args.append("--module=\(modURL.path)")
    for v in inputs { args.append("--input=\(v)") }

    if let extra = ProcessInfo.processInfo.environment["X10_IREE_RUN_EXTRA_FLAGS"], !extra.isEmpty {
      let parts = extra.split(separator: " ").map(String.init)
      args.insert(contentsOf: parts, at: 0)
    }

    let timeout = (ProcessInfo.processInfo.environment["X10_IREE_TIMEOUT_SEC"]).flatMap(Int.init) ?? 20
    let (status, stdout, stderr) = try run(tool.url, args: args, timeoutSeconds: timeout)

    // Clean up temp file (best-effort)
    try? FileManager.default.removeItem(at: modURL)

    return (stdout, stderr, status)
  }

  // MARK: - Safe process runner (drains pipes concurrently, supports timeout)

  private static func run(_ tool: URL, args: [String], timeoutSeconds: Int) throws -> (Int32, String, String) {
    let p = Process()
    p.executableURL = tool
    p.arguments = args
    p.standardInput = FileHandle.nullDevice

    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError  = err

    var stdoutData = Data()
    var stderrData = Data()
    let group = DispatchGroup()

    try p.run()

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      stdoutData = out.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      stderrData = err.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    let termSem = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in termSem.signal() }

    let timeout = DispatchTime.now() + .seconds(timeoutSeconds)
    if termSem.wait(timeout: timeout) == .timedOut {
      p.terminate()
      _ = termSem.wait(timeout: .now() + .seconds(2))
    }

    _ = group.wait(timeout: .now() + .seconds(5))

    let status = p.terminationStatus
    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
    return (status, stdout, stderr)
  }

  private static func error(_ message: String) -> NSError {
    NSError(domain: "IREEExecuteCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private static func firstLine(_ s: String) -> String? {
    s.split(whereSeparator: \.isNewline).first.map(String.init)
  }
}
