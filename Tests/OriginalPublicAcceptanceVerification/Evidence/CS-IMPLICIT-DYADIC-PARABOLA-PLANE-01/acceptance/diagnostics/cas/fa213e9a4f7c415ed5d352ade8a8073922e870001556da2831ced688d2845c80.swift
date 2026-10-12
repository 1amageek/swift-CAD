/// Retains the actual immutable certified graph and its original Native parents.
public struct OriginalImplicitCurveSnapshot: Sendable {
    public let original: CertifiedImplicitIntersectionCurve
    public let first: OriginalSourceBinding<BSplineSurface3D>
    public let second: OriginalSourceBinding<BSplineSurface3D>
    public var cell: CertifiedImplicitIntersectionGraphCell { original.cells[0] }

    init(original: CertifiedImplicitIntersectionCurve,
        first: OriginalSourceBinding<BSplineSurface3D>, second: OriginalSourceBinding<BSplineSurface3D>) {
        self.original = original; self.first = first; self.second = second
    }
}
