import CADCore
import CADGeometry
import CADIR
import CADKernel

public struct DocumentDrawingProjectedContactPreparer: DocumentDrawingProjectedContactPreparing {
    private let producer: any BRepDrawingProjectedContactPreparing
    public init(producer: any BRepDrawingProjectedContactPreparing = DefaultBRepDrawingProjectedContactPreparer()) {
        self.producer = producer
    }
    public func prepare(_ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        document: CADDocument, currentEvaluation: EvaluatedDocument, maximumPartitions: Int,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingProjectedContacts {
        try execution.consumeWork(1)
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Projected contact preparation requires the complete current original source.")
        }
        return try producer.prepare(projection, silhouettes: silhouettes, in: currentEvaluation,
            maximumPartitions: maximumPartitions, using: &execution)
    }
}
