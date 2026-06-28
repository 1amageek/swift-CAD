import CADCore

public struct BSplineSurfaceFeature: Codable, Sendable, Hashable {
    public var surface: BSplineSurface3D
    public var material: MaterialID?

    public init(
        surface: BSplineSurface3D,
        material: MaterialID? = nil
    ) {
        self.surface = surface
        self.material = material
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try surface.validate(tolerance: tolerance)
    }
}
