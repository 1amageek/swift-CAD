import CADCore

/// Whole original families consume the same source/DI/caller execution.
struct OriginalCoaxialSurfacePublicProducer {
    private typealias Field = OriginalPhysicalAngleScalarDomain
    private typealias Interval = ExactParameterInterval<Field.Value>
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution) throws -> OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>? {
        a.context = a.context.at(stage: .source)
        try a.checkpoint()
        let input = OriginalCoaxialSurfacePairInput(first: first, second: second)
        guard let pair = OriginalCoaxialSurfacePairSnapshotProvider.coneAndCylinder(input),
            case .analytic(.cone(_, _, let angle)) = pair.cone else { return nil }

        let binding = try source(input, angle: angle, options: options, tolerance: tolerance, using: &a)
        try a.admitSourceDepth(binding.sourceDepth)
        a.context = a.context.retaining(first: .init(source: binding), second: .init(source: binding))
        try a.checkpoint()
        return binding
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance, includeRelations: Bool = false,
        using a: inout OriginalQueryExecution,
        retained: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): Unit-Z coaxial original families
        // are published by ordinary/prepared SSI. Other axes/noncoaxial input
        // families still require complete source/DI coverage before success.
        let input = OriginalCoaxialSurfacePairInput(first: first, second: second)
        guard let pair = OriginalCoaxialSurfacePairSnapshotProvider.coneAndCylinder(input),
            case .analytic(.cone(_, _, let angle)) = pair.cone else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let limits = try limits(options: options, executionLimits: a.effectiveLimits)
            let binding: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>
            a.context = a.context.at(stage: .domain)
            if let retained {
                guard retained.original.original.first == first, retained.original.original.second == second else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                binding = retained
            } else { binding = try source(input, angle: angle, options: options, tolerance: tolerance, using: &a) }
            try a.admitSourceDepth(binding.sourceDepth)
            a.context = a.context.retaining(first: .init(source: binding), second: .init(source: binding))
            a.context = a.context.at(stage: .domain)
            try a.checkpoint(); try binding.require(limits.source)
            let field = binding.original.field
            let firstIntervals = try intervals(firstBox, field: field, using: &a)
            let secondIntervals = try intervals(secondBox, field: field, using: &a)
            a.context = a.context.at(stage: .relation)
            let relation = try OriginalCoaxialSurfaceSurfaceRelation.resolve(source: binding,
                firstIntervals: firstIntervals, secondIntervals: secondIntervals,
                maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults), limits: limits, using: &a)
            var count = 0
            for branch in relation.branches {
                try a.consumeWork(1)
                let next = count.addingReportingOverflow(branch.phase.intervalCount)
                guard !next.overflow, next.partialValue <= min(options.maximumSeedCount, a.effectiveLimits.maximumResults) else {
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
                    guard components.count < min(options.maximumSeedCount, a.effectiveLimits.maximumResults) else {
                        throw NativeExactRelationFailure.resultLimit
                    }
                    let component = try OriginalCoaxialSurfaceComponent(relation: relation, branch: branch,
                        interval: interval, using: &a)
                    components.append(.originalCoaxial(component))
                }
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalCoaxialSurfaceRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, executionLimits: OriginalQueryExecutionLimits) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: executionLimits.remainingSourceDepth),
            maximumTransportDepth: executionLimits.maximumTransportDepth,
            maximumCharts: min(min(executionLimits.maximumCharts, executionLimits.maximumSpans), options.maximumSubdivisionCells), maximumFamilies: min(2, executionLimits.maximumFamilies), maximumIdentityProofs: 0)
    }
    private func source(_ input: OriginalCoaxialSurfacePairInput, angle: Double, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution)
        throws -> OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot> {
        a.context = a.context.at(stage: .source)
        try a.checkpoint(); try options.validate(tolerance: tolerance)
        let field = try Field(originalRadians: angle, using: &a)
        return try DefaultOriginalSourceBindingIssuer(provider: OriginalCoaxialSurfacePairSnapshotProvider(field: field, tolerance: tolerance))
            .bind(input, limits: limits(options: options, executionLimits: a.effectiveLimits).source, using: &a)
    }
    private func intervals(_ box: SurfaceParameterBox?, field: Field, using a: inout OriginalQueryExecution) throws -> [[Interval]] {
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
