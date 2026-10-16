import CADCore
@testable import CADGeometry
import Testing

@Suite("Whole original polynomial coprimality", .timeLimit(.minutes(1)))
struct IntersectionWholePolynomialCoprimalityTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private enum AdmissionFailure: Error, Equatable { case work, storage, unexpectedDepth }
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var maximumWork = 80_000_000
        var maximumStorage = 268_435_456
        var work = 0
        var storage = 0
        var cancelAtWork: Int?
        var cancelAtStorage: Int?
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw AdmissionFailure.work }
            work += count
            if work == cancelAtWork { withUnsafeCurrentTask { $0?.cancel() } }
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            guard count >= 0, count <= maximumStorage - storage else { throw AdmissionFailure.storage }
            storage += count
            if storage == cancelAtStorage { withUnsafeCurrentTask { $0?.cancel() } }
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value
 throw AdmissionFailure.unexpectedDepth 
                case .coefficient:
                    let depth = mapped.coefficient
 throw ExactScalarFailure.resourceLimit(.coefficientDepth) 
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }
    private struct Pair: Sendable {
        let first: Polynomial
        let second: Polynomial
    }
    private func unitPair(_ kind: Int, usage: inout Admission) throws -> Pair {
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        if kind == 0 {
            let first = try x.adding(y, usage: &usage).adding(z, usage: &usage)
            return Pair(first: first, second: try first.adding(one, usage: &usage))
        }
        let first = try x.multiplied(by: x, usage: &usage).adding(one, usage: &usage)
        if kind == 1 {
            return Pair(first: first, second: try y.multiplied(by: y, usage: &usage).adding(one, usage: &usage))
        }
        return Pair(first: first, second: try first.adding(one, usage: &usage))
    }
    private func contentPair(_ kind: Int, usage: inout Admission) throws
        -> (pair: Pair, content: Polynomial, firstQuotient: Polynomial, secondQuotient: Polynomial) {
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let two = try Polynomial.constant(variableCount: 3, value: .natural(2, usage: &usage), usage: &usage)
        let content: Polynomial
        if kind == 0 { content = try y.adding(two, usage: &usage) }
        else if kind == 1 { content = try x.adding(y, usage: &usage).adding(two, usage: &usage) }
        else { content = try x.scaled(by: .natural(65_537, usage: &usage), usage: &usage).adding(y, usage: &usage) }
        let firstQuotient = try z.subtracting(x, usage: &usage)
        let secondQuotient = try z.subtracting(one, usage: &usage)
        let first = try content.multiplied(by: firstQuotient, usage: &usage)
        let second = try content.multiplied(by: secondQuotient, usage: &usage)
        return (Pair(first: first, second: second), content, firstQuotient, secondQuotient)
    }
    private func refusedPair(_ kind: Int, usage: inout Admission) throws -> Pair {
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let p = try ExactRationalCoefficient.natural(65_537, usage: &usage)
        let first: Polynomial
        if kind == 0 { first = try x.adding(y.scaled(by: p, usage: &usage), usage: &usage) }
        else if kind == 1 {
            let reciprocal = try ExactRationalCoefficient.one.divided(by: p, usage: &usage)
            first = try x.adding(y.scaled(by: reciprocal, usage: &usage), usage: &usage)
        } else {
            let two = try Polynomial.constant(variableCount: 3, value: .natural(2, usage: &usage), usage: &usage)
            let leading = try x.multiplied(by: x.subtracting(one, usage: &usage), usage: &usage)
                .multiplied(by: x.subtracting(two, usage: &usage), usage: &usage)
            first = try leading.multiplied(by: y, usage: &usage).adding(x, usage: &usage)
        }
        return Pair(first: first, second: try first.adding(one, usage: &usage))
    }

    @Test(arguments: [0, 1, 2])
    func wholeUnitIdentitiesCoverSharedAndDisjointSupports(kind: Int) throws {
        var preparation = Admission()
        let pair = try unitPair(kind, usage: &preparation)
        let unit = try Polynomial.constant(variableCount: 3, value: .one, usage: &preparation)
        if kind != 1 {
            // Their exact difference is one, so every common divisor is a unit.
            let difference = try pair.second.subtracting(pair.first, usage: &preparation)
            #expect(difference == unit)
        }
        let aliases = (pair.first, pair.second)
        var usage = Admission()
        let actual = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &usage)
        #expect(actual == unit)
        #expect(pair.first == aliases.0 && pair.second == aliases.1)
        if kind == 1 {
            // These nonconstant inputs live in disjoint coordinate rings.
            let zero = try Polynomial.zero(variableCount: 3)
            let zeroGCD = try ExactIntersectionPolynomialGCD.gcd(zero, pair.first, usage: &usage)
            let expected = try pair.first.monic(usage: &preparation)
            #expect(zeroGCD == expected)
            let constantGCD = try ExactIntersectionPolynomialGCD.gcd(unit, pair.second, usage: &usage)
            #expect(constantGCD == unit)
        }
    }

    @Test(arguments: [0, 1, 2])
    func oneAxisUnitCannotDiscardOriginalContentOrCrossAxisFactors(kind: Int) throws {
        var preparation = Admission()
        let fixture = try contentPair(kind, usage: &preparation)
        let firstQuotient = try fixture.pair.first.dividedExactly(by: fixture.content, usage: &preparation)
        let secondQuotient = try fixture.pair.second.dividedExactly(by: fixture.content, usage: &preparation)
        #expect(firstQuotient == fixture.firstQuotient && secondQuotient == fixture.secondQuotient)
        // z-x and z-1 are distinct irreducible linear polynomials. Their
        // common content H is the exact GCD, including H depending on x,y.
        // At x=0,y=1, both original z degrees survive and the z probe is unit.
        let point: [ExactRationalCoefficient] = [.zero, .one, .zero]
        let firstCoefficients = try fixture.pair.first.axisCoefficients(at: 2, usage: &preparation)
        let secondCoefficients = try fixture.pair.second.axisCoefficients(at: 2, usage: &preparation)
        var first: [ExactRationalCoefficient] = [], second: [ExactRationalCoefficient] = []
        for coefficient in firstCoefficients { first.append(try coefficient.evaluated(at: point, usage: &preparation)) }
        for coefficient in secondCoefficients { second.append(try coefficient.evaluated(at: point, usage: &preparation)) }
        #expect(first.count == 2 && second.count == 2)
        #expect(try ExactIntersectionModularCoprimality.certifies(first, second, usage: &preparation))
        var usage = Admission()
        let actual = try ExactIntersectionPolynomialGCD.gcd(fixture.pair.first, fixture.pair.second, usage: &usage)
        let expected = try fixture.content.monic(usage: &preparation)
        #expect(actual == expected && !actual.isConstant)
    }

    @Test(arguments: [0, 1, 2])
    func invalidModularDegreeAndDenominatorProbesKeepTheExactFallback(kind: Int) throws {
        var preparation = Admission()
        let pair = try refusedPair(kind, usage: &preparation)
        let unit = try Polynomial.constant(variableCount: 3, value: .one, usage: &preparation)
        let difference = try pair.second.subtracting(pair.first, usage: &preparation)
        #expect(difference == unit)
        let coefficients = try pair.first.axisCoefficients(at: 1, usage: &preparation)
        let leading = try #require(coefficients.last)
        if kind < 2 {
            let point: [ExactRationalCoefficient] = [.zero, .zero, .zero]
            let value = try leading.evaluated(at: point, usage: &preparation)
            let accepted = try ExactIntersectionModularCoprimality.certifies([.zero, value], [.one, value], usage: &preparation)
            #expect(!accepted)
        } else {
            // Original y degree is one, but x(x-1)(x-2) vanishes at
            // every existing x station: 1, 0 and coordinate[0]+2.
            for station in [0, 1, 2] {
                let value = try ExactRationalCoefficient.natural(station, usage: &preparation)
                let point: [ExactRationalCoefficient] = [value, .zero, .zero]
                let specialized = try leading.evaluated(at: point, usage: &preparation)
                #expect(specialized.isZero)
            }
        }
        var usage = Admission()
        let actual = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &usage)
        #expect(actual == unit)
    }

    @Test func callerWorkStorageAndOriginalRingFailuresRemainExplicit() throws {
        var preparation = Admission()
        let pair = try unitPair(0, usage: &preparation)
        var measured = Admission()
        _ = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &measured)
        var exact = Admission(); exact.maximumWork = measured.work; exact.maximumStorage = measured.storage
        let complete = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &exact)
        #expect(complete.isConstant && !complete.isZero)
        for allowance in [0, measured.work - 1] {
            var usage = Admission(); usage.maximumWork = allowance
            geometryTestExpectFailure({ if case .work? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
                try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &usage)
            }
            #expect(usage.work <= allowance)
        }
        for allowance in [0, measured.storage - 1] {
            var usage = Admission(); usage.maximumStorage = allowance
            geometryTestExpectFailure({ if case .storage? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
                try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &usage)
            }
            #expect(usage.storage <= allowance)
        }
        let wrongRing = try Polynomial.zero(variableCount: 2)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try ExactIntersectionPolynomialGCD.gcd(pair.first, wrongRing, usage: &preparation)
        }
    }

    @Test(arguments: [0, 1, 2])
    func completeWholeUnitCertificateCannotSurviveCallerCancellation(callback: Int) async throws {
        var preparation = Admission()
        let pair = try unitPair(0, usage: &preparation)
        var measured = Admission()
        _ = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &measured)
        let finalWork = measured.work, finalStorage = measured.storage
        let cancelled = try await Task {
            var usage = Admission()
            if callback == 0 { withUnsafeCurrentTask { $0?.cancel() } }
            if callback == 1 { usage.cancelAtWork = finalWork }
            if callback == 2 { usage.cancelAtStorage = finalStorage }
            do {
                _ = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &usage)
                Issue.record("A cancelled whole-polynomial unit certificate published a GCD.")
                return false
            } catch let error where geometryTestIsCancelled(error) {
                if callback == 0 { return usage.work == 0 && usage.storage == 0 }
                return callback == 1 ? usage.work == finalWork : usage.storage == finalStorage
            }
        }.value
        #expect(cancelled)
    }
}
