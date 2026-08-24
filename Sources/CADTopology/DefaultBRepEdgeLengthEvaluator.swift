import CADCore
import CADGeometry

public struct DefaultBRepEdgeLengthEvaluator: BRepEdgeLengthEvaluating {
    private let arcLengthResolver: any CurveArcLengthResolving

    public init(
        arcLengthResolver: any CurveArcLengthResolving = DefaultCurveArcLengthResolver()
    ) {
        self.arcLengthResolver = arcLengthResolver
    }

    public func lengthEnclosure(
        of edge: Edge,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure {
        try tolerance.validate()
        guard let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference(
                "Edge \(edge.id) references missing curve \(edge.curveID)."
            )
        }
        try curve.validate(tolerance: tolerance)
        let interval = try parameterInterval(
            of: edge,
            curve: curve,
            in: model,
            tolerance: tolerance
        )
        return try arcLengthResolver.enclosure(
            of: curve,
            over: interval,
            tolerance: tolerance
        )
    }

    private func parameterInterval(
        of edge: Edge,
        curve: Curve3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: edge.id, tolerance: tolerance)
            return try ScalarInterval(
                lower: min(trim.startParameter, trim.endParameter),
                upper: max(trim.startParameter, trim.endParameter)
            )
        }
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            guard let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference(
                    "Unbounded edge \(edge.id) requires both endpoint vertices."
                )
            }
            let startParameter = try curve.parameterProjection(
                of: start,
                tolerance: tolerance
            ).parameter
            let endParameter = try curve.parameterProjection(
                of: end,
                tolerance: tolerance
            ).parameter
            return try ScalarInterval(
                lower: min(startParameter, endParameter),
                upper: max(startParameter, endParameter)
            )
        }
    }
}
