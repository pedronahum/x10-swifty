import Foundation

public struct Executable: Sendable, Equatable {
  public let id: UUID
  public init(id: UUID = UUID()) { self.id = id }
  public static func == (lhs: Executable, rhs: Executable) -> Bool { lhs.id == rhs.id }
}
