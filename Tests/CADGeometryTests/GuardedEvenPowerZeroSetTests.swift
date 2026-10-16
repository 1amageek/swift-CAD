import CADCore
@testable import CADGeometry
import Testing

@Suite("Guarded pure even-power real zero certificates", .timeLimit(.minutes(1)))
struct GuardedEvenPowerZeroSetTests {
    private enum AdmissionFailure: Error { case work, storage }
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var maximumWork = 2_000_000
        var maximumStorage = 2_000_000
        var work = 0
        var storage = 0
        var cancelAtStorage: Int?
        var storageRequests: [Int]?
        var lastStorageRequest = 0
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw AdmissionFailure.work }
            work += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            lastStorageRequest = count
            storageRequests?.append(count)
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

            guard (0...24).contains(depth) else { throw AdmissionFailure.work }
        
                case .coefficient:
                    let depth = mapped.coefficient
 throw ExactScalarFailure.resourceLimit(.coefficientDepth) 
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }

    private func term(_ axis: Int, exponent: Int, coefficient: ExactRationalCoefficient = .one,
        variableCount: Int = 3, usage: inout Admission) throws -> ExactIntersectionPolynomial {
        try .monomial(variableCount: variableCount,
            power: .coordinate(at: axis, exponent: exponent, variableCount: variableCount, usage: &usage),
            coefficient: coefficient, usage: &usage)
    }

    @Test(arguments: [false, true])
    func certificateRetainsExactTermsAndBothRealZeroImplications(negative: Bool) throws {
        var usage = Admission()
        let sign = negative ? ExactRationalCoefficient.one.negated : .one
        let weighted = try ExactRationalCoefficient.originalDouble(0.5, usage: &usage).multiplied(by: sign, usage: &usage)
        let equation = try term(0, exponent: 2, coefficient: sign, usage: &usage)
            .adding(term(0, exponent: 6, coefficient: weighted, usage: &usage), usage: &usage)
            .adding(term(1, exponent: 4, coefficient: weighted, usage: &usage), usage: &usage)
        let proof = try geometryTestRequire(OriginalEvenPowerEquationZeroSet.prepare(equation, equationIndex: 7, usage: &usage))
        #expect(proof.equationIndex == 7 && proof.guardedEquation == equation)
        #expect(proof.coefficientSign == (negative ? -1 : 1))
        #expect(proof.terms.count == 3 && proof.coordinates.count == 2)
        #expect(Set(proof.coordinates) == [0, 1])
        #expect(try proof.reconstruction.matches(equation, usage: &usage))
        for retained in proof.terms {
            #expect(retained.coefficient.canonicalSign == proof.coefficientSign)
            #expect(retained.exponent > 0 && retained.exponent % 2 == 0)
            for axis in 0..<equation.variableCount {
                #expect(try retained.power.exponent(at: axis) == (axis == retained.coordinate ? retained.exponent : 0))
            }
        }
        for (index, coordinate) in proof.coordinates.enumerated() {
            #expect(try proof.coordinateEquations[index].matches(
                .coordinate(variableCount: 3, at: coordinate, usage: &usage), usage: &usage))
        }
        // Free coordinates, either sign of active coordinates and repeated powers
        // exercise both implications independently of polynomial reconstruction.
        for x in [-1.0, 0, 0.5] {
            for y in [-0.5, 0, 1.0] {
                for free in [-1.0, 0, 1.0] {
                    let point = try [x, y, free].map { try ExactRationalCoefficient.originalDouble($0, usage: &usage) }
                    let originalZero = try equation.evaluated(at: point, usage: &usage).isZero
                    var coordinatesZero = true
                    for coordinateEquation in proof.coordinateEquations {
                        if try !coordinateEquation.evaluated(at: point, usage: &usage).isZero { coordinatesZero = false }
                    }
                    #expect(originalZero == coordinatesZero)
                    #expect(originalZero == (x == 0 && y == 0))
                }
            }
        }
    }

    @Test func rejectsEveryUnprovedTermShapeAndKeepsTheDefaultPath() throws {
        var usage = Admission()
        let x2 = try term(0, exponent: 2, usage: &usage)
        let y2 = try term(1, exponent: 2, usage: &usage)
        let mixedSigns = try x2.subtracting(y2, usage: &usage)
        let odd = try x2.adding(term(1, exponent: 3, usage: &usage), usage: &usage)
        let constant = try x2.adding(.constant(variableCount: 3, value: .one, usage: &usage), usage: &usage)
        let product = try x2.multiplied(by: y2, usage: &usage)
        let refused = [mixedSigns, odd, constant, product,
            try ExactIntersectionPolynomial.zero(variableCount: 3),
            try .constant(variableCount: 3, value: .one, usage: &usage)]
        for equation in refused {
            #expect(try OriginalEvenPowerEquationZeroSet.prepare(equation, equationIndex: 0, usage: &usage) == nil)
            let guarded = try OriginalGuardedIntersectionEquations.prepare(equations: [equation],
                denominatorGuards: [], variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &usage)
            #expect(guarded.evenPowerZeroSets.isEmpty && guarded.normalizedEquations == [equation])
        }
        let valid = try x2.adding(y2, usage: &usage)
        let defaultPath = try OriginalGuardedIntersectionEquations.prepare(equations: [valid],
            denominatorGuards: [], variableCount: 3, squareFreeRepeatedFactors: true, usage: &usage)
        #expect(defaultPath.evenPowerZeroSets.isEmpty && defaultPath.normalizedEquations == [valid])
        let pureRepeated = try term(0, exponent: 6, usage: &usage)
        let optedIn = try OriginalGuardedIntersectionEquations.prepare(equations: [pureRepeated],
            denominatorGuards: [], variableCount: 3, squareFreeRepeatedFactors: true,
            reducePureEvenPowerZeroSets: true, usage: &usage)
        #expect(optedIn.evenPowerZeroSets.count == 1 && optedIn.zeroSetEquivalences.isEmpty)
    }

    @Test func guardDivisionPrecedesReductionAndOriginalJacobianRankSurvivesExpansion() throws {
        var usage = Admission()
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
        let sum = try term(0, exponent: 2, usage: &usage)
            .adding(term(1, exponent: 4, coefficient: two, usage: &usage), usage: &usage)
        let z = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let guardPolynomial = try z.adding(.constant(variableCount: 3, value: .one, usage: &usage), usage: &usage)
        let authored = try sum.multiplied(by: guardPolynomial, usage: &usage)
        let equations = [authored, z]
        let guarded = try OriginalGuardedIntersectionEquations.prepare(equations: equations,
            denominatorGuards: [guardPolynomial], variableCount: 3, squareFreeRepeatedFactors: true,
            reducePureEvenPowerZeroSets: true, usage: &usage)
        let proof = try #require(guarded.evenPowerZeroSets.first)
        #expect(proof.equationIndex == 0 && proof.guardedEquation == sum)
        #expect(guarded.originalEquations == equations && guarded.denominatorGuards == [guardPolynomial])
        #expect(guarded.divisions.count == 1 && guarded.normalizedEquations.count == 3)
        #expect(guarded.zeroSetEquivalences.isEmpty)
        for division in guarded.divisions {
            #expect(try division.factor.multiplied(by: division.quotient, usage: &usage)
                .matches(division.dividend, usage: &usage))
            #expect(try division.factor.multiplied(by: division.guardQuotient, usage: &usage)
                .matches(guarded.guardProduct, usage: &usage))
        }
        let excluded = [ExactRationalCoefficient.one, .zero, .one.negated]
        #expect(try authored.evaluated(at: excluded, usage: &usage).isZero)
        #expect(try guarded.guardProduct.evaluated(at: excluded, usage: &usage).isZero)
        #expect(try !sum.evaluated(at: excluded, usage: &usage).isZero)
        let domain = try OriginalRationalParameterDomain(.init(lower: -1, upper: 1), usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: guarded.normalizedEquations,
            variableCount: 3, usage: &usage)
        let strata = try OriginalRationalIntersectionStrata.prepare(ideal: ideal,
            exactDomains: [domain, domain, domain], nonzeroPolynomials: guarded.denominatorGuards,
            thomEncoding: true, originalRankEquations: guarded.originalEquations, isolatedOnly: true,
            pruneExcludedPrefixes: true, maximumDepth: 24, usage: &usage)
        #expect(strata.jacobian.equations == equations && strata.partition.solutionCells.count == 1)
        #expect(strata.strata.first?.originalJacobianRank == 1)
        let index = try #require(strata.partition.solutionCells.first)
        let cell = strata.partition.cells[index]
        #expect(cell.dimension == 0)
        for coordinate in cell.coordinates {
            #expect(try coordinate.sign(maximumDepth: 24, usage: &usage) == .zero)
        }
    }

    @Test func independentCallerLimitsCoverProofRetentionAndExpandedEquationStorage() throws {
        var preparation = Admission()
        let equation = try term(0, exponent: 2, usage: &preparation)
            .adding(term(1, exponent: 4, usage: &preparation), usage: &preparation)
        var measured = Admission()
        _ = try OriginalGuardedIntersectionEquations.prepare(equations: [equation], denominatorGuards: [],
            variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &measured)
        #expect(measured.work > 0 && measured.storage > 0)
        for allowance in [0, measured.work / 2, measured.work - 1] {
            var limited = Admission(); limited.maximumWork = allowance
            geometryTestExpectFailure({ geometryTestOriginalFailure($0) is AdmissionFailure }) {
                try OriginalGuardedIntersectionEquations.prepare(equations: [equation], denominatorGuards: [],
                    variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &limited)
            }
            #expect(limited.work <= allowance)
        }
        for allowance in [0, measured.storage / 2, measured.storage - 1] {
            var limited = Admission(); limited.maximumStorage = allowance
            geometryTestExpectFailure({ geometryTestOriginalFailure($0) is AdmissionFailure }) {
                try OriginalGuardedIntersectionEquations.prepare(equations: [equation], denominatorGuards: [],
                    variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &limited)
            }
            #expect(limited.storage <= allowance)
        }
    }

    @Test func replacementBuffersAdmitTheirFullAllocationBeforePublishingExpandedEquations() throws {
        var preparation = Admission()
        let first = try term(0, exponent: 2, usage: &preparation)
            .adding(term(1, exponent: 4, usage: &preparation), usage: &preparation)
        let second = try term(2, exponent: 2, usage: &preparation)
        var measured = Admission(); measured.storageRequests = []
        let result = try OriginalGuardedIntersectionEquations.prepare(equations: [first, second],
            denominatorGuards: [], variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &measured)
        #expect(result.normalizedEquations.count == 3 && result.evenPowerZeroSets.count == 2)
        let wordStride = MemoryLayout<UInt32>.stride
        let proofWords = (MemoryLayout<OriginalEvenPowerEquationZeroSet>.stride + wordStride - 1) / wordStride
        let fullProofBufferWords = (2 * MemoryLayout<OriginalEvenPowerEquationZeroSet>.stride + wordStride - 1) / wordStride
        let fullEquationBufferWords = (4 * MemoryLayout<ExactIntersectionPolynomial>.stride + wordStride - 1) / wordStride
        let receiptWords = (MemoryLayout<OriginalGuardedIntersectionEquations>.stride + wordStride - 1) / wordStride
        let requests = try geometryTestRequire(measured.storageRequests)
        // After the final certificate's own retention, both previously nonempty
        // collections must admit full replacement buffers before the receipt.
        #expect(Array(requests.suffix(4)) == [proofWords, fullProofBufferWords, fullEquationBufferWords, receiptWords])
        for offset in [2, 3] {
            let index = requests.count - offset
            let precedingWords = requests[..<index].reduce(0, +)
            var limited = Admission(); limited.maximumStorage = precedingWords + requests[index] - 1
            geometryTestExpectFailure({ geometryTestOriginalFailure($0) is AdmissionFailure }) {
                try OriginalGuardedIntersectionEquations.prepare(equations: [first, second],
                    denominatorGuards: [], variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &limited)
            }
            #expect(limited.storage == precedingWords && limited.lastStorageRequest == requests[index])
        }
    }

    @Test func overflowCoordinatesRetainTheSamePurePowerContract() throws {
        var usage = Admission()
        let equation = try term(10, exponent: 2, variableCount: 12, usage: &usage)
            .adding(term(11, exponent: 4, variableCount: 12, usage: &usage), usage: &usage)
        let proof = try geometryTestRequire(OriginalEvenPowerEquationZeroSet.prepare(equation, equationIndex: 0, usage: &usage))
        #expect(Set(proof.coordinates) == [10, 11])
        #expect(try proof.reconstruction.matches(equation, usage: &usage))
        for (index, coordinate) in proof.coordinates.enumerated() {
            #expect(try proof.coordinateEquations[index].matches(
                .coordinate(variableCount: 12, at: coordinate, usage: &usage), usage: &usage))
        }
    }

    @Test(arguments: [false, true])
    func cancellationFromFinalRetentionCallbackCannotPublishSuccess(normalizer: Bool) async throws {
        var preparation = Admission()
        let equation = try term(0, exponent: 2, usage: &preparation)
        var measured = Admission()
        if normalizer {
            _ = try OriginalGuardedIntersectionEquations.prepare(equations: [equation], denominatorGuards: [],
                variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &measured)
        } else {
            _ = try OriginalEvenPowerEquationZeroSet.prepare(equation, equationIndex: 0, usage: &measured)
        }
        let finalStorage = measured.storage
        let cancelled = try await Task {
            var usage = Admission(); usage.cancelAtStorage = finalStorage
            do {
                if normalizer {
                    _ = try OriginalGuardedIntersectionEquations.prepare(equations: [equation], denominatorGuards: [],
                        variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &usage)
                } else {
                    _ = try OriginalEvenPowerEquationZeroSet.prepare(equation, equationIndex: 0, usage: &usage)
                }
                Issue.record("A final retention callback cancelled the task but successful proof was published.")
                return false
            } catch let error where geometryTestIsCancelled(error) { return usage.storage == finalStorage }
        }.value
        #expect(cancelled)
    }

    @Test func cancellationCannotPublishProofOrNormalizedEquations() async throws {
        var preparation = Admission()
        let equation = try term(0, exponent: 2, usage: &preparation)
        let charges = try await Task {
            var usage = Admission()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try OriginalEvenPowerEquationZeroSet.prepare(equation, equationIndex: 0, usage: &usage)
                Issue.record("Cancelled real-zero proof was published.")
            } catch let error where geometryTestIsCancelled(error) { }
            do {
                _ = try OriginalGuardedIntersectionEquations.prepare(equations: [equation], denominatorGuards: [],
                    variableCount: 3, reducePureEvenPowerZeroSets: true, usage: &usage)
                Issue.record("Cancelled guarded real-zero normalization was published.")
            } catch let error where geometryTestIsCancelled(error) { }
            return (usage.work, usage.storage)
        }.value
        #expect(charges.0 == 0 && charges.1 == 0)
    }
}
