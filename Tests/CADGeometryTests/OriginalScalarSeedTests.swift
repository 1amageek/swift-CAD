import CADCore
@testable import CADGeometry
import Testing

@Suite("Verified original scalar localization seeds")
struct OriginalScalarSeedTests {
    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
    }

    @Test(.timeLimit(.minutes(1)))
    func exactSeedRejectsReversedExcludingAndForeignValueBounds() throws {
        var admission = usage()
        let context = try OriginalSingularFieldContext(usage: &admission)
        let half = try ExactRationalCoefficient.originalDouble(0.5, usage: &admission)
        let value = try OriginalSingularFieldElement.constant(half, in: context, maximumDepth: 0, usage: &admission)
        let seeded = try OriginalSingularFieldValueIsolation(original: value, lower: .zero, upper: .one,
            inheritedDepth: 3, maximumDepth: 3, usage: &admission)
        #expect(seeded.lower == half && seeded.upper == half && seeded.sourceDepth == 3)
        #expect(throws: KernelError.self) {
            try OriginalSingularFieldValueIsolation(original: value, lower: .one, upper: .zero,
                inheritedDepth: 3, maximumDepth: 3, usage: &admission)
        }
        #expect(throws: KernelError.self) {
            try OriginalSingularFieldValueIsolation(original: value, lower: .zero, upper: .zero,
                inheritedDepth: 3, maximumDepth: 3, usage: &admission)
        }
        #expect(throws: KernelError.self) {
            try OriginalSingularFieldValueIsolation(original: value, lower: .one, upper: .one,
                inheritedDepth: 3, maximumDepth: 3, usage: &admission)
        }
        #expect(throws: KernelError.self) {
            try OriginalSingularFieldValueIsolation(original: value, lower: .zero, upper: .one,
                inheritedDepth: 4, maximumDepth: 3, usage: &admission)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func seededAlgebraicCoordinatePreservesDepthThroughRefinement() throws {
        var admission = usage()
        let context = try OriginalSingularFieldContext(usage: &admission)
        let half = try ExactRationalCoefficient.originalDouble(0.5, usage: &admission)
        let value = try OriginalSingularFieldElement.constant(half, in: context, maximumDepth: 0, usage: &admission)
        let coordinate = OriginalAlgebraicCoordinate(original: value, inheritedDepth: 7,
            certifiedBounds: (.zero, .one))
        let enclosed = try coordinate.enclosed(maximumDepth: 7, maximumCoefficientDepth: 0, usage: admission)
        #expect(enclosed.sourceDepth == 7 && enclosed.lower == half && enclosed.upper == half)
        let refined = try enclosed.refined(maximumWidth: half, maximumDepth: 7,
            maximumCoefficientDepth: 0, usage: admission)
        #expect(refined.sourceDepth == 7 && refined.lower == half && refined.upper == half)
        #expect(throws: KernelError.self) {
            try enclosed.refined(maximumWidth: half, maximumDepth: 6,
                maximumCoefficientDepth: 0, usage: admission)
        }
    }
}
