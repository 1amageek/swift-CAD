import CADCore
import CADIR
import CADTopology

package protocol PlanarBodyGeometryRebuilding: Sendable {
    func rebuild(
        featureID: FeatureID,
        bodyID: BodyID,
        in model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws
}
