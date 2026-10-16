import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADModeling

extension SurfaceQueryEvaluator {
    public func resolveOriginalGeometry(_ reference: SurfaceReference,
        in document: some SurfaceQueryModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ResolvedOriginalSurfaceGeometry {
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        guard (0...32).contains(maximumSubdivisionDepth), remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original surface query has invalid depth limits.")
        }
        let topology = try document.originalTopologyReference(for: reference.subshape,
            tolerance: queryTolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        guard case .face(let id) = topology,
            let face = document.brep.faces[id], let surface = document.brep.geometry.surfaces[face.surfaceID] else {
            throw FeatureEvaluationError.missingInput("Original surface query does not resolve to a live face support.")
        }
        try surface.validate(tolerance: queryTolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return ResolvedOriginalSurfaceGeometry(reference: reference, faceID: id, surfaceID: face.surfaceID, surface: surface)
    }

    public func knotOriginal(_ reference: SurfaceKnotReference, in document: some SurfaceQueryModel,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> Double {
        let source = try resolveOriginalGeometry(reference.surface, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try knotOriginal(reference, source: source, remainingSourceDepth: remainingSourceDepth, using: &execution)
    }

    public func knotOriginal(_ reference: SurfaceKnotReference, source: ResolvedOriginalSurfaceGeometry, remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard reference.knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface knot reference index must not be negative.")
        }
        try requireOriginalReference(reference.surface, source: source, using: &execution)
        let spline = try nativeSpline(source.surface, remainingSourceDepth: remainingSourceDepth, using: &execution)
        let knots = reference.direction == .u ? spline.uKnots : spline.vKnots
        guard knots.indices.contains(reference.knotIndex) else {
            throw FeatureEvaluationError.missingInput("Original surface knot index could not be resolved.")
        }
        return knots[reference.knotIndex]
    }

    public func spanOriginal(_ reference: SurfaceSpanReference, in document: some SurfaceQueryModel,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> SurfaceSpanQueryResult {
        let source = try resolveOriginalGeometry(reference.surface, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try spanOriginal(reference, source: source, remainingSourceDepth: remainingSourceDepth, using: &execution)
    }

    public func spanOriginal(_ reference: SurfaceSpanReference, source: ResolvedOriginalSurfaceGeometry, remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceSpanQueryResult {
        try execution.consumeWork(1)
        guard reference.spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface span reference index must not be negative.")
        }
        try requireOriginalReference(reference.surface, source: source, using: &execution)
        let spline = try nativeSpline(source.surface, remainingSourceDepth: remainingSourceDepth, using: &execution)
        let knots = reference.direction == .u ? spline.uKnots : spline.vKnots
        let degree = reference.direction == .u ? spline.uDegree : spline.vDegree
        let upperIndex = knots.count - degree - 1
        guard degree < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Original surface has no queryable knot spans.")
        }
        var ordinal = 0
        for index in degree..<upperIndex {
            try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
            let lower = knots[index], upper = knots[index + 1]
            guard upper - lower > queryTolerance.distance else { continue }
            if ordinal == reference.spanIndex {
                return SurfaceSpanQueryResult(reference: reference, lowerParameter: lower, upperParameter: upper)
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Original surface span index could not be resolved.")
    }

    private func requireOriginalReference(_ reference: SurfaceReference,
        source: ResolvedOriginalSurfaceGeometry, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for _ in reference.subshape.subshapeID.role.utf8 { try execution.consumeWork(1) }
        for _ in source.reference.subshape.subshapeID.role.utf8 { try execution.consumeWork(1) }
        try SubshapeGeometrySignatureBuilder.chargeStoredSignature(reference.subshape.geometrySignature, using: &execution)
        try SubshapeGeometrySignatureBuilder.chargeStoredSignature(source.reference.subshape.geometrySignature, using: &execution)
        guard reference == source.reference else {
            throw FeatureEvaluationError.invalidGraph("Original parameter receipt belongs to another surface reference.")
        }
    }

    private func nativeSpline(_ surface: Surface3D, remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.consumeWork(1); try execution.admitSourceDepth(0)
        let source: Surface3D
        switch surface {
        case .bSpline(let spline): return spline
        case .procedural(.originalAffineWord(let image)): source = image.source
        case .procedural(.offset(let image)): source = image.source
        default:
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: queryTolerance,
                message: "Original knot/span query requires a parameter-preserving B-spline support.")
        }
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original surface knot traversal exhausted source depth.")
        }
        return try execution.withSourceDepthOffset(1) { execution in
            try nativeSpline(source, remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
        }
    }

}
