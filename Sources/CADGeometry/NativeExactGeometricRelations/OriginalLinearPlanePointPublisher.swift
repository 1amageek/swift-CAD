import CADCore

/// Refines the proved isolated tuple; it never searches for a new root.
struct OriginalLinearPlanePointPublisher {
    typealias F = OriginalExactScalarDomain

    /// Containment proves accuracy; an inconclusive enclosure only requests
    /// another iteration of the original numeric refinement loop.
    private enum Accuracy: Equatable { case provenWithin, needsRefinement }

    /// Invocation-local enclosures of six rational functions of one sealed
    /// coefficient root. The exact transfer remains their equality authority.
    private struct CoordinateEnclosures {
        private enum Coordinate {
            case rational(ExactRationalCoefficient)
            case fraction(ExactBivariatePolynomial, ExactBivariatePolynomial)
        }
        private struct RationalBounds {
            let lower: ExactRationalCoefficient
            let upper: ExactRationalCoefficient

            func squared(using a: inout OriginalQueryExecution) throws -> Self {
                let first = try lower.multiplied(by: lower, usage: &a)
                let last = try upper.multiplied(by: upper, usage: &a)
                let ascending = try last.subtracting(first, usage: &a).isPositive
                let crossesZero = !lower.isPositive && !upper.isNegative
                return Self(lower: crossesZero ? .zero : ascending ? first : last,
                    upper: ascending ? last : first)
            }

            func outward(using a: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
                let first = try lower.outwardInterval(usage: &a)
                let last = try upper.outwardInterval(usage: &a)
                return .init(lower: first.lower, upper: last.upper)
            }
        }
        private let field: F
        private let coordinates: [Coordinate]
        private var root: ExactAlgebraicRealRoot?
        private(set) var depth: ExactScalarDepth

        init(transfer: ExactOriginalScalarTransferReceipt,
            using a: inout OriginalQueryExecution) throws {
            let field = transfer.field
            var depth = field.originalDepth
            var coordinates: [Coordinate] = []
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: transfer.values.count, of: Coordinate.self))
            coordinates.reserveCapacity(transfer.values.count)
            var needsRoot = false
            for value in transfer.values {
                try a.consumeWork(1)
                try a.admitDepth(value: value.depth.value, coefficient: value.depth.coefficient)
                depth = try .init(value: max(depth.value, value.depth.value),
                    coefficient: max(depth.coefficient, value.depth.coefficient))
                let coordinate = try Self.coordinate(value, field: field, using: &a)
                coordinates.append(coordinate)
                if case .fraction = coordinate { needsRoot = true }
            }
            let root: ExactAlgebraicRealRoot?
            if needsRoot {
                guard case .extended(let source) = field.context.source,
                    let retained = source.retainedRationalRoot else { throw ExactScalarFailure.invalidEvidence }
                root = retained
                depth = try .init(value: depth.value,
                    coefficient: max(depth.coefficient, retained.isolation.isolationDepth))
            } else { root = nil }
            try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
            self.field = field; self.coordinates = coordinates; self.root = root; self.depth = depth
            try a.checkpoint()
        }

        private static func polynomial(_ source: OriginalSingularFieldPolynomial,
            using a: inout OriginalQueryExecution) throws -> ExactBivariatePolynomial {
            var coefficients: [ExactBivariatePolynomial.Power: ExactRationalCoefficient] = [:]
            for (power, coefficient) in source.coefficients.enumerated() {
                try a.consumeWork(1)
                guard let rational = try coefficient.rationalValue(usage: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                if rational.isZero { continue }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                    of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self))
                coefficients[try .init(u: power, v: 0)] = rational
            }
            return ExactBivariatePolynomial(coefficients)
        }

        private static func coordinate(_ value: OriginalExactScalar, field: F,
            using a: inout OriginalQueryExecution) throws -> Coordinate {
            guard value.original.context === field.context else { throw ExactScalarFailure.incompatibleDomain }
            if let rational = try value.original.rationalValue(usage: &a) { return .rational(rational) }
            guard case .extended(let source) = field.context.source,
                case .coefficient = source.admissionDomain,
                case .rational = source.polynomial.context.source,
                case .extended(let numerator, let denominator) = value.original.storage,
                numerator.context === source.polynomial.context,
                denominator.context === source.polynomial.context else {
                throw ExactScalarFailure.invalidEvidence
            }
            return .fraction(try polynomial(numerator, using: &a), try polynomial(denominator, using: &a))
        }

        private static func interval(_ coordinate: Coordinate, root: ExactAlgebraicRealRoot?,
            using a: inout OriginalQueryExecution) throws -> RationalBounds? {
            switch coordinate {
            case .rational(let value): return .init(lower: value, upper: value)
            case .fraction(let numerator, let denominator):
                guard let root else { throw ExactScalarFailure.invalidEvidence }
                var n = try OriginalRationalPolynomialRange(original: numerator,
                    lower: root.isolation.lower, upper: root.isolation.upper, usage: &a)
                var d = try OriginalRationalPolynomialRange(original: denominator,
                    lower: root.isolation.lower, upper: root.isolation.upper, usage: &a)
                if d.upper.isNegative {
                    n = try n.scaled(by: .one.negated, usage: &a)
                    d = try d.scaled(by: .one.negated, usage: &a)
                }
                // The original field retains the source denominator's nonzero
                // law. Its interval must separate zero before division.
                guard d.lower.isPositive else { return nil }
                let quotient = try n.divided(by: d, usage: &a)
                return .init(lower: quotient.lower, upper: quotient.upper)
            }
        }

        /// Enclose an arbitrary scalar of this exact field over the same private
        /// certified root; nil does not authorize an accuracy or source claim.
        private mutating func interval(_ value: OriginalExactScalar,
            using a: inout OriginalQueryExecution) throws -> RationalBounds? {
            let inherited = try ExactScalarDepth(value: max(depth.value, value.depth.value),
                coefficient: max(depth.coefficient, value.depth.coefficient))
            let observed = try ExactScalarNumericAccess.withAdmission(&a, original: value.depth,
                inherited: inherited, maximum: .init(value: field.maximumValueDepth,
                    coefficient: field.maximumCoefficientDepth)) { a in
                let coordinate = try Self.coordinate(value, field: field, using: &a)
                if case .fraction = coordinate, root == nil {
                    // Rational initial coordinates do not make later forward
                    // scalars rational. Retain only this same source's sealed root.
                    guard case .extended(let source) = field.context.source,
                        case .coefficient = source.admissionDomain,
                        case .rational = source.polynomial.context.source,
                        let retained = source.retainedRationalRoot else {
                        throw ExactScalarFailure.invalidEvidence
                    }
                    let retainedDepth = try ExactScalarDepth(value: depth.value,
                        coefficient: max(depth.coefficient, retained.isolation.isolationDepth))
                    try a.admitDepth(value: retainedDepth.value, coefficient: retainedDepth.coefficient)
                    root = retained
                    depth = retainedDepth
                }
                return try Self.interval(coordinate, root: root, using: &a)
            }
            depth = try .init(value: max(depth.value, observed.depth.value),
                coefficient: max(depth.coefficient, observed.depth.coefficient))
            try a.checkpoint(); return observed.value
        }

        mutating func parameterAccuracy(_ difference: OriginalExactScalar,
            epsilon: ExactRationalCoefficient, using a: inout OriginalQueryExecution) throws -> Accuracy {
            guard let bounds = try interval(difference, using: &a) else { return .needsRefinement }
            let lower = try bounds.lower.adding(epsilon, usage: &a)
            let upper = try epsilon.subtracting(bounds.upper, usage: &a)
            return !lower.isNegative && !upper.isNegative ? .provenWithin : .needsRefinement
        }

        mutating func distanceAccuracy(_ first: [OriginalExactScalar], _ second: [OriginalExactScalar],
            squaredEpsilon: ExactRationalCoefficient, using a: inout OriginalQueryExecution) throws -> Accuracy {
            var upper = ExactRationalCoefficient.zero
            for axis in 0..<3 {
                let delta = try field.subtracting(first[axis], second[axis], using: &a)
                guard let bounds = try interval(delta, using: &a) else { return .needsRefinement }
                upper = try upper.adding(bounds.squared(using: &a).upper, usage: &a)
            }
            return try squaredEpsilon.subtracting(upper, usage: &a).isNegative ? .needsRefinement : .provenWithin
        }

        mutating func bounds(maximumWidth: ExactRationalCoefficient,
            using a: inout OriginalQueryExecution) throws -> [OutwardScalarInterval]? {
            try a.checkpoint()
            try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
            if let retained = root {
                let refined = try a.withProofScope(valueAxis: .coefficient) { a in
                    // Keep the source's dyadic bracket under the existing
                    // Sturm-counted refiner; Newton fractions would be expanded
                    // again by every coordinate range and quotient below.
                    try retained.refinedForSeparation(maximumWidth: maximumWidth,
                        maximumDepth: a.effectiveLimits.maximumCoefficientDepth, usage: &a)
                }
                root = refined
                depth = try .init(value: depth.value,
                    coefficient: max(depth.coefficient, refined.isolation.isolationDepth))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: coordinates.count, of: OutwardScalarInterval.self))
            var result: [OutwardScalarInterval] = []; result.reserveCapacity(coordinates.count)
            for coordinate in coordinates {
                try a.consumeWork(1)
                guard let bounds = try Self.interval(coordinate, root: root, using: &a) else { return nil }
                result.append(try bounds.outward(using: &a))
            }
            try a.checkpoint(); return result
        }
    }

    func publish(_ geometry: OriginalLinearPlaneGeometricRelations,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution)
        throws -> (points: [CurveSurfaceIntersection], receipt: OriginalIssuedNumericalCurveSurfacePoints) {
        try geometry.admitProof(limits: limits, using: &a)
        let count = geometry.exactPoints.count
        guard count <= options.maximumCandidateCount else { throw ExactScalarFailure.resourceLimit(.work) }
        let payload = count.multipliedReportingOverflow(by: 6)
        guard !payload.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: payload.partialValue,
            of: ExactAlgebraicScalar<F>.self))
        var exact: [ExactAlgebraicScalar<F>] = []; exact.reserveCapacity(payload.partialValue)
        for point in geometry.exactPoints {
            try a.consumeWork(1)
            guard point.firstParameters.count == 1, point.secondParameters.count == 2 else {
                throw ExactGeometricRelationFailure.invalidSourceBinding
            }
            exact.append(point.firstParameters[0]); exact.append(contentsOf: point.secondParameters)
            exact.append(point.position.x); exact.append(point.position.y); exact.append(point.position.z)
        }
        let basis = geometry.original.second.original.law
        let transferred = try DefaultExactOriginalScalarTransporter().transfer(exact, into: basis.field, using: &a)
        let f = transferred.field, values = transferred.values
        // A nonconstant line and regular plane have at most one isolated tuple.
        // Keep all closed-cell incidents and prove equality before grouping them.
        for index in 1..<max(1, count) {
            for axis in 0..<6 {
                try a.consumeWork(1)
                guard try f.compare(values[axis], values[6 * index + axis], using: &a) == .equal else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
            }
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Int.self))
        var ordinals: [Int] = []; ordinals.reserveCapacity(count)
        for index in 0..<count { try a.consumeWork(1); ordinals.append(index) }
        let points: [CurveSurfaceIntersection]
        let ranges: [Range<Int>]
        if count == 0 { points = []; ranges = [] }
        else {
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersection.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Range<Int>.self))
            points = [try representative(geometry, transfer: transferred, options: options,
                tolerance: tolerance, limits: limits, using: &a)]
            ranges = [0..<count]
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedNumericalCurveSurfacePoints.self))
        let receipt = OriginalIssuedNumericalCurveSurfacePoints(geometry: geometry, coordinates: transferred,
            incidenceOrdinals: ordinals, incidenceRanges: ranges)
        try a.checkpoint()
        return (points, receipt)
    }

    private func representative(_ geometry: OriginalLinearPlaneGeometricRelations,
        transfer: ExactOriginalScalarTransferReceipt, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        using a: inout OriginalQueryExecution) throws -> CurveSurfaceIntersection {
        let f = transfer.field, values = transfer.values
        let maximum = try ExactScalarDepth(value: a.effectiveLimits.maximumValueDepth,
            coefficient: a.effectiveLimits.maximumCoefficientDepth)
        var enclosures = try CoordinateEnclosures(transfer: transfer, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OutwardScalarInterval.self))
        var numbers: [Double] = []; numbers.reserveCapacity(6)
        var bounds: [OutwardScalarInterval] = []; bounds.reserveCapacity(6)
        let epsilon = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &a)
        let squared = try epsilon.multiplied(by: epsilon, usage: &a)
        let line = geometry.original.first.source.original
        let basis = geometry.original.second.original.law
        var dot = try f.integer(0, using: &a), tangentSquare = dot, normalSquare = dot
        for axis in 0..<3 {
            let direction = try f.binary64(exactly: line.directionCoordinate(in: axis), using: &a)
            let normal = try f.importing(basis.normal[axis], using: &a)
            dot = try f.adding(dot, f.multiplying(direction, normal, using: &a), using: &a)
            tangentSquare = try f.adding(tangentSquare, f.multiplying(direction, direction, using: &a), using: &a)
            normalSquare = try f.adding(normalSquare, f.multiplying(normal, normal, using: &a), using: &a)
        }
        let angle = try f.binary64(exactly: tolerance.angle, using: &a)
        let threshold = try f.multiplying(f.multiplying(tangentSquare, normalSquare, using: &a),
            f.multiplying(angle, angle, using: &a), using: &a)
        let kind: CurveSurfaceIntersectionKind = try f.compare(f.multiplying(dot, dot, using: &a), threshold, using: &a) == .greater ? .transverse : .tangent
        var width = ExactRationalCoefficient.one
        for iteration in 0..<options.maximumIterations {
            numbers.removeAll(keepingCapacity: true); bounds.removeAll(keepingCapacity: true)
            guard let refined = try enclosures.bounds(maximumWidth: width, using: &a) else {
                width = try ExactScalarNumericAccess.withAdmission(&a, inherited: enclosures.depth, maximum: maximum) { usage in
                    try width.divided(by: .natural(2, usage: &usage), usage: &usage)
                }.value
                continue
            }
            bounds.append(contentsOf: refined)
            for axis in 0..<6 {
                try a.consumeWork(1)
                var number = bounds[axis].lower * 0.5 + bounds[axis].upper * 0.5
                let request = axis == 0 ? options.curveRange : axis == 1 ? options.surfaceURange : axis == 2 ? options.surfaceVRange : nil
                if let request { number = max(request.lower, min(request.upper, number)) }
                guard number.isFinite, number >= bounds[axis].lower, number <= bounds[axis].upper else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
                numbers.append(number)
            }
            if bounds.allSatisfy({ $0.upper - $0.lower <= tolerance.distance }) {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                var numeric: [OriginalExactScalar] = []; numeric.reserveCapacity(6)
                for number in numbers { numeric.append(try f.binary64(exactly: number, using: &a)) }
                var parametersValid = true
                for axis in 0..<3 {
                    let delta = try f.subtracting(values[axis], numeric[axis], using: &a)
                    if try enclosures.parameterAccuracy(delta, epsilon: epsilon, using: &a) == .needsRefinement {
                        parametersValid = false
                    }
                }
                let target = try basis.position(u: basis.field.binary64(exactly: numbers[1], using: &a),
                    v: basis.field.binary64(exactly: numbers[2], using: &a), limits: limits, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                var curve: [OriginalExactScalar] = [], surface: [OriginalExactScalar] = []
                curve.reserveCapacity(3); surface.reserveCapacity(3)
                for axis in 0..<3 {
                    let origin = try f.binary64(exactly: line.originCoordinate(in: axis), using: &a)
                    let direction = try f.binary64(exactly: line.directionCoordinate(in: axis), using: &a)
                    curve.append(try f.adding(origin, f.multiplying(direction, numeric[0], using: &a), using: &a))
                    surface.append(try f.importing(target[axis], using: &a))
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                let point = [numeric[3], numeric[4], numeric[5]], original = [values[3], values[4], values[5]]
                if parametersValid,
                    try enclosures.distanceAccuracy(original, point, squaredEpsilon: squared, using: &a) == .provenWithin,
                    try enclosures.distanceAccuracy(curve, surface, squaredEpsilon: squared, using: &a) == .provenWithin,
                    try enclosures.distanceAccuracy(curve, point, squaredEpsilon: squared, using: &a) == .provenWithin,
                    try enclosures.distanceAccuracy(surface, point, squaredEpsilon: squared, using: &a) == .provenWithin {
                    return try .init(point: .init(x: numbers[3], y: numbers[4], z: numbers[5]), curveParameter: numbers[0],
                        surfaceU: numbers[1], surfaceV: numbers[2], kind: kind,
                        residual: tolerance.distance, iterations: iteration)
                }
            }
            width = try ExactScalarNumericAccess.withAdmission(&a, inherited: enclosures.depth, maximum: maximum) { usage in
                try width.divided(by: .natural(2, usage: &usage), usage: &usage)
            }.value
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original line/plane publication exhausted caller refinement iterations.")
    }

}
