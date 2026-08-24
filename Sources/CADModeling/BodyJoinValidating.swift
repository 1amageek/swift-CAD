import CADCore
import CADTopology

/// Identifies an exact material or boundary interaction between two solid
/// bodies. Pattern reconstruction uses these edges to isolate Boolean-connected
/// components; Join requires the interaction set to be empty.
public struct BodyMaterialInteraction: Hashable, Sendable {
    public let firstBodyID: BodyID
    public let secondBodyID: BodyID

    public init(firstBodyID: BodyID, secondBodyID: BodyID) {
        self.firstBodyID = firstBodyID
        self.secondBodyID = secondBodyID
    }
}

/// Resolves exact material relationships. The Modeling package owns the port;
/// a geometry-kernel adapter owns broad-phase, intersection, and classification.
public protocol BodyJoinValidating: Sendable {
    func materialInteractions(
        bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [BodyMaterialInteraction]

    func validateDisjointMaterial(
        bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws
}
