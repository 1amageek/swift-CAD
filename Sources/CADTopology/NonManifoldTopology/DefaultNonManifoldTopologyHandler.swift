import CADCore

public struct DefaultNonManifoldTopologyHandler: NonManifoldTopologyHandling {
    public init() {}

    public func retain(_ source: any ShapeRepresenting, limits: TopologyRetentionLimits) throws -> RetainedTopologyShape {
        try CurrentTaskCancellationChecker().checkCancellation()
        let snapshot = source.shapeSnapshot()
        var engine = TopologyRetentionDiagnosticEngine(snapshot: snapshot, limits: limits)
        try engine.inventory()
        try CurrentTaskCancellationChecker().checkCancellation()
        return RetainedTopologyShape(snapshot: snapshot)
    }

    public func diagnose(_ retained: RetainedTopologyShape, limits: TopologyRetentionLimits) throws -> NonManifoldTopologyReport {
        var engine = TopologyRetentionDiagnosticEngine(snapshot: retained.snapshot, limits: limits)
        return try engine.report()
    }

    public func admitToShapeOperations(_ retained: RetainedTopologyShape, tolerance: ModelingTolerance,
        limits: TopologyRetentionLimits) throws -> Shape {
        try requireClean(retained, limits: limits)
        let admitted = try DefaultShapeOperator().extract(retained.snapshot, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return admitted
    }

    public func admitToBRepModeling(_ retained: RetainedTopologyShape, tolerance: ModelingTolerance,
        limits: TopologyRetentionLimits) throws -> ValidatedBRepModel {
        try requireClean(retained, limits: limits)
        let admitted = try ValidatedBRepModel(retained.model, tolerance: tolerance, validationLevel: .exact)
        try CurrentTaskCancellationChecker().checkCancellation()
        return admitted
    }

    private func requireClean(_ retained: RetainedTopologyShape, limits: TopologyRetentionLimits) throws {
        let report = try diagnose(retained, limits: limits)
        guard !report.hasStructuralDefects else { throw TopologyRetentionError.modelingAdmissionRejected(report) }
        try CurrentTaskCancellationChecker().checkCancellation()
    }
}
