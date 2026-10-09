#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

struct PlaneTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try plane.requireLegacyUnitNormal(tolerance: tolerance)
        let axisProjection = plane.normal.dot(torus.axis)
        let radialNormal = plane.normal - torus.axis * axisProjection
        let radialNormalLength = radialNormal.length
        let centerDistance = (torus.center - plane.origin).dot(plane.normal)

        if radialNormalLength <= tolerance.angle {
            return try axialSection(
                plane: plane,
                torus: torus,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }

        if abs(axisProjection) <= tolerance.angle,
           abs(centerDistance) <= tolerance.distance {
            let radialDirection = try torus.axis.cross(plane.normal).normalized(
                tolerance: tolerance.distance
            )
            return try [-1.0, 1.0].map { sign in
                try verifier.curve(
                    .circle(Circle3D(
                        center: torus.center + radialDirection * (sign * torus.majorRadius),
                        normal: plane.normal,
                        radius: torus.minorRadius
                    )),
                    kind: .transverse,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                    tolerance: tolerance
                )
            }
        }

        let support = torus.majorRadius * radialNormalLength + torus.minorRadius
        let absoluteDistance = abs(centerDistance)
        guard absoluteDistance <= support + tolerance.distance else { return [] }
        if abs(absoluteDistance - support) <= tolerance.distance {
            let targetSign = centerDistance > 0.0 ? -1.0 : 1.0
            let radialDirection = try radialNormal.normalized(tolerance: tolerance.distance)
            let point = torus.center
                + radialDirection * (targetSign * torus.majorRadius)
                + plane.normal * (targetSign * torus.minorRadius)
            return [try verifier.point(
                point,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )]
        }

        return try generalSection(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func generalSection(
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try AnalyticAnalyticSurfaceIntersector().intersections(
            first: firstSurface,
            second: secondSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func axialSection(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let height = (plane.origin - torus.center).dot(torus.axis)
        guard abs(height) <= torus.minorRadius + tolerance.distance else { return [] }
        let radialOffset = sqrt(max(
            0.0,
            torus.minorRadius * torus.minorRadius - height * height
        ))
        let center = torus.center + torus.axis * height
        if radialOffset <= tolerance.distance {
            return [try verifier.curve(
                .circle(Circle3D(
                    center: center,
                    normal: plane.normal,
                    radius: torus.majorRadius
                )),
                kind: .tangent,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )]
        }
        return try [torus.majorRadius - radialOffset, torus.majorRadius + radialOffset].map { radius in
            try verifier.curve(
                .circle(Circle3D(center: center, normal: plane.normal, radius: radius)),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }
}
