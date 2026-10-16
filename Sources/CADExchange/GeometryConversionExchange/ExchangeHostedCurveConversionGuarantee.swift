import CADCore
import CADGeometry
import CADTopology

public struct ExchangeHostedCurveConversionGuarantee: Sendable {
    public let faceID: FaceID
    public let loopID: LoopID
    public let coedgeOrdinal: Int
    public let hostedSurface: Surface3D
    public let parameterCurve: SurfaceParameterCurve
    public let guarantee: GeometryConversionGuarantee
}
