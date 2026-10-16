import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Validates the semantic precondition of Join: every material region remains
/// disconnected from every other material region.
package struct ExactBodyJoinValidator: BodyJoinValidating {
    private struct BoundedBody: Sendable {
        let ordinal: Int
        let bodyID: BodyID
        let bounds: BoundingBox3D
    }

    private let pointClassifier: any SolidPointClassifying

    package init(
        pointClassifier: any SolidPointClassifying = DefaultBRepSolidPointClassifier()
    ) {
        self.pointClassifier = pointClassifier
    }

    package func validateDisjointMaterial(bodyIDs: [BodyID], in model: BRepModel,
        tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validateDisjointMaterial(bodyIDs: bodyIDs, in: model, tolerance: tolerance, using: &execution)
    }

    package func validateDisjointMaterial(
        bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws {
        let interactions = try materialInteractions(
            bodyIDs: bodyIDs,
            in: model,
            tolerance: tolerance, using: &execution
        )
        guard interactions.isEmpty else {
            throw joinError(
                tolerance: tolerance,
                "Join requires pairwise disjoint material regions and boundaries."
            )
        }
    }

    package func materialInteractions(bodyIDs: [BodyID], in model: BRepModel,
        tolerance: ModelingTolerance) throws -> [BodyMaterialInteraction] {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try materialInteractions(bodyIDs: bodyIDs, in: model, tolerance: tolerance, using: &execution)
    }

    package func materialInteractions(
        bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [BodyMaterialInteraction] {
        try tolerance.validate()
        guard bodyIDs.count >= 2, try OriginalParameterQueryStorage.set(bodyIDs, using: &execution).count == bodyIDs.count else {
            throw joinError(
                tolerance: tolerance,
                "Join requires at least two distinct solid bodies."
            )
        }
        for bodyID in bodyIDs {
            try execution.consumeWork(1)
            guard let body = model.bodies[bodyID] else {
                throw TopologyError.missingReference("Join validation references a missing body.")
            }
            guard body.kind == .solid else {
                throw joinError(
                    tolerance: tolerance,
                    "Join validation requires every source body to be a solid."
                )
            }
        }
        let boundedBodies = try boundedBodies(
            bodyIDs,
            in: model,
            tolerance: tolerance
        , using: &execution)
        let candidates = try candidatePairs(
            in: boundedBodies,
            tolerance: tolerance
        , using: &execution)
        guard candidates.isEmpty == false else {
            return []
        }
        let classificationSessions = try SolidPointClassificationSessionSet(
            bodyIDs: bodyIDs,
            pointClassifier: pointClassifier,
            model: model,
            tolerance: tolerance
        , using: &execution)
        var interactions: [BodyMaterialInteraction] = []
        for (first, second) in candidates {
            try execution.consumeWork(1)
            do {
                try validatePair(
                    first.bodyID,
                    second.bodyID,
                    in: model,
                    classificationSessions: classificationSessions,
                    tolerance: tolerance
                , using: &execution)
            } catch let error as KernelError where error.code == .invalidInput {
                try OriginalParameterQueryStorage.append(BodyMaterialInteraction(
                    firstBodyID: first.bodyID,
                    secondBodyID: second.bodyID
                ), to: &interactions, using: &execution)
            }
        }
        return interactions
    }

    private func boundedBodies(
        _ bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BoundedBody] {
        let boundsBuilder = BRepBodyBoundingBoxBuilder()
        return try OriginalParameterQueryStorage.map(bodyIDs.enumerated(), using: &execution) { item, execution in
            let (ordinal, bodyID) = item
            return BoundedBody(
                ordinal: ordinal,
                bodyID: bodyID,
                bounds: try boundsBuilder.bounds(
                    for: bodyID,
                    in: model,
                    tolerance: tolerance
                , using: &execution)
            )
        }
    }

    private func candidatePairs(
        in boundedBodies: [BoundedBody],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [(BoundedBody, BoundedBody)] {
        let sorted = try OriginalParameterQueryStorage.ordered(boundedBodies, using: &execution, less: { lhs, rhs in
            if lhs.bounds.minimum.x != rhs.bounds.minimum.x {
                return lhs.bounds.minimum.x < rhs.bounds.minimum.x
            }
            return lhs.ordinal < rhs.ordinal
        })
        var result: [(BoundedBody, BoundedBody)] = []
        for firstIndex in sorted.indices {
            try execution.consumeWork(1)
            let first = sorted[firstIndex]
            for second in sorted[sorted.index(after: firstIndex)...] {
            try execution.consumeWork(1)
                if second.bounds.minimum.x - tolerance.distance
                    > first.bounds.maximum.x {
                    break
                }
                if first.bounds.intersects(
                    second.bounds,
                    tolerance: tolerance.distance
                ) {
                    try OriginalParameterQueryStorage.append((first, second), to: &result, using: &execution)
                }
            }
        }
        return result
    }

    private func validatePair(
        _ firstBodyID: BodyID,
        _ secondBodyID: BodyID,
        in model: BRepModel,
        classificationSessions: SolidPointClassificationSessionSet,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<BodyID>.stride)
        let intersectionGraph = try pipeline.completeIntersectionGraph(
            targetBodyIDs: [firstBodyID],
            toolBodyID: secondBodyID,
            operation: .union,
            model: model,
            tolerance: tolerance
        , using: &execution)
        let splitGraph = try pipeline.uvSplitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance
        , using: &execution)
        // Raw boundary contacts are intersections with the other face's
        // supporting surface and may lie outside that face's trim. The split
        // graph is the certified, trim-aware boundary-intersection result.
        guard splitGraph.splits.isEmpty else {
            throw joinError(
                tolerance: tolerance,
                "Join requires disjoint bodies; two source boundaries intersect or touch."
            )
        }

        try validateVerticesOutside(
            of: firstBodyID,
            otherBodyID: secondBodyID,
            model: model,
            classificationSessions: classificationSessions,
            tolerance: tolerance
        , using: &execution)
        try validateVerticesOutside(
            of: secondBodyID,
            otherBodyID: firstBodyID,
            model: model,
            classificationSessions: classificationSessions,
            tolerance: tolerance
        , using: &execution)
    }

    private func validateVerticesOutside(
        of sourceBodyID: BodyID,
        otherBodyID: BodyID,
        model: BRepModel,
        classificationSessions: SolidPointClassificationSessionSet,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        let points = try boundaryPoints(
            of: sourceBodyID,
            in: model,
            tolerance: tolerance
        , using: &execution)
        for point in points {
            try execution.consumeWork(1)
            let classification = try classificationSessions.classify(
                point,
                in: otherBodyID
            , using: &execution)
            guard classification == .outside else {
                throw joinError(
                    tolerance: tolerance,
                    "Join requires disjoint bodies; one source occupies or touches the other source's material region."
                )
            }
        }
    }

    private func boundaryPoints(
        of bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Join validation references a missing body.")
        }
        var vertexIDs = Set<VertexID>()
        for shellID in try body.originalShellIDs(using: &execution) {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Join validation references a missing shell.")
            }
            for faceID in shell.faceIDs {
            try execution.consumeWork(1)
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Join validation references a missing face.")
                }
                for loopID in face.loops {
            try execution.consumeWork(1)
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Join validation references a missing loop.")
                    }
                    for coedge in loop.coedges {
            try execution.consumeWork(1)
                        guard let edge = model.edges[coedge.edgeID] else {
                            throw TopologyError.missingReference("Join validation references a missing edge.")
                        }
                        try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &vertexIDs, using: &execution)
                        try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &vertexIDs, using: &execution)
                    }
                }
            }
        }
        let orderedVertices = try OriginalParameterQueryStorage.ordered(vertexIDs, using: &execution, less: <)
        let points = try OriginalParameterQueryStorage.map(orderedVertices, using: &execution) { vertexID, execution -> Point3D in
            guard let point = model.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Join validation references a missing vertex.")
            }
            return point
        }
        guard points.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Join validation requires bounded source topology."
            )
        }
        return points
    }

    private func joinError(
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .validation,
            code: .invalidInput,
            tolerance: tolerance,
            message: message
        )
    }
}
