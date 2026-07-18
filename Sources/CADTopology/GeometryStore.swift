import CADCore
import CADGeometry

public struct GeometryStore: Codable, Equatable, Sendable {
    public var curves: PersistentMap<CurveID, Curve3D>
    public var surfaces: PersistentMap<SurfaceID, Surface3D>

    public init(curves: [CurveID: Curve3D] = [:], surfaces: [SurfaceID: Surface3D] = [:]) {
        self.curves = PersistentMap(curves)
        self.surfaces = PersistentMap(surfaces)
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
