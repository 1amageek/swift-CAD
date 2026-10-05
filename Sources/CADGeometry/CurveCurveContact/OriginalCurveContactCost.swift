import CADCore

/// Precharges retained original representation and closed-jet work before preparation.
struct OriginalCurveContactCost {
    let preparation: Int
    let jet: Int

    init(source: Curve3D, budget: inout NativeCurveCurveContactBudget) throws {
        func adding(_ a: Int, _ b: Int) throws -> Int {
            let value = a.addingReportingOverflow(b)
            guard !value.overflow else { throw budget.exhausted() }
            return value.partialValue
        }
        func product(_ a: Int, _ b: Int) throws -> Int {
            let value = a.multipliedReportingOverflow(by: b)
            guard !value.overflow else { throw budget.exhausted() }
            return value.partialValue
        }
        func cost(_ curve: Curve3D, depth: Int) throws -> (Int, Int) {
            try budget.work(1)
            guard depth <= budget.remainingSourceDepth else { throw budget.exhausted() }
            switch curve {
            case .line: return (32, 64)
            case .circle, .analytic: return (64, 256)
            case .originalPolyline(let original):
                let payload = try product(original.points.count, 3)
                try budget.work(payload)
                return (try adding(payload, 16), try adding(payload, 64))
            case .bSpline(let original):
                let n = try adding(original.degree, 1)
                let perSpan = try product(product(product(n, n), n), 4)
                let allSpans = try product(perSpan, original.controlPointCount)
                return (try adding(allSpans, original.knots.count), try adding(allSpans, original.controlPointCount))
            case .originalGuideEndpointConnector(let connector):
                let guide = try cost(connector.source.source, depth: depth + 1)
                let first = try cost(connector.startBoundary.source, depth: depth + 1)
                let second = try cost(connector.endBoundary.source, depth: depth + 1)
                return (try adding(adding(adding(guide.0, first.0), second.0), 64),
                    try adding(guide.1, 192))
            case .originalGuideTraversalChain(let chain):
                var preparation = 0, jet = 0
                for traversal in chain.traversals {
                    let source = try cost(traversal.source, depth: depth+1)
                    preparation = try adding(preparation, source.0)
                    jet = try adding(jet, source.1)
                }
                for station in chain.stations {
                    try budget.work(1)
                    preparation = try adding(preparation, adding(station.canonicalNumeratorWords.count,
                        station.canonicalDenominatorWords.count))
                }
                return (try adding(preparation, chain.sourceSegmentOrdinals.count),
                    try adding(jet, product(chain.traversals.count, 64)))
            case .rigidImage(let image):
                let source = try cost(image.source, depth: depth + 1)
                return (try adding(source.0, 64), try adding(source.1, 192))
            case .affineImage(let image):
                let source = try cost(image.source, depth: depth + 1)
                return (try adding(source.0, 64), try adding(source.1, 192))
            case .originalAffineWord(let image):
                let original = try cost(image.source, depth: depth + 1)
                // The immutable word is already prepared. Actual bounded lower
                // queries admit its retained rational/algebraic action visits.
                let words = try product(image.operationWord.factors.count, 64)
                return (try adding(original.0, words), try adding(original.1, words))
            case .originalAngularTransport(let image):
                let original = try cost(image.source, depth: depth + 1)
                // Symbolic phase coefficients remain original source. Actual
                // preparation and closed angular jets charge their lower visits.
                return (try adding(original.0, 64), try adding(original.1, 192))
            case .originalConstructionChart(let image):
                let original = try cost(image.source, depth: depth + 1)
                return (try adding(original.0, 64), try adding(original.1, 192))
            case .originalEndpointConnector(let connector):
                let construction = try cost(.bSpline(connector.construction), depth: depth + 1)
                let first = try cost(connector.startBoundary.source, depth: depth + 1)
                let second = try cost(connector.endBoundary.source, depth: depth + 1)
                return (try adding(adding(adding(construction.0, first.0), second.0), 64),
                    try adding(construction.1, 192))
            case .originalDrafted(let image):
                let original = try cost(image.generator.source, depth: depth + 1)
                // Original draft ruling jets admit their physical-angle and
                // tangent-dependent operations through the same lower callbacks.
                return (try adding(original.0, 64), try adding(original.1, 256))
            case .originalPlaneDerivative(let image):
                let original = try cost(image.source.source, depth: depth + 1)
                var constraintCount = 0
                for constraints in [image.startConstraints, image.endConstraints] {
                    for constraint in constraints {
                        try budget.work(1)
                        guard depth < budget.remainingSourceDepth else { throw budget.exhausted() }
                        try GeometryStructuralComparisonWork.charge(surface: constraint.surface,
                            using: { try budget.work($0) })
                        constraintCount = try adding(constraintCount, 1)
                    }
                }
                // Exact projection caches are retained by the immutable source;
                // bounded queries charge the actual original endpoint action.
                let metadata = try product(constraintCount, 64)
                return (try adding(original.0, metadata), try adding(original.1, 192))
            case .parameterImage(let image):
                let source = try cost(image.source, depth: depth + 1)
                return (try adding(source.0, 16), try adding(source.1, 64))
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original Loft event queries reach
            // implicit/lift/certified curves here. Bounded Geometry preparation and
            // closed queries now debit actual work through the caller callback.
            // C1-only offset/localizer differential families still need their
            // original lower authority before complete guide-law support is claimed.
            case .implicit, .surfaceLift, .certifiedIntersection:
                // These are metadata reservations; all lower numeric preparation,
                // storage and jet operations are admitted by the same callback.
                return (1, 1)
            }
        }
        let result = try cost(source, depth: 0)
        preparation = result.0
        jet = result.1
    }
}
