import CADCore
import CADGeometry
import CADIR
import CADKernel

public struct DocumentDrawingSilhouetteProducer: DocumentDrawingSilhouetteProducing {
    private let producer: any BRepDrawingSilhouetteProducing
    public init(producer: any BRepDrawingSilhouetteProducing = BRepDrawingSilhouetteProducer()) {
        self.producer = producer
    }
    public func silhouettes(_ placement: BRepDrawingPlacement, document: CADDocument,
        currentEvaluation: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
        maximumSourceEntities: Int, maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes {
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Placed silhouettes require the complete current source document.")
        }
        return try producer.silhouettes(placement, in: currentEvaluation, onto: frame,
            maximumSourceEntities: maximumSourceEntities, maximumSourceFaces: maximumSourceFaces,
            maximumProjectedSpans: maximumProjectedSpans, maximumControlPointCount: maximumControlPointCount,
            maximumBoundaryCurveCount: maximumBoundaryCurveCount, usage: &usage)
    }
    public func silhouettes(document: CADDocument, currentEvaluation: EvaluatedDocument,
        onto frame: OrthographicProjectionFrame, maximumSourceFaces: Int,
        maximumProjectedSpans: Int, maximumControlPointCount: Int,
        maximumBoundaryCurveCount: Int, usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes {
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Original silhouettes require the complete current source document.")
        }
        return try producer.silhouettes(in: currentEvaluation, onto: frame,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount,
            maximumBoundaryCurveCount: maximumBoundaryCurveCount, usage: &usage)
    }
}
