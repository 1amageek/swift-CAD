import CADCore
import Foundation
import Testing

@testable import CADGeometry

@Suite("Original native rectangle geometry")
struct OriginalNativeRectangleGeometryTests {
    private let tolerance = ModelingTolerance(distance: 1e-10, angle: 1e-11, relative: 1e-12)

    @Test(.timeLimit(.minutes(1)))
    func nonclampedOriginalPanelsContainPositionAndDerivatives() throws {
        let surface = nonclampedPlane()
        let box = try rectangle(u: 0, 2)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
            of: surface, over: box, tolerance: tolerance)
        #expect(panels.count == 2)
        #expect(panels.map(\.span.uSpanIndex) == [2, 3])
        #expect(panels[0].parameters.u.lower == 0)
        #expect(panels[0].parameters.u.upper == 1)
        #expect(panels[1].parameters.u.lower == 1)
        #expect(panels[1].parameters.u.upper == 2)
        for panel in panels {
            for u in [panel.parameters.u.lower, panel.parameters.u.midpoint, panel.parameters.u.upper] {
                let jet = try panel.span.pointJet(u: u, v: 0.4, on: surface, tolerance: tolerance)
                #expect(jet.x.value.lower <= u && jet.x.value.upper >= u)
                #expect(jet.y.value.lower <= 0.4 && jet.y.value.upper >= 0.4)
                #expect(jet.x.derivativeU.lower <= 1 && jet.x.derivativeU.upper >= 1)
                #expect(jet.y.derivativeV.lower <= 1 && jet.y.derivativeV.upper >= 1)
                let normal = try surface.normal(u: u, v: 0.4, owning: panel.span, tolerance: tolerance)
                #expect(abs(normal.z - 1) < 1e-12)
            }
            #expect(panel.bounds.tangentUMagnitudeUpperBound >= 1)
            #expect(panel.bounds.tangentVMagnitudeUpperBound >= 1)
        }
        let whole = try prepared.intervalJet(over: box, tolerance: tolerance)
        let direct = try DefaultSurfaceDifferentialEncloser().intervalJet(
            of: .bSpline(surface), over: box, tolerance: tolerance)
        for (actual, expected) in zip([whole.x, whole.y, whole.z], [direct.x, direct.y, direct.z]) {
            let actualIntervals = [actual.value, actual.derivativeU, actual.derivativeV,
                actual.secondDerivativeUU, actual.secondDerivativeUV, actual.secondDerivativeVV,
                actual.thirdDerivativeUUU, actual.thirdDerivativeUUV, actual.thirdDerivativeUVV, actual.thirdDerivativeVVV]
            let expectedIntervals = [expected.value, expected.derivativeU, expected.derivativeV,
                expected.secondDerivativeUU, expected.secondDerivativeUV, expected.secondDerivativeVV,
                expected.thirdDerivativeUUU, expected.thirdDerivativeUUV, expected.thirdDerivativeUVV, expected.thirdDerivativeVVV]
            for (actual, expected) in zip(actualIntervals, expectedIntervals) {
                #expect(actual.lower == expected.lower)
                #expect(actual.upper == expected.upper)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func c0ClosedEndpointRetainsBothOriginalNormalOwners() throws {
        let surface = c0Surface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let spans = try prepared.originalNativeSpans(over: rectangle(u: 0, 1), tolerance: tolerance)
        #expect(spans.count == 2)
        let left = try #require(spans.first)
        let right = try #require(spans.last)
        let leftJet = try left.pointJet(u: 0.5, v: 0.5, on: surface, tolerance: tolerance)
        let rightJet = try right.pointJet(u: 0.5, v: 0.5, on: surface, tolerance: tolerance)
        #expect(leftJet.z.derivativeU.lower <= 0 && leftJet.z.derivativeU.upper >= 0)
        #expect(rightJet.z.derivativeU.lower <= 4 && rightJet.z.derivativeU.upper >= 4)
        let leftNormal = try surface.normal(u: 0.5, v: 0.5, owning: left, tolerance: tolerance)
        let rightNormal = try surface.normal(u: 0.5, v: 0.5, owning: right, tolerance: tolerance)
        #expect(abs(leftNormal.z - 1) < 1e-12)
        #expect(abs(rightNormal.x + 4 / sqrt(17)) < 1e-12)
        #expect(leftNormal.dot(rightNormal) < 0.3)
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
            of: surface, over: rectangle(u: 0, 1), tolerance: tolerance)
        #expect(panels.count == 2)
        #expect(panels[0].span.uSpanIndex != panels[1].span.uSpanIndex)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectedTokensRejectChangedAuthorityAndClosedDomainEscape() throws {
        let surface = nonclampedPlane()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let span = try #require(prepared.originalNativeSpans(over: rectangle(u: 0, 2), tolerance: tolerance).first)
        var changed = surface
        changed.controlPoints[0][0].z = 1
        expectFailure(.invalidInput) {
            _ = try span.pointJet(u: 0.4, v: 0.5, on: changed, tolerance: tolerance)
        }
        expectFailure(.invalidInput) {
            _ = try surface.normal(u: 0.4, v: 0.5, owning: span,
                tolerance: ModelingTolerance(distance: 2e-10, angle: 1e-11, relative: 1e-12))
        }
        expectFailure(.invalidInput) {
            _ = try span.pointJet(u: Double(1).nextUp, v: 0.5, on: surface, tolerance: tolerance)
        }
        expectFailure(.invalidInput) {
            _ = try prepared.originalNativeSpans(over: rectangle(u: Double(0).nextDown, 2), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aggregateBudgetAndCollapsedSourceFailExplicitly() throws {
        expectFailure(.resourceLimitExceeded) {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: nonclampedPlane(), over: rectangle(u: 0, 2), tolerance: tolerance, maximumCellCount: 1)
        }
        var collapsed = nonclampedPlane()
        for row in collapsed.controlPoints.indices {
            for column in collapsed.controlPoints[row].indices {
                collapsed.controlPoints[row][column].x = 0
            }
        }
        expectFailure(.singularGeometry) {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: collapsed, over: rectangle(u: 0, 2), tolerance: tolerance)
        }
        expectFailure(.invalidInput) {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: nonclampedPlane(), over: rectangle(u: 1, 1), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationPropagatesBeforeNativeProofWork() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: nonclampedPlane(), over: rectangle(u: 0, 2), tolerance: tolerance)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled original rectangle proof unexpectedly succeeded.")
        } catch is CancellationError {
            // Cancellation is the original invocation's explicit failure.
        }
    }

    private func rectangle(u lower: Double, _ upper: Double) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: lower, upper: upper),
                            v: try ScalarInterval(lower: 0, upper: 1))
    }

    private func nonclampedPlane() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-2, -1, 0, 1, 2, 3, 4],
            vKnots: [0, 0, 1, 1], controlPoints: [0.0, 1.0].map { y in
                [-0.5, 0.5, 1.5, 2.5].map { Point3D(x: $0, y: y, z: 0) }
            })
    }

    private func c0Surface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
            vKnots: [0, 0, 1, 1], controlPoints: [0.0, 1.0].map { y in
                zip([0.0, 0.25, 0.5, 0.75, 1.0], [0.0, 0.0, 0.0, 1.0, 2.0]).map {
                    Point3D(x: $0.0, y: y, z: $0.1)
                }
            })
    }

    private func expectFailure(_ code: KernelErrorCode, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Original rectangle geometry unexpectedly admitted a refused request.")
        } catch let error as KernelError {
            #expect(error.code == code)
        } catch {
            Issue.record("Original rectangle geometry returned an unexpected failure: \(error)")
        }
    }
}
