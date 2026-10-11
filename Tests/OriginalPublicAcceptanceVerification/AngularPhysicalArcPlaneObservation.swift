import Foundation
import CADCore
@testable import CADGeometry

/// One ordinary public observation; numerical representatives do not certify coverage.
@main struct AngularPhysicalArcPlaneObservation {
    struct SetupFailure: Error {}

    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        fflush(nil)
    }

    static func run() throws {
        // Keep the independent oracle in Q(pi), separate from numerical output.
        var oracleAdmission = ExactScalarLedger(limits: try .init(work: 8_388_608,
            storageBytes: 64_000_000, valueDepth: 32, coefficientDepth: 32))
        let field = try OriginalPiScalarDomain(using: &oracleAdmission)
        let pi = try field.pi(using: &oracleAdmission)
        let zero = try field.integer(0, using: &oracleAdmission)
        let one = try field.integer(1, using: &oracleAdmission)
        let two = try field.integer(2, using: &oracleAdmission)
        let three = try field.integer(3, using: &oracleAdmission)
        let four = try field.integer(4, using: &oracleAdmission)
        let gain = try field.adding(one, field.multiplying(two, pi, using: &oracleAdmission), using: &oracleAdmission)
        let denominator = try field.multiplying(two, gain, using: &oracleAdmission)
        let first = try field.dividing(pi, denominator, using: &oracleAdmission)
        let second = try field.dividing(field.multiplying(three, pi, using: &oracleAdmission), denominator, using: &oracleAdmission)
        let binaryPeriod = try field.binary64(exactly: 2 * Double.pi, using: &oracleAdmission)
        let firstLabel = try field.dividing(binaryPeriod, four, using: &oracleAdmission)
        let secondLabel = try field.dividing(field.multiplying(three, binaryPeriod, using: &oracleAdmission), four, using: &oracleAdmission)
        guard try field.compare(pi, two, using: &oracleAdmission) == .greater,
              try field.compare(first, zero, using: &oracleAdmission) == .greater,
              try field.compare(first, second, using: &oracleAdmission) == .less,
              try field.compare(second, one, using: &oracleAdmission) == .less,
              try field.compare(firstLabel, secondLabel, using: &oracleAdmission) == .less else { throw SetupFailure() }
        try emit(["stage": "exact-oracle", "field": "Q(pi)",
            "gain": "1+2*pi", "roots": ["pi/(2*(1+2*pi))", "3*pi/(2*(1+2*pi))"],
            "childLabels": ["B/4", "3*B/4"], "B": "exact binary64(2*Double.pi)",
            "completeRootCount": 2, "overlapCount": 0,
            "xyz": [[0,3,0], [0,-3,0]], "targetUV": [[0,-3], [0,3]],
            "authority": "Independent source-law oracle; not an observed public receipt."])

        var usage = try NativeRationalSourceAllowance(maximumWork: 80_000_000,
            maximumCells: 1_000_000, maximumStorage: 268_435_456, maximumDepth: 32,
            operationCheck: { try CurrentTaskCancellationChecker().checkCancellation() })
        let source = Curve3D.circle(.init(center: .origin, normal: .unitZ, radius: 3))
        let wrapper = try OriginalAngularTransportCurve3D(source: source,
            transport: .physicalRadianArc(start: .zero, end: .one, additionalTurns: 1),
            tolerance: .standard, usage: &usage)
        let curve = Curve3D.originalAngularTransport(wrapper)
        let surface = Surface3D.analytic(.plane(origin: .origin, normal: .unitX))
        var options = CurveSurfaceIntersectionOptions()
        options.curveRange = try .init(lower: 0, upper: 1)
        options.surfaceURange = try .init(lower: -1, upper: 1)
        options.surfaceVRange = try .init(lower: -4, upper: 4)
        try emit(["stage": "before-public-entry", "entry": "DefaultCurveSurfaceIntersector.intersectionResult",
            "ordinaryCalls": 1, "curveRange": [0,1], "surfaceURange": [-1,1], "surfaceVRange": [-4,4]])
        do {
            let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve,
                surface: surface, options: options, tolerance: .standard)
            let points: [[String: Any]] = result.points.map { point in
                ["t": point.curveParameter, "u": point.surfaceU, "v": point.surfaceV,
                 "xyz": [point.point.x, point.point.y, point.point.z],
                 "kind": String(describing: point.kind), "residual": point.residual,
                 "originalCurveBoundary": point.originalCurveBoundary != nil]
            }
            try emit(["stage": "public-result", "representation": String(describing: result.representation),
                "pointCount": result.points.count, "overlapCount": result.overlaps.count, "points": points,
                "hasPositiveDimensionalSolutions": result.hasPositiveDimensionalSolutions,
                "receiptPresence": [
                    "originalNativePoints": result.originalNativePoints != nil,
                    "originalNativeRelations": result.originalNativeRelations != nil,
                    "originalPolynomialPoints": result.originalPolynomialPoints != nil,
                    "originalAffinePoints": result.originalAffinePoints != nil,
                    "originalCoonsPoints": result.originalCoonsPoints != nil,
                    "originalExactGeometricRelation": result.originalExactGeometricRelation != nil,
                    "originalIssuedGeometricRelation": result.originalIssuedGeometricRelation != nil,
                    "originalIssuedNumericalPoints": result.originalIssuedNumericalPoints != nil,
                    "originalContainedLiftPlaneFamily": result.originalContainedLiftPlaneFamily != nil,
                    "originalRevolutionAxisRelation": result.originalRevolutionAxisRelation != nil],
                "cellComplete": false])
        } catch let error as KernelError {
            try emit(["stage": "public-failure", "type": "KernelError",
                "phase": String(describing: error.phase), "code": error.code.rawValue,
                "message": error.message, "description": String(describing: error), "cellComplete": false])
        } catch {
            try emit(["stage": "public-failure", "type": String(reflecting: type(of: error)),
                "description": String(describing: error), "cellComplete": false])
        }
    }

    static func main() {
        do { try run() }
        catch { print("SETUP_FAILURE", String(reflecting: type(of: error)), error); exit(2) }
    }
}
