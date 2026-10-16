import CADCore

/// Exact original graph/pcurve elimination sharing the caller's complete ledger.
public struct OriginalSurfaceSilhouetteTrimPartitionProducer: SurfaceSilhouetteTrimPartitionProviding {
    public init() {}

    public func partition(curve: OriginalSurfaceSilhouetteCurve,
        boundary: OriginalSurfaceSilhouetteBoundary,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteTrimPartition {
        return try curve.queryContext.withExecution(using: &execution) { execution in
        try GeometryStructuralComparisonWork.charge(surface: boundary.surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: curve.surface, using: &execution)
        guard curve.surface == boundary.surface, curve.certificationTolerance == boundary.tolerance else {
            throw rationalAlgebraFailure("Original silhouette trim sources require the same surface and tolerance authority.")
        }
        let authority = try curve.originalTrimGraphAuthority()
        let spans = try OriginalRationalSilhouetteBoundarySegment.extract(boundary.curve,
            tolerance: boundary.tolerance, usage: &execution)
        var context = try authority.ramified?.original.germ.strictTransform.context
            ?? authority.fieldPolynomial?.context ?? OriginalSingularFieldContext(usage: &execution)
        let (start, last, slope) = try traversal(curve: curve, authority: authority,
            context: &context, using: &execution)
        var events: [SurfaceSilhouetteTrimPartition.Event] = []
        var overlaps: [SurfaceSilhouetteTrimPartition.Overlap] = []
        var nativeCuts: [SurfaceSilhouetteTrimEndpoint] = []
        try RationalAlgebraStorage.retain(2, of: SurfaceSilhouetteTrimEndpoint.self, usage: &execution)
        if authority.image != nil || authority.orderedImage != nil || authority.ramified != nil {
            nativeCuts.append(try .init(try .constant(.zero, in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), depth: context.depth, using: &execution))
            nativeCuts.append(try .init(try .constant(.one, in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), depth: context.depth, using: &execution))
        } else { nativeCuts.append(try .init(start, depth: context.depth, using: &execution)); nativeCuts.append(try .init(last, depth: context.depth, using: &execution)) }

        for span in spans {
            try processSpan(span, curve: curve, authority: authority, context: &context,
                start: start, last: last, slope: slope, events: &events,
                overlaps: &overlaps, nativeCuts: &nativeCuts, using: &execution)
        }
        return try publishedPartition(curve: curve, boundary: boundary, nativeCuts: nativeCuts,
            events: events, overlaps: overlaps, using: &execution)
    
        }
    }

    private typealias Authority = (polynomial: ExactBivariatePolynomial?, fieldPolynomial: OriginalSingularFieldPlanePolynomial?, image: SurfaceSilhouetteFreeParameterImage?, orderedImage: SurfaceSilhouetteOrderedFreeParameterImage?, cusp: SurfaceSilhouetteCuspParameterImage?, ramified: SurfaceSilhouetteRamifiedParameterImage?)

    @inline(never)
    private func originalFreeParameter(
        t: OriginalSingularFieldElement, originalU: OriginalSingularFieldElement,
        originalV: OriginalSingularFieldElement, curve: OriginalSurfaceSilhouetteCurve,
        ramifiedMap: OriginalRamifiedSilhouetteBoundaryMap?, authority: Authority,
        start: OriginalSingularFieldElement, last: OriginalSingularFieldElement,
        using execution: inout OriginalQueryExecution
    ) throws -> OriginalSingularFieldElement? {
        let originalFree: OriginalSingularFieldElement
        if let map = ramifiedMap {
            guard let local = try map.originalParameter(at: t, originalU: originalU, originalV: originalV, usage: &execution) else { return nil }
            originalFree = local
        } else if let cusp = authority.cusp {
            let mapU = try polynomial(cusp.cusp.u, in: t.context, usage: &execution)
            let mapV = try polynomial(cusp.cusp.v, in: t.context, usage: &execution)
            let first = try mapU.subtracting(.init(context: t.context, coefficients: [originalU],
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            let second = try mapV.subtracting(.init(context: t.context, coefficients: [originalV],
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            let common = try OriginalSingularFieldPolynomial.gcd(first, second,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            if common.degree <= 0 { return nil }
            let roots = try OriginalSingularFieldRoot.allRealRoots(common,
                inheritedDepth: t.context.depth, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            var selected: OriginalSingularFieldElement?
            for root in roots {
                let q = try root.value(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                let lower = try start.embedded(in: q.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                let upper = try last.embedded(in: q.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                if case .negative = try q.subtracting(lower, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { continue }
                if case .positive = try q.subtracting(upper, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { continue }
                if case .some = selected {
                    throw rationalAlgebraFailure("Original injective cusp map retained more than one source preimage.")
                }
                selected = q
            }
            guard let q = selected else { return nil }
            originalFree = q
        } else { originalFree = curve.freeCoordinate == .u ? originalU : originalV }
        return originalFree
    }

    @inline(never)
    private func admitted(
        _ t: OriginalSingularFieldElement,
        fractionImage: OriginalRationalSilhouetteBoundarySegment.FractionImage?,
        w: OriginalSingularFieldPolynomial, u: OriginalSingularFieldPolynomial,
        v: OriginalSingularFieldPolynomial, curve: OriginalSurfaceSilhouetteCurve,
        ramifiedMap: OriginalRamifiedSilhouetteBoundaryMap?, authority: Authority,
        start: OriginalSingularFieldElement, last: OriginalSingularFieldElement,
        slope: OriginalSingularFieldElement,
        using execution: inout OriginalQueryExecution
    ) throws -> (native: SurfaceSilhouetteTrimEndpoint, fraction: SurfaceSilhouetteTrimEndpoint)? {

        let originalBoundaryFraction: OriginalSingularFieldElement
        let fractionDepth: Int
        if let image = fractionImage {
            let first = try image.start.embedded(in: t.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            let gain = try image.gain.embedded(in: t.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            originalBoundaryFraction = try first.adding(gain.multiplied(by: t,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            fractionDepth = max(image.sourceDepth, t.context.depth)
            if case .negative = try originalBoundaryFraction.sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { return nil }
            let one = try OriginalSingularFieldElement.constant(.one, in: t.context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            if case .positive = try originalBoundaryFraction.subtracting(one, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { return nil }
        } else { originalBoundaryFraction = t; fractionDepth = t.context.depth }
        let denominator = try w.evaluated(at: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        guard case .positive = try denominator.sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) else {
            throw rationalAlgebraFailure("Original pcurve event lost its positive native denominator.")
        }
        let originalU = try u.evaluated(at: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            .divided(by: denominator, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let originalV = try v.evaluated(at: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            .divided(by: denominator, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        for (coordinate, bounds) in [(originalU, curve.chart.u), (originalV, curve.chart.v)] {
            let low = try OriginalSingularFieldElement.constant(.originalDouble(bounds.lower, usage: &execution),
                in: coordinate.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            let high = try OriginalSingularFieldElement.constant(.originalDouble(bounds.upper, usage: &execution),
                in: coordinate.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            if case .negative = try coordinate.subtracting(low, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { return nil }
            if case .positive = try coordinate.subtracting(high, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { return nil }
        }
        guard let originalFree = try originalFreeParameter(t: t, originalU: originalU,
            originalV: originalV, curve: curve, ramifiedMap: ramifiedMap, authority: authority,
            start: start, last: last, using: &execution) else { return nil }
        let offset = try originalFree.subtracting(start.embedded(in: originalFree.context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let normalized = try offset.divided(by: slope.embedded(in: originalFree.context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        if case .negative = try normalized.sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { return nil }
        let one = try OriginalSingularFieldElement.constant(.one, in: originalFree.context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        if case .positive = try normalized.subtracting(one, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { return nil }
        let native = authority.image == nil && authority.ramified == nil ? originalFree : normalized
        try RationalAlgebraStorage.retain(1,
            of: (SurfaceSilhouetteTrimEndpoint, SurfaceSilhouetteTrimEndpoint).self, usage: &execution)
        return (try .init(native, depth: originalFree.context.depth, using: &execution),
            try .init(originalBoundaryFraction, depth: fractionDepth, using: &execution))
    }

    @inline(never)
    private func station(
        _ endpoint: OriginalSingularFieldEndpoint, context: OriginalSingularFieldContext,
        using execution: inout OriginalQueryExecution
    ) throws -> OriginalSingularFieldElement {

        switch endpoint {
        case .authored(let value): return try .constant(value, in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        case .algebraic(let root): return try root.value(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        }
    }

    @inline(never)
    private func addRoots(
        _ source: OriginalSingularFieldPolynomial, context: OriginalSingularFieldContext,
        span: OriginalRationalSilhouetteBoundarySegment, cuts: inout [OriginalSingularFieldEndpoint],
        using execution: inout OriginalQueryExecution
    ) throws {

        if source.isZero || source.degree <= 0 { return }
        let roots = try OriginalSingularFieldRoot.allRealRoots(source, inheritedDepth: context.depth,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        for root in roots {
            var candidate = OriginalSingularFieldEndpoint.algebraic(root)
            var low = OriginalSingularFieldEndpoint.authored(span.lower)
            var high = OriginalSingularFieldEndpoint.authored(span.upper)
            guard try OriginalSingularFieldEndpoint.compare(&candidate, &low,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) >= 0,
                try OriginalSingularFieldEndpoint.compare(&candidate, &high,
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) <= 0 else { continue }
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldEndpoint.self, usage: &execution)
            cuts.append(candidate)
        }
    }

    @inline(never)
    private func originalEquation(
        ramifiedMap: OriginalRamifiedSilhouetteBoundaryMap?, authority: Authority,
        span: OriginalRationalSilhouetteBoundarySegment, context: OriginalSingularFieldContext,
        u: OriginalSingularFieldPolynomial, v: OriginalSingularFieldPolynomial,
        w: OriginalSingularFieldPolynomial,
        using execution: inout OriginalQueryExecution
    ) throws -> OriginalSingularFieldPolynomial {
        let original: OriginalSingularFieldPolynomial
        if let map = ramifiedMap { original = map.strictTransform.numerator }
        else if let equation = authority.polynomial {
            original = try polynomial(span.substituted(equation, usage: &execution), in: context, usage: &execution)
        } else if let equation = authority.fieldPolynomial {
            let first = try OriginalFieldUnivariateRationalFunction(numerator: u, denominator: w,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            let second = try OriginalFieldUnivariateRationalFunction(numerator: v, denominator: w,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            original = try OriginalFieldUnivariateRationalFunction.composed(equation.embedded(in: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), withU: first, v: second,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution).numerator
        } else { throw rationalAlgebraFailure("Original trim branch has no retained zero equation.") }
        return original
    }

    @inline(never)
    private func originalCuts(
        original: OriginalSingularFieldPolynomial, fractionImage: OriginalRationalSilhouetteBoundarySegment.FractionImage?,
        u: OriginalSingularFieldPolynomial, v: OriginalSingularFieldPolynomial,
        w: OriginalSingularFieldPolynomial, free: OriginalSingularFieldPolynomial,
        context: OriginalSingularFieldContext, span: OriginalRationalSilhouetteBoundarySegment,
        curve: OriginalSurfaceSilhouetteCurve, ramifiedMap: OriginalRamifiedSilhouetteBoundaryMap?,
        authority: Authority, start: OriginalSingularFieldElement, last: OriginalSingularFieldElement,
        using execution: inout OriginalQueryExecution
    ) throws -> [OriginalSingularFieldEndpoint] {
        var cuts: [OriginalSingularFieldEndpoint] = [.authored(span.lower), .authored(span.upper)]
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldEndpoint.self, usage: &execution)

        try addRoots(original, context: context, span: span, cuts: &cuts, using: &execution)
        if let image = fractionImage {
            for side in 0..<2 {
                let bound = try OriginalSingularFieldElement.constant(side == 0 ? .zero : .one,
                    in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                let start = try image.start.subtracting(bound, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &execution)
                try addRoots(.init(context: context, coefficients: [start, image.gain],
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            }
        }
        // Every chart edge and exact normalized traversal end participates.
        // These cuts also restrict continuous overlaps to their owning chart.
        for (coordinate, bounds) in [(u, curve.chart.u), (v, curve.chart.v)] {
            for bound in [bounds.lower, bounds.upper] {
                let scalar = try OriginalSingularFieldElement.constant(.originalDouble(bound, usage: &execution),
                    in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                try addRoots(coordinate.subtracting(scaled(w, by: scalar, usage: &execution),
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            }
        }
        if let map = ramifiedMap {
            for (coordinate, bounds) in [(map.localU, map.chart.localDomain.u), (map.localV, map.chart.localDomain.v)] {
                try addRoots(coordinate.denominator, context: context, span: span, cuts: &cuts, using: &execution)
                for bound in [bounds.lower, bounds.upper] {
                    let value = try OriginalSingularFieldElement.constant(.originalDouble(bound, usage: &execution),
                        in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    try addRoots(coordinate.numerator.subtracting(scaled(coordinate.denominator, by: value, usage: &execution),
                        maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
                }
            }
            let localFree = map.chart.freeAlongU ? map.localU : map.localV
            for bound in [start, last] {
                try addRoots(localFree.numerator.subtracting(scaled(localFree.denominator, by: bound, usage: &execution),
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            }
            // Original center incidence includes exceptional inverse denominators.
            try addRoots(u.subtracting(scaled(w, by: map.centerU, usage: &execution),
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            try addRoots(v.subtracting(scaled(w, by: map.centerV, usage: &execution),
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            if original.isZero {
                try addRoots(localFree.numerator.differentiated(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .multiplied(by: localFree.denominator, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .subtracting(localFree.numerator.multiplied(by: localFree.denominator.differentiated(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution),
                        maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            }
        } else if let cusp = authority.cusp {
            let mapU = try polynomial(cusp.cusp.u, in: context, usage: &execution)
            let mapV = try polynomial(cusp.cusp.v, in: context, usage: &execution)
            for bound in [start, last] {
                let originalU = try mapU.evaluated(at: bound, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                let originalV = try mapV.evaluated(at: bound, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                try addRoots(u.subtracting(scaled(w, by: originalU, usage: &execution),
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
                try addRoots(v.subtracting(scaled(w, by: originalV, usage: &execution),
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            }
        } else {
            for bound in [start, last] {
                try addRoots(free.subtracting(scaled(w, by: bound, usage: &execution),
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), context: context, span: span, cuts: &cuts, using: &execution)
            }
        }
        if original.isZero {
            // Every zero-speed native traversal is a root of an original UV
            // derivative. The cusp center is included even at stationary maps.
            for coordinate in authority.cusp == nil ? [free] : [u, v] {
                let derivative = try coordinate.differentiated(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .multiplied(by: w, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .subtracting(coordinate.multiplied(by: w.differentiated(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution),
                        maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                try addRoots(derivative, context: context, span: span, cuts: &cuts, using: &execution)
            }
        }
        return cuts
    }

    @inline(never)
    private func processSpan(
        _ span: OriginalRationalSilhouetteBoundarySegment,
        curve: OriginalSurfaceSilhouetteCurve, authority: Authority,
        context: inout OriginalSingularFieldContext, start: OriginalSingularFieldElement,
        last: OriginalSingularFieldElement, slope: OriginalSingularFieldElement,
        events: inout [SurfaceSilhouetteTrimPartition.Event],
        overlaps: inout [SurfaceSilhouetteTrimPartition.Overlap],
        nativeCuts: inout [SurfaceSilhouetteTrimEndpoint],
        using execution: inout OriginalQueryExecution
    ) throws {

        try execution.consumeWork(1)
        let fractionImage: OriginalRationalSilhouetteBoundarySegment.FractionImage?
        if let image = span.originalFractionImage {
            var transport = OriginalSingularFieldTransport()
            context = try transport.importing(image.start.context, into: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            fractionImage = try .init(start: transport.applying(to: image.start, in: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution),
                gain: transport.applying(to: image.gain, in: context,
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), sourceDepth: image.sourceDepth)
        } else { fractionImage = nil }
        let u = try polynomial(span.u, in: context, usage: &execution)
        let v = try polynomial(span.v, in: context, usage: &execution)
        let w = try polynomial(span.weight, in: context, usage: &execution)
        let ramifiedMap: OriginalRamifiedSilhouetteBoundaryMap?
        if let ramified = authority.ramified {
            ramifiedMap = try .init(image: ramified, u: u, v: v, weight: w, usage: &execution)
        } else { ramifiedMap = nil }
        let original = try originalEquation(ramifiedMap: ramifiedMap, authority: authority,
            span: span, context: context, u: u, v: v, w: w, using: &execution)
        let free = curve.freeCoordinate == .u ? u : v
        let cuts = try originalCuts(original: original, fractionImage: fractionImage,
            u: u, v: v, w: w, free: free, context: context, span: span, curve: curve,
            ramifiedMap: ramifiedMap, authority: authority, start: start, last: last, using: &execution)
        let ordered = try ordered(cuts, usage: &execution)


        for endpoint in ordered {
            let t = try station(endpoint, context: context, using: &execution)
            let equationZero: Bool
            if case .zero = try original.evaluated(at: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { equationZero = true }
            else { equationZero = false }
            let originalCenter: Bool
            if let map = ramifiedMap {
                let first = try u.subtracting(scaled(w, by: map.centerU, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                let second = try v.subtracting(scaled(w, by: map.centerV, usage: &execution), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                if case .zero = try first.evaluated(at: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution),
                    case .zero = try second.evaluated(at: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                    .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) { originalCenter = true }
                else { originalCenter = false }
            } else { originalCenter = false }
            if equationZero || originalCenter, let point = try admitted(t, fractionImage: fractionImage, w: w, u: u, v: v, curve: curve, ramifiedMap: ramifiedMap, authority: authority, start: start, last: last, slope: slope, using: &execution) {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimPartition.Event.self, usage: &execution)
                events.append(.init(parameter: point.native, boundaryFraction: point.fraction, originalBoundarySpan: span.ordinal))
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &execution)
                nativeCuts.append(point.native)
            }
        }
        if original.isZero, ordered.count > 1 {
            for index in 0..<(ordered.count - 1) {
                var low = ordered[index], high = ordered[index + 1]
                let witness = try OriginalSingularFieldEndpoint.between(&low, &high,
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                let t = try OriginalSingularFieldElement.constant(witness, in: context,
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                guard case .some = try admitted(t, fractionImage: fractionImage, w: w, u: u, v: v, curve: curve, ramifiedMap: ramifiedMap, authority: authority, start: start, last: last, slope: slope, using: &execution) else { continue }
                guard let first = try admitted(station(low, context: context, using: &execution), fractionImage: fractionImage, w: w, u: u, v: v, curve: curve, ramifiedMap: ramifiedMap, authority: authority, start: start, last: last, slope: slope, using: &execution),
                    let last = try admitted(station(high, context: context, using: &execution), fractionImage: fractionImage, w: w, u: u, v: v, curve: curve, ramifiedMap: ramifiedMap, authority: authority, start: start, last: last, slope: slope, using: &execution) else {
                    throw rationalAlgebraFailure("Original coincident sector contradicts its complete edge partition.")
                }
                let comparison = try first.native.compare(to: last.native, using: &execution)
                if comparison == 0 { continue }
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimPartition.Overlap.self, usage: &execution)
                overlaps.append(.init(lower: comparison < 0 ? first.native : last.native,
                    upper: comparison < 0 ? last.native : first.native,
                    boundaryLowerFraction: first.fraction, boundaryUpperFraction: last.fraction,
                    originalBoundarySpan: span.ordinal))
            }
        }
    }

    @inline(never)
    private func traversal(
        curve: OriginalSurfaceSilhouetteCurve, authority: Authority,
        context: inout OriginalSingularFieldContext,
        using execution: inout OriginalQueryExecution
    ) throws -> (start: OriginalSingularFieldElement, last: OriginalSingularFieldElement, slope: OriginalSingularFieldElement) {
        func value(_ endpoint: ExactMonotoneGraphEndpoint,
            in owner: OriginalSingularFieldContext, usage execution: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
            switch endpoint {
            case .authored(let value): return try .constant(value, in: owner, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            case .algebraic(let root):
                return try OriginalSingularFieldRoot.retaining(root, in: owner,
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution).value(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            }
        }
        let freeDomain = authority.cusp?.nativeCover ?? (curve.freeCoordinate == .u ? curve.chart.u : curve.chart.v)
        let startEndpoint: ExactMonotoneGraphEndpoint, endEndpoint: ExactMonotoneGraphEndpoint
        if let image = authority.image { startEndpoint = image.start; endEndpoint = image.end }
        else {
            startEndpoint = try .authored(.originalDouble(freeDomain.lower, usage: &execution))
            endEndpoint = try .authored(.originalDouble(freeDomain.upper, usage: &execution))
        }
        let first: OriginalSingularFieldElement, last: OriginalSingularFieldElement
        if let ordered = authority.orderedImage {
            var transport = OriginalSingularFieldTransport()
            context = try transport.importing(ordered.start.original.context, into: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            first = try transport.applying(to: ordered.start.original, in: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            last = try transport.applying(to: ordered.end.original, in: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        } else if let ramified = authority.ramified {
            var transport = OriginalSingularFieldTransport()
            func endpoint(_ endpoint: OriginalSingularFieldEndpoint, usage execution: inout OriginalQueryExecution)
                throws -> OriginalSingularFieldElement {
                switch endpoint {
                case .authored(let value): return try .constant(value, in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                case .algebraic(let root): return try OriginalSingularFieldRoot.retaining(root, in: context,
                    maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution).value(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                }
            }
            if let retained = ramified.retainedStart {
                context = try transport.importing(retained.context, into: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                first = try transport.applying(to: retained, in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            } else { first = try endpoint(ramified.start, usage: &execution); context = first.context }
            if let retained = ramified.retainedEnd {
                context = try transport.importing(retained.context, into: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
                last = try transport.applying(to: retained, in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            } else { last = try endpoint(ramified.end, usage: &execution); context = last.context }
        } else {
            first = try value(startEndpoint, in: context, usage: &execution); context = first.context
            last = try value(endEndpoint, in: context, usage: &execution); context = last.context
        }
        let start = try first.embedded(in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let slope = try last.subtracting(start, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        guard case .positive = try slope.sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) else {
            throw rationalAlgebraFailure("Original trim graph traversal has no proved positive free-coordinate image.")
        }
        return (start, last, slope)
    }

    @inline(never)
    private func publishedPartition(
        curve: OriginalSurfaceSilhouetteCurve, boundary: OriginalSurfaceSilhouetteBoundary,
        nativeCuts: [SurfaceSilhouetteTrimEndpoint], events: [SurfaceSilhouetteTrimPartition.Event],
        overlaps: [SurfaceSilhouetteTrimPartition.Overlap],
        using execution: inout OriginalQueryExecution
    ) throws -> SurfaceSilhouetteTrimPartition {
        let orderedNative = try orderedNative(nativeCuts, usage: &execution)
        var sectors: [SurfaceSilhouetteTrimPartition.Sector] = []
        if orderedNative.count > 1 {
            for index in 0..<(orderedNative.count - 1) {
                let lower = orderedNative[index], upper = orderedNative[index + 1]
                var coincident = false
                for overlap in overlaps {
                    if try lower.compare(to: overlap.lower, using: &execution) >= 0,
                        try upper.compare(to: overlap.upper, using: &execution) <= 0 { coincident = true; break }
                }
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimPartition.Sector.self, usage: &execution)
                sectors.append(.init(lower: lower, upper: upper, kind: coincident ? .coincident : .eventFree))
            }
        }
        return .init(originalCurve: curve, originalBoundary: boundary, events: events, overlaps: overlaps, sectors: sectors)
    }

    private func polynomial(_ value: ExactBivariatePolynomial, in context: OriginalSingularFieldContext,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldPolynomial {
        guard value.vDegree <= 0 else { throw rationalAlgebraFailure("Original pcurve fraction polynomial retained a foreign axis.") }
        let count = max(0, try rationalAlgebraCount(max(0, value.uDegree), value.isZero ? 0 : 1))
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for (power, coefficient) in try value.orderedTerms(usage: &usage) {
            coefficients[power.u] = try .constant(coefficient, in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        return try .init(context: context, coefficients: coefficients, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }
    private func scaled(_ polynomial: OriginalSingularFieldPolynomial, by value: OriginalSingularFieldElement,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldPolynomial {
        try RationalAlgebraStorage.retain(polynomial.coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(polynomial.coefficients.count)
        for coefficient in polynomial.coefficients {
            coefficients.append(try coefficient.multiplied(by: value, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage))
        }
        return try .init(context: polynomial.context, coefficients: coefficients, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }
    private func ordered(_ input: [OriginalSingularFieldEndpoint], usage: inout OriginalQueryExecution)
        throws -> [OriginalSingularFieldEndpoint] {
        try RationalAlgebraStorage.retain(input.count, of: OriginalSingularFieldEndpoint.self, usage: &usage)
        var output: [OriginalSingularFieldEndpoint] = []; output.reserveCapacity(input.count)
        for original in input {
            var value = original, index = 0, duplicate = false
            while index < output.count {
                var other = output[index]
                let order = try OriginalSingularFieldEndpoint.compare(&value, &other,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                output[index] = other
                if order == 0 { duplicate = true; break }
                if order < 0 { break }; index += 1
            }
            if !duplicate { output.insert(value, at: index) }
        }
        return output
    }
    private func orderedNative(_ input: [SurfaceSilhouetteTrimEndpoint], usage: inout OriginalQueryExecution)
        throws -> [SurfaceSilhouetteTrimEndpoint] {
        try RationalAlgebraStorage.retain(input.count, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
        var output: [SurfaceSilhouetteTrimEndpoint] = []; output.reserveCapacity(input.count)
        for value in input {
            var index = 0, duplicate = false
            while index < output.count {
                let order = try value.compare(to: output[index], using: &usage)
                if order == 0 { duplicate = true; break }
                if order < 0 { break }; index += 1
            }
            if !duplicate { output.insert(value, at: index) }
        }
        return output
    }
}
