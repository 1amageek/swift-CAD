import CADCore

/// Bounds the continuous original Euclidean fraction law of authored UV points.
struct OriginalPolylineParameterBounds {
    static func enclosure(_ points: [SurfaceParameter], over range: ScalarInterval,
        order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws
        -> (u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet) {
            let law = try OriginalEuclideanPolylineParameterLaw(originalPoints: points,
                inheritedDepth: 0, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)
            func original(_ value: Double, using execution: inout OriginalQueryExecution)
                throws -> OriginalSingularFieldElement {
                try .constant(.originalDouble(value, usage: &execution), in: law.context,
                    maximumDepth: maximumAlgebraicDepth, usage: &execution)
            }
            let lower = try original(range.lower, using: &execution)
            let upper = try original(range.upper, using: &execution)
            var uValue: OutwardScalarInterval?, vValue: OutwardScalarInterval?
            var derivative: (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement)?
            var count = 0
            for segment in law.segments {
                try execution.consumeWork(1)
                if case .positive = try lower.subtracting(segment.upperFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &execution)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &execution) { continue }
                if case .negative = try upper.subtracting(segment.lowerFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &execution)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &execution) { continue }
                count += 1
                guard count <= maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original polyline owning cover exceeds caller span admission.")
                }
                let start: OriginalSingularFieldElement
                if case .negative = try lower.subtracting(segment.lowerFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &execution)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &execution) { start = segment.lowerFraction }
                else { start = lower }
                let end: OriginalSingularFieldElement
                if case .positive = try upper.subtracting(segment.upperFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &execution)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &execution) { end = segment.upperFraction }
                else { end = upper }
                let a = try segment.originalUV(atOriginalFraction: start,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)
                let b = try segment.originalUV(atOriginalFraction: end,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)
                let u = try a.u.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &execution)
                    .union(b.u.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &execution))
                let v = try a.v.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &execution)
                    .union(b.v.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &execution))
                uValue = uValue.map { $0.union(u) } ?? u
                vValue = vValue.map { $0.union(v) } ?? v
                if order > 0 {
                    let next = try segment.originalFirstDerivative(maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)
                    if let previous = derivative {
                        guard case .zero = try previous.u.subtracting(next.u,
                            maximumDepth: maximumAlgebraicDepth, usage: &execution)
                            .sign(maximumDepth: maximumAlgebraicDepth, usage: &execution),
                            case .zero = try previous.v.subtracting(next.v,
                            maximumDepth: maximumAlgebraicDepth, usage: &execution)
                            .sign(maximumDepth: maximumAlgebraicDepth, usage: &execution) else {
                            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                                message: "Original polyline query crosses unequal one-sided derivative laws.")
                        }
                    } else { derivative = next }
                }
            }
            guard let uValue, let vValue else {
                throw GeometryConversionError.invalidInput("Original polyline fraction has no complete positive-segment cover.")
            }
            var u = try SurfaceAreaIntervalTaylorScalarJet.constant(uValue, order: order, axis: .u,
                tolerance: tolerance, using: &execution)
            var v = try SurfaceAreaIntervalTaylorScalarJet.constant(vValue, order: order, axis: .u,
                tolerance: tolerance, using: &execution)
            if order > 0, let derivative {
                try u.set(derivative.u.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &execution), 1, 0)
                try v.set(derivative.v.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &execution), 1, 0)
            }
            return (u, v)
    }
}
