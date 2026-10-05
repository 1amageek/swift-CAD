import CADCore

/// Requested-order first offset on native pole charts with original normal joins.
struct OriginalNativePoleOffsetHigherJet {
    static func intervalTaylorJet(source: BSplineSurface3D, distances: [Double],
        over query: SurfaceParameterBox, throughOrder: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try withoutActuallyEscaping(consumeWork) { borrowed in
            var usage = OriginalSurfaceNativeHigherContinuity.Usage(consume: borrowed,
                maximumDepth: maximumSubdivisionDepth, consumeStorage: consumeStorage)
            guard !distances.isEmpty else {
                throw GeometryConversionError.invalidInput("Original parallel composition requires its genuine authored offset stages.")
            }
            let sourceOrder = throughOrder.addingReportingOverflow(distances.count)
            guard !sourceOrder.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original pole offset derivative order overflows.")
            }
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
                tolerance: tolerance, consumeWork: borrowed, consumeStorage: consumeStorage)
            let authorities = try OriginalNativePoleOffsetTaylor.prepare(source: source,
                prepared: prepared, over: query, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
            let spans = try prepared.originalNativeSpans(over: query, tolerance: tolerance,
                maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: borrowed, consumeStorage: { try consumeStorage?($0) })
            guard !spans.isEmpty else { throw rationalAlgebraFailure("Original pole offset has no native chart cover.") }
            if spans.count > 1 {
                try OriginalSurfaceNativeHigherContinuity.prove(source: source, spans: spans,
                    over: query, throughOrder: sourceOrder.partialValue,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, consumeWork: borrowed, consumeStorage: consumeStorage)
            }
            let pole = OriginalBSplinePoleNormal(surface: source, tolerance: tolerance, prepared: prepared)
            var values: [SurfaceAreaIntervalTaylorVectorJet] = []
            var normalFields: [[ExactBivariatePolynomial]] = []
            try RationalAlgebraStorage.retain(spans.count, of: SurfaceAreaIntervalTaylorVectorJet.self, usage: &usage)
            try RationalAlgebraStorage.retain(spans.count, of: [ExactBivariatePolynomial].self, usage: &usage)
            values.reserveCapacity(spans.count); normalFields.reserveCapacity(spans.count)
            for span in spans {
                try usage.visitExactCell(depth: 0)
                let local = SurfaceParameterBox(
                    u: .init(lower: max(query.u.lower, span.uBounds.lower), upper: min(query.u.upper, span.uBounds.upper)),
                    v: .init(lower: max(query.v.lower, span.vBounds.lower), upper: min(query.v.upper, span.vBounds.upper)))
                let receipt = try span.originalCoefficientReceipt(overClosedBox: local, on: source,
                    tolerance: tolerance, consumeWork: borrowed, consumeStorage: consumeStorage)
                let encloser = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
                    order: sourceOrder.partialValue, consumeWork: borrowed, consumeStorage: consumeStorage)
                let original = try encloser.intervalTaylorJet(using: receipt, consumeWork: borrowed, consumeStorage: consumeStorage)
                let coefficients = try pole.prepareExactPanelIfCollapsed(over: local, owning: span, usage: &usage)
                let polynomials: [ExactBivariatePolynomial]
                let normal: SurfaceAreaIntervalTaylorVectorJet
                if let factored = try OriginalNativePoleOffsetTaylor.normal(source: source, pole: pole,
                    coefficients: coefficients, authorities: authorities, over: local, owning: span,
                    throughOrder: throughOrder, tolerance: tolerance, usage: &usage), let coefficients {
                    polynomials = coefficients.coefficients; normal = factored
                } else {
                    polynomials = try OriginalRationalSurfacePolynomial(source: source, native: span,
                        domain: local, view: .zero, tolerance: tolerance, usage: &usage).normalNumerators
                    let taylor = try OriginalPolynomialSurfaceTaylor.vector(polynomials: polynomials,
                        over: local, throughOrder: throughOrder, tolerance: tolerance, usage: &usage)
                    normal = try OriginalPolynomialSurfaceTaylor.normalized(taylor, usage: &usage)
                }
                normalFields.append(polynomials)
                let polynomial = try OriginalRationalSurfacePolynomial(source: source, native: span,
                    domain: local, view: .zero, tolerance: tolerance, usage: &usage)
                let metric = try OriginalNativeParallelMetric(original: polynomial, normal: polynomials, usage: &usage)
                guard let admission = try metric.admission(over: local, distances: distances, usage: &usage) else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original native parallel prefix metric is unresolved on this whole higher chart.")
                }
                let displacement = try admission.displacement.outwardInterval(usage: &usage)
                values.append(try original.truncated(to: throughOrder, consumeWork: borrowed, consumeStorage: consumeStorage)
                    .adding(normal.scaled(by: displacement, consumeWork: borrowed, consumeStorage: consumeStorage), consumeWork: borrowed, consumeStorage: consumeStorage))
            }
            if spans.count > 1 {
                try OriginalNativeNormalHigherContinuity.prove(spans: spans, fields: normalFields,
                    over: query, throughOrder: throughOrder, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &usage)
            }
            guard let first = values.first else { throw rationalAlgebraFailure("Original pole offset lost its nonempty source cover.") }
            var result = first
            for value in values.dropFirst() {
                result = try hull(result, value, order: throughOrder, tolerance: tolerance, consumeWork: borrowed, consumeStorage: consumeStorage)
            }
            return result
        }
    }

    private static func hull(_ a: SurfaceAreaIntervalTaylorVectorJet,
        _ b: SurfaceAreaIntervalTaylorVectorJet, order: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func coordinate(_ first: SurfaceAreaIntervalTaylorScalarJet,
            _ second: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            for total in 0...order { for u in 0...total {
                let v = total - u
                try consumeWork()
                let lhs = try first.coefficient(u, v), rhs = try second.coefficient(u, v)
                try result.set(.init(lower: min(lhs.lower, rhs.lower), upper: max(lhs.upper, rhs.upper)), u, v)
            } }
            return result
        }
        return try .init(x: coordinate(a.x, b.x), y: coordinate(a.y, b.y), z: coordinate(a.z, b.z))
    }
}
