import HashTreeCollections
import CADCore
import CADGeometry

/// Resolves and validates the original selected topology before publication.
public struct DefaultOrthographicEdgeProjector: OrthographicEdgeProjecting {
    private let curveProjector: any OrthographicCurveProjecting

    public init(curveProjector: any OrthographicCurveProjecting = DefaultOrthographicCurveProjector()) {
        self.curveProjector = curveProjector
    }

    public func project(
        edgeID: EdgeID,
        in model: BRepModel,
        orientation: Orientation = .forward,
        onto frame: OrthographicProjectionFrame,
        tolerance: ModelingTolerance
    ) throws -> OrthographicProjectedEdge {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try project(edgeID: edgeID, in: model, orientation: orientation,
            onto: frame, tolerance: tolerance, using: &execution)
    }

    public func project(edgeID: EdgeID, in model: BRepModel, orientation: Orientation = .forward,
        onto frame: OrthographicProjectionFrame, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> OrthographicProjectedEdge {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard let edge = model.edges[edgeID], edge.id == edgeID,
              let startVertex = model.vertices[edge.startVertexID],
              startVertex.id == edge.startVertexID,
              let endVertex = model.vertices[edge.endVertexID],
              endVertex.id == edge.endVertexID else {
            throw TopologyError.invalidEdge(edgeID)
        }
        guard let source = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing curve \(edge.curveID).")
        }
        let projected = try curveProjector.project(source, onto: frame, tolerance: tolerance, using: &execution)
        try startVertex.point.validate()
        try endVertex.point.validate()
        let trim: CurveTrim
        if let originalTrim = edge.trim {
            trim = originalTrim
        } else {
            // An unbounded linear image retains the original affine parameter law.
            // A bounded rational straight-line locus does not establish that law.
            guard case .unbounded = source.parameterDomain,
                  let line = try source.exactLinearLocus(using: &execution) else {
                throw TopologyError.invalidTrim(edgeID)
            }
            let length = line.direction.length
            guard length.isFinite, length > 0.0 else {
                throw TopologyError.invalidEdge(edgeID)
            }
            let direction = line.direction / length
            trim = CurveTrim(
                startParameter: (startVertex.point - line.origin).dot(direction) / length,
                endParameter: (endVertex.point - line.origin).dot(direction) / length
            )
        }
        try trim.validate(on: source, edgeID: edgeID, tolerance: tolerance,
            remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth),
            maximumAlgebraicDepth: min(32, execution.effectiveLimits.maximumValueDepth),
            maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth), using: &execution)
        let originalStart = try projected.originalPoint(at: trim.startParameter, using: &execution)
        let originalEnd = try projected.originalPoint(at: trim.endParameter, using: &execution)
        let startResidual = (startVertex.point - originalStart).length
        let endResidual = (endVertex.point - originalEnd).length
        let endpointAllowance = tolerance.distance * 8.0
        guard endpointAllowance.isFinite,
              startResidual.isFinite, endResidual.isFinite,
              startResidual <= endpointAllowance, endResidual <= endpointAllowance else {
            throw TopologyError.invalidEdge(edgeID)
        }
        if (startVertex.point - endVertex.point).length <= tolerance.distance,
           try BRepEdgeGeometryClassifier().kind(curve: source, from: trim.startParameter,
               to: trim.endParameter, tolerance: tolerance, using: &execution) == .open { throw TopologyError.invalidEdge(edgeID) }
        // Verify finite projection at both published trim endpoints.
        _ = try frame.project(originalStart)
        _ = try frame.project(originalEnd)
        try execution.consumeWork(1)
        let reversed = orientation == .reversed
        return OrthographicProjectedEdge(
            edgeID: edgeID,
            curveID: edge.curveID,
            startVertexID: reversed ? edge.endVertexID : edge.startVertexID,
            endVertexID: reversed ? edge.startVertexID : edge.endVertexID,
            startParameter: reversed ? trim.endParameter : trim.startParameter,
            endParameter: reversed ? trim.startParameter : trim.endParameter,
            curve: projected
        )
    }
}
