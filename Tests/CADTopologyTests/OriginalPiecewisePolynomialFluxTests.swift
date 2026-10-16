import Foundation
import Synchronization
import Testing
import CADCore
import CADGeometry
@testable import CADTopology

@Suite("Original piecewise polynomial Green flux")
struct OriginalPiecewisePolynomialFluxTests {
    private typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval

    private func retainedKernelFailure(_ error: any Error) -> KernelError? {
        if let kernel = error as? KernelError { return kernel }
        if let query = error as? OriginalQueryFailure { return retainedKernelFailure(query.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return retainedKernelFailure(cause)
        }
        return nil
    }

    private func surface(weight: Double = 1, vCrease: Bool = false) -> BSplineSurface3D {
        let u = [1.0, 2, 4], h = [1.0, 2, 8]
        let v = vCrease ? [0.0, 1, 3] : [0.0, 3]
        let k = vCrease ? [0.0, 1, 5] : [0.0, 0]
        return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [1, 1, 2, 4, 4],
            vKnots: vCrease ? [0, 0, 1, 3, 3] : [0, 0, 3, 3],
            controlPoints: v.indices.map { j in u.indices.map { i in Point3D(x: u[i], y: v[j], z: h[i] + k[j]) } },
            weights: v.map { _ in u.map { _ in weight } })
    }
    private func field(_ source: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws -> CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField {
        let candidate = try CertifiedRationalBezierSurfaceFluxIntegrator().preparedField(
            surface: source, reference: .origin, tolerance: .standard, using: &execution)
        return try #require(candidate)
    }
    private func primitive(_ source: BSplineSurface3D, base: Double = 1, using execution: inout OriginalQueryExecution) throws -> CertifiedPiecewisePolynomialSurfaceFluxPrimitive {
        var charged = 0
        let candidate = try field(source, using: &execution).preparedPolynomialGreenPrimitive(uBase: base, coefficientOperations: &charged, maximumCoefficientOperations: Int.max, using: &execution)
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
    private func integral(_ curves: [SurfaceParameterCurve], primitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive, using execution: inout OriginalQueryExecution) throws -> Interval {
        let integrator = CertifiedAnalyticPcurveFluxIntegrator()
        var total = Interval.exact(0)
        for curve in curves {
            total = total + (try integrator.piecewisePolynomialBounds(for: curve, primitive: primitive,
                requestedWidth: 1e-8 / Double(curves.count), tolerance: .standard, using: &execution))
        }
        return total
    }
    private func contains(_ bounds: Interval, _ value: Double) {
        #expect(bounds.lower <= value && bounds.upper >= value)
        #expect(bounds.width <= 1e-8)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func literalC0TriangleAndReverseUseOriginalRationalJets(rational: Bool) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let receipt = try primitive(surface(), using: &execution)
        let curves = triangle(rational: rational)
        contains(try integral(curves, primitive: receipt, using: &execution), -16.0 / 3)
        let reverse = try curves.reversed().map { try $0.reversed(tolerance: .standard) }
        contains(try integral(reverse, primitive: receipt, using: &execution), 16.0 / 3)
        let rectangle: [SurfaceParameterCurve] = [.constantV(v: 0, uStart: 1, uEnd: 4),
            .constantU(u: 4, vStart: 0, vEnd: 3), .constantV(v: 3, uStart: 4, uEnd: 1),
            .constantU(u: 1, vStart: 3, vEnd: 0)]
        contains(try integral(rectangle, primitive: receipt, using: &execution), -8)
    }

    /// The original C0 support has density 0 for u<=2 and -4/3 for u>=2.
    /// Its U-anchored Green value is -4/3*max(0,u-2), including both knot sides.
    @Test(.timeLimit(.minutes(1)), arguments: ["crossing", "contact", "onSeam", "nearEndpoint", "endpoint"])
    func closedUBandsRetainLiteralOriginalRationalFlux(kind: String) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
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
        let receipt = try primitive(surface(), using: &execution)
        let integrator = CertifiedAnalyticPcurveFluxIntegrator()
        contains(try integrator.piecewisePolynomialBounds(for: .bSpline(curve), primitive: receipt,
            requestedWidth: 1e-8, tolerance: .standard, using: &execution), expected)
        contains(try integrator.piecewisePolynomialBounds(for: .bSpline(try curve.reversed(tolerance: .standard)),
            primitive: receipt, requestedWidth: 1e-8, tolerance: .standard, using: &execution), -expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPcurveNativePatchesRetainTheirEntireMeasure() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        // Native pcurve knot t=1/4 maps exactly to the C0 support knot (2,1).
        // The geometric image v=u-1 gives integral -4/3*integral_2^4(u-2)du=-8/3.
        let curve = BSplineCurve2D(degree: 1, knots: [0, 0, 0.25, 1, 1],
            controlPoints: [Point2D(x: 1, y: 0), Point2D(x: 2, y: 1), Point2D(x: 4, y: 3)],
            weights: [1, 2, 1])
        contains(try CertifiedAnalyticPcurveFluxIntegrator().piecewisePolynomialBounds(for: .bSpline(curve),
            primitive: primitive(surface(), using: &execution), requestedWidth: 1e-8, tolerance: .standard, using: &execution), -8.0 / 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func UBandWorkAndWidthRemainTypedAndNonconstantKeepsRootOwner() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let receipt = try primitive(surface(), using: &execution)
        let crossing = triangle(rational: true)[2]
        for integrator in [CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1),
                           CertifiedAnalyticPcurveFluxIntegrator(maximumDepth: 0)] {
            do {
                _ = try integrator.piecewisePolynomialBounds(for: crossing, primitive: receipt,
                    requestedWidth: 1e-30, tolerance: .standard, using: &execution)
                Issue.record("The complete original U band must prove its unchanged work and width allowance.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.phase == .topology && error.code == .resourceLimitExceeded)
            }
        }
        var source = surface(weight: 7)
        source.weights[0][1] = 7.0.nextUp
        let prepared = try field(source, using: &execution)
        var coefficientOperations = 0
        #expect(try prepared.preparedPolynomialGreenPrimitive(uBase: 1, coefficientOperations: &coefficientOperations, maximumCoefficientOperations: Int.max, using: &execution) == nil)
        do {
            _ = try CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1).rationalSurfaceBounds(
                for: crossing, field: prepared, uBase: 1, requestedWidth: 1e-8, tolerance: .standard, using: &execution)
            Issue.record("A nonconstant original support must retain the existing U root work owner.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.phase == .topology && error.code == .resourceLimitExceeded)
            #expect(error.residual == 2)
            #expect(error.message.contains("Bernstein-cell budget"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledOriginalUBandIntegrationPublishesNoFlux() async throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let receipt = try primitive(surface(), using: &execution)
        let curve = triangle(rational: true)[2]
        let task = Task {
            var execution = try OriginalQueryExecution.independentGeometry()
            withUnsafeCurrentTask { $0?.cancel() }
            return try CertifiedAnalyticPcurveFluxIntegrator().piecewisePolynomialBounds(for: curve,
                primitive: receipt, requestedWidth: 1e-8, tolerance: .standard, using: &execution)
        }
        do { _ = try await task.value; Issue.record("Cancelled original U-band integration published flux.") }
        catch { #expect(retainedCancellation(error)) }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonUnitUniformWeightsAndNativeBasePreserveFlux() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let source = surface(weight: 7)
        contains(try integral(triangle(rational: true), primitive: primitive(source, base: 2, using: &execution), using: &execution), -16.0 / 3)
        var perturbed = source
        perturbed.weights[0][1] = 7.0.nextUp
        var charged = 0
        let refusal = try field(perturbed, using: &execution).preparedPolynomialGreenPrimitive(uBase: 1, coefficientOperations: &charged, maximumCoefficientOperations: Int.max, using: &execution)
        #expect(refusal == nil && charged > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedC0SidesAndBothNativeScalesRemainOwned() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let receipt = try primitive(surface(vCrease: true), using: &execution)
        let seam = try receipt.range(overClosedUV: .exact(2), v: .exact(1), using: &execution)
        #expect(seam.lower <= -1.0 / 3 && seam.upper >= 0)
        contains(try integral(triangle(rational: true), primitive: receipt, using: &execution), -6)
        let rectangle: [SurfaceParameterCurve] = [.constantV(v: 0, uStart: 1, uEnd: 4),
            .constantU(u: 4, vStart: 0, vEnd: 3), .constantV(v: 3, uStart: 4, uEnd: 1),
            .constantU(u: 1, vStart: 3, vEnd: 0)]
        contains(try integral(rectangle, primitive: receipt, using: &execution), -10)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        let prepared = try field(surface(), using: &execution)
        var cost = 0
        let measured = try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
            coefficientOperations: &cost, maximumCoefficientOperations: Int.max, using: &execution)
        _ = try #require(measured)
        print("Original two-panel Green preparation charged \(cost) coefficient operations.")
        // The earlier 370-operation allowance omits the prepared-control scan.
        var previousAllowanceConsumed = 0
        #expect(throws: KernelError.self) {
            _ = try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
                coefficientOperations: &previousAllowanceConsumed,
                maximumCoefficientOperations: 370, using: &execution)
        }
        var consumed = 0
        let admitted = try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
            coefficientOperations: &consumed, maximumCoefficientOperations: cost, using: &execution)
        _ = try #require(admitted)
        #expect(consumed == cost)
        #expect(throws: KernelError.self) {
            _ = try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
                coefficientOperations: &consumed, maximumCoefficientOperations: cost, using: &execution)
        }
        var invalidCoefficientOperations = 0
        #expect(throws: KernelError.self) {
            _ = try prepared.preparedPolynomialGreenPrimitive(uBase: 0,
                coefficientOperations: &invalidCoefficientOperations,
                maximumCoefficientOperations: Int.max, using: &execution)
        }
        #expect(throws: KernelError.self) {
            _ = try CertifiedPiecewisePolynomialSurfaceFluxPrimitive(source: surface(), reference: .origin,
                tolerance: .standard, uBase: 1, uSpans: prepared.uSpans, vSpans: prepared.vSpans,
                panels: [], field: prepared, coefficientOperations: &invalidCoefficientOperations,
                maximumCoefficientOperations: Int.max, using: &execution)
        }
        let receipt = try primitive(surface(), using: &execution)
        do {
            _ = try receipt.range(overClosedUV: .exact(0), v: .exact(1), using: &execution)
            Issue.record("An outside native domain published a Green range.")
        } catch {
            let cause = try #require(retainedKernelFailure(error))
            #expect(cause.phase == .topology && cause.code == .invalidInput)
        }
        do {
            _ = try CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1, maximumDepth: 0)
                .piecewisePolynomialBounds(for: triangle(rational: true)[2], primitive: receipt,
                    requestedWidth: 1e-30, tolerance: .standard, using: &execution)
            Issue.record("An exhausted polynomial proof allowance published Green bounds.")
        } catch {
            let cause = try #require(retainedKernelFailure(error))
            #expect(cause.phase == .topology && cause.code == .resourceLimitExceeded)
        }
    }

    private func retainedCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let scalar = error as? ExactScalarFailure {
            if case .cancelled = scalar { return true }
            if case .admissionRejected(let cause) = scalar { return retainedCancellation(cause) }
        }
        if let query = error as? OriginalQueryFailure { return retainedCancellation(query.originalError) }
        return (error as? KernelError)?.code == .cancelled
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPreparationPublishesNoReceipt() async throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let prepared = try field(surface(), using: &execution)
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            var execution = try OriginalQueryExecution.independentGeometry()
            var coefficientOperations = 0
            for await _ in gate.stream { break }
            return try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
                coefficientOperations: &coefficientOperations, maximumCoefficientOperations: Int.max,
                using: &execution)
        }
        task.cancel(); gate.continuation.yield(()); gate.continuation.finish()
        do { _ = try await task.value; Issue.record("Cancelled preparation published a receipt.") }
        catch { #expect(retainedCancellation(error)) }

        var preparationCost = 0
        let before = execution.budget.snapshot.work
        let original = try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
            coefficientOperations: &preparationCost, maximumCoefficientOperations: Int.max, using: &execution)
        _ = try #require(original)
        let finalCost = execution.budget.snapshot.work - before
        let publicationTask = Task {
            let consumed = Mutex(0)
            let budget = try OriginalQueryBudget(consumeWorkUnits: { amount in
                let total = consumed.withLock { value in value += amount; return value }
                if total == finalCost { withUnsafeCurrentTask { $0?.cancel() } }
            })
            var execution = OriginalQueryExecution(budget: budget,
                limits: try .init(maximumValueDepth: Int.max, maximumCoefficientDepth: Int.max))
            var coefficientOperations = 0
            return try prepared.preparedPolynomialGreenPrimitive(uBase: 1,
                coefficientOperations: &coefficientOperations, maximumCoefficientOperations: Int.max,
                using: &execution)
        }
        do { _ = try await publicationTask.value; Issue.record("Cancellation at the final admission published a receipt.") }
        catch { #expect(retainedCancellation(error)) }
    }
}
