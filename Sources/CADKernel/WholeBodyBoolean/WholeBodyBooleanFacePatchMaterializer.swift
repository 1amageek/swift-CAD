import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Materializes a Boolean whose operands do not cross: each operand lies wholly inside or outside
/// the other's material (or they coincide), so the region rule keeps, turns or drops each body
/// whole.
struct WholeBodyBooleanFacePatchMaterializer {
    /// Where a target's boundary lies in the tool's material and the tool's boundary in the
    /// target's: each is what the region rule takes for that body's faces.
    private struct Relation: Equatable {
        let target: SolidPointClassification
        let tool: SolidPointClassification

        var isCoincident: Bool { target == .boundary && tool == .boundary }
        var isDisjoint: Bool { target == .outside && tool == .outside }
    }

    func materialize(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        hasBoundaryContact: Bool,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        guard !targetBodyIDs.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Whole-body Boolean materialization requires at least one target."
            )
        }
        let classificationSessions = try SolidPointClassificationSessionSet(
            bodyIDs: targetBodyIDs + [toolBodyID],
            pointClassifier: operands.pointClassifier,
            model: model,
            tolerance: tolerance
        )
        let relations = try targetBodyIDs.map { targetBodyID in
            try relation(
                targetBodyID: targetBodyID,
                toolBodyID: toolBodyID,
                model: model,
                classificationSessions: classificationSessions,
                operands: operands,
                tolerance: tolerance
            )
        }
        switch operation {
        case .union:
            if hasBoundaryContact,
               relations.allSatisfy(\.isDisjoint) {
                throw KernelError(
                    phase: .topology,
                    code: .nonManifoldResult,
                    tolerance: tolerance,
                    message: "Union of externally contacting solids would create a non-manifold result."
                )
            }
        case .difference:
            if hasBoundaryContact,
               relations.contains(where: { $0.tool == .inside }) {
                throw KernelError(
                    phase: .topology,
                    code: .nonManifoldResult,
                    tolerance: tolerance,
                    message: "A contained tool touching its target boundary would create a non-manifold cavity."
                )
            }
        case .intersect, .slice:
            break
        case .region:
            throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                message: "A region is built from the cell complex of its operands, not a whole-body Boolean.")
        }
        let selected: [(bodyID: BodyID, reversedShells: Bool)]
        var coincidentRepresentative: [BRepSewingShell]?
        if relations.contains(where: \.isCoincident) {
            guard operands.solidities.areVolumes else {
                throw KernelError(
                    phase: .classification,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Operands that coincide whole are combined only as solid volumes."
                )
            }
            // A boundary-only vertex relation is a candidate. Whole original face/trim
            // coverage below must establish coincidence before selecting a representative.
            coincidentRepresentative = try coincidentBoundaries(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
                relations: relations, model: model, sourceSubshapes: sourceSubshapes,
                tolerance: tolerance)
            // Union/intersection retain one coincident representative. Difference removes
            // coincident targets and may still hollow another target around the tool.
            let uncovered = zip(targetBodyIDs, relations).compactMap { bodyID, relation in
                relation.target == .inside || relation.isCoincident ? nil : (bodyID, false)
            }
            switch operation {
            case .union:
                selected = uncovered + (relations.contains(where: { $0.tool == .inside })
                    ? [] : [(toolBodyID, false)])
            case .difference:
                selected = uncovered + (relations.contains(where: { $0.tool == .inside }) ? [(toolBodyID, true)] : [])
            case .intersect:
                selected = [(toolBodyID, false)]
            case .slice:
                selected = targetBodyIDs.map { ($0, false) }
            case .region:
                selected = []
            }
        } else {
            // Each body lies wholly on one side of the other's material: the rule decides it
            // like any face region there. The tool lies in the targets' material when it lies in
            // any target's.
            func selection(_ bodyID: BodyID, _ classification: SolidPointClassification, isToolFace: Bool) -> (BodyID, Bool)? {
                switch operands.rule.action(operation: operation, classification: classification, isToolFace: isToolFace) {
                case .keep: (bodyID, false)
                case .keepReversed: (bodyID, true)
                case .discard, .partitionBoundary: nil
                }
            }
            let targets = zip(targetBodyIDs, relations).compactMap { bodyID, relation in
                selection(bodyID, relation.target, isToolFace: false)
            }
            let tool = selection(toolBodyID, relations.contains(where: { $0.tool == .inside }) ? .inside : .outside, isToolFace: true)
            selected = operation == .slice ? targetBodyIDs.map { ($0, false) } : targets + (tool.map { [$0] } ?? [])
        }
        guard !selected.isEmpty else {
            throw KernelError(
                phase: .classification,
                code: .emptyResult,
                tolerance: tolerance,
                message: "Whole-body Boolean classification proved that the result is empty."
            )
        }

        var shells: [BRepSewingShell] = []
        for (bodyIndex, item) in selected.enumerated() {
            let originalShells: [BRepSewingShell]
            if item.bodyID == toolBodyID, !item.reversedShells, let coincidentRepresentative {
                originalShells = coincidentRepresentative
            } else {
                originalShells = try extractedShells(bodyID: item.bodyID,
                    stablePrefix: "whole-body:\(bodyIndex)", reversed: item.reversedShells,
                    model: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance)
            }
            shells.append(contentsOf: originalShells)
        }
        let keptTool = selected.contains { $0.bodyID == toolBodyID && !$0.reversedShells }
        let parentBodyIDs = sourceSubshapes.compactMap { subshapeID, reference -> SubshapeID? in
            if selected.contains(where: { reference == .body($0.bodyID) }) { return subshapeID }
            if keptTool, zip(targetBodyIDs, relations).contains(where: {
                $0.1.isCoincident && reference == .body($0.0)
            }) { return subshapeID }
            return nil
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: operands.resultBodyKind,
            shells: shells,
            bodyParentSubshapeIDs: parentBodyIDs
        )
        try request.validate(tolerance: tolerance)
        return request
    }

    private func coincidentBoundaries(targetBodyIDs: [BodyID], toolBodyID: BodyID,
        relations: [Relation], model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference], tolerance: ModelingTolerance) throws -> [BRepSewingShell] {
        var retained = try extractedShells(bodyID: toolBodyID,
            stablePrefix: "whole-body:coincident:0", reversed: false, model: model,
            sourceSubshapes: sourceSubshapes, tolerance: tolerance)
        for (index, bodyID) in targetBodyIDs.enumerated() where relations[index].isCoincident {
            try CurrentTaskCancellationChecker().checkCancellation()
            let originals = retained.flatMap(\.patches)
            let targetPatches = try extractedShells(bodyID: bodyID,
                stablePrefix: "whole-body:coincident:1:\(index)", reversed: false, model: model,
                sourceSubshapes: sourceSubshapes, tolerance: tolerance).flatMap(\.patches)
            let merged = try CoincidentFacePatchMerger().merge(originals + targetPatches,
                tolerance: tolerance)
            guard originals.count == targetPatches.count, merged.count == originals.count else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): The general Boolean whole-body path
                // requires shared arrangement for differently partitioned coincident faces.
                // Vertex-boundary agreement alone cannot authorize a coincident result.
                // Complete all original trim regions before admitting this source family.
                throw KernelError(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Whole-body coincidence needs complete original face-region correspondence.")
            }
            let mergedByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.stableID, $0) })
            retained = try retained.map { shell in
                let patches = try shell.patches.map { patch in
                    guard let kept = mergedByID[patch.stableID] else {
                        throw missingReference("Coincident source ancestry lost the original representative.",
                            tolerance: tolerance)
                    }
                    return kept
                }
                return BRepSewingShell(stableID: shell.stableID, patches: patches,
                    orientation: shell.orientation)
            }
        }
        return retained
    }

    private func relation(
        targetBodyID: BodyID,
        toolBodyID: BodyID,
        model: BRepModel,
        classificationSessions: SolidPointClassificationSessionSet,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> Relation {
        let relation = Relation(
            target: try classification(
                of: targetBodyID,
                relativeTo: toolBodyID,
                model: model,
                classificationSessions: classificationSessions,
                tolerance: tolerance
            ),
            tool: try classification(
                of: toolBodyID,
                relativeTo: targetBodyID,
                model: model,
                classificationSessions: classificationSessions,
                tolerance: tolerance
            )
        )
        // A boundary on the other's boundary without the other on it (or the reverse) needs a
        // partition, never a whole-body decision. Two volumes cannot each hold the other's
        // boundary, but a volume and a complement or a sheet's side can: that is how a body inside
        // another lies in the other's outside.
        let oneSidedBoundary = (relation.target == .boundary) != (relation.tool == .boundary)
        let mutualInsideVolumes = relation.target == .inside && relation.tool == .inside && operands.solidities.areVolumes
        guard !oneSidedBoundary, !mutualInsideVolumes else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Whole-body Boolean containment produced an inconsistent boundary relation."
            )
        }
        return relation
    }

    private func classification(
        of bodyID: BodyID,
        relativeTo oppositeBodyID: BodyID,
        model: BRepModel,
        classificationSessions: SolidPointClassificationSessionSet,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        let points = try boundaryVertices(
            of: bodyID,
            model: model,
            tolerance: tolerance
        )
        var nonBoundary: SolidPointClassification?
        var boundaryCount = 0
        for point in points {
            let value = try classificationSessions.classify(
                point,
                in: oppositeBodyID
            )
            if value == .boundary {
                boundaryCount += 1
                continue
            }
            if let nonBoundary, nonBoundary != value {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "A solid boundary contains both inside and outside samples without a partitioning intersection."
                )
            }
            nonBoundary = value
        }
        if let nonBoundary { return nonBoundary }
        guard boundaryCount == points.count else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Whole-body Boolean classification did not produce a usable boundary sample."
            )
        }
        return .boundary
    }

    private func boundaryVertices(
        of bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard let body = model.bodies[bodyID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Whole-body Boolean classification references a missing body."
            )
        }
        var points: [Point3D] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw missingReference("Whole-body Boolean references a missing shell.", tolerance: tolerance)
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw missingReference("Whole-body Boolean references a missing face.", tolerance: tolerance)
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw missingReference("Whole-body Boolean references a missing loop.", tolerance: tolerance)
                    }
                    for coedge in loop.coedges {
                        guard let edge = model.edges[coedge.edgeID],
                              let point = model.vertices[edge.startVertexID]?.point else {
                            throw missingReference("Whole-body Boolean references missing edge topology.", tolerance: tolerance)
                        }
                        if !points.contains(where: {
                            $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
                        }) {
                            points.append(point)
                        }
                    }
                }
            }
        }
        guard !points.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Whole-body Boolean classification requires bounded vertices."
            )
        }
        return points
    }

    private func extractedShells(
        bodyID: BodyID,
        stablePrefix: String,
        reversed: Bool,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingShell] {
        guard let body = model.bodies[bodyID] else {
            throw missingReference("Whole-body Boolean extraction references a missing body.", tolerance: tolerance)
        }
        return try body.shellIDs.enumerated().map { shellIndex, shellID in
            guard let shell = model.shells[shellID] else {
                throw missingReference("Whole-body Boolean extraction references a missing shell.", tolerance: tolerance)
            }
            let shellStableID = "\(stablePrefix):shell:\(shellIndex)"
            let patches = try shell.faceIDs.enumerated().map { faceIndex, faceID in
                try SourceBRepFacePatchBuilder().build(
                    faceID: faceID,
                    stableID: "\(shellStableID):face:\(faceIndex)",
                    from: model,
                    sourceSubshapes: sourceSubshapes,
                    tolerance: tolerance
                ).patch
            }
            let orientation: Orientation
            if reversed {
                orientation = shell.orientation == .forward ? .reversed : .forward
            } else {
                orientation = shell.orientation
            }
            return BRepSewingShell(
                stableID: shellStableID,
                patches: patches,
                orientation: orientation
            )
        }
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }
}
