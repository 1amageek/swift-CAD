import CADCore

public struct OriginalCommonApexConeInput: Sendable {
    public let first: Surface3D
    public let second: Surface3D
    public init(first: Surface3D, second: Surface3D) { self.first = first; self.second = second }
}
