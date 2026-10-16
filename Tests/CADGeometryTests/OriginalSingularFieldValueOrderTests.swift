import CADCore
@testable import CADGeometry
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OriginalSingularFieldValueOrderTests {
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var maximumWork = 50_000_000
        var maximumStorage = 50_000_000
        var maximumParameterDepth = 96
        var maximumCoefficientDepth = 24
        var work = 0
        var storage = 0
        var parameterDepth = 0
        var coefficientDepth = 0
        var coefficientVisits = 0
        var storageCalls = 0
        var cancelOnStorageCall: Int?
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw failure("work") }
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
            guard count >= 0, count <= maximumStorage - storage else { throw failure("storage") }
            storage += count
            storageCalls += 1
            if storageCalls == cancelOnStorageCall { withUnsafeCurrentTask { $0?.cancel() } }
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
        
        private func failure(_ domain: String) -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original field order test exhausted independent \(domain).")
        }
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value

            guard depth >= 0, depth <= maximumParameterDepth else { throw failure("parameter") }
            parameterDepth = max(parameterDepth, depth)
        
                case .coefficient:
                    let depth = mapped.coefficient

            guard depth >= 0, depth <= maximumCoefficientDepth else { throw failure("coefficient") }
            coefficientDepth = max(coefficientDepth, depth); coefficientVisits += 1
        
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        var maximumTestValueDepth: Int { maximumParameterDepth }
        var maximumTestCoefficientDepth: Int { maximumCoefficientDepth }
    }

    private func squareRoot(_ radicand: Int, coefficient: Bool = false,
        usage: inout Admission) throws -> OriginalSingularFieldElement {
        let parent = try OriginalSingularFieldContext(usage: &usage)
        let value = try OriginalSingularFieldElement.constant(.natural(radicand, usage: &usage),
            in: parent, maximumDepth: 96, usage: &usage)
        return try value.nonnegativeSquareRoot(inheritedDepth: coefficient ? 2 : 0,
            maximumDepth: 96, admissionDomain: coefficient ? .coefficient(maximumDepth: 24) : .parameter,
            usage: &usage)
    }

    private func seed(_ value: OriginalSingularFieldElement, depth: Int = 8,
        usage: inout Admission) throws -> OriginalSingularFieldValueIsolation {
        try .init(original: value, lower: .one, upper: .natural(2, usage: &usage),
            inheritedDepth: depth, maximumDepth: 96, usage: &usage)
    }

    @Test func unrelatedEqualEmbeddingsRetainSeedDepthWithZeroCoefficientBudget() throws {
        var preparation = Admission()
        let firstValue = try squareRoot(2, usage: &preparation)
        let secondValue = try squareRoot(2, usage: &preparation)
        #expect(firstValue.context !== secondValue.context)
        var first = try seed(firstValue, usage: &preparation)
        var second = try seed(secondValue, usage: &preparation)
        var usage = Admission(); usage.maximumParameterDepth = 8; usage.maximumCoefficientDepth = 0
        #expect(try OriginalSingularFieldValueOrder.compare(&first, &second,
            maximumDepth: 8, usage: &usage) == .zero)
        #expect(first.original.context === firstValue.context && second.original.context === secondValue.context)
        #expect(first.sourceDepth == 8 && second.sourceDepth == 8)
        #expect(usage.parameterDepth == 8 && usage.coefficientVisits == 0)
        #expect(usage.work > 0 && usage.storage > 0)
    }

    @Test func originalConjugatesAndDistinctPositiveValuesHaveExactOrder() throws {
        var usage = Admission()
        let positive = try squareRoot(2, usage: &usage)
        let opposite = try positive.negated(maximumDepth: 96, usage: &usage)
        let distinct = try squareRoot(3, usage: &usage)
        var first = try seed(positive, usage: &usage)
        var second = try OriginalSingularFieldValueIsolation(original: opposite,
            inheritedDepth: 8, maximumDepth: 96, usage: &usage)
        #expect(try OriginalSingularFieldValueOrder.compare(&first, &second,
            maximumDepth: 96, usage: &usage) == .positive)
        second = try seed(distinct, usage: &usage)
        #expect(try OriginalSingularFieldValueOrder.compare(&first, &second,
            maximumDepth: 96, usage: &usage) == .negative)
        #expect(try first.upper.subtracting(second.lower, usage: &usage).isNegative)
        #expect(first.sourceDepth >= 8 && second.sourceDepth >= 8)
    }

    @Test func nearValuesRespectFiniteBudgetAndNativeDepthContract() throws {
        var preparation = Admission()
        let value = try squareRoot(2, usage: &preparation)
        let other = try squareRoot(2, usage: &preparation)
        let offset = try ExactRationalCoefficient.originalDouble(0x1p-60, usage: &preparation)
        let translated = try other.adding(.constant(offset, in: other.context,
            maximumDepth: 96, usage: &preparation), maximumDepth: 96, usage: &preparation)
        let firstSeed = try seed(value, depth: 3, usage: &preparation)
        let secondSeed = try seed(translated, depth: 3, usage: &preparation)
        var first = firstSeed, second = secondSeed
        var exhausted = Admission(); exhausted.maximumCoefficientDepth = 0
        do {
            _ = try OriginalSingularFieldValueOrder.compare(&first, &second,
                maximumDepth: 96, usage: &exhausted)
            Issue.record("Finite work budget unexpectedly published closer-than-Double scalar order.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.message == "Original field order test exhausted independent work.")
        }
        #expect(exhausted.work > 0 && exhausted.work <= exhausted.maximumWork)
        #expect(first.original.context === firstSeed.original.context)
        #expect(second.original.context === secondSeed.original.context)
        #expect(first.lower == firstSeed.lower && first.upper == firstSeed.upper
            && first.sourceDepth == firstSeed.sourceDepth)
        #expect(second.lower == secondSeed.lower && second.upper == secondSeed.upper
            && second.sourceDepth == secondSeed.sourceDepth)
        #expect(2.0.squareRoot() + 0x1p-60 == 2.0.squareRoot())

        // This success fixture uses the Native caller's parameter depth contract
        // with unchanged finite work/storage caps and independent C0 admission.
        let nativeOffset = try ExactRationalCoefficient.originalDouble(0x1p-10, usage: &preparation)
        let nativeTranslated = try other.adding(.constant(nativeOffset, in: other.context,
            maximumDepth: 32, usage: &preparation), maximumDepth: 32, usage: &preparation)
        first = firstSeed; second = try seed(nativeTranslated, depth: 3, usage: &preparation)
        var usage = Admission(); usage.maximumParameterDepth = 32; usage.maximumCoefficientDepth = 0
        #expect(try OriginalSingularFieldValueOrder.compare(&first, &second,
            maximumDepth: 32, usage: &usage) == .negative)
        #expect(first.sourceDepth > 3 && second.sourceDepth > 3)
        #expect(first.sourceDepth <= 32 && second.sourceDepth <= 32)
        let depths = (first.sourceDepth, second.sourceDepth)
        #expect(try OriginalSingularFieldValueOrder.compare(&second, &first,
            maximumDepth: 32, usage: &usage) == .positive)
        #expect(first.sourceDepth == depths.0 && second.sourceDepth == depths.1)
        #expect(usage.coefficientVisits == 0)
    }

    @Test func independentLimitsFailWithoutReplacingOriginalSeeds() throws {
        var preparation = Admission()
        let value = try squareRoot(2, usage: &preparation)
        var first = try seed(value, usage: &preparation)
        var second = try seed(squareRoot(3, usage: &preparation), usage: &preparation)
        let bounds = (first.lower, first.upper, first.sourceDepth)
        var depth = Admission()
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalSingularFieldValueOrder.compare(&first, &second, maximumDepth: 7, usage: &depth)
        }
        #expect(depth.work == 0 && depth.storage == 0)
        var work = Admission(); work.maximumWork = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalSingularFieldValueOrder.compare(&first, &second, maximumDepth: 96, usage: &work)
        }
        var storage = Admission(); storage.maximumStorage = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalSingularFieldValueOrder.compare(&first, &second, maximumDepth: 96, usage: &storage)
        }
        #expect(first.original.context === value.context)
        #expect(first.lower == bounds.0 && first.upper == bounds.1 && first.sourceDepth == bounds.2)
        let coefficientValue = try squareRoot(2, coefficient: true, usage: &preparation)
        first = try seed(coefficientValue, usage: &preparation)
        var coefficient = Admission()
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalSingularFieldValueOrder.compare(&first, &second,
                maximumDepth: 96, maximumCoefficientDepth: 0, usage: &coefficient)
        }
        #expect(coefficient.work == 0 && coefficient.storage == 0)
        #expect(try OriginalSingularFieldValueOrder.compare(&first, &second,
            maximumDepth: 96, maximumCoefficientDepth: 24, usage: &coefficient) == .negative)
        #expect(coefficient.coefficientVisits > 0 && coefficient.coefficientDepth >= 2)
    }

    @Test func cancelledOrderDoesNotSpendOrReplaceSeeds() async throws {
        let result = try await Task {
            var preparation = Admission()
            var first = try seed(squareRoot(2, usage: &preparation), usage: &preparation)
            var second = try seed(squareRoot(2, usage: &preparation), usage: &preparation)
            let depth = first.sourceDepth
            var usage = Admission()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try OriginalSingularFieldValueOrder.compare(&first, &second,
                    maximumDepth: 96, usage: &usage)
                Issue.record("Cancelled scalar order published a result.")
            } catch let error where geometryTestIsCancelled(error) {
                return usage.work == 0 && usage.storage == 0 && first.sourceDepth == depth
            }
            return false
        }.value
        #expect(result)
    }

    @Test func legacyTransportRejectsCoefficientCapBeforeFreshIsolationWork() throws {
        var preparation = Admission()
        let value = try squareRoot(2, coefficient: true, usage: &preparation)
        #expect(value.context.coefficientDepth == 3)
        var usage = Admission()
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalSingularRationalCoordinateRoot(original: value,
                maximumDepth: 96, maximumAlgebraicDepth: 0, usage: &usage)
        }
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalSingularRationalCoordinateRoot(original: value,
                maximumDepth: 96, maximumAlgebraicDepth: 2, usage: &usage)
        }
        #expect(usage.work == 0 && usage.storage == 0 && usage.coefficientVisits == 0)
        let root = try OriginalSingularRationalCoordinateRoot(original: value,
            maximumDepth: 96, maximumAlgebraicDepth: 3, usage: &usage)
        #expect(root.original.context === value.context)
        #expect(usage.coefficientVisits > 0 && usage.coefficientDepth == 3)
    }

    @Test func finalStorageCallbackCancellationCannotPublishScalarOrder() async throws {
        let rejected = try await Task {
            var preparation = Admission()
            let firstSeed = try seed(squareRoot(2, usage: &preparation), usage: &preparation)
            let secondSeed = try seed(squareRoot(2, usage: &preparation), usage: &preparation)
            var first = firstSeed, second = secondSeed
            var baseline = Admission()
            #expect(try OriginalSingularFieldValueOrder.compare(&first, &second,
                maximumDepth: 96, usage: &baseline) == .zero)
            #expect(baseline.storageCalls > 0)
            first = firstSeed; second = secondSeed
            var usage = Admission(); usage.cancelOnStorageCall = baseline.storageCalls
            do {
                _ = try OriginalSingularFieldValueOrder.compare(&first, &second,
                    maximumDepth: 96, usage: &usage)
                Issue.record("Final callback cancellation published scalar order.")
            } catch let error where geometryTestIsCancelled(error) {
                return usage.storageCalls == baseline.storageCalls
                    && first.original.context === firstSeed.original.context
                    && second.original.context === secondSeed.original.context
            }
            return false
        }.value
        #expect(rejected)
    }
}
