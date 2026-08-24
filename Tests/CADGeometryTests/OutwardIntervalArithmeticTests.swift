import CADGeometry
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
}
