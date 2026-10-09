import L0
import L1
import L2
import L3
import L4
import L5

/// A valid exact rational field whose cancelled zero retains causal depth.
public enum GraphDepthFixtures {
    struct Value: Sendable {
        let raw: ExactRationalCoefficient
        let depth: Int
    }
    struct Field: ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting {
        typealias Source = Value
        let rational = ExactRationalScalarDomain()
        func admit<A:ExactScalarAdmission & ~Copyable>(_ value:Value,_ a:inout A) throws(ExactScalarFailure) { try a.admitDepth(value:value.depth,coefficient:0) }
        func integer<I:BinaryInteger,A:ExactScalarAdmission & ~Copyable>(_ value:I,using a:inout A) throws(ExactScalarFailure)->Value { .init(raw:try rational.integer(value,using:&a),depth:0) }
        func binary64<A:ExactScalarAdmission & ~Copyable>(exactly value:Double,using a:inout A) throws(ExactScalarFailure)->Value { .init(raw:try rational.binary64(exactly:value,using:&a),depth:0) }
        func importing<A:ExactScalarAdmission & ~Copyable>(_ value:borrowing Value,using a:inout A) throws(ExactScalarFailure)->Value { try admit(value,&a);return copy value }
        func negated<A:ExactScalarAdmission & ~Copyable>(_ value:borrowing Value,using a:inout A) throws(ExactScalarFailure)->Value { try admit(value,&a);return .init(raw:try rational.negated(value.raw,using:&a),depth:value.depth) }
        func adding<A:ExactScalarAdmission & ~Copyable>(_ l:borrowing Value,_ r:borrowing Value,using a:inout A) throws(ExactScalarFailure)->Value { try admit(l,&a);try admit(r,&a);return .init(raw:try rational.adding(l.raw,r.raw,using:&a),depth:max(l.depth,r.depth)) }
        func subtracting<A:ExactScalarAdmission & ~Copyable>(_ l:borrowing Value,_ r:borrowing Value,using a:inout A) throws(ExactScalarFailure)->Value { try admit(l,&a);try admit(r,&a);return .init(raw:try rational.subtracting(l.raw,r.raw,using:&a),depth:max(l.depth,r.depth)) }
        func multiplying<A:ExactScalarAdmission & ~Copyable>(_ l:borrowing Value,_ r:borrowing Value,using a:inout A) throws(ExactScalarFailure)->Value { try admit(l,&a);try admit(r,&a);return .init(raw:try rational.multiplying(l.raw,r.raw,using:&a),depth:max(l.depth,r.depth)) }
        func dividing<A:ExactScalarAdmission & ~Copyable>(_ l:borrowing Value,_ r:borrowing Value,using a:inout A) throws(ExactScalarFailure)->Value { try admit(l,&a);try admit(r,&a);return .init(raw:try rational.dividing(l.raw,r.raw,using:&a),depth:max(l.depth,r.depth)) }
        func sign<A:ExactScalarAdmission & ~Copyable>(of value:borrowing Value,using a:inout A) throws(ExactScalarFailure)->ExactSign { try admit(value,&a);return try rational.sign(of:value.raw,using:&a) }
        func compare<A:ExactScalarAdmission & ~Copyable>(_ l:borrowing Value,_ r:borrowing Value,using a:inout A) throws(ExactScalarFailure)->ExactOrder { try admit(l,&a);try admit(r,&a);return try rational.compare(l.raw,r.raw,using:&a) }
    }
    public static func inheritedDepth() throws {
        typealias Scalar = ExactAlgebraicScalarDomain<Field>
        typealias Cells = ExactRealCellDomain<Field>
        typealias Topology = ExactRealTopologyDomain<Field,Cells>
        var a = try RelationFixtures.ledger()
        let base = Field(), f = try Scalar.base(field:base,maximumExtensionLevel:10,using:&a)
        let curve = try Cells(field:f,variableCount:1,using:&a), surface = try Cells(field:f,variableCount:2,using:&a)
        let deep = Value(raw:try base.rational.integer(0,using:&a),depth:20)
        let coefficient = try f.importingBase(deep,using:&a)
        let cp = curve.polynomials, sp = surface.polynomials
        let cz = try cp.constant(coefficient,using:&a), sz = try sp.zero(using:&a)
        let roots = try ExactRealRootDomain(field:f,using:&a)
        let zero = try f.integer(0,using:&a), point = try roots.domain(lower:.finite(zero),upper:.finite(zero),using:&a)
        let cs = try curve.bind(polynomials:[cz,cp.zero(using:&a),cp.zero(using:&a),cp.constant(f.integer(1,using:&a),using:&a)],domains:[point],using:&a)
        let ss = try surface.bind(polynomials:[sz,sz,sz,sp.constant(f.integer(1,using:&a),using:&a)],domains:[point,point],using:&a)
        let first = try curve.predicate(instructions:[.literal(true)],for:cs,using:&a)
        let second = try surface.predicate(instructions:[.literal(true)],for:ss,using:&a)
        let domain = ExactParametricRelationDomain<Field,Cells,Topology>(cells:Cells.self,topology:Topology(cells:Cells.self))
        let source = try domain.compile(kind:.curveSurface,first:domain.graph(from:first,parameterCount:1,using:&a),second:domain.graph(from:second,parameterCount:2,using:&a),using:&a)
        try RelationFixtures.require(first.depth.value == 20)
        var low = ExactScalarLedger(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:19,coefficientDepth:400))
        var rejected=false
        do { _ = try domain.resolve(source,cellLimits:.init(maximumStoredCells:2000,maximumRootsPerStack:100),topologyLimits:.init(maximumGeneratedCells:2000,maximumRootsPerStack:100,maximumClosures:100,maximumAttachmentPieces:2000,maximumComponents:100),using:&low) }
        catch ExactParametricRelationFailure.scalar(.resourceLimit(.valueDepth)) { rejected=true }
        let result = try domain.resolve(source,cellLimits:.init(maximumStoredCells:2000,maximumRootsPerStack:100),topologyLimits:.init(maximumGeneratedCells:2000,maximumRootsPerStack:100,maximumClosures:100,maximumAttachmentPieces:2000,maximumComponents:100),using:&a)
        try RelationFixtures.require(source.depth.value == 20 && result.depth.value >= 20)
        var reuseRejected=false
        do { try result.admitProof(using:&low) }
        catch ExactParametricRelationFailure.scalar(.resourceLimit(.valueDepth)) { reuseRejected=true }
        try RelationFixtures.require(reuseRejected)
        print("DEPTH input=\(first.depth.value) normalized=\(source.predicate.depth.value) rejected=\(rejected)")
        try RelationFixtures.require(rejected)
    }
}
