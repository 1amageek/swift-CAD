import CADCore

public protocol BRepTopologyValidating: Sendable {
    func report(
        for model: BRepModel,
        request: BRepValidationRequest,
        tolerance: ModelingTolerance
    ) throws -> TopologyValidationReport
}
