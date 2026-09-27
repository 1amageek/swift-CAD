import CADCore
import CADTopology

/// Where a body lies relative to a plane, as far as its geometry proves it.
package enum BodyPlaneSide: Sendable, Equatable {
    /// All of the body lies on one side of the plane, clear of it by more than the tolerance.
    case clear
    /// All of the body lies on one side of the plane and may reach it within the tolerance.
    case oneSided
    /// Neither could be proven: the body may cross the plane.
    case undetermined
}

/// Proves on which side of a plane a body lies from enclosures of its geometry, never from
/// samples, so `clear` and `oneSided` hold for every point of the body.
package protocol BodyPlaneSideClassifying: Sendable {
    func side(
        of bodyID: BodyID,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BodyPlaneSide
}
