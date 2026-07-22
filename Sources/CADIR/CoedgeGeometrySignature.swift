import CADCore
import CADGeometry
import CADTopology

public struct CoedgeGeometrySignature: Codable, Hashable, Sendable {
    public let edge: CurveSpanGeometrySignature
    public let orientation: Orientation
    public let surfaceParameterCurve: SurfaceParameterCurve

    public init(
        edge: CurveSpanGeometrySignature,
        orientation: Orientation,
        surfaceParameterCurve: SurfaceParameterCurve
    ) {
        self.edge = edge
        self.orientation = orientation
        self.surfaceParameterCurve = surfaceParameterCurve
    }

    public func validate(on surface: Surface3D) throws {
        try edge.validate()
        try surfaceParameterCurve.validate(
            on: surface,
            tolerance: GeometrySignatureValidation.tolerance
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case edge
        case orientation
        case surfaceParameterCurve
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(Set(CodingKeys.allCases), in: decoder)
        edge = try container.decode(CurveSpanGeometrySignature.self, forKey: .edge)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        surfaceParameterCurve = try container.decode(
            SurfaceParameterCurve.self,
            forKey: .surfaceParameterCurve
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edge, forKey: .edge)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(surfaceParameterCurve, forKey: .surfaceParameterCurve)
    }
}
