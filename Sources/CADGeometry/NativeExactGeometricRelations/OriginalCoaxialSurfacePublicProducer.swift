import CADCore

/// Whole original families consume the same source/DI/caller allowance.
struct OriginalCoaxialSurfacePublicProducer {
    private typealias Field = OriginalPhysicalAngleScalarDomain
    private typealias Admission = NativeExactPublicAdmission<NativeSurfaceSurfacePointAllowance>
    private typealias Interval = ExactParameterInterval<Field.Value>
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>? {
        let input = OriginalCoaxialSurfacePairInput(first: first, second: second)
        guard let pair = OriginalCoaxialSurfacePairSnapshotProvider.coneAndCylinder(input),
            case .analytic(.cone(_, _, let angle)) = pair.cone else { return nil }
        let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
        var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
        return try source(input, angle: angle, options: options, tolerance: tolerance, admission: admission, using: &a)
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance, includeRelations: Bool = false,
        admission: SurfaceSurfaceQueryAdmission = .legacy,
        retained: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Unit-Z coaxial original families
        // are published by ordinary/prepared SSI. Other axes/noncoaxial input
        // families still require complete source/DI coverage before success.
        let input = OriginalCoaxialSurfacePairInput(first: first, second: second)
        guard let pair = OriginalCoaxialSurfacePairSnapshotProvider.coneAndCylinder(input),
            case .analytic(.cone(_, _, let angle)) = pair.cone else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
            var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
            let limits = try limits(options: options, admission: admission)
            let binding: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>
            if let retained {
                guard retained.original.original.first == first, retained.original.original.second == second else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                binding = retained
            } else { binding = try source(input, angle: angle, options: options, tolerance: tolerance, admission: admission, using: &a) }
            try a.checkpoint(); try binding.require(limits.source)
            let field = binding.original.field
            let firstIntervals = try intervals(firstBox, field: field, using: &a)
            let secondIntervals = try intervals(secondBox, field: field, using: &a)
            let relation = try OriginalCoaxialSurfaceSurfaceRelation.resolve(source: binding,
                firstIntervals: firstIntervals, secondIntervals: secondIntervals,
                maximumComponents: options.maximumSeedCount, limits: limits, using: &a)
            var count = 0
            for branch in relation.branches {
                try a.consumeWork(1)
                let next = count.addingReportingOverflow(branch.phase.intervalCount)
                guard !next.overflow, next.partialValue <= options.maximumSeedCount else {
                    throw NativeExactRelationFailure.resultLimit
                }
                count = next.partialValue
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []
            // Admit the complete output before reserving; append growth would
            // otherwise allocate four elements for a three-component selection.
            components.reserveCapacity(count)
            for branch in relation.branches.indices {
                for interval in relation.branches[branch].phase.intervals.indices {
                    try a.consumeWork(1)
                    guard components.count < options.maximumSeedCount else {
                        throw NativeExactRelationFailure.resultLimit
                    }
                    let component = try OriginalCoaxialSurfaceComponent(relation: relation, branch: branch,
                        interval: interval, using: &a)
                    components.append(.originalCoaxial(component))
                }
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalCoaxialSurfaceRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: min(options.maximumSubdivisionDepth, admission.remainingSourceDepth)),
            maximumTransportDepth: admission.maximumAlgebraicDepth ?? 32,
            maximumCharts: min(admission.maximumSpanCount, options.maximumSubdivisionCells), maximumFamilies: 2, maximumIdentityProofs: 0)
    }
    private func source(_ input: OriginalCoaxialSurfacePairInput, angle: Double, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission, using a: inout Admission)
        throws -> OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot> {
        try a.checkpoint(); try options.validate(tolerance: tolerance)
        let field = try Field(originalRadians: angle, using: &a)
        return try DefaultOriginalSourceBindingIssuer(provider: OriginalCoaxialSurfacePairSnapshotProvider(field: field, tolerance: tolerance))
            .bind(input, limits: limits(options: options, admission: admission).source, using: &a)
    }
    private func intervals(_ box: SurfaceParameterBox?, field: Field, using a: inout Admission) throws -> [[Interval]] {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Interval].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Interval.self))
        let depth = try ExactScalarDepth(value: 0, coefficient: 0)
        if let box {
            return [[try .checked(field: field, lower: .finite(field.binary64(exactly: box.u.lower, using: &a)),
                upper: .finite(field.binary64(exactly: box.u.upper, using: &a)), depth: depth, using: &a)],
                [try .checked(field: field, lower: .finite(field.binary64(exactly: box.v.lower, using: &a)),
                upper: .finite(field.binary64(exactly: box.v.upper, using: &a)), depth: depth, using: &a)]]
        }
        let whole = try Interval.checked(field: field, lower: .negativeInfinity, upper: .positiveInfinity, depth: depth, using: &a)
        return [[whole], [whole]]
    }
}
