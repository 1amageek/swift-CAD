import CADCore

extension Curve3D {
    package func validate(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, atSourceDepth sourceDepth: Int = 0, using execution: inout OriginalQueryExecution) throws {
        try validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth, using: &execution)
    }

    package func validateOriginalSource(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, atSourceDepth sourceDepth: Int = 0, using execution: inout OriginalQueryExecution) throws {
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ $0 >= 0 }) ?? true else {
            throw GeometryConversionError.resourceLimitExceeded("Original curve validation exhausted caller depth.")
        }
        let selectedMaximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: selectedMaximum) { execution in
        try execution.admitSourceDepth(sourceDepth)
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
        switch self {
        case .line(let value): try value.validate(tolerance: tolerance)
        case .circle(let value): try value.validate(tolerance: tolerance)
        case .analytic(let value): try value.validate(tolerance: tolerance, using: &execution)
        case .bSpline(let value):
            try OriginalGeometrySourceValidation.validate(value, tolerance: tolerance,
                using: &execution)
        case .surfaceLift(let lift):
            try Self.validateLiftOriginalSource(lift, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth, using: &execution)
        default:
            try Self.validateOtherOriginalSource(self, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth, using: &execution)
        }
        }
    }

    @inline(never)
    private static func validateLiftOriginalSource(_ lift: SurfaceLiftCurve3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int?, atSourceDepth sourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original lift validation exhausted source depth.")
            }
            try lift.surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
            try lift.parameterCurve.validateOriginalSource(on: lift.surface, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
            if let image = lift.exactBSplineImage {
                try OriginalGeometrySourceValidation.validate(image, tolerance: tolerance,
                    using: &execution)
                guard case .closed(let lower, let upper) = image.domain,
                      abs(lower) <= tolerance.relative, abs(upper - 1) <= tolerance.relative else {
                    throw GeometryConversionError.invalidInput("Original lift image needs its normalized native domain.")
                }
            }
    }

    @inline(never)
    private static func validateOtherOriginalSource(_ original: Curve3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int?, atSourceDepth sourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws {
        func descendant(_ source: Curve3D) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original curve descendant exhausted source depth.")
            }
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
        }
        func traversal(_ value: OriginalCurveRootSpan3D, sourceEdges: Int = 1) throws {
            func endpoint(_ endpoint: OriginalCurveRootEndpoint) throws {
                try execution.consumeWork(1)
                if case .algebraic(let root) = endpoint,
                    let maximumAlgebraicDepth, root.isolationDepth > maximumAlgebraicDepth {
                    throw GeometryConversionError.resourceLimitExceeded("Original traversal endpoint exceeds the selected independent algebra depth.")
                }
            }
            try endpoint(value.start); try endpoint(value.end)
            if sourceEdges == 2 {
                guard remainingSourceDepth >= 2 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original drafted source exhausted generator traversal depth.")
                }
                try execution.admitSourceDepth(sourceDepth + 1)
                try value.source.validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: remainingSourceDepth - 2,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                    atSourceDepth: sourceDepth + 2, using: &execution)
            } else {
                try descendant(value.source)
            }
        }
        switch original {
        case .originalPolyline(let value):
            try value.validate(tolerance: tolerance)
            for point in value.points {
                try execution.consumeWork(1); try point.validate()
            }
            if let selected = maximumAlgebraicDepth, selected < value.maximumAlgebraicDepth {

                    _ = try OriginalPolylineCurve3D(points: value.points, isClosed: value.isClosed,
                        tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                        maximumSubdivisionDepth: maximumSubdivisionDepth,
                        maximumAlgebraicDepth: selected, usage: &execution)

            }
        case .rigidImage(let image):
            try image.transform.validate(tolerance: tolerance); try descendant(image.source)
        case .affineImage(let image):
            try image.transform.validate(); try descendant(image.source)
        case .originalAffineWord(let image):
            try image.validateOriginalRelation(tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        case .originalAngularTransport(let image):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original angular curve exhausted source depth.")
            }

                try image.validateOriginalRelation(tolerance: tolerance, usage: &execution)

        case .originalConstructionChart(let image):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try image.validate(tolerance: tolerance, using: &execution)
            }
            try descendant(image.source)
        case .originalEndpointConnector(let connector):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try connector.validate(tolerance: tolerance, using: &execution)
            }
            try OriginalGeometrySourceValidation.validate(connector.construction,
                tolerance: tolerance, using: &execution)
            try traversal(connector.startBoundary)
            try traversal(connector.endBoundary)
        case .originalPlaneDerivative(let value):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try value.validate(tolerance: tolerance, using: &execution)
            }
            try traversal(value.source)
            func supports(_ constraints: [OriginalPlaneDerivativeConstraint]) throws {
                for constraint in constraints {
                    try execution.consumeWork(1)
                    guard remainingSourceDepth > 0 else {
                        throw GeometryConversionError.resourceLimitExceeded("Original plane derivative support exhausted source depth.")
                    }
                    try constraint.surface.validateOriginalSource(tolerance: tolerance,
                        remainingSourceDepth: remainingSourceDepth - 1,
                        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
                }
            }
            try supports(value.startConstraints); try supports(value.endConstraints)
        case .originalDrafted(let value):
            try value.validate(tolerance: tolerance)
            try traversal(value.generator, sourceEdges: 2)
        case .originalGuideTraversalChain(let value):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try value.validate(tolerance: tolerance, using: &execution)
            }
            for piece in value.traversals {
                try execution.consumeWork(1)
                try traversal(piece)
            }
        case .originalGuideEndpointConnector(let value):
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try value.validate(tolerance: tolerance, using: &execution)
            }
            try traversal(value.source)
            try traversal(value.startBoundary)
            try traversal(value.endBoundary)
        case .parameterImage(let image):
            try image.parameterGain.validateOriginalSource(remainingSourceDepth: remainingSourceDepth, atSourceDepth: sourceDepth, using: &execution)
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
                    maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
                try source.secondSurface.validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: remainingSourceDepth - 1,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, atSourceDepth: sourceDepth + 1, using: &execution)
            }
        case .certifiedIntersection(let certified):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Direct certificate proof loops now
            // borrow this execution. Original exact source correspondence/coverage
            // remains a separate family obligation; manual bounded structural BRep
            // validation must not be reported as that exact-intersection proof.
            try execution.withSourceDepthOffset(sourceDepth) { execution in
                try certified.validate(tolerance: tolerance, using: &execution)
            }
        case .line, .circle, .analytic, .bSpline, .surfaceLift:
            throw GeometryConversionError.invalidInput("Original curve family dispatch requires a non-native non-lift source.")
        }
    }
}
