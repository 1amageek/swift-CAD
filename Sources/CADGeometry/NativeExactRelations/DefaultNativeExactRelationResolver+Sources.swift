import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import struct CADGeometry.ScalarInterval
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
import struct CADGeometry.SurfaceParameterBox
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
import SourceGeometryAdapters
#endif

extension DefaultNativeExactRelationResolver {
    func curveMap<A: ExactScalarAdmission & ~Copyable>(_ curve: BSplineCurve3D,
        selected: ScalarInterval?, field: Field, tolerance: ModelingTolerance,
        degree: Int, using admission: inout A
    ) throws -> (map: ExactParametricMap<ExactRationalScalarDomain>, cover: OriginalBSplineDomainCover<BSplineCurve3D,Field>) {
        guard degree >= 0, curve.degree <= degree else { throw NativeExactRelationFailure.invalidDegree }
        guard !curve.isPeriodic else { throw NativeExactRelationFailure.unsupportedCoverage }
        let limits = try domainLimits()
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalBSplineCurveSnapshotProvider(tolerance:tolerance)).bind(curve,limits:limits.source,using:&admission)
        let request: [ScalarInterval]?
        if let selected {
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ScalarInterval.self))
            request = [selected]
        } else { request = nil }
        return try boundMap(source:source,selected:request,field:field,limits:limits,using:&admission)
    }

    func surfaceMap<A: ExactScalarAdmission & ~Copyable>(_ surface: BSplineSurface3D,
        selected: SurfaceParameterBox?, field: Field, tolerance: ModelingTolerance,
        degree: Int, using admission: inout A
    ) throws -> (map: ExactParametricMap<ExactRationalScalarDomain>, cover: OriginalBSplineDomainCover<BSplineSurface3D,Field>) {
        guard degree >= 0, max(surface.uDegree,surface.vDegree) <= degree else { throw NativeExactRelationFailure.invalidDegree }
        guard !surface.isUPeriodic, !surface.isVPeriodic else { throw NativeExactRelationFailure.unsupportedCoverage }
        let limits = try domainLimits()
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalBSplineSurfaceSnapshotProvider(tolerance:tolerance)).bind(surface,limits:limits.source,using:&admission)
        let request: [ScalarInterval]?
        if let selected {
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ScalarInterval.self))
            request = [selected.u,selected.v]
        } else { request = nil }
        return try boundMap(source:source,selected:request,field:field,limits:limits,using:&admission)
    }

    private func domainLimits() throws -> OriginalDomainIdentityLimits {
        // Direct snapshots have source depth zero, one nonperiodic chart, and a
        // fixed identity/inverse word of depth two. Caller scalar limits are unchanged.
        try .init(source:.init(remainingSourceDepth:0),maximumTransportDepth:2,
            maximumCharts:1,maximumFamilies:0,maximumIdentityProofs:0)
    }

    private func boundMap<S: OriginalBSplineSourceReading,A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<S>,selected: [ScalarInterval]?,field: Field,
        limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws -> (map: ExactParametricMap<ExactRationalScalarDomain>, cover: OriginalBSplineDomainCover<S,Field>) {
        let original = source.original,n = original.parameterCount
        guard n == 1 || n == 2 else { throw NativeExactRelationFailure.unsupportedCoverage }
        // Validation is owned by the snapshot provider and precedes every indexed access.
        for axis in 0..<n {
            var count = 0
            for index in original.degree(in:axis)..<original.controlCount(in:axis) {
                try admission.consumeWork(1)
                if original.knot(at:index,in:axis) < original.knot(at:index+1,in:axis) { count += 1 }
            }
            guard count == 1 else { throw NativeExactRelationFailure.unsupportedCoverage }
        }
        let issuer = DefaultOriginalBSplineDomainIssuer<S,Field>()
        let space = try issuer.prepare(source:source,field:field,limits:limits,using:&admission)
        let request: OriginalParameterSelection<S,Field>
        if let selected {
            guard selected.count == n else { throw NativeExactRelationFailure.invalidDomain }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:[ExactParameterInterval<Field.Value>].self))
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:ExactParameterInterval<Field.Value>.self))
            var intervals: [[ExactParameterInterval<Field.Value>]] = []; intervals.reserveCapacity(n)
            for axis in selected {
                try admission.consumeWork(1)
                guard axis.lower.isFinite,axis.upper.isFinite,axis.lower <= axis.upper else { throw NativeExactRelationFailure.invalidDomain }
                intervals.append([try .checked(field:field,lower:.finite(field.binary64(exactly:axis.lower,using:&admission)),
                    upper:.finite(field.binary64(exactly:axis.upper,using:&admission)),depth:.init(value:0,coefficient:0),using:&admission)])
            }
            request = try space.frame.selection(intervals:intervals,limits:limits,using:&admission)
        } else { request = try space.frame.fullSelection(limits:limits,using:&admission) }
        let cover = try issuer.issue(space:space,request:request,limits:limits,using:&admission)
        try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:OriginalParameterCycle.self))
        let zero = try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(0,using:&admission),using:&admission)
        let chart = try DefaultOriginalDomainBoundBSplineChartIssuer<S,Field>().issue(cover:cover,template:0,
            cycles:[OriginalParameterCycle](repeating:zero,count:n),limits:limits,using:&admission)
        let cells = try Cells(field:field,variableCount:n,using:&admission)
        let roots = try ExactRealRootDomain(field:field,using:&admission)
        try admission.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<Field>.self))
        try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:ExactRealRootInterval<Field.Value>.self))
        var polynomials: [ExactPolynomial<Field>] = []; polynomials.reserveCapacity(4)
        var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(n)
        for law in chart.law.homogeneous {
            try admission.consumeWork(1)
            // L3 has a different ring owner. This is a checked representation transfer,
            // not another source preparation or equation solve.
            polynomials.append(try cells.polynomials.importing(law,using:&admission))
        }
        for axis in chart.localSelection.axes {
            try admission.consumeWork(1)
            guard axis.intervalCount <= 1 else { throw NativeExactRelationFailure.unsupportedCoverage }
            if let interval = axis.intervals.first {
                guard case .finite(let lower) = interval.lower,case .finite(let upper) = interval.upper else {
                    throw NativeExactRelationFailure.unsupportedCoverage
                }
                domains.append(try roots.domain(lower:.finite(lower),upper:.finite(upper),
                    includesLower:interval.includesLower,includesUpper:interval.includesUpper,using:&admission))
            } else { domains.append(try roots.emptyDomain(using:&admission)) }
        }
        let system = try cells.bind(polynomials:polynomials,domains:domains,using:&admission)
        let map = try Domain(cells:Cells.self,topology:.init(cells:Cells.self)).map(from:system,using:&admission)
        return (map,cover)
    }
}
