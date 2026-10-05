import CADCore

public struct GeometrySurfaceInterpolationPoint: Sendable {
    public let u: Double
    public let v: Double
    public let point: Point3D
    public init(u: Double, v: Double, point: Point3D) { self.u = u; self.v = v; self.point = point }
}
