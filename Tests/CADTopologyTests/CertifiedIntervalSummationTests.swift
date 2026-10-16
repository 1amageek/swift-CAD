import CADGeometry
import Testing
@testable import CADTopology

struct CertifiedIntervalSummationTests {
    @Test
    func balancedCompositionContainsLargeIntervalSumWithoutLinearInflation() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
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

        let balanced = try CertifiedIntervalSummation.sum(values, using: &execution)
        var sequential = SurfaceParameterAreaBounds.zero
        for value in values {
            sequential = sequential.adding(value)
        }

        #expect(balanced.lower <= lower * Double(count))
        #expect(balanced.upper >= upper * Double(count))
        #expect(balanced.width < sequential.width)
    }
}
