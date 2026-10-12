/// One shared boundary identity represented by two opposite cell-local faces.
public struct SolidInterface: Equatable, Sendable {
    public let first: SolidFaceUse
    public let second: SolidFaceUse

    public init(first: SolidFaceUse, second: SolidFaceUse) {
        self.first = first
        self.second = second
    }
}
