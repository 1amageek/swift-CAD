import CADCore

public struct OriginalGraphRollingBallSnapshot: OriginalRollingBallChildSourceReading {
    public let original: RollingBallBlendSurface3D
    public let originalCenter: OriginalSourceBinding<OriginalRollingBallCurveSnapshot>
    public let originalFirstContact: OriginalSourceBinding<OriginalRollingBallCurveSnapshot>
    public let originalSecondContact: OriginalSourceBinding<OriginalRollingBallCurveSnapshot>
    public var originalRadius: Double { original.radius }
    public var originalDistanceTolerance: Double { original.tolerance.distance }
    public var originalRadialCrossThreshold: Double { original.originalRadialCrossThreshold }
    init(original: RollingBallBlendSurface3D,center: OriginalSourceBinding<OriginalRollingBallCurveSnapshot>,
        first: OriginalSourceBinding<OriginalRollingBallCurveSnapshot>,second: OriginalSourceBinding<OriginalRollingBallCurveSnapshot>) {
        self.original=original;originalCenter=center;originalFirstContact=first;originalSecondContact=second
    }
}
