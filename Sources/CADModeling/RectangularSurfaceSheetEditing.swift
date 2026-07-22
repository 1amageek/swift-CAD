import CADCore
import CADGeometry
import CADIR
import CADTopology

package protocol RectangularSurfaceSheetEditing: Sendable {
    func bounds(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> RectangularSurfaceParameterBounds

    func resize(
        featureID: FeatureID,
        bodyID: BodyID,
        to bounds: RectangularSurfaceParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws

    func replaceSurface(
        featureID: FeatureID,
        bodyID: BodyID,
        with surface: Surface3D,
        bounds: RectangularSurfaceParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws
}
