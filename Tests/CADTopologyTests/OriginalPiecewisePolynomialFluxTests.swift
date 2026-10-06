import Foundation
import Testing
import CADCore
import CADGeometry
@testable import CADTopology

@Suite("Original piecewise polynomial Green flux")
struct OriginalPiecewisePolynomialFluxTests {
    private typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval

    private func surface(weight: Double = 1, vCrease: Bool = false) -> BSplineSurface3D {
        let u = [1.0, 2, 4], h = [1.0, 2, 8]
        let v = vCrease ? [0.0, 1, 3] : [0.0, 3]
        let k = vCrease ? [0.0, 1, 5] : [0.0, 0]
        return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [1, 1, 2, 4, 4],
            vKnots: vCrease ? [0, 0, 1, 3, 3] : [0, 0, 3, 3],
            controlPoints: v.indices.map { j in u.indices.map { i in Point3D(x: u[i], y: v[j], z: h[i] + k[j]) } },
            weights: v.map { _ in u.map { _ in weight } })
    }
    private func field(_ source: BSplineSurface3D) throws -> CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField {
        let candidate = try CertifiedRationalBezierSurfaceFluxIntegrator().preparedField(
            surface: source, reference: .origin, tolerance: .standard)
        return try #require(candidate)
    }
    private func primitive(_ source: BSplineSurface3D, base: Double = 1) throws -> CertifiedPiecewisePolynomialSurfaceFluxPrimitive {
        var charged = 0
        let candidate = try field(source).preparedPolynomialGreenPrimitive(uBase: base) { charged += $0 }
        let result = try #require(candidate)
        #expect(charged > 0 && charged < 2_000_000)
        return result
    }
    private func triangle(rational: Bool) -> [SurfaceParameterCurve] {
        let side: SurfaceParameterCurve = rational ? .bSpline(BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point2D(x: 4, y: 3), Point2D(x: 2.5, y: 1.5), Point2D(x: 1, y: 0)], weights: [1, 2, 1])) :
            .polyline([SurfaceParameter(u: 4, v: 3), SurfaceParameter(u: 1, v: 0)])
        return [.constantV(v: 0, uStart: 1, uEnd: 4), .constantU(u: 4, vStart: 0, vEnd: 3), side]
    }
    private func integral(_ curves: [SurfaceParameterCurve], primitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive) throws -> Interval {
        let integrator = CertifiedAnalyticPcurveFluxIntegrator()
        var total = Interval.exact(0)
        for curve in curves {
            total = total + (try integrator.piecewisePolynomialBounds(for: curve, primitive: primitive,
                requestedWidth: 1e-8 / Double(curves.count), tolerance: .standard))
        }
        return total
    }
    private func contains(_ bounds: Interval, _ value: Double) {
        #expect(bounds.lower <= value && bounds.upper >= value)
        #expect(bounds.width <= 1e-8)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func literalC0TriangleAndReverseUseOriginalRationalJets(rational: Bool) throws {
        let receipt = try primitive(surface())
        let curves = triangle(rational: rational)
        contains(try integral(curves, primitive: receipt), -16.0 / 3)
        let reverse = try curves.reversed().map { try $0.reversed(tolerance: .standard) }
        contains(try integral(reverse, primitive: receipt), 16.0 / 3)
        let rectangle: [SurfaceParameterCurve] = [.constantV(v: 0, uStart: 1, uEnd: 4),
            .constantU(u: 4, vStart: 0, vEnd: 3), .constantV(v: 3, uStart: 4, uEnd: 1),
            .constantU(u: 1, vStart: 3, vEnd: 0)]
        contains(try integral(rectangle, primitive: receipt), -8)
    }

    /// The original C0 support has density 0 for u<=2 and -4/3 for u>=2.
    /// Its U-anchored Green value is -4/3*max(0,u-2), including both knot sides.
    @Test(.timeLimit(.minutes(1)), arguments: ["crossing", "contact", "onSeam", "nearEndpoint", "endpoint"])
    func closedUBandsRetainLiteralOriginalRationalFlux(kind: String) throws {
        let curve: BSplineCurve2D
        let expected: Double
        switch kind {
        case "crossing":
            curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [Point2D(x: 1, y: 0), Point2D(x: 2.5, y: 1.5), Point2D(x: 4, y: 3)],
                weights: [1, 2, 1])
            expected = -8.0 / 3
        case "contact":
            // u=2+(t-1/2)^2 and v=3t; integral -4*(t-1/2)^2 dt = -1/3.
            curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [Point2D(x: 2.25, y: 0), Point2D(x: 1.75, y: 1.5), Point2D(x: 2.25, y: 3)])
            expected = -1.0 / 3
        case "onSeam":
            curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [Point2D(x: 2, y: 0), Point2D(x: 2, y: 1.5), Point2D(x: 2, y: 3)],
                weights: [1, 2, 1])
            expected = 0
        case "nearEndpoint":
            let delta = 1.0 / 1024
            // Unequal weights reparameterize the same line v=3*(u-(2-delta)).
            curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [Point2D(x: 2-delta, y: 0), Point2D(x: 2.5-delta, y: 1.5), Point2D(x: 3-delta, y: 3)],
                weights: [1, 2, 1])
            expected = -2 * (1-delta) * (1-delta)
        case "endpoint":
            curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [Point2D(x: 1, y: 0), Point2D(x: 1.5, y: 1.5), Point2D(x: 2, y: 3)],
                weights: [1, 2, 1])
            expected = 0
        default:
            Issue.record("The independent original U-band fixture was not selected.")
            return
        }
        let receipt = try primitive(surface())
        let integrator = CertifiedAnalyticPcurveFluxIntegrator()
        contains(try integrator.piecewisePolynomialBounds(for: .bSpline(curve), primitive: receipt,
            requestedWidth: 1e-8, tolerance: .standard), expected)
        contains(try integrator.piecewisePolynomialBounds(for: .bSpline(try curve.reversed(tolerance: .standard)),
            primitive: receipt, requestedWidth: 1e-8, tolerance: .standard), -expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPcurveNativePatchesRetainTheirEntireMeasure() throws {
        // Native pcurve knot t=1/4 maps exactly to the C0 support knot (2,1).
        // The geometric image v=u-1 gives integral -4/3*integral_2^4(u-2)du=-8/3.
        let curve = BSplineCurve2D(degree: 1, knots: [0, 0, 0.25, 1, 1],
            controlPoints: [Point2D(x: 1, y: 0), Point2D(x: 2, y: 1), Point2D(x: 4, y: 3)],
            weights: [1, 2, 1])
        contains(try CertifiedAnalyticPcurveFluxIntegrator().piecewisePolynomialBounds(for: .bSpline(curve),
            primitive: primitive(surface()), requestedWidth: 1e-8, tolerance: .standard), -8.0 / 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func UBandWorkAndWidthRemainTypedAndNonconstantKeepsRootOwner() throws {
        let receipt = try primitive(surface())
        let crossing = triangle(rational: true)[2]
        for integrator in [CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1),
                           CertifiedAnalyticPcurveFluxIntegrator(maximumDepth: 0)] {
            do {
                _ = try integrator.piecewisePolynomialBounds(for: crossing, primitive: receipt,
                    requestedWidth: 1e-30, tolerance: .standard)
                Issue.record("The complete original U band must prove its unchanged work and width allowance.")
            } catch let error as KernelError {
                #expect(error.phase == .topology && error.code == .resourceLimitExceeded)
            }
        }
        var source = surface(weight: 7)
        source.weights[0][1] = 7.0.nextUp
        let prepared = try field(source)
        #expect(try prepared.preparedPolynomialGreenPrimitive(uBase: 1) { _ in } == nil)
        do {
            _ = try CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1).rationalSurfaceBounds(
                for: crossing, field: prepared, uBase: 1, requestedWidth: 1e-8, tolerance: .standard)
            Issue.record("A nonconstant original support must retain the existing U root work owner.")
        } catch let error as KernelError {
            #expect(error.phase == .topology && error.code == .resourceLimitExceeded)
            #expect(error.residual == 2)
            #expect(error.message.contains("Bernstein-cell budget"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledOriginalUBandIntegrationPublishesNoFlux() async throws {
        let receipt = try primitive(surface())
        let curve = triangle(rational: true)[2]
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CertifiedAnalyticPcurveFluxIntegrator().piecewisePolynomialBounds(for: curve,
                primitive: receipt, requestedWidth: 1e-8, tolerance: .standard)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonUnitUniformWeightsAndNativeBasePreserveFlux() throws {
        let source = surface(weight: 7)
        contains(try integral(triangle(rational: true), primitive: primitive(source, base: 2)), -16.0 / 3)
        var perturbed = source
        perturbed.weights[0][1] = 7.0.nextUp
        var charged = 0
        let refusal = try field(perturbed).preparedPolynomialGreenPrimitive(uBase: 1) { charged += $0 }
        #expect(refusal == nil && charged > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedC0SidesAndBothNativeScalesRemainOwned() throws {
        let receipt = try primitive(surface(vCrease: true))
        let seam = try receipt.range(overClosedUV: .exact(2), v: .exact(1))
        #expect(seam.lower <= -1.0 / 3 && seam.upper >= 0)
        contains(try integral(triangle(rational: true), primitive: receipt), -6)
        let rectangle: [SurfaceParameterCurve] = [.constantV(v: 0, uStart: 1, uEnd: 4),
            .constantU(u: 4, vStart: 0, vEnd: 3), .constantV(v: 3, uStart: 4, uEnd: 1),
            .constantU(u: 1, vStart: 3, vEnd: 0)]
        contains(try integral(rectangle, primitive: receipt), -10)
    }

    @Test(.timeLimit(.minutes(1)))
    func existingLoopOwnerConsumesThePreparedPrefix() throws {
        let candidate = try TrimmedParametricSurfaceVolumeEvaluator().rationalLoopVolumeBounds(
            surface: surface(), parameterCurves: triangle(rational: false), role: .outer,
            reference: .origin, requestedWidth: 1e-8, tolerance: .standard)
        let result = try #require(candidate)
        #expect(result.lower <= -16.0 / 3 && result.upper >= -16.0 / 3)
        #expect(result.upper - result.lower <= 1e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func cumulativePreparationAndInvalidDomainRefuseExplicitly() throws {
        let prepared = try field(surface())
        var cost = 0
        let measured = try prepared.preparedPolynomialGreenPrimitive(uBase: 1) { cost += $0 }
        _ = try #require(measured)
        print("Original two-panel Green preparation charged \(cost) coefficient operations.")
        // The preceding snapshot spent 370 operations while omitting prepared-control
        // admission. Its same allowance must not publish the additional whole scan.
        var previousAllowanceConsumed = 0
        #expect(throws: KernelError.self) {
            _ = try prepared.preparedPolynomialGreenPrimitive(uBase: 1) { amount in
                guard previousAllowanceConsumed <= 370 - amount else {
                    throw KernelError(phase: .topology, code: .resourceLimitExceeded,
                        tolerance: .standard, message: "The original pre-scan allowance is exhausted.")
                }
                previousAllowanceConsumed += amount
            }
        }
        var consumed = 0
        let charge: (Int) throws -> Void = { amount in
            guard amount >= 0, consumed <= cost - amount else {
                throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: .standard,
                    message: "The caller's original cumulative coefficient allowance is exhausted.")
            }
            consumed += amount
        }
        let admitted = try prepared.preparedPolynomialGreenPrimitive(uBase: 1, consumeCoefficientOperations: charge)
        _ = try #require(admitted)
        #expect(consumed == cost)
        #expect(throws: KernelError.self) { _ = try prepared.preparedPolynomialGreenPrimitive(uBase: 1, consumeCoefficientOperations: charge) }
        #expect(throws: KernelError.self) { _ = try prepared.preparedPolynomialGreenPrimitive(uBase: 0) { _ in } }
        #expect(throws: KernelError.self) {
            _ = try CertifiedPiecewisePolynomialSurfaceFluxPrimitive(source: surface(), reference: .origin,
                tolerance: .standard, uBase: 1, uSpans: prepared.uSpans, vSpans: prepared.vSpans,
                panels: [], field: prepared, consume: { _ in })
        }
        let receipt = try primitive(surface())
        #expect(throws: KernelError.self) { _ = try receipt.range(overClosedUV: .exact(0), v: .exact(1)) }
        #expect(throws: KernelError.self) {
            _ = try CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1, maximumDepth: 0)
                .piecewisePolynomialBounds(for: triangle(rational: true)[2], primitive: receipt,
                    requestedWidth: 1e-30, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPreparationPublishesNoReceipt() async throws {
        let prepared = try field(surface())
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            return try prepared.preparedPolynomialGreenPrimitive(uBase: 1) { _ in }
        }
        task.cancel(); gate.continuation.yield(()); gate.continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }

        var preparationCost = 0
        let original = try prepared.preparedPolynomialGreenPrimitive(uBase: 1) { preparationCost += $0 }
        _ = try #require(original)
        let finalCost = preparationCost
        let publicationTask = Task {
            var consumed = 0
            return try prepared.preparedPolynomialGreenPrimitive(uBase: 1) { amount in
                consumed += amount
                if consumed == finalCost {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await publicationTask.value }
    }
}
