import CADGeometry
import CADTopology
import CADIR

public struct ExchangeCurveConversionGuarantee: Sendable {
    public let curveID: CurveID
    public let edgeID: EdgeID?
    public let itemID: IndependentShapeItemID?
    public let originalCurve: Curve3D
    public let startParameter: Double
    public let endParameter: Double
    public let guarantee: GeometryConversionGuarantee
    public let hostedBoundaries: [ExchangeHostedCurveConversionGuarantee]
}
