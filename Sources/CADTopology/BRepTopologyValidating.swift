import CADCore
import CADGeometry

public protocol BRepTopologyValidating: Sendable {
    func report(
        for model: BRepModel,
        request: BRepValidationRequest,
        tolerance: ModelingTolerance
    ) throws -> TopologyValidationReport
    func report(for model: BRepModel, request: BRepValidationRequest,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> TopologyValidationReport
}
