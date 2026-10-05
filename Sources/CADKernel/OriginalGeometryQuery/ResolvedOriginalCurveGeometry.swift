import CADCore
import CADGeometry
import CADIR
import CADModeling

/// Original-law geometry tied to the exact queried output key.
public struct ResolvedOriginalCurveGeometry: Sendable, Hashable {
    public let reference: CurveOutputReference
    public let original: OriginalEvaluatedCurveGeometry
    public var curve: Curve3D { original.curve }
    public var parameterDomain: ParameterDomain { original.parameterDomain }
    public var startParameter: Double { original.startParameter }
    public var endParameter: Double { original.endParameter }

    package init(reference: CurveOutputReference, original: OriginalEvaluatedCurveGeometry) {
        self.reference = reference
        self.original = original
    }
}
