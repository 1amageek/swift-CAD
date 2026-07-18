import CADCore
import CADIR
import CADTopology

package protocol RectangularPlanarSheetEditing: Sendable {
    func bounds(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> PlanarSheetParameterBounds

    func resize(
        bodyID: BodyID,
        to bounds: PlanarSheetParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws
}
