import CADCore
import CADGeometry
import CADIR
import CADModeling

extension CurveQueryEvaluator {
    public func resolveOriginalGeometry(_ reference: CurveOutputReference,
        in document: EvaluatedDocument, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ResolvedOriginalCurveGeometry {
        let cap = maximumAlgebraicDepth ?? 32
        let selected = try execution.makeContributionHandle(allocationPolicy: execution.effectiveAllocationPolicy,
            executionLimits: .init(maximumValueDepth: cap, maximumCoefficientDepth: cap,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
        return try execution.withContributionScope(selected) { execution in
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        try reference.validate()
        guard let node = document.document.designGraph.nodes[reference.featureID], !node.isSuppressed,
            let curves = document.curves[reference.featureID], curves.indices.contains(reference.curveIndex) else {
            throw FeatureEvaluationError.missingInput("Original curve output does not belong to a live current feature.")
        }
        let curve = curves[reference.curveIndex]
        guard curve.sourceFeatureID == reference.featureID else {
            throw FeatureEvaluationError.invalidGraph("Original curve output has foreign feature provenance.")
        }
        let original = try curve.validateOriginalGeometry(tolerance: queryTolerance, using: &execution)
        return ResolvedOriginalCurveGeometry(reference: reference, original: original)
            }
}

    public func knotOriginal(_ reference: CurveKnotReference, in document: EvaluatedDocument,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> Double {
        let original = try resolveOriginalGeometry(reference.curve, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try knotOriginal(reference, source: original,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
    }

    public func knotOriginal(_ reference: CurveKnotReference, source: ResolvedOriginalCurveGeometry,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1); try reference.validate()
        guard reference.curve == source.reference else {
            throw FeatureEvaluationError.invalidGraph("Original knot receipt belongs to another curve output.")
        }
        let spline = try nativeSpline(source.curve, remainingSourceDepth: remainingSourceDepth, using: &execution)
        guard spline.knots.indices.contains(reference.knotIndex) else {
            throw FeatureEvaluationError.missingInput("Original curve knot index could not be resolved.")
        }
        return spline.knots[reference.knotIndex]
    }

    public func spanOriginal(_ reference: CurveSpanReference, in document: EvaluatedDocument,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> CurveSpanQueryResult {
        let original = try resolveOriginalGeometry(reference.curve, in: document,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try spanOriginal(reference, source: original,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
    }

    public func spanOriginal(_ reference: CurveSpanReference, source: ResolvedOriginalCurveGeometry,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> CurveSpanQueryResult {
        try execution.consumeWork(1); try reference.validate()
        guard reference.curve == source.reference else {
            throw FeatureEvaluationError.invalidGraph("Original span receipt belongs to another curve output.")
        }
        let spline = try nativeSpline(source.curve, remainingSourceDepth: remainingSourceDepth, using: &execution)
        let upperIndex = spline.knots.count - spline.degree - 1
        guard spline.degree < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Original curve has no queryable knot spans.")
        }
        var ordinal = 0
        for index in spline.degree..<upperIndex {
            try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
            let lower = spline.knots[index], upper = spline.knots[index + 1]
            guard upper - lower > queryTolerance.distance else { continue }
            if ordinal == reference.spanIndex {
                return CurveSpanQueryResult(reference: reference, lowerParameter: lower, upperParameter: upper)
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Original curve span index could not be resolved.")
    }

    private func nativeSpline(_ curve: Curve3D, remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(1); try execution.admitSourceDepth(0)
        let source: Curve3D
        switch curve {
        case .bSpline(let spline): return spline
        case .rigidImage(let image): source = image.source
        case .affineImage(let image): source = image.source
        case .originalAffineWord(let image): source = image.source
        default:
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: queryTolerance,
                message: "Original knot/span selection requires a parameter-preserving B-spline source.")
        }
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original spline query exhausted source depth.")
        }
        return try execution.withSourceDepthOffset(1) { execution in
            try nativeSpline(source, remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
        }
    }
}
