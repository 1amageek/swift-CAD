import CADCore
import CADIR
import CADKernel

public struct DocumentDrawingRegionProducer: DocumentDrawingRegionProducing {
    private let producer: any BRepDrawingRegionProducing

    public init(producer: any BRepDrawingRegionProducing = BRepDrawingRegionProducer()) {
        self.producer = producer
    }

    public func regions(_ section: BRepDrawingSection, document: CADDocument,
                        currentEvaluation: EvaluatedDocument, maximumBoundaryEdges: Int,
                        maximumRegions: Int) throws -> [BRepDrawingMaterialRegion] {
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Original section regions require the complete current source.")
        }
        return try producer.regions(section, in: currentEvaluation,
            maximumBoundaryEdges: maximumBoundaryEdges, maximumRegions: maximumRegions)
    }
}
