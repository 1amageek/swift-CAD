import CADCore

extension Curve3D {
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
            throw GeometryConversionError.resourceLimitExceeded("Original curve validation exhausted caller depth.")
        }
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
        func descendant(_ source: Curve3D) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original curve descendant exhausted source depth.")
            }
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        func traversal(_ value: OriginalCurveRootSpan3D) throws {
            func endpoint(_ endpoint: OriginalCurveRootEndpoint) throws {
                try consumeWork(0)
                if case .algebraic(let root) = endpoint,
                    let maximumAlgebraicDepth, root.isolationDepth > maximumAlgebraicDepth {
                    throw GeometryConversionError.resourceLimitExceeded("Original traversal endpoint exceeds the selected independent algebra depth.")
                }
            }
            try endpoint(value.start); try endpoint(value.end)
            try descendant(value.source)
        }
        switch self {
        case .line(let value): try value.validate(tolerance: tolerance)
        case .circle(let value): try value.validate(tolerance: tolerance)
        case .analytic(let value): try value.validate(tolerance: tolerance)
        case .bSpline(let value):
            try OriginalGeometrySourceValidation.validate(value, tolerance: tolerance,
                consumeWork: { try consumeWork(0) })
        case .originalPolyline(let value):
            try value.validate(tolerance: tolerance)
            for point in value.points {
                try consumeWork(0); try point.validate()
            }
            if let selected = maximumAlgebraicDepth, selected < value.maximumAlgebraicDepth {
                try withoutActuallyEscaping(consumeWork) { visit in
                    var usage = OriginalGeometryValidationAdmission(consumeWork: visit,
                        consumeStorage: consumeStorage, maximumAlgebraicDepth: selected)
                    _ = try OriginalPolylineCurve3D(points: value.points, isClosed: value.isClosed,
                        tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                        maximumSubdivisionDepth: maximumSubdivisionDepth,
                        maximumAlgebraicDepth: selected, usage: &usage)
                }
            }
        case .rigidImage(let image):
            try image.transform.validate(tolerance: tolerance); try descendant(image.source)
        case .affineImage(let image):
            try image.transform.validate(); try descendant(image.source)
        case .originalAffineWord(let image):
            try image.validateOriginalRelation(tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .originalAngularTransport(let image):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original angular curve exhausted source depth.")
            }
            try withoutActuallyEscaping(consumeWork) { visit in
                var usage = OriginalGeometryValidationAdmission(consumeWork: visit,
                    consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
                try image.validateOriginalRelation(tolerance: tolerance, usage: &usage)
            }
        case .originalConstructionChart(let image):
            try image.validate(tolerance: tolerance)
            try descendant(image.source)
        case .originalEndpointConnector(let connector):
            try connector.validate(tolerance: tolerance)
            try OriginalGeometrySourceValidation.validate(connector.construction,
                tolerance: tolerance, consumeWork: { try consumeWork(0) })
            try traversal(connector.startBoundary)
            try traversal(connector.endBoundary)
        case .originalPlaneDerivative(let value):
            try value.validate(tolerance: tolerance)
            try traversal(value.source)
            func supports(_ constraints: [OriginalPlaneDerivativeConstraint]) throws {
                for constraint in constraints {
                    try consumeWork(0)
                    guard remainingSourceDepth > 0 else {
                        throw GeometryConversionError.resourceLimitExceeded("Original plane derivative support exhausted source depth.")
                    }
                    try constraint.surface.validateOriginalSource(tolerance: tolerance,
                        remainingSourceDepth: remainingSourceDepth - 1,
                        maximumSubdivisionDepth: maximumSubdivisionDepth,
                        consumeWork: consumeWork, consumeStorage: consumeStorage,
                        maximumAlgebraicDepth: maximumAlgebraicDepth)
                }
            }
            try supports(value.startConstraints); try supports(value.endConstraints)
        case .originalDrafted(let value):
            try value.validate(tolerance: tolerance)
            try traversal(value.generator)
        case .originalGuideTraversalChain(let value):
            try value.validate(tolerance: tolerance)
            for piece in value.traversals {
                try consumeWork(0)
                try traversal(piece)
            }
        case .originalGuideEndpointConnector(let value):
            try value.validate(tolerance: tolerance)
            try traversal(value.source)
            try traversal(value.startBoundary)
            try traversal(value.endBoundary)
        case .parameterImage(let image):
            try image.parameterGain.validateOriginalSource(remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork)
            guard image.offset.isFinite else { throw GeometryError.invalidCoordinate(image.offset) }
            try descendant(image.source); try image.parameterDomain.validate(tolerance: tolerance)
        case .implicit(let source):
            // Immutable graph values can only be constructed/decoded after the
            // original cells and joins have been certified. This consumes that
            // witness rather than rerunning a private interval allowance.
            try source.validateCertificationContract(tolerance: tolerance)
            if maximumAlgebraicDepth != nil {
                guard remainingSourceDepth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original graph source exhausted source depth.")
                }
                try source.firstSurface.validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: remainingSourceDepth - 1,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
                try source.secondSurface.validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: remainingSourceDepth - 1,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
            }
        case .surfaceLift(let lift):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original lift validation exhausted source depth.")
            }
            try lift.surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try lift.parameterCurve.validateOriginalSource(on: lift.surface, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            if let image = lift.exactBSplineImage {
                try OriginalGeometrySourceValidation.validate(image, tolerance: tolerance,
                    consumeWork: { try consumeWork(0) })
                guard case .closed(let lower, let upper) = image.domain,
                      abs(lower) <= tolerance.relative, abs(upper - 1) <= tolerance.relative else {
                    throw GeometryConversionError.invalidInput("Original lift image needs its normalized native domain.")
                }
            }
        case .certifiedIntersection:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Manual bounded BRep validation
            // reaches analytic certificate producers whose proof loops do not
            // yet accept this caller ledger. Full validation must forward those
            // original proof visits before this branch can succeed.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original analytic certificate validation requires caller-admitted proof loops.")
        }
    }
}
