import CADCore
import CADGeometry

public protocol BRepRepairing: Sendable {
    func repair(
        _ model: BRepModel,
        request: BRepRepairRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepRepairResult
    func repair(_ model: BRepModel, request: BRepRepairRequest,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepRepairResult
}
