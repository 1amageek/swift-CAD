import CADCore

extension Surface3D {
    package func validate(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, atSourceDepth sourceDepth: Int = 0, using execution: inout OriginalQueryExecution) throws {
        try validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth, using: &execution)
    }

    package func validateOriginalSource(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, atSourceDepth sourceDepth: Int = 0, using execution: inout OriginalQueryExecution) throws {
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ $0 >= 0 }) ?? true else {
            throw GeometryConversionError.resourceLimitExceeded("Original surface validation exhausted caller depth.")
        }
        let selectedMaximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: selectedMaximum) { execution in
        try execution.admitSourceDepth(sourceDepth)
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
        switch self {
        case .plane(let value): try value.validate(tolerance: tolerance)
        case .cylinder(let value): try value.validate(tolerance: tolerance)
        case .analytic(let value): try value.validate(tolerance: tolerance, using: &execution)
        case .bSpline(let value):
            try OriginalGeometrySourceValidation.validate(value, tolerance: tolerance,
                using: &execution)
        case .procedural(let original):
            try Self.validateProceduralOriginalSource(original, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth, using: &execution)
        }
        }
    }

    @inline(never)
    private static func validateProceduralOriginalSource(_ original: ProceduralSurface3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int?, atSourceDepth sourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws {
        func surface(_ source: Surface3D) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original surface descendant exhausted source depth.")
            }
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
        }
        func curve(_ source: Curve3D, at sourceTolerance: ModelingTolerance) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original surface rail exhausted source depth.")
            }
            try source.validateOriginalSource(tolerance: sourceTolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
        }
        switch original {
        case .offset(let value):
            guard value.distance.isFinite else { throw GeometryError.invalidDistance(value.distance) }
            try surface(value.source)
        case .originalAffineWord(let image):
            try image.validateOriginalRelation(tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        case .originalAngularTransport(let image):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original angular support exhausted source depth.")
            }

                try image.validateOriginalRelation(tolerance: tolerance, usage: &execution)

        case .originalImage(let image):
            try image.transform.validate()
            guard image.uOffset.isFinite, image.vOffset.isFinite else {
                throw GeometryConversionError.invalidInput("Original surface image offsets are not finite.")
            }
            try image.uParameterGain.validateOriginalSource(remainingSourceDepth: remainingSourceDepth, atSourceDepth: sourceDepth, using: &execution)
            try image.vParameterGain.validateOriginalSource(remainingSourceDepth: remainingSourceDepth, atSourceDepth: sourceDepth, using: &execution)
            try surface(image.source)
            try image.uDomain.validate(tolerance: tolerance); try image.vDomain.validate(tolerance: tolerance)
        case .ruled(let value):
            try curve(value.startBoundary, at: tolerance); try curve(value.endBoundary, at: tolerance)
            guard case .closed(let lower, let upper) = value.uDomain,
                  lower.isFinite, upper.isFinite,
                  upper - lower > max(tolerance.angle, tolerance.distance),
                  try value.startBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance),
                  try value.endBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance) else {
                throw GeometryConversionError.invalidInput("Original ruled support requires both complete finite rails.")
            }
        case .rollingBall(let value):
            try value.tolerance.validate()
            guard value.radius.isFinite, value.radius > value.tolerance.distance,
                  case .closed(0, 1) = value.centerSpine.parameterDomain,
                  case .closed(0, 1) = value.firstContact.parameterDomain,
                  case .closed(0, 1) = value.secondContact.parameterDomain else {
                throw GeometryConversionError.invalidInput("Original rolling support needs normalized source rails and positive radius.")
            }
            try curve(value.centerSpine, at: value.tolerance)
            try curve(value.firstContact, at: value.tolerance); try curve(value.secondContact, at: value.tolerance)
        case .originalCoons(let value):
            // Corner and traversal source witnesses were admitted by the only
            // immutable constructors/decoders, with their exact caller ledger.
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try value.validate(tolerance: tolerance, using: &execution)
            }
            try curve(value.vMinimumBoundary.source, at: tolerance)
            try curve(value.vMaximumBoundary.source, at: tolerance)
            try curve(value.uMinimumBoundary.source, at: tolerance)
            try curve(value.uMaximumBoundary.source, at: tolerance)
        case .originalBoundaryCorrected(let value):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try value.validate(tolerance: tolerance, using: &execution)
            }
            try surface(.bSpline(value.construction))
            try surface(.procedural(.originalCoons(value.boundaries)))
        case .originalPlaneDerivative(let value):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try value.validate(tolerance: tolerance, using: &execution)
            }
            try surface(.procedural(.originalBoundaryCorrected(value.construction)))
            try surface(.procedural(.originalCoons(value.boundaries)))
            func supports(_ constraints: [OriginalPlaneDerivativeConstraint]) throws {
                for constraint in constraints {
                    try execution.consumeWork(1)
                    try surface(constraint.surface)
                }
            }
            try supports(value.startConstraints); try supports(value.endConstraints)
        case .originalDrafted(let value):
            try value.validate(tolerance: tolerance)
            try curve(.originalDrafted(value.start), at: tolerance)
        case .originalRevolution(let value):
            // The immutable root span constructor/decoder already proves its
            // exact endpoint order, owning source coefficients and root cache.
            try value.validate(tolerance: tolerance)
            if maximumAlgebraicDepth != nil {
                try curve(value.generator.source, at: tolerance)
            }
        }
    }
}
