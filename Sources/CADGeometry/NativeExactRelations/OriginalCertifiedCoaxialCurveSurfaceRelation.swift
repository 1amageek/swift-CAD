import CADCore

/// Complete original coaxial contacts, with a symbolic integer-indexed UV family.
public final class OriginalCertifiedCoaxialCurveSurfaceRelation: Sendable {
    public typealias Base = OriginalPhysicalAngleScalarDomain
    public typealias Value = Base.Value
    public typealias Interval = ExactParameterInterval<Value>
    public typealias Source = OriginalCertifiedCoaxialConeCylinderSnapshot
    public typealias CurveSelection = OriginalParameterSelection<Source, Base>
    public typealias TargetSelection = OriginalParameterSelection<Surface3D, Base>

    public let source: OriginalSourceBinding<Source>
    public let support: CurveSelection
    public let request: CurveSelection
    public let effective: CurveSelection
    public let targetSupport: TargetSelection
    public let targetRequest: TargetSelection
    public let targetEffective: TargetSelection
    public let isCylinder: Bool
    public let isEmpty: Bool
    public let hasPositiveDimensionalSolutions: Bool
    public var hasPositiveDimensionalImage: Bool { hasPositiveDimensionalSolutions }
    public var imageDimension: Int? { isEmpty ? nil : hasPositiveDimensionalSolutions ? 1 : 0 }
    public var fiberDimension: Int? { isEmpty ? nil : 0 }
    public let proofDepth: ExactScalarDepth
    private let roots: [Value]
    public var planeParameters: ArraySlice<Value> { roots[...] }

    private init(source: OriginalSourceBinding<Source>, support: CurveSelection,
        request: CurveSelection, effective: CurveSelection, targetSupport: TargetSelection,
        targetRequest: TargetSelection, targetEffective: TargetSelection, isCylinder: Bool,
        isEmpty: Bool, positive: Bool, roots: [Value], proofDepth: ExactScalarDepth) {
        self.source = source; self.support = support; self.request = request
        self.effective = effective; self.targetSupport = targetSupport
        self.targetRequest = targetRequest; self.targetEffective = targetEffective
        self.isCylinder = isCylinder; self.isEmpty = isEmpty
        hasPositiveDimensionalSolutions = positive; self.roots = roots; self.proofDepth = proofDepth
    }

    public static func resolve<A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<Source>, target: OriginalSourceBinding<Surface3D>,
        curveIntervals: [[Interval]], targetIntervals: [[Interval]], maximumPoints: Int,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalCertifiedCoaxialCurveSurfaceRelation {
        try a.checkpoint(); try source.require(limits.source); try target.require(limits.source)
        let law = source.original, f = law.field
        try a.admitDepth(value: law.proofDepth.value, coefficient: law.proofDepth.coefficient)
        let cylinder = target.original == law.original.cylinderSurface
        guard cylinder || OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(target.original) else {
            throw OriginalDomainIdentityFailure.foreignOwner
        }
        guard curveIntervals.count == 1, targetIntervals.count == 2, maximumPoints >= 0 else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
        // Both original parents retain independent arbitrary integer lifts.
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let interval = try Interval.checked(field: f, lower: .finite(zero), upper: .finite(one),
            depth: .init(value: 0, coefficient: 0), using: &a)
        try storage(1, [Interval].self, &a); try storage(1, Interval.self, &a)
        try storage(1, OriginalCoordinateSemantics.self, &a)
        let frame = try DefaultOriginalParameterTransporter<Source, Base>().frame(source: source,
            field: f, support: [[interval]], semantics: [.authoredScalar], limits: limits, using: &a)
        let support = try frame.fullSelection(limits: limits, using: &a)
        let request = try frame.selection(intervals: curveIntervals, limits: limits, using: &a)
        let effective = try request.intersection(support, limits: limits, using: &a)
        let whole = try Interval.checked(field: f, lower: .negativeInfinity, upper: .positiveInfinity,
            depth: .init(value: 0, coefficient: 0), using: &a)
        try storage(2, [Interval].self, &a); try storage(2, Interval.self, &a)
        try storage(2, OriginalCoordinateSemantics.self, &a)
        let targetFrame = try DefaultOriginalParameterTransporter<Surface3D, Base>().frame(source: target,
            field: f, support: [[whole], [whole]], semantics: [cylinder ? .intrinsicAngularLabel : .authoredScalar, .authoredScalar],
            limits: limits, using: &a)
        let targetSupport = try targetFrame.fullSelection(limits: limits, using: &a)
        let targetRequest = try targetFrame.selection(intervals: targetIntervals, limits: limits, using: &a)
        let targetEffective = try targetRequest.intersection(targetSupport, limits: limits, using: &a)
        var roots: [Value] = [], empty = true, positive = false
        if cylinder {
            let domain = targetEffective.frame.axisDomains[1]
            if !effective.isEmpty && !targetEffective.isEmpty,
                try domain.contains(law.height, in: targetEffective.axes[1], queryField: f, using: &a) {
                for t in effective.axes[0].intervals {
                    for u in targetEffective.axes[0].intervals {
                        try a.consumeWork(1)
                        if try integerOverlap(t, u, strict: false, law: law, using: &a) { empty = false }
                        if try hasLength(t, field: f, using: &a), try hasLength(u, field: f, using: &a),
                            try integerOverlap(t, u, strict: true, law: law, using: &a) { positive = true }
                    }
                }
            }
        } else {
            for index in 0..<2 {
                let t = try law.planeRoot(at: index, using: &a)
                let x = try f.integer(index == 0 ? -1 : 1, using: &a)
                let v = try f.negated(law.height, using: &a)
                try storage(1, Value.self, &a); try storage(2, Value.self, &a)
                if try effective.contains([t], limits: limits, using: &a),
                    try targetEffective.contains([x, v], limits: limits, using: &a) {
                    guard roots.count < maximumPoints else { throw NativeExactRelationFailure.resultLimit }
                    try storage(1, Value.self, &a); roots.append(t)
                }
            }
            empty = roots.isEmpty
        }
        var value = law.proofDepth.value, coefficient = law.proofDepth.coefficient
        for axis in effective.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        for axis in targetEffective.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
        try a.admitDepth(value: value, coefficient: coefficient)
        try storage(1, OriginalCertifiedCoaxialCurveSurfaceRelation.self, &a)
        // Include the immutable class allocation rather than only its reference.
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, CurveSelection,
            CurveSelection, CurveSelection, TargetSelection, TargetSelection, TargetSelection,
            Bool, Bool, Bool, [Value], ExactScalarDepth)>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let result = OriginalCertifiedCoaxialCurveSurfaceRelation(source: source, support: support, request: request, effective: effective,
            targetSupport: targetSupport, targetRequest: targetRequest, targetEffective: targetEffective,
            isCylinder: cylinder, isEmpty: empty, positive: positive, roots: roots, proofDepth: depth)
        try a.checkpoint(); return result
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        try support.frame.require(limits, &a); try request.frame.require(limits, &a)
        try effective.frame.require(limits, &a)
        try targetSupport.frame.require(limits, &a); try targetRequest.frame.require(limits, &a)
        try targetEffective.frame.require(limits, &a)
        // Requests may contain endpoints deeper than the effective intersection.
        for axis in request.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        for axis in targetRequest.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        try a.checkpoint()
    }

    /// Membership in the complete retained target relation, without re-solving.
    public func contains<A: ExactScalarAdmission & ~Copyable>(parameter: Value, u: Value, v: Value,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> Bool {
        try admitProof(limits: limits, using: &a)
        let f = source.original.field
        try Self.storage(1, Value.self, &a); try Self.storage(2, Value.self, &a)
        guard try effective.contains([parameter], limits: limits, using: &a),
            try targetEffective.contains([u, v], limits: limits, using: &a) else { try a.checkpoint(); return false }
        let included: Bool
        if isCylinder {
            let height = try f.compare(v, source.original.height, using: &a) == .equal
            let cycle = try f.subtracting(f.dividing(u, source.original.labelPeriod, using: &a), parameter, using: &a)
            let integer = try OriginalParameterCycle.floor(cycle, field: f, using: &a).scalar(in: f, using: &a)
            included = try height && f.compare(integer, cycle, using: &a) == .equal
        } else {
            included = try planeContains(parameter: parameter, u: u, v: v, using: &a)
        }
        try a.checkpoint(); return included
    }

    public func cylinderUV<A: ExactScalarAdmission & ~Copyable>(parameter: Value, cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> [Value] {
        try admitProof(limits: limits, using: &a)
        let law = source.original, f = law.field
        let u = try law.cylinderLabel(parameter: parameter, cycle: cycle.scalar(in: f, using: &a), using: &a)
        guard isCylinder, try contains(parameter: parameter, u: u, v: law.height, limits: limits, using: &a) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        try Self.storage(2, Value.self, &a); let result = [u, law.height]
        try a.checkpoint(); return result
    }

    /// Both parent families retain independent index domains and the original owners.
    public func parentUV<A: ExactScalarAdmission & ~Copyable>(parameter: Value,
        cylinderCycle: OriginalParameterCycle, coneCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> [Value] {
        try admitProof(limits: limits, using: &a)
        let law = source.original, f = law.field
        try Self.storage(1, Value.self, &a)
        guard try effective.contains([parameter], limits: limits, using: &a) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        let cu = try law.cylinderLabel(parameter: parameter, cycle: cylinderCycle.scalar(in: f, using: &a), using: &a)
        let ku = try law.coneLabel(parameter: parameter, cycle: coneCycle.scalar(in: f, using: &a), using: &a)
        try Self.storage(4, Value.self, &a)
        let result = [cu, law.height, ku, law.coneSlant]
        try a.checkpoint(); return result
    }

    private func planeContains<A: ExactScalarAdmission & ~Copyable>(parameter: Value, u: Value, v: Value,
        using a: inout A) throws -> Bool {
        let law = source.original, f = law.field
        for t in roots {
            if try f.compare(t, parameter, using: &a) == .equal {
                let first = try f.compare(t, law.planeRoot(at: 0, using: &a), using: &a) == .equal
                return try f.compare(u, f.integer(first ? -1 : 1, using: &a), using: &a) == .equal
                    && f.compare(v, f.negated(law.height, using: &a), using: &a) == .equal
            }
        }
        return false
    }

    private static func hasLength<A: ExactScalarAdmission & ~Copyable>(_ interval: Interval,
        field f: Base, using a: inout A) throws -> Bool {
        guard !interval.isEmpty else { return false }
        if case .finite(let l) = interval.lower, case .finite(let u) = interval.upper {
            return try f.compare(l, u, using: &a) == .less
        }
        return true
    }

    private static func integerOverlap<A: ExactScalarAdmission & ~Copyable>(_ t: Interval, _ u: Interval,
        strict: Bool, law: Source, using a: inout A) throws -> Bool {
        guard !t.isEmpty, !u.isEmpty else { return false }
        let f = law.field
        guard case .finite(let tl) = t.lower, case .finite(let th) = t.upper else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        // The authored T support is finite. A nonempty half-unbounded U interval
        // always admits an integer lift; no finite search window is required.
        guard case .finite(let ul) = u.lower, case .finite(let uh) = u.upper else { return true }
        let lower = try f.subtracting(f.dividing(ul, law.labelPeriod, using: &a), th, using: &a)
        let upper = try f.subtracting(f.dividing(uh, law.labelPeriod, using: &a), tl, using: &a)
        var n = try OriginalParameterCycle.floor(lower, field: f, using: &a).scalar(in: f, using: &a)
        let order = try f.compare(n, lower, using: &a)
        if order != .equal || strict || !(u.includesLower && t.includesUpper) {
            n = try f.adding(n, f.integer(1, using: &a), using: &a)
        }
        let end = try f.compare(n, upper, using: &a)
        return end == .less || (end == .equal && !strict && u.includesUpper && t.includesLower)
    }

    private static func storage<T, A: ExactScalarAdmission & ~Copyable>(_ count: Int, _ type: T.Type,
        _ a: inout A) throws {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }
}
