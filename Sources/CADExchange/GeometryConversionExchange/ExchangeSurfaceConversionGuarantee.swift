import CADCore
import CADGeometry
import CADTopology

public struct ExchangeSurfaceConversionGuarantee: Sendable {
    public let surfaceID: SurfaceID
    public let originalSurface: Surface3D
    public let parameters: SurfaceParameterBox
    public let guarantee: GeometryConversionGuarantee
}
