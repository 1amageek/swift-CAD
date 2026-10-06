import CADCore

/// Retains an actual original boundary law without tensor decomposition or degree conversion.
struct OriginalSurfaceBoundarySourceIssuer {
    func boundary<B: RationalAlgebraAdmitting>(of surface: Surface3D, at boundary: SurfaceParameterBoundary,
        maximumDepth: Int, maximumSpanCount: Int, tolerance: ModelingTolerance, usage: inout B) throws -> OriginalCurveRootSpan3D {
        try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
        if case .procedural(.originalCoons(let original)) = surface { return original.boundarySource(boundary) }
        if case .procedural(.originalBoundaryCorrected(let original)) = surface { return original.boundarySource(boundary) }
        if case .procedural(.originalPlaneDerivative(let original)) = surface { return original.boundarySource(boundary) }
        guard case .bSpline(let original) = surface else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Loft's original mixed-source
            // side contact path requires a structural boundary producer for
            // other surface families before they can nominate a shared seam.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original shared-side admission has no boundary-source receipt for this family.")
        }
        let fixedU = boundary == .uLower || boundary == .uUpper
        let upper = boundary == .uUpper || boundary == .vUpper
        let fixedDegree = fixedU ? original.uDegree : original.vDegree
        let fixedKnots = fixedU ? original.uKnots : original.vKnots
        let selected = upper ? fixedKnots.suffix(fixedDegree + 1) : fixedKnots.prefix(fixedDegree + 1)
        try usage.consumeExactWork(selected.count)
        guard let parameter = selected.first, selected.allSatisfy({ $0 == parameter }) else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original shared spline boundary requires its exact clamped boundary authority.")
        }
        let points: [Point3D], weights: [Double]
        if fixedU {
            let count = original.controlPoints.count
            try RationalAlgebraStorage.retain(count, of: Point3D.self, usage: &usage)
            try RationalAlgebraStorage.retain(count, of: Double.self, usage: &usage)
            try usage.consumeExactWork(rationalAlgebraCount(count, 2, multiply: true))
            points = original.controlPoints.map { upper ? $0[$0.count - 1] : $0[0] }
            weights = original.weights.map { upper ? $0[$0.count - 1] : $0[0] }
        } else {
            points = upper ? original.controlPoints[original.controlPoints.count - 1] : original.controlPoints[0]
            weights = upper ? original.weights[original.weights.count - 1] : original.weights[0]
        }
        let degree = fixedU ? original.vDegree : original.uDegree
        let knots = fixedU ? original.vKnots : original.uKnots
        let curve = BSplineCurve3D(degree: degree, knots: knots, controlPoints: points, weights: weights)
        return try OriginalCurveRootSpan3D(source: .bSpline(curve), start: .authored(knots[degree]),
            end: .authored(knots[points.count]), maximumParameterWidth: tolerance.relative,
            maximumSubdivisionDepth: maximumDepth, tolerance: tolerance,
            storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
            maximumSpanCount: maximumSpanCount, remainingSourceDepth: 0)
    }
}
