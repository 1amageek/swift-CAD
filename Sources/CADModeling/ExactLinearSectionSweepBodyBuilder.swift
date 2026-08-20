import CADCore
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
        try context.tolerance.validate()
        let spanBuilder = ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance
        )
        return try build(
            sectionSpans: spanBuilder.profileSpans(from: profile),
            sectionIsClosed: true,
            profilePlane: profile.plane,
            pathSegments: pathSegments,
            pathEndPoint: pathEndPoint,
            resultKind: resultKind,
            endTransform: endTransform,
            spanBuilder: spanBuilder
        )
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
            tolerance: context.tolerance
        )
        return try build(
            sectionSpans: spanBuilder.sectionSpans(from: section),
            sectionIsClosed: section.isClosed,
            profilePlane: profilePlane,
            pathSegments: pathSegments,
            pathEndPoint: pathEndPoint,
            resultKind: .sheet,
            endTransform: endTransform,
            spanBuilder: spanBuilder
        )
    }

    private func build(
        sectionSpans: [ExactBSplineCurveSpan],
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
            tolerance: context.tolerance
        ).request(
            profileSpans: sectionSpans,
            pathSpans: pathSpans,
            profilePlane: profilePlane,
            sectionIsClosed: sectionIsClosed,
            resultKind: resultKind,
            endTransform: endTransform,
            featureID: featureID
        )
        let sewn = try sewer.sew(
            request,
            tolerance: context.tolerance
        )
        let combined = try BRepModelCombiner().combined([
            context.brep,
            sewn.brep,
        ])
        let subshapes = try semanticSubshapes(
            sewn: sewn,
            profileSpanCount: sectionSpans.count,
            pathSpanCount: pathSpans.count,
            includesCaps: resultKind == .solid
        )
        return EvaluationResult(
            brep: combined,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: subshapes
            )
        )
    }

    private func semanticSubshapes(
        sewn: BRepSewingResult,
        profileSpanCount: Int,
        pathSpanCount: Int,
        includesCaps: Bool
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [
            subshapeID(role: .body, ordinal: 0): .body(sewn.bodyID),
        ]
        if includesCaps {
            result[subshapeID(role: .startFace, ordinal: 0)] = try reference(
                .face("sweep:cap:start"),
                in: sewn
            )
            result[subshapeID(role: .endFace, ordinal: 0)] = try reference(
                .face("sweep:cap:end"),
                in: sewn
            )
        }
        var sideOrdinal = 0
        for pathIndex in 0..<pathSpanCount {
            for profileIndex in 0..<profileSpanCount {
                result[subshapeID(
                    role: .sideFace,
                    ordinal: sideOrdinal
                )] = try reference(
                    .face("sweep:side:path:\(pathIndex):profile:\(profileIndex)"),
                    in: sewn
                )
                sideOrdinal += 1
            }
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
