#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact ordered field Q(pi), using pi's transcendence and rational enclosures.
public struct OriginalPiScalarDomain: OriginalPiGenerating {
    public typealias Value = OriginalPiValue
    public typealias Source = Value
    let owner: OriginalPiOwner
    public init<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) {
        owner = try Self.query(&admission) { a in
            let q = ExactRationalScalarDomain()
            let ring = try ExactPolynomialDomain(field:q,variableCount:1,using:&a)
            let one = try ring.constant(q.integer(1,using:&a),using:&a)
            let generator = try ring.variable(0,using:&a)
            let header = try exactScalarPayloadBytes(count:2,of:UnsafeRawPointer.self)
            let payload = MemoryLayout<(ExactRationalScalarDomain,ExactPolynomialDomain<ExactRationalScalarDomain>,
                ExactPolynomial<ExactRationalScalarDomain>,ExactPolynomial<ExactRationalScalarDomain>)>.stride
            let bytes = header.addingReportingOverflow(payload)
            guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes:bytes.partialValue)
            return OriginalPiOwner(rationals:q,ring:ring,one:one,generator:generator)
        }
    }
    static func query<A: ExactScalarAdmission & ~Copyable,R>(_ admission: inout A,
        _ body: (inout A) throws -> R) throws(ExactScalarFailure) -> R {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            let result = try body(&admission)
            try admission.checkpoint(); return result
        } catch let error as ExactScalarFailure { throw error }
        catch let error as ExactPolynomialFailure {
            switch error {
            case .scalar(let cause): throw cause
            case .incompatibleDomain: throw .incompatibleDomain
            case .countOverflow,.exponentOverflow: throw .countOverflow
            default: throw .admissionRejected(error)
            }
        } catch { throw .admissionRejected(error) }
    }
    func require<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value,_ a: inout A) throws(ExactScalarFailure) {
        try a.consumeWork(1)
        guard value.owner === owner else { throw .incompatibleDomain }
        let depth = try value.depth
        try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
    }
    func value<A: ExactScalarAdmission & ~Copyable>(_ numerator: ExactPolynomial<ExactRationalScalarDomain>,
        _ denominator: ExactPolynomial<ExactRationalScalarDomain>,_ a: inout A) throws -> Value {
        // A nonzero polynomial cannot vanish at transcendental pi.
        guard try !owner.ring.isZero(denominator,using:&a) else { throw ExactScalarFailure.divisionByZero }
        let depth = try ExactScalarDepth(value:max(numerator.depth.value,denominator.depth.value),
            coefficient:max(numerator.depth.coefficient,denominator.depth.coefficient))
        try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Value.self))
        return .init(owner:owner,numerator:numerator,denominator:denominator)
    }
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let x = copy input
        return try Self.query(&admission) { a in
            let depth = try x.depth
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            if x.owner === owner { return x }
            return try value(owner.ring.importing(x.numerator,using:&a),
                owner.ring.importing(x.denominator,using:&a),&a)
        }
    }
    public func pi<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in try value(owner.generator,owner.one,&a) }
    }
    public func integer<I: BinaryInteger,A: ExactScalarAdmission & ~Copyable>(_ source: I,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in try value(owner.ring.constant(owner.rationals.integer(source,using:&a),using:&a),owner.one,&a) }
    }
    public func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in try value(owner.ring.constant(owner.rationals.binary64(exactly:source,using:&a),using:&a),owner.one,&a) }
    }
}
