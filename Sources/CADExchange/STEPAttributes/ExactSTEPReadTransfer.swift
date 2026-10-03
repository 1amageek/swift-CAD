import CADCore
import CADTopology

struct ExactSTEPReadTransfer {
    let model: BRepModel
    let bodies: [Int: BodyID]
    let faces: [Int: FaceID]
}
