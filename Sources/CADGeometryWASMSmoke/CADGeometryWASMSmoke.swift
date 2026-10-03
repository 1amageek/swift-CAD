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
        print("CADGeometryWASMSmoke passed: periodic curves and tensor surfaces, evaluation/jets, origins, exact refinement/restriction, certified knot reduction, projection, bounds, edge/face transport and typed refusals")
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

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .validation, code: .classificationFailure, tolerance: .standard, message: message)
    }
}
