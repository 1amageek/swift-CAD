import CADCore

/// Complete native-owner incidence before any numerical station publication.
package struct OriginalNativePlaneContactProducer {
    fileprivate struct SourcePayload: Sendable {
        let curve: BSplineCurve3D
        let plane: Plane3D
        let prepared: PreparedCurveDifferentialEncloser
    }
    /// Immutable identity for one admitted original source and chart.
    fileprivate final class SourceOwner: Sendable {
        let payload: SourcePayload
        init(curve: BSplineCurve3D, plane: Plane3D, prepared: PreparedCurveDifferentialEncloser) {
            payload = .init(curve: curve, plane: plane, prepared: prepared)
        }
    }
    fileprivate final class CutOwner: Sendable {
        let polynomial: ExactBivariatePolynomial
        init(polynomial: ExactBivariatePolynomial) { self.polynomial = polynomial }
    }

    private static func samePosition<B: ExactScalarAdmission & ~Copyable>(
        _ a: OriginalRationalCurvePolynomial, _ b: OriginalRationalCurvePolynomial,
        at station: ExactRationalCoefficient, usage: inout B) throws -> Bool {
        let aw = try a.homogeneous[3].evaluated(atU: station, v: .zero, usage: &usage)
        let bw = try b.homogeneous[3].evaluated(atU: station, v: .zero, usage: &usage)
        guard aw.isPositive, bw.isPositive else { return false }
        for axis in 0..<3 {
            let x = try a.homogeneous[axis].evaluated(atU: station, v: .zero, usage: &usage)
            let y = try b.homogeneous[axis].evaluated(atU: station, v: .zero, usage: &usage)
            if try !x.multiplied(by: bw, usage: &usage)
                .subtracting(y.multiplied(by: aw, usage: &usage), usage: &usage).isZero { return false }
        }
        return true
    }
    package struct Isolated: Sendable {
        package let boundary: OriginalCurveRootBoundary
        package let kind: CurveSurfaceIntersectionKind
        package let originalPlane: Plane3D
        fileprivate let owner: SourceOwner
        fileprivate let originalLaw: OriginalRationalCurvePolynomial
        fileprivate let clipOwner: CutOwner?
        fileprivate let clipEvent: Int?
        private let uNumerator: ExactBivariatePolynomial
        private let vNumerator: ExactBivariatePolynomial
        private let uDenominator: ExactBivariatePolynomial
        private let vDenominator: ExactBivariatePolynomial

        fileprivate init(boundary: OriginalCurveRootBoundary, kind: CurveSurfaceIntersectionKind,
            originalPlane: Plane3D, owner: SourceOwner, originalLaw: OriginalRationalCurvePolynomial,
            clipOwner: CutOwner? = nil, clipEvent: Int? = nil,
            uNumerator: ExactBivariatePolynomial, vNumerator: ExactBivariatePolynomial,
            uDenominator: ExactBivariatePolynomial, vDenominator: ExactBivariatePolynomial) {
            self.boundary = boundary; self.kind = kind
            self.originalPlane = originalPlane
            self.owner = owner; self.originalLaw = originalLaw
            self.clipOwner = clipOwner; self.clipEvent = clipEvent
            self.uNumerator = uNumerator; self.vNumerator = vNumerator
            self.uDenominator = uDenominator; self.vDenominator = vDenominator
        }

        package func planeParameterBounds<B: ExactScalarAdmission & ~Copyable>(maximumParameterWidth: Double,
            maximumAlgebraicDepth: Int, usage: inout B) throws -> SurfaceParameterBox {
            let parameter = try boundary.refinedIsolation(maximumWidth: maximumParameterWidth,
                maximumSubdivisionDepth: maximumAlgebraicDepth, usage: &usage)
            func quotient(_ numerator: ExactBivariatePolynomial,
                _ denominator: ExactBivariatePolynomial, usage: inout B) throws -> ScalarInterval {
                let weight = try OriginalRationalPolynomialRange(original: denominator,
                    lower: parameter.lower, upper: parameter.upper, usage: &usage)
                let numeratorRange = try OriginalRationalPolynomialRange(original: numerator,
                    lower: parameter.lower, upper: parameter.upper, usage: &usage)
                let value = try numeratorRange.divided(by: weight, usage: &usage).outward(usage: &usage)
                guard value.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original plane UV quotient exceeds finite output coordinates.")
                }
                return try ScalarInterval(lower: value.lower, upper: value.upper)
            }
            return try SurfaceParameterBox(u: quotient(uNumerator, uDenominator, usage: &usage),
                v: quotient(vNumerator, vDenominator, usage: &usage))
        }

        package func liesIn<B: ExactScalarAdmission & ~Copyable>(_ box: SurfaceParameterBox,
            maximumAlgebraicDepth: Int, usage: inout B) throws -> Bool {
            try liesIn(uRange: box.u, vRange: box.v, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        }

        package func liesIn<B: ExactScalarAdmission & ~Copyable>(uRange: ScalarInterval?, vRange: ScalarInterval?,
            maximumAlgebraicDepth: Int, usage: inout B) throws -> Bool {
            for axis in 0..<2 {
                guard let interval = axis == 0 ? uRange : vRange else { continue }
                let numerator = axis == 0 ? uNumerator : vNumerator
                let denominator = axis == 0 ? uDenominator : vDenominator
                let low = try numerator.subtracting(denominator.scaled(by:
                    .originalDouble(interval.lower, usage: &usage), usage: &usage), usage: &usage)
                let high = try numerator.subtracting(denominator.scaled(by:
                    .originalDouble(interval.upper, usage: &usage), usage: &usage), usage: &usage)
                if case .negative = try boundary.sign(of: low,
                    maximumSubdivisionDepth: maximumAlgebraicDepth, usage: &usage) { return false }
                if case .positive = try boundary.sign(of: high,
                    maximumSubdivisionDepth: maximumAlgebraicDepth, usage: &usage) { return false }
            }
            return true
        }

        package func nativeKnotStation(using usage: inout OriginalQueryExecution) throws -> Double? {
            for side in 0..<2 {
                try usage.consumeWork(1)
                let station = owner.payload.curve.knots[boundary.spanIndex + side]
                let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                    .subtracting(.constant(.originalDouble(station, usage: &usage), usage: &usage), usage: &usage)
                if case .zero = try boundary.sign(of: equation,
                    maximumSubdivisionDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage) { return station }
            }
            return nil
        }

        /// The original native multiplicity admission owns C0; sided jets own kind.
        package func mergingNativeKnotEvent(_ next: Isolated,
            using usage: inout OriginalQueryExecution) throws -> Isolated? {
            try usage.consumeWork(1)
            guard owner === next.owner, boundary.spanIndex != next.boundary.spanIndex,
                let station = try nativeKnotStation(using: &usage),
                let nextStation = try next.nativeKnotStation(using: &usage),
                station == nextStation else { return nil }
            let t = try ExactRationalCoefficient.originalDouble(station, usage: &usage)
            guard try OriginalNativePlaneContactProducer.samePosition(originalLaw, next.originalLaw,
                at: t, usage: &usage) else { return nil }
            func tangent(_ law: OriginalRationalCurvePolynomial, usage: inout OriginalQueryExecution) throws
                -> (x: ExactRationalCoefficient, y: ExactRationalCoefficient, z: ExactRationalCoefficient) {
                let w = try law.homogeneous[3].evaluated(atU: t, v: .zero, usage: &usage)
                let dw = try law.homogeneous[3].differentiated(alongU: true, usage: &usage)
                    .evaluated(atU: t, v: .zero, usage: &usage)
                let denominator = try w.multiplied(by: w, usage: &usage)
                func axis(_ index: Int, usage: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
                    let x = try law.homogeneous[index].evaluated(atU: t, v: .zero, usage: &usage)
                    let dx = try law.homogeneous[index].differentiated(alongU: true, usage: &usage)
                        .evaluated(atU: t, v: .zero, usage: &usage)
                    return try dx.multiplied(by: w, usage: &usage)
                        .subtracting(x.multiplied(by: dw, usage: &usage), usage: &usage)
                        .divided(by: denominator, usage: &usage)
                }
                return try (axis(0, usage: &usage), axis(1, usage: &usage), axis(2, usage: &usage))
            }
            let a = try tangent(originalLaw, usage: &usage), b = try tangent(next.originalLaw, usage: &usage)
            let sameDerivative = try a.x.subtracting(b.x, usage: &usage).isZero
                && a.y.subtracting(b.y, usage: &usage).isZero && a.z.subtracting(b.z, usage: &usage).isZero
            let mergedKind = sameDerivative && kind == next.kind ? kind : .mixed
            try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
            return .init(boundary: boundary, kind: mergedKind, originalPlane: originalPlane,
                owner: owner, originalLaw: originalLaw, clipOwner: clipOwner, clipEvent: clipEvent,
                uNumerator: uNumerator, vNumerator: vNumerator,
                uDenominator: uDenominator, vDenominator: vDenominator)
        }
    }

    package struct Overlap: Sendable {
        package let source: BSplineCurve3D
        package let spanIndex: Int
        package let interval: ScalarInterval
        package let plane: Plane3D
        fileprivate let owner: SourceOwner
        private let originalLaw: OriginalRationalCurvePolynomial
        private let uNumerator: ExactBivariatePolynomial
        private let vNumerator: ExactBivariatePolynomial
        private let uDenominator: ExactBivariatePolynomial
        private let vDenominator: ExactBivariatePolynomial
        private let tolerance: ModelingTolerance

        fileprivate init(source: BSplineCurve3D, spanIndex: Int, interval: ScalarInterval,
            originalLaw: OriginalRationalCurvePolynomial, plane: Plane3D, owner: SourceOwner,
            uNumerator: ExactBivariatePolynomial, vNumerator: ExactBivariatePolynomial,
            uDenominator: ExactBivariatePolynomial, vDenominator: ExactBivariatePolynomial,
            tolerance: ModelingTolerance) {
            self.source = source; self.spanIndex = spanIndex; self.interval = interval
            self.originalLaw = originalLaw
            self.plane = plane
            self.owner = owner
            self.uNumerator = uNumerator; self.vNumerator = vNumerator
            self.uDenominator = uDenominator; self.vDenominator = vDenominator
            self.tolerance = tolerance
        }

        package struct ClipResult: Sendable {
            package let hasPositiveContact: Bool
            package let isolated: [Isolated]
            package let sectors: [Sector]
        }

        package struct Sector: Sendable {
            package let start: OriginalCurveRootEndpoint
            package let end: OriginalCurveRootEndpoint
            fileprivate let contact: Overlap
            fileprivate let startEvent: Int?
            fileprivate let endEvent: Int?
            fileprivate let cutOwner: CutOwner?

            package func hasEndpoint(_ isolated: Isolated,
                using usage: inout OriginalQueryExecution) throws -> Bool {
                try usage.consumeWork(1)
                guard contact.owner === isolated.owner else { return false }
                if contact.spanIndex == isolated.boundary.spanIndex,
                    let cutOwner, let isolatedOwner = isolated.clipOwner,
                    cutOwner === isolatedOwner, let event = isolated.clipEvent {
                    return startEvent == event || endEvent == event
                }
                func equals(_ endpoint: OriginalCurveRootEndpoint,
                    station: Double, usage: inout OriginalQueryExecution) throws -> Bool {
                    switch endpoint {
                    case .authored(let authored): try usage.consumeWork(1); return authored == station
                    case .algebraic(let boundary):
                        let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                            .subtracting(.constant(.originalDouble(station, usage: &usage), usage: &usage), usage: &usage)
                        if case .zero = try boundary.sign(of: equation,
                            maximumSubdivisionDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage) { return true }
                        return false
                    }
                }
                if let station = try isolated.nativeKnotStation(using: &usage) {
                    return try equals(start, station: station, usage: &usage)
                        || equals(end, station: station, usage: &usage)
                }
                for side in 0..<2 {
                    let endpoint = side == 0 ? start : end
                    guard case .authored(let station) = endpoint else { continue }
                    let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                        .subtracting(.constant(.originalDouble(station, usage: &usage), usage: &usage), usage: &usage)
                    if case .zero = try isolated.boundary.sign(of: equation,
                        maximumSubdivisionDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage) { return true }
                }
                return false
            }

            package func joins(_ next: Sector, using usage: inout OriginalQueryExecution) throws -> Bool {
                try usage.consumeWork(1)
                guard contact.owner === next.contact.owner else { return false }
                if contact.spanIndex == next.contact.spanIndex {
                    if let cutOwner, let nextOwner = next.cutOwner, cutOwner === nextOwner,
                        let endEvent, let startEvent = next.startEvent { return endEvent == startEvent }
                    if case .authored(let end) = end, case .authored(let start) = next.start {
                        return end == start
                    }
                    return false
                }
                guard contact.spanIndex < next.contact.spanIndex else { return false }
                let source = contact.owner.payload.curve
                let knot = source.knots[contact.spanIndex + 1]
                try usage.consumeWork(1)
                guard knot == source.knots[next.contact.spanIndex] else { return false }
                func equalsKnot(_ endpoint: OriginalCurveRootEndpoint, usage: inout OriginalQueryExecution) throws -> Bool {
                    switch endpoint {
                    case .authored(let station): try usage.consumeWork(1); return station == knot
                    case .algebraic(let boundary):
                        let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                            .subtracting(.constant(.originalDouble(knot, usage: &usage), usage: &usage), usage: &usage)
                        if case .zero = try boundary.sign(of: equation,
                            maximumSubdivisionDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage) { return true }
                        return false
                    }
                }
                guard try equalsKnot(end, usage: &usage), try equalsKnot(next.start, usage: &usage) else { return false }
                return try OriginalNativePlaneContactProducer.samePosition(contact.originalLaw, next.contact.originalLaw,
                    at: .originalDouble(knot, usage: &usage), usage: &usage)
            }

            package func prepared(maximumParameterWidth: Double,
                using usage: inout OriginalQueryExecution) throws -> PreparedSector {
                let traversal = try OriginalCurveRootSpan3D(
                    retainingPreparedNativeSource: contact.owner.payload.prepared,
                    start: start, end: end,
                    maximumParameterWidth: maximumParameterWidth,
                    maximumSubdivisionDepth: usage.effectiveLimits.maximumSubdivisionDepth,
                    tolerance: contact.tolerance, usage: &usage,
                    maximumSpanCount: usage.effectiveLimits.maximumSpans,
                    remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth,
                    maximumAlgebraicDepth: usage.effectiveLimits.maximumValueDepth)
                try RationalAlgebraStorage.retain(1, of: PreparedSector.self, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Overlap.self, usage: &usage)
                return .init(traversal: traversal, contact: contact, pieces: [contact],
                    maximumAlgebraicDepth: usage.effectiveLimits.maximumValueDepth)
            }
        }

        package struct PreparedSector: Sendable {
            package let traversal: OriginalCurveRootSpan3D
            package var plane: Plane3D { contact.plane }
            fileprivate let contact: Overlap
            fileprivate let pieces: [Overlap]
            fileprivate let maximumAlgebraicDepth: Int

            package static func joining(_ sectors: [Sector], maximumParameterWidth: Double,
                using usage: inout OriginalQueryExecution) throws -> Self {
                guard let first = sectors.first, let last = sectors.last else {
                    throw GeometryConversionError.invalidInput("Original plane component requires positive sectors.")
                }
                if sectors.count == 1 { return try first.prepared(maximumParameterWidth: maximumParameterWidth, using: &usage) }
                try RationalAlgebraStorage.retain(sectors.count, of: Overlap.self, usage: &usage)
                var pieces: [Overlap] = []; pieces.reserveCapacity(sectors.count)
                for index in sectors.indices {
                    try usage.consumeWork(1)
                    if index > 0, try !sectors[index - 1].joins(sectors[index], using: &usage) {
                        throw GeometryConversionError.invalidInput("Original plane component has no exact adjacent native source authority.")
                    }
                    pieces.append(sectors[index].contact)
                }
                let traversal = try OriginalCurveRootSpan3D(
                    retainingPreparedNativeSource: first.contact.owner.payload.prepared,
                    start: first.start, end: last.end,
                    maximumParameterWidth: maximumParameterWidth,
                    maximumSubdivisionDepth: usage.effectiveLimits.maximumSubdivisionDepth,
                    tolerance: first.contact.tolerance, usage: &usage,
                    maximumSpanCount: usage.effectiveLimits.maximumSpans,
                    remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth,
                    maximumAlgebraicDepth: usage.effectiveLimits.maximumValueDepth)
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                return .init(traversal: traversal, contact: first.contact, pieces: pieces,
                    maximumAlgebraicDepth: usage.effectiveLimits.maximumValueDepth)
            }

            package func bounds<B: ExactScalarAdmission & ~Copyable>(over normalized: ScalarInterval,
                maximumParameterWidth: Double, maximumAlgebraicDepth: Int,
                usage: inout B) throws -> (position: IntervalVector3DBounds,
                    planeUV: SurfaceParameterBox, sourceParameter: ScalarInterval) {
                guard normalized.lower.isFinite, normalized.upper.isFinite,
                    normalized.lower >= 0, normalized.upper <= 1,
                    normalized.lower <= normalized.upper,
                    (0...32).contains(maximumAlgebraicDepth) else {
                    throw GeometryConversionError.invalidInput("Original plane overlap correspondence requires a normalized interval and independent algebra depth.")
                }
                let depth = min(maximumAlgebraicDepth, self.maximumAlgebraicDepth)
                let a = try traversal.start.refinedIsolation(maximumWidth: maximumParameterWidth,
                    maximumSubdivisionDepth: depth, usage: &usage)
                let b = try traversal.end.refinedIsolation(maximumWidth: maximumParameterWidth,
                    maximumSubdivisionDepth: depth, usage: &usage)
                let s0 = try ExactRationalCoefficient.originalDouble(normalized.lower, usage: &usage)
                let s1 = try ExactRationalCoefficient.originalDouble(normalized.upper, usage: &usage)
                func mapped(_ a: ExactRationalCoefficient, _ b: ExactRationalCoefficient,
                    _ s: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient {
                    try a.multiplied(by: ExactRationalCoefficient.one.subtracting(s, usage: &usage), usage: &usage)
                        .adding(b.multiplied(by: s, usage: &usage), usage: &usage)
                }
                var lower = try mapped(a.lower, b.lower, s0, usage: &usage)
                var upper = try mapped(a.upper, b.upper, s0, usage: &usage)
                let secondLower = try mapped(a.lower, b.lower, s1, usage: &usage)
                let secondUpper = try mapped(a.upper, b.upper, s1, usage: &usage)
                if try secondLower.subtracting(lower, usage: &usage).isNegative { lower = secondLower }
                if try secondUpper.subtracting(upper, usage: &usage).isPositive { upper = secondUpper }
                func range(_ polynomial: ExactBivariatePolynomial,
                    lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, usage: inout B)
                    throws -> OriginalRationalPolynomialRange {
                    try .init(original: polynomial, lower: lower, upper: upper, usage: &usage)
                }
                func quotient(_ numerator: ExactBivariatePolynomial,
                    _ denominator: ExactBivariatePolynomial, lower: ExactRationalCoefficient,
                    upper: ExactRationalCoefficient, usage: inout B) throws -> OutwardScalarInterval {
                    let n = try range(numerator, lower: lower, upper: upper, usage: &usage)
                    let d = try range(denominator, lower: lower, upper: upper, usage: &usage)
                    let value = try n.divided(by: d, usage: &usage).outward(usage: &usage)
                    guard value.isFinite else {
                        throw GeometryConversionError.resourceLimitExceeded("Original plane overlap quotient has no finite numerical enclosure.")
                    }
                    return value
                }
                var position: IntervalVector3DBounds?, u: OutwardScalarInterval?, v: OutwardScalarInterval?
                for piece in pieces {
                    try usage.consumeWork(1)
                    let law = piece.originalLaw
                    let lo = try lower.subtracting(law.lowerParameter, usage: &usage).isNegative ? law.lowerParameter : lower
                    let hi = try upper.subtracting(law.upperParameter, usage: &usage).isPositive ? law.upperParameter : upper
                    if try hi.subtracting(lo, usage: &usage).isNegative { continue }
                    let original = law.homogeneous
                    let value = try IntervalVector3DBounds(
                        x: quotient(original[0], original[3], lower: lo, upper: hi, usage: &usage),
                        y: quotient(original[1], original[3], lower: lo, upper: hi, usage: &usage),
                        z: quotient(original[2], original[3], lower: lo, upper: hi, usage: &usage))
                    let pu = try quotient(piece.uNumerator, piece.uDenominator, lower: lo, upper: hi, usage: &usage)
                    let pv = try quotient(piece.vNumerator, piece.vDenominator, lower: lo, upper: hi, usage: &usage)
                    if let prior = position {
                        position = try .init(x: prior.x.union(value.x), y: prior.y.union(value.y), z: prior.z.union(value.z))
                    } else { position = value }
                    u = u.map { $0.union(pu) } ?? pu; v = v.map { $0.union(pv) } ?? pv
                }
                guard let position, let u, let v else {
                    throw GeometryConversionError.invalidInput("Original plane component omitted its normalized source interval.")
                }
                let sourceLower = try lower.outwardInterval(usage: &usage)
                let sourceUpper = try upper.outwardInterval(usage: &usage)
                return (position, try .init(u: .init(lower: u.lower, upper: u.upper),
                    v: .init(lower: v.lower, upper: v.upper)),
                    try .init(lower: sourceLower.lower, upper: sourceUpper.upper))
            }
        }

        /// Uses all exact rectangle boundary roots, never sampled curve absence.
        package func clipped(to box: SurfaceParameterBox,
            using usage: inout OriginalQueryExecution) throws -> ClipResult {
            try clipped(uRange: box.u, vRange: box.v, using: &usage)
        }

        package func clipped(uRange: ScalarInterval?, vRange: ScalarInterval?,
            using usage: inout OriginalQueryExecution) throws -> ClipResult {
            let depth = usage.effectiveLimits.maximumValueDepth
            try usage.visitCell(axis: .value, depth: 0)
            func wholeSector(usage: inout OriginalQueryExecution) throws -> Sector {
                try RationalAlgebraStorage.retain(1, of: Sector.self, usage: &usage)
                return .init(start: .authored(interval.lower), end: .authored(interval.upper), contact: self,
                    startEvent: nil, endEvent: nil, cutOwner: nil)
            }
            if uRange == nil && vRange == nil {
                return .init(hasPositiveContact: true, isolated: [], sectors: [try wholeSector(usage: &usage)])
            }
            let count = (uRange == nil ? 0 : 2) + (vRange == nil ? 0 : 2)
            try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
            var inequalities: [ExactBivariatePolynomial] = []; inequalities.reserveCapacity(count)
            for axis in 0..<2 {
                guard let range = axis == 0 ? uRange : vRange else { continue }
                let numerator = axis == 0 ? uNumerator : vNumerator
                let denominator = axis == 0 ? uDenominator : vDenominator
                inequalities.append(try numerator.subtracting(denominator.scaled(by:
                    .originalDouble(range.lower, usage: &usage), usage: &usage), usage: &usage))
                inequalities.append(try denominator.scaled(by:
                    .originalDouble(range.upper, usage: &usage), usage: &usage).subtracting(numerator, usage: &usage))
            }
            var product = try ExactBivariatePolynomial.constant(.one, usage: &usage)
            for inequality in inequalities where !inequality.isZero {
                product = try product.multiplied(by: inequality, usage: &usage)
            }
            let lower = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &usage)
            let upper = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &usage)
            func inside(_ station: ExactRationalCoefficient, usage: inout OriginalQueryExecution) throws -> Bool {
                for inequality in inequalities {
                    if try inequality.evaluated(atU: station, v: .zero, usage: &usage).isNegative { return false }
                }
                return true
            }
            let two = try ExactRationalCoefficient.natural(2, usage: &usage)
            if product.uDegree <= 0 {
                let station = try lower.adding(upper, usage: &usage).divided(by: two, usage: &usage)
                let positive = try inside(station, usage: &usage)
                return .init(hasPositiveContact: positive, isolated: [],
                    sectors: positive ? [try wholeSector(usage: &usage)] : [])
            }
            let cuts = try ExactUnivariateRootIsolator().isolate(product, lower: lower,
                upper: upper, maximumDepth: depth, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            let cutOwner = CutOwner(polynomial: product)
            try RationalAlgebraStorage.retain(cuts.count, of: ExactAlgebraicRealRoot.self, usage: &usage)
            var ordered: [ExactAlgebraicRealRoot] = []; ordered.reserveCapacity(cuts.count)
            for cut in cuts {
                let root = try ExactAlgebraicRealRoot(polynomial: product, isolation: cut, usage: &usage)
                var index = ordered.count
                while index > 0 {
                    let previous = ordered[index - 1].isolation
                    let delta = try previous.lower.subtracting(cut.lower, usage: &usage)
                    let upperDelta = try previous.upper.subtracting(cut.upper, usage: &usage)
                    if delta.isNegative || (delta.isZero && !upperDelta.isPositive) { break }
                    index -= 1
                }
                try usage.consumeWork(ordered.count - index)
                ordered.insert(root, at: index)
            }
            var positive = false
            var isolated: [Isolated] = []
            var sectors: [Sector] = []
            var cursor = lower
            var precedingEndpoint = OriginalCurveRootEndpoint.authored(interval.lower)
            var precedingEvent: Int?
            for event in ordered.indices {
                let original = ordered[event]
                var root = original
                var width = try root.isolation.upper.subtracting(root.isolation.lower, usage: &usage)
                // Prove an event-free rational witness on each nonempty sector.
                while !(try root.isolation.lower.subtracting(cursor, usage: &usage)).isPositive {
                    let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                        .subtracting(.constant(cursor, usage: &usage), usage: &usage)
                    if case .zero = try root.sign(of: equation, maximumDepth: depth, usage: &usage) { break }
                    guard width.isPositive else {
                        throw GeometryConversionError.resourceLimitExceeded("Original clipping sector could not separate its retained roots.")
                    }
                    width = try width.divided(by: two, usage: &usage)
                    root = try root.refined(maximumWidth: width, maximumDepth: depth, usage: &usage)
                }
                let boundary = try OriginalCurveRootBoundary.retaining(prepared: originalLaw,
                    coordinate: root, maximumSubdivisionDepth: usage.effectiveLimits.maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &usage, maximumAlgebraicDepth: depth)
                if try root.isolation.lower.subtracting(cursor, usage: &usage).isPositive {
                    let witness = try cursor.adding(root.isolation.lower, usage: &usage).divided(by: two, usage: &usage)
                    if try inside(witness, usage: &usage) {
                        try RationalAlgebraStorage.retain(1, of: Sector.self, usage: &usage)
                        sectors.append(.init(start: precedingEndpoint, end: .algebraic(boundary), contact: self,
                            startEvent: precedingEvent, endEvent: event, cutOwner: cutOwner))
                        positive = true
                    }
                }
                let contact = Isolated(boundary: boundary, kind: .tangent, originalPlane: plane,
                    owner: owner, originalLaw: originalLaw, clipOwner: cutOwner, clipEvent: event,
                    uNumerator: uNumerator, vNumerator: vNumerator,
                    uDenominator: uDenominator, vDenominator: vDenominator)
                if try contact.liesIn(uRange: uRange, vRange: vRange, maximumAlgebraicDepth: depth, usage: &usage) {
                    try RationalAlgebraStorage.retain(1, of: Isolated.self, usage: &usage)
                    isolated.append(contact)
                }
                // Localize the root away from the next distinct source event.
                // Its upper bound remains a witness cursor, never a root value.
                while !(try upper.subtracting(root.isolation.upper, usage: &usage)).isPositive {
                    let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                        .subtracting(.constant(upper, usage: &usage), usage: &usage)
                    if case .zero = try root.sign(of: equation, maximumDepth: depth, usage: &usage) { break }
                    width = try root.isolation.upper.subtracting(root.isolation.lower, usage: &usage).divided(by: two, usage: &usage)
                    guard width.isPositive else { break }
                    root = try root.refined(maximumWidth: width, maximumDepth: depth, usage: &usage)
                }
                cursor = root.isolation.upper
                precedingEndpoint = .algebraic(boundary)
                precedingEvent = event
            }
            if try upper.subtracting(cursor, usage: &usage).isPositive {
                let witness = try cursor.adding(upper, usage: &usage).divided(by: two, usage: &usage)
                if try inside(witness, usage: &usage) {
                    try RationalAlgebraStorage.retain(1, of: Sector.self, usage: &usage)
                    sectors.append(.init(start: precedingEndpoint, end: .authored(interval.upper), contact: self,
                        startEvent: precedingEvent, endEvent: nil, cutOwner: cutOwner))
                    positive = true
                }
            }
            return .init(hasPositiveContact: positive, isolated: isolated, sectors: sectors)
        }
    }

    package struct Result: Sendable {
        package let isolated: [Isolated]
        package let overlaps: [Overlap]
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This original producer supplies complete
    // base-native/authored-U-plane isolated and positive-interval incidence to
    // the public curve-surface dispatcher, including retained positive segments.
    // Periodic translated source carriers and non-native families require their
    // original publication producers before the full G4 domain is complete.
    package func contacts(source: BSplineCurve3D, over interval: ScalarInterval,
        plane: Plane3D, tolerance: ModelingTolerance,
        using usage: inout OriginalQueryExecution) throws -> Result {
        let algebraDepth = usage.effectiveLimits.maximumValueDepth
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(source), tolerance: tolerance,
            remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: usage.effectiveLimits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: algebraDepth, using: &usage)
        try plane.validate(tolerance: tolerance)
        try RationalAlgebraStorage.retain(1, of: SourcePayload.self, usage: &usage)
        let owner = SourceOwner(curve: source, plane: plane, prepared: prepared)
        guard let authoredU = plane.uDirection,
            interval.lower.isFinite, interval.upper.isFinite, interval.lower < interval.upper,
            interval.lower >= source.knots[source.degree],
            interval.upper <= source.knots[source.controlPoints.count] else {
            throw GeometryConversionError.invalidInput("Original plane contacts require an authored-U plane and an increasing base-native trim.")
        }
        func originalVector(_ v: Vector3D, usage: inout OriginalQueryExecution) throws -> [ExactRationalCoefficient] {
            try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
            return try [.originalDouble(v.x, usage: &usage), .originalDouble(v.y, usage: &usage),
                .originalDouble(v.z, usage: &usage)]
        }
        func cross(_ a: [ExactRationalCoefficient], _ b: [ExactRationalCoefficient],
            usage: inout OriginalQueryExecution) throws -> [ExactRationalCoefficient] {
            try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
            var result: [ExactRationalCoefficient] = []; result.reserveCapacity(3)
            for axis in 0..<3 {
                let j = (axis + 1) % 3, k = (axis + 2) % 3
                result.append(try a[j].multiplied(by: b[k], usage: &usage)
                    .subtracting(a[k].multiplied(by: b[j], usage: &usage), usage: &usage))
            }
            return result
        }
        func squared(_ a: [ExactRationalCoefficient], usage: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
            var result = ExactRationalCoefficient.zero
            for q in a { result = try result.adding(q.multiplied(by: q, usage: &usage), usage: &usage) }
            return result
        }
        let u = try originalVector(authoredU, usage: &usage)
        let n = try originalVector(plane.normal, usage: &usage)
        let v = try cross(n, u, usage: &usage)
        let chartNormal = try cross(u, v, usage: &usage)
        let uu = try squared(u, usage: &usage), vv = try squared(v, usage: &usage)
        guard uu.isPositive, vv.isPositive else {
            throw GeometryConversionError.invalidInput("Original plane chart has no exact independent authored directions.")
        }
        var isolated: [Isolated] = [], overlaps: [Overlap] = []
        var spans = 0
        for index in source.degree..<source.controlPoints.count {
            try usage.consumeWork(1)
            let lower = max(interval.lower, source.knots[index])
            let upper = min(interval.upper, source.knots[index + 1])
            guard source.knots[index] < source.knots[index + 1], lower < upper else { continue }
            spans += 1
            guard spans <= usage.effectiveLimits.maximumSpans else {
                throw GeometryConversionError.resourceLimitExceeded("Original plane contacts exhausted owning native spans.")
            }
            let law = try OriginalRationalCurvePolynomial(source: source,
                spanIndex: index, tolerance: tolerance, usage: &usage)
            var h = ExactBivariatePolynomial.zero
            var hu = ExactBivariatePolynomial.zero, hv = ExactBivariatePolynomial.zero
            for axis in 0..<3 {
                let origin = axis == 0 ? plane.origin.x : axis == 1 ? plane.origin.y : plane.origin.z
                let displacement = try law.homogeneous[axis].subtracting(law.homogeneous[3].scaled(by:
                    .originalDouble(origin, usage: &usage), usage: &usage), usage: &usage)
                h = try h.adding(displacement.scaled(by: chartNormal[axis], usage: &usage), usage: &usage)
                hu = try hu.adding(displacement.scaled(by: u[axis], usage: &usage), usage: &usage)
                hv = try hv.adding(displacement.scaled(by: v[axis], usage: &usage), usage: &usage)
            }
            if h.isZero {
                try RationalAlgebraStorage.retain(1, of: Overlap.self, usage: &usage)
                overlaps.append(.init(source: source, spanIndex: index,
                    interval: try ScalarInterval(lower: lower, upper: upper),
                    originalLaw: law, plane: plane, owner: owner,
                    uNumerator: hu, vNumerator: hv,
                    uDenominator: try law.homogeneous[3].scaled(by: uu, usage: &usage),
                    vDenominator: try law.homogeneous[3].scaled(by: vv, usage: &usage), tolerance: tolerance))
                continue
            }
            let roots = try ExactUnivariateRootIsolator().isolate(h,
                lower: .originalDouble(lower, usage: &usage), upper: .originalDouble(upper, usage: &usage),
                maximumDepth: algebraDepth, usage: &usage)
            let derivative = try h.differentiated(alongU: true, usage: &usage)
            let ud = try law.homogeneous[3].scaled(by: uu, usage: &usage)
            let vd = try law.homogeneous[3].scaled(by: vv, usage: &usage)
            for isolation in roots {
                let coordinate = try ExactAlgebraicRealRoot(polynomial: h, isolation: isolation, usage: &usage)
                let boundary = try OriginalCurveRootBoundary.retaining(prepared: law,
                    coordinate: coordinate, maximumSubdivisionDepth: usage.effectiveLimits.maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &usage, maximumAlgebraicDepth: algebraDepth)
                let kind: CurveSurfaceIntersectionKind
                if case .zero = try boundary.sign(of: derivative,
                    maximumSubdivisionDepth: algebraDepth, usage: &usage) { kind = .tangent }
                else { kind = .transverse }
                try RationalAlgebraStorage.retain(1, of: Isolated.self, usage: &usage)
                isolated.append(.init(boundary: boundary, kind: kind, originalPlane: plane,
                    owner: owner, originalLaw: law, uNumerator: hu,
                    vNumerator: hv, uDenominator: ud, vDenominator: vd))
            }
        }
        try RationalAlgebraStorage.retain(isolated.count, of: Isolated.self, usage: &usage)
        try RationalAlgebraStorage.retain(isolated.count, of: (key: Double, value: Int).self, usage: &usage)
        var compacted: [Isolated] = []; compacted.reserveCapacity(isolated.count)
        var nativeEvents: [Double: Int] = [:]; nativeEvents.reserveCapacity(isolated.count)
        for contact in isolated {
            try usage.consumeWork(1)
            if let station = try contact.nativeKnotStation(using: &usage) {
                if let index = nativeEvents[station],
                    let combined = try compacted[index].mergingNativeKnotEvent(contact, using: &usage) {
                    compacted[index] = combined
                    continue
                }
                nativeEvents[station] = compacted.count
            }
            compacted.append(contact)
        }
        return .init(isolated: compacted, overlaps: overlaps)
    }
}
