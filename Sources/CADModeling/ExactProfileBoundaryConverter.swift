import Foundation
import CADCore
import CADGeometry
import CADIR

package struct ExactProfileBoundaryConverter: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func segments(
        from profile: Profile,
        offset: Vector3D,
        extrusionAxis: Vector3D
    ) throws -> [ExactPrismaticBoundarySegment] {
        try segments(
            from: profile.outerLoop,
            on: profile.plane,
            offset: offset,
            extrusionAxis: extrusionAxis
        )
    }

    package func boundaries(
        from profile: Profile,
        offset: Vector3D,
        extrusionAxis: Vector3D
    ) throws -> [[ExactPrismaticBoundarySegment]] {
        try ([profile.outerLoop] + profile.innerLoops).map { loop in
            try segments(
                from: loop,
                on: profile.plane,
                offset: offset,
                extrusionAxis: extrusionAxis
            )
        }
    }

    private func segments(
        from loop: ProfileLoop,
        on plane: SketchPlane,
        offset: Vector3D,
        extrusionAxis: Vector3D
    ) throws -> [ExactPrismaticBoundarySegment] {
        try tolerance.validate()
        let axis = try extrusionAxis.normalized(tolerance: tolerance.distance)
        let profilePlane = try self.plane(for: plane)
        var result: [ExactPrismaticBoundarySegment] = []
        for boundary in loop.boundarySegments {
            switch boundary {
            case let .line(line):
                try validate(point: line.start, on: profilePlane)
                try validate(point: line.end, on: profilePlane)
                result.append(try .line(
                    from: line.start + offset,
                    to: line.end + offset,
                    tolerance: tolerance
                ))
            case let .circularArc(arc):
                result.append(contentsOf: try circularSegments(
                    arc,
                    offset: offset,
                    extrusionAxis: axis,
                    profilePlane: profilePlane
                ))
            case let .spline(spline):
                result.append(contentsOf: try splineSegments(
                    spline.curve,
                    offset: offset,
                    profilePlane: profilePlane
                ))
            }
        }
        guard result.count >= 2 else {
            throw SketchError.openProfile
        }
        try validateClosure(result)
        return result
    }

    private func circularSegments(
        _ arc: ProfileCircularArcSegment,
        offset: Vector3D,
        extrusionAxis: Vector3D,
        profilePlane: Plane3D
    ) throws -> [ExactPrismaticBoundarySegment] {
        try validate(point: arc.center, on: profilePlane)
        try validate(point: arc.start, on: profilePlane)
        try validate(point: arc.end, on: profilePlane)
        let normal = try arc.normal.normalized(tolerance: tolerance.distance)
        guard abs(abs(normal.dot(profilePlane.normal)) - 1.0) <= tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: abs(normal.dot(profilePlane.normal)),
                tolerance: tolerance,
                message: "Extrude circular boundary normal must match the profile plane."
            )
        }
        let circle = Circle3D(
            center: arc.center + offset,
            normal: normal,
            radius: arc.radius
        )
        try circle.validate(tolerance: tolerance)
        let exactCircle = Curve3D.circle(circle)
        let startParameter = try exactCircle.parameterProjection(
            of: arc.start + offset,
            tolerance: tolerance
        ).parameter
        let segmentCount = max(
            1,
            Int(ceil(abs(arc.sweepAngle) / (0.5 * Double.pi)))
        )
        let useAnalyticCylinder = abs(abs(normal.dot(extrusionAxis)) - 1.0)
            <= tolerance.angle
        return try (0..<segmentCount).map { index in
            let lower = startParameter
                + arc.sweepAngle * Double(index) / Double(segmentCount)
            let upper = startParameter
                + arc.sweepAngle * Double(index + 1) / Double(segmentCount)
            if useAnalyticCylinder {
                return try .circularArc(
                    circle: circle,
                    startParameter: lower,
                    endParameter: upper,
                    tolerance: tolerance
                )
            }
            return try .bSpline(
                rationalCircularSpan(
                    circle: circle,
                    startParameter: lower,
                    endParameter: upper
                ),
                tolerance: tolerance
            )
        }
    }

    private func rationalCircularSpan(
        circle: Circle3D,
        startParameter: Double,
        endParameter: Double
    ) throws -> BSplineCurve3D {
        let curve = Curve3D.circle(circle)
        let middleParameter = 0.5 * (startParameter + endParameter)
        let middleWeight = cos(0.5 * (endParameter - startParameter))
        guard middleWeight > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Extrude circular boundary produced a singular rational span."
            )
        }
        let middlePoint = try curve.point(
            at: middleParameter,
            tolerance: tolerance
        )
        let result = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                try curve.point(at: startParameter, tolerance: tolerance),
                circle.center + (middlePoint - circle.center) / middleWeight,
                try curve.point(at: endParameter, tolerance: tolerance),
            ],
            weights: [1.0, middleWeight, 1.0]
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    private func splineSegments(
        _ source: BSplineCurve3D,
        offset: Vector3D,
        profilePlane: Plane3D
    ) throws -> [ExactPrismaticBoundarySegment] {
        try source.validate(tolerance: tolerance)
        for point in source.controlPoints {
            try validate(point: point, on: profilePlane)
        }
        guard case let .closed(lower, upper) = source.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Extrude spline profile requires a bounded exact curve."
            )
        }
        var breaks = [lower]
        for knot in source.knots where knot > lower + tolerance.distance
            && knot < upper - tolerance.distance {
            if breaks.last.map({ abs($0 - knot) > tolerance.distance }) != false {
                breaks.append(knot)
            }
        }
        breaks.append(upper)
        let start = try source.point(at: lower, tolerance: tolerance)
        let end = try source.point(at: upper, tolerance: tolerance)
        if breaks.count == 2,
           start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) {
            breaks.insert(0.5 * (lower + upper), at: 1)
        }
        return try (0..<(breaks.count - 1)).map { index in
            let span = try source.trimmed(
                from: breaks[index],
                to: breaks[index + 1],
                tolerance: tolerance
            )
            let translated = BSplineCurve3D(
                degree: span.degree,
                knots: span.knots,
                controlPoints: span.controlPoints.map { $0 + offset },
                weights: span.weights
            )
            return try .bSpline(translated, tolerance: tolerance)
        }
    }

    private func validateClosure(
        _ segments: [ExactPrismaticBoundarySegment]
    ) throws {
        for index in segments.indices {
            let next = segments[(index + 1) % segments.count]
            guard segments[index].endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: tolerance.distance
            ) else {
                throw SketchError.openProfile
            }
        }
    }

    private func validate(
        point: Point3D,
        on plane: Plane3D
    ) throws {
        try point.validate()
        let residual = abs((point - plane.origin).dot(plane.normal))
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: tolerance,
                message: "Extrude profile control geometry must lie on the profile plane."
            )
        }
    }

    private func plane(for sketchPlane: SketchPlane) throws -> Plane3D {
        let plane: Plane3D
        switch sketchPlane {
        case .xy:
            plane = Plane3D(origin: .origin, normal: .unitZ)
        case .yz:
            plane = Plane3D(origin: .origin, normal: .unitX)
        case .zx:
            plane = Plane3D(origin: .origin, normal: .unitY)
        case let .plane(value):
            plane = value
        }
        try plane.validate(tolerance: tolerance)
        return Plane3D(
            origin: plane.origin,
            normal: try plane.normal.normalized(tolerance: tolerance.distance)
        )
    }
}
