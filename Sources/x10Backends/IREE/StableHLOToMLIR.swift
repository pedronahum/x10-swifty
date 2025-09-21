import Foundation
import x10Core

/// Converts our toy StableHLO textual IR into valid MLIR with `func.func` and `tensor<...>` types.
/// Minimal support: a single function with two inputs, one `stablehlo.add`, and a return.
/// This is enough for our examples/tests; extend as we add more ops.
internal func stablehloToyToMLIRModule(_ toy: String) -> String? {
  // Find function name: between "func @" and "("; default to "main" if not found.
  let name: String = {
    guard let r = toy.range(of: "func @"),
          let p = toy[r.upperBound...].firstIndex(of: "(")
    else { return "main" }
    return String(toy[r.upperBound..<p]).trimmingCharacters(in: .whitespacesAndNewlines)
  }()

  // Find the add line to extract the element type + shape (e.g. "f32[2,3]").
  guard let addLine = toy.split(whereSeparator: \.isNewline).first(where: { $0.contains("stablehlo.add") }) else {
    return nil
  }
  // After the last ":" should be our toy type token "f32[2,3]" (or i32[...] etc).
  guard let colon = addLine.lastIndex(of: ":") else { return nil }
  let typeSpec = addLine[addLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)

  guard let mlirElt = extractElementType(from: typeSpec),
        let dims    = extractDims(from: typeSpec) else { return nil }

  let mlirType = "tensor<" + dims.map(String.init).joined(separator: "x") + "x" + mlirElt + ">"

  // Compose a simple MLIR module:
  // module { func.func @name(%arg0: T, %arg1: T) -> T { %0 = stablehlo.add %arg0, %arg1 : T ; return %0 : T } }
  var out: [String] = []
  out.append("module {")
  out.append("  func.func @\(name)(%arg0: \(mlirType), %arg1: \(mlirType)) -> \(mlirType) {")
  out.append("    %0 = stablehlo.add %arg0, %arg1 : \(mlirType)")
  out.append("    return %0 : \(mlirType)")
  out.append("  }")
  out.append("}")
  return out.joined(separator: "\n")
}

private func extractElementType(from spec: some StringProtocol) -> String? {
  // Accept these tokens from our DType: f16, bf16, f32, f64, i32, i64
  let tokens = ["f16", "bf16", "f32", "f64", "i32", "i64"]
  for tok in tokens where spec.contains(tok) { return tok }
  return nil
}

private func extractDims(from spec: some StringProtocol) -> [Int]? {
  // spec like "f32[2,3]" -> extract 2,3
  guard let lb = spec.firstIndex(of: "["),
        let rb = spec[spec.index(after: lb)...].firstIndex(of: "]")
  else { return nil }
  let inside = spec[spec.index(after: lb)..<rb]
  let parts = inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  let dims = parts.compactMap { Int($0) }
  return dims.count == parts.count ? dims : nil
}
