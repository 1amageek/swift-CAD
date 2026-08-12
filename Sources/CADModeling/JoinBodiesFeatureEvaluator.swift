import CADCore
import CADIR
import CADTopology

public struct JoinBodiesFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    public init() {}

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .joinBodies(join) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Join bodies evaluator requires a joinBodies feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try join.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let bodyIDs = try join.targets.map { target in
            try context.bodyID(generatedBy: target.featureID)
        }
        let bodies = try bodyIDs.map { bodyID -> Body in
            guard let body = context.brep.bodies[bodyID] else {
                throw TopologyError.missingReference("Join bodies source body is missing.")
            }
            guard body.kind == .solid else {
                throw error(
                    .invalidInput,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    "Join bodies requires every source body to be a solid."
                )
            }
            return body
        }
        try validateSeparatedBodies(bodyIDs, featureID: feature.id, context: context)

        let joinedBodyID = BodyID()
        var replacement = try BRepBodySubmodelExtractor().extract(
            bodyIDs: Set(bodyIDs),
            from: context.brep
        )
        for bodyID in bodyIDs {
            replacement.bodies.removeValue(forKey: bodyID)
        }
        replacement.bodies[joinedBodyID] = Body(
            id: joinedBodyID,
            shellIDs: bodies.flatMap(\.shellIDs),
            kind: .solid
        )
        let model = try BRepBodyModelReplacer().replacing(
            bodyIDs: Set(bodyIDs),
            with: replacement,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)

        let joinedSubshapeID = SubshapeID(
            featureID: feature.id,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        let removedSubshapeIDs = Set(bodyIDs.flatMap { bodyID in
            context.subshapeIDs(for: .body(bodyID))
        })
        return EvaluationResult(
            brep: model,
            subshapes: [joinedSubshapeID: .body(joinedBodyID)],
            removedSubshapeIDs: removedSubshapeIDs,
            lineage: [
                joinedSubshapeID: TopologyLineage(
                    output: joinedSubshapeID,
                    parents: Array(removedSubshapeIDs),
                    relation: .merged
                ),
            ]
        )
    }

    private func validateSeparatedBodies(
        _ bodyIDs: [BodyID],
        featureID: FeatureID,
        context: EvaluationContext
    ) throws {
        let bounds = try bodyIDs.map { bodyID in
            Bounds(points: try points(bodyID: bodyID, model: context.brep))
        }
        for firstIndex in bounds.indices {
            for secondIndex in bounds.indices where secondIndex > firstIndex {
                guard bounds[firstIndex].isSeparated(
                    from: bounds[secondIndex],
                    tolerance: context.tolerance.distance
                ) else {
                    throw error(
                        .unsupportedCapability,
                        featureID: featureID,
                        tolerance: context.tolerance,
                        "Join bodies currently requires source bodies with separated bounding boxes."
                    )
                }
            }
        }
    }

    private func points(bodyID: BodyID, model: BRepModel) throws -> [Point3D] {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Join bodies source body is missing.")
        }
        var points: [Point3D] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Join bodies source shell is missing.")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Join bodies source face is missing.")
                }
                for loopID in face.loops {
                    points.append(contentsOf: try model.orderedPoints(for: loopID))
                }
            }
        }
        guard points.isEmpty == false else {
            throw TopologyError.unreferencedTopology("Join bodies source body has no vertices.")
        }
        return points
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }

    private struct Bounds {
        let minimum: Point3D
        let maximum: Point3D

        init(points: [Point3D]) {
            let first = points[0]
            let values = points.dropFirst().reduce(
                into: (minimum: first, maximum: first)
            ) { result, point in
                result.minimum = Point3D(
                    x: min(result.minimum.x, point.x),
                    y: min(result.minimum.y, point.y),
                    z: min(result.minimum.z, point.z)
                )
                result.maximum = Point3D(
                    x: max(result.maximum.x, point.x),
                    y: max(result.maximum.y, point.y),
                    z: max(result.maximum.z, point.z)
                )
            }
            minimum = values.minimum
            maximum = values.maximum
        }

        func isSeparated(from other: Bounds, tolerance: Double) -> Bool {
            maximum.x < other.minimum.x - tolerance
                || other.maximum.x < minimum.x - tolerance
                || maximum.y < other.minimum.y - tolerance
                || other.maximum.y < minimum.y - tolerance
                || maximum.z < other.minimum.z - tolerance
                || other.maximum.z < minimum.z - tolerance
        }
    }
}
