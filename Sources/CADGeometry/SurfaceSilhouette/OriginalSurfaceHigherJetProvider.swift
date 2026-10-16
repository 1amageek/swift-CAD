import CADCore

/// Original higher source jets shared by implicit-curve and silhouette algorithms.
package struct OriginalSurfaceHigherJetProvider {
    package static func intervalTaylorJet(of source: Surface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, throughOrder order: Int,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard order >= 0, maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true, maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original surface jets need a nonnegative requested order and caller span admission.")
        }
        if let cap = maximumAlgebraicDepth {
            return try execution.withProofScope(maximum: .init(value: cap, coefficient: cap)) { execution in
                try intervalTaylorJet(of: source, over: box, tolerance: tolerance,
                    throughOrder: order, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: nil,
                    using: &execution)
            }
        }
        try execution.consumeWork(1)
        if case .procedural = source, remainingSourceDepth == 0 {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original higher surface source exhausted caller depth.")
        }
        if let analytic = try SurfaceSilhouetteAnalyticTaylor.surface(source, over: box,
            tolerance: tolerance, order: order, using: &execution) { return analytic }
        switch source {
        case .bSpline(let surface):
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface,
                tolerance: tolerance, using: &execution)
            let spans = try prepared.originalNativeSpans(over: box, tolerance: tolerance,
                maximumSpanCount: min(262_144, maximumSpanCount), using: &execution)
            guard !spans.isEmpty else { throw failure(tolerance, "Original higher native chart has no span cover.") }
            if spans.count > 1 {
                try OriginalSurfaceNativeHigherContinuity.prove(source: surface, spans: spans,
                    over: box, throughOrder: order, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            }
            var result: SurfaceAreaIntervalTaylorVectorJet?
            for span in spans {
                let local = try SurfaceParameterBox(
                    u: ScalarInterval(lower: max(box.u.lower, span.uBounds.lower), upper: min(box.u.upper, span.uBounds.upper)),
                    v: ScalarInterval(lower: max(box.v.lower, span.vBounds.lower), upper: min(box.v.upper, span.vBounds.upper)))
                let receipt = try span.originalCoefficientReceipt(overClosedBox: local,
                    on: surface, tolerance: tolerance, using: &execution)
                let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
                    order: order, using: &execution)
                let value = try higher.intervalTaylorJet(using: receipt, admission: &execution)
                if let previous = result {
                    result = try hull(previous, value, order: order, tolerance: tolerance, using: &execution)
                } else { result = value }
            }
            guard let result else { throw failure(tolerance, "Original higher native cover did not publish a value.") }
            return result
        case .procedural(.offset(let offset)):
            var base = offset.source
            var distances: [Double] = []
            var chainDepth = remainingSourceDepth - 1
            if offset.distance != 0 {
                try execution.consumeWork(1); try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
                distances.append(offset.distance)
            }
            while case .procedural(.offset(let inner)) = base {
                guard chainDepth > 0 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Original higher offset chain exhausted the caller source depth.")
                }
                try execution.consumeWork(1); chainDepth -= 1
                if inner.distance != 0 {
                    try execution.consumeWork(1); try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
                    distances.append(inner.distance)
                }
                base = inner.source
            }
            if !distances.isEmpty, case .bSpline(let native) = base {
                distances.reverse()
                return try OriginalNativePoleOffsetHigherJet.intervalTaylorJet(source: native,
                    distances: distances, over: box, throughOrder: order,
                    maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, using: &execution)
            }
            let next = order.addingReportingOverflow(offset.distance == 0 ? 0 : 1)
            guard !next.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original higher offset derivative order overflows.")
            }
            let original = try intervalTaylorJet(of: offset.source, over: box, tolerance: tolerance,
                throughOrder: next.partialValue, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            if offset.distance == 0 { return original }
            try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
            return try SurfaceAreaOffsetTaylorComposition(distances: [offset.distance])
                .intervalTaylorJet(from: original, translation: nil, requestedResultOrder: order,
                    using: &execution)
        case .procedural(.originalAngularTransport(let image)):
            return try image.intervalTaylorJet(over: box, throughOrder: order,
                tolerance: tolerance, using: &execution)
        case .procedural(.originalImage(let image)):
            let nativeBox = try image.nativeBox(box, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            let original = try intervalTaylorJet(of: image.source, over: nativeBox,
                tolerance: tolerance, throughOrder: order, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            let gu = try image.uParameterGain.interval(), gv = try image.vParameterGain.interval()
            func coordinate(_ scalar: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
                var mapped = try SurfaceAreaIntervalTaylorScalarJet(order: order,
                    tolerance: tolerance, using: &execution)
                var uScale = OutwardScalarInterval.exact(1)
                for u in 0...order {
                    var scale = uScale
                    for v in 0...(order - u) {
                        try execution.consumeWork(1); try mapped.set(scalar.coefficient(image.swapAxes ? v : u, image.swapAxes ? u : v) * scale, u, v)
                        scale = scale * gv
                    }
                    uScale = uScale * gu
                }
                return mapped
            }
            let x = try coordinate(original.x), y = try coordinate(original.y), z = try coordinate(original.z)
            func transformed(_ a: Double, _ b: Double, _ c: Double, _ translation: Double)
                throws -> SurfaceAreaIntervalTaylorScalarJet {
                try x.scaled(by: .exact(a), using: &execution)
                    .adding(y.scaled(by: .exact(b), using: &execution), using: &execution)
                    .adding(z.scaled(by: .exact(c), using: &execution), using: &execution)
                    .adding(.constant(.exact(translation), order: order, tolerance: tolerance,
                        using: &execution), using: &execution)
            }
            let t = image.transform
            return try .init(x: transformed(t.basisX.x, t.basisY.x, t.basisZ.x, t.translation.x),
                y: transformed(t.basisX.y, t.basisY.y, t.basisZ.y, t.translation.y),
                z: transformed(t.basisX.z, t.basisY.z, t.basisZ.z, t.translation.z))
        case .procedural(.originalAffineWord(let image)):
            if let coefficients = image.harmonicCoefficients {
                try image.admitCoefficientProof(using: &execution)
                return try coefficients.intervalTaylorJet(over: box, throughOrder: order,
                    tolerance: tolerance, using: &execution)
            }
            let sourceTolerance = try image.sourceCalculationTolerance(tolerance: tolerance,
                using: &execution)
            let original = try intervalTaylorJet(of: image.source, over: box,
                tolerance: sourceTolerance, throughOrder: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            let transported = try OriginalAffineWordJetTransport.applying(image.preparedWord,
                to: original, using: &execution)
            return try transported.retagTolerance(to: tolerance)
        case .procedural(.originalDrafted(let drafted)):
            return try drafted.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, using: &execution)
        case .procedural(.originalPlaneDerivative(let constrained)):
            return try constrained.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, using: &execution)
        case .procedural(.originalBoundaryCorrected(let corrected)):
            return try corrected.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, using: &execution)
        case .procedural(.originalCoons(let coons)):
            return try coons.intervalTaylorJet(over: box, throughOrder: order,
                tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth, using: &execution)
        case .procedural(.originalRevolution(let revolution)):
            return try OriginalRevolutionSurfaceHigherTaylor.surface(revolution, over: box,
                tolerance: tolerance, order: order,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, using: &execution)
        case .procedural(let procedural):
            return try OriginalProceduralSurfaceHigherTaylor.surface(procedural, over: box,
                tolerance: tolerance, order: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): The production generic implicit
            // C4 and silhouette consumers need original procedural rail C4 and
            // higher rolling-ball composition. Until their lower owner supplies
            // those source jets, this branch propagates an explicit failure.
            throw failure(tolerance, "Original procedural higher surface authority is not yet available.")
        }
    }

    private static func hull(_ first: SurfaceAreaIntervalTaylorVectorJet,
        _ second: SurfaceAreaIntervalTaylorVectorJet, order: Int, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func coordinate(_ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: tolerance, using: &execution)
            for total in 0...order { for u in 0...total {
                let v = total - u; try execution.consumeWork(1)
                let lhs = try a.coefficient(u, v), rhs = try b.coefficient(u, v)
                try result.set(.init(lower: min(lhs.lower, rhs.lower), upper: max(lhs.upper, rhs.upper)), u, v)
            } }
            return result
        }
        return try .init(x: coordinate(first.x, second.x), y: coordinate(first.y, second.y), z: coordinate(first.z, second.z))
    }
    private static func failure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
}
