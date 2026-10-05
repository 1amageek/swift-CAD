import CADCore

/// Exact original graph/pcurve elimination sharing the caller's complete ledger.
public struct OriginalSurfaceSilhouetteTrimPartitionProducer: SurfaceSilhouetteTrimPartitionProviding {
    public init() {}

    public func partition(curve: OriginalSurfaceSilhouetteCurve,
        boundary: OriginalSurfaceSilhouetteBoundary,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteTrimPartition {
        try GeometryStructuralComparisonWork.charge(surface: boundary.surface, using: { try usage.consumeWork($0) })
        try GeometryStructuralComparisonWork.charge(surface: curve.surface, using: { try usage.consumeWork($0) })
        guard curve.surface == boundary.surface, curve.certificationTolerance == boundary.tolerance else {
            throw rationalAlgebraFailure("Original silhouette trim sources require the same surface and tolerance authority.")
        }
        let authority = try curve.originalTrimGraphAuthority()
        let spans = try OriginalRationalSilhouetteBoundarySegment.extract(boundary.curve,
            tolerance: boundary.tolerance, usage: &usage)
        var context = try authority.ramified?.original.germ.strictTransform.context
            ?? authority.fieldPolynomial?.context ?? OriginalSingularFieldContext(usage: &usage)
        func value(_ endpoint: ExactMonotoneGraphEndpoint,
            in owner: OriginalSingularFieldContext, usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldElement {
            switch endpoint {
            case .authored(let value): return try .constant(value, in: owner, maximumDepth: usage.maximumDepth, usage: &usage)
            case .algebraic(let root):
                return try OriginalSingularFieldRoot.retaining(root, in: owner,
                    maximumDepth: usage.maximumDepth, usage: &usage).value(maximumDepth: usage.maximumDepth, usage: &usage)
            }
        }
        let freeDomain = authority.cusp?.nativeCover ?? (curve.freeCoordinate == .u ? curve.chart.u : curve.chart.v)
        let startEndpoint: ExactMonotoneGraphEndpoint, endEndpoint: ExactMonotoneGraphEndpoint
        if let image = authority.image { startEndpoint = image.start; endEndpoint = image.end }
        else {
            startEndpoint = try .authored(.originalDouble(freeDomain.lower, usage: &usage))
            endEndpoint = try .authored(.originalDouble(freeDomain.upper, usage: &usage))
        }
        let first: OriginalSingularFieldElement, last: OriginalSingularFieldElement
        if let ordered = authority.orderedImage {
            var transport = OriginalSingularFieldTransport()
            context = try transport.importing(ordered.start.original.context, into: context,
                maximumDepth: usage.maximumDepth, usage: &usage)
            first = try transport.applying(to: ordered.start.original, in: context,
                maximumDepth: usage.maximumDepth, usage: &usage)
            last = try transport.applying(to: ordered.end.original, in: context,
                maximumDepth: usage.maximumDepth, usage: &usage)
        } else if let ramified = authority.ramified {
            var transport = OriginalSingularFieldTransport()
            func endpoint(_ endpoint: OriginalSingularFieldEndpoint, usage: inout SurfaceSilhouetteUsage)
                throws -> OriginalSingularFieldElement {
                switch endpoint {
                case .authored(let value): return try .constant(value, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
                case .algebraic(let root): return try OriginalSingularFieldRoot.retaining(root, in: context,
                    maximumDepth: usage.maximumDepth, usage: &usage).value(maximumDepth: usage.maximumDepth, usage: &usage)
                }
            }
            if let retained = ramified.retainedStart {
                context = try transport.importing(retained.context, into: context, maximumDepth: usage.maximumDepth, usage: &usage)
                first = try transport.applying(to: retained, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
            } else { first = try endpoint(ramified.start, usage: &usage); context = first.context }
            if let retained = ramified.retainedEnd {
                context = try transport.importing(retained.context, into: context, maximumDepth: usage.maximumDepth, usage: &usage)
                last = try transport.applying(to: retained, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
            } else { last = try endpoint(ramified.end, usage: &usage); context = last.context }
        } else {
            first = try value(startEndpoint, in: context, usage: &usage); context = first.context
            last = try value(endEndpoint, in: context, usage: &usage); context = last.context
        }
        let start = try first.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let slope = try last.subtracting(start, maximumDepth: usage.maximumDepth, usage: &usage)
        guard case .positive = try slope.sign(maximumDepth: usage.maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original trim graph traversal has no proved positive free-coordinate image.")
        }
        var events: [SurfaceSilhouetteTrimPartition.Event] = []
        var overlaps: [SurfaceSilhouetteTrimPartition.Overlap] = []
        var nativeCuts: [SurfaceSilhouetteTrimEndpoint] = []
        try RationalAlgebraStorage.retain(2, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
        if authority.image != nil || authority.orderedImage != nil || authority.ramified != nil {
            nativeCuts.append(.init(try .constant(.zero, in: context, maximumDepth: usage.maximumDepth, usage: &usage), depth: context.depth))
            nativeCuts.append(.init(try .constant(.one, in: context, maximumDepth: usage.maximumDepth, usage: &usage), depth: context.depth))
        } else { nativeCuts.append(.init(start, depth: context.depth)); nativeCuts.append(.init(last, depth: context.depth)) }

        for span in spans {
            try usage.consumeWork()
            let fractionImage: OriginalRationalSilhouetteBoundarySegment.FractionImage?
            if let image = span.originalFractionImage {
                var transport = OriginalSingularFieldTransport()
                context = try transport.importing(image.start.context, into: context,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                fractionImage = try .init(start: transport.applying(to: image.start, in: context,
                    maximumDepth: usage.maximumDepth, usage: &usage),
                    gain: transport.applying(to: image.gain, in: context,
                        maximumDepth: usage.maximumDepth, usage: &usage), sourceDepth: image.sourceDepth)
            } else { fractionImage = nil }
            let u = try polynomial(span.u, in: context, usage: &usage)
            let v = try polynomial(span.v, in: context, usage: &usage)
            let w = try polynomial(span.weight, in: context, usage: &usage)
            let ramifiedMap: OriginalRamifiedSilhouetteBoundaryMap?
            if let ramified = authority.ramified {
                ramifiedMap = try .init(image: ramified, u: u, v: v, weight: w, usage: &usage)
            } else { ramifiedMap = nil }
            let original: OriginalSingularFieldPolynomial
            if let map = ramifiedMap { original = map.strictTransform.numerator }
            else if let equation = authority.polynomial {
                original = try polynomial(span.substituted(equation, usage: &usage), in: context, usage: &usage)
            } else if let equation = authority.fieldPolynomial {
                let first = try OriginalFieldUnivariateRationalFunction(numerator: u, denominator: w,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                let second = try OriginalFieldUnivariateRationalFunction(numerator: v, denominator: w,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                original = try OriginalFieldUnivariateRationalFunction.composed(equation.embedded(in: context,
                    maximumDepth: usage.maximumDepth, usage: &usage), withU: first, v: second,
                    maximumDepth: usage.maximumDepth, usage: &usage).numerator
            } else { throw rationalAlgebraFailure("Original trim branch has no retained zero equation.") }
            let free = curve.freeCoordinate == .u ? u : v
            var cuts: [OriginalSingularFieldEndpoint] = [.authored(span.lower), .authored(span.upper)]
            try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldEndpoint.self, usage: &usage)
            func addRoots(_ source: OriginalSingularFieldPolynomial, usage: inout SurfaceSilhouetteUsage) throws {
                if source.isZero || source.degree <= 0 { return }
                let roots = try OriginalSingularFieldRoot.allRealRoots(source, inheritedDepth: context.depth,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                for root in roots {
                    var candidate = OriginalSingularFieldEndpoint.algebraic(root)
                    var low = OriginalSingularFieldEndpoint.authored(span.lower)
                    var high = OriginalSingularFieldEndpoint.authored(span.upper)
                    guard try OriginalSingularFieldEndpoint.compare(&candidate, &low,
                        maximumDepth: usage.maximumDepth, usage: &usage) >= 0,
                        try OriginalSingularFieldEndpoint.compare(&candidate, &high,
                            maximumDepth: usage.maximumDepth, usage: &usage) <= 0 else { continue }
                    try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldEndpoint.self, usage: &usage)
                    cuts.append(candidate)
                }
            }
            try addRoots(original, usage: &usage)
            if let image = fractionImage {
                for side in 0..<2 {
                    let bound = try OriginalSingularFieldElement.constant(side == 0 ? .zero : .one,
                        in: context, maximumDepth: usage.maximumDepth, usage: &usage)
                    let start = try image.start.subtracting(bound, maximumDepth: usage.maximumDepth, usage: &usage)
                    try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
                    try addRoots(.init(context: context, coefficients: [start, image.gain],
                        maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                }
            }
            // Every chart edge and exact normalized traversal end participates.
            // These cuts also restrict continuous overlaps to their owning chart.
            for (coordinate, bounds) in [(u, curve.chart.u), (v, curve.chart.v)] {
                for bound in [bounds.lower, bounds.upper] {
                    let scalar = try OriginalSingularFieldElement.constant(.originalDouble(bound, usage: &usage),
                        in: context, maximumDepth: usage.maximumDepth, usage: &usage)
                    try addRoots(coordinate.subtracting(scaled(w, by: scalar, usage: &usage),
                        maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                }
            }
            if let map = ramifiedMap {
                for (coordinate, bounds) in [(map.localU, map.chart.localDomain.u), (map.localV, map.chart.localDomain.v)] {
                    try addRoots(coordinate.denominator, usage: &usage)
                    for bound in [bounds.lower, bounds.upper] {
                        let value = try OriginalSingularFieldElement.constant(.originalDouble(bound, usage: &usage),
                            in: context, maximumDepth: usage.maximumDepth, usage: &usage)
                        try addRoots(coordinate.numerator.subtracting(scaled(coordinate.denominator, by: value, usage: &usage),
                            maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                    }
                }
                let localFree = map.chart.freeAlongU ? map.localU : map.localV
                for bound in [start, last] {
                    try addRoots(localFree.numerator.subtracting(scaled(localFree.denominator, by: bound, usage: &usage),
                        maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                }
                // Original center incidence includes exceptional inverse denominators.
                try addRoots(u.subtracting(scaled(w, by: map.centerU, usage: &usage),
                    maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                try addRoots(v.subtracting(scaled(w, by: map.centerV, usage: &usage),
                    maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                if original.isZero {
                    try addRoots(localFree.numerator.differentiated(maximumDepth: usage.maximumDepth, usage: &usage)
                        .multiplied(by: localFree.denominator, maximumDepth: usage.maximumDepth, usage: &usage)
                        .subtracting(localFree.numerator.multiplied(by: localFree.denominator.differentiated(maximumDepth: usage.maximumDepth, usage: &usage),
                            maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                }
            } else if let cusp = authority.cusp {
                let mapU = try polynomial(cusp.cusp.u, in: context, usage: &usage)
                let mapV = try polynomial(cusp.cusp.v, in: context, usage: &usage)
                for bound in [start, last] {
                    let originalU = try mapU.evaluated(at: bound, maximumDepth: usage.maximumDepth, usage: &usage)
                    let originalV = try mapV.evaluated(at: bound, maximumDepth: usage.maximumDepth, usage: &usage)
                    try addRoots(u.subtracting(scaled(w, by: originalU, usage: &usage),
                        maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                    try addRoots(v.subtracting(scaled(w, by: originalV, usage: &usage),
                        maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                }
            } else {
                for bound in [start, last] {
                    try addRoots(free.subtracting(scaled(w, by: bound, usage: &usage),
                        maximumDepth: usage.maximumDepth, usage: &usage), usage: &usage)
                }
            }
            if original.isZero {
                // Every zero-speed native traversal is a root of an original UV
                // derivative. The cusp center is included even at stationary maps.
                for coordinate in authority.cusp == nil ? [free] : [u, v] {
                    let derivative = try coordinate.differentiated(maximumDepth: usage.maximumDepth, usage: &usage)
                        .multiplied(by: w, maximumDepth: usage.maximumDepth, usage: &usage)
                        .subtracting(coordinate.multiplied(by: w.differentiated(maximumDepth: usage.maximumDepth, usage: &usage),
                            maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                    try addRoots(derivative, usage: &usage)
                }
            }
            let ordered = try ordered(cuts, usage: &usage)
            func station(_ endpoint: OriginalSingularFieldEndpoint, usage: inout SurfaceSilhouetteUsage)
                throws -> OriginalSingularFieldElement {
                switch endpoint {
                case .authored(let value): return try .constant(value, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
                case .algebraic(let root): return try root.value(maximumDepth: usage.maximumDepth, usage: &usage)
                }
            }
            func admitted(_ t: OriginalSingularFieldElement, usage: inout SurfaceSilhouetteUsage)
                throws -> (native: SurfaceSilhouetteTrimEndpoint, fraction: SurfaceSilhouetteTrimEndpoint)? {
                let originalBoundaryFraction: OriginalSingularFieldElement
                let fractionDepth: Int
                if let image = fractionImage {
                    let first = try image.start.embedded(in: t.context, maximumDepth: usage.maximumDepth, usage: &usage)
                    let gain = try image.gain.embedded(in: t.context, maximumDepth: usage.maximumDepth, usage: &usage)
                    originalBoundaryFraction = try first.adding(gain.multiplied(by: t,
                        maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                    fractionDepth = max(image.sourceDepth, t.context.depth)
                    if case .negative = try originalBoundaryFraction.sign(maximumDepth: usage.maximumDepth, usage: &usage) { return nil }
                    let one = try OriginalSingularFieldElement.constant(.one, in: t.context,
                        maximumDepth: usage.maximumDepth, usage: &usage)
                    if case .positive = try originalBoundaryFraction.subtracting(one, maximumDepth: usage.maximumDepth, usage: &usage)
                        .sign(maximumDepth: usage.maximumDepth, usage: &usage) { return nil }
                } else { originalBoundaryFraction = t; fractionDepth = t.context.depth }
                let denominator = try w.evaluated(at: t, maximumDepth: usage.maximumDepth, usage: &usage)
                guard case .positive = try denominator.sign(maximumDepth: usage.maximumDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("Original pcurve event lost its positive native denominator.")
                }
                let originalU = try u.evaluated(at: t, maximumDepth: usage.maximumDepth, usage: &usage)
                    .divided(by: denominator, maximumDepth: usage.maximumDepth, usage: &usage)
                let originalV = try v.evaluated(at: t, maximumDepth: usage.maximumDepth, usage: &usage)
                    .divided(by: denominator, maximumDepth: usage.maximumDepth, usage: &usage)
                for (coordinate, bounds) in [(originalU, curve.chart.u), (originalV, curve.chart.v)] {
                    let low = try OriginalSingularFieldElement.constant(.originalDouble(bounds.lower, usage: &usage),
                        in: coordinate.context, maximumDepth: usage.maximumDepth, usage: &usage)
                    let high = try OriginalSingularFieldElement.constant(.originalDouble(bounds.upper, usage: &usage),
                        in: coordinate.context, maximumDepth: usage.maximumDepth, usage: &usage)
                    if case .negative = try coordinate.subtracting(low, maximumDepth: usage.maximumDepth, usage: &usage)
                        .sign(maximumDepth: usage.maximumDepth, usage: &usage) { return nil }
                    if case .positive = try coordinate.subtracting(high, maximumDepth: usage.maximumDepth, usage: &usage)
                        .sign(maximumDepth: usage.maximumDepth, usage: &usage) { return nil }
                }
                let originalFree: OriginalSingularFieldElement
                if let map = ramifiedMap {
                    guard let local = try map.originalParameter(at: t, originalU: originalU, originalV: originalV, usage: &usage) else { return nil }
                    originalFree = local
                } else if let cusp = authority.cusp {
                    let mapU = try polynomial(cusp.cusp.u, in: t.context, usage: &usage)
                    let mapV = try polynomial(cusp.cusp.v, in: t.context, usage: &usage)
                    let first = try mapU.subtracting(.init(context: t.context, coefficients: [originalU],
                        maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                    let second = try mapV.subtracting(.init(context: t.context, coefficients: [originalV],
                        maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                    let common = try OriginalSingularFieldPolynomial.gcd(first, second,
                        maximumDepth: usage.maximumDepth, usage: &usage)
                    if common.degree <= 0 { return nil }
                    let roots = try OriginalSingularFieldRoot.allRealRoots(common,
                        inheritedDepth: t.context.depth, maximumDepth: usage.maximumDepth, usage: &usage)
                    var selected: OriginalSingularFieldElement?
                    for root in roots {
                        let q = try root.value(maximumDepth: usage.maximumDepth, usage: &usage)
                        let lower = try start.embedded(in: q.context, maximumDepth: usage.maximumDepth, usage: &usage)
                        let upper = try last.embedded(in: q.context, maximumDepth: usage.maximumDepth, usage: &usage)
                        if case .negative = try q.subtracting(lower, maximumDepth: usage.maximumDepth, usage: &usage)
                            .sign(maximumDepth: usage.maximumDepth, usage: &usage) { continue }
                        if case .positive = try q.subtracting(upper, maximumDepth: usage.maximumDepth, usage: &usage)
                            .sign(maximumDepth: usage.maximumDepth, usage: &usage) { continue }
                        if case .some = selected {
                            throw rationalAlgebraFailure("Original injective cusp map retained more than one source preimage.")
                        }
                        selected = q
                    }
                    guard let q = selected else { return nil }
                    originalFree = q
                } else { originalFree = curve.freeCoordinate == .u ? originalU : originalV }
                let offset = try originalFree.subtracting(start.embedded(in: originalFree.context,
                    maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                let normalized = try offset.divided(by: slope.embedded(in: originalFree.context,
                    maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                if case .negative = try normalized.sign(maximumDepth: usage.maximumDepth, usage: &usage) { return nil }
                let one = try OriginalSingularFieldElement.constant(.one, in: originalFree.context,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                if case .positive = try normalized.subtracting(one, maximumDepth: usage.maximumDepth, usage: &usage)
                    .sign(maximumDepth: usage.maximumDepth, usage: &usage) { return nil }
                let native = authority.image == nil && authority.ramified == nil ? originalFree : normalized
                try RationalAlgebraStorage.retain(1,
                    of: (SurfaceSilhouetteTrimEndpoint, SurfaceSilhouetteTrimEndpoint).self, usage: &usage)
                return (.init(native, depth: originalFree.context.depth),
                    .init(originalBoundaryFraction, depth: fractionDepth))
            }
            for endpoint in ordered {
                let t = try station(endpoint, usage: &usage)
                let equationZero: Bool
                if case .zero = try original.evaluated(at: t, maximumDepth: usage.maximumDepth, usage: &usage)
                    .sign(maximumDepth: usage.maximumDepth, usage: &usage) { equationZero = true }
                else { equationZero = false }
                let originalCenter: Bool
                if let map = ramifiedMap {
                    let first = try u.subtracting(scaled(w, by: map.centerU, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                    let second = try v.subtracting(scaled(w, by: map.centerV, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                    if case .zero = try first.evaluated(at: t, maximumDepth: usage.maximumDepth, usage: &usage)
                        .sign(maximumDepth: usage.maximumDepth, usage: &usage),
                        case .zero = try second.evaluated(at: t, maximumDepth: usage.maximumDepth, usage: &usage)
                        .sign(maximumDepth: usage.maximumDepth, usage: &usage) { originalCenter = true }
                    else { originalCenter = false }
                } else { originalCenter = false }
                if equationZero || originalCenter, let point = try admitted(t, usage: &usage) {
                    try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimPartition.Event.self, usage: &usage)
                    events.append(.init(parameter: point.native, boundaryFraction: point.fraction, originalBoundarySpan: span.ordinal))
                    try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
                    nativeCuts.append(point.native)
                }
            }
            if original.isZero, ordered.count > 1 {
                for index in 0..<(ordered.count - 1) {
                    var low = ordered[index], high = ordered[index + 1]
                    let witness = try OriginalSingularFieldEndpoint.between(&low, &high,
                        maximumDepth: usage.maximumDepth, usage: &usage)
                    let t = try OriginalSingularFieldElement.constant(witness, in: context,
                        maximumDepth: usage.maximumDepth, usage: &usage)
                    guard case .some = try admitted(t, usage: &usage) else { continue }
                    guard let first = try admitted(station(low, usage: &usage), usage: &usage),
                        let last = try admitted(station(high, usage: &usage), usage: &usage) else {
                        throw rationalAlgebraFailure("Original coincident sector contradicts its complete edge partition.")
                    }
                    let comparison = try first.native.compare(to: last.native, usage: &usage)
                    if comparison == 0 { continue }
                    try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimPartition.Overlap.self, usage: &usage)
                    overlaps.append(.init(lower: comparison < 0 ? first.native : last.native,
                        upper: comparison < 0 ? last.native : first.native,
                        boundaryLowerFraction: first.fraction, boundaryUpperFraction: last.fraction,
                        originalBoundarySpan: span.ordinal))
                }
            }
        }
        let orderedNative = try orderedNative(nativeCuts, usage: &usage)
        var sectors: [SurfaceSilhouetteTrimPartition.Sector] = []
        if orderedNative.count > 1 {
            for index in 0..<(orderedNative.count - 1) {
                let lower = orderedNative[index], upper = orderedNative[index + 1]
                var coincident = false
                for overlap in overlaps {
                    if try lower.compare(to: overlap.lower, usage: &usage) >= 0,
                        try upper.compare(to: overlap.upper, usage: &usage) <= 0 { coincident = true; break }
                }
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimPartition.Sector.self, usage: &usage)
                sectors.append(.init(lower: lower, upper: upper, kind: coincident ? .coincident : .eventFree))
            }
        }
        return .init(originalCurve: curve, originalBoundary: boundary, events: events, overlaps: overlaps, sectors: sectors)
    }

    private func polynomial(_ value: ExactBivariatePolynomial, in context: OriginalSingularFieldContext,
        usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldPolynomial {
        guard value.vDegree <= 0 else { throw rationalAlgebraFailure("Original pcurve fraction polynomial retained a foreign axis.") }
        let count = max(0, try rationalAlgebraCount(max(0, value.uDegree), value.isZero ? 0 : 1))
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for (power, coefficient) in try value.orderedTerms(usage: &usage) {
            coefficients[power.u] = try .constant(coefficient, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        }
        return try .init(context: context, coefficients: coefficients, maximumDepth: usage.maximumDepth, usage: &usage)
    }
    private func scaled(_ polynomial: OriginalSingularFieldPolynomial, by value: OriginalSingularFieldElement,
        usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldPolynomial {
        try RationalAlgebraStorage.retain(polynomial.coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(polynomial.coefficients.count)
        for coefficient in polynomial.coefficients {
            coefficients.append(try coefficient.multiplied(by: value, maximumDepth: usage.maximumDepth, usage: &usage))
        }
        return try .init(context: polynomial.context, coefficients: coefficients, maximumDepth: usage.maximumDepth, usage: &usage)
    }
    private func ordered(_ input: [OriginalSingularFieldEndpoint], usage: inout SurfaceSilhouetteUsage)
        throws -> [OriginalSingularFieldEndpoint] {
        try RationalAlgebraStorage.retain(input.count, of: OriginalSingularFieldEndpoint.self, usage: &usage)
        var output: [OriginalSingularFieldEndpoint] = []; output.reserveCapacity(input.count)
        for original in input {
            var value = original, index = 0, duplicate = false
            while index < output.count {
                var other = output[index]
                let order = try OriginalSingularFieldEndpoint.compare(&value, &other,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                output[index] = other
                if order == 0 { duplicate = true; break }
                if order < 0 { break }; index += 1
            }
            if !duplicate { output.insert(value, at: index) }
        }
        return output
    }
    private func orderedNative(_ input: [SurfaceSilhouetteTrimEndpoint], usage: inout SurfaceSilhouetteUsage)
        throws -> [SurfaceSilhouetteTrimEndpoint] {
        try RationalAlgebraStorage.retain(input.count, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
        var output: [SurfaceSilhouetteTrimEndpoint] = []; output.reserveCapacity(input.count)
        for value in input {
            var index = 0, duplicate = false
            while index < output.count {
                let order = try value.compare(to: output[index], usage: &usage)
                if order == 0 { duplicate = true; break }
                if order < 0 { break }; index += 1
            }
            if !duplicate { output.insert(value, at: index) }
        }
        return output
    }
}
