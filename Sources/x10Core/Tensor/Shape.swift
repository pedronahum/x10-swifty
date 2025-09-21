public enum DimSpec: Equatable, Hashable, Sendable {
  case exact(Int)
  case any
  case bucket(lo: Int, hi: Int)
}
