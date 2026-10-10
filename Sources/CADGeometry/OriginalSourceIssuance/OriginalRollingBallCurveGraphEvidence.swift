import CADCore

/// Original unwrapped law/graph owner survives normalized Curve3D rebinding.
public enum OriginalRollingBallCurveGraphEvidence: Sendable {
    case native(OriginalRationalChartReceipt<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>)
    case nativeLift(OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>.Graph)
    case retainedLift(OriginalFiniteRetainedSurfaceLiftGraphs<OriginalAffineSurfaceLiftSnapshot>.Graph)
}
