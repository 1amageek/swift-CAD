import CADCore
import CADIR

public struct SelectionMeasurementPoint: Codable, Sendable, Hashable {
    public var selection: SelectionReference
    public var point: Point3D
    public var tangent: Vector3D?
    public var normal: Vector3D?
    public var curvature: Double?

    public init(
        selection: SelectionReference,
        point: Point3D,
        tangent: Vector3D? = nil,
        normal: Vector3D? = nil,
        curvature: Double? = nil
    ) {
        self.selection = selection
        self.point = point
        self.tangent = tangent
        self.normal = normal
        self.curvature = curvature
    }
}
