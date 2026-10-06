import CADCore
@testable import CADGeometry
import Testing

@Suite("General original closed curve-surface overlap")
struct OriginalGeneralClosedOverlapTests {
    private let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nonfactorableOriginalTensorReturnsWholeOwnedCorrespondence(reversed: Bool) throws {
        var source = literalSource(reversed: reversed)
        var target = literalTarget()
        let originalSource = source, originalTarget = target
        #expect(OverlapRegularGraphClosedDomainAuthority.equalPositiveDyadicProducts(1, 2, 1, 1) == false)
        let result = try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options(), tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: 0, upper: 1)))
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        source.controlPoints[1].z = 7
        target.controlPoints[0][0].z = 9
        for t in [0.0, 0.125, 0.5, 0.875, 1.0] {
            let value = try overlap.correspondence(at: t)
            try verify(value, t: t, reversed: reversed, source: originalSource, target: originalTarget)
        }
        #expect(overlap.start.surfaceParameter == SurfaceParameter(u: reversed ? 1 : 0, v: reversed ? 1 : 0))
        #expect(overlap.end.surfaceParameter == SurfaceParameter(u: reversed ? 0 : 1, v: reversed ? 0 : 1))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nonfactorableOriginalTensorClipUsesLiteralSourceEndpoints(reversed: Bool) throws {
        var request = options()
        request.surfaceURange = try ScalarInterval(lower: 0.25, upper: 0.75)
        request.surfaceVRange = request.surfaceURange
        let source = literalSource(reversed: reversed), target = literalTarget()
        let result = try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: request, tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(abs(overlap.curveRange.lower - 0.25) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 0.75) < 1e-8)
        for t in [overlap.curveRange.lower, 0.5, overlap.curveRange.upper] {
            try verify(overlap.correspondence(at: t), t: t, reversed: reversed, source: source, target: target)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0.0, 1.0])
    func nonfactorableNativeCornerRequestsReturnIsolatedIncidence(boundary: Double) throws {
        var request = options()
        request.surfaceURange = try ScalarInterval(lower: boundary, upper: boundary)
        request.surfaceVRange = request.surfaceURange
        let result = try resolver.intersectionResult(curve: .bSpline(literalSource()), surface: .bSpline(literalTarget()),
            options: request, tolerance: .standard)
        #expect(result.overlaps.isEmpty && result.points.count == 1)
        let point = try #require(result.points.first)
        #expect(point.curveParameter == boundary && point.surfaceU == boundary && point.surfaceV == boundary)
        #expect(point.residual <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonfactorableQueryCannotBypassCallerWork() throws {
        var request = options()
        request.maximumSubdivisionCells = 1
        do {
            _ = try resolver.intersectionResult(curve: .bSpline(literalSource()), surface: .bSpline(literalTarget()),
                options: request, tolerance: .standard)
            Issue.record("A general closed query bypassed its caller work ceiling.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aPositiveInteriorDeviationCannotBecomeAnOverlap() throws {
        var source = literalSource()
        let target = literalTarget()
        source.controlPoints[1].z = 1e-3
        let result = try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options(), tolerance: .standard)
        #expect(result.overlaps.isEmpty)
        for event in result.points {
            let t = event.curveParameter
            let deviation = 2e-3*t*(1-t)/(1+t*t)
            #expect(deviation >= 0)
            let point = try source.point(at: t, tolerance: .standard)
            let image = try target.point(u: event.surfaceU, v: event.surfaceV, tolerance: .standard)
            #expect((point-image).length <= ModelingTolerance.standard.distance)
            #expect(event.residual <= ModelingTolerance.standard.distance)
        }
        // U=V=t is the independently known selected-coordinate solution.
        // Its third-coordinate deviation is positive at every strict interior t.
        #expect(2e-3*0.5*(1-0.5)/(1+0.5*0.5) > ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledGeneralClosedQueryPublishesNoResult() async throws {
        let source = literalSource(), target = literalTarget(), request = options()
        let task = Task {
            while Task.isCancelled == false { await Task.yield() }
            return try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
                options: request, tolerance: .standard)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func completeHomogeneousResidualDistinguishesInteriorCoefficients(reversed: Bool) throws {
        let target = literalTarget()
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        var source = literalSource(reversed: reversed)
        var budget = OverlapProofBudget(options: options(), tolerance: .standard)
        let exact = try #require(OverlapAffineComposedResidualAuthority.certificate(
            source: source, target: target, pair: pair, budget: &budget))
        // Independent complete degree-four numerator is [0,0,0,0,0] on every axis.
        #expect(exact.errors.count == 3 && exact.errors.allSatisfy({ $0 < 1e-10 }))
        #expect(exact.start == SurfaceParameter(u: reversed ? 1 : 0, v: reversed ? 1 : 0))
        #expect(exact.end == SurfaceParameter(u: reversed ? 0 : 1, v: reversed ? 0 : 1))
        source.controlPoints[1].z = 1e-3
        let changed = try #require(OverlapAffineComposedResidualAuthority.certificate(
            source: source, target: target, pair: pair, budget: &budget))
        // Forward numerator is [0,-1/2000,-1/1500,-1/1000,0]; reverse reverses it.
        #expect(changed.errors[0] < 1e-10 && changed.errors[1] < 1e-10)
        #expect(changed.errors[2] > 1e-4)
        #expect(changed.errors[2] >= 2e-3*0.5*(1-0.5)/(1+0.5*0.5))
        #expect(exact.source.controlPoints[1].z == 0)
        let hint = try exact.candidateBox(over: ScalarInterval(lower: 0.25, upper: 0.75), budget: &budget)
        #expect(hint.u.lower <= 0.25 && hint.u.upper >= 0.75)
        #expect(hint.v.lower <= 0.25 && hint.v.upper >= 0.75)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalDerivativeTubesContainLiteralUnitSpeed(reversed: Bool) throws {
        let source = literalSource(reversed: reversed), target = literalTarget()
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        var budget = OverlapProofBudget(options: options(), tolerance: .standard)
        try budget.preparation(curve: source, surface: target)
        let root = OverlapRegularGraphRootCertifier(
            curve: try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: .standard),
            surface: try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: .standard),
            tolerance: .standard)
        let range = try ScalarInterval(lower: 0, upper: 1.0/64)
        let mid = range.midpoint, uv = reversed ? 1-mid : mid
        // The literal UV is a trial hint only; original closed/strict proof is mandatory.
        let box = try #require(root.trialBox(range: range, pair: pair,
            seed: SurfaceParameter(u: uv, v: uv), budget: &budget))
        let proof = try #require(root.proof(range: range, box: box, pair: pair, budget: &budget))
        let coefficient = try #require(OverlapAffineComposedResidualAuthority.certificate(
            source: source, target: target, pair: pair, budget: &budget))
        let transfer = try #require(root.composedResidual(proof: proof, coefficient: coefficient, budget: &budget))
        #expect(transfer.residual.absoluteUpperBound <= ModelingTolerance.standard.distance)
        let derivative = try root.composedFirstDerivatives(transfer, budget: &budget)
        let speed = reversed ? -1.0 : 1.0
        #expect(derivative.u.lower <= speed && derivative.u.upper >= speed)
        #expect(derivative.v.lower <= speed && derivative.v.upper >= speed)
        #expect(derivative.u.lower > 0 || derivative.u.upper < 0)
        #expect(derivative.v.lower > 0 || derivative.v.upper < 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func composedResidualPreparationRetainsExactCallerFees() throws {
        let source = literalSource(), target = literalTarget()
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        let fee = try OverlapAffineComposedResidualAuthority.preparationWork(degree: source.degree,
            sourceKnots: source.knots.count, targetKnots: target.uKnots.count + target.vKnots.count,
            tolerance: .standard)
        var request = options()
        request.maximumSubdivisionCells = fee
        var exact = OverlapProofBudget(options: request, tolerance: .standard)
        _ = try #require(OverlapAffineComposedResidualAuthority.certificate(
            source: source, target: target, pair: pair, budget: &exact))
        do { try exact.work(); Issue.record("Composed preparation reset its consumed work.") }
        catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        request.maximumSubdivisionCells = fee - 1
        var insufficient = OverlapProofBudget(options: request, tolerance: .standard)
        do {
            _ = try OverlapAffineComposedResidualAuthority.certificate(source: source, target: target, pair: pair, budget: &insufficient)
            Issue.record("Composed coefficients were allocated beyond the caller work cap.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        request = options()
        request.maximumPolynomialDegree = 3
        var degree = OverlapProofBudget(options: request, tolerance: .standard)
        do {
            _ = try OverlapAffineComposedResidualAuthority.certificate(source: source, target: target, pair: pair, budget: &degree)
            Issue.record("A complete degree-four residual bypassed the degree-three cap.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledComposedPreparationPublishesNoCertificate() async throws {
        let source = literalSource(), target = literalTarget(), request = options()
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            var budget = OverlapProofBudget(options: request, tolerance: .standard)
            return try OverlapAffineComposedResidualAuthority.certificate(source: source, target: target,
                pair: OverlapRegularGraphCell.Pair(first: 0, second: 1), budget: &budget)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func higherOrderTensorRetainsWholeOriginalCorrespondence(reversed: Bool) throws {
        var source = higherOrderSource(reversed: reversed), target = higherOrderTarget()
        let originalSource = source, originalTarget = target
        let result = try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options(), tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(overlap.curveRange == (try ScalarInterval(lower: 0, upper: 1)))
        #expect(overlap.maximumSpatialDeviation <= ModelingTolerance.standard.distance)
        source.controlPoints[2].z = 7
        target.controlPoints[1][1].z = 9
        for t in [0.0, 0.125, 0.5, 0.875, 1.0] {
            try verifyHigherOrder(overlap.correspondence(at: t), t: t, reversed: reversed,
                source: originalSource, target: originalTarget)
        }
        #expect(overlap.start.surfaceParameter == SurfaceParameter(u: reversed ? 1 : 0, v: reversed ? 1 : 0))
        #expect(overlap.end.surfaceParameter == SurfaceParameter(u: reversed ? 0 : 1, v: reversed ? 0 : 1))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func higherOrderTensorClipRetainsLiteralEndpoints(reversed: Bool) throws {
        let source = higherOrderSource(reversed: reversed), target = higherOrderTarget()
        var request = options()
        request.surfaceURange = try ScalarInterval(lower: 0.25, upper: 0.75)
        request.surfaceVRange = request.surfaceURange
        let result = try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: request, tolerance: .standard)
        #expect(result.points.isEmpty && result.overlaps.count == 1)
        let overlap = try #require(result.overlaps.first)
        #expect(abs(overlap.curveRange.lower - 0.25) < 1e-8)
        #expect(abs(overlap.curveRange.upper - 0.75) < 1e-8)
        for t in [overlap.curveRange.lower, 0.5, overlap.curveRange.upper] {
            try verifyHigherOrder(overlap.correspondence(at: t), t: t, reversed: reversed,
                source: source, target: target)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0.0, 1.0])
    func higherOrderNativeCornerRetainsIsolatedIncidence(boundary: Double) throws {
        var request = options()
        request.surfaceURange = try ScalarInterval(lower: boundary, upper: boundary)
        request.surfaceVRange = request.surfaceURange
        let result = try resolver.intersectionResult(curve: .bSpline(higherOrderSource()), surface: .bSpline(higherOrderTarget()),
            options: request, tolerance: .standard)
        #expect(result.overlaps.isEmpty && result.points.count == 1)
        let event = try #require(result.points.first)
        #expect(event.curveParameter == boundary && event.surfaceU == boundary && event.surfaceV == boundary)
        #expect(event.residual <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func higherOrderResidualConsumesCompleteCoefficientsAndExactFee() throws {
        let source = higherOrderSource(), target = higherOrderTarget()
        let pair = OverlapRegularGraphCell.Pair(first: 0, second: 1)
        let fee = try OverlapAffineComposedResidualAuthority.preparationWork(sourceDegree: source.degree,
            uDegree: target.uDegree, vDegree: target.vDegree, sourceKnots: source.knots.count,
            targetKnots: target.uKnots.count + target.vKnots.count, tolerance: .standard)
        var request = options()
        request.maximumSubdivisionCells = fee
        var budget = OverlapProofBudget(options: request, tolerance: .standard)
        let certificate = try #require(OverlapAffineComposedResidualAuthority.certificate(
            source: source, target: target, pair: pair, budget: &budget))
        // Ideal degree-eight cross-products are all zero. Original rounded
        // controls/weights must be enclosed, rather than asserted algebraically equal.
        #expect(certificate.errors.count == 3 && certificate.errors.allSatisfy({ $0 < 1e-10 }))
        do { try budget.work(); Issue.record("Higher-order preparation reset its original work charge.") }
        catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        request.maximumSubdivisionCells = fee - 1
        var insufficient = OverlapProofBudget(options: request, tolerance: .standard)
        do {
            _ = try OverlapAffineComposedResidualAuthority.certificate(source: source, target: target,
                pair: pair, budget: &insufficient)
            Issue.record("Higher-order coefficients bypassed the caller preparation cap.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        request = options()
        request.maximumPolynomialDegree = 7
        var degree = OverlapProofBudget(options: request, tolerance: .standard)
        do {
            _ = try OverlapAffineComposedResidualAuthority.certificate(source: source, target: target, pair: pair, budget: &degree)
            Issue.record("A complete degree-eight residual bypassed the degree-seven cap.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        var changed = source
        changed.controlPoints[2].z += 1e-3
        budget = OverlapProofBudget(options: options(), tolerance: .standard)
        let deviation = try #require(OverlapAffineComposedResidualAuthority.certificate(
            source: changed, target: target, pair: pair, budget: &budget))
        // Independent ideal midpoint deviation is 7*k*t^2*(1-t)^2/(1+t^2).
        #expect(deviation.errors[2] >= 3.5e-4)
        #expect(deviation.errors[0] < 1e-10 && deviation.errors[1] < 1e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func higherOrderInteriorDeviationCannotProduceWholeOverlap() throws {
        var source = higherOrderSource()
        source.controlPoints[2].z += 1e-3
        let target = higherOrderTarget()
        let result = try resolver.intersectionResult(curve: .bSpline(source), surface: .bSpline(target),
            options: options(), tolerance: .standard)
        #expect(result.overlaps.isEmpty)
        let middle = try source.point(at: 0.5, tolerance: .standard)
        let image = try target.point(u: 0.5, v: 0.5, tolerance: .standard)
        #expect(abs((middle-image).z-3.5e-4) < 1e-12)
        #expect((middle-image).length > ModelingTolerance.standard.distance)
        for event in result.points {
            let point = try source.point(at: event.curveParameter, tolerance: .standard)
            let targetPoint = try target.point(u: event.surfaceU, v: event.surfaceV, tolerance: .standard)
            #expect((point-targetPoint).length <= ModelingTolerance.standard.distance)
            #expect(event.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledHigherOrderPreparationPublishesNoCertificate() async throws {
        let source = higherOrderSource(), target = higherOrderTarget(), request = options()
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            var budget = OverlapProofBudget(options: request, tolerance: .standard)
            return try OverlapAffineComposedResidualAuthority.certificate(source: source, target: target,
                pair: OverlapRegularGraphCell.Pair(first: 0, second: 1), budget: &budget)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func higherOrderSource(reversed: Bool = false) -> BSplineCurve3D {
        // Degree-four Bernstein data for (t+t^2,t+t^2,2t^2+t^4)/(1+t^2).
        let points: [Point3D] = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.25, y: 0.25, z: 0),
            Point3D(x: 4.0/7, y: 4.0/7, z: 2.0/7), Point3D(x: 5.0/6, y: 5.0/6, z: 2.0/3),
            Point3D(x: 1, y: 1, z: 1.5)]
        let weights: [Double] = [1, 1, 7.0/6, 1.5, 2]
        return BSplineCurve3D(degree: 4, knots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
            controlPoints: reversed ? Array(points.reversed()) : points,
            weights: reversed ? Array(weights.reversed()) : weights)
    }

    private func higherOrderTarget() -> BSplineSurface3D {
        // Independent degree-two tensor coefficients; weights are non-factorable.
        let points: [[Point3D]] = [
            [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
            [Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 0.6, y: 0.6, z: 0.4), Point3D(x: 1, y: 2.0/3, z: 2.0/3)],
            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 2.0/3, y: 1, z: 2.0/3), Point3D(x: 1, y: 1, z: 1.5)]]
        let weights: [[Double]] = [[1, 1, 1], [1, 1.25, 1.5], [1, 1.5, 2]]
        return BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1], controlPoints: points, weights: weights)
    }

    private func verifyHigherOrder(_ value: CurveSurfaceOverlapEndpoint, t: Double, reversed: Bool,
                                  source: BSplineCurve3D, target: BSplineSurface3D) throws {
        let r = reversed ? 1-t : t, denominator = 1+r*r
        let expected = Point3D(x: r*(1+r)/denominator, y: r*(1+r)/denominator,
            z: (2*r*r+r*r*r*r)/denominator)
        #expect(abs(value.surfaceParameter.u-r) < 1e-7 && abs(value.surfaceParameter.v-r) < 1e-7)
        let point = try source.point(at: t, tolerance: .standard)
        let targetPoint = try target.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: .standard)
        #expect((point-expected).length < 1e-12)
        #expect((point-targetPoint).length <= ModelingTolerance.standard.distance)
        #expect(value.residual <= ModelingTolerance.standard.distance)
    }

    private func literalSource(reversed: Bool = false) -> BSplineCurve3D {
        let points = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0.5, z: 0), Point3D(x: 1, y: 1, z: 1)]
        return BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: reversed ? Array(points.reversed()) : points,
            weights: reversed ? [2, 1, 1] : [1, 1, 2])
    }

    private func literalTarget() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 1)]], weights: [[1, 1], [1, 2]])
    }

    private func options() -> CurveSurfaceIntersectionOptions {
        .init(maximumSubdivisionDepth: 20,
            maximumSubdivisionCells: 4_194_304, maximumIterations: 64)
    }

    private func verify(_ value: CurveSurfaceOverlapEndpoint, t: Double, reversed: Bool,
                        source: BSplineCurve3D, target: BSplineSurface3D) throws {
        let r = reversed ? 1-t : t, denominator = 1+r*r
        let expected = Point3D(x: r*(1+r)/denominator, y: r*(1+r)/denominator, z: 2*r*r/denominator)
        #expect(abs(value.surfaceParameter.u-r) < 1e-7 && abs(value.surfaceParameter.v-r) < 1e-7)
        let point = try source.point(at: t, tolerance: .standard)
        let targetPoint = try target.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: .standard)
        #expect((point-expected).length < 1e-12)
        #expect((point-targetPoint).length <= ModelingTolerance.standard.distance)
        #expect(value.residual <= ModelingTolerance.standard.distance)
    }
}
