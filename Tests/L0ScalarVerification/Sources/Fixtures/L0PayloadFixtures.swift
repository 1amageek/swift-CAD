import L0

public enum L0PayloadFixtures {
    static func check(_ condition: Bool) { precondition(condition, "L0 payload assertion failed") }
    struct WordGate: RationalAlgebraAdmitting {
        let limit: Int
        var words = 0
        var work = 0
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= 50_000_000 - work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= limit - words else { throw ExactScalarFailure.resourceLimit(.storage) }
            words += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...24).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }

    public static func run() throws {
        check(try exactScalarPayloadBytes(count: 0, of: UInt64.self) == 0)
        check(try exactScalarPayloadBytes(count: 7, of: UInt8.self) == 7)
        for count in [-1, Int.max] {
            do {
                _ = try exactScalarPayloadBytes(count: count, of: UInt64.self)
                preconditionFailure("Invalid payload count published success")
            } catch ExactScalarFailure.countOverflow {}
        }
        var preparation = WordGate(limit: 50_000_000)
        let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &preparation)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &preparation)
        let stride = MemoryLayout<(ExactBivariatePolynomial.Power, ExactRationalCoefficient)>.stride
        check(try exactScalarPayloadBytes(count: 1,
            of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self) == stride)
        let required = (stride + MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
        for operation in 0..<4 {
            var rejected = WordGate(limit: required - 1)
            do {
                if operation == 0 { _ = try x.quotientAndRemainder(dividingBy: one, usage: &rejected) }
                else if operation == 1 { _ = try one.quotientAndRemainder(dividingBy: x, usage: &rejected) }
                else if operation == 2 { _ = try ExactBivariatePolynomial.monomial(u: 1, v: 0, coefficient: .one, usage: &rejected) }
                else { _ = try x.exchangedAxes(usage: &rejected) }
                preconditionFailure("Insufficient monomial payload storage published success")
            } catch ExactScalarFailure.resourceLimit(.storage) {
                precondition(rejected.words == 0)
                if operation != 3 { precondition(rejected.work > 0) }
            }
        }
        let division = try x.quotientAndRemainder(dividingBy: one, usage: &preparation)
        precondition(division.quotient == x && division.remainder.isZero)
        let remainder = try one.quotientAndRemainder(dividingBy: x, usage: &preparation)
        precondition(remainder.quotient.isZero && remainder.remainder == one)

        let two = try ExactRationalCoefficient.originalDouble(2, usage: &preparation)
        let cubic = try x.multiplied(by: x, usage: &preparation).multiplied(by: x, usage: &preparation)
            .subtracting(.constant(two, usage: &preparation), usage: &preparation)
        let roots = try ExactUnivariateRootIsolator().isolate(cubic, lower: .one, upper: two,
            maximumDepth: 32, usage: &preparation)
        precondition(roots.count == 1)
        let root = try ExactAlgebraicRealRoot(polynomial: cubic, isolation: roots[0], usage: &preparation)
        let limits = try ExactScalarLimits(work: 50_000_000, storageBytes: 200_000_000, valueDepth: 32, coefficientDepth: 24)
        var admission = ExactScalarLedger(limits: limits)
        let field = try OriginalExactScalarDomain(root: root, axis: .value,
            maximumValueDepth: 32, maximumCoefficientDepth: 24, using: &admission)
        let alpha = try field.generator(using: &admission)
        let expression = try field.subtracting(field.multiplying(alpha, alpha, using: &admission),
            field.integer(3, using: &admission), using: &admission)
        var baseline = ExactScalarLedger(limits: limits)
        let sign = try field.sign(of: expression, using: &baseline)
        precondition(sign == .negative && baseline.storageBytes > 0)
        var constrained = ExactScalarLedger(limits: try .init(work: limits.work,
            storageBytes: baseline.storageBytes - 1, valueDepth: limits.valueDepth, coefficientDepth: limits.coefficientDepth))
        do {
            _ = try field.sign(of: expression, using: &constrained)
            preconditionFailure("Incomplete algebraic sign published success")
        } catch ExactScalarFailure.resourceLimit(.storage) {
            precondition(constrained.work > 0 && constrained.storageBytes <= constrained.limits.storageBytes)
        }
        let reused = try field.sign(of: expression, using: &admission)
        precondition(reused == .negative)
    }
}
