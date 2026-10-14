import CADCore

/// Publishes retained original families under the existing SSI caller allowance.
struct OriginalCoincidentConePublicProducer {
    private typealias Admission = NativeExactPublicAdmission<NativeSurfaceSurfacePointAllowance>
    typealias Source = OriginalCoincidentConeSnapshot
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalCoincidentConeRelation? {
        let input = OriginalCoincidentConeInput(first: first, second: second)
        guard OriginalCoincidentConeSnapshotProvider.angle(input) != nil else { return nil }
        let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
        var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
        let bound = try source(input, options: options, tolerance: tolerance, admission: admission, using: &a)
        return try OriginalCoincidentConeRelation.resolve(source: bound, firstBox: nil, secondBox: nil,
            maximumComponents: options.maximumSeedCount, limits: limits(options: options, admission: admission), using: &a)
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil,
        secondBox: SurfaceParameterBox? = nil, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, includeRelations: Bool = false, admission: SurfaceSurfaceQueryAdmission = .legacy,
        retained: OriginalCoincidentConeRelation? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        let input = OriginalCoincidentConeInput(first: first, second: second)
        guard OriginalCoincidentConeSnapshotProvider.angle(input) != nil else { return nil }
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
            let relation = try OriginalCoincidentConeRelation.resolve(source: bound, firstBox: firstBox,
                secondBox: secondBox, maximumComponents: options.maximumSeedCount,
                limits: limits(options: options, admission: admission), prepared: retained, using: &a)
            let count = relation.pieces.count
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []; components.reserveCapacity(count)
            for i in relation.pieces.indices {
                try a.consumeWork(1)
                components.append(.originalCoincidentCone(.init(relation:relation,ordinal:i)))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalCoincidentConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: min(options.maximumSubdivisionDepth, admission.remainingSourceDepth)),
            maximumTransportDepth: admission.maximumAlgebraicDepth ?? 32,
            maximumCharts: min(admission.maximumSpanCount, options.maximumSubdivisionCells), maximumFamilies: 2, maximumIdentityProofs: 2)
    }
    private func source(_ input: OriginalCoincidentConeInput, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission, using a: inout Admission)
        throws -> OriginalSourceBinding<Source> {
        guard let angle=OriginalCoincidentConeSnapshotProvider.angle(input) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        let field=try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
        return try DefaultOriginalSourceBindingIssuer(provider:OriginalCoincidentConeSnapshotProvider(field:field,tolerance:tolerance))
            .bind(input,limits:limits(options:options,admission:admission).source,using:&a)
    }
}
