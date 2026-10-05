import CADGeometry
import CADTopology
import CADIR

struct ExchangeCurveConversionPlan: Sendable {
    var edges: [EdgeID: BSplineCurve3D] = [:]
    var selections: [EdgeID: CurveTrim] = [:]
    var hostedBoundaries: [EdgeID: [ExchangeHostedCurveConversionGuarantee]] = [:]
    var items: [IndependentShapeItemID: BSplineCurve3D] = [:]
    var guarantees: [ExchangeCurveConversionGuarantee] = []
}
