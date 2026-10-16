import CADCore

/// Publishes retained original families under the shared original execution.
struct OriginalBoundedSphereConeSurfacePublicProducer {
    typealias Source = OriginalBoundedSphereConeSurfaceSnapshot
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceRelation? {
        a.context = a.context.at(stage: .source)
        try a.checkpoint()
        let input = OriginalBoundedSphereConeSurfaceInput(first: first, second: second)
        guard OriginalBoundedSphereConeSurfaceSnapshotProvider.pair(input) != nil else { return nil }

        guard let bound = try source(input, options: options, tolerance: tolerance, using: &a) else { return nil }
        try a.admitSourceDepth(bound.sourceDepth)
        a.context = a.context.retaining(first: .init(source: bound), second: .init(source: bound))
        a.context = a.context.at(stage: .relation)
        let prepared = try OriginalBoundedSphereConeSurfaceRelation.prepare(source: bound,
            maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults), tolerance: tolerance, limits: limits(options: options, executionLimits: a.effectiveLimits), using: &a)
        try a.checkpoint()
        return prepared
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil,
        secondBox: SurfaceParameterBox? = nil, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, includeRelations: Bool = false, using a: inout OriginalQueryExecution,
        retained: OriginalBoundedSphereConeSurfaceRelation? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): This aligned single-arc parent SSI publishes
        // the complete full pair, selected exclusions and source-proved finite
        // arcs. Other parent pairs and finite classes require their source owner.
        let input = OriginalBoundedSphereConeSurfaceInput(first: first, second: second)
        guard OriginalBoundedSphereConeSurfaceSnapshotProvider.pair(input) != nil else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let bound: OriginalSourceBinding<Source>
            a.context = a.context.at(stage: .domain)
            if let retained {
                guard retained.source.original.original.first == first, retained.source.original.original.second == second else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                bound = retained.source
            } else {
                guard let issued=try source(input,options:options,tolerance:tolerance,using: &a) else { return nil }
                bound=issued
            }
            try a.admitSourceDepth(bound.sourceDepth)
            a.context = a.context.retaining(first: .init(source: bound), second: .init(source: bound))
            a.context = a.context.at(stage: .relation)
            let relation = try OriginalBoundedSphereConeSurfaceRelation.resolve(source: bound, firstBox: firstBox,
                secondBox: secondBox, maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults), tolerance: tolerance,
                limits: limits(options: options, executionLimits: a.effectiveLimits), prepared: retained, using: &a)
            a.context = a.context.at(stage: .publication)
            let count = relation.isEmpty ? 0 : 1
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []; components.reserveCapacity(count)
            if !relation.isEmpty {
                components.append(.originalBoundedSphereCone(.init(relation: relation)))
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalBoundedSphereConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, executionLimits: OriginalQueryExecutionLimits) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: executionLimits.remainingSourceDepth),
            maximumTransportDepth: executionLimits.maximumTransportDepth,
            maximumCharts: min(min(executionLimits.maximumCharts, executionLimits.maximumSpans), options.maximumSubdivisionCells), maximumFamilies: min(2, executionLimits.maximumFamilies), maximumIdentityProofs: 0)
    }
    private func source(_ input: OriginalBoundedSphereConeSurfaceInput, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution)
        throws -> OriginalSourceBinding<Source>? {
        a.context = a.context.at(stage: .source)
        guard let pair=OriginalBoundedSphereConeSurfaceSnapshotProvider.pair(input),
            case .analytic(.cone(_,_,let angle))=pair.cone else { return nil }
        let physical=try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
        guard try OriginalBoundedSphereConeSurfaceSnapshotProvider.admitsSingleArc(input,physical:physical,using:&a) else { return nil }
        return try DefaultOriginalSourceBindingIssuer(provider: OriginalBoundedSphereConeSurfaceSnapshotProvider(
            physical: physical, maximumExtensionLevel: a.effectiveLimits.maximumValueDepth, tolerance: tolerance))
            .bind(input, limits: limits(options: options, executionLimits: a.effectiveLimits).source, using: &a)
    }
}
