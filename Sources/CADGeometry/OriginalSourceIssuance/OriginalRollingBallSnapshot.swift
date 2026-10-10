import CADCore

public struct OriginalRollingBallSnapshot<Child: OriginalBSplineSourceReading>: OriginalRollingBallSourceReading {
    public let original: RollingBallBlendSurface3D
    public let originalCenter: OriginalSourceBinding<Child>
    public let originalFirstContact: OriginalSourceBinding<Child>
    public let originalSecondContact: OriginalSourceBinding<Child>
    public var originalRadius: Double { original.radius }
    public var originalDistanceTolerance: Double { original.tolerance.distance }
    public var originalRadialCrossThreshold: Double { original.originalRadialCrossThreshold }
    init(original: RollingBallBlendSurface3D, center: OriginalSourceBinding<Child>,
        first: OriginalSourceBinding<Child>, second: OriginalSourceBinding<Child>) {
        self.original = original; originalCenter = center
        originalFirstContact = first; originalSecondContact = second
    }
}
