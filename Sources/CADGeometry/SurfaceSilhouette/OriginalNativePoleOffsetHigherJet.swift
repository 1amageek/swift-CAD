import CADCore

/// Requested-order first offset on native pole charts with original normal joins.
struct OriginalNativePoleOffsetHigherJet {
    static func intervalTaylorJet(source: BSplineSurface3D, distances: [Double],
        over query: SurfaceParameterBox, throughOrder: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
            guard !distances.isEmpty else {
                throw GeometryConversionError.invalidInput("Original parallel composition requires its genuine authored offset stages.")
            }
            let sourceOrder = throughOrder.addingReportingOverflow(distances.count)
            guard !sourceOrder.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original pole offset derivative order overflows.")
            }
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
                tolerance: tolerance, using: &execution)
            let authorities = try OriginalNativePoleOffsetTaylor.prepare(source: source,
                prepared: prepared, over: query, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &execution)
            let spans = try prepared.originalNativeSpans(over: query, tolerance: tolerance,
                maximumSpanCount: min(262_144, maximumSpanCount), using: &execution)
            guard !spans.isEmpty else { throw rationalAlgebraFailure("Original pole offset has no native chart cover.") }
            if spans.count > 1 {
                try OriginalSurfaceNativeHigherContinuity.prove(source: source, spans: spans,
                    over: query, throughOrder: sourceOrder.partialValue,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, using: &execution)
            }
            let pole = OriginalBSplinePoleNormal(surface: source, tolerance: tolerance, prepared: prepared)
            var values: [SurfaceAreaIntervalTaylorVectorJet] = []
            var normalFields: [[ExactBivariatePolynomial]] = []
            try RationalAlgebraStorage.retain(spans.count, of: SurfaceAreaIntervalTaylorVectorJet.self, usage: &execution)
            try RationalAlgebraStorage.retain(spans.count, of: [ExactBivariatePolynomial].self, usage: &execution)
            values.reserveCapacity(spans.count); normalFields.reserveCapacity(spans.count)
            for span in spans {
                try execution.visitCell(axis: .value, depth: 0)
                let local = try SurfaceParameterBox(
                    u: .init(lower: max(query.u.lower, span.uBounds.lower), upper: min(query.u.upper, span.uBounds.upper)),
                    v: .init(lower: max(query.v.lower, span.vBounds.lower), upper: min(query.v.upper, span.vBounds.upper)))
                let receipt = try span.originalCoefficientReceipt(overClosedBox: local, on: source,
                    tolerance: tolerance, using: &execution)
                let encloser = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
                    order: sourceOrder.partialValue, using: &execution)
                let original = try encloser.intervalTaylorJet(using: receipt, admission: &execution)
                let coefficients = try pole.prepareExactPanelIfCollapsed(over: local, owning: span, usage: &execution)
                let polynomials: [ExactBivariatePolynomial]
                let normal: SurfaceAreaIntervalTaylorVectorJet
                if let factored = try OriginalNativePoleOffsetTaylor.normal(source: source, pole: pole,
                    coefficients: coefficients, authorities: authorities, over: local, owning: span,
                    throughOrder: throughOrder, tolerance: tolerance, usage: &execution), let coefficients {
                    polynomials = coefficients.coefficients; normal = factored
                } else {
                    polynomials = try OriginalRationalSurfacePolynomial(source: source, native: span,
                        domain: local, view: .zero, tolerance: tolerance, usage: &execution).normalNumerators
                    let taylor = try OriginalPolynomialSurfaceTaylor.vector(polynomials: polynomials,
                        over: local, throughOrder: throughOrder, tolerance: tolerance, usage: &execution)
                    normal = try OriginalPolynomialSurfaceTaylor.normalized(taylor, usage: &execution)
                }
                normalFields.append(polynomials)
                let polynomial = try OriginalRationalSurfacePolynomial(source: source, native: span,
                    domain: local, view: .zero, tolerance: tolerance, usage: &execution)
                let metric = try OriginalNativeParallelMetric(original: polynomial, normal: polynomials, usage: &execution)
                guard let admission = try metric.admission(over: local, distances: distances, usage: &execution) else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original native parallel prefix metric is unresolved on this whole higher chart.")
                }
                let displacement = try admission.displacement.outwardInterval(usage: &execution)
                values.append(try original.truncated(to: throughOrder, using: &execution)
                    .adding(normal.scaled(by: displacement, using: &execution), using: &execution))
            }
            if spans.count > 1 {
                try OriginalNativeNormalHigherContinuity.prove(spans: spans, fields: normalFields,
                    over: query, throughOrder: throughOrder, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &execution)
            }
            guard let first = values.first else { throw rationalAlgebraFailure("Original pole offset lost its nonempty source cover.") }
            var result = first
            for value in values.dropFirst() {
                result = try hull(result, value, order: throughOrder, tolerance: tolerance, using: &execution)
            }
            return result
    }

    private static func hull(_ a: SurfaceAreaIntervalTaylorVectorJet,
        _ b: SurfaceAreaIntervalTaylorVectorJet, order: Int, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func coordinate(_ first: SurfaceAreaIntervalTaylorScalarJet,
            _ second: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order,
                tolerance: tolerance, using: &execution)
            for total in 0...order { for u in 0...total {
                let v = total - u
                try execution.consumeWork(1)
                let lhs = try first.coefficient(u, v), rhs = try second.coefficient(u, v)
                try result.set(.init(lower: min(lhs.lower, rhs.lower), upper: max(lhs.upper, rhs.upper)), u, v)
            } }
            return result
        }
        return try .init(x: coordinate(a.x, b.x), y: coordinate(a.y, b.y), z: coordinate(a.z, b.z))
    }
}
