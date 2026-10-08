import CADCore

/// Migrates the existing single-span Native SSI family under its original caller allowance.
struct NativeExactPublicSurfaceSurfaceProducer {
    func resolve(first: Surface3D, second: Surface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        includeRelations: Bool = false, admission: SurfaceSurfaceQueryAdmission = .legacy
    ) throws -> SurfaceSurfaceIntersectionResult? {
        guard case .bSpline(let source) = first, case .bSpline(let target) = second,
            !source.isUPeriodic, !source.isVPeriodic, !target.isUPeriodic, !target.isVPeriodic,
            source.uDegree >= 0, source.uDegree < Int.max - 1,
            source.vDegree >= 0, source.vDegree < Int.max - 1,
            target.uDegree >= 0, target.uDegree < Int.max - 1,
            target.vDegree >= 0, target.vDegree < Int.max - 1,
            source.uControlPointCount == source.uDegree + 1,
            source.vControlPointCount == source.vDegree + 1,
            target.uControlPointCount == target.uDegree + 1,
            target.vControlPointCount == target.vDegree + 1 else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            var usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
            try usage.consumeExactWork(1)
            guard admission.remainingSourceDepth > 0, admission.maximumSpanCount > 0 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Native exact SSI preparation exhausted original source or span admission.")
            }
            try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
            try target.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
            try requireSingleSpan(source.uKnots, degree: source.uDegree, tolerance: tolerance, using: &usage)
            try requireSingleSpan(source.vKnots, degree: source.vDegree, tolerance: tolerance, using: &usage)
            try requireSingleSpan(target.uKnots, degree: target.uDegree, tolerance: tolerance, using: &usage)
            try requireSingleSpan(target.vKnots, degree: target.vDegree, tolerance: tolerance, using: &usage)
            var exactAdmission = NativeExactPublicAdmission(usage: usage,
                maximumDepth: usage.maximumAlgebraicDepth)
            let exact = try DefaultNativeExactGeometricRelationResolver().exactGeometricRelation(
                first: source, second: target, firstDomain: firstBox, secondDomain: secondBox,
                tolerance: tolerance, maximumPolynomialDegree: Int.max, maximumExtensionLevel: Int.max,
                limits: NativeExactPublicLimits.unboundedStructure(), using: &exactAdmission)
            let result = try NativeExactSurfaceSurfacePublisher.publish(exact,
                options: options, using: &exactAdmission)
            guard includeRelations || !exact.hasPositiveDimensionalSolutions else {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "The complete original Native surface product contains positive-dimensional parameter solutions.")
            }
            try exactAdmission.checkpoint()
            return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }

    private func requireSingleSpan(_ knots: [Double], degree: Int, tolerance: ModelingTolerance,
        using usage: inout NativeSurfaceSurfacePointAllowance) throws {
        try usage.consumeExactWork(1)
        guard degree >= 0, degree < Int.max / 2, knots.count == 2 * (degree + 1),
            knots.indices.contains(degree + 1) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Native exact SSI requires its complete original single-span knot source.")
        }
        let lower = knots[degree], upper = knots[degree + 1]
        guard lower.isFinite, upper.isFinite, lower < upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Native exact SSI requires a finite positive original knot span.")
        }
    }
}
