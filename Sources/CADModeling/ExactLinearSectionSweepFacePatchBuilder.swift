import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactLinearSectionSweepFacePatchBuilder: Sendable {
    private let tolerance: ModelingTolerance
    private let admission: GeometryConversionAdmission?

    package init(tolerance: ModelingTolerance, admission: GeometryConversionAdmission? = nil) {
        self.tolerance = tolerance
        self.admission = admission
    }

    package func translatedSheetRequest(
        spans: [ExactBSplineCurveSpan], isClosed: Bool,
        startOffset: Vector3D, endOffset: Vector3D, featureID: FeatureID
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        try startOffset.validate()
        try endOffset.validate()
        guard !spans.isEmpty, (endOffset - startOffset).length > tolerance.distance else {
            throw FeatureEvaluationError.invalidGraph("A curve extrusion requires spans and nonzero translation.")
        }
        try validateSectionContinuity(spans, isClosed: isClosed)
        let builder = ExactRuledBSplineSurfaceBuilder()
        let patches = try spans.enumerated().map { index, span in
            func translated(_ offset: Vector3D) -> BSplineCurve3D {
                BSplineCurve3D(degree: span.curve.degree, knots: span.curve.knots,
                    controlPoints: span.curve.controlPoints.map { $0 + offset }, weights: span.curve.weights)
            }
            let surface = try builder.build(startBoundary: translated(startOffset),
                endBoundary: translated(endOffset), tolerance: tolerance)
            let u = try closedBounds(surface.uDomain)
            let v = try closedBounds(surface.vDomain)
            try DefaultSurfaceRegularityValidator().validate(.bSpline(surface),
                over: SurfaceParameterBox(
                    u: try ScalarInterval(lower: u.lower, upper: u.upper),
                    v: try ScalarInterval(lower: v.lower, upper: v.upper)),
                tolerance: tolerance)
            let stableID = sideStableID(pathIndex: 0, loopIndex: 0, profileIndex: index)
            // A straight span swept straight is a flat parallelogram: it is published on its exact
            // plane, bounded by the same edges.
            if try isStraight(span.curve) {
                return try planarSidePatch(ruled: surface, translation: endOffset - startOffset, stableID: stableID)
            }
            return try tensorSidePatch(surface: surface, orientation: .forward, stableID: stableID)
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "sweep:shell", patches: patches)])
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
        try request(
            profileSpanLoops: [profileSpans],
            pathSpans: pathSpans,
            profilePlane: profilePlane,
            sectionIsClosed: sectionIsClosed,
            resultKind: resultKind,
            endTransform: endTransform,
            featureID: featureID
        )
    }

    package func request(
        profileSpanLoops: [[ExactBSplineCurveSpan]],
        pathSpans: [ExactBSplineCurveSpan],
        profilePlane: SketchPlane,
        sectionIsClosed: Bool,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D = .identity,
        featureID: FeatureID,
        certifiedTwist: CertifiedTwistSweepPlan? = nil,
        authoredPathAnchor: Point3D? = nil
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        guard profileSpanLoops.isEmpty == false,
              profileSpanLoops.allSatisfy({ $0.isEmpty == false }),
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
        for profileSpans in profileSpanLoops {
            try validateSectionContinuity(
                profileSpans,
                isClosed: sectionIsClosed
            )
        }
        let sectionPlane = try ExactSweepSectionPlane(
            profilePlane,
            tolerance: tolerance
        )
        for profileSpans in profileSpanLoops {
            try validateProfileSpans(profileSpans, on: sectionPlane.plane)
        }
        let advanceSign = try certifiedAdvanceSign(
            pathSpans: pathSpans,
            profileNormal: sectionPlane.plane.normal,
            featureID: featureID
        )
        let windingSigns = try profileSpanLoops.map { profileSpans in
            sectionIsClosed
                ? try profileWindingSign(
                    profileSpans,
                    normal: sectionPlane.plane.normal,
                    featureID: featureID
                )
                : 1.0
        }
        let transformLaw = try ExactLinearSectionTransformLaw(
            pathSpans: pathSpans,
            endTransform: endTransform,
            featureID: featureID,
            tolerance: tolerance
        )
        let pathStart = transformLaw.pathStart
        let pathEnd = transformLaw.pathEnd
        let pathAnchor = authoredPathAnchor ?? sectionPlane.orthogonalProjection(pathStart)
        var capPatches: [BRepSewingFacePatch] = []
        if resultKind == .solid {
            capPatches.append(try capPatch(
                profileSpanLoops: profileSpanLoops,
                pathPoint: pathStart,
                pathAnchor: pathAnchor,
                transform: .identity,
                sectionPlane: sectionPlane,
                desiredNormalSign: -advanceSign,
                outerWindingSign: windingSigns[0],
                reversedBoundary: true,
                stableID: "sweep:cap:start",
                suppliedCurves: try certifiedTwist?.surfaces.map { loop in
                    try loop[0].map { try $0.uIsoparametricCurve(atV: 0, tolerance: tolerance) }
                }
            ))
            if !endTransform.isTerminalCollapse && certifiedTwist?.terminalSectionCollapsed != true {
                capPatches.append(try capPatch(
                    profileSpanLoops: profileSpanLoops,
                    pathPoint: pathEnd,
                    pathAnchor: pathAnchor,
                    transform: endTransform,
                    sectionPlane: sectionPlane,
                    desiredNormalSign: advanceSign,
                    outerWindingSign: windingSigns[0],
                    reversedBoundary: false,
                    stableID: "sweep:cap:end",
                    suppliedCurves: try certifiedTwist?.surfaces.map { loop in
                        try loop[loop.count - 1].map { try $0.uIsoparametricCurve(atV: 1, tolerance: tolerance) }
                    }
                ))
            }
        }
        var sidePatchesByLoop: [[BRepSewingFacePatch]] = []
        sidePatchesByLoop.reserveCapacity(profileSpanLoops.count)
        for (loopIndex, profileSpans) in profileSpanLoops.enumerated() {
            let sideOrientation: Orientation
            if sectionIsClosed {
                sideOrientation = windingSigns[loopIndex] * advanceSign > 0.0
                    ? .forward
                    : .reversed
            } else {
                sideOrientation = .forward
            }
            var loopPatches: [BRepSewingFacePatch] = []
            for pathIndex in pathSpans.indices {
                for profileIndex in profileSpans.indices {
                    loopPatches.append(try sidePatch(
                        profileSpan: profileSpans[profileIndex],
                        pathSpan: pathSpans[pathIndex],
                        pathAnchor: pathAnchor,
                        transformLaw: transformLaw,
                        sectionPlane: sectionPlane,
                        orientation: sideOrientation,
                        stableID: sideStableID(
                            pathIndex: pathIndex,
                            loopIndex: loopIndex,
                            profileIndex: profileIndex
                        ),
                        suppliedSurface: certifiedTwist?.surfaces[loopIndex][pathIndex][profileIndex]
                    ))
                }
            }
            sidePatchesByLoop.append(loopPatches)
        }
        let bodyKind: BodyKind = resultKind == .solid ? .solid : .sheet
        let shells: [BRepSewingShell]
        if resultKind == .solid {
            shells = [BRepSewingShell(
                stableID: "sweep:shell",
                patches: capPatches + sidePatchesByLoop.flatMap { $0 }
            )]
        } else {
            shells = sidePatchesByLoop.enumerated().map { loopIndex, patches in
                BRepSewingShell(
                    stableID: loopIndex == 0
                        ? "sweep:shell"
                        : "sweep:inner:\(loopIndex - 1):shell",
                    patches: patches
                )
            }
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: bodyKind,
            shells: shells
        )
    }

    private func sideStableID(
        pathIndex: Int,
        loopIndex: Int,
        profileIndex: Int
    ) -> String {
        if loopIndex == 0 {
            return "sweep:side:path:\(pathIndex):profile:\(profileIndex)"
        }
        return "sweep:side:path:\(pathIndex):inner:\(loopIndex - 1):profile:\(profileIndex)"
    }

    private func sidePatch(
        profileSpan: ExactBSplineCurveSpan,
        pathSpan: ExactBSplineCurveSpan,
        pathAnchor: Point3D,
        transformLaw: ExactLinearSectionTransformLaw,
        sectionPlane: ExactSweepSectionPlane,
        orientation: Orientation,
        stableID: String,
        suppliedSurface: BSplineSurface3D? = nil
    ) throws -> BRepSewingFacePatch {
        if let suppliedSurface {
            return try tensorSidePatch(surface: suppliedSurface, orientation: orientation, stableID: stableID)
        }
        let surface = try transformedSurface(
            profileCurve: profileSpan.curve,
            pathCurve: pathSpan.curve,
            pathAnchor: pathAnchor,
            transformLaw: transformLaw,
            sectionPlane: sectionPlane
        )
        if transformLaw.endTransform.isTerminalCollapse {
            return try tensorSidePatch(surface: surface, orientation: orientation, stableID: stableID)
        }
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
        profileSpanLoops: [[ExactBSplineCurveSpan]],
        pathPoint: Point3D,
        pathAnchor: Point3D,
        transform: ExactSectionTransform2D,
        sectionPlane: ExactSweepSectionPlane,
        desiredNormalSign: Double,
        outerWindingSign: Double,
        reversedBoundary: Bool,
        stableID: String,
        suppliedCurves: [[BSplineCurve3D]]? = nil
    ) throws -> BRepSewingFacePatch {
        guard let first = profileSpanLoops.first?.first else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep cap has no profile span."
            )
        }
        let boundaryNormalSign = reversedBoundary
            ? -outerWindingSign
            : outerWindingSign
        let firstCurve = try suppliedCurves?.first?.first ?? transformedProfileCurve(
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
        let loops = try profileSpanLoops.enumerated().map { loopIndex, profileSpans in
            let ordered = reversedBoundary
                ? Array(profileSpans.indices.reversed())
                : Array(profileSpans.indices)
            let loopPrefix = loopIndex == 0
                ? stableID
                : "\(stableID):inner:\(loopIndex - 1)"
            let edges = try ordered.map { profileIndex in
                let curve = try suppliedCurves?[loopIndex][profileIndex] ?? transformedProfileCurve(
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
                    stableID: "\(loopPrefix):edge:\(profileIndex)"
                )
            }
            return BRepSewingLoop(
                stableID: "\(loopPrefix):loop",
                role: loopIndex == 0 ? .outer : .inner,
                edges: edges
            )
        }
        let patch = BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: boundaryNormalSign == desiredNormalSign
                ? .forward
                : .reversed,
            loops: loops
        )
        try patch.validate(tolerance: tolerance)
        return patch
    }

    package func tensorSidePatch(
        surface: BSplineSurface3D,
        orientation: Orientation,
        stableID: String
    ) throws -> BRepSewingFacePatch {
        let u = try closedBounds(surface.uDomain)
        let v = try closedBounds(surface.vDomain)
        let host = Surface3D.bSpline(surface)
        let boundaries: [(BSplineCurve3D, Bool, SurfaceParameterCurve, String)] = [
            (try surface.uIsoparametricCurve(atV: v.lower, tolerance: tolerance), false,
                .constantV(v: v.lower, uStart: u.lower, uEnd: u.upper), "bottom"),
            (try surface.vIsoparametricCurve(atU: u.upper, tolerance: tolerance), false,
                .constantU(u: u.upper, vStart: v.lower, vEnd: v.upper), "end"),
            (try surface.uIsoparametricCurve(atV: v.upper, tolerance: tolerance), true,
                .constantV(v: v.upper, uStart: u.upper, uEnd: u.lower), "top"),
            (try surface.vIsoparametricCurve(atU: u.lower, tolerance: tolerance), true,
                .constantU(u: u.lower, vStart: v.upper, vEnd: v.lower), "start")]
        let edges = try boundaries.map { curve, reversed, pcurve, name in
            try tensorBoundaryEdge(curve: curve, reversed: reversed, surface: host, pcurve: pcurve,
                stableID: "\(stableID):\(name)")
        }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: .bSpline(surface), orientation: orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
        try patch.validate(tolerance: tolerance)
        return patch
    }

    package func tensorBoundaryEdge(curve: BSplineCurve3D, reversed: Bool, surface: Surface3D,
        pcurve: SurfaceParameterCurve, stableID: String) throws -> BRepSewingEdge {
        let lifted = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve))
        if try BRepEdgeGeometryClassifier().kind(curve: lifted, from: 0, to: 1, tolerance: tolerance) == .singular {
            return BRepSewingEdge(stableID: stableID, curve: lifted, startParameter: 0, endParameter: 1,
                startPoint: try lifted.point(at: 0, tolerance: tolerance),
                endPoint: try lifted.point(at: 1, tolerance: tolerance), surfaceParameterCurve: pcurve)
        }
        return try exactEdge(curve, reversed: reversed, surfaceParameterCurve: pcurve, stableID: stableID)
    }

    /// Whether every control point of `curve` lies on the line through its end points.
    package func isStraight(_ curve: BSplineCurve3D) throws -> Bool {
        guard let first = curve.controlPoints.first, let last = curve.controlPoints.last else { return false }
        let chord = last - first
        guard chord.length > tolerance.distance else { return false }
        let direction = chord * (1 / chord.length)
        return curve.controlPoints.allSatisfy { point in
            let offset = point - first
            return (offset - direction * offset.dot(direction)).length <= tolerance.distance
        }
    }

    /// The side patch of a ruled surface that is a flat parallelogram, on its exact plane: its
    /// four boundary edges are the ruled surface's, their parameter curves projected on the plane,
    /// and the plane faces the way the ruled surface does (along the curve, then the translation).
    package func planarSidePatch(ruled surface: BSplineSurface3D, translation: Vector3D, stableID: String) throws -> BRepSewingFacePatch {
        let u = try closedBounds(surface.uDomain)
        let v = try closedBounds(surface.vDomain)
        let bottom = try surface.uIsoparametricCurve(atV: v.lower, tolerance: tolerance)
        let end = try surface.vIsoparametricCurve(atU: u.upper, tolerance: tolerance)
        let top = try surface.uIsoparametricCurve(atV: v.upper, tolerance: tolerance)
        let start = try surface.vIsoparametricCurve(atU: u.lower, tolerance: tolerance)
        let origin = try Curve3D.bSpline(bottom).point(at: closedBounds(bottom.domain).lower, tolerance: tolerance)
        let along = try Curve3D.bSpline(bottom).point(at: closedBounds(bottom.domain).upper, tolerance: tolerance) - origin
        let plane = Surface3D.plane(Plane3D(origin: origin, normal: try along.cross(translation).normalized(tolerance: tolerance.distance)))
        let edges = [
            try exactEdge(bottom, reversed: false, surfaceParameterCurve: try planarPcurve(bottom, reversed: false, on: plane), stableID: "\(stableID):bottom"),
            try exactEdge(end, reversed: false, surfaceParameterCurve: try planarPcurve(end, reversed: false, on: plane), stableID: "\(stableID):end"),
            try exactEdge(top, reversed: true, surfaceParameterCurve: try planarPcurve(top, reversed: true, on: plane), stableID: "\(stableID):top"),
            try exactEdge(start, reversed: true, surfaceParameterCurve: try planarPcurve(start, reversed: true, on: plane), stableID: "\(stableID):start"),
        ]
        let patch = BRepSewingFacePatch(stableID: stableID, surface: plane, orientation: .forward,
            loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
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
        let count = profileCurve.controlPointCount.multipliedReportingOverflow(by: pathCurve.controlPointCount)
        guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Sweep tensor payload count overflowed.") }
        try retain(pathCurve.controlPointCount, of: [Point3D].self)
        try retain(pathCurve.controlPointCount, of: [Double].self)
        try retain(count.partialValue, of: Point3D.self)
        try retain(count.partialValue, of: Double.self)
        try admission?.chargeWork(count.partialValue)
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
        try validateOriginal(.bSpline(surface))
        return surface
    }

    package func exactEdge(
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
        try retain(source.controlPointCount, of: Point3D.self)
        try admission?.chargeWork(source.controlPointCount)
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
        try validateOriginal(.bSpline(curve))
        return curve
    }

    private func transformedRailCurve(
        _ pathCurve: BSplineCurve3D,
        through profilePoint: Point3D,
        pathAnchor: Point3D,
        transformLaw: ExactLinearSectionTransformLaw,
        sectionPlane: ExactSweepSectionPlane
    ) throws -> BSplineCurve3D {
        try retain(pathCurve.controlPointCount, of: Point3D.self)
        try admission?.chargeWork(pathCurve.controlPointCount)
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
        try validateOriginal(.bSpline(curve))
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

    package func planarPcurve(
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

    package func validateProfileSpans(
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

    package func validateSectionContinuity(
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
                message: "Exact linear section Sweep requires nonzero total profile-normal advance and every path span to advance monotonically in one direction."
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

    package func profileWindingSign(
        _ spans: [ExactBSplineCurveSpan],
        normal: Vector3D,
        featureID: FeatureID
    ) throws -> Double {
        guard let origin = spans.first?.startPoint else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep profile is empty."
            )
        }
        let admission = try admission ?? CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission()
        try admission.chargeStorage(bytes: spans.count * MemoryLayout<OriginalCurveSpanParameterChart>.stride)
        let charts = try spans.map { try admission.chargeWork(); return $0.originalChart }
        return try OriginalPlanarLoopOrientation().counterclockwise(charts: charts,
            origin: origin, normal: normal, tolerance: tolerance, admission: admission) ? 1 : -1
    }

    @available(*, deprecated, message: "Production winding uses the complete original parameter-chart integral.")
    // FIXME(INCOMPLETE_IMPLEMENTATION): This unused candidate Gaussian estimator
    // remains for migration comparison only. Sweep publication never calls it;
    // its estimates cannot establish original section winding before removal.
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

    private func retain<T>(_ count: Int, of: T.Type) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Sweep geometry payload byte count overflowed.")
        }
        try admission?.chargeStorage(bytes: bytes.partialValue)
    }

    private func validateOriginal(_ curve: Curve3D) throws {
        if let admission {
            try curve.validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { _ in try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
        } else { try curve.validate(tolerance: tolerance) }
    }

    private func validateOriginal(_ surface: Surface3D) throws {
        if let admission {
            try surface.validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { _ in try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
        } else { try surface.validate(tolerance: tolerance) }
    }

    package func closedBounds(
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
