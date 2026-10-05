import CADCore
import CADGeometry

/// An immutable original-law selection receipt; it does not certify display caches.
public struct OriginalEvaluatedCurveGeometry: Sendable, Hashable {
    public let sourceFeatureID: FeatureID
    public let source: EvaluatedCurveSource
    public let kind: EvaluatedCurveKind
    public let curve: Curve3D
    public let parameterDomain: ParameterDomain
    public let startParameter: Double
    public let endParameter: Double
    public let isClosed: Bool

    package init(sourceFeatureID: FeatureID, source: EvaluatedCurveSource,
        kind: EvaluatedCurveKind, curve: Curve3D, parameterDomain: ParameterDomain,
        startParameter: Double, endParameter: Double, isClosed: Bool) {
        self.sourceFeatureID = sourceFeatureID
        self.source = source
        self.kind = kind
        self.curve = curve
        self.parameterDomain = parameterDomain
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.isClosed = isClosed
    }
}
