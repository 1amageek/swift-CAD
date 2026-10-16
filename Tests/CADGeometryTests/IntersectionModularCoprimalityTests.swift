import CADCore
@testable import CADGeometry
import Testing

@Suite("Exact modular specialization coprimality", .timeLimit(.minutes(1)))
struct IntersectionModularCoprimalityTests {
    private enum AdmissionFailure: Error, Equatable { case work, storage }
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var maximumWork = Int.max
        var maximumStorage = Int.max
        var work = 0
        var storage = 0
        var cancelAtWork: Int?
        var cancelAtStorage: Int?
        var requests: [Int]?
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
            requests?.append(count)
        
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
 
                case .coefficient:
                    let depth = mapped.coefficient
 throw ExactScalarFailure.resourceLimit(.coefficientDepth) 
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }

    private func rational(_ numerator: Int, _ denominator: Int = 1,
        usage: inout Admission) throws -> ExactRationalCoefficient {
        let magnitude = try ExactRationalCoefficient.natural(abs(numerator), usage: &usage)
        let value = try magnitude.divided(by: .natural(denominator, usage: &usage), usage: &usage)
        return numerator < 0 ? value.negated : value
    }

    private func polynomial(_ coefficients: [ExactRationalCoefficient], variableCount: Int = 2,
        axis: Int = 1, usage: inout Admission) throws -> ExactIntersectionPolynomial {
        var result = try ExactIntersectionPolynomial.zero(variableCount: variableCount)
        for (exponent, coefficient) in coefficients.enumerated() where !coefficient.isZero {
            let term = try ExactIntersectionPolynomial.monomial(variableCount: variableCount,
                power: .coordinate(at: axis, exponent: exponent, variableCount: variableCount, usage: &usage),
                coefficient: coefficient, usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    // Exact observed pair; source log SHA c53da35338c084e9b1c4240949954900fd5a24992693c1f9d931ee78a71c4a02.
    private func actualPair(usage: inout Admission) throws
        -> (first: [ExactRationalCoefficient], second: [ExactRationalCoefficient]) {
        let firstWords: [(Int, [UInt32], [UInt32])] = [
            (1, [1], [1]),
            (-1, [2158783290, 45074368], [2951351673, 2588793]),
            (1, [2338800965, 994186059], [264120427, 7766381]),
            (-1, [2413297616, 3094877986, 2], [792361281, 23299143]),
            (1, [516177899, 2488119243, 5], [792361281, 23299143]),
            (-1, [2248616150, 3334463907, 8], [2377083843, 69897429]),
            (-1, [363386345, 3623220128, 39], [2377083843, 69897429]),
            (1, [229730428, 905181384, 33], [792361281, 23299143]),
            (-1, [3610410468, 2986515688, 79], [2377083843, 69897429]),
            (-1, [3964239312, 2162805373, 37], [2377083843, 69897429]),
            (1, [409237372, 1193180867, 13], [264120427, 7766381]),
            (-1, [3778099360, 3754803753, 22], [792361281, 23299143]),
            (-1, [2228682336, 4066044862], [2951351673, 2588793]),
            (1, [3750420864, 2700562640, 15], [792361281, 23299143]),
            (-1, [4044548416, 2844681209, 14], [2377083843, 69897429]),
            (-1, [2940812288, 1803386572, 5], [2377083843, 69897429]),
            (1, [2550476800, 2311502850, 1], [792361281, 23299143]),
            (-1, [3553742848, 4279825902], [2377083843, 69897429]),
            (1, [2137489408, 237682717], [2377083843, 69897429]),
        ]
        let secondWords: [(Int, [UInt32], [UInt32])] = [
            (1, [1], [1]),
            (-1, [1719833789, 4197178806, 449099], [3364190661, 981482297, 25309]),
            (1, [2559714170, 1682342369, 10481971], [1502637391, 2944446893, 75927]),
            (-1, [3471155506, 1464183091, 139893834], [212944877, 243406088, 227783]),
            (1, [4047735365, 614705570, 386022444], [212944877, 243406088, 227783]),
            (-1, [3650921509, 98661891, 655028307], [212944877, 243406088, 227783]),
            (1, [1928787764, 3497860759, 572437280], [212944877, 243406088, 227783]),
            (1, [2285554256, 4100949165, 81133398], [212944877, 243406088, 227783]),
            (-1, [3210745316, 3412363215, 807242280], [212944877, 243406088, 227783]),
            (1, [513491636, 1080051185, 270864283], [1502637391, 2944446893, 75927]),
            (-1, [1159692960, 3928584683, 46865576], [1502637391, 2944446893, 75927]),
            (-1, [567459008, 2598258441, 122530790], [1502637391, 2944446893, 75927]),
            (1, [801289344, 930897892, 305486965], [212944877, 243406088, 227783]),
            (-1, [2150222784, 3603337798, 47071836], [212944877, 243406088, 227783]),
            (-1, [1012921088, 2947303045, 53011823], [212944877, 243406088, 227783]),
            (1, [650807296, 794724418, 30767717], [212944877, 243406088, 227783]),
            (-1, [2647945216, 59251662, 5951482], [212944877, 243406088, 227783]),
            (1, [477265920, 3225874522, 316213], [212944877, 243406088, 227783]),
        ]
        let first = try firstWords.reversed().map {
            try ExactRationalCoefficient(canonicalSign: $0.0, numeratorWords: $0.1,
                denominatorWords: $0.2, usage: &usage)
        }
        let second = try secondWords.reversed().map {
            try ExactRationalCoefficient(canonicalSign: $0.0, numeratorWords: $0.1,
                denominatorWords: $0.2, usage: &usage)
        }
        return (first, second)
    }

    // Exact observed axis-5 pair; source log SHA 37509bc524094df2d9bc2f0d45d13b768fd23550c4f6718ce9fbce16a99636d4.
    private func actualAxisFivePair(usage: inout Admission) throws
        -> (first: ExactIntersectionPolynomial, second: ExactIntersectionPolynomial) {
        let first: [(Int, Int, Int, Int, Int)] = [
            (0, 1, 2, 1, 1),
            (3, 0, 2, 9, 4),
            (2, 0, 2, -27, 4),
            (1, 0, 2, 7, 2),
            (0, 2, 1, -2, 3),
            (3, 1, 1, -1, 2),
            (2, 1, 1, 3, 2),
            (1, 1, 1, -1, 3),
            (0, 1, 1, -4, 3),
            (3, 0, 1, -4, 1),
            (2, 0, 1, 52, 3),
            (1, 0, 1, -52, 3),
            (0, 0, 1, 16, 3),
            (0, 2, 0, 2, 3),
            (3, 1, 0, 1, 2),
            (2, 1, 0, -5, 2),
            (1, 1, 0, 7, 3),
            (0, 1, 0, -2, 3),
            (3, 0, 0, -5, 4),
            (2, 0, 0, -7, 12),
            (1, 0, 0, 17, 6),
            (0, 0, 0, -4, 3),
        ]
        let second: [(Int, Int, Int, Int, Int)] = [
            (4, 4, 1, 1, 1),
            (3, 4, 1, -4, 1),
            (2, 4, 1, 52, 9),
            (1, 4, 1, -32, 9),
            (5, 3, 1, 2, 3),
            (4, 3, 1, -22, 3),
            (3, 3, 1, 202, 9),
            (2, 3, 1, -262, 9),
            (1, 3, 1, 244, 9),
            (0, 3, 1, -32, 3),
            (10, 2, 1, -9, 16),
            (9, 2, 1, 45, 8),
            (8, 2, 1, -353, 16),
            (7, 2, 1, 83, 2),
            (6, 2, 1, -149, 3),
            (5, 2, 1, 93, 1),
            (4, 2, 1, -1159, 6),
            (3, 2, 1, 644, 3),
            (2, 2, 1, -442, 3),
            (1, 2, 1, 200, 3),
            (0, 2, 1, -40, 3),
            (10, 1, 1, 9, 8),
            (9, 1, 1, -39, 2),
            (8, 1, 1, 947, 8),
            (7, 1, 1, -4831, 12),
            (6, 1, 1, 11405, 12),
            (5, 1, 1, -32041, 18),
            (4, 1, 1, 23632, 9),
            (3, 1, 1, -7994, 3),
            (2, 1, 1, 14992, 9),
            (1, 1, 1, -5192, 9),
            (0, 1, 1, 256, 3),
            (10, 0, 1, -981, 16),
            (9, 0, 1, 4971, 8),
            (8, 0, 1, -43821, 16),
            (7, 0, 1, 83053, 12),
            (6, 0, 1, -198331, 18),
            (5, 0, 1, 102386, 9),
            (4, 0, 1, -136393, 18),
            (3, 0, 1, 28174, 9),
            (2, 0, 1, -6526, 9),
            (1, 0, 1, 640, 9),
            (4, 4, 0, -1, 1),
            (3, 4, 0, 4, 1),
            (2, 4, 0, -52, 9),
            (1, 4, 0, 32, 9),
            (6, 3, 0, 3, 2),
            (5, 3, 0, -29, 3),
            (4, 3, 0, 71, 2),
            (3, 3, 0, -676, 9),
            (2, 3, 0, 706, 9),
            (1, 3, 0, -400, 9),
            (0, 3, 0, 32, 3),
            (10, 2, 0, 9, 16),
            (9, 2, 0, -27, 4),
            (8, 2, 0, 515, 16),
            (7, 2, 0, -373, 8),
            (6, 2, 0, -2591, 24),
            (5, 2, 0, 5725, 12),
            (4, 2, 0, -1395, 2),
            (3, 2, 0, 1663, 3),
            (2, 2, 0, -266, 1),
            (1, 2, 0, 76, 1),
            (0, 2, 0, -32, 3),
            (10, 1, 0, 207, 8),
            (9, 1, 0, -993, 4),
            (8, 1, 0, 7855, 8),
            (7, 1, 0, -12427, 6),
            (6, 1, 0, 2573, 1),
            (5, 1, 0, -17794, 9),
            (4, 1, 0, 7658, 9),
            (3, 1, 0, -16, 1),
            (2, 1, 0, -1972, 9),
            (1, 1, 0, 1064, 9),
            (0, 1, 0, -64, 3),
            (10, 0, 0, 549, 16),
            (9, 0, 0, -276, 1),
            (8, 0, 0, 15039, 16),
            (7, 0, 0, -45149, 24),
            (6, 0, 0, 185479, 72),
            (5, 0, 0, -90635, 36),
            (4, 0, 0, 30541, 18),
            (3, 0, 0, -6571, 9),
            (2, 0, 0, 1588, 9),
            (1, 0, 0, -160, 9),
        ]
        return (try axisFivePolynomial(first, usage: &usage), try axisFivePolynomial(second, usage: &usage))
    }

    // Exact observed four-role PRS tuple; source log SHA 149ef074c4e7b3afd0dd14b15164e2f52b1a4f9b4418fefba53dd758b005d9f1.
    private func actualUnitStage(usage: inout Admission) throws
        -> (currentA: ExactIntersectionPolynomial, currentB: ExactIntersectionPolynomial,
            originalA: ExactIntersectionPolynomial, originalB: ExactIntersectionPolynomial) {
        let currentA: [(Int, Int, Int, Int, Int)] = [
            (4, 0, 1, 1, 1),
            (3, 0, 1, -4, 1),
            (2, 0, 1, 44, 9),
            (1, 0, 1, -16, 9),
            (4, 1, 0, -1, 9),
            (3, 1, 0, 4, 9),
            (2, 1, 0, -4, 9),
            (4, 0, 0, -8, 9),
            (3, 0, 0, 128, 27),
            (2, 0, 0, -8, 1),
            (1, 0, 0, 16, 3),
            (0, 0, 0, -32, 27),
        ]
        let currentB: [(Int, Int, Int, Int, Int)] = [
            (0, 0, 0, 1, 1),
        ]
        let originalA: [(Int, Int, Int, Int, Int)] = [
            (0, 0, 1, 1, 1),
            (0, 1, 0, -1, 1),
        ]
        let originalB: [(Int, Int, Int, Int, Int)] = [
            (4, 0, 1, 1, 1),
            (3, 0, 1, -4, 1),
            (2, 0, 1, 44, 9),
            (1, 0, 1, -16, 9),
            (4, 1, 0, -1, 9),
            (3, 1, 0, 4, 9),
            (2, 1, 0, -4, 9),
            (4, 0, 0, -8, 9),
            (3, 0, 0, 128, 27),
            (2, 0, 0, -8, 1),
            (1, 0, 0, 16, 3),
            (0, 0, 0, -32, 27),
        ]
        return (try axisFivePolynomial(currentA, usage: &usage),
            try axisFivePolynomial(currentB, usage: &usage),
            try axisFivePolynomial(originalA, usage: &usage),
            try axisFivePolynomial(originalB, usage: &usage))
    }

    private func axisFivePolynomial(_ rows: [(Int, Int, Int, Int, Int)],
        usage: inout Admission) throws -> ExactIntersectionPolynomial {
        var result = try ExactIntersectionPolynomial.zero(variableCount: 7)
        for row in rows {
            let term = try ExactIntersectionPolynomial.monomial(variableCount: 7,
                power: .init((row.0, 0, 0, row.1, 0, row.2, 0, 0, 0), variableCount: 7),
                coefficient: rational(row.3, row.4, usage: &usage), usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    @Test func degreePreservingRationalUnitGCDAndResidueBounds() throws {
        var usage = Admission()
        let first = try [rational(-1, 2, usage: &usage), .zero, .one]
        let second = try [rational(1, 3, usage: &usage), .one]
        // The only root of the linear polynomial is -1/3; substituting it
        // into z^2 - 1/2 gives -7/18, so the exact GCD is a unit.
        #expect(try ExactIntersectionModularCoprimality.certifies(first, second, usage: &usage))
        let a = try polynomial(first, usage: &usage), b = try polynomial(second, usage: &usage)
        let gcd = try ExactIntersectionPolynomialGCD.gcd(a, b, usage: &usage)
        #expect(try gcd.matches(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage))
        let maximum = try rational(65_536, usage: &usage)
        let preceding = try rational(65_535, usage: &usage)
        // Equal nonzero leading residues at their maximum value exercise
        // the UInt64 product bound while the constant difference is one.
        #expect(try ExactIntersectionModularCoprimality.certifies(
            [maximum, .zero, maximum], [preceding, .zero, maximum], usage: &usage))
        #expect((2...256).allSatisfy { ExactIntersectionModularCoprimality.prime % UInt64($0) != 0 })
    }

    @Test func genuineCommonFactorIsNotCertifiedAndExactGCDRetainsIt() throws {
        var usage = Admission()
        let two = try rational(2, usage: &usage)
        let three = try rational(3, usage: &usage)
        #expect(try !ExactIntersectionModularCoprimality.certifies(
            [.one, .zero, .one], [two, .one, two, .one], usage: &usage))
        let factor = try polynomial([.one, .zero, .one], usage: &usage)
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let a = try polynomial([two, .zero, .one], usage: &usage).adding(x, usage: &usage)
        let b = try polynomial([three, .zero, .one], usage: &usage).adding(x, usage: &usage)
        let first = try factor.multiplied(by: a, usage: &usage)
        let second = try factor.multiplied(by: b, usage: &usage)
        let gcd = try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &usage)
        #expect(try gcd.matches(factor, usage: &usage))
        #expect(try gcd.multiplied(by: first.dividedExactly(by: gcd, usage: &usage), usage: &usage)
            .matches(first, usage: &usage))
        #expect(try gcd.multiplied(by: second.dividedExactly(by: gcd, usage: &usage), usage: &usage)
            .matches(second, usage: &usage))
    }

    @Test func primitiveCertificatePreservesCommonContentAndSquareFreeNormalization() throws {
        var usage = Admission()
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let content = try x.adding(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage)
        let a = try polynomial([.one, .zero, .one], usage: &usage).adding(x, usage: &usage)
        let b = try a.adding(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage)
        let first = try content.multiplied(by: a, usage: &usage)
        let second = try content.multiplied(by: b, usage: &usage)
        let gcd = try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &usage)
        #expect(try gcd.matches(content.monic(usage: &usage), usage: &usage))
        let repeated = try a.multiplied(by: a, usage: &usage)
        let squareFree = try ExactIntersectionPolynomialGCD.squareFree(repeated, usage: &usage)
        #expect(try squareFree.matches(a.monic(usage: &usage), usage: &usage))
        #expect(try squareFree.multiplied(by: squareFree, usage: &usage).matches(repeated, usage: &usage))
    }

    @Test(arguments: [0, 1, 2])
    func invalidPrimeWitnessFallsBackToTheExactUnitGCD(kind: Int) throws {
        var usage = Admission()
        let p = try rational(65_537, usage: &usage)
        let reciprocal = try rational(1, 65_537, usage: &usage)
        let two = try rational(2, usage: &usage)
        let first: [ExactRationalCoefficient]
        let second: [ExactRationalCoefficient]
        switch kind {
        case 0: // A rational denominator is not a unit modulo the prime.
            first = [reciprocal, .zero, .one]; second = [two, .zero, .one]
        case 1: // Both rational degrees are two; one modular degree drops.
            first = [.one, p, .one]; second = [two, .zero, p]
        default: // Distinct rational polynomials become identical modulo p.
            first = [.one, .zero, .one]
            second = [try p.adding(.one, usage: &usage), .zero, .one]
        }
        #expect(try !ExactIntersectionModularCoprimality.certifies(first, second, usage: &usage))
        let a = try polynomial(first, usage: &usage)
        var b = try polynomial(second, usage: &usage)
        if kind == 1 {
            // Keep the leading coefficient symbolic so monic normalization
            // retains it: uniform x=1 gives the same leading residue zero.
            let x = try ExactIntersectionPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
            let z2 = try polynomial([.zero, .zero, .one], usage: &usage)
            b = try polynomial([two, .zero, p.subtracting(.one, usage: &usage)], usage: &usage)
                .adding(z2.multiplied(by: x, usage: &usage), usage: &usage)
        }
        let gcd = try ExactIntersectionPolynomialGCD.gcd(a, b, usage: &usage)
        #expect(try gcd.matches(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage))
    }

    @Test(arguments: [false, true])
    func multiwordSignedRationalReductionDoesNotTruncateSource(negative: Bool) throws {
        var usage = Admission()
        // (2^65 - 1)/(2^32 + 1) is reduced and equals 1/2 modulo 65537.
        let large = try ExactRationalCoefficient(canonicalSign: negative ? -1 : 1,
            numeratorWords: [UInt32.max, UInt32.max, 1], denominatorWords: [1, 1], usage: &usage)
        let half = try rational(negative ? -1 : 1, 2, usage: &usage)
        let two = try rational(2, usage: &usage)
        #expect(large != half)
        #expect(try !ExactIntersectionModularCoprimality.certifies([large, .one], [half, .one], usage: &usage))
        #expect(try ExactIntersectionModularCoprimality.certifies([large, .one], [two, .one], usage: &usage))
    }

    @Test func independentCallerLimitsAndCompleteReplacementBufferAdmission() throws {
        var preparation = Admission()
        let two = try rational(2, usage: &preparation)
        let first: [ExactRationalCoefficient] = [.one, .zero, .one]
        let second: [ExactRationalCoefficient] = [two, .zero, .one]
        var measured = Admission(); measured.requests = []
        #expect(try ExactIntersectionModularCoprimality.certifies(first, second, usage: &measured))
        let fullBuffer = (3 * MemoryLayout<UInt64>.stride + MemoryLayout<UInt32>.stride - 1)
            / MemoryLayout<UInt32>.stride
        // Two input buffers and two complete three-coefficient COW remainders.
        let probeWords = (MemoryLayout<ExactIntersectionModularCoprimality.Probe>.stride
            + MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
        #expect(measured.requests == [fullBuffer, fullBuffer, fullBuffer, fullBuffer, probeWords])
        for allowance in [0, measured.work - 1] {
            var limited = Admission(); limited.maximumWork = allowance
            geometryTestExpectFailure({ if case .work? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
                try ExactIntersectionModularCoprimality.certifies(first, second, usage: &limited)
            }
            #expect(limited.work <= allowance)
        }
        for allowance in [0, 2 * fullBuffer + fullBuffer - 1, measured.storage - 1] {
            var limited = Admission(); limited.maximumStorage = allowance
            geometryTestExpectFailure({ if case .storage? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
                try ExactIntersectionModularCoprimality.certifies(first, second, usage: &limited)
            }
            #expect(limited.storage <= allowance)
        }
    }

    @Test(arguments: [false, true])
    func finalAdmissionCancellationCannotPublishEitherProbeOutcome(unit: Bool) async throws {
        var preparation = Admission()
        let constant = try rational(unit ? 2 : 1, usage: &preparation)
        let first: [ExactRationalCoefficient] = [.one, .zero, .one]
        let second: [ExactRationalCoefficient] = [constant, .zero, .one]
        var measured = Admission()
        #expect(try ExactIntersectionModularCoprimality.certifies(first, second, usage: &measured) == unit)
        let finalWork = measured.work
        let cancelled = try await Task {
            var usage = Admission(); usage.cancelAtWork = finalWork
            do {
                _ = try ExactIntersectionModularCoprimality.certifies(first, second, usage: &usage)
                Issue.record("A cancelled modular probe published a result.")
                return false
            } catch let error where geometryTestIsCancelled(error) { return usage.work == finalWork }
        }.value
        #expect(cancelled)
    }

    @Test func precancellationAndRetainedRingFailureRemainExplicit() async throws {
        let charges = try await Task {
            var usage = Admission()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ExactIntersectionModularCoprimality.certifies([.one], [.one], usage: &usage)
                Issue.record("A precancelled modular probe published a result.")
            } catch let error where geometryTestIsCancelled(error) { }
            return (usage.work, usage.storage)
        }.value
        #expect(charges.0 == 0 && charges.1 == 0)
        var usage = Admission()
        let first = try polynomial([.one, .zero, .one], usage: &usage)
        let second = try polynomial([.one, .zero, .one], variableCount: 3, axis: 2, usage: &usage)
        do {
            _ = try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &usage)
            Issue.record("A GCD across distinct retained rings was accepted.")
        } catch let error as KernelError { #expect(error.code == .intersectionFailure) }
    }

    @Test func actualPrimitivePairCertifiesTheExactDegreeTenFactorWithinOriginalBudget() throws {
        var preparation = Admission()
        let pair = try actualPair(usage: &preparation)
        let first = try polynomial(pair.first, variableCount: 7, axis: 0, usage: &preparation)
        let second = try polynomial(pair.second, variableCount: 7, axis: 0, usage: &preparation)
        // (z - 8/3)(z + 2/3)(z - 1)^4(z^2 - 2z - 2)^2.
        let expectedCoefficients = try [-64, 56, 308, -376, -400, 770, -91, -448, 326]
            .map { try rational($0, 9, usage: &preparation) }
            + [rational(-10, usage: &preparation), .one]
        let expected = try polynomial(expectedCoefficients, variableCount: 7, axis: 0, usage: &preparation)
        var usage = Admission(); usage.maximumWork = 80_000_000; usage.maximumStorage = 268_435_456
        let probe = try geometryTestRequire(ExactIntersectionModularCoprimality.prepare(pair.first, pair.second, usage: &usage))
        #expect(probe.degree == 10)
        let receipt = try geometryTestRequire(ExactIntersectionModularCoprimality.factorReceipt(probe,
            first: pair.first, second: pair.second, denominatorBound: 16, usage: &usage))
        #expect(receipt.coefficients == expectedCoefficients)
        let firstQuotient = try polynomial(receipt.firstQuotient, variableCount: 7, axis: 0, usage: &usage)
        let secondQuotient = try polynomial(receipt.secondQuotient, variableCount: 7, axis: 0, usage: &usage)
        #expect(try expected.multiplied(by: firstQuotient, usage: &usage).matches(first, usage: &usage))
        #expect(try expected.multiplied(by: secondQuotient, usage: &usage).matches(second, usage: &usage))
        let gcd = try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &usage)
        #expect(try gcd.matches(expected, usage: &usage))
        #expect(usage.work > 0 && usage.work <= 80_000_000 && usage.storage <= 268_435_456)
    }

    @Test func factorProposalsRefuseBadPrimesMissingReconstructionAndAccidentalFactors() throws {
        var usage = Admission()
        let p = try rational(65_537, usage: &usage)
        let reciprocal = try rational(1, 65_537, usage: &usage)
        #expect(try ExactIntersectionModularCoprimality.prepare([reciprocal, .zero, .one],
            [.one, .zero, .one], usage: &usage)?.degree == nil)
        let first: [ExactRationalCoefficient] = [.one, .zero, .one]
        let second: [ExactRationalCoefficient] = [try p.adding(.one, usage: &usage), .zero, .one]
        let falseProbe = try geometryTestRequire(ExactIntersectionModularCoprimality.prepare(first, second, usage: &usage))
        #expect(falseProbe.degree == 2)
        #expect(try ExactIntersectionModularCoprimality.factorReceipt(falseProbe,
            first: first, second: second, denominatorBound: 1, usage: &usage)?.coefficients.count == nil)
        let coefficient = try rational(3_000, usage: &usage)
        let missed: [ExactRationalCoefficient] = [coefficient, .zero, .one]
        let missedProbe = try geometryTestRequire(ExactIntersectionModularCoprimality.prepare(missed, missed, usage: &usage))
        // This box cannot reconstruct residue 3000: the Euclidean candidate
        // has denominator 22, beyond D=16. A proposal refusal is explicit.
        #expect(try ExactIntersectionModularCoprimality.factorReceipt(missedProbe,
            first: missed, second: missed, denominatorBound: 16, usage: &usage)?.coefficients.count == nil)
    }

    @Test func factorReceiptAdmissionAndFinalCancellationRemainCallerOwned() async throws {
        var preparation = Admission()
        let two = try rational(2, usage: &preparation), three = try rational(3, usage: &preparation)
        let four = try rational(4, usage: &preparation)
        let first: [ExactRationalCoefficient] = [two, .zero, three, .zero, .one]
        let second: [ExactRationalCoefficient] = [three, .zero, four, .zero, .one]
        let probe = try geometryTestRequire(ExactIntersectionModularCoprimality.prepare(first, second, usage: &preparation))
        var measured = Admission()
        #expect(try ExactIntersectionModularCoprimality.factorReceipt(probe,
            first: first, second: second, denominatorBound: 1, usage: &measured)?.coefficients.count == 3)
        for allowance in [0, measured.work - 1] {
            var limited = Admission(); limited.maximumWork = allowance
            geometryTestExpectFailure({ if case .work? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
                try ExactIntersectionModularCoprimality.factorReceipt(probe,
                    first: first, second: second, denominatorBound: 1, usage: &limited)
            }
            #expect(limited.work <= allowance)
        }
        for allowance in [0, measured.storage - 1] {
            var limited = Admission(); limited.maximumStorage = allowance
            geometryTestExpectFailure({ if case .storage? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
                try ExactIntersectionModularCoprimality.factorReceipt(probe,
                    first: first, second: second, denominatorBound: 1, usage: &limited)
            }
            #expect(limited.storage <= allowance)
        }
        let finalStorage = measured.storage
        let cancelled = try await Task {
            var limited = Admission(); limited.cancelAtStorage = finalStorage
            do {
                _ = try ExactIntersectionModularCoprimality.factorReceipt(probe,
                    first: first, second: second, denominatorBound: 1, usage: &limited)
                Issue.record("A final factor receipt callback cancelled the task but a result was published.")
                return false
            } catch let error where geometryTestIsCancelled(error) { return limited.storage == finalStorage }
        }.value
        #expect(cancelled)
    }

    @Test func actualAxisFivePairUsesADegreePreservingDistinctProposalWithinOriginalBudget() throws {
        var preparation = Admission()
        let pair = try actualAxisFivePair(usage: &preparation)
        #expect(try pair.first.orderedTerms(usage: &preparation).count == 22)
        #expect(try pair.second.orderedTerms(usage: &preparation).count == 85)
        let firstCoefficients = try pair.first.axisCoefficients(at: 5, usage: &preparation)
        let secondCoefficients = try pair.second.axisCoefficients(at: 5, usage: &preparation)
        #expect(firstCoefficients.count == 3 && secondCoefficients.count == 2)
        let firstLeading = try #require(firstCoefficients.last)
        let secondLeading = try #require(secondCoefficients.last)
        for station in [ExactRationalCoefficient.one, .zero] {
            let point = Array(repeating: station, count: 7)
            #expect(try firstLeading.evaluated(at: point, usage: &preparation).isZero)
            #expect(try secondLeading.evaluated(at: point, usage: &preparation).isZero)
        }
        // The actual active coordinates are x0=2, x3=5; both retained main
        // degrees survive and the same modular unit certificate succeeds.
        let distinct = try [2, 3, 4, 5, 6, 7, 8].map { try rational($0, usage: &preparation) }
        let first = try firstCoefficients.map { try $0.evaluated(at: distinct, usage: &preparation) }
        let second = try secondCoefficients.map { try $0.evaluated(at: distinct, usage: &preparation) }
        #expect(first.last?.isZero == false && second.last?.isZero == false)
        #expect(try ExactIntersectionModularCoprimality.certifies(first, second, usage: &preparation))
        var usage = Admission(); usage.maximumWork = 80_000_000; usage.maximumStorage = 268_435_456
        let gcd = try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &usage)
        #expect(try gcd.matches(.constant(variableCount: 7, value: .one, usage: &usage), usage: &usage))
        #expect(usage.work > 0 && usage.work <= 80_000_000 && usage.storage <= 268_435_456)
        var noWork = Admission(); noWork.maximumWork = 0
        geometryTestExpectFailure({ if case .work? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
            try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &noWork)
        }
        var noStorage = Admission(); noStorage.maximumStorage = 0
        geometryTestExpectFailure({ if case .storage? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
            try ExactIntersectionPolynomialGCD.gcd(pair.first, pair.second, usage: &noStorage)
        }
    }

    @Test(arguments: [false, true])
    func actualPrimitiveUnitTerminationPreservesContentAndFinalAdmission(sharedContent: Bool) async throws {
        var preparation = Admission()
        let roles = try actualUnitStage(usage: &preparation)
        #expect(try roles.currentA.orderedTerms(usage: &preparation).count == 12)
        #expect(try roles.currentB.orderedTerms(usage: &preparation).count == 1)
        #expect(try roles.originalA.orderedTerms(usage: &preparation).count == 2)
        #expect(try roles.originalB.orderedTerms(usage: &preparation).count == 12)
        let one = try ExactIntersectionPolynomial.constant(variableCount: 7, value: .one, usage: &preparation)
        #expect(try roles.currentA.matches(roles.originalB, usage: &preparation))
        #expect(try roles.currentB.matches(one, usage: &preparation))
        let content = sharedContent
            ? try axisFivePolynomial([(1, 0, 0, 1, 1), (0, 0, 0, 1, 1)], usage: &preparation) : one
        let first = try roles.originalA.multiplied(by: content, usage: &preparation)
        let second = try roles.originalB.multiplied(by: content, usage: &preparation)
        // Uniform one has the common specialized factor z-1; uniform zero
        // and coordinate[i]=i+2 drop the second main degree. Exact PRS must
        // therefore reach the observed constant primitive remainder.
        var measured = Admission(); measured.maximumWork = 80_000_000; measured.maximumStorage = 268_435_456
        let result = try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &measured)
        #expect(try result.matches(content, usage: &preparation))
        #expect(measured.work > 0 && measured.work <= 80_000_000 && measured.storage <= 268_435_456)
        var noFinalWork = Admission(); noFinalWork.maximumWork = measured.work - 1
        geometryTestExpectFailure({ if case .work? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
            try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &noFinalWork)
        }
        #expect(noFinalWork.work == measured.work - 1)
        var noFinalStorage = Admission(); noFinalStorage.maximumStorage = measured.storage - 1
        geometryTestExpectFailure({ if case .storage? = geometryTestOriginalFailure($0) as? AdmissionFailure { true } else { false } }) {
            try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &noFinalStorage)
        }
        #expect(noFinalStorage.storage <= noFinalStorage.maximumStorage)
        let finalWork = measured.work
        let cancelled = try await Task {
            var usage = Admission(); usage.cancelAtWork = finalWork
            do {
                _ = try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &usage)
                Issue.record("The terminal primitive unit admission cancelled the task but published a GCD.")
                return false
            } catch let error where geometryTestIsCancelled(error) { return usage.work == finalWork }
        }.value
        #expect(cancelled)
    }
}
