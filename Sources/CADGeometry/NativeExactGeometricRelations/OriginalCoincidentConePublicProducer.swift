import CADCore

/// Publishes retained original families under the shared original execution.
struct OriginalCoincidentConePublicProducer {
    typealias Source = OriginalCoincidentConeSnapshot
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution) throws -> OriginalCoincidentConeRelation? {
        a.context = a.context.at(stage: .source)
        try a.checkpoint()
        let input = OriginalCoincidentConeInput(first: first, second: second)
        guard OriginalCoincidentConeSnapshotProvider.angle(input) != nil else { return nil }
        let bound = try source(input, options: options, tolerance: tolerance, using: &a)
        try a.admitSourceDepth(bound.sourceDepth)
        a.context = a.context.retaining(first: .init(source: bound), second: .init(source: bound))
        a.context = a.context.at(stage: .relation)
        let prepared = try OriginalCoincidentConeRelation.resolve(source: bound, firstBox: nil, secondBox: nil,
            maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults), limits: limits(options: options, executionLimits: a.effectiveLimits), using: &a)
        try a.checkpoint()
        return prepared
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil,
        secondBox: SurfaceParameterBox? = nil, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, includeRelations: Bool = false, using a: inout OriginalQueryExecution,
        retained: OriginalCoincidentConeRelation? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        let input = OriginalCoincidentConeInput(first: first, second: second)
        guard OriginalCoincidentConeSnapshotProvider.angle(input) != nil else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let bound: OriginalSourceBinding<Source>
            a.context = a.context.at(stage: .domain)
            if let retained {
                guard retained.source.original.original.first == first, retained.source.original.original.second == second else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                bound = retained.source
            } else { bound = try source(input, options: options, tolerance: tolerance, using: &a) }
            try a.admitSourceDepth(bound.sourceDepth)
            a.context = a.context.retaining(first: .init(source: bound), second: .init(source: bound))
            a.context = a.context.at(stage: .relation)
            let relation = try OriginalCoincidentConeRelation.resolve(source: bound, firstBox: firstBox,
                secondBox: secondBox, maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults),
                limits: limits(options: options, executionLimits: a.effectiveLimits), prepared: retained, using: &a)
            a.context = a.context.at(stage: .publication)
            let count = relation.pieces.count
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []; components.reserveCapacity(count)
            for i in relation.pieces.indices {
                try a.consumeWork(1)
                components.append(.originalCoincidentCone(.init(relation:relation,ordinal:i)))
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalCoincidentConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, executionLimits: OriginalQueryExecutionLimits) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: executionLimits.remainingSourceDepth),
            maximumTransportDepth: executionLimits.maximumTransportDepth,
            maximumCharts: min(min(executionLimits.maximumCharts, executionLimits.maximumSpans), options.maximumSubdivisionCells), maximumFamilies: min(2, executionLimits.maximumFamilies), maximumIdentityProofs: 2)
    }
    private func source(_ input: OriginalCoincidentConeInput, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution)
        throws -> OriginalSourceBinding<Source> {
        a.context = a.context.at(stage: .source)
        guard let angle=OriginalCoincidentConeSnapshotProvider.angle(input) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        let field=try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
        return try DefaultOriginalSourceBindingIssuer(provider:OriginalCoincidentConeSnapshotProvider(field:field,tolerance:tolerance))
            .bind(input,limits:limits(options:options,executionLimits: a.effectiveLimits).source,using:&a)
    }
}
