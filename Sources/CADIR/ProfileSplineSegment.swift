import CADGeometry

public struct ProfileSplineSegment: Sendable, Hashable {
    public var curve: BSplineCurve3D

    public init(curve: BSplineCurve3D) {
        self.curve = curve
    }
}
