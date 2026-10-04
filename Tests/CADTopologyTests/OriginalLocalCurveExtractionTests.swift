import CADCore
import CADGeometry
@testable import CADTopology
import Testing

@Suite("Original local B-spline curve extraction")
struct OriginalLocalCurveExtractionTests {
    private typealias Patch = CertifiedHomogeneousBezierCurvePatch
    private typealias Scalar = Patch.ScalarBounds
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func localPatchesContainOriginalHomogeneousValueAndDerivative() throws {
        let curve = sourceCurve()
        let patches = try CertifiedBSplineCurveBezierExtractor().patches(
            curve: curve,
            tolerance: tolerance
        )

        #expect(patches.count == 2)
        #expect(patches[0].lower == 0.0)
        #expect(patches[0].upper == 0.4)
        #expect(patches[1].lower == 0.4)
        #expect(patches[1].upper == 1.0)

        let segments = literalSegments()
        for (patchIndex, patch) in patches.enumerated() {
            for fraction in [0.0, 0.5, 1.0] {
                let segment = segments[patchIndex]
                let ownership = endpointOwnership(
                    patchIndex: patchIndex,
                    fraction: fraction,
                    segmentCount: segments.count
                )
                let expectedValue = literalValue(segment, at: fraction)
                let expectedDerivative = literalDerivative(segment, at: fraction)
                switch ownership {
                case .leftLimit:
                    #expect(patchIndex < segments.count)
                case .rightLimit:
                    #expect(patchIndex > 0)
                case .boundary:
                    #expect(patchIndex == 0 || patchIndex == segments.count - 1)
                case .interior:
                    break
                }
                let actualValue = evaluate(
                    patch.controls,
                    at: fraction
                )
                let actualDerivative = derivative(
                    patch.controls,
                    at: fraction
                )
                let parameterDerivative = Patch.HomogeneousPoint(
                    x: actualDerivative.x / .exact(patch.upper - patch.lower),
                    y: actualDerivative.y / .exact(patch.upper - patch.lower),
                    weight: actualDerivative.weight / .exact(patch.upper - patch.lower)
                )

                expectContains(actualValue.x, expectedValue.x)
                expectContains(actualValue.y, expectedValue.y)
                expectContains(actualValue.weight, expectedValue.weight)
                expectContains(parameterDerivative.x, expectedDerivative.x)
                expectContains(parameterDerivative.y, expectedDerivative.y)
                expectContains(parameterDerivative.weight, expectedDerivative.weight)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func localExtractionPreservesTypedOperationFailure() throws {
        do {
            _ = try CertifiedBSplineCurveBezierExtractor(
                maximumControlOperations: 0
            ).patches(curve: sourceCurve(), tolerance: tolerance)
            Issue.record("The local extractor must preserve its control-operation failure contract.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func localExtractionRefusesBeforeMaterializingSliceWithTinyAllowance() throws {
        do {
            _ = try CertifiedBSplineCurveBezierExtractor(
                maximumControlOperations: 1
            ).patches(curve: sourceCurve(), tolerance: tolerance)
            Issue.record("A tiny allowance must refuse before local slice materialization.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    private struct LiteralHomogeneousPoint {
        var x: Double
        var y: Double
        var weight: Double
    }

    private struct LiteralSegment {
        let lower: Double
        let upper: Double
        let controls: [LiteralHomogeneousPoint]
    }

    private enum EndpointOwnership {
        case boundary
        case interior
        case leftLimit
        case rightLimit
    }

    private func sourceCurve() -> BSplineCurve2D {
        BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 0.4, 0.4, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.8, y: 0.2),
                Point2D(x: 1.4, y: 1.0),
                Point2D(x: 0.5, y: 1.8),
                Point2D(x: -0.3, y: 2.2),
            ],
            weights: [0.8, 1.4, 0.6, 1.7, 1.1]
        )
    }

    private func evaluate(
        _ controls: [Patch.HomogeneousPoint],
        at fraction: Double
    ) -> Patch.HomogeneousPoint {
        var level = controls
        let parameter = Scalar.exact(fraction)
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index].interpolated(
                    to: level[index + 1],
                    parameter: parameter
                )
            }
        }
        return level[0]
    }

    private func derivative(
        _ controls: [Patch.HomogeneousPoint],
        at fraction: Double
    ) -> Patch.HomogeneousPoint {
        let degree = Double(controls.count - 1)
        let derivativeControls = (0..<(controls.count - 1)).map { index in
            Patch.HomogeneousPoint(
                x: (controls[index + 1].x - controls[index].x) * .exact(degree),
                y: (controls[index + 1].y - controls[index].y) * .exact(degree),
                weight: (controls[index + 1].weight - controls[index].weight) * .exact(degree)
            )
        }
        return evaluate(derivativeControls, at: fraction)
    }

    private func literalSegments() -> [LiteralSegment] {
        [
            LiteralSegment(
                lower: 0.0,
                upper: 0.4,
                controls: [
                    LiteralHomogeneousPoint(x: 0.0, y: 0.0, weight: 0.8),
                    LiteralHomogeneousPoint(x: 1.12, y: 0.28, weight: 1.4),
                    LiteralHomogeneousPoint(x: 0.84, y: 0.6, weight: 0.6),
                ]
            ),
            LiteralSegment(
                lower: 0.4,
                upper: 1.0,
                controls: [
                    LiteralHomogeneousPoint(x: 0.84, y: 0.6, weight: 0.6),
                    LiteralHomogeneousPoint(x: 0.85, y: 3.06, weight: 1.7),
                    LiteralHomogeneousPoint(x: -0.33, y: 2.42, weight: 1.1),
                ]
            ),
        ]
    }

    private func endpointOwnership(
        patchIndex: Int,
        fraction: Double,
        segmentCount: Int
    ) -> EndpointOwnership {
        if fraction == 0.0, patchIndex > 0 { return .rightLimit }
        if fraction == 1.0, patchIndex < segmentCount - 1 { return .leftLimit }
        if fraction == 0.0 || fraction == 1.0 { return .boundary }
        return .interior
    }

    private func literalValue(
        _ segment: LiteralSegment,
        at fraction: Double
    ) -> LiteralHomogeneousPoint {
        let first = segment.controls[0]
        let second = segment.controls[1]
        let third = segment.controls[2]
        let complement = 1.0 - fraction
        return LiteralHomogeneousPoint(
            x: complement * complement * first.x
                + 2.0 * complement * fraction * second.x
                + fraction * fraction * third.x,
            y: complement * complement * first.y
                + 2.0 * complement * fraction * second.y
                + fraction * fraction * third.y,
            weight: complement * complement * first.weight
                + 2.0 * complement * fraction * second.weight
                + fraction * fraction * third.weight
        )
    }

    private func literalDerivative(
        _ segment: LiteralSegment,
        at fraction: Double
    ) -> LiteralHomogeneousPoint {
        let first = segment.controls[0]
        let second = segment.controls[1]
        let third = segment.controls[2]
        let complement = 1.0 - fraction
        let parameterScale = 1.0 / (segment.upper - segment.lower)
        return LiteralHomogeneousPoint(
            x: parameterScale * 2.0 * (complement * (second.x - first.x) + fraction * (third.x - second.x)),
            y: parameterScale * 2.0 * (complement * (second.y - first.y) + fraction * (third.y - second.y)),
            weight: parameterScale * 2.0 * (complement * (second.weight - first.weight) + fraction * (third.weight - second.weight))
        )
    }

    private func expectContains(
        _ interval: Scalar,
        _ value: Double
    ) {
        let margin = max(1.0e-12, abs(value) * 1.0e-12)
        #expect(interval.lower <= value + margin)
        #expect(interval.upper >= value - margin)
    }
}
