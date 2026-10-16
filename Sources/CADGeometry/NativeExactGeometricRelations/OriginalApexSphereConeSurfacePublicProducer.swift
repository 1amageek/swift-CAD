import CADCore

/// Publishes retained original families under the shared original execution.
struct OriginalApexSphereConeSurfacePublicProducer {
    typealias Source = OriginalApexSphereConeSurfaceSnapshot
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution) throws -> OriginalApexSphereConeSurfaceRelation? {
        a.context = a.context.at(stage: .source)
        try a.checkpoint()
        let input = OriginalApexSphereConeSurfaceInput(first: first, second: second)
        guard OriginalApexSphereConeSurfaceSnapshotProvider.pair(input) != nil else { return nil }
        let bound = try source(input, options: options, tolerance: tolerance, using: &a)
        try a.admitSourceDepth(bound.sourceDepth)
        a.context = a.context.retaining(first: .init(source: bound), second: .init(source: bound))
        a.context = a.context.at(stage: .relation)
        let prepared = try OriginalApexSphereConeSurfaceRelation.resolve(source: bound, firstBox: nil, secondBox: nil,
            maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults), limits: limits(options: options, executionLimits: a.effectiveLimits), using: &a)
        try a.checkpoint()
        return prepared
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil,
        secondBox: SurfaceParameterBox? = nil, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, includeRelations: Bool = false, using a: inout OriginalQueryExecution,
        retained: OriginalApexSphereConeSurfaceRelation? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): This fixed full parent SSI publishes
        // the complete full pair and selected exclusions. Other parent pairs and
        // nonempty finite UV clipping need their complete source/refinement owner.
        let input = OriginalApexSphereConeSurfaceInput(first: first, second: second)
        guard OriginalApexSphereConeSurfaceSnapshotProvider.pair(input) != nil else { return nil }
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
            let relation = try OriginalApexSphereConeSurfaceRelation.resolve(source: bound, firstBox: firstBox,
                secondBox: secondBox, maximumComponents: min(options.maximumSeedCount, a.effectiveLimits.maximumResults),
                limits: limits(options: options, executionLimits: a.effectiveLimits), prepared: retained, using: &a)
            a.context = a.context.at(stage: .publication)
            let count = relation.isEmpty ? 0 : 1
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []; components.reserveCapacity(count)
            if !relation.isEmpty {
                components.append(.originalApexSphereCone(.init(relation: relation)))
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalApexSphereConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, executionLimits: OriginalQueryExecutionLimits) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: executionLimits.remainingSourceDepth),
            maximumTransportDepth: executionLimits.maximumTransportDepth,
            maximumCharts: min(min(executionLimits.maximumCharts, executionLimits.maximumSpans), options.maximumSubdivisionCells), maximumFamilies: min(3, executionLimits.maximumFamilies), maximumIdentityProofs: 0)
    }
    private func source(_ input: OriginalApexSphereConeSurfaceInput, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution)
        throws -> OriginalSourceBinding<Source> {
        a.context = a.context.at(stage: .source)
        guard let pair=OriginalApexSphereConeSurfaceSnapshotProvider.pair(input),
            case .analytic(.cone(_,_,let angle))=pair.cone else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        let physical = try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
        return try DefaultOriginalSourceBindingIssuer(provider: OriginalApexSphereConeSurfaceSnapshotProvider(
            physical: physical, maximumExtensionLevel: a.effectiveLimits.maximumValueDepth, tolerance: tolerance))
            .bind(input, limits: limits(options: options, executionLimits: a.effectiveLimits).source, using: &a)
    }
}
