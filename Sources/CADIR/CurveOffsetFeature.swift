import CADCore

public struct CurveOffsetFeature: Codable, Hashable, Sendable {
    public var source: CurveOutputReference
    public var distance: CADExpression
    public var planeNormal: Vector3D
    public var side: CurveOffsetSide
    public var sampleCount: Int

    public init(
        source: CurveOutputReference,
        distance: CADExpression,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left,
        sampleCount: Int = 33
    ) {
        self.source = source
        self.distance = distance
        self.planeNormal = planeNormal
        self.side = side
        self.sampleCount = sampleCount
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try source.validate()
        try distance.validateLiteralQuantities()
        try planeNormal.validateUnitLength(tolerance: tolerance)
        guard sampleCount >= 4 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
    }
}

public enum CurveOffsetSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
}
