import L0
import L1
import DI0
import DI
import SourceIssuer

public enum ComposedDomainFixtures {
    typealias F = ExactRationalScalarDomain
    struct Image<C: Sendable>: OriginalParameterImageSourceReading {
        let originalChild: OriginalSourceBinding<C>
        let gains: [Int], offsets: [Int], axes: [Int]
        var parameterCount: Int { gains.count }
        var hasSpatialAction: Bool { false }
        func childAxis(forOriginalAxis axis: Int) -> Int { axes[axis] }
        func originalGain<T: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
            in axis: Int, field: borrowing T, using a: inout A) throws(OriginalSourceIssuanceFailure) -> T.Value {
            do { return try field.integer(gains[axis], using: &a) } catch { throw .scalar(error) }
        }
        func originalOffset<T: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
            in axis: Int, field: borrowing T, using a: inout A) throws(OriginalSourceIssuanceFailure) -> T.Value {
            do { return try field.integer(offsets[axis], using: &a) } catch { throw .scalar(error) }
        }
        func originalSpatialCoefficient<T: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
            row: Int, column: Int, field: borrowing T, using a: inout A) throws(OriginalSourceIssuanceFailure) -> T.Value {
            do { return try field.integer(row == column ? 1 : 0, using: &a) } catch { throw .scalar(error) }
        }
    }
    struct Snapshot<S: Sendable>: OriginalSourceSnapshotting {
        let depth: Int
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing S,
            limits: OriginalSourceIssuanceLimits, using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<S> {
            do { try a.consumeWork(1) } catch { throw .scalar(error) }
            return .init(original: copy input, sourceDepth: depth)
        }
    }
    struct Spatial<C: Sendable>: OriginalSpatialSourceReading {
        let originalChild: OriginalSourceBinding<C>
        func spatialCoefficient(row: Int, column: Int) -> Int { row == column ? 1 : 0 }
    }
    struct Traversal<C: Sendable>: OriginalTraversalSourceReading {
        let originalChild: OriginalSourceBinding<C>
        let originalStart: ExactRationalCoefficient, originalEnd: ExactRationalCoefficient
    }
    static func bind<S: Sendable,A: ExactScalarAdmission & ~Copyable>(_ input: S, depth: Int,
        using a: inout A) throws -> OriginalSourceBinding<S> {
        try DefaultOriginalSourceBindingIssuer(provider: Snapshot<S>(depth: depth)).bind(input,
            limits: TransportFixtures.limits().source, using: &a)
    }
    static func occurrences<C: OriginalChartFamilyQuerying,A: ExactScalarAdmission & ~Copyable>(
        _ cover: C, tuple: [C.Field.Value], using a: inout A) throws -> Int {
        try cover.incident(at: tuple, limits: TransportFixtures.limits(), using: &a).count
    }
    public static func completeFamilies() throws {
        var a = try TransportFixtures.admission()
        let f = F(), l = try TransportFixtures.limits(), childSource = try TransportFixtures.binding(true)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,F>()
        let space = try issuer.prepare(source: childSource, field: f, limits: l, using: &a)
        let child = try issuer.issue(space: space, request: space.frame.fullSelection(limits: l, using: &a), limits: l, using: &a)
        let source = try bind(Image(originalChild: child.source, gains: [-2], offsets: [1], axes: [0]), depth: 1, using: &a)
        let composed = try DefaultOriginalParameterImageDomainIssuer<Image<NativeSnapshot>,OriginalBSplineDomainCover<NativeSnapshot,F>>()
            .issue(source: source, child: child, limits: l, using: &a)
        let half = try f.dividing(f.integer(1, using: &a), f.integer(2, using: &a), using: &a)
        try TransportFixtures.require(composed.integerFamilyRank == 1 && composed.templateCount == child.templateCount)
        if case .negativeInfinity = composed.support.axes[0].intervals[0].lower {} else { throw ExactScalarFailure.invalidEvidence }
        let seam = try f.negated(half, using: &a)
        try TransportFixtures.require(occurrences(composed, tuple: [seam], using: &a) == occurrences(child, tuple: [f.integer(2, using: &a)], using: &a))
        let incidents = try composed.incident(at: [seam], limits: l, using: &a)
        try TransportFixtures.require(incidents.count == 2)
        let p = try DefaultOriginalParameterTransporter<Image<NativeSnapshot>,F>().forward(
            [f.integer(2, using: &a)], through: incidents[0].correspondence, limits: l, using: &a)
        try TransportFixtures.require(f.compare(p[0], seam, using: &a) == .equal)
        let cycle = try OriginalParameterCycle(exact: f.integer(123456789, using: &a), using: &a)
        let lifted = try composed.member(template: 0, cycles: [cycle], limits: l, using: &a)
        try TransportFixtures.require(f.compare(lifted.child.cycles[0].original, f.integer(-123456789, using: &a), using: &a) == .equal)
        let nestedSource = try bind(Image(originalChild: source, gains: [3], offsets: [0], axes: [0]), depth: 2, using: &a)
        let nested = try DefaultOriginalParameterImageDomainIssuer<Image<Image<NativeSnapshot>>,OriginalAffineChildDomainCover<Image<NativeSnapshot>,OriginalBSplineDomainCover<NativeSnapshot,F>>>()
            .issue(source: nestedSource, child: composed, limits: l, using: &a)
        try TransportFixtures.require(occurrences(nested, tuple: [f.dividing(seam, f.integer(3, using: &a), using: &a)], using: &a) == 2)
        let spatialSource = try bind(Spatial(originalChild: child.source), depth: 1, using: &a)
        let spatial = try DefaultOriginalSpatialChildDomainIssuer<Spatial<NativeSnapshot>,OriginalBSplineDomainCover<NativeSnapshot,F>>()
            .issue(source: spatialSource, child: child, limits: l, using: &a)
        try TransportFixtures.require(occurrences(spatial, tuple: [f.integer(2, using: &a)], using: &a) == 2)
        let traversalSource = try bind(Traversal(originalChild: child.source,
            originalStart: f.integer(4, using: &a), originalEnd: f.integer(0, using: &a)), depth: 1, using: &a)
        let traversal = try DefaultOriginalTraversalDomainIssuer<Traversal<NativeSnapshot>,OriginalBSplineDomainCover<NativeSnapshot,F>>()
            .issue(source: traversalSource, child: child, limits: l, using: &a)
        try TransportFixtures.require(occurrences(traversal, tuple: [half], using: &a) == 2)
        try TransportFixtures.require(occurrences(traversal, tuple: [f.integer(2, using: &a)], using: &a) == 0)
        guard case .finite(let lower) = traversal.support.axes[0].intervals[0].lower else { throw ExactScalarFailure.invalidEvidence }
        try TransportFixtures.require(f.compare(lower, f.integer(0, using: &a), using: &a) == .equal)
        print("PASS M4 affine source-domain composition: reversed/nested image, spatial word, directed traversal, infinite lifts and closed seams")
    }
    public static func completePullbackAndFailures() throws {
        var a = try TransportFixtures.admission()
        let f = F(), l = try TransportFixtures.limits(), s = try TransportFixtures.binding()
        let native = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,F>()
        let space = try native.prepare(source: s, field: f, limits: l, using: &a)
        let point = try space.frame.selection(intervals: [[TransportFixtures.interval(0,0,using:&a)]], limits: l, using: &a)
        let child = try native.issue(space: space, request: point, limits: l, using: &a)
        let source = try bind(Image(originalChild: s, gains: [-1], offsets: [0], axes: [0]), depth: 1, using: &a)
        let issuer = DefaultOriginalParameterImageDomainIssuer<Image<NativeSnapshot>,OriginalBSplineDomainCover<NativeSnapshot,F>>()
        do { _ = try issuer.issue(source: source, child: child, limits: l, using: &a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.incompleteCoverage {}
        let selected = try issuer.issue(source: source, child: child, requested: [[TransportFixtures.interval(0,0,using:&a)]], limits: l, using: &a)
        try TransportFixtures.require(occurrences(selected, tuple: [f.integer(0,using:&a)], using: &a) == 1)
        let empty = try issuer.issue(source: source, child: child, requested: [[TransportFixtures.interval(2,3,using:&a)]], limits: l, using: &a)
        try TransportFixtures.require(empty.effective.isEmpty && occurrences(empty, tuple: [f.integer(2,using:&a)], using: &a) == 0)
        let foreign = try bind(Image(originalChild: TransportFixtures.binding(), gains: [1], offsets: [0], axes: [0]), depth: 1, using: &a)
        do { _ = try issuer.issue(source: foreign, child: child, limits: l, using: &a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let zero = try bind(Image(originalChild: s, gains: [0], offsets: [0], axes: [0]), depth: 1, using: &a)
        do { _ = try issuer.issue(source: zero, child: child, limits: l, using: &a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.singularTransport {}
        let requested = [[try TransportFixtures.interval(0,0,using:&a)]]
        var measured = try TransportFixtures.admission()
        _ = try issuer.issue(source:source,child:child,requested:requested,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try issuer.issue(source:source,child:child,requested:requested,limits:l,using:&exact)
        var belowWork = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try issuer.issue(source:source,child:child,requested:requested,limits:l,using:&belowWork); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var belowStorage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try issuer.issue(source:source,child:child,requested:requested,limits:l,using:&belowStorage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        var terminalBaseline = try TerminalAdmission()
        _ = try issuer.issue(source:source,child:child,requested:requested,limits:l,using:&terminalBaseline)
        var terminal = try TerminalAdmission(); terminal.cancelAt = terminalBaseline.checks
        do { _ = try issuer.issue(source:source,child:child,requested:requested,limits:l,using:&terminal); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var cancel = try TransportFixtures.admission(); cancel.cancel()
        do { _ = try issuer.issue(source: source, child: child, limits: l, using: &cancel); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var work = try TransportFixtures.admission(work:0)
        do { _ = try selected.incident(at: [f.integer(0,using:&a)], limits:l, using:&work); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var storage = try TransportFixtures.admission(storage:0)
        do { _ = try selected.incident(at: [f.integer(0,using:&a)], limits:l, using:&storage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        do { _ = try selected.incident(at: [f.integer(0,using:&a)], limits:TransportFixtures.limits(depth:0), using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        print("PASS M4 exact source pullback: uncovered scope refuses, singleton/empty succeed, foreign/zero/depth/work/storage/cancel fail")
    }
}
