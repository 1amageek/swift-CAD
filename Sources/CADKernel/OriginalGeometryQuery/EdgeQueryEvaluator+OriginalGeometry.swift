import CADCore
import CADGeometry
import CADIR
import CADTopology

extension EdgeQueryEvaluator {
    public func resolveOriginalGeometry(_ reference: EdgeReference, in document: EvaluatedDocument,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ResolvedOriginalEdgeGeometry {
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        guard (0...32).contains(maximumSubdivisionDepth), remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original edge query has invalid depth limits.")
        }
        let topology = try document.originalTopologyReference(for: reference.subshape,
            tolerance: queryTolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        guard case .edge(let id) = topology else {
            throw FeatureEvaluationError.missingInput("Original stable selection is not an edge.")
        }
        let value = try prepareOriginalEdge(id, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return ResolvedOriginalEdgeGeometry(reference: reference, edgeID: id, curveID: value.curveID,
            curve: value.curve, startParameter: value.start, endParameter: value.end)
    }

    /// Resolves a generated edge against its issuing current feature/index, without a historical signature.
    public func resolveCurrentOriginalGeometry(_ subshapeID: SubshapeID, in document: EvaluatedDocument,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ResolvedCurrentOriginalEdgeGeometry {
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        guard subshapeID.isValid, (0...32).contains(maximumSubdivisionDepth), remainingSourceDepth >= 0,
            let node = document.document.designGraph.nodes[subshapeID.featureID], !node.isSuppressed,
            document.lineage[subshapeID]?.output == subshapeID,
            case .edge(let id) = try document.subshapes.reference(for: subshapeID) else {
            throw FeatureEvaluationError.missingInput("Original generated edge has no current feature/index binding.")
        }
        for _ in subshapeID.role.utf8 { try execution.consumeWork(1) }
        let value = try prepareOriginalEdge(id, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return ResolvedCurrentOriginalEdgeGeometry(subshapeID: subshapeID, edgeID: id, curveID: value.curveID,
            curve: value.curve, startParameter: value.start, endParameter: value.end)
    }

    /// Composes an already source-admitted BRep edge without fabricating lineage.
    package func originalGeometry(of id: EdgeID, in document: EvaluatedDocument,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws
        -> (curveID: CurveID, curve: Curve3D, startParameter: Double, endParameter: Double) {
        let value = try prepareOriginalEdge(id, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return (value.curveID, value.curve, value.start, value.end)
    }

    private func prepareOriginalEdge(_ id: EdgeID, in document: EvaluatedDocument,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws
        -> (curveID: CurveID, curve: Curve3D, start: Double, end: Double) {
        try execution.consumeWork(1)
        guard let edge = document.brep.edges[id],
            let curve = document.brep.geometry.curves[edge.curveID],
            let first = document.brep.vertices[edge.startVertexID],
            let last = document.brep.vertices[edge.endVertexID] else {
            throw FeatureEvaluationError.missingInput("Original edge source or vertices are absent.")
        }
        try execution.consumeWork(1); try first.point.validate(); try last.point.validate()
        try curve.validateOriginalSource(tolerance: queryTolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let start: Double, end: Double
        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: id, tolerance: queryTolerance,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32,
                maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
            start = trim.startParameter; end = trim.endParameter
        } else if case .closed(let lower, let upper) = try originalDomain(curve,
            remainingSourceDepth: remainingSourceDepth, using: &execution) {
            start = lower; end = upper
        } else {
            switch curve {
            case .line(let line):
                start = try originalLinearParameter(first.point, origin: line.origin,
                    direction: line.direction, using: &execution)
                end = try originalLinearParameter(last.point, origin: line.origin,
                    direction: line.direction, using: &execution)
            case .analytic(.line(let origin, let direction)):
                start = try originalLinearParameter(first.point, origin: origin,
                    direction: direction, using: &execution)
                end = try originalLinearParameter(last.point, origin: origin,
                    direction: direction, using: &execution)
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Untrimmed original image-linear
                // endpoints need a retained exact native projection law. This bounded
                // public query cannot call the legacy inverse matrix/dot preparation.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: queryTolerance,
                    message: "Untrimmed original edge requires its retained native endpoint law.")
            }
        }
        guard start.isFinite, end.isFinite else { throw GeometryError.invalidDistance(end - start) }
        return (edge.curveID, curve, start, end)
    }

    private func originalDomain(_ source: Curve3D, remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> ParameterDomain {
        var curve = source, remaining = remainingSourceDepth
        while true {
            try execution.consumeWork(1)
            guard remaining >= 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original edge native domain exhausted source depth.")
            }
            switch curve {
            case .rigidImage(let image): curve = image.source; remaining -= 1
            case .affineImage(let image): curve = image.source; remaining -= 1
            case .originalAffineWord(let image): curve = image.source; remaining -= 1
            default: return curve.parameterDomain
            }
        }
    }

    private func originalLinearParameter(_ point: Point3D, origin: Point3D, direction: Vector3D, using execution: inout OriginalQueryExecution) throws -> Double {
        var value = ExactRationalCoefficient.zero
        for axis in 0..<3 {
            let coordinate = axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
            let center = axis == 0 ? origin.x : (axis == 1 ? origin.y : origin.z)
            let coefficient = axis == 0 ? direction.x : (axis == 1 ? direction.y : direction.z)
            let difference = try ExactRationalCoefficient.originalDouble(coordinate, usage: &execution)
                .subtracting(.originalDouble(center, usage: &execution), usage: &execution)
            value = try value.adding(difference.multiplied(by: .originalDouble(coefficient, usage: &execution),
                usage: &execution), usage: &execution)
        }
        let bounds = try value.outwardInterval(usage: &execution)
        if bounds.isFinite {
            for index in 0..<2 {
                let candidate = index == 0 ? bounds.lower : bounds.upper
                if try value.subtracting(.originalDouble(candidate, usage: &execution), usage: &execution).isZero {
                    return candidate
                }
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Nonrepresentable original projected
        // native stations require a retained endpoint carrier for edge intervals.
        // The public original query never promotes a rounded dot to source authority.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: queryTolerance,
            message: "Original linear edge endpoint is not a represented native station.")
    }
}
