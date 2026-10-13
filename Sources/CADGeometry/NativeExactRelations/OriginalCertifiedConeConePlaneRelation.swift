import CADCore

/// Complete original cardinal contacts selected in actual T and plane domains.
public final class OriginalCertifiedConeConePlaneRelation: Sendable {
    public typealias Source = OriginalCertifiedConeConeFullSnapshot
    public typealias Field = OriginalPiScalarDomain
    public typealias Selection = OriginalParameterSelection<Source, Field>
    public let source: OriginalSourceBinding<Source>
    public let target: OriginalSourceBinding<Surface3D>
    public let support: Selection
    public let request: Selection
    public let effective: Selection
    private let selected: [Int]
    private let targetRanges: [ScalarInterval?]
    public var phaseOrdinals: ArraySlice<Int> { selected[...] }
    public var planeRanges: ArraySlice<ScalarInterval?> { targetRanges[...] }
    public var isEmpty: Bool { selected.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { false }
    public var hasPositiveDimensionalImage: Bool { false }
    public var imageDimension: Int? { isEmpty ? nil : 0 }
    public var fiberDimension: Int? { isEmpty ? nil : 0 }
    public let proofDepth: ExactScalarDepth
    private init(source: OriginalSourceBinding<Source>, target: OriginalSourceBinding<Surface3D>,
        support: Selection, request: Selection, effective: Selection, selected: [Int],
        targetRanges: [ScalarInterval?], proofDepth: ExactScalarDepth) {
        self.source = source; self.target = target; self.support = support; self.request = request
        self.effective = effective; self.selected = selected; self.targetRanges = targetRanges; self.proofDepth = proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        target: OriginalSourceBinding<Surface3D>, curveIntervals: [[ExactParameterInterval<Field.Value>]],
        planeRanges: [ScalarInterval?], maximumPoints: Int, limits: OriginalDomainIdentityLimits,
        tolerance: ModelingTolerance, using a: inout A) throws -> OriginalCertifiedConeConePlaneRelation {
        try a.checkpoint(); try source.require(limits.source); try target.require(limits.source)
        guard OriginalCertifiedConeConeTargetSnapshotProvider.supports(target.original) else {
            throw OriginalDomainIdentityFailure.foreignOwner
        }
        try requireLimits(limits)
        guard curveIntervals.count == 1, planeRanges.count == 2, maximumPoints >= 0 else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        let f = source.original.phaseField
        try source.original.admitProof(using: &a)
        let span = try ExactParameterInterval.checked(field: f, lower: .finite(f.integer(0, using: &a)),
            upper: .finite(f.integer(1, using: &a)), depth: source.original.proofDepth, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<Field.Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Field.Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCoordinateSemantics.self))
        let frame = try DefaultOriginalParameterTransporter<Source, Field>().frame(source: source, field: f,
            support: [[span]], semantics: [.authoredScalar], limits: limits, using: &a)
        let support = try frame.fullSelection(limits: limits, using: &a)
        let request = try frame.selection(intervals: curveIntervals, limits: limits, using: &a)
        let effective = try request.intersection(support, limits: limits, using: &a)
        var selected: [Int] = []
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ScalarInterval?.self))
        for ordinal in 0..<2 {
            try a.consumeWork(1)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Field.Value.self))
            let tIncluded = try effective.contains([source.original.parameters[ordinal]], limits: limits, using: &a)
            guard tIncluded else { continue }
            let bounds = try source.original.bounds(phaseOrdinal: ordinal, tolerance: tolerance, using: &a)
            let uIncluded = try includes(bounds.planeU, in: planeRanges[0])
            let vIncluded = try includes(bounds.planeV, in: planeRanges[1])
            if uIncluded && vIncluded {
                guard selected.count < maximumPoints else { throw NativeExactRelationFailure.resultLimit }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Int.self)); selected.append(ordinal)
            }
        }
        var v = source.original.proofDepth.value, c = source.original.proofDepth.coefficient
        for axis in request.axes { v = max(v, axis.depth.value); c = max(c, axis.depth.coefficient) }
        for axis in effective.axes { v = max(v, axis.depth.value); c = max(c, axis.depth.coefficient) }
        let depth = try ExactScalarDepth(value: v, coefficient: c)
        try a.admitDepth(value: v, coefficient: c)
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, OriginalSourceBinding<Surface3D>,
            Selection, Selection, Selection, [Int], [ScalarInterval?], ExactScalarDepth)>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let result = OriginalCertifiedConeConePlaneRelation(source: source, target: target, support: support, request: request,
            effective: effective, selected: selected, targetRanges: planeRanges, proofDepth: depth)
        try a.checkpoint(); return result
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source); try target.require(limits.source); try OriginalCertifiedConeConePlaneRelation.requireLimits(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try source.original.admitProof(using: &a)
        try support.frame.require(limits, &a); try request.frame.require(limits, &a); try effective.frame.require(limits, &a)
        for axis in request.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        for axis in effective.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        try a.checkpoint()
    }
    public func parentUV<A: ExactScalarAdmission & ~Copyable>(phaseOrdinal: Int,
        referenceCycle: OriginalParameterCycle, parameterizedCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (referenceU: Field.Value, referenceV: OriginalCertifiedConeConeCoordinate,
            parameterizedU: Field.Value, parameterizedV: OriginalCertifiedConeConeCoordinate) {
        try admitProof(limits: limits, using: &a)
        guard selected.contains(phaseOrdinal) else { throw OriginalDomainIdentityFailure.outsideSupport }
        let f = source.original.phaseField
        let b = try f.binary64(exactly: 2 * Double.pi, using: &a)
        let half = try f.dividing(b, f.integer(2, using: &a), using: &a)
        let ref = source.original.original.componentKind == .positiveFullBranch ? try f.integer(0, using: &a) : half
        let par = phaseOrdinal == 0 ? try f.integer(0, using: &a) : half
        let ru = try f.adding(ref, f.multiplying(b, referenceCycle.scalar(in: f, using: &a), using: &a), using: &a)
        let pu = try f.adding(par, f.multiplying(b, parameterizedCycle.scalar(in: f, using: &a), using: &a), using: &a)
        let rv = try OriginalCertifiedConeConeCoordinate.issue(source: source, phaseOrdinal: phaseOrdinal,
            kind: .referenceSlant, limits: limits.source, using: &a)
        let pv = try OriginalCertifiedConeConeCoordinate.issue(source: source, phaseOrdinal: phaseOrdinal,
            kind: .parameterizedSlant, limits: limits.source, using: &a)
        try a.checkpoint(); return (ru, rv, pu, pv)
    }
    private static func includes(_ bounds: OutwardScalarInterval, in request: ScalarInterval?) throws -> Bool {
        guard bounds.isFinite else { throw ExactScalarFailure.unresolved }
        guard let request else { return true }
        if request.upper < bounds.lower || request.lower > bounds.upper { return false }
        if request.lower <= bounds.lower && bounds.upper <= request.upper { return true }
        throw ExactScalarFailure.unresolved
    }
    private static func requireLimits(_ limits: OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
    }
}
