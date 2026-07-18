import CADCore

public struct CurveOffsetFeature: Codable, Hashable, Sendable {
    public var source: CurveOutputReference
    public var distance: CADExpression
    public var planeNormal: Vector3D
    public var side: CurveOffsetSide

    public init(
        source: CurveOutputReference,
        distance: CADExpression,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left
    ) {
        self.source = source
        self.distance = distance
        self.planeNormal = planeNormal
        self.side = side
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try source.validate()
        try distance.validateLiteralQuantities()
        try planeNormal.validateUnitLength(tolerance: tolerance)
    }
}

public enum CurveOffsetSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
}
