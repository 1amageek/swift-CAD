import CADCore

extension Surface3D {
    package func validate(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws {
        try validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    package func validateOriginalSource(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, consumeWork: (Int) throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws {
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.resourceLimitExceeded("Original surface validation exhausted caller depth.")
        }
        try consumeWork(0); try Task.checkCancellation(); try tolerance.validate()
        func surface(_ source: Surface3D) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original surface descendant exhausted source depth.")
            }
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        func curve(_ source: Curve3D, at sourceTolerance: ModelingTolerance) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original surface rail exhausted source depth.")
            }
            try source.validateOriginalSource(tolerance: sourceTolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        switch self {
        case .plane(let value): try value.validate(tolerance: tolerance)
        case .cylinder(let value): try value.validate(tolerance: tolerance)
        case .analytic(let value): try value.validate(tolerance: tolerance)
        case .bSpline(let value):
            try OriginalGeometrySourceValidation.validate(value, tolerance: tolerance,
                consumeWork: { try consumeWork(0) })
        case .procedural(.offset(let value)):
            guard value.distance.isFinite else { throw GeometryError.invalidDistance(value.distance) }
            try surface(value.source)
        case .procedural(.originalAffineWord(let image)):
            try image.validateOriginalRelation(tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .procedural(.originalAngularTransport(let image)):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original angular support exhausted source depth.")
            }
            try withoutActuallyEscaping(consumeWork) { visit in
                var usage = OriginalGeometryValidationAdmission(consumeWork: visit,
                    consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
                try image.validateOriginalRelation(tolerance: tolerance, usage: &usage)
            }
        case .procedural(.originalImage(let image)):
            try image.transform.validate()
            guard image.uOffset.isFinite, image.vOffset.isFinite else {
                throw GeometryConversionError.invalidInput("Original surface image offsets are not finite.")
            }
            try image.uParameterGain.validateOriginalSource(remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork)
            try image.vParameterGain.validateOriginalSource(remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork)
            try surface(image.source)
            try image.uDomain.validate(tolerance: tolerance); try image.vDomain.validate(tolerance: tolerance)
        case .procedural(.ruled(let value)):
            try curve(value.startBoundary, at: tolerance); try curve(value.endBoundary, at: tolerance)
            guard case .closed(let lower, let upper) = value.uDomain,
                  lower.isFinite, upper.isFinite,
                  upper - lower > max(tolerance.angle, tolerance.distance),
                  try value.startBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance),
                  try value.endBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance) else {
                throw GeometryConversionError.invalidInput("Original ruled support requires both complete finite rails.")
            }
        case .procedural(.rollingBall(let value)):
            try value.tolerance.validate()
            guard value.radius.isFinite, value.radius > value.tolerance.distance,
                  case .closed(0, 1) = value.centerSpine.parameterDomain,
                  case .closed(0, 1) = value.firstContact.parameterDomain,
                  case .closed(0, 1) = value.secondContact.parameterDomain else {
                throw GeometryConversionError.invalidInput("Original rolling support needs normalized source rails and positive radius.")
            }
            try curve(value.centerSpine, at: value.tolerance)
            try curve(value.firstContact, at: value.tolerance); try curve(value.secondContact, at: value.tolerance)
        case .procedural(.originalCoons(let value)):
            // Corner and traversal source witnesses were admitted by the only
            // immutable constructors/decoders, with their exact caller ledger.
            try value.validate(tolerance: tolerance)
            if maximumAlgebraicDepth != nil {
                try curve(value.vMinimumBoundary.source, at: tolerance)
                try curve(value.vMaximumBoundary.source, at: tolerance)
                try curve(value.uMinimumBoundary.source, at: tolerance)
                try curve(value.uMaximumBoundary.source, at: tolerance)
            }
        case .procedural(.originalBoundaryCorrected(let value)):
            try value.validate(tolerance: tolerance)
            try surface(.bSpline(value.construction))
            try surface(.procedural(.originalCoons(value.boundaries)))
        case .procedural(.originalPlaneDerivative(let value)):
            try value.validate(tolerance: tolerance)
            try surface(.procedural(.originalBoundaryCorrected(value.construction)))
            try surface(.procedural(.originalCoons(value.boundaries)))
            func supports(_ constraints: [OriginalPlaneDerivativeConstraint]) throws {
                for constraint in constraints {
                    try consumeWork(0)
                    try surface(constraint.surface)
                }
            }
            try supports(value.startConstraints); try supports(value.endConstraints)
        case .procedural(.originalDrafted(let value)):
            try value.validate(tolerance: tolerance)
            try curve(.originalDrafted(value.start), at: tolerance)
        case .procedural(.originalRevolution(let value)):
            // The immutable root span constructor/decoder already proves its
            // exact endpoint order, owning source coefficients and root cache.
            try value.validate(tolerance: tolerance)
            if maximumAlgebraicDepth != nil {
                try curve(value.generator.source, at: tolerance)
            }
        }
    }
}
