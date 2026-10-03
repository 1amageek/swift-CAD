import CADCore
import CADGeometry
import CADIR
import Foundation

@main
struct CADGeometryWASMSmoke {
    static func main() throws {
        let tolerance = ModelingTolerance.standard
        let curve = try BSplineCurve3D.periodic(degree: 3, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 2, z: 0.5),
                Point3D(x: -1, y: 0, z: 1), Point3D(x: 0, y: -2, z: 0.5)],
            weights: [1, 2, 0.5, 1.5], tolerance: tolerance)
            .changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
        try require(try curve.normalizedParameter(-1.75, tolerance: tolerance) == 8.25,
            "Public normalization lost the chosen fundamental interval.")
        let highDegree = try BSplineCurve3D.periodic(degree: 5, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 2, z: 0.5),
                Point3D(x: -1, y: 0, z: 1), Point3D(x: 0, y: -2, z: 0.5)], tolerance: tolerance)
        let highRefined = try highDegree.insertingKnot(4.25, tolerance: tolerance)
        for parameter in [-1.75, 3, 4.25, 7.75, 8.25] {
            let expected = try highDegree.parameterDerivatives(at: parameter, tolerance: tolerance)
            let actual = try highRefined.parameterDerivatives(at: parameter, tolerance: tolerance)
            try require((expected.position - actual.position).length < 1e-11
                && (expected.firstDerivative - actual.firstDerivative).length < 1e-10
                && (expected.secondDerivative - actual.secondDerivative).length < 1e-9,
                "A polynomial cycle with degree greater than its control count changed under refinement.")
        }
        let refined = try curve.insertingKnot(3, tolerance: tolerance)
            .insertingKnot(4.25, tolerance: tolerance)
        let trimmed = try refined.trimmed(from: 7.5, to: 9.5, tolerance: tolerance)
        try require(refined.isPeriodic && refined.periodicOrigin == 7.25,
            "Refinement lost the periodic cycle or origin.")
        try require(!trimmed.isPeriodic && trimmed.domain == .closed(7.5, 9.5),
            "Restriction did not retain its exact finite interval.")
        for parameter in [7.5, 7.75, 8, 8.25, 8.75, 9.5] {
            let source = try curve.parameterDerivatives(at: parameter, tolerance: tolerance)
            let actual = try trimmed.parameterDerivatives(at: parameter, tolerance: tolerance)
            let translated = try refined.parameterDerivatives(at: parameter - 15, tolerance: tolerance)
            for value in [actual, translated] {
                try require((source.position - value.position).length < 1e-11
                    && (source.firstDerivative - value.firstDerivative).length < 1e-10
                    && (source.secondDerivative - value.secondDerivative).length < 1e-9,
                    "Periodic homogeneous editing changed the curve or its derivatives.")
            }
        }
        let prepared = try ValidatedCurve3D(.bSpline(curve), tolerance: tolerance)
        let point = try prepared.point(at: 8.25)
        let projection = try prepared.parameterProjection(of: point)
        try require(abs(projection.parameter - 8.25) < 1e-7 && projection.residual <= tolerance.distance,
            "Prepared periodic projection returned the wrong representative.")
        let bounds = try prepared.tessellationIntervalEvaluation(ScalarInterval(lower: 7.75, upper: 8.25)).bounds
        try require(bounds.secondDerivativeMagnitudeUpperBound.isFinite,
            "The periodic smooth interval has no finite derivative bound.")
        for parameter in [7.75, 8, 8.25] {
            try require(try curve.parameterDerivatives(at: parameter, tolerance: tolerance).secondDerivative.length
                <= bounds.secondDerivativeMagnitudeUpperBound, "A periodic derivative escaped its interval bound.")
        }
        let signature = SubshapeGeometrySignature.edge(CurveSpanGeometrySignature(
            curve: .bSpline(refined), startParameter: 7.75, endParameter: 8.25,
            startPoint: try refined.point(at: 7.75, tolerance: tolerance),
            endPoint: try refined.point(at: 8.25, tolerance: tolerance)))
        let decoded = try JSONDecoder().decode(SubshapeGeometrySignature.self, from: JSONEncoder().encode(signature))
        try require(decoded == signature, "Source transport changed exact periodic geometry.")
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(curve)) as? [String: Any] else {
            throw failure("Periodic source encoding did not produce a keyed value.")
        }
        object.removeValue(forKey: "isPeriodic")
        do {
            _ = try JSONDecoder().decode(BSplineCurve3D.self, from: JSONSerialization.data(withJSONObject: object))
            throw failure("The current curve schema accepted missing periodicity.")
        } catch DecodingError.keyNotFound(let key, _) {
            try require(key.stringValue == "isPeriodic", "Current-schema refusal reported the wrong missing field.")
        }
        do {
            _ = try curve.insertingKnot(4.25, expansionOptions: .init(maximumKnotInsertionWork: 1), tolerance: tolerance)
            throw failure("Periodic refinement exceeded its work budget.")
        } catch let error as KernelError {
            try require(error.code == .resourceLimitExceeded, "Resource refusal lost its typed failure.")
        }
        do {
            _ = try curve.trimmed(from: 9, to: 7, tolerance: tolerance)
            throw failure("An invalid periodic interval returned success.")
        } catch let error as KernelError {
            try require(error.code == .invalidInput, "Invalid-input refusal lost its typed failure.")
        }
        try verifyKnotReduction(curve: refined, tolerance: tolerance)
        try verifyPeriodicTensor(tolerance: tolerance)
        try verifyContinuousOverlap(tolerance: tolerance)
        try OverlapIsocurveSmoke.verify(tolerance: tolerance)
        try OverlapIsocurveSmoke.verifyRegularGraph(tolerance: tolerance)
        try OverlapIsocurveSmoke.verifyOriginalC0Graph(tolerance: tolerance)
        try verifyCommonConversion(tolerance: tolerance)
        try NonManifoldTopologySmoke.verify(tolerance: tolerance)
        try C0SurfaceAreaSmoke.verify()
        print("CADGeometryWASMSmoke passed: periodic curves and tensor surfaces, evaluation/jets, origins, exact refinement/restriction, certified knot reduction, projection, bounds, edge/face transport, authored, native rational isocurve and regular/C0 graph overlaps, common conversion, non-manifold retention/admission and C0 surface area/centroid with typed refusals")
    }

    private static func verifyKnotReduction(curve: BSplineCurve3D, tolerance: ModelingTolerance) throws {
        let remover: any BSplineKnotRemoving = CertifiedBSplineKnotRemover()
        let options = BSplineKnotRemovalOptions()
        let periodic = try remover.reducingMultiplicity(of: curve, at: 4.25, to: 0,
            maximumDeviation: 1e-7, options: options, tolerance: tolerance)
        try require(periodic.geometry.isPeriodic && periodic.geometry.periodicOrigin == curve.periodicOrigin
            && periodic.certifiedMaximumDeviation <= 1e-7, "Cyclic knot removal lost its contract.")
        for parameter in [3, 4.25, 7.75, 8.25, 13.25] {
            try require(try (periodic.geometry.point(at: parameter, tolerance: tolerance)
                - curve.point(at: parameter, tolerance: tolerance)).length <= periodic.certifiedMaximumDeviation + 1e-12,
                "Cyclic knot removal escaped its full-domain bound.")
        }
        let base = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 0, y: 0), .init(x: 1, y: 2), .init(x: 3, y: 0)], weights: [1, 2, 0.75])
        let input = try base.insertingKnot(0.4, tolerance: tolerance)
        let reduced = try remover.reducingMultiplicity(of: input, at: 0.4, to: 0,
            maximumDeviation: 1e-7, options: options, tolerance: tolerance)
        try require(reduced.geometry.knots == base.knots && reduced.certifiedMaximumDeviation <= 1e-7,
            "Rational pcurve knot removal did not retain its source basis.")
        do {
            _ = try remover.reducingMultiplicity(of: curve, at: 4.25, to: 0,
                maximumDeviation: 1e-7, options: .init(maximumWork: 1), tolerance: tolerance)
            throw failure("Knot reduction ignored its work budget.")
        } catch BSplineKnotRemovalError.resourceLimitExceeded { }
    }

    private static func verifyPeriodicTensor(tolerance: ModelingTolerance) throws {
        let circle: [(Double, Double)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let points = (0..<4).map { j in
            circle.map { Point3D(x: (3 + circle[j].0) * $0.0,
                y: (3 + circle[j].0) * $0.1, z: circle[j].1) }
        }
        let weights = (0..<4).map { j in (0..<4).map { 1 + Double($0 + j) * 0.025 } }
        let surface = try BSplineSurface3D.periodic(uDegree: 3, vDegree: 3,
            uKnots: [0, 1, 2, 3, 4], vKnots: [0, 1, 2, 3, 4], controlPoints: points, weights: weights,
            isUPeriodic: true, isVPeriodic: true, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .u, to: 3.25, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .v, to: -0.25, tolerance: tolerance)
        let refined = try surface.insertingKnot(direction: .u, value: 0, tolerance: tolerance)
            .insertingKnot(direction: .v, value: 1.25, tolerance: tolerance)
        let remover: any BSplineKnotRemoving = CertifiedBSplineKnotRemover()
        let uReduced = try remover.reducingMultiplicity(of: refined, direction: .u, at: 0, to: 1,
            maximumDeviation: 1e-7, options: .init(), tolerance: tolerance)
        let vReduced = try remover.reducingMultiplicity(of: uReduced.geometry, direction: .v, at: 1.25, to: 0,
            maximumDeviation: 1e-7, options: .init(), tolerance: tolerance)
        try require(vReduced.geometry.isUPeriodic && vReduced.geometry.isVPeriodic
            && vReduced.geometry.uPeriodicOrigin == surface.uPeriodicOrigin
            && vReduced.geometry.vPeriodicOrigin == surface.vPeriodicOrigin, "Tensor knot reduction lost independent origins.")
        for (u, v) in [(3.75, -0.25), (4.0, 0.0), (4.25, 0.25), (4.5, 0.5)] {
            try require(try (vReduced.geometry.point(u: u, v: v, tolerance: tolerance)
                - surface.point(u: u, v: v, tolerance: tolerance)).length < 2e-7,
                "U/V tensor knot reduction changed the original surface beyond its admitted deviation.")
        }
        let restriction = try refined.trimmed(uFrom: 3.75, uTo: 4.5, vFrom: -0.25, vTo: 0.5, tolerance: tolerance)
        try require(refined.isUPeriodic && refined.isVPeriodic && refined.uPeriodicOrigin == 3.25,
            "Tensor refinement lost its independent cycles or origins.")
        try require(!restriction.isUPeriodic && !restriction.isVPeriodic
            && restriction.uDomain == .closed(3.75, 4.5), "Tensor restriction did not retain its finite interval.")
        for (u, v) in [(3.75, -0.25), (4.0, 0.0), (4.25, 0.25), (4.5, 0.5)] {
            let expected = try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance)
            for value in [try restriction.parameterDerivatives(u: u, v: v, tolerance: tolerance),
                          try refined.parameterDerivatives(u: u - 8, v: v + 12, tolerance: tolerance)] {
                try require((expected.position - value.position).length < 1e-11
                    && (expected.tangentU - value.tangentU).length < 1e-10
                    && (expected.tangentV - value.tangentV).length < 1e-10
                    && (expected.secondDerivativeUV - value.secondDerivativeUV).length < 1e-9,
                    "Exact tensor editing changed its locus or mixed derivatives.")
            }
        }
        let target = try surface.point(u: 0.25, v: 0.25, tolerance: tolerance)
        let projected = try Surface3D.bSpline(surface).parameterProjection(of: target, tolerance: tolerance)
        try require(abs(projected.u - 4.25) < 1e-7 && abs(projected.v - 0.25) < 1e-7
            && projected.residual <= tolerance.distance, "Periodic tensor projection lost the chosen representatives.")
        let seamTarget = try surface.point(u: 0, v: 0, tolerance: tolerance)
        let seam = try Surface3D.bSpline(surface).parameterProjection(of: seamTarget, tolerance: tolerance)
        try require(abs(seam.u - 4) < 1e-7 && abs(seam.v) < 1e-7,
            "Two-axis seam roots were returned as distinct projections.")
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 3.75, upper: 4.25),
            v: try ScalarInterval(lower: -0.25, upper: 0.25))
        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(of: .bSpline(surface), over: box, tolerance: tolerance)
        for (u, v) in [(3.75, -0.25), (4.0, 0.0), (4.25, 0.25), (3.875, 0.125)] {
            let jet = try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance)
            try require(enclosure.position.contains(jet.position) && enclosure.tangentU.contains(jet.tangentU)
                && enclosure.tangentV.contains(jet.tangentV) && enclosure.secondDerivativeUU.contains(jet.secondDerivativeUU)
                && enclosure.secondDerivativeUV.contains(jet.secondDerivativeUV) && enclosure.secondDerivativeVV.contains(jet.secondDerivativeVV),
                "A seam-crossing tensor jet escaped its interval enclosure.")
        }
        let isocurve = try surface.uIsoparametricCurve(atV: 8.25, tolerance: tolerance)
        try require(isocurve.isPeriodic && isocurve.periodicOrigin == 3.25
            && (try isocurve.point(at: 4.25, tolerance: tolerance) - target).length < 1e-11,
            "A periodic tensor isocurve lost its varying axis.")
        let face = SubshapeGeometrySignature.untrimmedFace(surface: .bSpline(refined))
        let transported = try JSONDecoder().decode(SubshapeGeometrySignature.self, from: JSONEncoder().encode(face))
        try require(face == transported, "Face transport lost exact tensor periodicity.")
        let single = try BSplineSurface3D.periodic(uDegree: 3, vDegree: 1,
            uKnots: [0, 1, 2, 3, 4], vKnots: [0, 0, 1, 1], controlPoints: [points[0], points[1]],
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        try require((try single.point(u: 0.25, v: 0.5, tolerance: tolerance)
            - single.point(u: 8.25, v: 0.5, tolerance: tolerance)).length < 1e-11,
            "A single periodic tensor axis failed to wrap independently.")
        do {
            _ = try surface.insertingKnot(direction: .u, value: 0.25,
                expansionOptions: .init(maximumKnotInsertionWork: 1), tolerance: tolerance)
            throw failure("Tensor refinement ignored its aggregate work budget.")
        } catch let error as KernelError {
            try require(error.code == .resourceLimitExceeded, "Tensor work refusal lost its typed failure.")
        }
        let corner = try BSplineSurface3D.periodic(uDegree: 1, vDegree: 1,
            uKnots: [0, 1, 2, 3, 4], vKnots: [0, 1, 2, 3, 4], controlPoints: points,
            isUPeriodic: true, isVPeriodic: true, tolerance: tolerance)
        do {
            _ = try DefaultSurfaceDifferentialEncloser().enclosure(of: .bSpline(corner), over: box, tolerance: tolerance)
            throw failure("A C0 tensor seam returned a smooth interval jet.")
        } catch let error as KernelError {
            try require(error.code == .singularGeometry, "Tensor corner refusal lost its typed failure.")
        }
        let folded = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 1,
            uKnots: [0, 1, 3, 4], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0), .origin],
                [Point3D(x: 0, y: 0, z: 1), Point3D(x: 1, y: 0, z: 1), Point3D(x: 0, y: 0, z: 1)]],
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        do {
            _ = try Surface3D.bSpline(folded).parameterProjection(of: Point3D(x: 0.7, y: 0, z: 0.5),
                options: .init(maximumSubdivisionDepth: 0), tolerance: tolerance)
            throw failure("A folded periodic Bezier span returned an unproved unique root.")
        } catch let error as KernelError {
            try require(error.code == .resourceLimitExceeded, "Folded tensor refusal lost its typed failure.")
        }
        let collapsed = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 1,
            uKnots: [0, 1], vKnots: [0, 0, 1, 1], controlPoints: [[.origin], [Point3D(x: 0, y: 0, z: 1)]],
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        do {
            _ = try Surface3D.bSpline(collapsed).parameterProjection(of: Point3D(x: 0, y: 0, z: 0.5),
                options: .init(maximumSubdivisionDepth: 0), tolerance: tolerance)
            throw failure("A collapsed tensor cycle returned an arbitrary unique root.")
        } catch let error as KernelError {
            try require(error.code == .singularSystem, "Collapsed tensor refusal lost its typed failure.")
        }
    }

    private static func verifyContinuousOverlap(tolerance: ModelingTolerance) throws {
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: (0..<3).map { v in (0..<3).map { u in
                Point3D(x: Double(u) / 2, y: Double(v) / 2, z: u == 1 && v == 1 ? 0.5 : 0)
            } }))
        let lift = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface,
            parameterCurve: .affine(origin: .init(x: 0.1, y: 0.5), direction: .init(x: 0.8, y: 0),
                startParameter: 0, endParameter: 1)))
        let result = try resolver.intersectionResult(curve: lift, surface: surface,
            options: .init(curveRange: ScalarInterval(lower: 0, upper: 1),
                surfaceURange: ScalarInterval(lower: 0.3, upper: 0.7)), tolerance: tolerance)
        guard result.overlaps.count == 1, result.points.isEmpty, let overlap = result.overlaps.first else {
            throw failure("Authored overlap did not retain one complete clipped interval.")
        }
        try require(abs(overlap.curveRange.lower - 0.25) < 1e-8 && abs(overlap.curveRange.upper - 0.75) < 1e-8
            && overlap.maximumSpatialDeviation <= tolerance.distance, "Authored overlap lost its finite proof range.")
        for t in [overlap.curveRange.lower, 0.5, overlap.curveRange.upper] {
            let value = try overlap.correspondence(at: t)
            let actual = try surface.point(u: value.surfaceParameter.u, v: value.surfaceParameter.v, tolerance: tolerance)
            try require(value.residual <= tolerance.distance && (actual - value.point).length <= tolerance.distance
                && (try lift.point(at: t, tolerance: tolerance) - value.point).length <= tolerance.distance,
                "Authored overlap correspondence lost forward membership.")
        }
        let hosting = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let tangent = try hosting.differentialGeometry(u: 0, v: 0, tolerance: tolerance).tangentU
        let alpha = tolerance.angle / 2
        let length = 100 * tolerance.distance / alpha
        let normal = try (Vector3D.unitZ + tangent * alpha).normalized(tolerance: tolerance.distance)
        let tilted = Surface3D.plane(Plane3D(origin: .origin, normal: normal))
        let harmonic = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: hosting,
            parameterCurve: .harmonic(center: .init(x: 0, y: 0), cosine: .init(x: 0, y: 1),
                sine: .init(x: length, y: 0), startParameter: 0, endParameter: 2 * .pi)))
        let distance = abs(try (harmonic.point(at: 0.25, tolerance: tolerance) - .origin).dot(normal))
        try require(distance > 99 * tolerance.distance, "Tilted-plane fixture did not violate spatial membership.")
        do {
            _ = try resolver.intersectionResult(curve: harmonic, surface: tilted, options: .init(), tolerance: tolerance)
            throw failure("Angular support agreement authorized an invalid complete overlap.")
        } catch let error as KernelError {
            try require(error.code == .intersectionFailure, "Tilted-plane refusal lost its typed classification.")
        }
    }

    private static func verifyCommonConversion(tolerance: ModelingTolerance) throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let line = Curve3D.analytic(.line(origin: .origin, direction: .unitX))
        let range = try ScalarInterval(lower: 0, upper: 1)
        let limits = GeometryConversionRequirements(maximumPositionError: 1e-8, maximumTangentAngle: 1e-5,
            maximumCurvatureError: 1e-5)
        let result = try converter.approximateCurve(source: NativeCurveConversionSource(line, tolerance: tolerance),
            over: range, requirements: limits, tolerance: tolerance)
        try require(result.parameters == range && result.curve.degree == 3 && result.curve.controlPointCount == 4
            && result.guarantee.certifiedBoxCount > 0 && result.guarantee.positionErrorUpperBound <= limits.maximumPositionError
            && result.guarantee.tangentAngleUpperBound <= limits.maximumTangentAngle
            && result.guarantee.curvatureErrorUpperBound <= limits.maximumCurvatureError,
            "Same-chart conversion did not establish its continuous geometric conditions.")
        let observed = try (result.curve.point(at: 0.37, tolerance: tolerance) - line.point(at: 0.37, tolerance: tolerance)).length
        try require(observed <= result.guarantee.positionErrorUpperBound, "Converted curve escaped its advertised position bound.")
        let plane = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
        let box = SurfaceParameterBox(u: range, v: range)
        let tensor = try converter.approximateSurface(source: NativeSurfaceConversionSource(plane, tolerance: tolerance),
            over: box, requirements: limits, tolerance: tolerance)
        try require(tensor.parameters == box && tensor.surface.uDegree == 3 && tensor.surface.vDegree == 3
            && tensor.guarantee.certifiedBoxCount > 0 && tensor.guarantee.positionErrorUpperBound <= limits.maximumPositionError
            && tensor.guarantee.tangentAngleUpperBound <= limits.maximumTangentAngle
            && tensor.guarantee.curvatureErrorUpperBound <= limits.maximumCurvatureError,
            "Same-chart tensor conversion did not establish its continuous geometric conditions.")
        let tensorError = try (tensor.surface.point(u: 0.37, v: 0.61, tolerance: tolerance)
            - plane.point(u: 0.37, v: 0.61, tolerance: tolerance)).length
        try require(tensorError <= tensor.guarantee.positionErrorUpperBound, "Converted tensor escaped its advertised position bound.")
        let periodic = try BSplineCurve3D.periodic(degree: 1, cycleKnots: [0, 1, 2, 3, 4],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .init(x: 1, y: 1, z: 0), .init(x: 0, y: 1, z: 0)],
            tolerance: tolerance)
        let fake = BSplineCurve3D(degree: 1, knots: [-0.25, -0.25, 0.25, 0.25],
            controlPoints: [.init(x: -0.25, y: 0, z: 0), .init(x: 0.25, y: 0, z: 0)])
        let discrepancy = try (periodic.point(at: -0.25, tolerance: tolerance) - fake.point(at: -0.25, tolerance: tolerance)).length
        try require(discrepancy > 0.35, "Negative-cycle false candidate no longer exercises the spatial defect.")
        do {
            _ = try converter.certifyCurve(source: NativeCurveConversionSource(.bSpline(periodic), tolerance: tolerance),
                candidate: fake, over: ScalarInterval(lower: -0.25, upper: 0.25), requirements: limits, tolerance: tolerance)
            throw failure("A clipped negative cycle authorized a false continuous certificate.")
        } catch GeometryConversionError.toleranceRejected { }
        let highDegree = BSplineCurve3D(degree: 16,
            knots: Array(repeating: 0.0, count: 17) + Array(repeating: 1.0, count: 17),
            controlPoints: (0...16).map { Point3D(x: Double($0) / 16, y: 0, z: 0) })
        var bounded = limits
        bounded.maximumDegree = 16
        bounded.maximumControlPointCount = 17
        bounded.maximumCertificationBoxes = 1
        bounded.maximumScalarCount = 784
        do {
            _ = try converter.certifyCurve(source: NativeCurveConversionSource(line, tolerance: tolerance),
                candidate: highDegree, over: range, requirements: bounded, tolerance: tolerance)
            throw failure("High-degree enclosure ignored its cumulative scalar budget.")
        } catch GeometryConversionError.resourceLimitExceeded { }
        var sourceLimits = limits
        sourceLimits.maximumCandidateCount = 2
        sourceLimits.maximumControlPointCount = 4
        do {
            _ = try converter.approximateCurve(source: RefusingConversionSource(), over: range,
                requirements: sourceLimits, tolerance: tolerance)
            throw failure("A source failure published converted geometry.")
        } catch GeometryConversionError.toleranceRejected { }
    }

    private struct RefusingConversionSource: GeometryCurveConversionSource {
        func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws { }
        func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
            (.init(x: parameter, y: 0, z: 0), .unitX)
        }
        func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
            throw GeometryConversionError.toleranceRejected
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .validation, code: .classificationFailure, tolerance: .standard, message: message)
    }
}
