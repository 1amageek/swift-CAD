import CADCore

/// Original higher source jets shared by implicit-curve and silhouette algorithms.
package struct OriginalSurfaceHigherJetProvider {
    package static func intervalTaylorJet(of source: Surface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, throughOrder order: Int,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int = 32) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard order >= 4, (0...32).contains(maximumAlgebraicDepth), maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original higher surface jets need order four or higher and caller span admission.")
        }
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        if case .procedural = source, remainingSourceDepth == 0 {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original higher surface source exhausted caller depth.")
        }
        if let analytic = try SurfaceSilhouetteAnalyticTaylor.surface(source, over: box,
            tolerance: tolerance, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage) { return analytic }
        switch source {
        case .bSpline(let surface):
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
            if let consumeStorage {
                spans = try prepared.originalNativeSpans(over: box, tolerance: tolerance,
                    maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: consumeWork,
                    consumeStorage: consumeStorage)
            } else {
                spans = try prepared.originalNativeSpans(over: box, tolerance: tolerance,
                    maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: consumeWork)
            }
            guard !spans.isEmpty else { throw failure(tolerance, "Original higher native chart has no span cover.") }
            if spans.count > 1 {
                try OriginalSurfaceNativeHigherContinuity.prove(source: surface, spans: spans,
                    over: box, throughOrder: order, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
            }
            var result: SurfaceAreaIntervalTaylorVectorJet?
            for span in spans {
                let local = try SurfaceParameterBox(
                    u: ScalarInterval(lower: max(box.u.lower, span.uBounds.lower), upper: min(box.u.upper, span.uBounds.upper)),
                    v: ScalarInterval(lower: max(box.v.lower, span.vBounds.lower), upper: min(box.v.upper, span.vBounds.upper)))
                let receipt = try span.originalCoefficientReceipt(overClosedBox: local,
                    on: surface, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
                    order: order, consumeWork: consumeWork, consumeStorage: consumeStorage)
                let value = try higher.intervalTaylorJet(using: receipt, consumeWork: consumeWork, consumeStorage: consumeStorage)
                result = try result.map { try hull($0, value, order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage) } ?? value
            }
            guard let result else { throw failure(tolerance, "Original higher native cover did not publish a value.") }
            return result
        case .procedural(.offset(let offset)):
            var base = offset.source
            var distances: [Double] = []
            var chainDepth = remainingSourceDepth - 1
            if offset.distance != 0 {
                try consumeWork(); try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, consumeStorage: consumeStorage)
                distances.append(offset.distance)
            }
            while case .procedural(.offset(let inner)) = base {
                guard chainDepth > 0 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Original higher offset chain exhausted the caller source depth.")
                }
                try consumeWork(); chainDepth -= 1
                if inner.distance != 0 {
                    try consumeWork(); try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, consumeStorage: consumeStorage)
                    distances.append(inner.distance)
                }
                base = inner.source
            }
            if !distances.isEmpty, case .bSpline(let native) = base {
                distances.reverse()
                return try OriginalNativePoleOffsetHigherJet.intervalTaylorJet(source: native,
                    distances: distances, over: box, throughOrder: order,
                    maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            let next = order.addingReportingOverflow(offset.distance == 0 ? 0 : 1)
            guard !next.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original higher offset derivative order overflows.")
            }
            let original = try intervalTaylorJet(of: offset.source, over: box, tolerance: tolerance,
                throughOrder: next.partialValue, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            if offset.distance == 0 { return original }
            try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, consumeStorage: consumeStorage)
            return try SurfaceAreaOffsetTaylorComposition(distances: [offset.distance])
                .intervalTaylorJet(from: original, translation: nil, requestedResultOrder: order,
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .procedural(.originalAngularTransport(let image)):
            return try image.intervalTaylorJet(over: box, throughOrder: order,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .procedural(.originalImage(let image)):
            let nativeBox = try image.nativeBox(box, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            let original = try intervalTaylorJet(of: image.source, over: nativeBox,
                tolerance: tolerance, throughOrder: order, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            let gu = try image.uParameterGain.interval(), gv = try image.vParameterGain.interval()
            func coordinate(_ scalar: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
                var mapped = try SurfaceAreaIntervalTaylorScalarJet(order: order,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                var uScale = OutwardScalarInterval.exact(1)
                for u in 0...order {
                    var scale = uScale
                    for v in 0...(order - u) {
                        try consumeWork(); try mapped.set(scalar.coefficient(image.swapAxes ? v : u, image.swapAxes ? u : v) * scale, u, v)
                        scale = scale * gv
                    }
                    uScale = uScale * gu
                }
                return mapped
            }
            let x = try coordinate(original.x), y = try coordinate(original.y), z = try coordinate(original.z)
            func transformed(_ a: Double, _ b: Double, _ c: Double, _ translation: Double)
                throws -> SurfaceAreaIntervalTaylorScalarJet {
                try x.scaled(by: .exact(a), consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(y.scaled(by: .exact(b), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(z.scaled(by: .exact(c), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(.constant(.exact(translation), order: order, tolerance: tolerance,
                        consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            let t = image.transform
            return try .init(x: transformed(t.basisX.x, t.basisY.x, t.basisZ.x, t.translation.x),
                y: transformed(t.basisX.y, t.basisY.y, t.basisZ.y, t.translation.y),
                z: transformed(t.basisX.z, t.basisY.z, t.basisZ.z, t.translation.z))
        case .procedural(.originalAffineWord(let image)):
            if let coefficients = image.harmonicCoefficients {
                return try coefficients.intervalTaylorJet(over: box, throughOrder: order,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            let sourceTolerance = try image.sourceCalculationTolerance(tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            let original = try intervalTaylorJet(of: image.source, over: box,
                tolerance: sourceTolerance, throughOrder: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            let transported = try withoutActuallyEscaping(consumeWork) { borrowed in
                var usage = OriginalSurfaceNativeHigherContinuity.Usage(consume: borrowed,
                    maximumDepth: maximumSubdivisionDepth, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
                return try OriginalAffineWordJetTransport.applying(image.preparedWord,
                    to: original, usage: &usage)
            }
            return try transported.retagTolerance(to: tolerance)
        case .procedural(.originalDrafted(let drafted)):
            return try drafted.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .procedural(.originalPlaneDerivative(let constrained)):
            return try constrained.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .procedural(.originalBoundaryCorrected(let corrected)):
            return try corrected.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .procedural(.originalCoons(let coons)):
            return try coons.intervalTaylorJet(over: box, throughOrder: order,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth)
        case .procedural(.originalRevolution(let revolution)):
            return try OriginalRevolutionSurfaceHigherTaylor.surface(revolution, over: box,
                tolerance: tolerance, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth)
        case .procedural(let procedural):
            return try OriginalProceduralSurfaceHigherTaylor.surface(procedural, over: box,
                tolerance: tolerance, order: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
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
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func coordinate(_ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            for total in 0...order { for u in 0...total {
                let v = total - u; try consumeWork()
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
