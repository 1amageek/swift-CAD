import CADCore

/// Complete source UV product, two signed images and symbolic integer families.
public final class OriginalCoaxialSurfaceSurfaceRelation: Sendable {
    public typealias Source = OriginalCoaxialSurfacePairSnapshot
    public typealias Field = OriginalPhysicalAngleScalarDomain
    public typealias Value = Field.Value
    public typealias Primitive = OriginalAnalyticCoordinateSnapshot
    public typealias Selection = OriginalParameterSelection<Primitive, Field>
    public struct Branch: Sendable {
        public let positive: Bool
        public let phase: ExactParameterSet<Field>
        public let imageDimension: Int
        public var fiberDimension: Int { 0 }
    }
    public let source: OriginalSourceBinding<Source>
    public let firstSupport: Selection
    public let firstRequest: Selection
    public let firstEffective: Selection
    public let secondSupport: Selection
    public let secondRequest: Selection
    public let secondEffective: Selection
    public let phaseDomain: ExactParameterDomain<Field>
    public let fundamentalPhase: ExactParameterSet<Field>
    private let selected: [Branch]
    public var branches: ArraySlice<Branch> { selected[...] }
    public var isEmpty: Bool { selected.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { selected.contains { $0.imageDimension == 1 } }
    public var hasPositiveDimensionalImage: Bool { hasPositiveDimensionalSolutions }
    public let proofDepth: ExactScalarDepth
    private init(source: OriginalSourceBinding<Source>, firstSupport: Selection, firstRequest: Selection,
        firstEffective: Selection, secondSupport: Selection, secondRequest: Selection, secondEffective: Selection,
        phaseDomain: ExactParameterDomain<Field>, fundamentalPhase: ExactParameterSet<Field>, selected: [Branch], proofDepth: ExactScalarDepth) {
        self.source = source; self.firstSupport = firstSupport; self.firstRequest = firstRequest; self.firstEffective = firstEffective
        self.secondSupport = secondSupport; self.secondRequest = secondRequest; self.secondEffective = secondEffective
        self.phaseDomain = phaseDomain; self.fundamentalPhase = fundamentalPhase; self.selected = selected; self.proofDepth = proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        firstIntervals: [[ExactParameterInterval<Value>]], secondIntervals: [[ExactParameterInterval<Value>]],
        maximumComponents: Int, limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalCoaxialSurfaceSurfaceRelation {
        try a.checkpoint(); try source.require(limits.source); try requireLimits(limits)
        let snapshot = source.original, f = snapshot.field
        try snapshot.firstLaw.admitProof(limits: limits.source, using: &a)
        try snapshot.secondLaw.admitProof(limits: limits.source, using: &a)
        try a.admitDepth(value: snapshot.proofDepth.value, coefficient: snapshot.proofDepth.coefficient)
        guard firstIntervals.count == 2, secondIntervals.count == 2, maximumComponents >= 0 else { throw OriginalDomainIdentityFailure.invalidDomain }
        let (fs, fr, fe) = try selections(snapshot.first, field: f, intervals: firstIntervals, limits: limits, using: &a)
        let (ss, sr, se) = try selections(snapshot.second, field: f, intervals: secondIntervals, limits: limits, using: &a)
        let cone = snapshot.coneIsFirst ? fe : se, cylinder = snapshot.coneIsFirst ? se : fe
        let domain = try ExactParameterDomain(field: f, depth: snapshot.proofDepth, using: &a)
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let fundamental = try domain.interval(lower: .finite(zero), upper: .finite(one), includesUpper: false, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self))
        let full = try domain.set(intervals: [fundamental], using: &a)
        var branches: [Branch] = []
        for branchIndex in 0..<2 {
            let positive = branchIndex == 0
            try a.consumeWork(1)
            let slant = try snapshot.slant(positive: positive, using: &a), height = try snapshot.cylinderHeight(positive: positive, using: &a)
            guard try cone.frame.axisDomains[1].contains(slant, in: cone.axes[1], using: &a),
                try cylinder.frame.axisDomains[1].contains(height, in: cylinder.axes[1], using: &a) else { continue }
            let conePhase = try OriginalCoaxialAngularSelection.residue(axis: cone.axes[0], offset: snapshot.coneOffset(positive: positive, using: &a),
                period: snapshot.labelPeriod, field: f, domain: domain, using: &a)
            let cylinderPhase = try OriginalCoaxialAngularSelection.residue(axis: cylinder.axes[0], offset: zero,
                period: snapshot.labelPeriod, field: f, domain: domain, using: &a)
            let phase = try domain.intersection(conePhase, cylinderPhase, using: &a)
            if phase.isEmpty { continue }
            guard branches.count < maximumComponents else { throw NativeExactRelationFailure.resultLimit }
            var dimension = 0
            for interval in phase.intervals {
                if case .finite(let lo) = interval.lower, case .finite(let hi) = interval.upper,
                    try f.compare(lo, hi, using: &a) == .less { dimension = 1 }
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Branch.self))
            branches.append(.init(positive: positive, phase: phase, imageDimension: dimension))
        }
        var value = snapshot.proofDepth.value, coefficient = snapshot.proofDepth.coefficient
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Selection.self))
        for selection in [fr, sr, fe, se] {
            for axis in selection.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        }
        for branch in branches { value = max(value, branch.phase.depth.value); coefficient = max(coefficient, branch.phase.depth.coefficient) }
        let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
        try a.admitDepth(value: value, coefficient: coefficient)
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, Selection, Selection, Selection, Selection,
            Selection, Selection, ExactParameterDomain<Field>, ExactParameterSet<Field>, [Branch], ExactScalarDepth)>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let result = OriginalCoaxialSurfaceSurfaceRelation(source: source, firstSupport: fs, firstRequest: fr, firstEffective: fe,
            secondSupport: ss, secondRequest: sr, secondEffective: se, phaseDomain: domain, fundamentalPhase: full, selected: branches, proofDepth: depth)
        try a.checkpoint(); return result
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source); try OriginalCoaxialSurfaceSurfaceRelation.requireLimits(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try source.original.firstLaw.admitProof(limits: limits.source, using: &a)
        try source.original.secondLaw.admitProof(limits: limits.source, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Selection.self))
        for selection in [firstRequest, secondRequest, firstEffective, secondEffective] {
            try selection.frame.require(limits, &a)
            for axis in selection.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        }
        try a.checkpoint()
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(branch: Int, phase: Value,
        coneCycle: OriginalParameterCycle, cylinderCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (firstUV: [Value], secondUV: [Value], position: OriginalCoaxialSymbolicPosition) {
        try admitProof(limits: limits, using: &a)
        guard branch >= 0, branch < selected.count else { throw OriginalDomainIdentityFailure.outsideSupport }
        let b = selected[branch], snapshot = source.original, f = snapshot.field
        guard try phaseDomain.contains(phase, in: b.phase, using: &a) else { throw OriginalDomainIdentityFailure.outsideSupport }
        let label = try f.multiplying(snapshot.labelPeriod, phase, using: &a)
        let cu = try f.adding(label, f.multiplying(snapshot.labelPeriod, cylinderCycle.scalar(in: f, using: &a), using: &a), using: &a)
        let ku = try f.adding(f.adding(label, snapshot.coneOffset(positive: b.positive, using: &a), using: &a),
            f.multiplying(snapshot.labelPeriod, coneCycle.scalar(in: f, using: &a), using: &a), using: &a)
        let kv = try snapshot.slant(positive: b.positive, using: &a), cv = try snapshot.cylinderHeight(positive: b.positive, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Value.self))
        let cone = [ku, kv], cylinder = [cu, cv]
        let first = snapshot.coneIsFirst ? cone : cylinder, second = snapshot.coneIsFirst ? cylinder : cone
        guard try firstEffective.contains(first, limits: limits, using: &a),
            try secondEffective.contains(second, limits: limits, using: &a) else { throw OriginalDomainIdentityFailure.outsideSupport }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCoaxialSymbolicPosition.self))
        let position = try OriginalCoaxialSymbolicPosition(source: source, positive: b.positive, intrinsicLabel: label,
            radius: snapshot.radius, centerX: snapshot.centerX, centerY: snapshot.centerY, height: snapshot.worldHeight(positive: b.positive, using: &a))
        try a.checkpoint(); return (first, second, position)
    }
    private static func selections<A: ExactScalarAdmission & ~Copyable>(_ source: OriginalSourceBinding<Primitive>, field: Field,
        intervals: [[ExactParameterInterval<Value>]], limits: OriginalDomainIdentityLimits, using a: inout A) throws -> (Selection, Selection, Selection) {
        let whole = try ExactParameterInterval<Value>.checked(field: field, lower: .negativeInfinity, upper: .positiveInfinity,
            depth: .init(value: 0, coefficient: 0), using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalCoordinateSemantics.self))
        let frame = try DefaultOriginalParameterTransporter<Primitive, Field>().frame(source: source, field: field,
            support: [[whole], [whole]], semantics: [.intrinsicAngularLabel, .authoredScalar], limits: limits, using: &a)
        let support = try frame.fullSelection(limits: limits, using: &a)
        let request = try frame.selection(intervals: intervals, limits: limits, using: &a)
        return (support, request, try request.intersection(support, limits: limits, using: &a))
    }
    private static func requireLimits(_ limits: OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts >= 2 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
    }
}
