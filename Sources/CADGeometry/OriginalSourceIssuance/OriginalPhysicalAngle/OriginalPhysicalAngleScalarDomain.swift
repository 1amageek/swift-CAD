#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact arithmetic and ordering for one retained nonzero physical angle.
public struct OriginalPhysicalAngleScalarDomain: ExactPhysicalAngleCoefficients {
    public typealias Value = OriginalPhysicalAngleValue
    public typealias Source = Value
    let owner: OriginalPhysicalAngleOwner
    public var originalRadians: Double { owner.originalRadians }

    public init<A: ExactScalarAdmission & ~Copyable>(originalRadians: Double,
        using admission: inout A) throws(ExactScalarFailure) {
        owner = try Self.query(&admission) { a in
            guard originalRadians.isFinite, originalRadians != 0 else { throw ExactScalarFailure.invalidSource }
            let q = ExactRationalScalarDomain()
            let one = try q.integer(1, using: &a), two = try q.integer(2, using: &a)
            var argument = try q.dividing(q.binary64(exactly: originalRadians, using: &a), two, using: &a)
            let negative = try q.sign(of: argument, using: &a) == .negative
            if negative { argument = try q.negated(argument, using: &a) }
            var doublings = 0
            while try q.compare(argument, one, using: &a) != .less {
                try a.consumeWork(1)
                argument = try q.dividing(argument, two, using: &a)
                doublings = try Self.increment(doublings)
            }
            let ring = try ExactPolynomialDomain(field: q, variableCount: 1, using: &a)
            let constant = try ring.constant(one, using: &a), generator = try ring.variable(0, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalPhysicalAngleOwner.self))
            // Include the immutable heap owner's header and its complete stored payload.
            let header = try exactScalarPayloadBytes(count: 2, of: UnsafeRawPointer.self)
            let payload = MemoryLayout<(Double, ExactRationalScalarDomain,
                ExactPolynomialDomain<ExactRationalScalarDomain>, ExactRationalCoefficient, Int, Bool,
                ExactPolynomial<ExactRationalScalarDomain>, ExactPolynomial<ExactRationalScalarDomain>)>.stride
            let total = header.addingReportingOverflow(payload)
            guard !total.overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes: total.partialValue)
            return OriginalPhysicalAngleOwner(originalRadians: originalRadians, rationals: q, ring: ring,
                reducedArgument: argument, doublings: doublings, negative: negative, one: constant, generator: generator)
        }
    }
    public init<A: ExactScalarAdmission & ~Copyable>(retaining value: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) {
        let retained = copy value
        owner = try Self.query(&admission) { a in
            let depth = try retained.depth
            try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
            return retained.owner
        }
    }
    static func increment(_ count: Int) throws(ExactScalarFailure) -> Int {
        let next = count.addingReportingOverflow(1)
        guard !next.overflow else { throw .countOverflow }
        return next.partialValue
    }
    static func query<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        _ body: (inout A) throws -> R) throws(ExactScalarFailure) -> R {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            let result = try body(&admission)
            try admission.checkpoint()
            return result
        } catch let error as ExactScalarFailure { throw error }
        catch let error as ExactPolynomialFailure {
            switch error {
            case .scalar(let cause): throw cause
            case .incompatibleDomain: throw .incompatibleDomain
            case .countOverflow, .exponentOverflow: throw .countOverflow
            default: throw .admissionRejected(error)
            }
        } catch { throw .admissionRejected(error) }
    }
    func require<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value,
        _ admission: inout A) throws(ExactScalarFailure) {
        try admission.consumeWork(1)
        guard value.owner === owner else { throw .incompatibleDomain }
        let depth = try value.depth
        try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
    }
    func value<A: ExactScalarAdmission & ~Copyable>(
        _ numerator: ExactPolynomial<ExactRationalScalarDomain>,
        _ denominator: ExactPolynomial<ExactRationalScalarDomain>, _ a: inout A) throws -> Value {
        guard try !owner.ring.isZero(denominator, using: &a) else { throw ExactScalarFailure.divisionByZero }
        let ring = owner.ring, q = owner.rationals
        var n = numerator, d = denominator
        if try ring.isZero(n, using: &a) {
            d = owner.one
        } else if d.termCount != 1 || d.terms[0].powers[0] != 0 {
            // Cancelling exact common factors prevents coefficient-ordering work
            // from growing with the expression tree rather than its value.
            let common = try ring.greatestCommonDivisor(n, d, using: &a)
            n = try ring.dividedExactly(n, by: common, using: &a)
            d = try ring.dividedExactly(d, by: common, using: &a)
        }
        guard let leading = d.terms.first else { throw ExactScalarFailure.divisionByZero }
        if try q.compare(leading.coefficient, q.integer(1, using: &a), using: &a) != .equal {
            let scale = try q.dividing(q.integer(1, using: &a), leading.coefficient, using: &a)
            n = try ring.scaled(n, by: scale, using: &a)
            d = try ring.scaled(d, by: scale, using: &a)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Value.self))
        return .init(owner: owner, numerator: n, denominator: d)
    }
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let retained = copy source
        return try Self.query(&admission) { a in try require(retained, &a); return retained }
    }
    public func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in
            try value(owner.ring.constant(owner.rationals.integer(source, using: &a), using: &a), owner.one, &a)
        }
    }
    public func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in
            try value(owner.ring.constant(owner.rationals.binary64(exactly: source, using: &a), using: &a), owner.one, &a)
        }
    }
    public func sine<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in
            let denominator = try owner.ring.adding(owner.one,
                owner.ring.multiplying(owner.generator, owner.generator, using: &a), using: &a)
            return try value(owner.ring.scaled(owner.generator, by: owner.rationals.integer(2, using: &a), using: &a),
                denominator, &a)
        }
    }
    public func cosine<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value {
        try Self.query(&admission) { a in
            let square = try owner.ring.multiplying(owner.generator, owner.generator, using: &a)
            return try value(owner.ring.subtracting(owner.one, square, using: &a),
                owner.ring.adding(owner.one, square, using: &a), &a)
        }
    }
}
