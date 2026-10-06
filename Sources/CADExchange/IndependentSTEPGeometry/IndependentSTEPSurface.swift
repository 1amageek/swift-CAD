import CADGeometry

/// An independent exact surface, without generated face or shell topology.
public struct IndependentSTEPSurface: Sendable {
    public let name: String
    public let surface: Surface3D

    public init(name: String, surface: Surface3D) {
        self.name = name
        self.surface = surface
    }
}
