import CADCore

/// Complete original child family retained without duplicating its law arrays.
public enum OriginalRollingBallCurveGraphCoverage: Sendable {
    case native(OriginalFiniteBSplineCharts<BSplineCurve3D>)
    case nativeLift(OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>)
    case retainedLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalAffineSurfaceLiftSnapshot>)
}
