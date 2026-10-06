import CADIR
import CADKernel

public protocol DocumentDrawingRegionProducing: Sendable {
    func regions(_ section: BRepDrawingSection, document: CADDocument,
                 currentEvaluation: EvaluatedDocument, maximumBoundaryEdges: Int,
                 maximumRegions: Int) throws -> [BRepDrawingMaterialRegion]
}
