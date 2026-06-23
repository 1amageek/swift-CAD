import CADCore
import CADIR

public struct SnapQueryCandidate: Codable, Sendable, Hashable {
    public var kind: SnapCandidateKind
    public var selection: SelectionReference
    public var persistentName: PersistentName
    public var role: SnapCandidateRole?
    public var point: Point3D
    public var distance: Double
    public var tangent: Vector3D?
    public var normal: Vector3D?
    public var curvature: Double?

    public init(
        kind: SnapCandidateKind,
        selection: SelectionReference,
        persistentName: PersistentName,
        role: SnapCandidateRole? = nil,
        point: Point3D,
        distance: Double,
        tangent: Vector3D? = nil,
        normal: Vector3D? = nil,
        curvature: Double? = nil
    ) {
        self.kind = kind
        self.selection = selection
        self.persistentName = persistentName
        self.role = role
        self.point = point
        self.distance = distance
        self.tangent = tangent
        self.normal = normal
        self.curvature = curvature
    }
}
