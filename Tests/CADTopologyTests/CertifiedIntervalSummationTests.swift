import Testing
@testable import CADTopology

struct CertifiedIntervalSummationTests {
    @Test
    func balancedCompositionContainsLargeIntervalSumWithoutLinearInflation() {
        let count = 1 << 16
        let lower = 8.0
        let upper = lower.nextUp
        let values = Array(
            repeating: SurfaceParameterAreaBounds(
                lower: lower,
                upper: upper
            ),
            count: count
        )

        let balanced = CertifiedIntervalSummation.sum(values)
        var sequential = SurfaceParameterAreaBounds.zero
        for value in values {
            sequential = sequential.adding(value)
        }

        #expect(balanced.lower <= lower * Double(count))
        #expect(balanced.upper >= upper * Double(count))
        #expect(balanced.width < sequential.width)
    }
}
