import Foundation
import CADCore
import CADIR

public struct ProfileRegionAnalyzer: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func summary(for profile: Profile) throws -> ProfileRegionSummary {
        try tolerance.validate()
        let points = try profile.vertices.map { vertex in
            try projectedPoint(vertex, on: profile.plane)
        }
        guard points.count >= 3 else {
            throw SketchError.degenerateProfile
        }

        // Rebase every boundary coordinate by one shared local origin before the
        // shoelace and moment products. At site-planning scale the profile can sit
        // ~1e12 m from the world origin, where absolute products (~1e24, ulp ~1e8)
        // cancel catastrophically and collapse the area/centroid. A closed loop's
        // area is translation invariant, and the centroid transforms covariantly,
        // so the true values are recovered by adding the origin back to the centroid.
        let origin = points[0]
        let moments = try exactBoundaryMoments(for: profile, origin: origin)
            ?? polygonMoments(for: points.map { rebased($0, by: origin) })
        let twiceArea = moments.twiceArea
        guard abs(twiceArea) > areaTolerance else {
            throw SketchError.degenerateProfile
        }

        let localCenter = Point2D(
            x: moments.firstMomentX / twiceArea,
            y: moments.firstMomentY / twiceArea
        )
        let center = Point2D(x: localCenter.x + origin.x, y: localCenter.y + origin.y)
        guard center.x.isFinite else {
            throw GeometryError.invalidCoordinate(center.x)
        }
        guard center.y.isFinite else {
            throw GeometryError.invalidCoordinate(center.y)
        }

        return ProfileRegionSummary(
            center: center,
            areaSquareMeters: abs(twiceArea) * 0.5,
            points: points
        )
    }

    private func rebased(_ point: Point2D, by origin: Point2D) -> Point2D {
        Point2D(x: point.x - origin.x, y: point.y - origin.y)
    }

    private var areaTolerance: Double {
        max(tolerance.distance * tolerance.distance, 1.0e-18)
    }

    private func polygonMoments(for points: [Point2D]) -> RegionMoments {
        var moments = RegionMoments()
        for index in points.indices {
            moments.addLine(from: points[index], to: points[(index + 1) % points.count])
        }
        return moments
    }

    private func exactBoundaryMoments(
        for profile: Profile,
        origin: Point2D
    ) throws -> RegionMoments? {
        guard profile.boundarySegments.isEmpty == false else {
            return nil
        }
        var moments = RegionMoments()
        for segment in profile.boundarySegments {
            switch segment {
            case .line(let line):
                moments.addLine(
                    from: rebased(try projectedPoint(line.start, on: profile.plane), by: origin),
                    to: rebased(try projectedPoint(line.end, on: profile.plane), by: origin)
                )
            case .circularArc(let arc):
                let center = rebased(try projectedPoint(arc.center, on: profile.plane), by: origin)
                let start = rebased(try projectedPoint(arc.start, on: profile.plane), by: origin)
                moments.addCircularArc(
                    center: center,
                    radius: arc.radius,
                    start: start,
                    sweepAngle: arc.sweepAngle
                )
            }
        }
        return moments
    }

    private func projectedPoint(
        _ point: Point3D,
        on plane: SketchPlane
    ) throws -> Point2D {
        switch plane {
        case .xy:
            return Point2D(x: point.x, y: point.y)
        case .yz:
            return Point2D(x: point.y, y: point.z)
        case .zx:
            return Point2D(x: point.z, y: point.x)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            let delta = Vector3D(
                x: point.x - plane.origin.x,
                y: point.y - plane.origin.y,
                z: point.z - plane.origin.z
            )
            return Point2D(x: delta.dot(u), y: delta.dot(v))
        }
    }
}

private struct RegionMoments {
    var twiceArea = 0.0
    var firstMomentX = 0.0
    var firstMomentY = 0.0

    mutating func addLine(from start: Point2D, to end: Point2D) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        twiceArea += start.x * end.y - end.x * start.y
        firstMomentX += dy * (start.x * start.x + start.x * dx + dx * dx / 3.0)
        firstMomentY += -dx * (start.y * start.y + start.y * dy + dy * dy / 3.0)
    }

    mutating func addCircularArc(
        center: Point2D,
        radius: Double,
        start: Point2D,
        sweepAngle: Double
    ) {
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = startAngle + sweepAngle
        let sinStart = sin(startAngle)
        let sinEnd = sin(endAngle)
        let cosStart = cos(startAngle)
        let cosEnd = cos(endAngle)
        let sinDoubleStart = sin(2.0 * startAngle)
        let sinDoubleEnd = sin(2.0 * endAngle)

        let integralCos = sinEnd - sinStart
        let integralSin = cosStart - cosEnd
        let integralCosSquared = sweepAngle / 2.0 + (sinDoubleEnd - sinDoubleStart) / 4.0
        let integralSinSquared = sweepAngle / 2.0 - (sinDoubleEnd - sinDoubleStart) / 4.0
        let integralCosCubed = (sinEnd - pow(sinEnd, 3.0) / 3.0)
            - (sinStart - pow(sinStart, 3.0) / 3.0)
        let integralSinCubed = (-cosEnd + pow(cosEnd, 3.0) / 3.0)
            - (-cosStart + pow(cosStart, 3.0) / 3.0)

        twiceArea += radius * (
            center.x * integralCos + center.y * integralSin
        ) + radius * radius * sweepAngle
        firstMomentX += radius * center.x * center.x * integralCos
            + 2.0 * center.x * radius * radius * integralCosSquared
            + radius * radius * radius * integralCosCubed
        firstMomentY += radius * center.y * center.y * integralSin
            + 2.0 * center.y * radius * radius * integralSinSquared
            + radius * radius * radius * integralSinCubed
    }
}
