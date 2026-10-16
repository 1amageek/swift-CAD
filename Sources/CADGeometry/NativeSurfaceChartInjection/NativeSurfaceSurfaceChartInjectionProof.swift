import CADCore

/// Exact source-map evidence issued before common SSI image publication.
package final class NativeSurfaceSurfaceChartInjectionProof: Sendable {
    package struct Coordinate: Sendable {
        package let xyzAxis: Int
        package let alongU: Bool
        package let numerator: ExactBivariatePolynomial
        package let denominator: ExactBivariatePolynomial
        package let leftIdentity: ExactBivariatePolynomial
        package let rightIdentity: ExactBivariatePolynomial
        package let determinant: ExactRationalCoefficient
        package let lowerDenominator: ExactRationalCoefficient
        package let upperDenominator: ExactRationalCoefficient
    }
    package struct Map: Sendable {
        package let u: Coordinate
        package let v: Coordinate
    }
    package struct Pair: Sendable {
        package let first: Map
        package let second: Map
    }
    private let charts: [NativeSurfaceSurfaceSourceChart]
    package let maps: [Pair]
    private init(charts: [NativeSurfaceSurfaceSourceChart], maps: [Pair]) {
        self.charts = charts; self.maps = maps
    }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(charts: [NativeSurfaceSurfaceSourceChart],
        usage: inout B) throws -> NativeSurfaceSurfaceChartInjectionProof? {
        try intersectionAlgebraStep(&usage)
        guard !charts.isEmpty else {
            try CurrentTaskCancellationChecker().checkCancellation()
            return nil
        }
        try RationalAlgebraStorage.retain(charts.count, of: Pair.self, usage: &usage)
        var maps: [Pair] = []; maps.reserveCapacity(charts.count)
        for chart in charts {
            try validateOwner(chart.firstOwner, law: chart.first, usage: &usage)
            try validateOwner(chart.secondOwner, law: chart.second, usage: &usage)
            guard chart.nativeDomains.count == 4 else { throw rationalAlgebraFailure("Chart injection requires the complete original native product.") }
            try validateDomains(chart, usage: &usage)
            guard chart.system.variableCount == 4, let secondSource = chart.system.secondSurfaceSource else {
                throw rationalAlgebraFailure("Chart injection requires genuine original surface-pair laws.")
            }
            try matching(chart.first, chart.system.firstSurfaceSource, usage: &usage)
            try matching(chart.second, secondSource, usage: &usage)
            guard let first = try map(chart.first, usage: &usage),
                let second = try map(chart.second, usage: &usage) else {
                try CurrentTaskCancellationChecker().checkCancellation()
                return nil
            }
            try intersectionAlgebraStep(&usage)
            maps.append(.init(first: first, second: second))
        }
        try RationalAlgebraStorage.retainBytes(MemoryLayout<NativeSurfaceSurfaceChartInjectionProof>.stride
            + MemoryLayout<[NativeSurfaceSurfaceSourceChart]>.stride + MemoryLayout<[Pair]>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(charts: charts, maps: maps)
    }

    /// Every source binding is checked; no chart-zero or representative binding is used.
    package func validate<B: ExactScalarAdmission & ~Copyable>(charts candidate: [NativeSurfaceSurfaceSourceChart],
        usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard candidate.count == charts.count, maps.count == charts.count else {
            throw rationalAlgebraFailure("Chart injection proof has a foreign chart inventory.")
        }
        for index in charts.indices {
            let original = charts[index], current = candidate[index]
            try Self.matching(original.first, current.first, usage: &usage)
            try Self.matching(original.second, current.second, usage: &usage)
            try Self.validateOwner(current.firstOwner, law: current.first, usage: &usage)
            try Self.validateOwner(current.secondOwner, law: current.second, usage: &usage)
            try Self.validateDomains(current, usage: &usage)
            try intersectionAlgebraStep(&usage)
            guard original.firstOwner.tolerance == current.firstOwner.tolerance,
                original.secondOwner.tolerance == current.secondOwner.tolerance,
                original.system.variableCount == current.system.variableCount,
                original.system.equations.count == current.system.equations.count,
                original.system.denominatorGuards.count == current.system.denominatorGuards.count else {
                throw rationalAlgebraFailure("Chart injection proof cannot change original source-system authority.")
            }
            for ordinal in original.system.equations.indices {
                guard try original.system.equations[ordinal].matches(current.system.equations[ordinal], usage: &usage) else {
                    throw rationalAlgebraFailure("Chart injection proof has a foreign original equation.")
                }
            }
            for ordinal in original.system.denominatorGuards.indices {
                guard try original.system.denominatorGuards[ordinal].matches(current.system.denominatorGuards[ordinal], usage: &usage) else {
                    throw rationalAlgebraFailure("Chart injection proof has a foreign original denominator guard.")
                }
            }
            guard original.nativeDomains.count == current.nativeDomains.count else {
                throw rationalAlgebraFailure("Chart injection proof has foreign native domains.")
            }
            for axis in original.nativeDomains.indices {
                try intersectionAlgebraStep(&usage)
                guard try Self.sameDomain(original.nativeDomains[axis], current.nativeDomains[axis], usage: &usage) else {
                    throw rationalAlgebraFailure("Chart injection proof cannot change native domains.")
                }
            }
        }
    }

    private static func validateOwner<B: ExactScalarAdmission & ~Copyable>(
        _ owner: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        law: OriginalRationalSurfacePolynomial, usage: inout B) throws {
        try owner.validate(on: law.source, over: law.domain, tolerance: owner.tolerance,
            using: &usage)
        try intersectionAlgebraStep(&usage)
        guard !law.source.isUPeriodic, !law.source.isVPeriodic,
            owner.uCycle == 0, owner.vCycle == 0,
            law.uSpanIndex == owner.uSpanIndex, law.vSpanIndex == owner.vSpanIndex,
            law.domain.u == owner.uBounds, law.domain.v == owner.vBounds,
            law.homogeneous.count == 4 else {
            throw rationalAlgebraFailure("Chart injection requires its full nonperiodic original native support.")
        }
        for row in law.source.weights { for weight in row {
            try intersectionAlgebraStep(&usage)
            guard weight.isFinite, weight > 0 else {
                throw rationalAlgebraFailure("Chart injection requires original strictly positive weights.")
            }
        } }
    }
    private static func validateDomains<B: ExactScalarAdmission & ~Copyable>(_ chart: NativeSurfaceSurfaceSourceChart,
        usage: inout B) throws {
        guard chart.nativeDomains.count == 4 else { throw rationalAlgebraFailure("Chart injection lost its original native domains.") }
        for axis in 0..<4 {
            let law = axis < 2 ? chart.first : chart.second
            let bounds = axis % 2 == 0 ? law.domain.u : law.domain.v
            let expected = try OriginalRationalParameterDomain(bounds, usage: &usage)
            try intersectionAlgebraStep(&usage)
            guard try sameDomain(expected, chart.nativeDomains[axis], usage: &usage) else { throw rationalAlgebraFailure("Chart injection native domain differs from its source law.") }
        }
    }
    private static func sameDomain<B: ExactScalarAdmission & ~Copyable>(_ first: OriginalRationalParameterDomain,
        _ second: OriginalRationalParameterDomain, usage: inout B) throws -> Bool {
        guard let a = first.lower, let b = first.upper, let c = second.lower, let d = second.upper else { return false }
        return try a.subtracting(c, usage: &usage).isZero && b.subtracting(d, usage: &usage).isZero
    }
    private static func matching<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalRationalSurfacePolynomial,
        _ candidate: OriginalRationalSurfacePolynomial, usage: inout B) throws {
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(original.source), using: &usage)
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(candidate.source), using: &usage)
        try intersectionAlgebraStep(&usage)
        guard original.source == candidate.source, original.domain.u == candidate.domain.u,
            original.domain.v == candidate.domain.v, original.uSpanIndex == candidate.uSpanIndex,
            original.vSpanIndex == candidate.vSpanIndex, candidate.homogeneous.count == 4 else {
            throw rationalAlgebraFailure("Chart injection proof belongs to another original source law.")
        }
        for axis in 0..<4 {
            guard try original.homogeneous[axis].subtracting(candidate.homogeneous[axis], usage: &usage).isZero else {
                throw rationalAlgebraFailure("Chart injection proof cannot replace original homogeneous coefficients.")
            }
        }
    }
    private static func map<B: ExactScalarAdmission & ~Copyable>(_ law: OriginalRationalSurfacePolynomial,
        usage: inout B) throws -> Map? {
        guard let u = try coordinate(law, alongU: true, excluding: nil, usage: &usage),
            let v = try coordinate(law, alongU: false, excluding: u.xyzAxis, usage: &usage) else { return nil }
        return .init(u: u, v: v)
    }
    private static func coordinate<B: ExactScalarAdmission & ~Copyable>(_ law: OriginalRationalSurfacePolynomial,
        alongU: Bool, excluding: Int?, usage: inout B) throws -> Coordinate? {
        let weight = law.homogeneous[3]
        var otherPower: Int?
        for (power, _) in weight.originalCoefficients {
            try intersectionAlgebraStep(&usage)
            let degree = alongU ? power.v : power.u
            otherPower = min(otherPower ?? degree, degree)
        }
        guard let otherPower else { return nil }
        guard let denominator = try slice(weight, alongU: alongU, otherPower: otherPower, usage: &usage) else { return nil }
        let bounds = alongU ? law.domain.u : law.domain.v
        let lower = try ExactRationalCoefficient.originalDouble(bounds.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(bounds.upper, usage: &usage)
        let lowerValue = try denominator.0.multiplied(by: lower, usage: &usage).adding(denominator.1, usage: &usage)
        let upperValue = try denominator.0.multiplied(by: upper, usage: &usage).adding(denominator.1, usage: &usage)
        guard lowerValue.canonicalSign != 0, lowerValue.canonicalSign == upperValue.canonicalSign else { return nil }
        let variable = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
        let d = try variable.scaled(by: denominator.0, usage: &usage)
            .adding(.constant(denominator.1, usage: &usage), usage: &usage)
        for axis in 0..<3 where axis != excluding {
            try intersectionAlgebraStep(&usage)
            guard let numerator = try slice(law.homogeneous[axis], alongU: alongU, otherPower: otherPower, usage: &usage) else { continue }
            let determinant = try numerator.0.multiplied(by: denominator.1, usage: &usage)
                .subtracting(numerator.1.multiplied(by: denominator.0, usage: &usage), usage: &usage)
            if determinant.isZero { continue }
            let n = try variable.scaled(by: numerator.0, usage: &usage)
                .adding(.constant(numerator.1, usage: &usage), usage: &usage)
            let left = try d.multiplied(by: law.homogeneous[axis], usage: &usage)
            let right = try n.multiplied(by: weight, usage: &usage)
            guard try left.subtracting(right, usage: &usage).isZero else { continue }
            return .init(xyzAxis: axis, alongU: alongU, numerator: n, denominator: d,
                leftIdentity: left, rightIdentity: right, determinant: determinant,
                lowerDenominator: lowerValue, upperDenominator: upperValue)
        }
        return nil
    }
    /// A coefficient slice only proposes a map; the full cross identity proves it.
    private static func slice<B: ExactScalarAdmission & ~Copyable>(_ law: ExactBivariatePolynomial,
        alongU: Bool, otherPower: Int, usage: inout B) throws -> (ExactRationalCoefficient, ExactRationalCoefficient)? {
        var slope = ExactRationalCoefficient.zero, intercept = ExactRationalCoefficient.zero
        for (power, value) in law.originalCoefficients {
            try intersectionAlgebraStep(&usage)
            if (alongU ? power.v : power.u) != otherPower { continue }
            switch alongU ? power.u : power.v {
            case 0: intercept = value
            case 1: slope = value
            default: return nil
            }
        }
        return (slope, intercept)
    }
}
