import CADCore
import CADIR

package struct SweepOptionValues: Equatable, Sendable {
    package var twistAngle: Double
    package var endScale: Double
    package var distanceFraction: Double
    package var approximationTolerance: Double? = nil
    package var twistPositions: [Double] = [0, 1]
    package var twistAngles: [Double] = []
}

package struct SweepOptionValueResolver: Sendable {
    private let resolver: any ParameterResolving

    package init(resolver: any ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    package func values(
        for sweep: SweepFeature,
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> SweepOptionValues {
        try sweep.options.validate()
        guard sweep.sections.count == 1 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Sweep evaluation currently supports exactly one section."
            )
        }
        let twistAngle = try resolvedAngle(
            sweep.options.twistAngle,
            operation: "sweep.twistAngle",
            parameters: parameters
        )
        guard twistAngle.isFinite else {
            throw FeatureEvaluationError.invalidGraph("Sweep twist angle must be finite.")
        }

        let endScale = try resolvedScalar(
            sweep.options.endScale,
            operation: "sweep.endScale",
            parameters: parameters
        )
        guard endScale.isFinite,
              endScale > tolerance.relative else {
            throw KernelError(
                phase: .validation,
                code: .sweepScaleCollapse,
                residual: endScale,
                tolerance: tolerance,
                message: "Sweep end-scale collapses the section before valid exact topology can be produced."
            )
        }

        let distanceFraction = try resolvedScalar(
            sweep.options.distanceFraction,
            operation: "sweep.distanceFraction",
            parameters: parameters
        )
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }
        let allowance: Double?
        if let expression = sweep.options.approximationTolerance {
            let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
            guard quantity.kind == .length, quantity.value.isFinite, quantity.value > 0 else {
                throw FeatureEvaluationError.invalidGraph("Sweep approximation tolerance must be a finite positive length.")
            }
            allowance = quantity.value
        } else {
            allowance = nil
        }
        let angles = try sweep.options.twistLaw?.map {
            try resolvedAngle($0.angle, operation: "sweep.twistLaw.angle", parameters: parameters)
        } ?? [0, twistAngle]
        guard angles.allSatisfy(\.isFinite), angles.first == 0, angles.last == twistAngle else {
            throw FeatureEvaluationError.invalidGraph("Sweep twist law must start at zero and end at twistAngle.")
        }
        return SweepOptionValues(
            twistAngle: twistAngle,
            endScale: endScale,
            distanceFraction: distanceFraction,
            approximationTolerance: allowance,
            twistPositions: sweep.options.twistLaw?.map(\.position) ?? [0, 1],
            twistAngles: angles
        )
    }

    private func resolvedAngle(
        _ expression: CADExpression,
        operation: String,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: quantity.kind)
        }
        return quantity.value
    }

    private func resolvedScalar(
        _ expression: CADExpression,
        operation: String,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard quantity.kind == .scalar else {
            throw UnitError.expectedQuantity(operation: operation, expected: .scalar, actual: quantity.kind)
        }
        return quantity.value
    }
}
