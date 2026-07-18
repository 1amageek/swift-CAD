import CADCore
import CADIR
import CADModeling
import CADTopology

public protocol BRepFacePatchExtracting: Sendable {
    func extract(
        bodyID: BodyID,
        featureID: FeatureID,
        from model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingExtraction
}
