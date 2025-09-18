import Foundation
import x10Core

extension CompileOptions {
  /// Stable, minimal JSON for passing options across the C FFI.
  public func toJSON() -> String {
    func esc(_ s: String) -> String {
      var out = ""
      for ch in s {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default: out.append(ch)
        }
      }
      return out
    }
    func precCode(_ p: PrecisionPolicy.Precision) -> String {
      switch p { case .f16: return "f16"; case .bf16: return "bf16"; case .fp8: return "fp8"; case .fp32: return "fp32" }
    }

    var parts: [String] = []
    if let dev = device?.stableKey { parts.append(" \"device\":\"\(esc(dev))\"") }

    let p = precision
    parts.append("""
      \"precision\":{\
      \"activations\":\"\(precCode(p.activations))\",\
      \"matmul\":\"\(precCode(p.matmul))\",\
      \"accumulators\":\"\(precCode(p.accumulators))\"}
    """.replacingOccurrences(of: "\n", with: ""))

    parts.append(" \"debugIR\":\(debugIR ? "true" : "false")")
    parts.append(" \"enableProfiling\":\(enableProfiling ? "true" : "false")")

    if !flags.isEmpty {
      let sorted = flags.sorted { $0.key < $1.key }
      let inner = sorted.map { "\"\(esc($0.key))\":\"\(esc($0.value))\"" }.joined(separator: ",")
      parts.append(" \"flags\":{\(inner)}")
    }

    return "{\(parts.joined(separator: ","))}"
  }
}
