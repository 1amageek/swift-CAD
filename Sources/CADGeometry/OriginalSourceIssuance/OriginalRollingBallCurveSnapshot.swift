import CADCore

/// Explicit original Curve3D construction; no fitted or XYZ-only authority.
public struct OriginalRollingBallCurveSnapshot: Sendable {
    enum Capability: Sendable {
        case spatialWord(OriginalSourceBinding<OriginalAffineWordSnapshot<OriginalAffineWordCurve3D,OriginalRollingBallCurveSnapshot>>)
        case native(OriginalSourceBinding<BSplineCurve3D>)
        case derivativeCurve(OriginalSourceBinding<OriginalPlaneDerivativeCurveSnapshot>)
        case guideCurve(OriginalSourceBinding<OriginalRetainedGuideCurveSnapshot>)
        case constructionCurve(OriginalSourceBinding<OriginalRetainedConstructionCurveSnapshot>)
        case nativeLift(OriginalSourceBinding<OriginalNativeSurfaceLiftSnapshot>)
        case retainedLift(OriginalSourceBinding<OriginalAffineSurfaceLiftSnapshot>)
        case coonsNativeLift(OriginalSourceBinding<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalCoonsAtlasSnapshot>>)
        case coonsLift(OriginalSourceBinding<OriginalRetainedAtlasSurfaceLiftSnapshot<OriginalCoonsAtlasSnapshot>>)
        case boundaryNativeLift(OriginalSourceBinding<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalBoundaryCorrectionSnapshot>>)
        case boundaryLift(OriginalSourceBinding<OriginalRetainedAtlasSurfaceLiftSnapshot<OriginalBoundaryCorrectionSnapshot>>)
        case derivativeNativeLift(OriginalSourceBinding<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalPlaneDerivativeSurfaceSnapshot>>)
        case derivativeLift(OriginalSourceBinding<OriginalRetainedAtlasSurfaceLiftSnapshot<OriginalPlaneDerivativeSurfaceSnapshot>>)
    }
    public let original: Curve3D
    let capability: Capability
    init(original: Curve3D,capability: Capability) { self.original=original;self.capability=capability }
}
