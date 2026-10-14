import CADCore

/// Publishes retained original families under the existing SSI caller allowance.
struct OriginalApexSphereConeSurfacePublicProducer {
    private typealias Admission = NativeExactPublicAdmission<NativeSurfaceSurfacePointAllowance>
    typealias Source = OriginalApexSphereConeSurfaceSnapshot
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalApexSphereConeSurfaceRelation? {
        let input = OriginalApexSphereConeSurfaceInput(first: first, second: second)
        guard OriginalApexSphereConeSurfaceSnapshotProvider.pair(input) != nil else { return nil }
        let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
        var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
        let bound = try source(input, options: options, tolerance: tolerance, admission: admission, using: &a)
        return try OriginalApexSphereConeSurfaceRelation.resolve(source: bound, firstBox: nil, secondBox: nil,
            maximumComponents: options.maximumSeedCount, limits: limits(options: options, admission: admission), using: &a)
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil,
        secondBox: SurfaceParameterBox? = nil, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, includeRelations: Bool = false, admission: SurfaceSurfaceQueryAdmission = .legacy,
        retained: OriginalApexSphereConeSurfaceRelation? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This fixed full parent SSI publishes
        // the complete full pair and selected exclusions. Other parent pairs and
        // nonempty finite UV clipping need their complete source/refinement owner.
        let input = OriginalApexSphereConeSurfaceInput(first: first, second: second)
        guard OriginalApexSphereConeSurfaceSnapshotProvider.pair(input) != nil else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
            var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
            let bound: OriginalSourceBinding<Source>
            if let retained {
                guard retained.source.original.original.first == first, retained.source.original.original.second == second else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                bound = retained.source
            } else { bound = try source(input, options: options, tolerance: tolerance, admission: admission, using: &a) }
            let relation = try OriginalApexSphereConeSurfaceRelation.resolve(source: bound, firstBox: firstBox,
                secondBox: secondBox, maximumComponents: options.maximumSeedCount,
                limits: limits(options: options, admission: admission), prepared: retained, using: &a)
            let count = relation.isEmpty ? 0 : 1
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []; components.reserveCapacity(count)
            if !relation.isEmpty {
                components.append(.originalApexSphereCone(.init(relation: relation)))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalApexSphereConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: min(options.maximumSubdivisionDepth, admission.remainingSourceDepth)),
            maximumTransportDepth: admission.maximumAlgebraicDepth ?? 32,
            maximumCharts: min(admission.maximumSpanCount, options.maximumSubdivisionCells), maximumFamilies: 3, maximumIdentityProofs: 0)
    }
    private func source(_ input: OriginalApexSphereConeSurfaceInput, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission, using a: inout Admission)
        throws -> OriginalSourceBinding<Source> {
        guard let pair=OriginalApexSphereConeSurfaceSnapshotProvider.pair(input),
            case .analytic(.cone(_,_,let angle))=pair.cone else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        let physical = try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
        return try DefaultOriginalSourceBindingIssuer(provider: OriginalApexSphereConeSurfaceSnapshotProvider(
            physical: physical, maximumExtensionLevel: a.usage.maximumAlgebraicDepth, tolerance: tolerance))
            .bind(input, limits: limits(options: options, admission: admission).source, using: &a)
    }
}
