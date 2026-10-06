import CADCore

/// Bounds the continuous original Euclidean fraction law of authored UV points.
struct OriginalPolylineParameterBounds {
    static func enclosure(_ points: [SurfaceParameter], over range: ScalarInterval,
        order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumAlgebraicDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?) throws
        -> (u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet) {
        try withoutActuallyEscaping(consumeWork) { work in
            var usage = OriginalGeometryValidationAdmission(consumeWork: { _ in try work() },
                consumeStorage: consumeStorage)
            let law = try OriginalEuclideanPolylineParameterLaw(originalPoints: points,
                inheritedDepth: 0, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
            func original(_ value: Double, usage: inout OriginalGeometryValidationAdmission)
                throws -> OriginalSingularFieldElement {
                try .constant(.originalDouble(value, usage: &usage), in: law.context,
                    maximumDepth: maximumAlgebraicDepth, usage: &usage)
            }
            let lower = try original(range.lower, usage: &usage)
            let upper = try original(range.upper, usage: &usage)
            var uValue: OutwardScalarInterval?, vValue: OutwardScalarInterval?
            var derivative: (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement)?
            var count = 0
            for segment in law.segments {
                try consumeWork()
                if case .positive = try lower.subtracting(segment.upperFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &usage)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) { continue }
                if case .negative = try upper.subtracting(segment.lowerFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &usage)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) { continue }
                count += 1
                guard count <= maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original polyline owning cover exceeds caller span admission.")
                }
                let start: OriginalSingularFieldElement
                if case .negative = try lower.subtracting(segment.lowerFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &usage)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) { start = segment.lowerFraction }
                else { start = lower }
                let end: OriginalSingularFieldElement
                if case .positive = try upper.subtracting(segment.upperFraction,
                    maximumDepth: maximumAlgebraicDepth, usage: &usage)
                    .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) { end = segment.upperFraction }
                else { end = upper }
                let a = try segment.originalUV(atOriginalFraction: start,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
                let b = try segment.originalUV(atOriginalFraction: end,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
                let u = try a.u.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &usage)
                    .union(b.u.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &usage))
                let v = try a.v.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &usage)
                    .union(b.v.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &usage))
                uValue = uValue.map { $0.union(u) } ?? u
                vValue = vValue.map { $0.union(v) } ?? v
                if order > 0 {
                    let next = try segment.originalFirstDerivative(maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
                    if let previous = derivative {
                        guard case .zero = try previous.u.subtracting(next.u,
                            maximumDepth: maximumAlgebraicDepth, usage: &usage)
                            .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage),
                            case .zero = try previous.v.subtracting(next.v,
                            maximumDepth: maximumAlgebraicDepth, usage: &usage)
                            .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) else {
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
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            var v = try SurfaceAreaIntervalTaylorScalarJet.constant(vValue, order: order, axis: .u,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            if order > 0, let derivative {
                try u.set(derivative.u.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &usage), 1, 0)
                try v.set(derivative.v.enclosure(maximumDepth: maximumAlgebraicDepth, usage: &usage), 1, 0)
            }
            return (u, v)
        }
    }
}
