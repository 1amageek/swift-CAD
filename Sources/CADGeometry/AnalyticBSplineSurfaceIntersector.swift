import Foundation
import CADCore

struct AnalyticBSplineSurfaceIntersector {
    func intersections(
        analytic: CanonicalAnalyticSurface,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        analyticIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try options.validate(tolerance: tolerance)
        let seamOffsets = try periodicSeamOffsets(
            analytic: analytic,
            reference: surface,
            count: options.maximumPeriodicSeamAttempts,
            tolerance: tolerance
        )
        var lastRetryableError: KernelError?
        for periodicSeamOffset in seamOffsets {
            let analyticBSpline = try AnalyticSurfaceBSplineBuilder().surface(
                for: analytic,
                boundedBy: surface,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
            let internalFirst = analyticIsFirst ? analyticBSpline : surface
            let internalSecond = analyticIsFirst ? surface : analyticBSpline
            let raw: [SurfaceSurfaceIntersection]
            do {
                raw = try BoundedBSplineSurfaceIntersector().intersections(
                    first: internalFirst,
                    second: internalSecond,
                    firstSurface: .bSpline(internalFirst),
                    secondSurface: .bSpline(internalSecond),
                    options: options,
                    tolerance: tolerance
                )
            } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    || error.code == .intersectionFailure {
                lastRetryableError = error
                continue
            }
            guard try containsPeriodicPatchBoundaryCoincidence(
                raw,
                analytic: analytic,
                analyticBSpline: analyticBSpline,
                analyticIsFirst: analyticIsFirst,
                tolerance: tolerance
            ) == false else {
                continue
            }
            return try raw.map {
                try remapped(
                    $0,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    analyticIsFirst: analyticIsFirst,
                    periodicSeamOffset: periodicSeamOffset,
                    tolerance: tolerance
                )
            }
        }
        if let lastRetryableError {
            throw lastRetryableError
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Analytic–B-spline intersection exhausted the periodic seam retry limit."
        )
    }

    private func periodicSeamOffsets(
        analytic: CanonicalAnalyticSurface,
        reference: BSplineSurface3D,
        count: Int,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let initialOffset = Double.pi * 0.125
        let goldenAngle = Double.pi * (3.0 - sqrt(5.0))
        let candidates = (0..<count).map {
            initialOffset + Double($0) * goldenAngle
        }
        let occupiedAngles = try periodicReferenceAngles(
            analytic: analytic,
            reference: reference,
            tolerance: tolerance
        )
        guard occupiedAngles.isEmpty == false else { return candidates }
        return candidates.enumerated().sorted { first, second in
            let firstClearance = minimumPeriodicPatchBoundaryClearance(
                first.element,
                occupiedAngles: occupiedAngles
            )
            let secondClearance = minimumPeriodicPatchBoundaryClearance(
                second.element,
                occupiedAngles: occupiedAngles
            )
            if abs(firstClearance - secondClearance) > tolerance.angle {
                return firstClearance > secondClearance
            }
            return first.offset < second.offset
        }.map(\.element)
    }

    private func periodicReferenceAngles(
        analytic: CanonicalAnalyticSurface,
        reference: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let origin: Point3D
        let axis: Vector3D
        let torusMajorRadius: Double?
        switch analytic {
        case let .cylinder(cylinder):
            origin = cylinder.origin
            axis = cylinder.axis
            torusMajorRadius = nil
        case let .cone(cone):
            origin = cone.apex
            axis = cone.axis
            torusMajorRadius = nil
        case let .sphere(sphere):
            origin = sphere.center
            axis = .unitZ
            torusMajorRadius = nil
        case let .torus(torus):
            origin = torus.center
            axis = torus.axis
            torusMajorRadius = torus.majorRadius
        case .plane, .unsupported:
            return []
        }
        let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
        var result: [Double] = []
        result.reserveCapacity(reference.controlPoints.count * reference.controlPoints[0].count * 2)
        for point in reference.controlPoints.flatMap({ $0 }) {
            let displacement = point - origin
            let axial = displacement.dot(axis)
            let radial = displacement - axis * axial
            let radialLength = radial.length
            guard radialLength > tolerance.distance else { continue }
            result.append(atan2(radial.dot(basis.v), radial.dot(basis.u)))
            if let torusMajorRadius {
                result.append(atan2(axial, radialLength - torusMajorRadius))
            }
        }
        return result
    }

    private func minimumPeriodicPatchBoundaryClearance(
        _ candidate: Double,
        occupiedAngles: [Double]
    ) -> Double {
        (0..<4).flatMap { quadrant in
            let boundary = candidate + Double(quadrant) * Double.pi * 0.5
            return occupiedAngles.map { occupied in
                let difference = abs(boundary - occupied)
                    .truncatingRemainder(dividingBy: 2.0 * Double.pi)
                return min(difference, 2.0 * Double.pi - difference)
            }
        }.min() ?? Double.pi
    }

    private func containsPeriodicPatchBoundaryCoincidence(
        _ intersections: [SurfaceSurfaceIntersection],
        analytic: CanonicalAnalyticSurface,
        analyticBSpline: BSplineSurface3D,
        analyticIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let directions: [SurfaceParameterDirection]
        switch analytic {
        case .cylinder, .cone, .sphere:
            directions = [.u]
        case .torus:
            directions = [.u, .v]
        case .plane, .unsupported:
            directions = []
        }
        for intersection in intersections {
            guard case let .curve(curve) = intersection else { continue }
            let pcurve = analyticIsFirst
                ? curve.firstSurfaceParameterCurve
                : curve.secondSurfaceParameterCurve
            for direction in directions where try liesOnPeriodicPatchBoundary(
                pcurve,
                direction: direction,
                surface: analyticBSpline,
                tolerance: tolerance
            ) {
                return true
            }
        }
        return false
    }

    private func liesOnPeriodicPatchBoundary(
        _ pcurve: SurfaceParameterCurve,
        direction: SurfaceParameterDirection,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let domain = direction == .u ? surface.uDomain : surface.vDomain
        let knots = direction == .u ? surface.uKnots : surface.vKnots
        guard case let .closed(lower, upper) = domain else { return false }
        let parameterTolerance = max(
            tolerance.angle * 4.0 / Double.pi,
            tolerance.distance * 8.0,
            Double.ulpOfOne * 256.0
        )
        let values = try (0...8).map { index in
            let parameter = try pcurve.parameter(
                atNormalizedFraction: Double(index) / 8.0,
                tolerance: tolerance
            )
            return direction == .u ? parameter.u : parameter.v
        }
        if values.allSatisfy({
            min(abs($0 - lower), abs($0 - upper)) <= parameterTolerance
        }) {
            return true
        }
        let internalBoundaries = Array(Set(knots)).filter {
            $0 > lower + parameterTolerance && $0 < upper - parameterTolerance
        }
        for boundary in internalBoundaries {
            if values.allSatisfy({ abs($0 - boundary) <= parameterTolerance }) {
                return true
            }
        }
        return false
    }

    private func remapped(
        _ intersection: SurfaceSurfaceIntersection,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        analyticIsFirst: Bool,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        switch intersection {
        case let .curve(value):
            return try remappedCurve(
                value,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                analyticIsFirst: analyticIsFirst,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
        case let .point(value):
            let firstProjection = try firstSurface.parameterProjection(
                of: value.point,
                tolerance: tolerance
            )
            let secondProjection = try secondSurface.parameterProjection(
                of: value.point,
                tolerance: tolerance
            )
            return .point(try SurfaceSurfaceIntersectionPoint(
                point: value.point,
                firstSurfaceParameter: firstProjection,
                secondSurfaceParameter: secondProjection,
                residual: max(firstProjection.residual, secondProjection.residual),
                tolerance: tolerance
            ))
        case let .coincident(value):
            return .coincident(value)
        }
    }

    private func remappedCurve(
        _ intersection: SurfaceSurfaceIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        analyticIsFirst: Bool,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        if case let .implicit(implicitCurve) = intersection.truth {
            let analyticSurface = analyticIsFirst ? firstSurface : secondSurface
            let certified = try CertifiedAnalyticBSplineIntersectionCurve(
                implicitCurve: implicitCurve,
                analyticSurface: analyticSurface,
                analyticIsFirst: analyticIsFirst,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
            let point = try implicitCurve.point(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let firstAnchor = try firstSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let secondAnchor = try secondSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let firstPcurve = certified.firstSurfaceParameterCurve
            let secondPcurve = certified.secondSurfaceParameterCurve
            try firstPcurve.validate(on: firstSurface, tolerance: tolerance)
            try secondPcurve.validate(on: secondSurface, tolerance: tolerance)
            return .curve(try SurfaceSurfaceIntersectionCurve(
                truth: .analyticBSpline(certified),
                derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                    curve: intersection.derivedRepresentation.curve,
                    firstSurfaceParameterCurve: firstPcurve,
                    secondSurfaceParameterCurve: secondPcurve,
                    maximumResidualUpperBound: intersection.maximumResidual,
                    tolerance: tolerance
                ),
                kind: intersection.kind,
                firstSurfaceAnchor: firstAnchor,
                secondSurfaceAnchor: secondAnchor,
                tolerance: tolerance
            ))
        }
        guard case let .quadraticTangency(tangencyCurve) = intersection.truth else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Analytic–B-spline remapping received an unsupported uncertified truth representation."
            )
        }
        let analyticSurface = analyticIsFirst ? firstSurface : secondSurface
        let certified = try CertifiedAnalyticBSplineTangencyIntersectionCurve(
            tangencyCurve: tangencyCurve,
            analyticSurface: analyticSurface,
            analyticIsFirst: analyticIsFirst,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: tolerance
        )
        let firstPcurve = certified.firstSurfaceParameterCurve
        let secondPcurve = certified.secondSurfaceParameterCurve
        try firstPcurve.validate(on: firstSurface, tolerance: tolerance)
        try secondPcurve.validate(on: secondSurface, tolerance: tolerance)
        let point = try certified.curve.point(
            at: 0.0,
            tolerance: tolerance
        )
        let firstAnchor = try firstSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let secondAnchor = try secondSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticBSplineTangency(certified),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: certified.curve,
                firstSurfaceParameterCurve: firstPcurve,
                secondSurfaceParameterCurve: secondPcurve,
                maximumResidualUpperBound: certified.maximumResidualUpperBound,
                tolerance: tolerance
            ),
            kind: tangencyCurve.kind,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            tolerance: tolerance
        ))
    }
}
