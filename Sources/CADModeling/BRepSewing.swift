import CADCore
import CADGeometry

/// Builds validated exact B-rep topology from face-patch sewing requests.
public protocol BRepSewing: Sendable {
    func sew(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult
    func sew(_ request: BRepSewingRequest, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BRepSewingResult
}
