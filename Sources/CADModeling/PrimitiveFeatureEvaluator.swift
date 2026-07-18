import CADCore
import CADIR

public struct PrimitiveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: DefaultBRepSewer

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
        sewer = DefaultBRepSewer()
    }

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
        try context.tolerance.validate()
        guard case let .primitive(primitive) = feature.operation else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PrimitiveFeatureEvaluator only supports primitive features."
            )
        }
        try primitive.validate(tolerance: context.tolerance)
        let request = try request(
            for: primitive.definition,
            featureID: feature.id,
            context: context
        )
        let sewn = try sewer.sew(request, tolerance: context.tolerance)
        let combined = try BRepModelCombiner().combined([context.brep, sewn.brep])
        return try ValidatedFeatureEvaluation(
            validating: EvaluationResult(
                brep: combined,
                subshapes: sewn.subshapes,
                lineage: sewn.lineage
            ),
            tolerance: context.tolerance
        )
    }

    private func request(
        for definition: PrimitiveDefinition,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let builder = PrimitiveBRepRequestBuilder(tolerance: context.tolerance)
        switch definition {
        case let .box(primitive):
            return try builder.box(
                primitive,
                width: length(primitive.width, name: "primitive.box.width", context: context),
                depth: length(primitive.depth, name: "primitive.box.depth", context: context),
                height: length(primitive.height, name: "primitive.box.height", context: context),
                featureID: featureID
            )
        case let .cylinder(primitive):
            return try builder.cylinder(
                primitive,
                radius: length(primitive.radius, name: "primitive.cylinder.radius", context: context),
                height: length(primitive.height, name: "primitive.cylinder.height", context: context),
                featureID: featureID
            )
        case let .cone(primitive):
            return try builder.cone(
                primitive,
                baseRadius: length(primitive.baseRadius, name: "primitive.cone.baseRadius", context: context),
                height: length(primitive.height, name: "primitive.cone.height", context: context),
                featureID: featureID
            )
        case let .sphere(primitive):
            return try builder.sphere(
                primitive,
                radius: length(primitive.radius, name: "primitive.sphere.radius", context: context),
                featureID: featureID
            )
        case let .torus(primitive):
            let majorRadius = try length(
                primitive.majorRadius,
                name: "primitive.torus.majorRadius",
                context: context
            )
            let minorRadius = try length(
                primitive.minorRadius,
                name: "primitive.torus.minorRadius",
                context: context
            )
            guard majorRadius > minorRadius + context.tolerance.distance else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: majorRadius - minorRadius,
                    tolerance: context.tolerance,
                    message: "Primitive torus major radius must exceed its minor radius."
                )
            }
            return try builder.torus(
                primitive,
                majorRadius: majorRadius,
                minorRadius: minorRadius,
                featureID: featureID
            )
        }
    }

    private func length(
        _ expression: CADExpression,
        name: String,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(
            expression,
            parameters: context.parameters,
            variables: [:]
        )
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: name,
                expected: .length,
                actual: quantity.kind
            )
        }
        guard quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: quantity.value,
                tolerance: context.tolerance,
                message: "\(name) must resolve to a positive length above modeling tolerance."
            )
        }
        return quantity.value
    }
}
