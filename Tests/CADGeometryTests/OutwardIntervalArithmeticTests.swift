@testable import CADGeometry
import Foundation
import Testing

@Suite("Outward Interval Arithmetic")
struct OutwardIntervalArithmeticTests {
    @Test
    func storedDoubleInputsRemainExactUntilArithmeticBegins() {
        let value = 0.1
        let exact = OutwardScalarInterval.exact(value)
        let external = OutwardScalarInterval(value)

        #expect(exact.lower == value)
        #expect(exact.upper == value)
        #expect(external.lower < value)
        #expect(external.upper > value)
    }

    @Test
    func arithmeticEnclosesAllEndpointCombinations() throws {
        let first = OutwardScalarInterval(lower: -1.25, upper: 2.5)
        let second = OutwardScalarInterval(lower: -0.75, upper: 4.0)

        let sum = first + second
        let difference = first - second
        let product = first * second

        for lhs in [first.lower, first.upper] {
            for rhs in [second.lower, second.upper] {
                #expect(sum.contains(lhs + rhs))
                #expect(difference.contains(lhs - rhs))
                #expect(product.contains(lhs * rhs))
            }
        }

        let positive = OutwardScalarInterval(lower: 0.25, upper: 3.0)
        let quotient = try #require(first.divided(by: positive))
        for numerator in [first.lower, first.upper] {
            for denominator in [positive.lower, positive.upper] {
                #expect(quotient.contains(numerator / denominator))
            }
        }
    }

    @Test
    func divisionRejectsAZeroCrossingDenominator() {
        let numerator = OutwardScalarInterval(lower: 1.0, upper: 2.0)
        let denominator = OutwardScalarInterval(lower: -1.0, upper: 1.0)

        #expect(numerator.divided(by: denominator) == nil)
    }

    @Test func vectorMagnitudeRetainsEuclideanLowerBoundsAcrossSignsAndScales() {
        for scale in [1e-200, 1e-8, 1.0, 1e200] {
            let bounds = IntervalVector3DBounds(
                x: OutwardScalarInterval(lower: 3 * scale, upper: 6 * scale),
                y: OutwardScalarInterval(lower: -8 * scale, upper: -4 * scale),
                z: OutwardScalarInterval(lower: -scale, upper: scale))
            #expect(bounds.lengthLowerBound <= 5 * scale)
            #expect(bounds.lengthLowerBound >= (4 * scale).nextDown)
            if scale >= 1e-8, scale <= 1 {
                #expect(bounds.lengthLowerBound > 4.99 * scale)
            }
            #expect(bounds.lengthUpperBound >= hypot(6 * scale, hypot(8 * scale, scale)))
        }
        let zero = IntervalVector3DBounds(x: .exact(0), y: .exact(0), z: .exact(0))
        #expect(zero.lengthLowerBound == 0)
    }
}
