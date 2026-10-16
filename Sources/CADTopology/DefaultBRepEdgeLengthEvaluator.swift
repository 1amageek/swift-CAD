import HashTreeCollections
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lengthEnclosure(of: edge, in: model, tolerance: tolerance, using: &execution)
    }

    public func lengthEnclosure(
        of edge: Edge,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> CurveArcLengthEnclosure {
        try execution.consumeWork(1)
        try tolerance.validate()
        let result: CurveArcLengthEnclosure
        let kind = try execution.withProofScope(maximum: ExactScalarDepth(value: 32, coefficient: 32)) { execution in
            try BRepEdgeGeometryClassifier().kind(of: edge, in: model,
                tolerance: tolerance, using: &execution)
        }
        if kind == .singular {
            result = try CurveArcLengthEnclosure(lowerBound: 0, upperBound: 0)
        } else {
            try execution.consumeWork(1)
            guard let curve = model.geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference(
                    "Edge \(edge.id) references missing curve \(edge.curveID)."
                )
            }
            try curve.validate(tolerance: tolerance, using: &execution)
            let interval = try parameterInterval(
                of: edge,
                curve: curve,
                in: model,
                tolerance: tolerance, using: &execution
            )
            let options = CurveArcLengthOptions()
            result = try arcLengthResolver.enclosure(
                of: curve,
                over: interval,
                options: options,
                tolerance: tolerance,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumAlgebraicDepth: nil, using: &execution
            )
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<CurveArcLengthEnclosure>.stride)
        try execution.checkpoint()
        return result
    }

    package func parameterInterval(
        of edge: Edge,
        curve: Curve3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterInterval(of: edge, curve: curve, in: model,
            tolerance: tolerance, using: &execution)
    }

    package func parameterInterval(
        of edge: Edge,
        curve: Curve3D,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> ScalarInterval {
        try execution.consumeWork(1)
        let result: ScalarInterval
        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: edge.id, tolerance: tolerance, using: &execution)
            result = try ScalarInterval(
                lower: min(trim.startParameter, trim.endParameter),
                upper: max(trim.startParameter, trim.endParameter)
            )
        } else {
            try execution.consumeWork(1)
            switch curve.parameterDomain {
            case let .closed(lower, upper):
                result = try ScalarInterval(lower: lower, upper: upper)
            case let .periodic(period):
                result = try ScalarInterval(lower: 0.0, upper: period)
            case .unbounded:
                try execution.consumeWork(2)
                guard let start = model.vertices[edge.startVertexID]?.point,
                      let end = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference(
                        "Unbounded edge \(edge.id) requires both endpoint vertices."
                    )
                }
                let startParameter = try curve.parameterProjection(
                    of: start,
                    tolerance: tolerance, using: &execution
                ).parameter
                let endParameter = try curve.parameterProjection(
                    of: end,
                    tolerance: tolerance, using: &execution
                ).parameter
                result = try ScalarInterval(
                    lower: min(startParameter, endParameter),
                    upper: max(startParameter, endParameter)
                )
            }
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<ScalarInterval>.stride)
        try execution.checkpoint()
        return result
    }
}
