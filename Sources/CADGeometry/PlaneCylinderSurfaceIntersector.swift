import Foundation
import CADCore

struct PlaneCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let axialProjection = plane.normal.dot(cylinder.axis)
        if abs(axialProjection) <= tolerance.angle {
            return try axialLines(
                plane: plane,
                cylinder: cylinder,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }

        let axisParameter = -((cylinder.origin - plane.origin).dot(plane.normal)) / axialProjection
        let center = cylinder.origin + cylinder.axis * axisParameter
        let majorRadius = cylinder.radius / abs(axialProjection)
        let curve: Curve3D
        if abs(majorRadius - cylinder.radius) <= tolerance.distance {
            curve = .circle(Circle3D(
                center: center,
                normal: plane.normal,
                radius: cylinder.radius
            ))
        } else {
            let minorAxis = try cylinder.axis.cross(plane.normal).normalized(
                tolerance: tolerance.angle
            )
            let majorAxis = try plane.normal.cross(minorAxis).normalized(
                tolerance: tolerance.angle
            )
            curve = .analytic(.ellipse(
                center: center,
                normal: plane.normal,
                majorAxis: majorAxis,
                majorRadius: majorRadius,
                minorRadius: cylinder.radius
            ))
        }
        return [try verifier.curve(
            curve,
            kind: .transverse,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
            tolerance: tolerance
        )]
    }

    private func axialLines(
        plane: CanonicalAnalyticSurface.Plane,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let signedDistance = (cylinder.origin - plane.origin).dot(plane.normal)
        let normalizedOffset = -signedDistance / cylinder.radius
        let normalizedTolerance = tolerance.distance / cylinder.radius
        guard abs(normalizedOffset) <= 1.0 + normalizedTolerance else { return [] }
        let clampedOffset = min(max(normalizedOffset, -1.0), 1.0)
        let transverse = try cylinder.axis.cross(plane.normal).normalized(
            tolerance: tolerance.angle
        )
        let transverseMagnitude = sqrt(max(0.0, 1.0 - clampedOffset * clampedOffset))
        let firstRadial = plane.normal * clampedOffset + transverse * transverseMagnitude
        let kind: CurveSurfaceIntersectionKind = transverseMagnitude <= normalizedTolerance
            ? .tangent
            : .transverse
        var results = [try verifier.curve(
            .line(Line3D(
                origin: cylinder.origin + firstRadial * cylinder.radius,
                direction: cylinder.axis
            )),
            kind: kind,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
            tolerance: tolerance
        )]
        if kind == .transverse {
            let secondRadial = plane.normal * clampedOffset - transverse * transverseMagnitude
            results.append(try verifier.curve(
                .line(Line3D(
                    origin: cylinder.origin + secondRadial * cylinder.radius,
                    direction: cylinder.axis
                )),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
                tolerance: tolerance
            ))
        }
        return results
    }
}
