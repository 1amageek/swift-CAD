import CADCore
import CADGeometry

struct OverlapIsocurveSmoke {
    static func verify(tolerance: ModelingTolerance) throws {
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        for variesU in [true, false] {
            var patch = rationalPatch()
            // These literal homogeneous sections are independent of the target's
            // isoparametric extraction implementation. Only the V source is reversed.
            var source = variesU
                ? BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                    controlPoints: [Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 0.5, y: 0.5, z: 0.3), Point3D(x: 1, y: 0.5, z: 0)],
                    weights: [1.25, 2.5, 1.25])
                : BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                    controlPoints: [Point3D(x: 0.5, y: 1, z: 0), Point3D(x: 0.5, y: 0.5, z: 1.0 / 3), Point3D(x: 0.5, y: 0, z: 0)],
                    weights: [1.5, 2.25, 1.5])
            let originalSource = source
            let originalTarget = Surface3D.bSpline(patch)
            let clip = try ScalarInterval(lower: 0.2, upper: 0.6)
            var options = CurveSurfaceIntersectionOptions(curveRange: try ScalarInterval(lower: 0.1, upper: 0.9))
            if variesU { options.surfaceURange = clip } else { options.surfaceVRange = clip }
            let result = try resolver.intersectionResult(curve: .bSpline(source), surface: originalTarget,
                options: options, tolerance: tolerance)
            let overlap = try soleOverlap(result, tolerance: tolerance)
            let lower = variesU ? 0.2 : 0.4, upper = variesU ? 0.6 : 0.8
            try require(abs(overlap.curveRange.lower - lower) < 1e-12
                && abs(overlap.curveRange.upper - upper) < 1e-12,
                "Native rational isocurve lost its source trim or orientation.", tolerance)
            try verifyBound(overlap, tolerance: tolerance)
            source.controlPoints[0] = Point3D(x: 50, y: 50, z: 50)
            patch.controlPoints[1][1] = Point3D(x: 60, y: 60, z: 60)
            for fraction in [0.0, 0.5, 1.0] {
                let parameter = fraction == 0 ? overlap.curveRange.lower : fraction == 1 ? overlap.curveRange.upper
                    : overlap.curveRange.lower + overlap.curveRange.width * fraction
                let native = variesU ? parameter : 1 - parameter
                let value = try overlap.correspondence(at: parameter)
                let expectedUV = variesU ? SurfaceParameter(u: native, v: 0.5)
                    : SurfaceParameter(u: 0.5, v: native)
                let product = native * (1 - native)
                let denominator = variesU ? 1 + 2 * product : 1 + product
                let expectedPoint = variesU
                    ? Point3D(x: (2 * native - native * native) / denominator, y: 0.5, z: 1.2 * product / denominator)
                    : Point3D(x: 0.5, y: (1.5 * native - 0.5 * native * native) / denominator, z: product / denominator)
                try require(abs(value.surfaceParameter.u - expectedUV.u) < 1e-12
                    && abs(value.surfaceParameter.v - expectedUV.v) < 1e-12,
                    "Owned isocurve correspondence changed its exact chart map.", tolerance)
                try require((value.point - expectedPoint).length < 1e-12,
                    "Native rational isocurve differs from the independent homogeneous known answer.", tolerance)
                try verifyForward(value, source: .bSpline(originalSource), target: originalTarget, tolerance: tolerance)
                if fraction == 0 { try require(value == overlap.start, "Isocurve start endpoint lost its correspondence.", tolerance) }
                if fraction == 1 { try require(value == overlap.end, "Isocurve end endpoint lost its correspondence.", tolerance) }
            }
        }

        let large = 18_014_398_509_481_984.0
        let shiftedTolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-18)
        var shiftedPatch = rationalPatch()
        let upper = large + 65_536
        shiftedPatch.uKnots = [large, large, large, upper, upper, upper]
        let shiftedSource = BSplineCurve3D(degree: 2, knots: shiftedPatch.uKnots,
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0), .origin],
            weights: [1, 2, 1])
        let shiftedTarget = Surface3D.bSpline(shiftedPatch)
        let shiftedClip = try ScalarInterval(lower: large + 16_384, upper: large + 49_152)
        let shiftedResult = try resolver.intersectionResult(curve: .bSpline(shiftedSource), surface: shiftedTarget,
            options: .init(curveRange: try ScalarInterval(lower: large + 8_192, upper: upper - 8_192),
                surfaceURange: shiftedClip), tolerance: shiftedTolerance)
        let shiftedOverlap = try soleOverlap(shiftedResult, tolerance: shiftedTolerance)
        try require(shiftedOverlap.curveRange == shiftedClip,
            "Large shifted reversed chart lost its exact retained interval.", shiftedTolerance)
        try verifyBound(shiftedOverlap, tolerance: shiftedTolerance)
        for parameter in [shiftedClip.lower, large + 32_768, shiftedClip.upper] {
            let value = try shiftedOverlap.correspondence(at: parameter)
            let native = large + upper - parameter
            let fraction = (native - large) / 65_536
            let expectedX = (2 * fraction - fraction * fraction) / (1 + 2 * fraction * (1 - fraction))
            try require(value.surfaceParameter.u == native && value.surfaceParameter.v == 0
                && (value.point - Point3D(x: expectedX, y: 0, z: 0)).length < 1e-12,
                "Large shifted correspondence lost its signed affine direction or known point.", shiftedTolerance)
            try verifyForward(value, source: .bSpline(shiftedSource), target: shiftedTarget, tolerance: shiftedTolerance)
        }

        // This extremely wide chart reaches the existing bounded inverse
        // projection admission before any compensated boundary inversion.
        // Preserve that explicit exhaustion; do not claim boundary-path coverage.
        var widePatch = rationalPatch()
        widePatch.uKnots = [0, 0, 0, large, large, large]
        let wideSource = BSplineCurve3D(degree: 2, knots: widePatch.uKnots,
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0), .origin],
            weights: [1, 2, 1])
        try expectFailure(.resourceLimitExceeded, tolerance: shiftedTolerance) {
            _ = try resolver.intersectionResult(curve: .bSpline(wideSource), surface: .bSpline(widePatch),
                options: .init(curveRange: try ScalarInterval(lower: large - 4, upper: large),
                    surfaceURange: try ScalarInterval(lower: 0.5, upper: 1)), tolerance: shiftedTolerance)
        }
        let limited = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0.5, z: 0), Point3D(x: 0.5, y: 0.5, z: 0.3), Point3D(x: 1, y: 0.5, z: 0)],
            weights: [1.25, 2.5, 1.25])
        try expectFailure(.resourceLimitExceeded, tolerance: tolerance) {
            _ = try resolver.intersectionResult(curve: .bSpline(limited), surface: .bSpline(rationalPatch()),
                options: .init(maximumSubdivisionCells: 2), tolerance: tolerance)
        }
    }

    static func verifyRegularGraph(tolerance: ModelingTolerance) throws {
        var source = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 0.25, y: 0.25, z: 0), Point3D(x: 0.5, y: 0.5, z: 0.25)],
            weights: [1, 2, 4])
        var target = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .origin, Point3D(x: 0.5, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0.5)]],
            weights: [[1, 1.5, 2], [1, 1.5, 2]])
        let originalSource = Curve3D.bSpline(source), originalTarget = Surface3D.bSpline(target)
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        var options = CurveSurfaceIntersectionOptions(curveRange: try ScalarInterval(lower: 0.1, upper: 0.8),
            maximumSubdivisionDepth: 20, maximumSubdivisionCells: 4_194_304, maximumCandidateCount: 16_384)
        let complete = try soleOverlap(resolver.intersectionResult(curve: originalSource,
            surface: originalTarget, options: options, tolerance: tolerance), tolerance: tolerance)
        try require(complete.curveRange == options.curveRange, "Regular graph lost complete source authority.", tolerance)
        try verifyBound(complete, tolerance: tolerance)
        source.controlPoints[1] = Point3D(x: 10, y: 10, z: 10)
        target.controlPoints[1][2] = Point3D(x: 20, y: 20, z: 20)
        for t in [0.1, 0.2, 0.43, 0.8] {
            let value = try complete.correspondence(at: t)
            let h = t / (1 + t), u = (h + (h * h + 4 * h).squareRoot()) / 2
            try require(abs(value.surfaceParameter.u - u) < 1e-7 && abs(value.surfaceParameter.v - h) < 1e-7
                && (value.point - Point3D(x: h, y: h, z: h * h)).length < 1e-12,
                "Owned regular graph differs from its independent algebraic correspondence.", tolerance)
            try verifyForward(value, source: originalSource, target: originalTarget, tolerance: tolerance)
        }
        options.surfaceURange = try ScalarInterval(lower: 0.5, upper: 0.75)
        let clipped = try soleOverlap(resolver.intersectionResult(curve: originalSource,
            surface: originalTarget, options: options, tolerance: tolerance), tolerance: tolerance)
        try require(abs(clipped.curveRange.lower - 0.2) < 1e-8
            && abs(clipped.curveRange.upper - 9.0 / 19.0) < 1e-8,
            "Regular graph lost its transverse original-chart clip.", tolerance)
        try verifyBound(clipped, tolerance: tolerance)
        options.maximumSubdivisionCells = 2
        try expectFailure(.resourceLimitExceeded, tolerance: tolerance) {
            _ = try resolver.intersectionResult(curve: originalSource, surface: originalTarget,
                options: options, tolerance: tolerance)
        }
    }

    static func verifyOriginalC0Graph(tolerance: ModelingTolerance) throws {
        try verifyOriginalKnotGraph(isC1: false, tolerance: tolerance)
    }

    static func verifyOriginalC1Graph(tolerance: ModelingTolerance) throws {
        try verifyOriginalKnotGraph(isC1: true, tolerance: tolerance)
    }

    private static func verifyOriginalKnotGraph(isC1: Bool, tolerance: ModelingTolerance) throws {
        let source = Curve3D.bSpline(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 0.25, y: 0.25, z: 0), Point3D(x: 0.5, y: 0.5, z: 0.25)],
            weights: [1, 2, 4]))
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        let x = isC1 ? [0.0, 0, 0.5, 1.25] : [0.0, 0, 0.25, 0.75, 1.5]
        let knots = isC1 ? [0.0, 0, 0, 0.5, 1, 1, 1] : [0.0, 0, 0, 0.5, 0.5, 1, 1, 1]
        for swapped in [false, true] {
            let net = [x.map { Point3D(x: $0, y: 0, z: 0) }, x.map { Point3D(x: $0, y: 1, z: $0) }]
            let points = swapped ? x.indices.map { u in net.map { $0[u] } } : net
            var surface = BSplineSurface3D(uDegree: swapped ? 1 : 2, vDegree: swapped ? 2 : 1,
                uKnots: swapped ? [0, 0, 1, 1] : knots, vKnots: swapped ? knots : [0, 0, 1, 1],
                controlPoints: points, weights: points.map { $0.map { _ in 1 } })
            let original = Surface3D.bSpline(surface)
            var options = CurveSurfaceIntersectionOptions(curveRange: try ScalarInterval(lower: 0.1, upper: 0.8),
                maximumSubdivisionDepth: 20, maximumSubdivisionCells: 4_194_304, maximumCandidateCount: 16_384)
            let complete = try soleOverlap(resolver.intersectionResult(curve: source,
                surface: original, options: options, tolerance: tolerance), tolerance: tolerance)
            try require(complete.curveRange == options.curveRange, "Original-knot graph lost original source span.", tolerance)
            try verifyBound(complete, tolerance: tolerance)
            surface.controlPoints[0][0] = Point3D(x: 8, y: 9, z: 10)
            for t in [0.1, 0.3, 1.0 / 3.0, 0.4, 0.8] {
                let h = t / (1 + t)
                let u = h <= 0.25 ? h.squareRoot() : isC1
                    ? (1 + (8 * h - 1).squareRoot()) / 4 : (0.75 + h).squareRoot() - 0.5
                let value = try complete.correspondence(at: t)
                try require(abs(value.surfaceParameter.u - (swapped ? h : u)) < 1e-7
                    && abs(value.surfaceParameter.v - (swapped ? u : h)) < 1e-7,
                    "Original-knot graph differs from its independent piecewise inverse.", tolerance)
                try verifyForward(value, source: source, target: original, tolerance: tolerance)
            }
            let clip = try ScalarInterval(lower: 0.4, upper: 0.55)
            if swapped { options.surfaceVRange = clip } else { options.surfaceURange = clip }
            let clipped = try soleOverlap(resolver.intersectionResult(curve: source,
                surface: original, options: options, tolerance: tolerance), tolerance: tolerance)
            try require(abs(clipped.curveRange.lower - 4.0 / 21.0) < 1e-8
                && abs(clipped.curveRange.upper - (isC1 ? 61.0 / 139.0 : 141.0 / 259.0)) < 1e-8,
                "Original-knot graph lost its independent source clip endpoints.", tolerance)
            try verifyBound(clipped, tolerance: tolerance)
            try verifyForward(clipped.start, source: source, target: original, tolerance: tolerance)
            try verifyForward(clipped.end, source: source, target: original, tolerance: tolerance)
        }
    }

    private static func rationalPatch() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: (0..<3).map { v in (0..<3).map { u in
                Point3D(x: Double(u) / 2, y: Double(v) / 2, z: u == 1 && v == 1 ? 0.5 : 0)
            } }, weights: [[1, 2, 1], [1.5, 3, 1.5], [1, 2, 1]])
    }

    private static func soleOverlap(_ result: CurveSurfaceIntersectionResult,
                                    tolerance: ModelingTolerance) throws -> CurveSurfaceOverlap {
        guard result.overlaps.count == 1, result.points.isEmpty, let overlap = result.overlaps.first else {
            throw failure("Native isocurve query did not publish one complete overlap without discrete points.", tolerance)
        }
        return overlap
    }

    private static func verifyBound(_ overlap: CurveSurfaceOverlap, tolerance: ModelingTolerance) throws {
        try require(overlap.maximumSpatialDeviation.isFinite && overlap.maximumSpatialDeviation >= 0
            && overlap.maximumSpatialDeviation <= tolerance.distance,
            "Native isocurve lost its whole-domain spatial certificate bound.", tolerance)
    }

    private static func verifyForward(_ value: CurveSurfaceOverlapEndpoint, source: Curve3D,
                                      target: Surface3D, tolerance: ModelingTolerance) throws {
        let sourcePoint = try source.point(at: value.curveParameter, tolerance: tolerance)
        let targetPoint = try target.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: tolerance)
        try require((value.point - sourcePoint).length < 1e-12 && value.residual.isFinite
            && value.residual <= tolerance.distance && (targetPoint - sourcePoint).length <= tolerance.distance,
            "Native isocurve source identity or forward residual failed.", tolerance)
    }

    private static func expectFailure(_ code: KernelErrorCode, tolerance: ModelingTolerance,
                                      _ operation: () throws -> Void) throws {
        do {
            try operation()
            throw failure("Native isocurve query returned success for a required typed refusal.", tolerance)
        } catch let error as KernelError {
            try require(error.code == code,
                "Native isocurve expected \(code) but received \(error).", tolerance)
        }
    }

    private static func require(_ condition: Bool, _ message: String, _ tolerance: ModelingTolerance) throws {
        guard condition else { throw failure(message, tolerance) }
    }

    private static func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance, message: message)
    }
}
