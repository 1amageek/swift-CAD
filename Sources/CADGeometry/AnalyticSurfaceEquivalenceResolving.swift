import CADCore

protocol AnalyticSurfaceEquivalenceResolving: Sendable {
    func areEquivalent(
        _ first: Surface3D,
        _ second: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
