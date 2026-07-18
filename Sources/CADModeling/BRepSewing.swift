import CADCore

/// Builds validated exact B-rep topology from face-patch sewing requests.
public protocol BRepSewing: Sendable {
    func sew(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult
}
