import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Certified cone-cylinder full-branch skew-cylinder reduction")
struct CertifiedConeCylinderFullBranchSkewCylinderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func allSourceComponentsSupportCertifiedFullBranchReductions() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))
        let curves = try certifiedConeCylinderCurves(
            first: cone,
            second: cylinder
        )
        #expect(curves.count == 2)
        for curve in curves {
            try verifyFullBranchIntersections(
                curve: curve,
                sourceCylinder: cylinder
            )
        }
    }

    private func certifiedConeCylinderCurves(
        first: Surface3D,
        second: Surface3D
    ) throws -> [Curve3D] {
        let intersections = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: first,
                second: second,
                tolerance: tolerance
            )
        let candidates: [(key: String, curve: Curve3D)] =
            intersections.compactMap { intersection in
                guard case let .curve(result) = intersection,
                      case let .certifiedIntersection(.coneCylinder(curve)) =
                        result.curve else {
                    return nil
                }
                return (
                    key: curve.componentKind.rawValue,
                    curve: result.curve
                )
            }
        return candidates.sorted {
            $0.key < $1.key
        }.map(\.curve)
    }

    private func verifyFullBranchIntersections(
        curve: Curve3D,
        sourceCylinder: Surface3D
    ) throws {
        let expectedParameter = 0.375
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        guard case let .cylinder(source) =
            CanonicalAnalyticSurface(sourceCylinder) else {
            throw failure(
                .invalidInput,
                "The skew-cylinder fixture requires an exact source cylinder."
            )
        }
        let skewAxis = try (
            source.axis + Vector3D.unitX
        ).normalized(tolerance: tolerance.distance)
        var radial = try (
            source.axis - skewAxis * source.axis.dot(skewAxis)
        ).normalized(tolerance: tolerance.distance)
        if radial.x > 0.0 {
            radial = -radial
        }
        let target = try fullBranchSkewCylinder(
            point: expectedGeometry.position,
            axis: skewAxis,
            radial: radial,
            radius: 20.0,
            source: source
        )
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.01,
            upper: expectedParameter + 0.01
        )
        let intersections = try diagnosticStage("full-branch transverse") {
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: target,
                options: options(curveRange: curveRange),
                tolerance: tolerance
            )
        }
        #expect(intersections.count == 1)
        let intersection = try #require(intersections.first)
        #expect(
            abs(intersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        try verifyCylinderIntersection(
            intersection,
            expectedKind: .transverse,
            curve: curve,
            cylinder: target
        )

        guard case let .cylinder(canonicalTarget) =
            CanonicalAnalyticSurface(target) else {
            throw failure(
                .invalidInput,
                "The full-branch fixture requires an exact target cylinder."
            )
        }
        let reversedTarget = Surface3D.analytic(.cylinder(
            origin: canonicalTarget.origin + canonicalTarget.axis * 2.0,
            axis: -canonicalTarget.axis,
            radius: canonicalTarget.radius
        ))
        let reversed = try diagnosticStage("full-branch reversed") {
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: reversedTarget,
                options: options(curveRange: curveRange),
                tolerance: tolerance
            )
        }
        #expect(reversed.count == intersections.count)
        #expect(reversed.allSatisfy { candidate in
            intersections.contains {
                ($0.point - candidate.point).length <= tolerance.distance
            }
        })

        let targetProjection = try target.parameterProjection(
            of: expectedGeometry.position,
            tolerance: tolerance
        )
        let excludedTargetRange = try ScalarInterval(
            lower: targetProjection.v + 1.0,
            upper: targetProjection.v + 2.0
        )
        let rangeExcluded = try diagnosticStage(
            "full-branch target range"
        ) {
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: target,
                options: options(
                    curveRange: curveRange,
                    surfaceVRange: excludedTargetRange
                ),
                tolerance: tolerance
            )
        }
        #expect(rangeExcluded.isEmpty)
        let excludedCurveRange = try ScalarInterval(
            lower: expectedParameter + 0.02,
            upper: expectedParameter + 0.03
        )
        let curveRangeExcluded = try diagnosticStage(
            "full-branch curve range"
        ) {
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: target,
                options: options(curveRange: excludedCurveRange),
                tolerance: tolerance
            )
        }
        #expect(curveRangeExcluded.isEmpty)
    }

    private func fullBranchSkewCylinder(
        point: Point3D,
        axis: Vector3D,
        radial: Vector3D,
        radius: Double,
        source: CanonicalAnalyticSurface.Cylinder
    ) throws -> Surface3D {
        let target = CanonicalAnalyticSurface.Cylinder(
            origin: point + radial * -radius,
            axis: axis,
            radius: radius
        )
        guard try DefaultCertifiedCylinderCylinderReductionEligibility()
            .supportsCertifiedIntersection(
                first: target,
                second: source,
                tolerance: tolerance
            ) else {
            throw failure(
                .intersectionFailure,
                "The fixed skew-cylinder fixture must retain a certified full-branch section."
            )
        }
        return .analytic(.cylinder(
            origin: target.origin,
            axis: target.axis,
            radius: target.radius
        ))
    }

    private func verifyCylinderIntersection(
        _ intersection: CurveSurfaceIntersection,
        expectedKind: CurveSurfaceIntersectionKind,
        curve: Curve3D,
        cylinder: Surface3D
    ) throws {
        #expect(intersection.kind == expectedKind)
        #expect(intersection.residual <= tolerance.distance)
        let curvePoint = try curve.point(
            at: intersection.curveParameter,
            tolerance: tolerance
        )
        #expect(
            (curvePoint - intersection.point).length
                <= tolerance.distance
        )
        let cylinderPoint = try cylinder.point(
            u: intersection.surfaceU,
            v: intersection.surfaceV,
            tolerance: tolerance
        )
        #expect(
            (cylinderPoint - intersection.point).length
                <= tolerance.distance
        )
    }

    private func options(
        curveRange: ScalarInterval,
        surfaceVRange: ScalarInterval? = nil
    ) -> CurveSurfaceIntersectionOptions {
        CurveSurfaceIntersectionOptions(
            curveRange: curveRange,
            surfaceVRange: surfaceVRange,
            maximumSubdivisionDepth: 20
        )
    }

    private func diagnosticStage<Result>(
        _ label: String,
        operation: () throws -> Result
    ) throws -> Result {
        do {
            return try operation()
        } catch let error as KernelError {
            throw KernelError(
                phase: error.phase,
                code: error.code,
                featureID: error.featureID,
                subshapeID: error.subshapeID,
                residual: error.residual,
                tolerance: error.tolerance,
                message: "\(label): \(error.message)"
            )
        } catch {
            throw failure(
                .intersectionFailure,
                "\(label): \(error)"
            )
        }
    }

    private func failure(
        _ code: KernelErrorCode,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: code,
            tolerance: tolerance,
            message: message
        )
    }
}
