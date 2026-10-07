import CADCore
@testable import CADGeometry
import Testing

@Suite("Canonical rational addition", .timeLimit(.minutes(1)))
struct IntersectionRationalAdditionTests {
    private enum AdmissionFailure: Error, Equatable { case work, storage, unexpectedDepth }
    private struct Admission: RationalAlgebraAdmitting {
        var maximumWork = 80_000_000
        var maximumStorage = 268_435_456
        var work = 0
        var storage = 0
        var cells = 0
        var cancelAtWork: Int?
        var cancelAtStorage: Int?
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw AdmissionFailure.work }
            work += count
            if work == cancelAtWork { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw AdmissionFailure.storage }
            storage += count
            if storage == cancelAtStorage { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func visitExactCell(depth: Int) throws {
            cells += 1
            throw AdmissionFailure.unexpectedDepth
        }
    }
    private struct Golden {
        let firstSign: Int
        let firstNumerator: [UInt32]
        let firstDenominator: [UInt32]
        let secondSign: Int
        let secondNumerator: [UInt32]
        let secondDenominator: [UInt32]
        let expectedSign: Int
        let expectedNumerator: [UInt32]
        let expectedDenominator: [UInt32]
    }

    // Independently calculated with exact integer fractions, not library arithmetic.
    private func golden(_ index: Int) -> Golden {
        let cases: [Golden] = [
            Golden(firstSign: 1,
                firstNumerator: [1],
                firstDenominator: [6],
                secondSign: 1,
                secondNumerator: [1],
                secondDenominator: [15],
                expectedSign: 1,
                expectedNumerator: [7],
                expectedDenominator: [30]),
            Golden(firstSign: 1,
                firstNumerator: [1],
                firstDenominator: [6],
                secondSign: 1,
                secondNumerator: [1],
                secondDenominator: [10],
                expectedSign: 1,
                expectedNumerator: [4],
                expectedDenominator: [15]),
            Golden(firstSign: 1,
                firstNumerator: [1],
                firstDenominator: [30],
                secondSign: 1,
                secondNumerator: [5],
                secondDenominator: [42],
                expectedSign: 1,
                expectedNumerator: [16],
                expectedDenominator: [105]),
            Golden(firstSign: 1,
                firstNumerator: [1],
                firstDenominator: [0, 0, 192],
                secondSign: 1,
                secondNumerator: [1],
                secondDenominator: [0, 0, 320],
                expectedSign: 1,
                expectedNumerator: [1],
                expectedDenominator: [0, 0, 120]),
            Golden(firstSign: 1,
                firstNumerator: [1],
                firstDenominator: [0, 0, 192],
                secondSign: -1,
                secondNumerator: [1],
                secondDenominator: [0, 0, 320],
                expectedSign: 1,
                expectedNumerator: [1],
                expectedDenominator: [0, 0, 480]),
            Golden(firstSign: 1,
                firstNumerator: [1, 0, 0, 0, 4],
                firstDenominator: [3],
                secondSign: 1,
                secondNumerator: [7, 0, 0, 32],
                secondDenominator: [5],
                expectedSign: 1,
                expectedNumerator: [26, 0, 0, 96, 20],
                expectedDenominator: [15]),
            Golden(firstSign: -1,
                firstNumerator: [1, 0, 0, 0, 4],
                firstDenominator: [3],
                secondSign: 1,
                secondNumerator: [7, 0, 0, 32],
                secondDenominator: [5],
                expectedSign: -1,
                expectedNumerator: [4294967280, 4294967295, 4294967295, 4294967199, 19],
                expectedDenominator: [15]),
            Golden(firstSign: 1,
                firstNumerator: [5, 0, 0, 0, 512],
                firstDenominator: [0, 0, 6],
                secondSign: 1,
                secondNumerator: [1, 0, 0, 0, 2],
                secondDenominator: [0, 0, 40],
                expectedSign: 1,
                expectedNumerator: [103, 0, 0, 0, 10246],
                expectedDenominator: [0, 0, 120]),
        ]
        return cases[index]
    }
    private func inputs(_ index: Int, usage: inout Admission) throws
        -> (first: ExactRationalCoefficient, second: ExactRationalCoefficient, expected: ExactRationalCoefficient) {
        let value = golden(index)
        return (try .init(canonicalSign: value.firstSign, numeratorWords: value.firstNumerator,
                         denominatorWords: value.firstDenominator, usage: &usage),
                try .init(canonicalSign: value.secondSign, numeratorWords: value.secondNumerator,
                         denominatorWords: value.secondDenominator, usage: &usage),
                try .init(canonicalSign: value.expectedSign, numeratorWords: value.expectedNumerator,
                         denominatorWords: value.expectedDenominator, usage: &usage))
    }

    @Test(arguments: 0..<8)
    func exactGoldenWordsAndSignedDifferentialIdentities(index: Int) throws {
        var preparation = Admission()
        let values = try inputs(index, usage: &preparation)
        let aliases = (values.first, values.second)
        var usage = Admission()
        let result = try values.first.adding(values.second, usage: &usage)
        #expect(result == values.expected)
        #expect(result.canonicalSign == golden(index).expectedSign)
        #expect(result.canonicalNumeratorWords == golden(index).expectedNumerator)
        #expect(result.canonicalDenominatorWords == golden(index).expectedDenominator)
        #expect(try values.second.adding(values.first, usage: &usage) == result)
        #expect(try values.first.subtracting(values.second.negated, usage: &usage) == result)
        #expect(try values.first.negated.adding(values.second.negated, usage: &usage) == result.negated)
        #expect(values.first == aliases.0 && values.second == aliases.1)
        #expect(usage.cells == 0 && usage.work > 0 && usage.storage > 0)
    }

    @Test func independentWorkAndStorageRefuseBeforePublishing() throws {
        var preparation = Admission()
        let values = try inputs(2, usage: &preparation)
        var measured = Admission()
        #expect(try values.first.adding(values.second, usage: &measured) == values.expected)
        for allowance in [0, measured.work - 1] {
            var usage = Admission(); usage.maximumWork = allowance
            #expect(throws: AdmissionFailure.work) {
                try values.first.adding(values.second, usage: &usage)
            }
            #expect(usage.work <= allowance && usage.cells == 0)
        }
        for allowance in [0, measured.storage - 1] {
            var usage = Admission(); usage.maximumStorage = allowance
            #expect(throws: AdmissionFailure.storage) {
                try values.first.adding(values.second, usage: &usage)
            }
            #expect(usage.storage <= allowance && usage.cells == 0)
        }
    }

    @Test(arguments: [false, true])
    func finalAdmissionCancellationCannotPublishCanonicalValue(storageCallback: Bool) async throws {
        var preparation = Admission()
        let values = try inputs(2, usage: &preparation)
        var measured = Admission()
        #expect(try values.first.adding(values.second, usage: &measured) == values.expected)
        let finalWork = measured.work, finalStorage = measured.storage
        let cancelled = try await Task {
            var usage = Admission()
            if storageCallback { usage.cancelAtStorage = finalStorage }
            else { usage.cancelAtWork = finalWork }
            do {
                _ = try values.first.adding(values.second, usage: &usage)
                Issue.record("A final rational addition admission cancelled the task but published a value.")
                return false
            } catch is CancellationError {
                return (storageCallback ? usage.storage == finalStorage : usage.work == finalWork) && usage.cells == 0
            }
        }.value
        #expect(cancelled)
    }

    @Test func zeroSignSourceRejectionAndPrecancellationRemainExplicit() async throws {
        var usage = Admission()
        let zero = try ExactRationalCoefficient(canonicalSign: 0, numeratorWords: [], denominatorWords: [1], usage: &usage)
        #expect(zero == .zero && zero.canonicalSign == 0)
        #expect(zero.canonicalNumeratorWords.isEmpty && zero.canonicalDenominatorWords == [1])
        let values = try inputs(7, usage: &usage)
        #expect(try zero.adding(values.first, usage: &usage) == values.first)
        #expect(try values.first.adding(zero, usage: &usage) == values.first)
        let cancelledSum = try values.first.adding(values.first.negated, usage: &usage)
        #expect(cancelledSum == zero && cancelledSum.canonicalSign == 0)
        let invalid: [(Int, [UInt32], [UInt32])] = [(0, [1], [1]), (1, [], [1]), (1, [2], [4])]
        for source in invalid {
            #expect(throws: KernelError.self) {
                try ExactRationalCoefficient(canonicalSign: source.0, numeratorWords: source.1,
                    denominatorWords: source.2, usage: &usage)
            }
        }
        let precancelled = try await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var admission = Admission()
            do {
                _ = try values.first.adding(values.second, usage: &admission)
                Issue.record("A precancelled rational addition published a value.")
                return false
            } catch is CancellationError { return admission.work == 0 && admission.storage == 0 && admission.cells == 0 }
        }.value
        #expect(precancelled)
    }
}
