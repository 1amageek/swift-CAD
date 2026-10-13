import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactLinearSectionSweepBodyBuilder: Sendable {
    private let featureID: FeatureID
    private let context: EvaluationContext
    private let sewer: any BRepSewing
    private let admission: GeometryConversionAdmission?

    package init(
        featureID: FeatureID,
        context: EvaluationContext,
        sewer: any BRepSewing,
        admission: GeometryConversionAdmission? = nil
    ) {
        self.featureID = featureID
        self.context = context
        self.sewer = sewer
        self.admission = admission
    }

    package func build(
        profile: Profile,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        let spanBuilder = ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance, admission: admission
        )
        return try build(
            sectionSpanLoops: spanBuilder.profileLoopSpans(from: profile),
            sectionIsClosed: true,
            profilePlane: profile.plane,
            pathSegments: pathSegments,
            pathEndPoint: pathEndPoint,
            resultKind: resultKind,
            endTransform: endTransform,
            spanBuilder: spanBuilder
        )
    }

    package func build(
        faceSection: ResolvedFaceSection,
        pathSegments: [EvaluatedCurvePathSegment], pathEndPoint: Point3D,
        resultKind: SweepResultKind, endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, admission: admission)
        return try build(sectionSpanLoops: spanBuilder.faceLoopSpans(from: faceSection),
            sectionIsClosed: true, profilePlane: faceSection.plane,
            pathSegments: pathSegments, pathEndPoint: pathEndPoint,
            resultKind: resultKind, endTransform: endTransform, spanBuilder: spanBuilder)
    }

    package func build(constructedRegion: ResolvedBoundaryRegion,
        pathSegments: [EvaluatedCurvePathSegment], pathEndPoint: Point3D,
        resultKind: SweepResultKind, endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, admission: admission)
        return try build(sectionSpanLoops: spanBuilder.constructedRegionLoopSpans(from: constructedRegion),
            sectionIsClosed: true, profilePlane: constructedRegion.plane,
            pathSegments: pathSegments, pathEndPoint: pathEndPoint, resultKind: resultKind,
            endTransform: endTransform, spanBuilder: spanBuilder)
    }

    package func buildTranslatedFace(_ section: ResolvedFaceSection, axis: Vector3D,
        lowerHeight: Double, distance: Double, resultKind: SweepResultKind) throws -> EvaluationResult {
        let admission = try admission ?? CurvedSweepSourceBudget(tolerance: context.tolerance).conversionAdmission()
        let plane = try ExactSweepSectionPlane(section.plane, tolerance: context.tolerance).plane
        let start = plane.origin + axis * lowerHeight
        let end = start + axis * distance
        let rawPath = Curve3D.line(Line3D(origin: start, direction: axis))
        try admission.chargeStorage(bytes: 4 * MemoryLayout<Double>.stride + 2 * MemoryLayout<Point3D>.stride)
        let path = try ExactBSplineCurveSpan(curve: BSplineCurve3D(degree: 1,
            knots: [0, 0, 1, 1], controlPoints: [start, end]),
            tolerance: context.tolerance, originalChart: OriginalCurveSpanParameterChart(
                curve: rawPath, startParameter: 0, endParameter: distance), admission: admission)
        let loops = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, admission: admission)
            .faceLoopSpans(from: section)
        try admission.chargeStorage(bytes: MemoryLayout<ExactBSplineCurveSpan>.stride)
        let request = try ExactLinearSectionSweepFacePatchBuilder(tolerance: context.tolerance,
            admission: admission).request(profileSpanLoops: loops, pathSpans: [path],
                profilePlane: section.plane, sectionIsClosed: true, resultKind: resultKind,
                featureID: featureID, authoredPathAnchor: plane.origin)
        try admission.chargeStorage(bytes: loops.count * MemoryLayout<Int>.stride)
        return try evaluationResult(request: request, profileSpanCounts: loops.map { $0.count },
            pathSpanCount: 1, includesCaps: resultKind == .solid)
    }

    package func buildSheet(
        section: EvaluatedCurve,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard let profilePlane = section.plane else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Exact linear section Sweep sheet sections require profile-plane metadata."
            )
        }
        let spanBuilder = ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance, admission: admission
        )
        return try build(
            sectionSpanLoops: [spanBuilder.sectionSpans(from: section)],
            sectionIsClosed: section.isClosed,
            profilePlane: profilePlane,
            pathSegments: pathSegments,
            pathEndPoint: pathEndPoint,
            resultKind: .sheet,
            endTransform: endTransform,
            spanBuilder: spanBuilder
        )
    }

    package func buildTranslatedSheet(
        section: EvaluatedCurve, startOffset: Vector3D, endOffset: Vector3D
    ) throws -> EvaluationResult {
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, admission: admission).sectionSpans(from: section)
        let request = try ExactLinearSectionSweepFacePatchBuilder(tolerance: context.tolerance)
            .translatedSheetRequest(spans: spans, isClosed: section.isClosed,
                startOffset: startOffset, endOffset: endOffset, featureID: featureID)
        return try evaluationResult(request: request, profileSpanCounts: [spans.count],
            pathSpanCount: 1, includesCaps: false)
    }

    private func build(
        sectionSpanLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D,
        spanBuilder: ExactBSplineCurveSpanBuilder
    ) throws -> EvaluationResult {
        let pathSpans = try spanBuilder.pathSpans(
            from: pathSegments,
            endingAt: pathEndPoint
        )
        let request = try ExactLinearSectionSweepFacePatchBuilder(
            tolerance: context.tolerance, admission: admission
        ).request(
            profileSpanLoops: sectionSpanLoops,
            pathSpans: pathSpans,
            profilePlane: profilePlane,
            sectionIsClosed: sectionIsClosed,
            resultKind: resultKind,
            endTransform: endTransform,
            featureID: featureID
        )
        return try evaluationResult(request: request, profileSpanCounts: sectionSpanLoops.map { $0.count },
            pathSpanCount: pathSpans.count, includesCaps: resultKind == .solid,
            includesEndCap: !endTransform.isTerminalCollapse)
    }

    package func buildCertifiedTwist(
        _ plan: CertifiedTwistSweepPlan,
        resultKind: SweepResultKind
    ) throws -> EvaluationResult {
        let request = try ExactLinearSectionSweepFacePatchBuilder(tolerance: context.tolerance,
            admission: plan.admission).request(
            profileSpanLoops: plan.profileSpanLoops, pathSpans: plan.pathSpans,
            profilePlane: plan.profilePlane, sectionIsClosed: plan.sectionIsClosed, resultKind: resultKind,
            featureID: featureID, certifiedTwist: plan
        )
        return try evaluationResult(request: request, profileSpanCounts: plan.profileSpanLoops.map { $0.count },
            pathSpanCount: plan.pathSpans.count, includesCaps: resultKind == .solid,
            includesEndCap: !plan.terminalSectionCollapsed)
    }

    package func buildMitred(_ mitred: MitredPolylineSweepBuilder.Request) throws -> EvaluationResult {
        try evaluationResult(request: mitred.request, profileSpanCounts: mitred.profileSpanCounts,
            pathSpanCount: mitred.armCount, includesCaps: mitred.includesCaps, extraSideFaceIDs: mitred.cornerFaceIDs,
            includesEndCap: mitred.includesEndCap)
    }

    package func buildCertifiedCurvedPath(
        _ plan: CertifiedCurvedPathSweepPlan,
        resultKind: SweepResultKind
    ) throws -> EvaluationResult {
        let request = try CertifiedCurvedPathSweepFacePatchBuilder(tolerance: context.tolerance)
            .request(plan, resultKind: resultKind, featureID: featureID)
        return try evaluationResult(request: request, profileSpanCounts: plan.profileSpanLoops.map { $0.count },
            pathSpanCount: plan.pieceCount, includesCaps: resultKind == .solid && plan.pathIsClosed == false,
            includesEndCap: !plan.terminalSectionCollapsed)
    }

    private func evaluationResult(
        request: BRepSewingRequest, profileSpanCounts: [Int], pathSpanCount: Int, includesCaps: Bool,
        extraSideFaceIDs: [String] = [], includesEndCap: Bool = true
    ) throws -> EvaluationResult {
        let sewn = try sewer.sew(request, tolerance: context.tolerance)
        let combined = try BRepModelCombiner().combined([context.brep, sewn.brep])
        let subshapes = try semanticSubshapes(sewn: sewn, profileSpanCounts: profileSpanCounts,
            pathSpanCount: pathSpanCount, includesCaps: includesCaps, extraSideFaceIDs: extraSideFaceIDs, includesEndCap: includesEndCap)
        return EvaluationResult(brep: combined, subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(featureID: featureID, subshapes: subshapes))
    }

    private func semanticSubshapes(
        sewn: BRepSewingResult,
        profileSpanCounts: [Int],
        pathSpanCount: Int,
        includesCaps: Bool,
        extraSideFaceIDs: [String], includesEndCap: Bool
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [
            subshapeID(role: .body, ordinal: 0): .body(sewn.bodyID),
        ]
        if includesCaps {
            result[subshapeID(role: .startFace, ordinal: 0)] = try reference(
                .face("sweep:cap:start"),
                in: sewn
            )
            if includesEndCap {
                result[subshapeID(role: .endFace, ordinal: 0)] = try reference(
                    .face("sweep:cap:end"),
                    in: sewn
                )
            }
        }
        var sideOrdinal = 0
        for pathIndex in 0..<pathSpanCount {
            for (loopIndex, profileSpanCount) in profileSpanCounts.enumerated() {
                for profileIndex in 0..<profileSpanCount {
                    let stableID = loopIndex == 0
                        ? "sweep:side:path:\(pathIndex):profile:\(profileIndex)"
                        : "sweep:side:path:\(pathIndex):inner:\(loopIndex - 1):profile:\(profileIndex)"
                    result[subshapeID(
                        role: .sideFace,
                        ordinal: sideOrdinal
                    )] = try reference(
                        .face(stableID),
                        in: sewn
                    )
                    sideOrdinal += 1
                }
            }
        }
        for stableID in extraSideFaceIDs {
            result[subshapeID(role: .sideFace, ordinal: sideOrdinal)] = try reference(.face(stableID), in: sewn)
            sideOrdinal += 1
        }
        for (ordinal, edgeID) in sewn.brep.edges.keys.sorted(by: {
            $0.description < $1.description
        }).enumerated() {
            result[subshapeID(role: .edge, ordinal: ordinal)] = .edge(edgeID)
        }
        for (ordinal, vertexID) in sewn.brep.vertices.keys.sorted(by: {
            $0.description < $1.description
        }).enumerated() {
            result[subshapeID(role: .vertex, ordinal: ordinal)] = .vertex(vertexID)
        }
        return result
    }

    private func reference(
        _ key: BRepSewingStableKey,
        in result: BRepSewingResult
    ) throws -> TopologyReference {
        guard let reference = result.stableReferences[key] else {
            throw TopologyError.missingReference(
                "Missing exact sweep topology reference \(key)."
            )
        }
        return reference
    }

    private func subshapeID(
        role: GeneratedSubshapeRole,
        ordinal: Int
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: role.rawValue,
            ordinal: ordinal
        )
    }
}
