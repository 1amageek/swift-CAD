import CADCore

/// Complete local lift contacts retaining the original child relation and roles.
public final class OriginalCertifiedPairLiftPlaneRelation: Sendable {
    public typealias Source = OriginalCertifiedPairLiftSnapshot
    public typealias Field = OriginalPhysicalAngleScalarDomain
    public typealias Value = Field.Value
    public typealias Selection = OriginalParameterSelection<Source, Field>
    public struct Contact: Sendable {
        public let parameter: Value
        public let childParameter: Value
        public let childOrdinal: Int
    }
    public let source: OriginalSourceBinding<Source>
    public let childRelation: OriginalCertifiedCoaxialCurveSurfaceRelation
    public let support: Selection
    public let request: Selection
    public let effective: Selection
    public let correspondence: OriginalParameterTransport<Source, Field>
    private let selected: [Contact]
    public var contacts: ArraySlice<Contact> { selected[...] }
    public var isEmpty: Bool { selected.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { false }
    public var hasPositiveDimensionalImage: Bool { false }
    public var imageDimension: Int? { isEmpty ? nil : 0 }
    public var fiberDimension: Int? { isEmpty ? nil : 0 }
    public let proofDepth: ExactScalarDepth
    public let transportDepth: Int
    private init(source: OriginalSourceBinding<Source>, childRelation: OriginalCertifiedCoaxialCurveSurfaceRelation,
        support: Selection, request: Selection, effective: Selection,
        correspondence: OriginalParameterTransport<Source, Field>, selected: [Contact], proofDepth: ExactScalarDepth, transportDepth: Int) {
        self.source = source; self.childRelation = childRelation; self.support = support; self.request = request
        self.effective = effective; self.correspondence = correspondence; self.selected = selected; self.proofDepth = proofDepth; self.transportDepth = transportDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        target: OriginalSourceBinding<Surface3D>, targetIntervals: [[ExactParameterInterval<Value>]],
        requested: [[ExactParameterInterval<Value>]], maximumPoints: Int,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalCertifiedPairLiftPlaneRelation {
        try a.checkpoint(); try source.require(limits.source)
        guard OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(target.original),
            requested.count == 1, maximumPoints >= 0 else { throw OriginalDomainIdentityFailure.invalidDomain }
        let snapshot = source.original, f = snapshot.child.original.field
        try a.admitDepth(value: snapshot.proofDepth.value, coefficient: snapshot.proofDepth.coefficient)
        let t = DefaultOriginalParameterTransporter<Source, Field>()
        let whole = try ExactParameterInterval.checked(field: f, lower: .finite(f.integer(0, using: &a)),
            upper: .finite(f.integer(1, using: &a)), depth: snapshot.proofDepth, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCoordinateSemantics.self))
        let parent = try t.frame(source: source, field: f, support: [[whole]], semantics: [.authoredScalar], limits: limits, using: &a)
        let support = try parent.fullSelection(limits: limits, using: &a)
        let request = try parent.selection(intervals: requested, limits: limits, using: &a)
        let effective = try request.intersection(support, limits: limits, using: &a)
        let positive = try f.sign(of: snapshot.extent, using: &a) == .positive
        let window = try ExactParameterInterval.checked(field: f,
            lower: .finite(positive ? snapshot.start : snapshot.end), upper: .finite(positive ? snapshot.end : snapshot.start),
            depth: snapshot.proofDepth, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCoordinateSemantics.self))
        let childChart = try t.frame(source: source, field: f, support: [[window]], semantics: [.authoredScalar], limits: limits, using: &a)
        let childWindow = try childChart.fullSelection(limits: limits, using: &a)
        let gain = try f.dividing(f.integer(1, using: &a), snapshot.extent, using: &a)
        let offset = try f.negated(f.dividing(snapshot.start, snapshot.extent, using: &a), using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Int.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Value.self))
        let map = try t.affine(from: childWindow, to: parent, permutation: [0], gains: [gain], offsets: [offset], limits: limits, using: &a)
        let inverse = try t.inverse(map, limits: limits, using: &a)
        let restricted = try t.restrict(inverse, to: effective, limits: limits, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: restricted.image.axes[0].intervalCount, of: ExactParameterInterval<Value>.self))
        // This is the transformed selection at the child API boundary, not a
        // duplicated contact/result array or a second source decomposition.
        let childRequest = [Array(restricted.image.axes[0].intervals)]
        let childRelation = try OriginalCertifiedCoaxialCurveSurfaceRelation.resolve(source: snapshot.child,
            target: target, curveIntervals: childRequest, targetIntervals: targetIntervals,
            maximumPoints: maximumPoints, limits: limits, using: &a)
        var selected: [Contact] = []
        for step in 0..<childRelation.planeParameters.count {
            try a.consumeWork(1)
            let index = positive ? step : childRelation.planeParameters.count - 1 - step
            let childParameter = childRelation.planeParameters[index]
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Value.self))
            guard try childWindow.contains([childParameter], limits: limits, using: &a) else { continue }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Value.self))
            let parentParameter = try t.forward([childParameter], through: map, limits: limits, using: &a)[0]
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Value.self))
            guard try effective.contains([parentParameter], limits: limits, using: &a) else { continue }
            guard selected.count < maximumPoints else { throw NativeExactRelationFailure.resultLimit }
            let ordinal = try f.compare(childParameter, snapshot.child.original.planeRoot(at: 0, using: &a), using: &a) == .equal ? 0 : 1
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Contact.self))
            selected.append(.init(parameter: parentParameter, childParameter: childParameter, childOrdinal: ordinal))
        }
        var value = max(snapshot.proofDepth.value, childRelation.proofDepth.value)
        var coefficient = max(snapshot.proofDepth.coefficient, childRelation.proofDepth.coefficient)
        for axis in request.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        for axis in effective.axes { value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient) }
        let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
        try a.admitDepth(value: value, coefficient: coefficient)
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, OriginalCertifiedCoaxialCurveSurfaceRelation,
            Selection, Selection, Selection, OriginalParameterTransport<Source, Field>, [Contact], ExactScalarDepth, Int)>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let result = OriginalCertifiedPairLiftPlaneRelation(source: source, childRelation: childRelation,
            support: support, request: request, effective: effective, correspondence: map, selected: selected, proofDepth: depth, transportDepth: max(map.depth, restricted.depth))
        try a.checkpoint(); return result
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source)
        guard transportDepth <= limits.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try childRelation.admitProof(limits: limits, using: &a)
        try DefaultOriginalParameterTransporter<Source, Field>().admitted(correspondence, limits: limits, using: &a)
        try request.frame.require(limits, &a); try effective.frame.require(limits, &a)
        for axis in request.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        for axis in effective.axes { try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient) }
        try a.checkpoint()
    }
    public func parentUV<A: ExactScalarAdmission & ~Copyable>(contact: Int,
        cylinderCycle: OriginalParameterCycle, coneCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> [Value] {
        try admitProof(limits: limits, using: &a)
        guard contact >= 0, contact < selected.count else { throw OriginalDomainIdentityFailure.outsideSupport }
        return try childRelation.parentUV(parameter: selected[contact].childParameter,
            cylinderCycle: cylinderCycle, coneCycle: coneCycle, limits: limits, using: &a)
    }
    public func liftUV<A: ExactScalarAdmission & ~Copyable>(contact: Int, cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> ArraySlice<Value> {
        let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &a), using: &a)
        let uv = try parentUV(contact: contact, cylinderCycle: source.original.isConeRole ? zero : cycle,
            coneCycle: source.original.isConeRole ? cycle : zero, limits: limits, using: &a)
        let result = source.original.isConeRole ? uv[2..<4] : uv[0..<2]
        try a.checkpoint(); return result
    }
}
