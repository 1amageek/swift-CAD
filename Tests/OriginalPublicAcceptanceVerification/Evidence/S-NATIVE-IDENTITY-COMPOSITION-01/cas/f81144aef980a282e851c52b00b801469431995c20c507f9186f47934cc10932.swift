import CADCore

public protocol BRepRepairing: Sendable {
    func repair(
        _ model: BRepModel,
        request: BRepRepairRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepRepairResult
}
