import CADCore

public enum KernelQueryResult: Sendable {
    case evaluatedDocument(EvaluatedDocument)
    case lineage(TopologyLineage?)
    case diagnostics(EvaluationReport)
    case snap(SnapQueryResult)
    case measurement(MeasurementQueryResult)
    case selectionDimensionEvaluation(SelectionDimensionEvaluation)
    case projection(ProjectionQueryResult)
}
