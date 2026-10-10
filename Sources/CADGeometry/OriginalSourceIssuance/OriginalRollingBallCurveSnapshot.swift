import CADCore

/// Explicit original Curve3D construction; no fitted or XYZ-only authority.
public struct OriginalRollingBallCurveSnapshot: Sendable {
    enum Capability: Sendable {
        case native(OriginalSourceBinding<BSplineCurve3D>)
        case nativeLift(OriginalSourceBinding<OriginalNativeSurfaceLiftSnapshot>)
        case retainedLift(OriginalSourceBinding<OriginalAffineSurfaceLiftSnapshot>)
    }
    public let original: Curve3D
    let capability: Capability
    init(original: Curve3D,capability: Capability) { self.original=original;self.capability=capability }
}
