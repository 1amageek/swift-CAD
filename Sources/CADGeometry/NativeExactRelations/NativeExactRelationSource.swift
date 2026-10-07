import CADCore

/// Immutable value snapshots of authored inputs and their original selections.
public enum NativeExactRelationSource: Sendable {
    case curveSurface(curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval?, surfaceDomain: SurfaceParameterBox?)
    case surfaceSurface(first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox?, secondDomain: SurfaceParameterBox?)
}
