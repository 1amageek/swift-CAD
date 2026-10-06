import CADCore

/// Original normalized rational law of one directed native boundary owner.
package struct OriginalSplineTraversalPolynomialPiece: Sendable {
    package let lower: ExactRationalCoefficient
    package let upper: ExactRationalCoefficient
    package let homogeneous: [ExactBivariatePolynomial]

    private struct Capability {
        let remainingSourceDepth: Int
        let certificationTolerance: ModelingTolerance
        init(_ traversal: OriginalCurveRootSpan3D) {
            remainingSourceDepth = traversal.remainingSourceDepth
            certificationTolerance = traversal.certificationTolerance
        }
        init(_ curve: OriginalPlaneDerivativeCurve3D) {
            remainingSourceDepth = curve.remainingSourceDepth
            certificationTolerance = curve.certificationTolerance
        }
        init(remainingSourceDepth: Int, tolerance: ModelingTolerance) {
            self.remainingSourceDepth = remainingSourceDepth
            certificationTolerance = tolerance
        }
    }

    package static func pieces<B: RationalAlgebraAdmitting>(_ traversal: OriginalCurveRootSpan3D,
        usage: inout B) throws -> [Self] {
        guard case .authored(let start) = traversal.start, case .authored(let end) = traversal.end else {
            throw unavailable(traversal)
        }
        return try pieces(source: traversal.source,
            start: .originalDouble(start, usage: &usage), end: .originalDouble(end, usage: &usage),
            selectedOwner: traversal.nativeSpanIndex, depth: 0, capability: Capability(traversal), usage: &usage)
    }

    package static func pieces<B: RationalAlgebraAdmitting>(of curve: OriginalPlaneDerivativeCurve3D,
        usage: inout B) throws -> [Self] {
        try pieces(source: .originalPlaneDerivative(curve), start: .zero, end: .one,
            selectedOwner: nil, depth: 0, capability: Capability(curve), usage: &usage)
    }

    /// Reuses a retained normalized guide source without differential preparation.
    package static func pieces<B: RationalAlgebraAdmitting>(of source: Curve3D,
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws -> [Self] {
        try tolerance.validate()
        let retainedDepth: Int
        let retainedTolerance: ModelingTolerance
        switch source {
        case .originalGuideTraversalChain(let chain):
            retainedDepth = chain.remainingSourceDepth; retainedTolerance = chain.certificationTolerance
        case .originalGuideEndpointConnector(let connector):
            retainedDepth = connector.remainingSourceDepth; retainedTolerance = connector.certificationTolerance
        default:
            throw GeometryConversionError.invalidInput("Original normalized guide polynomial requires its retained guide carrier.")
        }
        guard remainingSourceDepth >= 0, retainedTolerance == tolerance else {
            throw GeometryConversionError.invalidInput("Original guide polynomial changed its source capability or tolerance.")
        }
        return try pieces(source: source, start: .zero, end: .one, selectedOwner: nil, depth: 0,
            capability: Capability(remainingSourceDepth: min(remainingSourceDepth, retainedDepth),
                tolerance: tolerance), usage: &usage)
    }

    package static func supports<B: RationalAlgebraAdmitting>(_ traversal: OriginalCurveRootSpan3D,
        usage: inout B) throws -> Bool {
        guard case .authored = traversal.start, case .authored = traversal.end else { return false }
        func source(_ curve: Curve3D, depth: Int) throws -> Bool {
            try usage.consumeExactWork(1)
            guard depth <= traversal.remainingSourceDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original rational source admission exceeds its retained depth.")
            }
            switch curve {
            case .line, .analytic(.line): return true
            case .bSpline: return true
            case .rigidImage(let image): return try source(image.source, depth: depth + 1)
            case .affineImage(let image): return try source(image.source, depth: depth + 1)
            case .parameterImage(let image): return try source(image.source, depth: depth + 1)
            case .originalConstructionChart(let image):
                switch image.chart {
                case .parameterLaw(let chart):
                    return chart.law == .affine ? try source(chart.source, depth: depth + 1) : false
                case .traversal(let original):
                    guard case .authored = original.start, case .authored = original.end else { return false }
                    return try source(original.source, depth: depth + 1)
                }
            case .originalEndpointConnector(let connector):
                guard try source(.bSpline(connector.construction), depth: depth + 1) else { return false }
                for boundary in [connector.startBoundary, connector.endBoundary] {
                    guard case .authored = boundary.start, case .authored = boundary.end,
                        try source(boundary.source, depth: depth + 1) else { return false }
                }
                return true
            case .originalGuideTraversalChain(let chain):
                for span in chain.traversals {
                    guard case .authored = span.start, case .authored = span.end,
                        try source(span.source, depth: depth+1) else { return false }
                }
                return true
            case .originalGuideEndpointConnector(let connector):
                guard connector.source.start == .authored(0), connector.source.end == .authored(1),
                    case .authored = connector.startBoundary.start, case .authored = connector.startBoundary.end,
                    case .authored = connector.endBoundary.start, case .authored = connector.endBoundary.end,
                    try source(connector.source.source, depth: depth+1),
                    source(connector.startBoundary.source, depth: depth+1),
                    source(connector.endBoundary.source, depth: depth+1) else { return false }
                return true
            case .originalPlaneDerivative(let image):
                guard case .authored = image.source.start, case .authored = image.source.end else { return false }
                return try source(image.source.source, depth: depth + 1)
            case .originalAffineWord(let image):
                try usage.consumeExactWork(image.operationWord.factors.count)
                guard !image.operationWord.factors.contains(where: {
                    switch $0 { case .normalizedForward, .normalizedInverse: true; default: false }
                }) else { return false }
                return try source(image.source, depth: depth + 1)
            default: return false
            }
        }
        return try source(traversal.source, depth: 0)
    }

    private static func pieces<B: RationalAlgebraAdmitting>(source: Curve3D,
        start: ExactRationalCoefficient, end: ExactRationalCoefficient, selectedOwner: Int?,
        depth: Int, capability: Capability, usage: inout B) throws -> [Self] {
        try usage.consumeExactWork(1)
        guard depth <= capability.remainingSourceDepth else {
            throw GeometryConversionError.resourceLimitExceeded("Original rational traversal exceeded its retained source-depth capability.")
        }
        let gain = try end.subtracting(start, usage: &usage)
        guard !gain.isZero else { throw GeometryConversionError.invalidInput("Original rational traversal has zero parameter length.") }
        let parameter = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .scaled(by: gain, usage: &usage).adding(.constant(start, usage: &usage), usage: &usage)
        switch source {
        case .parameterImage(let image):
            let imageGain = try image.parameterGain.exactCoefficient(usage: &usage)
            let offset = try ExactRationalCoefficient.originalDouble(image.offset, usage: &usage)
            return try pieces(source: image.source,
                start: start.multiplied(by: imageGain, usage: &usage).adding(offset, usage: &usage),
                end: end.multiplied(by: imageGain, usage: &usage).adding(offset, usage: &usage),
                selectedOwner: selectedOwner, depth: depth + 1, capability: capability, usage: &usage)
        case .originalConstructionChart(let image):
            let labels: (Curve3D, ExactRationalCoefficient, ExactRationalCoefficient, Int?)
            switch image.chart {
            case .parameterLaw(let chart):
                guard chart.law == .affine else { throw unavailable(capability) }
                let first = try ExactRationalCoefficient.originalDouble(chart.startParameter, usage: &usage)
                let fullGain = try ExactRationalCoefficient.originalDouble(chart.endParameter, usage: &usage)
                    .subtracting(first, usage: &usage)
                let chartStart = try first.adding(fullGain.multiplied(by: chart.firstFraction, usage: &usage), usage: &usage)
                let chartGain = try fullGain.multiplied(by: chart.lastFraction.subtracting(chart.firstFraction,
                    usage: &usage), usage: &usage)
                labels = (chart.source, chartStart, chartGain, nil)
            case .traversal(let original):
                guard case .authored(let a) = original.start, case .authored(let b) = original.end else {
                    throw unavailable(capability)
                }
                let first = try ExactRationalCoefficient.originalDouble(a, usage: &usage)
                labels = (original.source, first,
                    try ExactRationalCoefficient.originalDouble(b, usage: &usage).subtracting(first, usage: &usage),
                    original.nativeSpanIndex)
            }
            return try pieces(source: labels.0,
                start: labels.1.adding(labels.2.multiplied(by: start, usage: &usage), usage: &usage),
                end: labels.1.adding(labels.2.multiplied(by: end, usage: &usage), usage: &usage),
                selectedOwner: labels.3, depth: depth + 1, capability: capability, usage: &usage)
        case .originalEndpointConnector(let connector):
            let original = try pieces(source: .bSpline(connector.construction), start: start, end: end,
                selectedOwner: selectedOwner, depth: depth + 1, capability: capability, usage: &usage)
            let first = try endpoint(connector.startBoundary, atEnd: connector.startAtEnd,
                depth: depth + 1, capability: capability, usage: &usage)
            let last = try endpoint(connector.endBoundary, atEnd: connector.endAtEnd,
                depth: depth + 1, capability: capability, usage: &usage)
            let constructionFirst = try rationalEndpoint(source: .bSpline(connector.construction), at: .zero,
                selectedOwner: nil, depth: depth + 1, capability: capability, usage: &usage)
            let constructionLast = try rationalEndpoint(source: .bSpline(connector.construction), at: .one,
                selectedOwner: nil, depth: depth + 1, capability: capability, usage: &usage)
            var h1 = ExactBivariatePolynomial.zero
            var power = try ExactBivariatePolynomial.constant(.one, usage: &usage)
            for degree in 0...connector.correctionBasis.degree {
                try usage.consumeExactWork(1)
                let coefficient = connector.correctionBasis.coefficient(at: degree)
                if coefficient != 0 {
                    h1 = try h1.adding(power.scaled(by: .originalDouble(coefficient, usage: &usage),
                        usage: &usage), usage: &usage)
                }
                if degree < connector.correctionBasis.degree {
                    power = try power.multiplied(by: parameter, usage: &usage)
                }
            }
            try RationalAlgebraStorage.retain(original.count, of: Self.self, usage: &usage)
            var result: [Self] = []; result.reserveCapacity(original.count)
            for piece in original {
                try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                var h: [ExactBivariatePolynomial] = []; h.reserveCapacity(4)
                for axis in 0..<3 {
                    let a = try first[axis].subtracting(constructionFirst[axis], usage: &usage)
                    let b = try last[axis].subtracting(constructionLast[axis], usage: &usage)
                    let correction = try h1.scaled(by: b.subtracting(a, usage: &usage), usage: &usage)
                        .adding(.constant(a, usage: &usage), usage: &usage)
                    h.append(try piece.homogeneous[axis].adding(correction.multiplied(
                        by: piece.homogeneous[3], usage: &usage), usage: &usage))
                }
                h.append(piece.homogeneous[3])
                result.append(Self(lower: piece.lower, upper: piece.upper, homogeneous: h))
            }
            return result
        case .originalGuideTraversalChain(let chain):
            let requestedLower = gain.isPositive ? start : end
            let requestedUpper = gain.isPositive ? end : start
            guard !requestedLower.isNegative,
                try !ExactRationalCoefficient.one.subtracting(requestedUpper, usage: &usage).isNegative else {
                throw GeometryConversionError.invalidInput("Original rational guide chart exceeds its declared station partition.")
            }
            var result: [Self] = []
            var admittedCapacity = 0
            for index in chain.traversals.indices {
                let traversal = chain.traversals[index]
                guard case .authored(let a) = traversal.start, case .authored(let b) = traversal.end else {
                    throw unavailable(capability)
                }
                let station = chain.stations[index]
                let width = try chain.stations[index+1].subtracting(station, usage: &usage)
                guard try chain.stations[index+1].subtracting(requestedLower, usage: &usage).isPositive,
                    requestedUpper.subtracting(station, usage: &usage).isPositive else { continue }
                let original = try pieces(source: traversal.source,
                    start: .originalDouble(a, usage: &usage), end: .originalDouble(b, usage: &usage),
                    selectedOwner: traversal.nativeSpanIndex, depth: depth+1, capability: capability, usage: &usage)
                let localParameter = try parameter.subtracting(.constant(station, usage: &usage), usage: &usage)
                    .scaled(by: ExactRationalCoefficient.one.divided(by: width, usage: &usage), usage: &usage)
                for piece in original {
                    let first = try station.adding(width.multiplied(by: piece.lower, usage: &usage), usage: &usage)
                    let last = try station.adding(width.multiplied(by: piece.upper, usage: &usage), usage: &usage)
                    let lo = try first.subtracting(requestedLower, usage: &usage).isPositive ? first : requestedLower
                    let hi = try last.subtracting(requestedUpper, usage: &usage).isNegative ? last : requestedUpper
                    guard try hi.subtracting(lo, usage: &usage).isPositive else { continue }
                    let lower = try (gain.isPositive ? lo : hi).subtracting(start, usage: &usage).divided(by: gain, usage: &usage)
                    let upper = try (gain.isPositive ? hi : lo).subtracting(start, usage: &usage).divided(by: gain, usage: &usage)
                    try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                    var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(4)
                    for value in piece.homogeneous {
                        values.append(try value.composed(withU: localParameter, v: .zero, usage: &usage))
                    }
                    if result.count == admittedCapacity {
                        let next = admittedCapacity.multipliedReportingOverflow(by: 2)
                        guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original guide polynomial capacity overflows.") }
                        let capacity = admittedCapacity == 0 ? 1 : next.partialValue
                        try RationalAlgebraStorage.retain(capacity, of: Self.self, usage: &usage)
                        try usage.consumeExactWork(result.count)
                        result.reserveCapacity(capacity); admittedCapacity = capacity
                    }
                    result.append(Self(lower: lower, upper: upper, homogeneous: values))
                }
            }
            guard !result.isEmpty else { throw GeometryConversionError.invalidInput("Original rational guide has no positive selected source piece.") }
            return result
        case .originalGuideEndpointConnector(let connector):
            guard connector.source.start == .authored(0), connector.source.end == .authored(1) else {
                throw unavailable(capability)
            }
            let full = try pieces(source: connector.source.source, start: .zero, end: .one,
                selectedOwner: connector.source.nativeSpanIndex, depth: depth+1, capability: capability, usage: &usage)
            let original = try pieces(source: connector.source.source, start: start, end: end,
                selectedOwner: connector.source.nativeSpanIndex, depth: depth+1, capability: capability, usage: &usage)
            let first = try endpoint(connector.startBoundary, atEnd: connector.startAtEnd,
                depth: depth+1, capability: capability, usage: &usage)
            let last = try endpoint(connector.endBoundary, atEnd: connector.endAtEnd,
                depth: depth+1, capability: capability, usage: &usage)
            let sourceFirst = try coordinates(full, at: .zero, usage: &usage)
            let sourceLast = try coordinates(full, at: .one, usage: &usage)
            var h = ExactBivariatePolynomial.zero
            for degree in (0...connector.correctionBasis.degree).reversed() {
                h = try h.multiplied(by: parameter, usage: &usage)
                    .adding(.constant(.originalDouble(connector.correctionBasis.coefficient(at: degree),
                        usage: &usage), usage: &usage), usage: &usage)
            }
            try RationalAlgebraStorage.retain(original.count, of: Self.self, usage: &usage)
            var result: [Self] = []; result.reserveCapacity(original.count)
            for piece in original {
                try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(4)
                for axis in 0..<3 {
                    let a = try first[axis].subtracting(sourceFirst[axis], usage: &usage)
                    let b = try last[axis].subtracting(sourceLast[axis], usage: &usage)
                    let delta = try h.scaled(by: b.subtracting(a, usage: &usage), usage: &usage)
                        .adding(.constant(a, usage: &usage), usage: &usage)
                    values.append(try piece.homogeneous[axis].adding(delta.multiplied(
                        by: piece.homogeneous[3], usage: &usage), usage: &usage))
                }
                values.append(piece.homogeneous[3])
                result.append(Self(lower: piece.lower, upper: piece.upper, homogeneous: values))
            }
            return result
        case .originalPlaneDerivative(let image):
            guard case .authored(let sourceStart) = image.source.start,
                case .authored(let sourceEnd) = image.source.end else { throw unavailable(capability) }
            let a = try ExactRationalCoefficient.originalDouble(sourceStart, usage: &usage)
            let g = try ExactRationalCoefficient.originalDouble(sourceEnd, usage: &usage)
                .subtracting(a, usage: &usage)
            // Full source pieces retain normalized endpoint derivative authority;
            // restricted pieces carry the requested directed parameter law.
            let full = try pieces(source: image.source.source, start: a,
                end: a.adding(g, usage: &usage), selectedOwner: image.source.nativeSpanIndex,
                depth: depth + 1, capability: capability, usage: &usage)
            let restricted = try pieces(source: image.source.source,
                start: a.adding(g.multiplied(by: start, usage: &usage), usage: &usage),
                end: a.adding(g.multiplied(by: end, usage: &usage), usage: &usage),
                selectedOwner: image.source.nativeSpanIndex, depth: depth + 1, capability: capability, usage: &usage)
            try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
            var corrections: [ExactBivariatePolynomial] = [.zero, .zero, .zero]
            for atEnd in [false, true] {
                let station: ExactRationalCoefficient = atEnd ? .one : .zero
                for derivativeOrder in 1...2 {
                    let original = try derivative(full, at: station, order: derivativeOrder, usage: &usage)
                    let target = try image.projectedOriginalDerivative(original, atEnd: atEnd,
                        order: derivativeOrder, usage: &usage)
                    let delta = try target.subtracting(original, usage: &usage)
                    var basis = ExactBivariatePolynomial.zero
                    for power in (0...5).reversed() {
                        let coefficient = try OriginalPlaneHermiteDerivativeBasis.coefficient(
                            power: power, atEnd: atEnd, derivativeOrder: derivativeOrder)
                        basis = try basis.multiplied(by: parameter, usage: &usage)
                            .adding(.constant(.originalDouble(coefficient, usage: &usage), usage: &usage), usage: &usage)
                    }
                    corrections[0] = try corrections[0].adding(basis.scaled(by: delta.x, usage: &usage), usage: &usage)
                    corrections[1] = try corrections[1].adding(basis.scaled(by: delta.y, usage: &usage), usage: &usage)
                    corrections[2] = try corrections[2].adding(basis.scaled(by: delta.z, usage: &usage), usage: &usage)
                }
            }
            try RationalAlgebraStorage.retain(restricted.count, of: Self.self, usage: &usage)
            var result: [Self] = []; result.reserveCapacity(restricted.count)
            for piece in restricted {
                try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                var h: [ExactBivariatePolynomial] = []; h.reserveCapacity(4)
                for axis in 0..<3 {
                    h.append(try piece.homogeneous[axis].adding(corrections[axis].multiplied(
                        by: piece.homogeneous[3], usage: &usage), usage: &usage))
                }
                h.append(piece.homogeneous[3])
                result.append(Self(lower: piece.lower, upper: piece.upper, homogeneous: h))
            }
            return result
        case .rigidImage(let image):
            let original = try pieces(source: image.source, start: start, end: end, selectedOwner: selectedOwner,
                depth: depth + 1, capability: capability, usage: &usage)
            return try transformed(original, x: image.transform.basisX, y: image.transform.basisY,
                z: image.transform.basisZ, translation: image.transform.translation, usage: &usage)
        case .affineImage(let image):
            let original = try pieces(source: image.source, start: start, end: end, selectedOwner: selectedOwner,
                depth: depth + 1, capability: capability, usage: &usage)
            return try transformed(original, x: image.transform.basisX, y: image.transform.basisY,
                z: image.transform.basisZ, translation: image.transform.translation, usage: &usage)
        case .originalAffineWord(let image):
            try usage.consumeExactWork(image.operationWord.factors.count)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original Loft seam comparison
            // requires an ordered-field normalized spatial-word boundary law.
            // Interval coefficient hulls cannot authorize exact shared identity.
            guard !image.operationWord.factors.contains(where: {
                switch $0 { case .normalizedForward, .normalizedInverse: true; default: false }
            }) else { throw unavailable(capability) }
            let original = try pieces(source: image.source, start: start, end: end, selectedOwner: selectedOwner,
                depth: depth + 1, capability: capability, usage: &usage)
            let word = try image.operationWord.prepared(usage: &usage)
            try RationalAlgebraStorage.retain(original.count, of: Self.self, usage: &usage)
            var result: [Self] = []
            result.reserveCapacity(original.count)
            for piece in original {
                try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                var h: [ExactBivariatePolynomial] = []
                h.reserveCapacity(4)
                for row in 0..<3 {
                    var value = try piece.homogeneous[3].scaled(by: word.translationCoefficient(row: row), usage: &usage)
                    for column in 0..<3 {
                        try usage.consumeExactWork(1)
                        value = try value.adding(piece.homogeneous[column].scaled(
                            by: word.linearCoefficient(row: row, column: column), usage: &usage), usage: &usage)
                    }
                    h.append(value)
                }
                h.append(piece.homogeneous[3])
                result.append(Self(lower: piece.lower, upper: piece.upper, homogeneous: h))
            }
            return result
        case .line(let line):
            return try linePiece(origin: line.origin, direction: line.direction, parameter: parameter, usage: &usage)
        case .analytic(.line(let origin, let direction)):
            return try linePiece(origin: origin, direction: direction, parameter: parameter, usage: &usage)
        case .bSpline(let spline):
            let nativeLower = gain.isPositive ? start : end, nativeUpper = gain.isPositive ? end : start
            let domainLower = try ExactRationalCoefficient.originalDouble(spline.knots[spline.degree], usage: &usage)
            let domainUpper = try ExactRationalCoefficient.originalDouble(spline.knots[spline.controlPoints.count], usage: &usage)
            let contained = try !nativeLower.subtracting(domainLower, usage: &usage).isNegative
                && !domainUpper.subtracting(nativeUpper, usage: &usage).isNegative
            guard contained else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original Coons seam and
                // rational embedding consumers require a selected exact-cycle
                // recipe for periodic traversals outside the base knot cover.
                // A rounded endpoint translation cannot authorize that law.
                if spline.isPeriodic { throw unavailable(capability) }
                throw GeometryConversionError.invalidInput("Original rational traversal exceeds its native coefficient domain.")
            }
            var result: [Self] = []
            for span in spline.degree..<spline.controlPoints.count {
                try usage.consumeExactWork(1)
                if let selectedOwner, span != selectedOwner { continue }
                guard spline.knots[span] < spline.knots[span + 1] else { continue }
                let rawLo = try ExactRationalCoefficient.originalDouble(spline.knots[span], usage: &usage)
                let rawHi = try ExactRationalCoefficient.originalDouble(spline.knots[span + 1], usage: &usage)
                let lo = try rawLo.subtracting(nativeLower, usage: &usage).isPositive ? rawLo : nativeLower
                let hi = try rawHi.subtracting(nativeUpper, usage: &usage).isNegative ? rawHi : nativeUpper
                guard try hi.subtracting(lo, usage: &usage).isPositive else { continue }
                let first = gain.isPositive ? lo : hi, last = gain.isPositive ? hi : lo
                let lower = try first.subtracting(start, usage: &usage).divided(by: gain, usage: &usage)
                let upper = try last.subtracting(start, usage: &usage).divided(by: gain, usage: &usage)
                let original = try OriginalRationalCurvePolynomial(source: spline, spanIndex: span,
                    tolerance: capability.certificationTolerance, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                var homogeneous: [ExactBivariatePolynomial] = []
                homogeneous.reserveCapacity(4)
                for law in original.homogeneous {
                    homogeneous.append(try law.composed(withU: parameter, v: .zero, usage: &usage))
                }
                result.append(Self(lower: lower, upper: upper, homogeneous: homogeneous))
            }
            guard !result.isEmpty else { throw GeometryConversionError.invalidInput("Original traversal has no positive native source partition.") }
            return result
        // FIXME(INCOMPLETE_IMPLEMENTATION): Mixed original Loft boundary
        // admission consumes this comparison. Angular, periodic, implicit and
        // algebraic parameter correspondences need their exact original
        // composition law before different structural traversals can share a
        // seam. Rounded image coefficients cannot authorize that identity.
        default: throw unavailable(capability)
        }
    }

    /// Exact source endpoint, evaluated from the same normalized original law.
    static func endpoint<B: RationalAlgebraAdmitting>(_ traversal: OriginalCurveRootSpan3D,
        atEnd: Bool, usage: inout B) throws -> [ExactRationalCoefficient] {
        let original = try pieces(traversal, usage: &usage)
        return try coordinates(original, at: atEnd ? .one : .zero, usage: &usage)
    }

    private static func endpoint<B: RationalAlgebraAdmitting>(_ traversal: OriginalCurveRootSpan3D,
        atEnd: Bool, depth: Int, capability: Capability,
        usage: inout B) throws -> [ExactRationalCoefficient] {
        guard case .authored(let a) = traversal.start, case .authored(let b) = traversal.end else {
            throw unavailable(capability)
        }
        let original = try pieces(source: traversal.source,
            start: .originalDouble(a, usage: &usage), end: .originalDouble(b, usage: &usage),
            selectedOwner: traversal.nativeSpanIndex, depth: depth, capability: capability, usage: &usage)
        return try coordinates(original, at: atEnd ? .one : .zero, usage: &usage)
    }

    private static func rationalEndpoint<B: RationalAlgebraAdmitting>(source: Curve3D,
        at station: ExactRationalCoefficient, selectedOwner: Int?, depth: Int,
        capability: Capability, usage: inout B) throws -> [ExactRationalCoefficient] {
        let original = try pieces(source: source, start: .zero, end: .one, selectedOwner: selectedOwner,
            depth: depth, capability: capability, usage: &usage)
        return try coordinates(original, at: station, usage: &usage)
    }

    static func coordinates<B: RationalAlgebraAdmitting>(_ original: [Self],
        at station: ExactRationalCoefficient, usage: inout B) throws -> [ExactRationalCoefficient] {
        for piece in original {
            try usage.consumeExactWork(1)
            guard try !station.subtracting(piece.lower, usage: &usage).isNegative,
                !piece.upper.subtracting(station, usage: &usage).isNegative else { continue }
            let weight = try piece.homogeneous[3].evaluated(atU: station, v: .zero, usage: &usage)
            guard !weight.isZero else {
                throw GeometryConversionError.invalidInput("Original rational endpoint has zero homogeneous weight.")
            }
            try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
            var result: [ExactRationalCoefficient] = []; result.reserveCapacity(3)
            for axis in 0..<3 {
                result.append(try piece.homogeneous[axis].evaluated(atU: station, v: .zero, usage: &usage)
                    .divided(by: weight, usage: &usage))
            }
            return result
        }
        throw GeometryConversionError.invalidInput("Original rational endpoint is outside its retained source pieces.")
    }

    /// Quotient-rule derivative at a retained normalized source endpoint.
    package static func derivative<B: RationalAlgebraAdmitting>(_ original: [Self],
        at station: ExactRationalCoefficient, order: Int, usage: inout B) throws
        -> OriginalSupportingPlaneEquation.Vector {
        guard (1...3).contains(order) else {
            throw GeometryConversionError.invalidInput("Original rational endpoint derivative order is invalid.")
        }
        for piece in original {
            try usage.consumeExactWork(1)
            guard try !station.subtracting(piece.lower, usage: &usage).isNegative,
                !piece.upper.subtracting(station, usage: &usage).isNegative else { continue }
            func component(_ axis: Int) throws -> ExactRationalCoefficient {
                var numerator = piece.homogeneous[axis]
                var denominator = piece.homogeneous[3]
                for _ in 0..<order {
                    let next = try numerator.differentiated(alongU: true, usage: &usage)
                        .multiplied(by: denominator, usage: &usage)
                        .subtracting(numerator.multiplied(by: denominator.differentiated(
                            alongU: true, usage: &usage), usage: &usage), usage: &usage)
                    denominator = try denominator.multiplied(by: denominator, usage: &usage)
                    numerator = next
                }
                let weight = try denominator.evaluated(atU: station, v: .zero, usage: &usage)
                guard !weight.isZero else {
                    throw GeometryConversionError.invalidInput("Original rational endpoint derivative has zero denominator.")
                }
                return try numerator.evaluated(atU: station, v: .zero, usage: &usage)
                    .divided(by: weight, usage: &usage)
            }
            return try .init(x: component(0), y: component(1), z: component(2))
        }
        throw GeometryConversionError.invalidInput("Original rational derivative is outside its retained source pieces.")
    }

    private static func linePiece<B: RationalAlgebraAdmitting>(origin: Point3D, direction: Vector3D,
        parameter: ExactBivariatePolynomial, usage: inout B) throws -> [Self] {
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var homogeneous: [ExactBivariatePolynomial] = []
        homogeneous.reserveCapacity(4)
        try RationalAlgebraStorage.retain(3, of: (Double, Double).self, usage: &usage)
        for (a, b) in [(origin.x, direction.x), (origin.y, direction.y), (origin.z, direction.z)] {
            homogeneous.append(try parameter.scaled(by: .originalDouble(b, usage: &usage), usage: &usage)
                .adding(.constant(.originalDouble(a, usage: &usage), usage: &usage), usage: &usage))
        }
        homogeneous.append(try .constant(.one, usage: &usage))
        return [Self(lower: .zero, upper: .one, homogeneous: homogeneous)]
    }

    private static func transformed<B: RationalAlgebraAdmitting>(_ original: [Self],
        x: Vector3D, y: Vector3D, z: Vector3D, translation: Vector3D, usage: inout B) throws -> [Self] {
        try RationalAlgebraStorage.retain(original.count, of: Self.self, usage: &usage)
        var result: [Self] = []
        result.reserveCapacity(original.count)
        for piece in original {
            try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
            var h: [ExactBivariatePolynomial] = []
            h.reserveCapacity(4)
            try RationalAlgebraStorage.retain(3, of: (Double, Double, Double, Double).self, usage: &usage)
            for (a, b, c, d) in [(x.x, y.x, z.x, translation.x),
                                  (x.y, y.y, z.y, translation.y),
                                  (x.z, y.z, z.z, translation.z)] {
                h.append(try piece.homogeneous[0].scaled(by: .originalDouble(a, usage: &usage), usage: &usage)
                    .adding(piece.homogeneous[1].scaled(by: .originalDouble(b, usage: &usage), usage: &usage), usage: &usage)
                    .adding(piece.homogeneous[2].scaled(by: .originalDouble(c, usage: &usage), usage: &usage), usage: &usage)
                    .adding(piece.homogeneous[3].scaled(by: .originalDouble(d, usage: &usage), usage: &usage), usage: &usage))
            }
            h.append(piece.homogeneous[3])
            result.append(Self(lower: piece.lower, upper: piece.upper, homogeneous: h))
        }
        return result
    }

    private static func unavailable(_ traversal: OriginalCurveRootSpan3D) -> KernelError {
        unavailable(Capability(traversal))
    }
    private static func unavailable(_ capability: Capability) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: capability.certificationTolerance,
            message: "Different original seam traversals require an available exact directed rational chart.")
    }
}
