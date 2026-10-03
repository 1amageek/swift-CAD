import CADCore

/// Square's Analysis of one given side, measured on the evaluated sheet: the largest distance from
/// the side's curve to the sheet's boundary along it (G0), and for a side continuous with the face
/// beside its edge the largest angle between their normals (G1) and, at curvature order, the
/// largest difference of their normal curvatures across the side (G2), each with the limit it is
/// judged against.
public struct SquareSideAnalysis: Sendable, Hashable {
    /// The index of the side in the Square's sides.
    public let side: Int
    public let position: Double
    public let positionLimit: Double
    public let angle: Double?
    public let angleLimit: Double?
    public let curvature: Double?
    public let curvatureLimit: Double?
    /// The middle of the side's curve, where its Analysis is shown; nil when the analysis measures
    /// no curve of its own.
    public let point: Point3D?

    public init(side: Int, position: Double, positionLimit: Double, angle: Double? = nil, angleLimit: Double? = nil,
                curvature: Double? = nil, curvatureLimit: Double? = nil, point: Point3D? = nil) {
        self.side = side
        self.point = point
        self.position = position
        self.positionLimit = positionLimit
        self.angle = angle
        self.angleLimit = angleLimit
        self.curvature = curvature
        self.curvatureLimit = curvatureLimit
    }

    /// Whether every measure is within its limit.
    public var isWithin: Bool {
        position <= positionLimit
            && (angle.map { $0 <= (angleLimit ?? 0) } ?? true)
            && (curvature.map { $0 <= (curvatureLimit ?? 0) } ?? true)
    }
}
