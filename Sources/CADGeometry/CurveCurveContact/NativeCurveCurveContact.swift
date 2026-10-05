import CADCore

/// Immutable contact truth bound to both original native source curves.
public struct NativeCurveCurveContact: Sendable {
    public enum Kind: Sendable {
        case point(first: ScalarInterval, second: ScalarInterval,
                   firstNativeSpan: Int, secondNativeSpan: Int, position: CoordinateEnclosure3D)
        case identityOverlap(first: ScalarInterval, second: ScalarInterval)
        case overlap(NativeCurveCurveCorrespondence)
        case algebraicOverlap(NativeCurveCurveAlgebraicCorrespondence)
    }

    public let firstSource: BSplineCurve3D
    public let secondSource: BSplineCurve3D
    public let kind: Kind
    public let tolerance: ModelingTolerance
    public let parameterAuthority: OriginalCurveContactParameterAuthority?

    init(firstSource: BSplineCurve3D, secondSource: BSplineCurve3D, kind: Kind, tolerance: ModelingTolerance,
        parameterAuthority: OriginalCurveContactParameterAuthority? = nil) {
        self.firstSource = firstSource
        self.secondSource = secondSource
        self.kind = kind
        self.tolerance = tolerance
        self.parameterAuthority = parameterAuthority
    }
}
