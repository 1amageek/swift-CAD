import CADCore

/// Immutable original curve law and authored finite parameter restriction.
public struct OriginalCurveContactSource: Sendable, Hashable {
    public let curve: Curve3D
    public let parameters: ScalarInterval

    public init(curve: Curve3D, parameters: ScalarInterval) {
        self.curve = curve
        self.parameters = parameters
    }
}
