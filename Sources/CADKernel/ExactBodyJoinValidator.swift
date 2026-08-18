import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Validates the semantic precondition of Join: every material region remains
/// disconnected from every other material region.
package struct ExactBodyJoinValidator: BodyJoinValidating {
    private let pointClassifier: any SolidPointClassifying

    package init(
        pointClassifier: any SolidPointClassifying = DefaultBRepSolidPointClassifier()
    ) {
        self.pointClassifier = pointClassifier
    }

    package func validateDisjointMaterial(
        bodyIDs: [BodyID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard bodyIDs.count >= 2, Set(bodyIDs).count == bodyIDs.count else {
            throw joinError(
                tolerance: tolerance,
                "Join requires at least two distinct solid bodies."
            )
        }
        for bodyID in bodyIDs {
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
        for firstIndex in bodyIDs.indices {
            for secondIndex in bodyIDs.indices where secondIndex > firstIndex {
                try validatePair(
                    bodyIDs[firstIndex],
                    bodyIDs[secondIndex],
                    in: model,
                    tolerance: tolerance
                )
            }
        }
    }

    private func validatePair(
        _ firstBodyID: BodyID,
        _ secondBodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        let boundsBuilder = BRepBodyBoundingBoxBuilder()
        let firstBounds = try boundsBuilder.bounds(
            for: firstBodyID,
            in: model,
            tolerance: tolerance
        )
        let secondBounds = try boundsBuilder.bounds(
            for: secondBodyID,
            in: model,
            tolerance: tolerance
        )
        guard firstBounds.intersects(secondBounds, tolerance: tolerance.distance) else {
            return
        }

        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let intersectionGraph = try pipeline.completeIntersectionGraph(
            targetBodyIDs: [firstBodyID],
            toolBodyID: secondBodyID,
            operation: .union,
            model: model,
            tolerance: tolerance
        )
        let splitGraph = try pipeline.uvSplitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance
        )
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
            tolerance: tolerance
        )
        try validateVerticesOutside(
            of: secondBodyID,
            otherBodyID: firstBodyID,
            model: model,
            tolerance: tolerance
        )
    }

    private func validateVerticesOutside(
        of sourceBodyID: BodyID,
        otherBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        let points = try boundaryPoints(
            of: sourceBodyID,
            in: model,
            tolerance: tolerance
        )
        for point in points {
            let classification = try pointClassifier.classify(
                point,
                in: otherBodyID,
                model: model,
                tolerance: tolerance
            )
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
    ) throws -> [Point3D] {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Join validation references a missing body.")
        }
        var vertexIDs = Set<VertexID>()
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Join validation references a missing shell.")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Join validation references a missing face.")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Join validation references a missing loop.")
                    }
                    for coedge in loop.coedges {
                        guard let edge = model.edges[coedge.edgeID] else {
                            throw TopologyError.missingReference("Join validation references a missing edge.")
                        }
                        vertexIDs.insert(edge.startVertexID)
                        vertexIDs.insert(edge.endVertexID)
                    }
                }
            }
        }
        let points = try vertexIDs.sorted().map { vertexID -> Point3D in
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
