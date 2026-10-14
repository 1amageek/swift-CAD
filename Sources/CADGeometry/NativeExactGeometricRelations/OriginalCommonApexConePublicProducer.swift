import CADCore

/// Publishes retained original families under the existing SSI caller allowance.
struct OriginalCommonApexConePublicProducer {
    private typealias Admission = NativeExactPublicAdmission<NativeSurfaceSurfacePointAllowance>
    typealias Source = OriginalCommonApexConeSnapshot
    func prepare(first: Surface3D, second: Surface3D, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalCommonApexConeRelation? {
        let input = OriginalCommonApexConeInput(first: first, second: second)
        guard OriginalCommonApexConeSnapshotProvider.pair(input) != nil else { return nil }
        let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
        var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
        let bound = try source(input, options: options, tolerance: tolerance, admission: admission, using: &a)
        return try OriginalCommonApexConeRelation.resolve(source: bound, firstBox: nil, secondBox: nil,
            maximumComponents: options.maximumSeedCount, limits: limits(options: options, admission: admission), using: &a)
    }
    func resolve(first: Surface3D, second: Surface3D, firstBox: SurfaceParameterBox? = nil,
        secondBox: SurfaceParameterBox? = nil, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, includeRelations: Bool = false, admission: SurfaceSurfaceQueryAdmission = .legacy,
        retained: OriginalCommonApexConeRelation? = nil) throws -> SurfaceSurfaceIntersectionResult? {
        let input = OriginalCommonApexConeInput(first: first, second: second)
        guard OriginalCommonApexConeSnapshotProvider.pair(input) != nil else { return nil }
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
            let relation = try OriginalCommonApexConeRelation.resolve(source: bound, firstBox: firstBox,
                secondBox: secondBox, maximumComponents: options.maximumSeedCount,
                limits: limits(options: options, admission: admission), prepared: retained, using: &a)
            let count = relation.isEmpty ? 0 : 1
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceSurfaceIntersection.self))
            var components: [SurfaceSurfaceIntersection] = []; components.reserveCapacity(count)
            if !relation.isEmpty {
                components.append(.originalCommonApexCone(.init(relation: relation)))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: components, originalCommonApexConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func limits(options: SurfaceSurfaceIntersectionOptions, admission: SurfaceSurfaceQueryAdmission) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: min(options.maximumSubdivisionDepth, admission.remainingSourceDepth)),
            maximumTransportDepth: admission.maximumAlgebraicDepth ?? 32,
            maximumCharts: min(admission.maximumSpanCount, options.maximumSubdivisionCells), maximumFamilies: 2, maximumIdentityProofs: 2)
    }
    private func source(_ input: OriginalCommonApexConeInput, options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission, using a: inout Admission)
        throws -> OriginalSourceBinding<Source> {
        let alpha=try OriginalPhysicalAngleScalarDomain(originalRadians:Double(bitPattern:0x3fddac670561bb50),using:&a)
        let beta=try OriginalPhysicalAngleScalarDomain(originalRadians:Double(bitPattern:0x3fd6f61941e4def1),using:&a)
        return try DefaultOriginalSourceBindingIssuer(provider:OriginalCommonApexConeSnapshotProvider(reference:alpha,
            parameterized:beta,maximumExtensionLevel:a.usage.maximumAlgebraicDepth,tolerance:tolerance))
            .bind(input,limits:limits(options:options,admission:admission).source,using:&a)
    }
}
