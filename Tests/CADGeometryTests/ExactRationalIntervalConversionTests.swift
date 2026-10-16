import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Exact rational outward interval conversion")
struct ExactRationalIntervalConversionTests {
    @Test(.timeLimit(.minutes(1)), arguments: Array(0...8))
    func exactOutwardEndpointsHaveBoundedWork(mode: Int) throws {
        var verification = GeometryTestScalarRecorder(observeWork: { _ in }, observeStorageWords: { _ in },
            observeValueCell: { _ in }, observeCoefficientCell: { _ in })
        let original: ExactRationalCoefficient
        switch mode {
        case 0, 1:
            original = try .init(canonicalSign: mode == 0 ? 1 : -1,
                numeratorWords: [1], denominatorWords: [3], usage: &verification)
        case 2, 3:
            original = try .init(canonicalSign: mode == 2 ? 1 : -1,
                numeratorWords: [1,1], denominatorWords: [3,2], usage: &verification)
        case 4, 5:
            // A two-word prefix loses the final denominator word and begins
            // hundreds of thousands of Double ULPs away from this exact ratio.
            original = try .init(canonicalSign: mode == 4 ? 1 : -1,
                numeratorWords: [1,0,1], denominatorWords: [.max,.max,1], usage: &verification)
        case 6, 7:
            let subnormal = try ExactRationalCoefficient.originalDouble(Double.leastNonzeroMagnitude, usage: &verification)
            let third = try subnormal.divided(by: .originalDouble(3, usage: &verification), usage: &verification)
            original = mode == 6 ? third : third.negated
        default:
            // Exact surface representative quotient from the public rational
            // repeated-root regression; its denominator's highest word is one.
            original = try .init(canonicalSign: 1, numeratorWords: [3_212_890_610,6_684_593],
                denominatorWords: [313_853_205,1_575_754_564,1], usage: &verification)
        }
        let work = Mutex(0)
        var bounded = GeometryTestScalarRecorder(observeWork: { count in
            try work.withLock { used in
                guard count <= 100_000 - used else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                        message: "Exact outward conversion exceeded the regression work bound.")
                }
                used += count
            }
        }, observeStorageWords: { _ in }, observeValueCell: { _ in }, observeCoefficientCell: { _ in })
        let interval = try original.outwardInterval(usage: &bounded)
        #expect(interval.isFinite && interval.lower <= interval.upper)
        let lower = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &verification)
        let upper = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &verification)
        #expect(try !lower.subtracting(original, usage: &verification).isPositive)
        #expect(try !upper.subtracting(original, usage: &verification).isNegative)
        #expect(interval.lower == interval.upper || interval.lower.nextUp == interval.upper)
        #expect(work.withLock { $0 } <= 100_000)
    }
}
