@usableFromInline
struct ShapeKey: Hashable {
  let dims: [Int?] // nil means dynamic/polymorphic dim
}
