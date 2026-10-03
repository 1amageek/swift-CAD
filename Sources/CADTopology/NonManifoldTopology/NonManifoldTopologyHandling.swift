import CADCore

public protocol NonManifoldTopologyHandling: Sendable {
    func retain(_ source: any ShapeRepresenting, limits: TopologyRetentionLimits) throws -> RetainedTopologyShape
    func diagnose(_ retained: RetainedTopologyShape, limits: TopologyRetentionLimits) throws -> NonManifoldTopologyReport
    func admitToShapeOperations(_ retained: RetainedTopologyShape, tolerance: ModelingTolerance,
        limits: TopologyRetentionLimits) throws -> Shape
    func admitToBRepModeling(_ retained: RetainedTopologyShape, tolerance: ModelingTolerance,
        limits: TopologyRetentionLimits) throws -> ValidatedBRepModel
}
