import CADCore
import CADTopology

/// Certifies that solid bodies have disjoint material regions before they are
/// represented as one multi-component body.
package protocol BodyJoinValidating: Sendable {
    func validateDisjointMaterial(
        bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws
}
