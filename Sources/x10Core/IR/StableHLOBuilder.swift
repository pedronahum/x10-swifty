// StableHLO-like minimal IR just for bootstrapping textual dumps.

public struct StableHLOModule: Sendable {
  public var functions: [Function] = []
  public init(functions: [Function] = []) { self.functions = functions }

  public struct Function: Sendable {
    public var name: String
    public var args: [Value]
    public var results: [Value]
    public var ops: [Op]
    public init(name: String, args: [Value], results: [Value], ops: [Op]) {
      self.name = name; self.args = args; self.results = results; self.ops = ops
    }
  }

  public struct Value: Sendable, Hashable {
    public var name: String
    public var shape: [Int?]   // nil == dynamic dim
    public var dtype: DType
    public init(_ name: String, _ shape: [Int?], _ dtype: DType) {
      self.name = name; self.shape = shape; self.dtype = dtype
    }
  }

  public enum Op: Sendable {
    case parameter(index: Int, into: Value)
    case add(lhs: Value, rhs: Value, into: Value)
    case multiply(lhs: Value, rhs: Value, into: Value)
    case dotGeneral(lhs: Value, rhs: Value, into: Value,
                    contractingDims: ([Int],[Int]))
    case returnValues([Value])
  }

  // Textual printer (StableHLO-ish)
  public func textual() -> String {
    var out: [String] = []
    for f in functions {
      out.append("func @\(f.name)(" +
        f.args.enumerated().map { i, v in "%\((i)): \(v.dtype.render())" + v.renderShape() }.joined(separator: ", ")
        + ") -> (" +
        f.results.map { v in v.dtype.render() + v.renderShape() }.joined(separator: ", ")
        + ") {")
      for op in f.ops {
        switch op {
        case .parameter(let i, let v):
          out.append("  %\(v.name) = stablehlo.parameter \(i) : \(v.dtype.render())\(v.renderShape())")
        case .add(let a, let b, let r):
          out.append("  %\(r.name) = stablehlo.add %\(a.name), %\(b.name) : \(r.dtype.render())\(r.renderShape())")
        case .multiply(let a, let b, let r):
          out.append("  %\(r.name) = stablehlo.multiply %\(a.name), %\(b.name) : \(r.dtype.render())\(r.renderShape())")
        case .dotGeneral(let a, let b, let r, let (lc, rc)):
          out.append("  %\(r.name) = stablehlo.dot_general %\(a.name), %\(b.name) " +
                     "contracting_dims=\(lc):\(rc) : \(r.dtype.render())\(r.renderShape())")
        case .returnValues(let vs):
          let names = vs.map { "%\($0.name)" }.joined(separator: ", ")
          out.append("  return \(names)")
        }
      }
      out.append("}")
    }
    return out.joined(separator: "\n")
  }
}

fileprivate extension StableHLOModule.Value {
  func renderShape() -> String {
    let dims = shape.map { $0.map(String.init) ?? "?" }.joined(separator: ",")
    return "[\(dims)]"
  }
}

fileprivate extension DType {
  func render() -> String {
    switch self {
    case .f16: return "f16"
    case .bf16: return "bf16"
    case .f32: return "f32"
    case .f64: return "f64"
    case .i32: return "i32"
    case .i64: return "i64"
    }
  }
}

public struct IRBuilder: Sendable {
  public init() {}
  public func function(name: String,
                       args: [(String, [Int?], DType)],
                       results: [(String, [Int?], DType)],
                       build: (inout FnBuilder) -> Void) -> StableHLOModule.Function {
    var fn = FnBuilder(args: args.map { StableHLOModule.Value($0.0, $0.1, $0.2) },
                       results: results.map { StableHLOModule.Value($0.0, $0.1, $0.2) })
    build(&fn)
    return StableHLOModule.Function(name: name, args: fn.args, results: fn.results, ops: fn.ops)
  }

  public struct FnBuilder: Sendable {
    public var args: [StableHLOModule.Value]
    public var results: [StableHLOModule.Value]
    public var ops: [StableHLOModule.Op] = []

    public mutating func parameter(_ index: Int, into v: StableHLOModule.Value) {
      ops.append(.parameter(index: index, into: v))
    }
    public mutating func add(_ a: StableHLOModule.Value, _ b: StableHLOModule.Value, into r: StableHLOModule.Value) {
      ops.append(.add(lhs: a, rhs: b, into: r))
    }
    public mutating func multiply(_ a: StableHLOModule.Value, _ b: StableHLOModule.Value, into r: StableHLOModule.Value) {
      ops.append(.multiply(lhs: a, rhs: b, into: r))
    }
    public mutating func dotGeneral(_ a: StableHLOModule.Value, _ b: StableHLOModule.Value, into r: StableHLOModule.Value,
                                    contractingDims: ([Int],[Int])) {
      ops.append(.dotGeneral(lhs: a, rhs: b, into: r, contractingDims: contractingDims))
    }
    public mutating func returnValues(_ vs: [StableHLOModule.Value]) {
      ops.append(.returnValues(vs))
    }
  }
}
