import CADCore

/// Owns one original positional preparation shared by receipt-consuming callers.
package enum OriginalExactSurfaceSelfContactPreparer {
    package typealias Base = OriginalExactScalarDomain
    package typealias Source = OriginalCoonsAtlasSnapshot
    package typealias Evidence = OriginalRationalChartReceipt<Source,Int,Base>
    package typealias Cover = OriginalIssuedDomainCover<Source,Int,Base>
    package typealias Contacts = OriginalIssuedGraphSelfContacts<Source,Evidence,Cover,Evidence,Cover>

    package static func coons<A: ExactScalarAdmission & ~Copyable>(surface: OriginalCoonsSurface3D, domain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits, maximumPairs: Int,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws -> Contacts {
        try a.checkpoint()
        let field = try Base(maximumValueDepth:limits.maximumTransportDepth,
            maximumCoefficientDepth:limits.maximumTransportDepth,using:&a)
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalCoonsAtlasSnapshotProvider(field:field,tolerance:tolerance))
            .bind(surface,limits:limits.source,using:&a)
        let charts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
            .prepare(source:source,maximumCharts:limits.maximumCharts,limits:limits.source,using:&a)
        let frame = try DefaultOriginalRetainedSurfaceDomainIssuer<Source>()
            .frame(family:charts,limits:limits,using:&a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws:charts.laws,
            request:selection(frame:frame,domain:domain,field:field,limits:limits,using:&a),limits:limits,using:&a)
        let algebraic = try ExactAlgebraicScalarDomain.base(field:field,
            maximumExtensionLevel:limits.maximumTransportDepth,using:&a)
        let family = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover,
            field:algebraic,maximumGraphs:limits.maximumCharts,limits:limits,using:&a)
        let raw = try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,
            first:family,second:family,maximumPairs:maximumPairs,limits:limits,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        let result = try DefaultOriginalIssuedGraphSelfContactQuery<Source,Evidence,Cover,Evidence,Cover>()
            .contacts(in:raw,domainLimits:limits,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        try a.checkpoint()
        return result
    }

    private static func selection<A: ExactScalarAdmission & ~Copyable>(
        frame: OriginalParameterFrame<Source,Base>, domain: SurfaceParameterBox?,
        field: Base, limits: OriginalDomainIdentityLimits, using a: inout A
    ) throws -> OriginalParameterSelection<Source,Base> {
        guard let domain else { return try frame.fullSelection(limits:limits,using:&a) }
        func interval(_ bounds: ScalarInterval) throws -> ExactParameterInterval<Base.Value> {
            try .checked(field:field,lower:.finite(field.binary64(exactly:bounds.lower,using:&a)),
                upper:.finite(field.binary64(exactly:bounds.upper,using:&a)),depth:.zero,using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<Base.Value>].self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactParameterInterval<Base.Value>.self))
        return try frame.selection(intervals:[[interval(domain.u)],[interval(domain.v)]],limits:limits,using:&a)
    }

    package static func native<A: ExactScalarAdmission & ~Copyable>(surface: BSplineSurface3D,
        domain: SurfaceParameterBox, tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        maximumMaps: Int, maximumPairs: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws -> OriginalExactNativeSelfContacts {
        try a.checkpoint()
        typealias Field = OriginalExactNativeSelfContacts.Field
        let field = try Field.base(field:ExactRationalScalarDomain(),maximumExtensionLevel:32,using:&a)
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:tolerance))
            .bind(surface,limits:limits.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space = try issuer.prepare(source:source,field:field,limits:limits,using:&a)
        func interval(_ box: ScalarInterval) throws -> ExactParameterInterval<Field.Value> {
            try .checked(field:field,lower:.finite(field.binary64(exactly:box.lower,using:&a)),
                upper:.finite(field.binary64(exactly:box.upper,using:&a)),depth:.zero,using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<Field.Value>].self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactParameterInterval<Field.Value>.self))
        let request = try space.frame.selection(intervals:[[interval(domain.u)],[interval(domain.v)]],limits:limits,using:&a)
        let cover = try issuer.issue(space:space,request:request,limits:limits,using:&a)
        let raw = try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:cover,second:cover,
            domainLimits:limits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        return try DefaultOriginalExactNativeSelfContactQuery().contacts(in:raw,domainLimits:limits,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
    }
}
