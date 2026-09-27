import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Moves faces, edges and vertices of one body together by one translation, rotation or scale.
///
/// Every vertex the targets bound moves once by the motion, so targets that share vertices stay
/// joined, and `LocalVertexDisplacementRebuilder` re-solves only the faces around them. A face
/// the targets carry whole keeps its outward side as the motion turns it.
public struct TopologyTransformFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateTransform(feature: feature, context: context)
        }
    }

    private func evaluateTransform(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .topologyTransform(transform) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Topology transform evaluator requires a topologyTransform feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try transform.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let bodyID = try context.bodyID(generatedBy: transform.target.featureID)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let motion = try affineMotion(transform.motion, featureID: feature.id, context: context)

        var vertexIDs = Set<VertexID>()
        for stableReference in transform.subshapes {
            let reference = try subshapeResolver.topologyReference(
                for: stableReference, model: context.brep, subshapes: context.subshapes,
                lineage: context.lineage, tolerance: context.tolerance
            )
            guard bodyScope.references.contains(reference) else {
                throw failure(.missingReference, feature.id, context.tolerance,
                              "A topology transform target does not belong to the target body.")
            }
            switch reference {
            case let .vertex(id):
                vertexIDs.insert(id)
            case let .edge(id):
                guard let edge = context.brep.edges[id] else {
                    throw TopologyError.missingReference("A topology transform edge is missing.")
                }
                vertexIDs.formUnion([edge.startVertexID, edge.endVertexID])
            case let .face(id):
                guard let face = context.brep.faces[id] else {
                    throw TopologyError.missingReference("A topology transform face is missing.")
                }
                for loopID in face.loops { vertexIDs.formUnion(try context.brep.orderedVertexIDs(for: loopID)) }
            default:
                throw failure(.invalidInput, feature.id, context.tolerance,
                              "A topology transform moves faces, edges and vertices only.")
            }
        }
        var displacements: [VertexID: Vector3D] = [:]
        for vertexID in vertexIDs {
            guard let point = context.brep.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("A topology transform vertex is missing.")
            }
            displacements[vertexID] = motion.applying(to: point) - point
        }
        guard displacements.values.contains(where: { $0.length > context.tolerance.distance }) else {
            throw failure(.invalidInput, feature.id, context.tolerance, "A topology transform moves nothing.")
        }

        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        var model = context.brep
        try LocalVertexDisplacementRebuilder().displace(
            displacements, motion: motion, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: context.tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    /// The motion as an affine map of the body's coordinates.
    private func affineMotion(_ motion: TopologyMotion, featureID: FeatureID, context: EvaluationContext) throws -> AffineTransform3D {
        func value(_ expression: CADExpression, _ kind: QuantityKind, _ name: String) throws -> Double {
            let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
            guard quantity.kind == kind else {
                throw UnitError.expectedQuantity(operation: "topologyTransform.\(name)", expected: kind, actual: quantity.kind)
            }
            guard quantity.value.isFinite else {
                throw failure(.invalidInput, featureID, context.tolerance, "A topology transform value must be finite.")
            }
            return quantity.value
        }
        switch motion {
        case let .translation(vector):
            let direction = try vector.direction.normalized(tolerance: context.tolerance.distance)
            let offset = direction * (try value(vector.distance, .length, "distance"))
            return try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: offset)
        case let .rotation(rotation):
            let rigid = try RigidTransform3D.rotated(
                around: rotation.origin, direction: rotation.axis,
                angle: try value(rotation.angle, .angle, "angle"), tolerance: context.tolerance
            )
            return try AffineTransform3D(
                basisX: rigid.basisX, basisY: rigid.basisY, basisZ: rigid.basisZ, translation: rigid.translation
            )
        case let .scale(scale):
            let factors = try scale.factors.map { try value($0, .scalar, "factor") }
            guard factors.allSatisfy({ $0 > context.tolerance.relative }) else {
                throw failure(.invalidInput, featureID, context.tolerance, "A topology scale needs positive factors.")
            }
            let x = try scale.xAxis.normalized(tolerance: context.tolerance.distance)
            let y = try scale.yAxis.normalized(tolerance: context.tolerance.distance)
            let axes = [x, y, x.cross(y)]
            // L = Σ fᵢ eᵢ eᵢᵀ, applied about the origin: p' = o + L (p − o).
            func column(_ unit: Vector3D) -> Vector3D {
                zip(axes, factors).reduce(Vector3D.zero) { $0 + $1.0 * ($1.1 * $1.0.dot(unit)) }
            }
            let linear = (column(.unitX), column(.unitY), column(.unitZ))
            let origin = scale.origin - .origin
            let image = linear.0 * origin.x + linear.1 * origin.y + linear.2 * origin.z
            return try AffineTransform3D(basisX: linear.0, basisY: linear.1, basisZ: linear.2, translation: origin - image)
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID,
                    tolerance: tolerance, message: message)
    }
}
