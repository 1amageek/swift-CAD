#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry
import CADIR

package struct ExactProfileBoundaryConverter: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func segments(from profile: Profile, offset: Vector3D,
        extrusionAxis: Vector3D) throws -> [ExactPrismaticBoundarySegment] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try segments(from: profile, offset: offset, extrusionAxis: extrusionAxis, using: &execution)
    }

    package func boundaries(from profile: Profile, offset: Vector3D,
        extrusionAxis: Vector3D) throws -> [[ExactPrismaticBoundarySegment]] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundaries(from: profile, offset: offset, extrusionAxis: extrusionAxis, using: &execution)
    }

    package func segments(
        from profile: Profile,
        offset: Vector3D,
        extrusionAxis: Vector3D
    , using execution: inout OriginalQueryExecution) throws -> [ExactPrismaticBoundarySegment] {
        try segments(
            from: profile.outerLoop,
            on: profile.plane,
            offset: offset,
            extrusionAxis: extrusionAxis
        , using: &execution)
    }

    package func boundaries(
        from profile: Profile,
        offset: Vector3D,
        extrusionAxis: Vector3D
    , using execution: inout OriginalQueryExecution) throws -> [[ExactPrismaticBoundarySegment]] {
        try execution.retainStorage(count: profile.innerLoops.count + 1, stride: MemoryLayout<ProfileLoop>.stride + MemoryLayout<[ExactPrismaticBoundarySegment]>.stride)
        return try ([profile.outerLoop] + profile.innerLoops).map { loop in
            try segments(
                from: loop,
                on: profile.plane,
                offset: offset,
                extrusionAxis: extrusionAxis
            , using: &execution)
        }
    }

    private func segments(
        from loop: ProfileLoop,
        on plane: SketchPlane,
        offset: Vector3D,
        extrusionAxis: Vector3D
    , using execution: inout OriginalQueryExecution) throws -> [ExactPrismaticBoundarySegment] {
        try tolerance.validate()
        let axis = try extrusionAxis.normalized(tolerance: tolerance.distance)
        let profilePlane = try self.plane(for: plane, using: &execution)
        var result: [ExactPrismaticBoundarySegment] = []
        for boundary in loop.boundarySegments {
            try execution.consumeWork(1)
            switch boundary {
            case let .line(line):
                try validate(point: line.start, on: profilePlane, using: &execution)
                try validate(point: line.end, on: profilePlane, using: &execution)
                try execution.retainStorage(count: 1, stride: MemoryLayout<ExactPrismaticBoundarySegment>.stride)
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
                , using: &execution))
            case let .spline(spline):
                result.append(contentsOf: try splineSegments(
                    spline.curve,
                    offset: offset,
                    profilePlane: profilePlane
                , using: &execution))
            }
        }
        guard result.count >= 2 else {
            throw SketchError.openProfile
        }
        try validateClosure(result, using: &execution)
        return result
    }

    private func circularSegments(
        _ arc: ProfileCircularArcSegment,
        offset: Vector3D,
        extrusionAxis: Vector3D,
        profilePlane: Plane3D
    , using execution: inout OriginalQueryExecution) throws -> [ExactPrismaticBoundarySegment] {
        try validate(point: arc.center, on: profilePlane, using: &execution)
        try validate(point: arc.start, on: profilePlane, using: &execution)
        try validate(point: arc.end, on: profilePlane, using: &execution)
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
        , using: &execution).parameter
        let segmentCount = max(
            1,
            Int(ceil(abs(arc.sweepAngle) / (0.5 * Double.pi)))
        )
        let useAnalyticCylinder = abs(abs(normal.dot(extrusionAxis)) - 1.0)
            <= tolerance.angle
        try execution.retainStorage(count: segmentCount, stride: MemoryLayout<ExactPrismaticBoundarySegment>.stride)
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
                , using: &execution)
            }
            return try .bSpline(
                rationalCircularSpan(
                    circle: circle,
                    startParameter: lower,
                    endParameter: upper
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        }
    }

    private func rationalCircularSpan(
        circle: Circle3D,
        startParameter: Double,
        endParameter: Double
    , using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
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
        , using: &execution)
        try execution.retainStorage(count: 9, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Point3D>.stride)
        let result = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                try curve.point(at: startParameter, tolerance: tolerance, using: &execution),
                circle.center + (middlePoint - circle.center) / middleWeight,
                try curve.point(at: endParameter, tolerance: tolerance, using: &execution),
            ],
            weights: [1.0, middleWeight, 1.0]
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    private func splineSegments(
        _ source: BSplineCurve3D,
        offset: Vector3D,
        profilePlane: Plane3D
    , using execution: inout OriginalQueryExecution) throws -> [ExactPrismaticBoundarySegment] {
        try source.validate(tolerance: tolerance, using: &execution)
        for point in source.controlPoints {
            try execution.consumeWork(1)
            try validate(point: point, on: profilePlane, using: &execution)
        }
        guard case let .closed(lower, upper) = source.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Extrude spline profile requires a bounded exact curve."
            )
        }
        try execution.retainStorage(count: source.knots.count + 3, stride: MemoryLayout<Double>.stride)
        var breaks = [lower]
        for knot in source.knots where knot > lower + tolerance.distance
            && knot < upper - tolerance.distance {
            if breaks.last.map({ abs($0 - knot) > tolerance.distance }) != false {
                breaks.append(knot)
            }
        }
        breaks.append(upper)
        let start = try source.point(at: lower, tolerance: tolerance, using: &execution)
        let end = try source.point(at: upper, tolerance: tolerance, using: &execution)
        if breaks.count == 2,
           start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) {
            breaks.insert(0.5 * (lower + upper), at: 1)
        }
        try execution.retainStorage(count: breaks.count - 1, stride: MemoryLayout<ExactPrismaticBoundarySegment>.stride)
        return try (0..<(breaks.count - 1)).map { index in
            let span = try source.trimmed(
                from: breaks[index],
                to: breaks[index + 1],
                tolerance: tolerance
            , using: &execution)
            try execution.retainStorage(count: span.controlPointCount, stride: MemoryLayout<Point3D>.stride)
            let translated = BSplineCurve3D(
                degree: span.degree,
                knots: span.knots,
                controlPoints: span.controlPoints.map { $0 + offset },
                weights: span.weights
            )
            return try .bSpline(translated, tolerance: tolerance, using: &execution)
        }
    }

    private func validateClosure(
        _ segments: [ExactPrismaticBoundarySegment]
    , using execution: inout OriginalQueryExecution) throws {
        for index in segments.indices {
            try execution.consumeWork(1)
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
        on plane: Plane3D, using execution: inout OriginalQueryExecution
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

    private func plane(for sketchPlane: SketchPlane, using execution: inout OriginalQueryExecution) throws -> Plane3D {
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
