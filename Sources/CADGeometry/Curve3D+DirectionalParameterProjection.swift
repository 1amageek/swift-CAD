import CADCore
import Foundation

public extension Curve3D {
    /// Returns the nearest certified intersection with a directed line over a finite curve interval.
    func directionalParameterProjection(
        from sourcePoint: Point3D,
        along direction: Vector3D,
        options: CurveDirectionalParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveDirectionalParameterProjection {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try sourcePoint.validate()
        let unitDirection = try direction.normalized(
            tolerance: tolerance.distance
        )
        let curveRange = try directionalProjectionInterval(
            requested: options.parameterRange,
            tolerance: tolerance
        )
        let helper = abs(unitDirection.z) < 0.9
            ? Vector3D.unitZ
            : Vector3D.unitY
        let firstNormal = try helper.cross(unitDirection).normalized(
            tolerance: tolerance.distance
        )
        let secondNormal = unitDirection.cross(firstNormal)

        switch try directionalPlaneIntersections(
            planeNormal: firstNormal,
            sourcePoint: sourcePoint,
            curveRange: curveRange,
            options: options,
            tolerance: tolerance
        ) {
        case let .discrete(intersections):
            return try selectedDirectionalProjection(
                from: intersections,
                sourcePoint: sourcePoint,
                direction: unitDirection,
                options: options,
                tolerance: tolerance
            )
        case .coincident:
            switch try directionalPlaneIntersections(
                planeNormal: secondNormal,
                sourcePoint: sourcePoint,
                curveRange: curveRange,
                options: options,
                tolerance: tolerance
            ) {
            case let .discrete(intersections):
                return try selectedDirectionalProjection(
                    from: intersections,
                    sourcePoint: sourcePoint,
                    direction: unitDirection,
                    options: options,
                    tolerance: tolerance
                )
            case .coincident:
                return try projectionForCurveCoincidentWithLine(
                    sourcePoint: sourcePoint,
                    direction: unitDirection,
                    curveRange: curveRange,
                    options: options,
                    tolerance: tolerance
                )
            }
        }
    }

    private func directionalProjectionInterval(
        requested: ScalarInterval?,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let requested {
            guard try parameterDomain.containsSpan(
                from: requested.lower,
                to: requested.upper,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Directional curve projection range lies outside the curve domain."
                )
            }
            return requested
        }
        switch parameterDomain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Directional projection on an unbounded curve requires a finite parameter range."
            )
        }
    }

    private func directionalPlaneIntersections(
        planeNormal: Vector3D,
        sourcePoint: Point3D,
        curveRange: ScalarInterval,
        options: CurveDirectionalParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> DirectionalPlaneIntersectionResult {
        let plane = Plane3D(origin: sourcePoint, normal: planeNormal)
        let ranges = try directionalPlaneParameterRanges(
            plane: plane,
            curveRange: curveRange,
            tolerance: tolerance
        )
        do {
            return .discrete(try DefaultCurveSurfaceIntersector().intersections(
                curve: self,
                surface: .plane(plane),
                options: CurveSurfaceIntersectionOptions(
                    curveRange: curveRange,
                    surfaceURange: ranges.u,
                    surfaceVRange: ranges.v,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    maximumSubdivisionCells: options.maximumSubdivisionCells,
                    maximumIterations: options.maximumIterations,
                    maximumCandidateCount: options.maximumCandidateCount
                ),
                tolerance: tolerance
            ))
        } catch let error as KernelError where error.code == .nonDiscreteIntersection {
            return .coincident
        }
    }

    private func directionalPlaneParameterRanges(
        plane: Plane3D,
        curveRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (u: ScalarInterval, v: ScalarInterval) {
        let enclosure = try DefaultCurvePositionEncloser().enclosure(
            of: self,
            over: curveRange,
            tolerance: tolerance
        )
        let helper = abs(plane.normal.z) < 0.9
            ? Vector3D.unitZ
            : Vector3D.unitY
        let basisU = try helper.cross(plane.normal).normalized(
            tolerance: tolerance.distance
        )
        let basisV = plane.normal.cross(basisU)
        let corners = directionalEnclosureCorners(enclosure)
        return (
            try directionalProjectionRange(
                values: corners.map { ($0 - plane.origin).dot(basisU) },
                tolerance: tolerance
            ),
            try directionalProjectionRange(
                values: corners.map { ($0 - plane.origin).dot(basisV) },
                tolerance: tolerance
            )
        )
    }

    private func directionalProjectionRange(
        values: [Double],
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard let rawLower = values.min(),
              let rawUpper = values.max() else {
            throw KernelError(
                phase: .geometry,
                code: .emptyResult,
                tolerance: tolerance,
                message: "Directional projection could not derive a plane search range."
            )
        }
        let scale = max(abs(rawLower), abs(rawUpper), rawUpper - rawLower, 1.0)
        let padding = max(
            tolerance.distance * 8.0,
            tolerance.relative * scale * 8.0,
            Double.ulpOfOne * scale * 4_096.0
        )
        return try ScalarInterval(
            lower: (rawLower - padding).nextDown,
            upper: (rawUpper + padding).nextUp
        )
    }

    private func directionalEnclosureCorners(
        _ enclosure: CoordinateEnclosure3D
    ) -> [Point3D] {
        [enclosure.x.lower, enclosure.x.upper].flatMap { x in
            [enclosure.y.lower, enclosure.y.upper].flatMap { y in
                [enclosure.z.lower, enclosure.z.upper].map { z in
                    Point3D(x: x, y: y, z: z)
                }
            }
        }
    }

    private func selectedDirectionalProjection(
        from intersections: [CurveSurfaceIntersection],
        sourcePoint: Point3D,
        direction: Vector3D,
        options: CurveDirectionalParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveDirectionalParameterProjection {
        let candidates: [CurveDirectionalParameterProjection] = try intersections.compactMap { intersection in
            let point = try self.point(
                at: intersection.curveParameter,
                tolerance: tolerance
            )
            let signedDistance = (point - sourcePoint).dot(direction)
            guard directionalProjectionRange(
                options.range,
                accepts: signedDistance,
                tolerance: tolerance
            ) else {
                return nil
            }
            let linePoint = sourcePoint + direction * signedDistance
            let residual = (point - linePoint).length
            guard residual <= tolerance.distance else {
                return nil
            }
            return try CurveDirectionalParameterProjection(
                parameter: intersection.curveParameter,
                point: point,
                signedDistanceAlongDirection: signedDistance,
                residual: residual,
                iterations: intersection.iterations
            )
        }
        guard let selected = candidates.min(by: { lhs, rhs in
            let lhsMetric = directionalSelectionMetric(
                lhs.signedDistanceAlongDirection,
                range: options.range
            )
            let rhsMetric = directionalSelectionMetric(
                rhs.signedDistanceAlongDirection,
                range: options.range
            )
            if lhsMetric == rhsMetric {
                return lhs.parameter < rhs.parameter
            }
            return lhsMetric < rhsMetric
        }) else {
            throw KernelError(
                phase: .geometry,
                code: .emptyResult,
                tolerance: tolerance,
                message: "The directed line does not intersect the curve in the requested range."
            )
        }
        return selected
    }

    private func projectionForCurveCoincidentWithLine(
        sourcePoint: Point3D,
        direction: Vector3D,
        curveRange: ScalarInterval,
        options: CurveDirectionalParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveDirectionalParameterProjection {
        let closest = try closestParameterProjection(
            of: sourcePoint,
            options: CurveParameterProjectionOptions(
                parameterRange: curveRange,
                maximumIterations: options.maximumIterations,
                seedCount: max(2, min(options.maximumCandidateCount, 64)),
                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.maximumSubdivisionCells,
                maximumCandidateCount: options.maximumCandidateCount
            ),
            tolerance: tolerance
        )
        let signedDistance = (closest.point - sourcePoint).dot(direction)
        let linePoint = sourcePoint + direction * signedDistance
        let residual = (closest.point - linePoint).length
        guard residual <= tolerance.distance,
              directionalProjectionRange(
                  options.range,
                  accepts: signedDistance,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .emptyResult,
                residual: residual,
                tolerance: tolerance,
                message: "The coincident curve does not intersect the requested directional range."
            )
        }
        return try CurveDirectionalParameterProjection(
            parameter: closest.parameter,
            point: closest.point,
            signedDistanceAlongDirection: signedDistance,
            residual: residual,
            iterations: closest.iterations
        )
    }

    private func directionalProjectionRange(
        _ range: DirectionalProjectionRange3D,
        accepts signedDistance: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        switch range {
        case .line:
            return true
        case .ray:
            return signedDistance >= -tolerance.distance
        }
    }

    private func directionalSelectionMetric(
        _ signedDistance: Double,
        range: DirectionalProjectionRange3D
    ) -> Double {
        switch range {
        case .line:
            return abs(signedDistance)
        case .ray:
            return signedDistance
        }
    }
}

private enum DirectionalPlaneIntersectionResult {
    case discrete([CurveSurfaceIntersection])
    case coincident
}
