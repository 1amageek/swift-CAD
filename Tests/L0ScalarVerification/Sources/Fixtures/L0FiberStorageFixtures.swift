@testable import L0

public enum L0FiberStorageFixtures {
    struct Gate: RationalAlgebraAdmitting {
        let limit: Int
        var words = 0
        var work = 0
        var requests: [Int] = []
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= 50_000_000 - work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            requests.append(count)
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
    static func words<T>(_ count: Int, _ type: T.Type) -> Int {
        (count * MemoryLayout<T>.stride + MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
    }
    static func rejectFirst(_ required: Int, _ operation: (inout Gate) throws -> Void) throws {
        var gate = Gate(limit: required - 1)
        do { try operation(&gate); preconditionFailure("Insufficient typed slot storage published success") }
        catch ExactScalarFailure.resourceLimit(.storage) {
            precondition(gate.words == 0 && gate.requests.first == required)
        }
    }
    static func bounded<T>(_ operation: (inout Gate) throws -> T) throws -> T {
        var baseline = Gate(limit: 50_000_000)
        let result = try operation(&baseline)
        precondition(baseline.words > 0)
        var constrained = Gate(limit: baseline.words - 1)
        do { _ = try operation(&constrained); preconditionFailure("Incomplete resource admission published success") }
        catch ExactScalarFailure.resourceLimit(.storage) {
            precondition(constrained.words <= constrained.limit && !constrained.requests.isEmpty)
        }
        var reused = Gate(limit: baseline.words)
        _ = try operation(&reused)
        precondition(reused.words == baseline.words)
        return result
    }
    public static func run() throws {
        var preparation = Gate(limit: 50_000_000)
        let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &preparation)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &preparation)
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &preparation)
        let law = try x.multiplied(by: x, usage: &preparation)
            .subtracting(.constant(two, usage: &preparation), usage: &preparation)
        let selections = try ExactUnivariateRootIsolator().isolate(law, lower: .one, upper: two,
            maximumDepth: 32, usage: &preparation)
        precondition(selections.count == 1)
        let root = try ExactAlgebraicRealRoot(polynomial: law, isolation: selections[0], usage: &preparation)
        let source = try v.multiplied(by: v, usage: &preparation).multiplied(by: v, usage: &preparation)
            .subtracting(v, usage: &preparation)
        let fiber = try bounded { try ExactAlgebraicFiberPolynomial(source: source, at: root,
            maximumDepth: 32, usage: &$0) }
        precondition(fiber.degree == 3 && fiber.coefficients.count == 2)
        let derivative = try bounded { try fiber.differentiated(usage: &$0) }
        precondition(derivative.degree == 2)
        _ = try bounded { try fiber.negated(usage: &$0) }
        try rejectFirst(words(fiber.coefficients.count, (Int, ExactAlgebraicFieldElement).self)) {
            _ = try fiber.negated(usage: &$0)
        }
        try rejectFirst(words(fiber.coefficients.count, Int.self)) {
            _ = try fiber.differentiated(usage: &$0)
        }
        let divisorSource = try v.subtracting(.constant(.one, usage: &preparation), usage: &preparation)
        let divisor = try ExactAlgebraicFiberPolynomial(source: divisorSource, at: root,
            maximumDepth: 32, usage: &preparation)
        try rejectFirst(words(fiber.coefficients.count, (Int, ExactAlgebraicFieldElement).self)) {
            _ = try fiber.divided(by: divisor, maximumDepth: 32, usage: &$0)
        }
        let division = try bounded { try fiber.divided(by: divisor, maximumDepth: 32, usage: &$0) }
        precondition(division.remainder.isZero && division.quotient.degree == 2)
        for station in [two.negated, .zero, .one, two] {
            let actual = try fiber.evaluated(at: station, usage: &preparation)
            let reconstructed = try division.quotient.evaluated(at: station, usage: &preparation)
                .multiplied(by: divisor.evaluated(at: station, usage: &preparation), usage: &preparation)
            let difference = try actual.subtracting(reconstructed, usage: &preparation)
            guard case .zero = try difference.sign(at: root, maximumDepth: 32, usage: &preparation) else {
                preconditionFailure("Fiber division changed the original polynomial")
            }
        }
        let gcd = try bounded { try ExactAlgebraicFiberPolynomial.gcd(fiber, derivative,
            maximumDepth: 32, usage: &$0) }
        precondition(gcd.degree == 0)
        let sequence = try bounded { try ExactAlgebraicFiberSturmSequence(fiber, maximumDepth: 32, usage: &$0) }
        let rootCount = try sequence.count(lower: two.negated, upper: two,
            excludesLower: false, excludesUpper: false, maximumDepth: 32, usage: &preparation)
        precondition(rootCount == 3)
        let constant = try ExactAlgebraicFiberPolynomial(source: .constant(.one, usage: &preparation),
            at: root, maximumDepth: 32, usage: &preparation)
        var constantGate = Gate(limit: 50_000_000)
        let constantSequence = try ExactAlgebraicFiberSturmSequence(constant, maximumDepth: 32, usage: &constantGate)
        precondition(constantSequence.chain.count == 1)
        precondition(constantGate.requests.last == words(1, ExactAlgebraicFiberPolynomial.self))
        for endpoints in [false, true] {
            let upper: ExactRationalCoefficient = endpoints ? .one : two
            let roots = try bounded { try ExactAlgebraicFiberRootIsolator.isolate(fiber,
                lower: upper.negated, upper: upper, maximumDepth: 32, usage: &$0) }
            precondition(roots.count == 3)
            for selected in roots {
                let count = try sequence.count(lower: selected.lower, upper: selected.upper,
                    excludesLower: selected.excludesLower, excludesUpper: selected.excludesUpper,
                    maximumDepth: 32, usage: &preparation)
                precondition(count == 1)
            }
            let pair = ExactAlgebraicPairAuthority(projectionRoot: root, fiber: fiber, fiberRoot: roots[0])
            let reconstructed = try bounded { try pair.originalFiberNumerator(usage: &$0) }
            precondition(reconstructed == source)
            let sign = try pair.sign(of: source, maximumDepth: 32, usage: &preparation)
            guard case .zero = sign else { preconditionFailure("Original pair lost its fiber root") }
        }
        let one = try ExactAlgebraicFieldElement(polynomial: .constant(.one, usage: &preparation), usage: &preparation)
        let linear = ExactAlgebraicFiberPolynomial(root: root, coefficients: [1: one])
        let pair = ExactAlgebraicPairAuthority(projectionRoot: root, fiber: linear,
            fiberRoot: .init(lower: .zero, upper: .zero, excludesLower: false, excludesUpper: false, isolationDepth: 0))
        try rejectFirst(words(1, (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self)) {
            _ = try pair.originalFiberNumerator(usage: &$0)
        }
        let exchanged = try bounded { try source.exchangedAxes(usage: &$0) }
        precondition(exchanged.uDegree == 3 && exchanged.vDegree == 0)
        let restricted = try bounded { try source.restricted(alongU: true, station: .one, usage: &$0) }
        precondition(restricted == exchanged)
    }
}
