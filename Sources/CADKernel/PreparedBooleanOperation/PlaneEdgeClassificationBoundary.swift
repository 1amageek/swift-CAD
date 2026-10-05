import CADCore
import CADModeling

/// Retains one original cutting-plane boundary and its independent sector identity.
struct PlaneEdgeClassificationBoundary: Sendable {
    let reference: BooleanFaceSplitComponentReference
    let edge: BRepSewingEdge
    let cuttingFaceID: FaceID
    let targetBodyID: BodyID
}
