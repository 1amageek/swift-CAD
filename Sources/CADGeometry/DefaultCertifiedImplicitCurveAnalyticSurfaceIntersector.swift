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
        seamOffset: Double,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [(u: ScalarInterval, v: ScalarInterval)]? {
        let parameterMap = try AnalyticSurfaceRationalParameterMap(
            surface: targetSurface,
            periodicSeamOffset: seamOffset,
            tolerance: tolerance
        )
        guard let requested = try parameterMap.rationalSearchRanges(
            surfaceU: options.surfaceURange,
            surfaceV: options.surfaceVRange
        ) else { return nil }
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
