import CADCore
import CADGeometry

/// A directed projected edge retaining original identity and source parameters.
public struct OrthographicProjectedEdge: Sendable {
    public let edgeID: EdgeID
    public let curveID: CurveID
    public let startVertexID: VertexID
    public let endVertexID: VertexID
    public let startParameter: Double
    public let endParameter: Double
    public let curve: OrthographicProjectedCurve

    public func point(at parameter: Double) throws -> Point2D {
        try validate(parameter)
        return try curve.point(at: parameter)
    }

    public func differentialGeometry(
        at parameter: Double
    ) throws -> OrthographicProjectedCurve.DifferentialGeometry {
        try validate(parameter)
        return try curve.differentialGeometry(at: parameter)
    }

    private func validate(_ parameter: Double) throws {
        guard parameter.isFinite,
              parameter >= min(startParameter, endParameter),
              parameter <= max(startParameter, endParameter) else {
            throw TopologyError.invalidTrim(edgeID)
        }
    }
}
