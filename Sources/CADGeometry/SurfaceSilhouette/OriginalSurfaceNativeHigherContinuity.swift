import CADCore

/// Requested-order exact source partial equality on every selected native edge.
struct OriginalSurfaceNativeHigherContinuity {
    private struct Edge: Hashable {
        let alongU: Bool
        let station: Double
        let transverse: ScalarInterval
    }

    static func prove(source: BSplineSurface3D,
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        over query: SurfaceParameterBox, throughOrder: Int, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        try proveOriginal(source: source, spans: spans, over: query, throughOrder: throughOrder,
            requiredPartials: nil, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    static func prove(source: BSplineSurface3D,
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        over query: SurfaceParameterBox, requiredPartials: [(uOrder: Int, vOrder: Int)],
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        guard !requiredPartials.isEmpty else { throw rationalAlgebraFailure("Original continuity needs explicitly requested partials.") }
        var order = 0
        for required in requiredPartials {
            try execution.consumeWork(1)
            let total = try rationalAlgebraCount(required.uOrder, required.vOrder)
            order = max(order, total)
        }
        try proveOriginal(source: source, spans: spans, over: query, throughOrder: order,
            requiredPartials: requiredPartials, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    private static func proveOriginal(source: BSplineSurface3D,
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        over query: SurfaceParameterBox, throughOrder: Int,
        requiredPartials: [(uOrder: Int, vOrder: Int)]?, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        if let maximumAlgebraicDepth, !(0...32).contains(maximumAlgebraicDepth) {
            throw rationalAlgebraFailure("Original join coefficient depth exceeds the intrinsic caller policy.")
        }
        if let cap = maximumAlgebraicDepth {
            return try execution.withProofScope(maximum: .init(value: cap, coefficient: cap)) { execution in
                try proveOriginal(source: source, spans: spans, over: query, throughOrder: throughOrder,
                    requiredPartials: requiredPartials, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, maximumAlgebraicDepth: nil, using: &execution)
            }
        }
            var edges: [Edge: [Int]] = [:]
            var laws: [Int: OriginalRationalSurfaceDerivativeLaw] = [:]
            func law(_ index: Int, using execution: inout OriginalQueryExecution) throws -> OriginalRationalSurfaceDerivativeLaw {
                if let retained = laws[index] { return retained }
                let span = spans[index]
                let local = try SurfaceParameterBox(
                    u: ScalarInterval(lower: max(query.u.lower, span.uBounds.lower), upper: min(query.u.upper, span.uBounds.upper)),
                    v: ScalarInterval(lower: max(query.v.lower, span.vBounds.lower), upper: min(query.v.upper, span.vBounds.upper)))
                let original = try OriginalRationalSurfacePolynomial(source: source, native: span,
                    domain: local, view: .zero, tolerance: tolerance, usage: &execution)
                let retained = try OriginalRationalSurfaceDerivativeLaw(original: original,
                    throughOrder: throughOrder, usage: &execution)
                try RationalAlgebraStorage.retain(1, of: (Int, OriginalRationalSurfaceDerivativeLaw).self, usage: &execution)
                laws[index] = retained
                return retained
            }
            for index in spans.indices {
                let span = spans[index]
                for axis in 0..<2 {
                    let alongU = axis == 0
                    let bounds = alongU ? span.uBounds : span.vBounds
                    let transverse = alongU ? span.vBounds : span.uBounds
                    let range = alongU ? query.u : query.v
                    for side in 0..<2 {
                        let station = side == 0 ? bounds.lower : bounds.upper
                        guard station >= range.lower, station <= range.upper else { continue }
                        let edge = Edge(alongU: alongU, station: station, transverse: transverse)
                        for other in edges[edge, default: []] {
                            try execution.consumeWork(1)
                            let previous = spans[other]
                            if previous.uSpanIndex == span.uSpanIndex, previous.vSpanIndex == span.vSpanIndex,
                                previous.uCycle == span.uCycle, previous.vCycle == span.vCycle { continue }
                            let first = try law(other, using: &execution), second = try law(index, using: &execution)
                            let differences = try first.equalityNumerators(with: second, requiredPartials: requiredPartials, usage: &execution)
                            let exactStation = try ExactRationalCoefficient.originalDouble(station, usage: &execution)
                            let transverseQuery = alongU ? query.v : query.u
                            let lo = max(transverse.lower, transverseQuery.lower), hi = min(transverse.upper, transverseQuery.upper)
                            for difference in differences {
                                let restriction = try difference.restricted(alongU: alongU, station: exactStation, usage: &execution)
                                let equal: Bool
                                if lo == hi {
                                    equal = try restriction.evaluated(atU: .originalDouble(lo, usage: &execution), v: .zero, usage: &execution).isZero
                                } else { equal = restriction.isZero }
                                guard equal else {
                                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                                        message: "Original requested surface partial is discontinuous at this selected native join.")
                                }
                            }
                        }
                        if edges[edge] == nil {
                            try RationalAlgebraStorage.retain(1, of: (Edge, [Int]).self, usage: &execution)
                        }
                        try RationalAlgebraStorage.retain(1, of: Int.self, usage: &execution)
                        edges[edge, default: []].append(index)
                    }
                }
            }
    }
}
