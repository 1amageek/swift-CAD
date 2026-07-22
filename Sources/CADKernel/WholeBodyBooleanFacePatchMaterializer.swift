import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct WholeBodyBooleanFacePatchMaterializer {
    private enum Relation: Equatable {
        case disjoint
        case targetInsideTool
        case toolInsideTarget
        case coincident
    }

    private let pointClassifier: any SolidPointClassifying

    init(
        pointClassifier: any SolidPointClassifying = DefaultBRepSolidPointClassifier()
    ) {
        self.pointClassifier = pointClassifier
    }

    func materialize(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        hasBoundaryContact: Bool,
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
        let relations = try targetBodyIDs.map { targetBodyID in
            try relation(
                targetBodyID: targetBodyID,
                toolBodyID: toolBodyID,
                model: model,
                tolerance: tolerance
            )
        }
        let selected: [(bodyID: BodyID, reversedShells: Bool)]
        switch operation {
        case .union:
            if hasBoundaryContact,
               relations.allSatisfy({ $0 == .disjoint }) {
                throw KernelError(
                    phase: .topology,
                    code: .nonManifoldResult,
                    tolerance: tolerance,
                    message: "Union of externally contacting solids would create a non-manifold result."
                )
            }
            var bodies = zip(targetBodyIDs, relations).compactMap { bodyID, relation in
                relation == .targetInsideTool || relation == .coincident ? nil : bodyID
            }
            if relations.contains(.toolInsideTarget) == false,
               relations.contains(.coincident) == false {
                bodies.append(toolBodyID)
            }
            selected = bodies.map { ($0, false) }
        case .difference:
            if hasBoundaryContact,
               relations.contains(.toolInsideTarget) {
                throw KernelError(
                    phase: .topology,
                    code: .nonManifoldResult,
                    tolerance: tolerance,
                    message: "A contained tool touching its target boundary would create a non-manifold cavity."
                )
            }
            var bodies = zip(targetBodyIDs, relations).compactMap { bodyID, relation in
                relation == .targetInsideTool || relation == .coincident ? nil : bodyID
            }.map { ($0, false) }
            if relations.contains(.toolInsideTarget) {
                bodies.append((toolBodyID, true))
            }
            selected = bodies
        case .intersect:
            if relations.contains(.coincident) || relations.contains(.toolInsideTarget) {
                selected = [(toolBodyID, false)]
            } else {
                selected = zip(targetBodyIDs, relations).compactMap { bodyID, relation in
                    relation == .targetInsideTool ? (bodyID, false) : nil
                }
            }
        case .slice:
            selected = targetBodyIDs.map { ($0, false) }
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
            shells.append(contentsOf: try extractedShells(
                bodyID: item.bodyID,
                stablePrefix: "whole-body:\(bodyIndex)",
                reversed: item.reversedShells,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            ))
        }
        let parentBodyIDs = selected.flatMap { item in
            sourceSubshapes.compactMap { subshapeID, reference in
                reference == .body(item.bodyID) ? subshapeID : nil
            }
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: shells,
            bodyParentSubshapeIDs: parentBodyIDs
        )
        try request.validate(tolerance: tolerance)
        return request
    }

    private func relation(
        targetBodyID: BodyID,
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Relation {
        let target = try classification(
            of: targetBodyID,
            relativeTo: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let tool = try classification(
            of: toolBodyID,
            relativeTo: targetBodyID,
            model: model,
            tolerance: tolerance
        )
        switch (target, tool) {
        case (.inside, .outside):
            return .targetInsideTool
        case (.outside, .inside):
            return .toolInsideTarget
        case (.outside, .outside):
            return .disjoint
        case (.boundary, .boundary):
            return .coincident
        case (.inside, .inside),
             (.inside, .boundary),
             (.boundary, .inside),
             (.outside, .boundary),
             (.boundary, .outside):
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Whole-body Boolean containment produced an inconsistent boundary relation."
            )
        }
    }

    private func classification(
        of bodyID: BodyID,
        relativeTo oppositeBodyID: BodyID,
        model: BRepModel,
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
            let value = try pointClassifier.classify(
                point,
                in: oppositeBodyID,
                model: model,
                tolerance: tolerance
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
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Whole-body Boolean classification requires a solid body."
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
