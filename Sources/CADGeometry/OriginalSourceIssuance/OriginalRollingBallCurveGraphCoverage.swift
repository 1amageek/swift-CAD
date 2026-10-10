import CADCore

/// Complete original child family retained without duplicating its law arrays.
public enum OriginalRollingBallCurveGraphCoverage: Sendable {
    case native(OriginalFiniteBSplineCharts<BSplineCurve3D>)
    case derivativeCurve(OriginalFiniteRetainedCurveCharts<OriginalPlaneDerivativeCurveSnapshot>)
    case nativeLift(OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>)
    case retainedLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalAffineSurfaceLiftSnapshot>)
    case coonsNativeLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalCoonsAtlasSnapshot>>)
    case coonsLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalRetainedAtlasSurfaceLiftSnapshot<OriginalCoonsAtlasSnapshot>>)
    case boundaryNativeLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalBoundaryCorrectionSnapshot>>)
    case boundaryLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalRetainedAtlasSurfaceLiftSnapshot<OriginalBoundaryCorrectionSnapshot>>)
    case derivativeNativeLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalPlaneDerivativeSurfaceSnapshot>>)
    case derivativeLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalRetainedAtlasSurfaceLiftSnapshot<OriginalPlaneDerivativeSurfaceSnapshot>>)
}
