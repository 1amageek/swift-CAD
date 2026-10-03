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
        print("CADGeometryWASMSmoke passed: periodic normalization/evaluation, rational and high-degree polynomial refinement, restriction, projection, bounds, source transport and typed refusals")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .validation, code: .classificationFailure, tolerance: .standard, message: message)
    }
}
