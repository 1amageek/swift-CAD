import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactLinearSectionSweepFacePatchBuilder: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func request(
        profileSpans: [ExactBSplineCurveSpan],
        pathSpans: [ExactBSplineCurveSpan],
        profilePlane: SketchPlane,
        sectionIsClosed: Bool,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D = .identity,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        guard profileSpans.isEmpty == false,
              pathSpans.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact linear section Sweep requires a nonempty section and an open path."
            )
        }
        guard resultKind != .solid || sectionIsClosed else {
            throw FeatureEvaluationError.invalidGraph(
                "Solid exact linear section Sweeps require a closed profile section."
            )
        }
        try validateSectionContinuity(
            profileSpans,
            isClosed: sectionIsClosed
        )
        let sectionPlane = try ExactSweepSectionPlane(
            profilePlane,
            tolerance: tolerance
        )
        try validateProfileSpans(profileSpans, on: sectionPlane.plane)
        let advanceSign = try certifiedAdvanceSign(
            pathSpans: pathSpans,
            profileNormal: sectionPlane.plane.normal,
            featureID: featureID
        )
        let windingSign = sectionIsClosed
            ? try profileWindingSign(
                profileSpans,
                normal: sectionPlane.plane.normal,
                featureID: featureID
            )
            : 1.0
        let transformLaw = try ExactLinearSectionTransformLaw(
            pathSpans: pathSpans,
            endTransform: endTransform,
            featureID: featureID,
            tolerance: tolerance
        )
        let pathStart = transformLaw.pathStart
        let pathEnd = transformLaw.pathEnd
        let pathAnchor = sectionPlane.orthogonalProjection(pathStart)
        var patches: [BRepSewingFacePatch] = []
        if resultKind == .solid {
            patches.append(try capPatch(
                profileSpans: profileSpans,
                pathPoint: pathStart,
                pathAnchor: pathAnchor,
                transform: .identity,
                sectionPlane: sectionPlane,
                desiredNormalSign: -advanceSign,
                windingSign: windingSign,
                reversedBoundary: true,
                stableID: "sweep:cap:start"
            ))
            patches.append(try capPatch(
                profileSpans: profileSpans,
                pathPoint: pathEnd,
                pathAnchor: pathAnchor,
                transform: endTransform,
                sectionPlane: sectionPlane,
                desiredNormalSign: advanceSign,
                windingSign: windingSign,
                reversedBoundary: false,
                stableID: "sweep:cap:end"
            ))
        }
        let sideOrientation: Orientation
        if sectionIsClosed {
            sideOrientation = windingSign * advanceSign > 0.0
                ? .forward
                : .reversed
        } else {
            sideOrientation = .forward
        }
        for pathIndex in pathSpans.indices {
            for profileIndex in profileSpans.indices {
                patches.append(try sidePatch(
                    profileSpan: profileSpans[profileIndex],
                    pathSpan: pathSpans[pathIndex],
                    pathAnchor: pathAnchor,
                    transformLaw: transformLaw,
                    sectionPlane: sectionPlane,
                    orientation: sideOrientation,
                    stableID: "sweep:side:path:\(pathIndex):profile:\(profileIndex)"
                ))
            }
        }
        let bodyKind: BodyKind = resultKind == .solid ? .solid : .sheet
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: bodyKind,
            shells: [BRepSewingShell(
                stableID: "sweep:shell",
                patches: patches
            )]
        )
    }

    private func sidePatch(
        profileSpan: ExactBSplineCurveSpan,
        pathSpan: ExactBSplineCurveSpan,
        pathAnchor: Point3D,
        transformLaw: ExactLinearSectionTransformLaw,
        sectionPlane: ExactSweepSectionPlane,
        orientation: Orientation,
        stableID: String
    ) throws -> BRepSewingFacePatch {
        let surface = try transformedSurface(
            profileCurve: profileSpan.curve,
            pathCurve: pathSpan.curve,
            pathAnchor: pathAnchor,
            transformLaw: transformLaw,
            sectionPlane: sectionPlane
        )
        let surfaceGeometry = Surface3D.bSpline(surface)
        let uBounds = try closedBounds(surface.uDomain)
        let vBounds = try closedBounds(surface.vDomain)
        let bottom = try exactEdge(
            try transformedProfileCurve(
                profileSpan.curve,
                at: pathSpan.startPoint,
                pathAnchor: pathAnchor,
                transform: transformLaw.transform(at: pathSpan.startPoint),
                sectionPlane: sectionPlane
            ),
            reversed: false,
            surfaceParameterCurve: .constantV(
                v: vBounds.lower,
                uStart: uBounds.lower,
                uEnd: uBounds.upper
            ),
            stableID: "\(stableID):bottom"
        )
        let endRail = try exactEdge(
            try transformedRailCurve(
                pathSpan.curve,
                through: profileSpan.endPoint,
                pathAnchor: pathAnchor,
                transformLaw: transformLaw,
                sectionPlane: sectionPlane
            ),
            reversed: false,
            surfaceParameterCurve: .constantU(
                u: uBounds.upper,
                vStart: vBounds.lower,
                vEnd: vBounds.upper
            ),
            stableID: "\(stableID):end"
        )
        let top = try exactEdge(
            try transformedProfileCurve(
                profileSpan.curve,
                at: pathSpan.endPoint,
                pathAnchor: pathAnchor,
                transform: transformLaw.transform(at: pathSpan.endPoint),
                sectionPlane: sectionPlane
            ),
            reversed: true,
            surfaceParameterCurve: .constantV(
                v: vBounds.upper,
                uStart: uBounds.upper,
                uEnd: uBounds.lower
            ),
            stableID: "\(stableID):top"
        )
        let startRail = try exactEdge(
            try transformedRailCurve(
                pathSpan.curve,
                through: profileSpan.startPoint,
                pathAnchor: pathAnchor,
                transformLaw: transformLaw,
                sectionPlane: sectionPlane
            ),
            reversed: true,
            surfaceParameterCurve: .constantU(
                u: uBounds.lower,
                vStart: vBounds.upper,
                vEnd: vBounds.lower
            ),
            stableID: "\(stableID):start"
        )
        let patch = BRepSewingFacePatch(
            stableID: stableID,
            surface: surfaceGeometry,
            orientation: orientation,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):loop",
                role: .outer,
                edges: [bottom, endRail, top, startRail]
            )]
        )
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func capPatch(
        profileSpans: [ExactBSplineCurveSpan],
        pathPoint: Point3D,
        pathAnchor: Point3D,
        transform: ExactSectionTransform2D,
        sectionPlane: ExactSweepSectionPlane,
        desiredNormalSign: Double,
        windingSign: Double,
        reversedBoundary: Bool,
        stableID: String
    ) throws -> BRepSewingFacePatch {
        guard let first = profileSpans.first else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep cap has no profile span."
            )
        }
        let boundaryNormalSign = reversedBoundary
            ? -windingSign
            : windingSign
        let firstCurve = try transformedProfileCurve(
            first.curve,
            at: pathPoint,
            pathAnchor: pathAnchor,
            transform: transform,
            sectionPlane: sectionPlane
        )
        let surface = Surface3D.plane(Plane3D(
            origin: try Curve3D.bSpline(firstCurve).point(
                at: closedBounds(firstCurve.domain).lower,
                tolerance: tolerance
            ),
            normal: sectionPlane.plane.normal * boundaryNormalSign
        ))
        let ordered = reversedBoundary
            ? Array(profileSpans.indices.reversed())
            : Array(profileSpans.indices)
        let edges = try ordered.map { profileIndex in
            let curve = try transformedProfileCurve(
                profileSpans[profileIndex].curve,
                at: pathPoint,
                pathAnchor: pathAnchor,
                transform: transform,
                sectionPlane: sectionPlane
            )
            return try exactEdge(
                curve,
                reversed: reversedBoundary,
                surfaceParameterCurve: try planarPcurve(
                    curve,
                    reversed: reversedBoundary,
                    on: surface
                ),
                stableID: "\(stableID):edge:\(profileIndex)"
            )
        }
        let patch = BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: boundaryNormalSign == desiredNormalSign
                ? .forward
                : .reversed,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):loop",
                role: .outer,
                edges: edges
            )]
        )
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func transformedSurface(
        profileCurve: BSplineCurve3D,
        pathCurve: BSplineCurve3D,
        pathAnchor: Point3D,
        transformLaw: ExactLinearSectionTransformLaw,
        sectionPlane: ExactSweepSectionPlane
    ) throws -> BSplineSurface3D {
        let controlPoints = pathCurve.controlPoints.map { pathPoint in
            let transform = transformLaw.transform(at: pathPoint)
            return profileCurve.controlPoints.map { profilePoint in
                transformedPoint(
                    profilePoint,
                    at: pathPoint,
                    pathAnchor: pathAnchor,
                    transform: transform,
                    sectionPlane: sectionPlane
                )
            }
        }
        let weights = pathCurve.weights.map { pathWeight in
            profileCurve.weights.map { profileWeight in
                profileWeight * pathWeight
            }
        }
        let surface = BSplineSurface3D(
            uDegree: profileCurve.degree,
            vDegree: pathCurve.degree,
            uKnots: profileCurve.knots,
            vKnots: pathCurve.knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }

    private func exactEdge(
        _ curve: BSplineCurve3D,
        reversed: Bool,
        surfaceParameterCurve: SurfaceParameterCurve,
        stableID: String
    ) throws -> BRepSewingEdge {
        let bounds = try closedBounds(curve.domain)
        let startParameter = reversed ? bounds.upper : bounds.lower
        let endParameter = reversed ? bounds.lower : bounds.upper
        let exactCurve = Curve3D.bSpline(curve)
        return BRepSewingEdge(
            stableID: stableID,
            curve: exactCurve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: try exactCurve.point(
                at: startParameter,
                tolerance: tolerance
            ),
            endPoint: try exactCurve.point(
                at: endParameter,
                tolerance: tolerance
            ),
            surfaceParameterCurve: surfaceParameterCurve
        )
    }

    private func transformedProfileCurve(
        _ source: BSplineCurve3D,
        at pathPoint: Point3D,
        pathAnchor: Point3D,
        transform: ExactSectionTransform2D,
        sectionPlane: ExactSweepSectionPlane
    ) throws -> BSplineCurve3D {
        let curve = BSplineCurve3D(
            degree: source.degree,
            knots: source.knots,
            controlPoints: source.controlPoints.map {
                transformedPoint(
                    $0,
                    at: pathPoint,
                    pathAnchor: pathAnchor,
                    transform: transform,
                    sectionPlane: sectionPlane
                )
            },
            weights: source.weights
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func transformedRailCurve(
        _ pathCurve: BSplineCurve3D,
        through profilePoint: Point3D,
        pathAnchor: Point3D,
        transformLaw: ExactLinearSectionTransformLaw,
        sectionPlane: ExactSweepSectionPlane
    ) throws -> BSplineCurve3D {
        let curve = BSplineCurve3D(
            degree: pathCurve.degree,
            knots: pathCurve.knots,
            controlPoints: pathCurve.controlPoints.map { pathPoint in
                transformedPoint(
                    profilePoint,
                    at: pathPoint,
                    pathAnchor: pathAnchor,
                    transform: transformLaw.transform(at: pathPoint),
                    sectionPlane: sectionPlane
                )
            },
            weights: pathCurve.weights
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func transformedPoint(
        _ profilePoint: Point3D,
        at pathPoint: Point3D,
        pathAnchor: Point3D,
        transform: ExactSectionTransform2D,
        sectionPlane: ExactSweepSectionPlane
    ) -> Point3D {
        let localOffset = sectionPlane.localOffset(
            from: pathAnchor,
            to: profilePoint
        )
        return pathPoint + sectionPlane.worldOffset(
            transform.applied(to: localOffset)
        )
    }

    private func planarPcurve(
        _ curve: BSplineCurve3D,
        reversed: Bool,
        on surface: Surface3D
    ) throws -> SurfaceParameterCurve {
        var parameterCurve = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: try curve.controlPoints.map { point in
                let parameter = try surface.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
                return Point2D(x: parameter.u, y: parameter.v)
            },
            weights: curve.weights
        )
        if reversed {
            parameterCurve = try parameterCurve.reversed(
                tolerance: tolerance
            )
        }
        try parameterCurve.validate(tolerance: tolerance)
        return .bSpline(parameterCurve)
    }

    private func validateProfileSpans(
        _ spans: [ExactBSplineCurveSpan],
        on plane: Plane3D
    ) throws {
        for span in spans {
            for point in span.curve.controlPoints {
                let residual = abs((point - plane.origin).dot(plane.normal))
                guard residual <= tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        residual: residual,
                        tolerance: tolerance,
                        message: "Exact sweep profile control geometry must lie on the profile plane."
                    )
                }
            }
        }
    }

    private func validateSectionContinuity(
        _ spans: [ExactBSplineCurveSpan],
        isClosed: Bool
    ) throws {
        guard spans.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep section is empty."
            )
        }
        if spans.count > 1 {
            for index in 0..<(spans.count - 1) {
                guard spans[index].endPoint.isApproximatelyEqual(
                    to: spans[index + 1].startPoint,
                    tolerance: tolerance.distance
                ) else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Exact linear section Sweep section spans are disconnected."
                    )
                }
            }
        }
        if isClosed {
            guard spans.last?.endPoint.isApproximatelyEqual(
                to: spans[0].startPoint,
                tolerance: tolerance.distance
            ) == true else {
                throw SketchError.openProfile
            }
        }
    }

    private func certifiedAdvanceSign(
        pathSpans: [ExactBSplineCurveSpan],
        profileNormal: Vector3D,
        featureID: FeatureID
    ) throws -> Double {
        guard let first = pathSpans.first,
              let last = pathSpans.last else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep path is empty."
            )
        }
        let totalAdvance = (last.endPoint - first.startPoint).dot(profileNormal)
        guard abs(totalAdvance) > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .sweepMixedNormalAdvance,
                featureID: featureID,
                residual: abs(totalAdvance),
                tolerance: tolerance,
                message: "Exact linear section Sweep requires nonzero profile-normal path advance."
            )
        }
        let sign = totalAdvance > 0.0 ? 1.0 : -1.0
        for span in pathSpans {
            let spanAdvance = (span.endPoint - span.startPoint).dot(profileNormal)
            guard sign * spanAdvance > tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .sweepMixedNormalAdvance,
                    featureID: featureID,
                    residual: abs(spanAdvance),
                    tolerance: tolerance,
                    message: "Exact linear section Sweep requires every path span to advance strictly in one profile-normal direction."
                )
            }
            let projectedControls = span.curve.controlPoints.map {
                ($0 - first.startPoint).dot(profileNormal)
            }
            for index in 0..<(projectedControls.count - 1) {
                let controlAdvance = projectedControls[index + 1]
                    - projectedControls[index]
                guard sign * controlAdvance >= -tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .sweepMonotonicityCertificateUnavailable,
                        featureID: featureID,
                        residual: abs(controlAdvance),
                        tolerance: tolerance,
                        message: "Exact linear section Sweep path lacks a monotone rational control-polygon certificate."
                    )
                }
            }
        }
        return sign
    }

    private func profileWindingSign(
        _ spans: [ExactBSplineCurveSpan],
        normal: Vector3D,
        featureID: FeatureID
    ) throws -> Double {
        guard let origin = spans.first?.startPoint else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep profile is empty."
            )
        }
        var twiceArea = 0.0
        for span in spans {
            let bounds = try closedBounds(span.curve.domain)
            twiceArea += try adaptiveWindingIntegral(
                curve: span.curve,
                origin: origin,
                normal: normal,
                lower: bounds.lower,
                upper: bounds.upper,
                depth: 0
            )
        }
        let areaTolerance = max(
            tolerance.distance * tolerance.distance,
            Double.ulpOfOne * 256.0
        )
        guard abs(twiceArea) > areaTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: featureID,
                residual: abs(twiceArea),
                tolerance: tolerance,
                message: "Exact linear section Sweep profile has indeterminate winding or zero area."
            )
        }
        return twiceArea > 0.0 ? 1.0 : -1.0
    }

    private func adaptiveWindingIntegral(
        curve: BSplineCurve3D,
        origin: Point3D,
        normal: Vector3D,
        lower: Double,
        upper: Double,
        depth: Int
    ) throws -> Double {
        let whole = try gaussianWindingIntegral(
            curve: curve,
            origin: origin,
            normal: normal,
            lower: lower,
            upper: upper
        )
        let middle = 0.5 * (lower + upper)
        let left = try gaussianWindingIntegral(
            curve: curve,
            origin: origin,
            normal: normal,
            lower: lower,
            upper: middle
        )
        let right = try gaussianWindingIntegral(
            curve: curve,
            origin: origin,
            normal: normal,
            lower: middle,
            upper: upper
        )
        let refined = left + right
        let errorTolerance = max(
            tolerance.distance * tolerance.distance,
            abs(refined) * 1.0e-12
        )
        guard depth < 12,
              abs(refined - whole) > errorTolerance else {
            return refined
        }
        return try adaptiveWindingIntegral(
            curve: curve,
            origin: origin,
            normal: normal,
            lower: lower,
            upper: middle,
            depth: depth + 1
        ) + adaptiveWindingIntegral(
            curve: curve,
            origin: origin,
            normal: normal,
            lower: middle,
            upper: upper,
            depth: depth + 1
        )
    }

    private func gaussianWindingIntegral(
        curve: BSplineCurve3D,
        origin: Point3D,
        normal: Vector3D,
        lower: Double,
        upper: Double
    ) throws -> Double {
        let nodes = [
            -0.9061798459386640,
            -0.5384693101056831,
            0.0,
            0.5384693101056831,
            0.9061798459386640,
        ]
        let weights = [
            0.2369268850561891,
            0.4786286704993665,
            0.5688888888888889,
            0.4786286704993665,
            0.2369268850561891,
        ]
        let midpoint = 0.5 * (lower + upper)
        let halfWidth = 0.5 * (upper - lower)
        var sum = 0.0
        for index in nodes.indices {
            let parameter = midpoint + halfWidth * nodes[index]
            let geometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let radial = geometry.position - origin
            sum += weights[index] * radial.cross(
                geometry.firstDerivative
            ).dot(normal)
        }
        return sum * halfWidth
    }

    private func closedBounds(
        _ domain: ParameterDomain
    ) throws -> (lower: Double, upper: Double) {
        guard case let .closed(lower, upper) = domain,
              upper - lower > max(tolerance.angle, Double.ulpOfOne) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact linear section Sweep requires bounded non-degenerate parameter domains."
            )
        }
        return (lower, upper)
    }
}
