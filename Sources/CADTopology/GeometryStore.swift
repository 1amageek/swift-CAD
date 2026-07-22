import CADCore
import CADGeometry

public struct GeometryStore: Codable, Equatable, Sendable {
    public var curves: PersistentMap<CurveID, Curve3D>
    public var surfaces: PersistentMap<SurfaceID, Surface3D>

    public init(curves: [CurveID: Curve3D] = [:], surfaces: [SurfaceID: Surface3D] = [:]) {
        self.curves = PersistentMap(curves)
        self.surfaces = PersistentMap(surfaces)
    }

    private enum CodingKeys: String, CodingKey {
        case curves
        case surfaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curves, .surfaces], in: decoder)
        curves = try container.decode(
            PersistentMap<CurveID, Curve3D>.self,
            forKey: .curves
        )
        surfaces = try container.decode(
            PersistentMap<SurfaceID, Surface3D>.self,
            forKey: .surfaces
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curves, forKey: .curves)
        try container.encode(surfaces, forKey: .surfaces)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        for curve in curves.values {
            try curve.validate(tolerance: tolerance)
        }
        for surface in surfaces.values {
            try surface.validate(tolerance: tolerance)
        }
    }
}
