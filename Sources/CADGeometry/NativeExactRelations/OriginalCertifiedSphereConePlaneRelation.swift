import CADCore

/// All original plane contacts, with separate exact phase and position fields.
public final class OriginalCertifiedSphereConePlaneRelation: Sendable {
    public typealias Source = OriginalCertifiedSphereConeFullSnapshot
    public typealias Phase = OriginalPiScalarDomain
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public typealias CurveSelection = OriginalParameterSelection<Source, Phase>
    public typealias PlaneSelection = OriginalParameterSelection<Surface3D, Field>
    public let source: OriginalSourceBinding<Source>
    public let support: CurveSelection
    public let request: CurveSelection
    public let effective: CurveSelection
    public let target: OriginalSourceBinding<Surface3D>
    private let selections: [PlaneSelection]
    private let ordinals: [Int]
    public var phaseOrdinals: ArraySlice<Int> { ordinals[...] }
    public var planeRequests: ArraySlice<PlaneSelection> { selections[...] }
    public var isEmpty: Bool { ordinals.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { false }
    public var hasPositiveDimensionalImage: Bool { false }
    public var imageDimension: Int? { isEmpty ? nil : 0 }
    public var fiberDimension: Int? { isEmpty ? nil : 0 }
    public let proofDepth: ExactScalarDepth

    private init(source: OriginalSourceBinding<Source>, support: CurveSelection, request: CurveSelection,
        effective: CurveSelection, target: OriginalSourceBinding<Surface3D>, selections: [PlaneSelection],
        ordinals: [Int], proofDepth: ExactScalarDepth) {
        self.source = source; self.support = support; self.request = request; self.effective = effective
        self.target = target; self.selections = selections; self.ordinals = ordinals; self.proofDepth = proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        target: OriginalSourceBinding<Surface3D>, curveIntervals: [[ExactParameterInterval<Phase.Value>]],
        planeRanges: [ScalarInterval?], maximumPoints: Int, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalCertifiedSphereConePlaneRelation {
        try a.checkpoint(); try source.require(limits.source); try target.require(limits.source)
        guard OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(target.original) else {
            throw OriginalDomainIdentityFailure.foreignOwner
        }
        guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        guard curveIntervals.count == 1, planeRanges.count == 2, maximumPoints >= 0 else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        let snapshot = source.original, phase = snapshot.phase.law.field
        let interval = try ExactParameterInterval.checked(field: phase, lower: .finite(snapshot.phase.supportLower),
            upper: .finite(snapshot.phase.supportUpper), depth: snapshot.phase.proofDepth, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<Phase.Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Phase.Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCoordinateSemantics.self))
        let frame = try DefaultOriginalParameterTransporter<Source, Phase>().frame(source: source, field: phase,
            support: [[interval]], semantics: [.authoredScalar], limits: limits, using: &a)
        let support = try frame.fullSelection(limits: limits, using: &a)
        let request = try frame.selection(intervals: curveIntervals, limits: limits, using: &a)
        let effective = try request.intersection(support, limits: limits, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: PlaneSelection.self))
        var selections: [PlaneSelection] = []; selections.reserveCapacity(2)
        var ordinals: [Int] = []
        for root in snapshot.roots {
            let field = root.field
            let whole = try ExactParameterInterval<Field.Value>.checked(field: field,
                lower: .negativeInfinity, upper: .positiveInfinity, depth: root.proofDepth, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<Field.Value>].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<Field.Value>.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalCoordinateSemantics.self))
            let targetFrame = try DefaultOriginalParameterTransporter<Surface3D, Field>().frame(source: target,
                field: field, support: [[whole], [whole]], semantics: [.authoredScalar, .authoredScalar],
                limits: limits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<Field.Value>].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<Field.Value>.self))
            var intervals: [[ExactParameterInterval<Field.Value>]] = []; intervals.reserveCapacity(2)
            for range in planeRanges {
                if let range {
                    intervals.append([try .checked(field: field,
                        lower: .finite(field.binary64(exactly: range.lower, using: &a)),
                        upper: .finite(field.binary64(exactly: range.upper, using: &a)),
                        depth: root.proofDepth, using: &a)])
                } else { intervals.append([whole]) }
            }
            let selection = try targetFrame.selection(intervals: intervals, limits: limits, using: &a)
            selections.append(selection)
            let parameter = snapshot.phase.roots[root.phaseOrdinal].parameter
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Phase.Value.self))
            let curveIncluded = try effective.contains([parameter], limits: limits, using: &a)
            let uvV = try field.negated(root.z, using: &a)
            let uIncluded = try included(root.x, selection: selection, axis: 0, using: &a)
            let vIncluded = try included(uvV, selection: selection, axis: 1, using: &a)
            if curveIncluded && uIncluded && vIncluded {
                guard ordinals.count < maximumPoints else { throw NativeExactRelationFailure.resultLimit }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Int.self)); ordinals.append(root.phaseOrdinal)
            }
        }
        var value = snapshot.proofDepth.value, coefficient = snapshot.proofDepth.coefficient
        for axis in request.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        for axis in effective.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        for selection in selections {
            for axis in selection.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        }
        let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
        try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, CurveSelection,
            CurveSelection, CurveSelection, OriginalSourceBinding<Surface3D>, [PlaneSelection], [Int], ExactScalarDepth)>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let result = OriginalCertifiedSphereConePlaneRelation(source: source, support: support,
            request: request, effective: effective, target: target, selections: selections,
            ordinals: ordinals, proofDepth: depth)
        try a.checkpoint(); return result
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source); try target.require(limits.source)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        try support.frame.require(limits, &a); try request.frame.require(limits, &a); try effective.frame.require(limits, &a)
        for axis in request.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        for axis in effective.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        for selection in selections {
            try selection.frame.require(limits, &a)
            for axis in selection.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        }
        try a.checkpoint()
    }
    public func parentUV<A: ExactScalarAdmission & ~Copyable>(phaseOrdinal: Int,
        coneCycle: OriginalParameterCycle, sphereCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (cone: [Field.Value], sphereU: Field.Value, sphereV: OriginalCertifiedSphereConeLatitude) {
        try admitProof(limits: limits, using: &a)
        guard ordinals.contains(phaseOrdinal) else { throw OriginalDomainIdentityFailure.outsideSupport }
        let root = source.original.roots[phaseOrdinal], field = root.field
        let period = try field.binary64(exactly: 2 * Double.pi, using: &a)
        let quarter = try field.dividing(period, field.integer(4, using: &a), using: &a)
        let baseCone = try field.multiplying(field.integer(root.sine == 1 ? 1 : 3, using: &a), quarter, using: &a)
        let coneU = try field.adding(baseCone, field.multiplying(period, coneCycle.scalar(in: field, using: &a), using: &a), using: &a)
        let negativeX = try field.sign(of: root.x, using: &a) == .negative
        let baseSphere = try field.multiplying(field.integer(negativeX ? 1 : 3, using: &a), quarter, using: &a)
        let sphereU = try field.adding(baseSphere, field.multiplying(period, sphereCycle.scalar(in: field, using: &a), using: &a), using: &a)
        let latitude = try OriginalCertifiedSphereConeLatitude.issue(source: source, phaseOrdinal: phaseOrdinal,
            limits: limits.source, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Field.Value.self))
        let result = ([coneU, root.slant], sphereU, latitude)
        try a.checkpoint(); return result
    }
    private static func included<A: ExactScalarAdmission & ~Copyable>(_ value: Field.Value,
        selection: PlaneSelection, axis: Int, using a: inout A) throws -> Bool {
        let field = selection.frame.scalarField
        _ = try field.importing(value, using: &a)
        for interval in selection.axes[axis].intervals where !interval.isEmpty {
            try a.consumeWork(1)
            var lower = true, upper = true
            if case .finite(let bound) = interval.lower {
                let order = try field.compare(value, bound, using: &a)
                lower = order == .greater || order == .equal && interval.includesLower
            }
            if case .finite(let bound) = interval.upper {
                let order = try field.compare(value, bound, using: &a)
                upper = order == .less || order == .equal && interval.includesUpper
            }
            if lower && upper { return true }
        }
        return false
    }
}
