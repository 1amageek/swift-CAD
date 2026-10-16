import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactLinearSectionSweepBodyBuilder: Sendable {
    private let featureID: FeatureID
    private let context: EvaluationContext
    private let sewer: any BRepSewing

    package init(
        featureID: FeatureID,
        context: EvaluationContext,
        sewer: any BRepSewing
    ) {
        self.featureID = featureID
        self.context = context
        self.sewer = sewer
    }

    package func build(
        profile: Profile,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try build(profile: profile, pathSegments: pathSegments, pathEndPoint: pathEndPoint, resultKind: resultKind, endTransform: endTransform, using: &execution)
    }

    package func build(
        faceSection: ResolvedFaceSection,
        pathSegments: [EvaluatedCurvePathSegment], pathEndPoint: Point3D,
        resultKind: SweepResultKind, endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try build(faceSection: faceSection, pathSegments: pathSegments, pathEndPoint: pathEndPoint, resultKind: resultKind, endTransform: endTransform, using: &execution)
    }

    package func build(constructedRegion: ResolvedBoundaryRegion,
        pathSegments: [EvaluatedCurvePathSegment], pathEndPoint: Point3D,
        resultKind: SweepResultKind, endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try build(constructedRegion: constructedRegion, pathSegments: pathSegments, pathEndPoint: pathEndPoint, resultKind: resultKind, endTransform: endTransform, using: &execution)
    }

    package func buildTranslatedFace(_ section: ResolvedFaceSection, axis: Vector3D,
        lowerHeight: Double, distance: Double, resultKind: SweepResultKind) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try buildTranslatedFace(section, axis: axis, lowerHeight: lowerHeight, distance: distance, resultKind: resultKind, using: &execution)
    }

    package func buildSheet(
        section: EvaluatedCurve,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        endTransform: ExactSectionTransform2D = .identity
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try buildSheet(section: section, pathSegments: pathSegments, pathEndPoint: pathEndPoint, endTransform: endTransform, using: &execution)
    }

    package func buildTranslatedSheet(
        section: EvaluatedCurve, startOffset: Vector3D, endOffset: Vector3D
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try buildTranslatedSheet(section: section, startOffset: startOffset, endOffset: endOffset, using: &execution)
    }

    package func buildCertifiedTwist(
        _ plan: CertifiedTwistSweepPlan,
        resultKind: SweepResultKind
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try buildCertifiedTwist(plan, resultKind: resultKind, using: &execution)
    }

    package func buildMitred(_ mitred: MitredPolylineSweepBuilder.Request) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try buildMitred(mitred, using: &execution)
    }

    package func buildCertifiedCurvedPath(
        _ plan: CertifiedCurvedPathSweepPlan,
        resultKind: SweepResultKind
    ) throws -> EvaluationResult {
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try buildCertifiedCurvedPath(plan, resultKind: resultKind, using: &execution)
    }

    package func build(
        profile: Profile,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D = .identity
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try context.tolerance.validate()
        let spanBuilder = try ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance, using: &execution
        )
        return try build(
            sectionSpanLoops: spanBuilder.profileLoopSpans(from: profile, using: &execution),
            sectionIsClosed: true,
            profilePlane: profile.plane,
            pathSegments: pathSegments,
            pathEndPoint: pathEndPoint,
            resultKind: resultKind,
            endTransform: endTransform,
            spanBuilder: spanBuilder
        , using: &execution)
    }

    package func build(
        faceSection: ResolvedFaceSection,
        pathSegments: [EvaluatedCurvePathSegment], pathEndPoint: Point3D,
        resultKind: SweepResultKind, endTransform: ExactSectionTransform2D = .identity
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let spanBuilder = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, using: &execution)
        return try build(sectionSpanLoops: spanBuilder.faceLoopSpans(from: faceSection, using: &execution),
            sectionIsClosed: true, profilePlane: faceSection.plane,
            pathSegments: pathSegments, pathEndPoint: pathEndPoint,
            resultKind: resultKind, endTransform: endTransform, spanBuilder: spanBuilder, using: &execution)
    }

    package func build(constructedRegion: ResolvedBoundaryRegion,
        pathSegments: [EvaluatedCurvePathSegment], pathEndPoint: Point3D,
        resultKind: SweepResultKind, endTransform: ExactSectionTransform2D = .identity
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let spanBuilder = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, using: &execution)
        return try build(sectionSpanLoops: spanBuilder.constructedRegionLoopSpans(from: constructedRegion, using: &execution),
            sectionIsClosed: true, profilePlane: constructedRegion.plane,
            pathSegments: pathSegments, pathEndPoint: pathEndPoint, resultKind: resultKind,
            endTransform: endTransform, spanBuilder: spanBuilder, using: &execution)
    }

    package func buildTranslatedFace(_ section: ResolvedFaceSection, axis: Vector3D,
        lowerHeight: Double, distance: Double, resultKind: SweepResultKind, using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let plane = try ExactSweepSectionPlane(section.plane, tolerance: context.tolerance).plane
        let start = plane.origin + axis * lowerHeight
        let end = start + axis * distance
        let rawPath = Curve3D.line(Line3D(origin: start, direction: axis))
        try execution.retainStorage(bytes: 4 * MemoryLayout<Double>.stride + 2 * MemoryLayout<Point3D>.stride)
        let path = try ExactBSplineCurveSpan(curve: BSplineCurve3D(degree: 1,
            knots: [0, 0, 1, 1], controlPoints: [start, end]),
            tolerance: context.tolerance, originalChart: OriginalCurveSpanParameterChart(
                curve: rawPath, startParameter: 0, endParameter: distance), using: &execution)
        let loops = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, using: &execution)
            .faceLoopSpans(from: section, using: &execution)
        try execution.retainStorage(bytes: MemoryLayout<ExactBSplineCurveSpan>.stride)
        let request = try ExactLinearSectionSweepFacePatchBuilder(tolerance: context.tolerance).request(profileSpanLoops: loops, pathSpans: [path],
                profilePlane: section.plane, sectionIsClosed: true, resultKind: resultKind,
                featureID: featureID, authoredPathAnchor: plane.origin, using: &execution)
        try execution.retainStorage(bytes: loops.count * MemoryLayout<Int>.stride)
        return try evaluationResult(request: request, profileSpanCounts: loops.map { $0.count },
            pathSpanCount: 1, includesCaps: resultKind == .solid, using: &execution)
    }

    package func buildSheet(
        section: EvaluatedCurve,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        endTransform: ExactSectionTransform2D = .identity
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
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
        let spanBuilder = try ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance, using: &execution
        )
        return try build(
            sectionSpanLoops: [spanBuilder.sectionSpans(from: section, using: &execution)],
            sectionIsClosed: section.isClosed,
            profilePlane: profilePlane,
            pathSegments: pathSegments,
            pathEndPoint: pathEndPoint,
            resultKind: .sheet,
            endTransform: endTransform,
            spanBuilder: spanBuilder
        , using: &execution)
    }

    package func buildTranslatedSheet(
        section: EvaluatedCurve, startOffset: Vector3D, endOffset: Vector3D
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, using: &execution).sectionSpans(from: section, using: &execution)
        let request = try ExactLinearSectionSweepFacePatchBuilder(tolerance: context.tolerance)
            .translatedSheetRequest(spans: spans, isClosed: section.isClosed,
                startOffset: startOffset, endOffset: endOffset, featureID: featureID, using: &execution)
        return try evaluationResult(request: request, profileSpanCounts: [spans.count],
            pathSpanCount: 1, includesCaps: false, using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let pathSpans = try spanBuilder.pathSpans(
            from: pathSegments,
            endingAt: pathEndPoint
        , using: &execution)
        let request = try ExactLinearSectionSweepFacePatchBuilder(
            tolerance: context.tolerance
        ).request(
            profileSpanLoops: sectionSpanLoops,
            pathSpans: pathSpans,
            profilePlane: profilePlane,
            sectionIsClosed: sectionIsClosed,
            resultKind: resultKind,
            endTransform: endTransform,
            featureID: featureID
        , using: &execution)
        return try evaluationResult(request: request, profileSpanCounts: sectionSpanLoops.map { $0.count },
            pathSpanCount: pathSpans.count, includesCaps: resultKind == .solid,
            includesEndCap: !endTransform.isTerminalCollapse, using: &execution)
    }

    package func buildCertifiedTwist(
        _ plan: CertifiedTwistSweepPlan,
        resultKind: SweepResultKind
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let request = try ExactLinearSectionSweepFacePatchBuilder(tolerance: context.tolerance).request(
            profileSpanLoops: plan.profileSpanLoops, pathSpans: plan.pathSpans,
            profilePlane: plan.profilePlane, sectionIsClosed: plan.sectionIsClosed, resultKind: resultKind,
            featureID: featureID, certifiedTwist: plan
        , using: &execution)
        return try evaluationResult(request: request, profileSpanCounts: plan.profileSpanLoops.map { $0.count },
            pathSpanCount: plan.pathSpans.count, includesCaps: resultKind == .solid,
            includesEndCap: !plan.terminalSectionCollapsed, using: &execution)
    }

    package func buildMitred(_ mitred: MitredPolylineSweepBuilder.Request, using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try evaluationResult(request: mitred.request, profileSpanCounts: mitred.profileSpanCounts,
            pathSpanCount: mitred.armCount, includesCaps: mitred.includesCaps, extraSideFaceIDs: mitred.cornerFaceIDs,
            includesEndCap: mitred.includesEndCap, using: &execution)
    }

    package func buildCertifiedCurvedPath(
        _ plan: CertifiedCurvedPathSweepPlan,
        resultKind: SweepResultKind
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let request = try CertifiedCurvedPathSweepFacePatchBuilder(tolerance: context.tolerance)
            .request(plan, resultKind: resultKind, featureID: featureID, using: &execution)
        return try evaluationResult(request: request, profileSpanCounts: plan.profileSpanLoops.map { $0.count },
            pathSpanCount: plan.pieceCount, includesCaps: resultKind == .solid && plan.pathIsClosed == false,
            includesEndCap: !plan.terminalSectionCollapsed, using: &execution)
    }

    private func evaluationResult(
        request: BRepSewingRequest, profileSpanCounts: [Int], pathSpanCount: Int, includesCaps: Bool,
        extraSideFaceIDs: [String] = [], includesEndCap: Bool = true
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        let sewn = try sewer.sew(request, tolerance: context.tolerance, using: &execution)
        let combined = try BRepModelCombiner().combined([context.brep, sewn.brep], using: &execution)
        let subshapes = try semanticSubshapes(sewn: sewn, profileSpanCounts: profileSpanCounts,
            pathSpanCount: pathSpanCount, includesCaps: includesCaps, extraSideFaceIDs: extraSideFaceIDs, includesEndCap: includesEndCap)
        return EvaluationResult(brep: combined, subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(featureID: featureID, subshapes: subshapes, using: &execution))
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
