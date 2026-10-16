import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

extension SurfaceQueryEvaluator {
    public func trimOriginal(_ reference: SurfaceTrimReference,
        in document: some SurfaceQueryModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ResolvedOriginalSurfaceTrim {
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        guard reference.loopIndex >= 0, reference.edgeIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Original trim indices must not be negative.")
        }
        let source = try resolveOriginalGeometry(reference.surface, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        guard let face = document.brep.faces[source.faceID], face.loops.indices.contains(reference.loopIndex) else {
            throw FeatureEvaluationError.missingInput("Original trim loop does not belong to the queried current face.")
        }
        try execution.consumeWork(1)
        let loopID = face.loops[reference.loopIndex]
        guard let loop = document.brep.loops[loopID], loop.coedges.indices.contains(reference.edgeIndex) else {
            throw FeatureEvaluationError.missingInput("Original trim coedge does not belong to the queried current loop.")
        }
        try execution.consumeWork(1)
        let coedge = loop.coedges[reference.edgeIndex]
        guard let edge = document.brep.edges[coedge.edgeID],
            document.brep.geometry.curves[edge.curveID] != nil,
            document.brep.vertices[edge.startVertexID] != nil,
            document.brep.vertices[edge.endVertexID] != nil else {
            throw FeatureEvaluationError.missingInput("Original trim references absent current edge geometry.")
        }
        guard let pcurve = coedge.surfaceParameterCurve else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded selected-trim measurement requires an original
            // coedge chart. The legacy endpoint projection/seventeen-sample polyline is not that source;
            // missing-chart reconstruction needs a same-ledger original correspondence producer.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: queryTolerance,
                message: "Original trim selection requires the current producer-retained coedge pcurve.")
        }
        try pcurve.validate(on: source.surface, tolerance: queryTolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return ResolvedOriginalSurfaceTrim(reference: reference, source: source,
            loopID: loopID, edgeID: edge.id, curveID: edge.curveID,
            orientation: coedge.orientation, parameterCurve: pcurve)
    }

    public func trimSpanOriginal(_ reference: SurfaceTrimSpanReference,
        source: ResolvedOriginalSurfaceTrim, using execution: inout OriginalQueryExecution) throws -> OriginalSurfaceTrimSpanGeometry {
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        guard reference.spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Original trim span index must not be negative.")
        }
        for _ in reference.trim.surface.subshape.subshapeID.role.utf8 { try execution.consumeWork(1) }
        for _ in source.reference.surface.subshape.subshapeID.role.utf8 { try execution.consumeWork(1) }
        try SubshapeGeometrySignatureBuilder.chargeStoredSignature(reference.trim.surface.subshape.geometrySignature, using: &execution)
        try SubshapeGeometrySignatureBuilder.chargeStoredSignature(source.reference.surface.subshape.geometrySignature, using: &execution)
        guard reference.trim == source.reference, case .bSpline(let curve) = source.parameterCurve else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: queryTolerance,
                message: "Original trim span requires the matching original B-spline chart receipt.")
        }
        let upperIndex = curve.knots.count - curve.degree - 1
        guard curve.degree < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Original trim chart has no queryable knot spans.")
        }
        var ordinal = 0
        for index in curve.degree..<upperIndex {
            try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
            let first = curve.knots[index], last = curve.knots[index + 1]
            guard last - first > queryTolerance.distance else { continue }
            if ordinal == reference.spanIndex {
                return OriginalSurfaceTrimSpanGeometry(reference: reference, trim: source,
                    lowerParameter: first, upperParameter: last, nativeDomain: curve.domain)
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Original trim span index could not be resolved.")
    }
}
