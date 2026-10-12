import CADCore
import CADGeometry

package protocol FaceParameterBoundsResolving: Sendable {
    func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox
}
