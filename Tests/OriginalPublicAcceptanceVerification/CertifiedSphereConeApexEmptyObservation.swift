import Foundation
import CADCore
@testable import CADGeometry

/// Observe the original public constructor and one ordinary rich query.
@main struct CertifiedSphereConeApexEmptyObservation {
    enum SetupFailure: Error { case unexpectedApexComponents }

    static func emit(_ value: [String: Any]) throws {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
        fflush(nil)
    }

    static func failure(_ error: Error, stage: String) throws {
        if let error = error as? KernelError {
            try emit(["stage": stage, "type": "KernelError", "phase": String(describing: error.phase),
                "code": error.code.rawValue, "message": error.message,
                "description": String(describing: error), "cellComplete": false])
        } else {
            try emit(["stage": stage, "type": String(reflecting: type(of: error)),
                "description": String(describing: error), "cellComplete": false])
        }
    }

    // Preserve the existing test constructor and its exact public call.
    static func apexReducedCurves() throws -> [CertifiedAnalyticAnalyticIntersectionCurve] {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 1.0))
        let cone = Surface3D.analytic(.cone(apex: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ, halfAngle: atan(0.5)))
        return try DefaultSurfaceSurfaceIntersector().intersections(first: sphere,
            second: cone, tolerance: .standard).compactMap { intersection in
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereCone(curve) = exact.definition,
                      curve.componentKind == .apexReducedAngularInterval else { return nil }
                return exact
            }
    }

    static func run() throws {
        try emit(["stage": "frozen-oracle", "cell": "CS-CERT-SPHERECONE-APEX-EMPTY-01",
            "sourceSnapshot": "6b8ea4954b616f9669eed1536bd02baa5021a79f",
            "closedT": [0,1], "targetU": [-2,2], "targetV": [-2,2], "targetZ": 2,
            "wholeThetaHeightUpper": "15/16 < 1 < 2; mathematical coefficients and imported binary coefficients",
            "oracleWorksheetSHA256": "a18d0488a08e53eaa7b1419709067109bcfa5d66cbf8e61263077b37f23ea09e",
            "completeTupleCount": 0, "overlapCount": 0, "imageCount": 0,
            "fiberCount": 0, "incidentCount": 0,
            "authority": "Independent whole-theta outward bound; no source sphere-membership assumption."])
        try emit(["stage": "before-constructor", "entry": "DefaultSurfaceSurfaceIntersector.intersections",
            "halfAngleBits": String(atan(0.5).bitPattern, radix: 16), "ordinaryCSCalls": 0])
        let components: [CertifiedAnalyticAnalyticIntersectionCurve]
        do { components = try apexReducedCurves() }
        catch { try failure(error, stage: "constructor-failure"); return }
        let ordered = components.sorted { $0.sphereConeCurve!.lowerAngle < $1.sphereConeCurve!.lowerAngle }
        guard ordered.count == 2, let selected = ordered.first,
              let sphereCone = selected.sphereConeCurve else { throw SetupFailure.unexpectedApexComponents }
        let bounds: [[String: Any]] = ordered.map { component in
            let curve = component.sphereConeCurve!
            return ["kind": String(describing: curve.componentKind),
                "lowerAngle": curve.lowerAngle, "upperAngle": curve.upperAngle,
                "lowerAngleBits": String(curve.lowerAngle.bitPattern, radix: 16),
                "upperAngleBits": String(curve.upperAngle.bitPattern, radix: 16)]
        }
        let curve = selected.curve
        try emit(["stage": "constructor-result", "apexComponentCount": ordered.count,
            "allOriginalBounds": bounds, "selectedIndex": 0,
            "selectedKind": String(describing: sphereCone.componentKind),
            "queryCurveVariant": String(describing: curve), "selection": "minimum lowerAngle"])
        let surface = Surface3D.analytic(.plane(origin: Point3D(x: 0, y: 0, z: 2), normal: .unitZ))
        var options = CurveSurfaceIntersectionOptions()
        options.curveRange = try .init(lower: 0, upper: 1)
        options.surfaceURange = try .init(lower: -2, upper: 2)
        options.surfaceVRange = try .init(lower: -2, upper: 2)
        try emit(["stage": "before-public-entry", "entry": "DefaultCurveSurfaceIntersector.intersectionResult",
            "ordinaryCSCalls": 1, "curveRange": [0,1], "surfaceURange": [-2,2], "surfaceVRange": [-2,2]])
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
                "receiptPresence": ["originalNativePoints": result.originalNativePoints != nil,
                    "originalNativeRelations": result.originalNativeRelations != nil,
                    "originalPolynomialPoints": result.originalPolynomialPoints != nil,
                    "originalAffinePoints": result.originalAffinePoints != nil,
                    "originalCoonsPoints": result.originalCoonsPoints != nil,
                    "originalExactGeometricRelation": result.originalExactGeometricRelation != nil,
                    "originalIssuedGeometricRelation": result.originalIssuedGeometricRelation != nil,
                    "originalIssuedNumericalPoints": result.originalIssuedNumericalPoints != nil,
                    "originalContainedLiftPlaneFamily": result.originalContainedLiftPlaneFamily != nil,
                    "originalRevolutionAxisRelation": result.originalRevolutionAxisRelation != nil,
                    "originalAngularPlaneRelation": result.originalAngularPlaneRelation != nil],
                "cellComplete": false])
        } catch { try failure(error, stage: "public-failure") }
    }

    static func main() {
        do { try run() }
        catch {
            do { try failure(error, stage: "setup-failure") }
            catch { print("OBSERVATION_RECORD_FAILURE", error) }
            exit(2)
        }
    }
}
