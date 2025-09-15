import x10Core
import x10Runtime

@main
struct Demo {
  static func main() async {
    let x = Tensor<Float>(shape: [2, 3], on: .gpu(0))
    let y = Tensor<Float>(shape: [2, 3], on: .gpu(0))
    do {
      let _ = try await x.materialize()
      print("Example OK ->", x, y)
    } catch {
      print("Error:", error)
    }
  }
}
