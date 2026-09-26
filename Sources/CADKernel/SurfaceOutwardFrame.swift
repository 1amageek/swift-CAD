import CADCore
import CADIR

/// A point on a face with the face's outward normal there: the surface normal oriented by the
/// face's sense in its shell, so it points out of the body the face bounds.
public struct SurfaceOutwardFrame: Codable, Sendable, Hashable {
    public var parameter: SurfaceParameterReference
    public var point: Point3D
    public var outwardNormal: Vector3D

    public init(parameter: SurfaceParameterReference, point: Point3D, outwardNormal: Vector3D) {
        self.parameter = parameter
        self.point = point
        self.outwardNormal = outwardNormal
    }
}
