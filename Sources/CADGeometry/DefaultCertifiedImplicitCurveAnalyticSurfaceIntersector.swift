import Foundation
import CADCore

struct DefaultCertifiedImplicitCurveAnalyticSurfaceIntersector:
    CertifiedImplicitCurveAnalyticSurfaceIntersecting
{
    private let surfaceNormalResolver: any SurfaceNormalResolving

    init(
        surfaceNormalResolver: any SurfaceNormalResolving =
            DefaultSurfaceNormalResolver()
    ) {
        self.surfaceNormalResolver = surfaceNormalResolver
    }

    func intersections(
        curve: CertifiedImplicitIntersectionCurve,
        targetSurface: Surface3D,
        canonicalTarget: CanonicalAnalyticSurface,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        rationalSurfaceIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection] {
        if case .unsupported = canonicalTarget {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified implicit curve analytic-surface intersection requires an analytic target."
            )
        }
        let curveValue = Curve3D.implicit(curve)
        let bounds = try curve.boundingBox(
            fromNormalizedFraction: options.curveRange?.lower ?? 0.0,
            toNormalizedFraction: options.curveRange?.upper ?? 1.0,
            tolerance: tolerance
        )
        let referencePoints = corners(of: bounds)
        let seamOffsets = periodicSeamOffsets(
            for: canonicalTarget,
            maximumCount: options.maximumPeriodicSeamAttempts
        )
        var lastRetryableError: KernelError?
        for seamOffset in seamOffsets {
            let rationalTarget = try AnalyticSurfaceBSplineBuilder().surface(
                for: canonicalTarget,
                boundedByPoints: referencePoints,
                periodicSeamOffset: seamOffset,
                tolerance: tolerance
            )
            guard let searchRanges = try rationalSearchRanges(
                surface: rationalTarget,
                targetSurface: targetSurface,
                canonicalTarget: canonicalTarget,
                seamOffset: seamOffset,
                options: options,
                tolerance: tolerance
            ) else {
                continue
            }
            guard searchRanges.isEmpty == false else { return [] }
            guard options.maximumSubdivisionCells >= searchRanges.count,
                  options.maximumCandidateCount >= searchRanges.count else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Certified implicit curve analytic-surface span partitioning exceeded its resource budget."
                )
            }
            let cellsPerRange = max(
                options.maximumSubdivisionCells / searchRanges.count,
                1
            )
            let candidatesPerRange = max(
                options.maximumCandidateCount / searchRanges.count,
                1
            )
            do {
                var raw: [CurveSurfaceIntersection] = []
                for searchRange in searchRanges {
                    let rationalOptions = CurveSurfaceIntersectionOptions(
                        curveRange: options.curveRange,
                        surfaceURange: searchRange.u,
                        surfaceVRange: searchRange.v,
                        maximumSubdivisionDepth:
                            options.maximumSubdivisionDepth,
                        maximumSubdivisionCells: cellsPerRange,
                        maximumIterations: options.maximumIterations,
                        maximumCandidateCount: candidatesPerRange,
                        maximumPolynomialDegree:
                            options.maximumPolynomialDegree,
                        maximumPeriodicSeamAttempts:
                            options.maximumPeriodicSeamAttempts
                    )
                    raw.append(
                        contentsOf:
                            try rationalSurfaceIntersector.intersections(
                                curve: curveValue,
                                surface: .bSpline(rationalTarget),
                                options: rationalOptions,
                                tolerance: tolerance
                            )
                    )
                }
                let remapped = try raw.compactMap {
                    try remapped(
                        $0,
                        curve: curveValue,
                        targetSurface: targetSurface,
                        options: options,
                        tolerance: tolerance
                    )
                }
                return deduplicated(remapped, tolerance: tolerance)
            } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    || error.code == .intersectionFailure
                    || error.code == .singularGeometry {
                lastRetryableError = error
            }
        }
        if let lastRetryableError {
            throw lastRetryableError
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Certified implicit curve analytic-surface intersection exhausted its periodic seam attempts."
        )
    }

    private func remapped(
        _ intersection: CurveSurfaceIntersection,
        curve: Curve3D,
        targetSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        let projection = try targetSurface.parameterProjection(
            of: intersection.point,
            tolerance: tolerance
        )
        let rangeResolver = SurfaceParameterRangeResolver()
        guard let surfaceU = rangeResolver.resolvedParameter(
            projection.u,
            domain: targetSurface.uDomain,
            requestedRange: options.surfaceURange,
            tolerance: tolerance
        ), let surfaceV = rangeResolver.resolvedParameter(
            projection.v,
            domain: targetSurface.vDomain,
            requestedRange: options.surfaceVRange,
            tolerance: tolerance
        ) else {
            return nil
        }
        let targetPoint = try targetSurface.point(
            u: surfaceU,
            v: surfaceV,
            tolerance: tolerance
        )
        let residual = max(
            intersection.residual,
            max(projection.residual, (intersection.point - targetPoint).length)
        )
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A remapped implicit curve analytic-surface root failed residual verification."
            )
        }
        let curveGeometry = try curve.differentialGeometry(
            at: intersection.curveParameter,
            tolerance: tolerance
        )
        let targetNormal = try surfaceNormalResolver.normal(
            at: intersection.point,
            on: targetSurface,
            u: surfaceU,
            v: surfaceV,
            tolerance: tolerance
        )
        let kind: CurveSurfaceIntersectionKind = abs(
            curveGeometry.tangent.dot(targetNormal)
        ) <= tolerance.angle ? .tangent : .transverse
        return try CurveSurfaceIntersection(
            point: intersection.point,
            curveParameter: intersection.curveParameter,
            surfaceU: surfaceU,
            surfaceV: surfaceV,
            kind: kind,
            residual: residual,
            iterations: intersection.iterations
        )
    }

    private func periodicSeamOffsets(
        for surface: CanonicalAnalyticSurface,
        maximumCount: Int
    ) -> [Double] {
        switch surface {
        case .plane:
            return [0.0]
        case .cylinder, .cone, .sphere, .torus:
            let initialOffset = Double.pi * 0.125
            let goldenAngle = Double.pi * (3.0 - sqrt(5.0))
            return (0..<maximumCount).map {
                initialOffset + Double($0) * goldenAngle
            }
        case .unsupported:
            return []
        }
    }

    private func rationalSearchRanges(
        surface: BSplineSurface3D,
        targetSurface: Surface3D,
        canonicalTarget: CanonicalAnalyticSurface,
        seamOffset: Double,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [(u: ScalarInterval, v: ScalarInterval)]? {
        let parameterOffset = try periodicParameterOffset(
            targetSurface: targetSurface,
            canonicalTarget: canonicalTarget,
            tolerance: tolerance
        )
        let requested: (
            u: ScalarInterval?,
            v: ScalarInterval?
        )
        switch canonicalTarget {
        case let .plane(plane):
            requested = try planeRationalRanges(
                targetSurface: targetSurface,
                plane: plane,
                options: options,
                tolerance: tolerance
            )
        case .cylinder, .cone:
            guard let u = try periodicRationalRange(
                requested: options.surfaceURange,
                seamOffset: seamOffset,
                parameterOffset: parameterOffset
            ) else {
                return nil
            }
            requested = (u: u, v: options.surfaceVRange)
        case .sphere:
            guard let u = try periodicRationalRange(
                requested: options.surfaceURange,
                seamOffset: seamOffset,
                parameterOffset: parameterOffset
            ) else {
                return nil
            }
            requested = (
                u: u,
                v: try sphericalMeridianRange(
                    requested: options.surfaceVRange
                )
            )
        case .torus:
            guard let u = try periodicRationalRange(
                requested: options.surfaceURange,
                seamOffset: seamOffset,
                parameterOffset: parameterOffset
            ), let v = try periodicRationalRange(
                requested: options.surfaceVRange,
                seamOffset: seamOffset,
                parameterOffset: 0.0
            ) else {
                return nil
            }
            requested = (u: u, v: v)
        case .unsupported:
            return nil
        }
        let uSpans = try knotSpans(
            knots: surface.uKnots,
            requested: requested.u
        )
        let vSpans = try knotSpans(
            knots: surface.vKnots,
            requested: requested.v
        )
        return uSpans.flatMap { u in
            vSpans.map { v in (u: u, v: v) }
        }
    }

    private func planeRationalRanges(
        targetSurface: Surface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> (u: ScalarInterval?, v: ScalarInterval?) {
        guard case let .plane(legacyPlane) = targetSurface else {
            return (
                u: options.surfaceURange,
                v: options.surfaceVRange
            )
        }
        guard let requestedU = options.surfaceURange,
              let requestedV = options.surfaceVRange else {
            return (u: nil, v: nil)
        }
        let targetBasis = try circleOrthonormalBasis(
            legacyPlane.normal,
            tolerance: tolerance
        )
        let rationalBasis = try analyticOrthonormalBasis(
            plane.normal,
            tolerance: tolerance
        )
        let corners = [
            (requestedU.lower, requestedV.lower),
            (requestedU.upper, requestedV.lower),
            (requestedU.lower, requestedV.upper),
            (requestedU.upper, requestedV.upper),
        ].map { targetU, targetV in
            let offset =
                targetBasis.u * targetU + targetBasis.v * targetV
            return (
                u: offset.dot(rationalBasis.u),
                v: offset.dot(rationalBasis.v)
            )
        }
        return (
            u: try ScalarInterval(
                lower: corners.map(\.u).min() ?? 0.0,
                upper: corners.map(\.u).max() ?? 0.0
            ),
            v: try ScalarInterval(
                lower: corners.map(\.v).min() ?? 0.0,
                upper: corners.map(\.v).max() ?? 0.0
            )
        )
    }

    private func periodicRationalRange(
        requested: ScalarInterval?,
        seamOffset: Double,
        parameterOffset: Double
    ) throws -> ScalarInterval? {
        guard let requested else {
            return try ScalarInterval(lower: 0.0, upper: 4.0)
        }
        let period = 2.0 * Double.pi
        guard requested.width < period else {
            return try ScalarInterval(lower: 0.0, upper: 4.0)
        }
        let shiftedLower = requested.lower + parameterOffset
        let shiftedUpper = requested.upper + parameterOffset
        let cycle = floor((shiftedLower - seamOffset) / period)
        let lower = shiftedLower - seamOffset - cycle * period
        let upper = shiftedUpper - seamOffset - cycle * period
        let boundaryEnvelope = Double.ulpOfOne * 4_096.0
        guard lower >= -boundaryEnvelope,
              upper <= period + boundaryEnvelope else {
            return nil
        }
        let internalLower = rationalCircleParameter(
            angle: max(lower, 0.0)
        ).nextDown
        let internalUpper = rationalCircleParameter(
            angle: min(upper, period)
        ).nextUp
        guard internalLower < internalUpper else {
            return nil
        }
        return try ScalarInterval(
            lower: max(0.0, internalLower),
            upper: min(4.0, internalUpper)
        )
    }

    private func periodicParameterOffset(
        targetSurface: Surface3D,
        canonicalTarget: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard case let .cylinder(cylinder) = targetSurface,
              case let .cylinder(canonicalCylinder) = canonicalTarget else {
            return 0.0
        }
        let targetBasis = try circleOrthonormalBasis(
            cylinder.axis,
            tolerance: tolerance
        )
        let rationalBasis = try analyticOrthonormalBasis(
            canonicalCylinder.axis,
            tolerance: tolerance
        )
        return atan2(
            targetBasis.u.dot(rationalBasis.v),
            targetBasis.u.dot(rationalBasis.u)
        )
    }

    private func rationalCircleParameter(angle: Double) -> Double {
        let period = 2.0 * Double.pi
        if angle <= 0.0 { return 0.0 }
        if angle >= period { return 4.0 }
        let quarterAngle = Double.pi * 0.5
        let quarter = min(Int(floor(angle / quarterAngle)), 3)
        let localAngle = angle - Double(quarter) * quarterAngle
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<64 {
            let parameter = (lower + upper) * 0.5
            if rationalQuarterCircleAngle(parameter: parameter)
                < localAngle {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return Double(quarter) + (lower + upper) * 0.5
    }

    private func rationalQuarterCircleAngle(parameter: Double) -> Double {
        let oneMinusParameter = 1.0 - parameter
        let weightedProduct =
            2.0 * sqrt(0.5) * oneMinusParameter * parameter
        let x = oneMinusParameter * oneMinusParameter + weightedProduct
        let y = weightedProduct + parameter * parameter
        return atan2(y, x)
    }

    private func sphericalMeridianRange(
        requested: ScalarInterval?
    ) throws -> ScalarInterval? {
        guard let requested else {
            return try ScalarInterval(lower: 0.0, upper: 2.0)
        }
        let lowerLatitude = -Double.pi * 0.5
        let upperLatitude = Double.pi * 0.5
        let lower = max(requested.lower, lowerLatitude)
        let upper = min(requested.upper, upperLatitude)
        guard lower <= upper else {
            return try ScalarInterval(lower: 0.0, upper: 0.0)
        }
        let quarter = Double.pi * 0.5
        let internalLower = max(
            0.0,
            floor((lower - lowerLatitude) / quarter)
        )
        let internalUpper = min(
            2.0,
            ceil((upper - lowerLatitude) / quarter)
        )
        return try ScalarInterval(
            lower: internalLower,
            upper: internalUpper
        )
    }

    private func knotSpans(
        knots: [Double],
        requested: ScalarInterval?
    ) throws -> [ScalarInterval] {
        let unique = Array(Set(knots)).sorted()
        var result: [ScalarInterval] = []
        for index in 1..<unique.count {
            let lower = max(unique[index - 1], requested?.lower ?? -Double.infinity)
            let upper = min(unique[index], requested?.upper ?? Double.infinity)
            guard lower < upper else { continue }
            result.append(try ScalarInterval(lower: lower, upper: upper))
        }
        return result
    }

    private func deduplicated(
        _ intersections: [CurveSurfaceIntersection],
        tolerance: ModelingTolerance
    ) -> [CurveSurfaceIntersection] {
        var result: [CurveSurfaceIntersection] = []
        for intersection in intersections.sorted(by: {
            $0.curveParameter < $1.curveParameter
        }) {
            if result.contains(where: {
                abs($0.curveParameter - intersection.curveParameter)
                    <= tolerance.relative
                    && ($0.point - intersection.point).length
                        <= tolerance.distance
            }) {
                continue
            }
            result.append(intersection)
        }
        return result
    }

    private func corners(of box: BoundingBox3D) -> [Point3D] {
        [
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.maximum.z),
        ]
    }
}
