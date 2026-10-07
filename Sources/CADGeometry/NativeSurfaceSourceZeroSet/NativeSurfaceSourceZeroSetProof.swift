import CADCore

/// Immutable real-zero consequences of one exact original Native coordinate equality.
package final class NativeSurfaceSourceZeroSetProof: Sendable {
    private let originalChart: NativeSurfaceSurfaceSourceChart
    package let equationIndex: Int
    package let targetRole: Int
    package let orientation: Int
    package let counterpartCoordinate: ExactRationalCoefficient
    package let numerator: ExactBivariatePolynomial
    package let orientedNumerator: ExactBivariatePolynomial
    package let counterpartIdentity: ExactBivariatePolynomial
    package let reconstruction: ExactBivariatePolynomial
    package let factors: [ExactBivariatePolynomial]
    package let positiveCoefficients: [ExactRationalCoefficient]
    package let consequences: [ExactIntersectionPolynomial]
    package let rawEquationIdentity: ExactIntersectionPolynomial

    private init(chart: NativeSurfaceSurfaceSourceChart, equationIndex: Int, targetRole: Int,
        orientation: Int, counterpartCoordinate: ExactRationalCoefficient,
        numerator: ExactBivariatePolynomial, orientedNumerator: ExactBivariatePolynomial,
        counterpartIdentity: ExactBivariatePolynomial, reconstruction: ExactBivariatePolynomial,
        factors: [ExactBivariatePolynomial], positiveCoefficients: [ExactRationalCoefficient],
        consequences: [ExactIntersectionPolynomial], rawEquationIdentity: ExactIntersectionPolynomial) {
        originalChart = chart; self.equationIndex = equationIndex; self.targetRole = targetRole
        self.orientation = orientation; self.counterpartCoordinate = counterpartCoordinate
        self.numerator = numerator; self.orientedNumerator = orientedNumerator
        self.counterpartIdentity = counterpartIdentity; self.reconstruction = reconstruction
        self.factors = factors; self.positiveCoefficients = positiveCoefficients
        self.consequences = consequences; self.rawEquationIdentity = rawEquationIdentity
    }
    private struct Candidate {
        let orientation: Int
        let original: ExactBivariatePolynomial
        let first: ExactBivariatePolynomial
        let second: ExactBivariatePolynomial
        let firstCoefficient: ExactRationalCoefficient
        let secondCoefficient: ExactRationalCoefficient
        let reconstruction: ExactBivariatePolynomial
    }
    package static func prepare<B: RationalAlgebraAdmitting>(chart: NativeSurfaceSurfaceSourceChart,
        usage: inout B) throws -> NativeSurfaceSourceZeroSetProof? {
        try intersectionAlgebraStep(&usage)
        try validateChart(chart, usage: &usage)
        for targetRole in 0..<2 {
            let target = targetRole == 0 ? chart.first : chart.second
            let counterpart = targetRole == 0 ? chart.second : chart.first
            for axis in 0..<3 {
                try intersectionAlgebraStep(&usage)
                guard let constant = try constantCoordinate(counterpart, axis: axis, usage: &usage) else { continue }
                let constantLaw = try counterpart.homogeneous[3].scaled(by: constant, usage: &usage)
                let n = try target.homogeneous[axis].subtracting(target.homogeneous[3].scaled(by: constant, usage: &usage), usage: &usage)
                if n.isZero { continue }
                for parameter in 0..<2 {
                    let alongU = parameter == 0
                    guard let candidate = try completed(n, alongU: alongU, usage: &usage) else { continue }
                    let uAxis = targetRole * 2, vAxis = uAxis + 1
                    let oppositeU = (1 - targetRole) * 2
                    let originalN = try ExactIntersectionPolynomial.embedding(n, variableCount: 4,
                        uCoordinate: uAxis, vCoordinate: vAxis, usage: &usage)
                    let originalW = try ExactIntersectionPolynomial.embedding(counterpart.homogeneous[3], variableCount: 4,
                        uCoordinate: oppositeU, vCoordinate: oppositeU + 1, usage: &usage)
                    let identity = try originalN.multiplied(by: originalW, usage: &usage)
                        .scaled(by: targetRole == 0 ? .one : .one.negated, usage: &usage)
                    guard try identity.matches(chart.system.equations[axis], usage: &usage) else {
                        throw rationalAlgebraFailure("Native source zero proof lost its original coordinate equation.")
                    }
                    try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
                    try RationalAlgebraStorage.retain(2, of: ExactRationalCoefficient.self, usage: &usage)
                    try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
                    let factors = [candidate.first,candidate.second]
                    let coefficients = [candidate.firstCoefficient,candidate.secondCoefficient]
                    let consequences = try [ExactIntersectionPolynomial.embedding(candidate.first, variableCount: 4,
                        uCoordinate: uAxis, vCoordinate: vAxis, usage: &usage),
                        .embedding(candidate.second, variableCount: 4, uCoordinate: uAxis, vCoordinate: vAxis, usage: &usage)]
                    try RationalAlgebraStorage.retainBytes(MemoryLayout<NativeSurfaceSourceZeroSetProof>.stride
                        + MemoryLayout<NativeSurfaceSurfaceSourceChart>.stride + 3 * MemoryLayout<Int>.stride
                        + MemoryLayout<ExactRationalCoefficient>.stride + 4 * MemoryLayout<ExactBivariatePolynomial>.stride
                        + MemoryLayout<ExactIntersectionPolynomial>.stride + 3 * MemoryLayout<[Int]>.stride
                        + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
                    try CurrentTaskCancellationChecker().checkCancellation()
                    return .init(chart: chart,equationIndex: axis,targetRole: targetRole,orientation: candidate.orientation,
                        counterpartCoordinate: constant,numerator: n,orientedNumerator: candidate.original,
                        counterpartIdentity: constantLaw,reconstruction: candidate.reconstruction,
                        factors: factors,positiveCoefficients: coefficients,consequences: consequences,rawEquationIdentity: identity)
                }
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return nil
    }

    package func validate<B: RationalAlgebraAdmitting>(chart: NativeSurfaceSurfaceSourceChart, usage: inout B) throws {
        try Self.validateChart(chart, usage: &usage)
        try Self.matching(originalChart.first, chart.first, usage: &usage)
        try Self.matching(originalChart.second, chart.second, usage: &usage)
        for axis in 0..<4 {
            guard let a = originalChart.nativeDomains[axis].lower, let b = originalChart.nativeDomains[axis].upper,
                let c = chart.nativeDomains[axis].lower, let d = chart.nativeDomains[axis].upper,
                try a.subtracting(c, usage: &usage).isZero, try b.subtracting(d, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Native source zero proof has foreign native domains.")
            }
        }
        for axis in 0..<3 {
            guard try originalChart.system.equations[axis].matches(chart.system.equations[axis], usage: &usage) else {
                throw rationalAlgebraFailure("Native source zero proof has a foreign original equation.")
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }
    static func validateChart<B: RationalAlgebraAdmitting>(_ chart: NativeSurfaceSurfaceSourceChart,
        usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard chart.system.variableCount == 4,chart.system.equations.count == 3,
            chart.system.denominatorGuards.count == 2,chart.nativeDomains.count == 4 else {
            throw rationalAlgebraFailure("Native source zero proof requires a genuine four-coordinate original chart pair.")
        }
        guard let secondSource = chart.system.secondSurfaceSource else { throw rationalAlgebraFailure("Native source zero proof requires both original source roles.") }
        try matching(chart.first, chart.system.firstSurfaceSource, usage: &usage)
        try matching(chart.second, secondSource, usage: &usage)
        try owner(chart.firstOwner, law: chart.first, usage: &usage)
        try owner(chart.secondOwner, law: chart.second, usage: &usage)
        for role in 0..<2 {
            let law = role == 0 ? chart.first : chart.second
            let guardLaw = try ExactIntersectionPolynomial.embedding(law.homogeneous[3], variableCount: 4,
                uCoordinate: role * 2, vCoordinate: role * 2 + 1, usage: &usage)
            guard try guardLaw.matches(chart.system.denominatorGuards[role], usage: &usage) else {
                throw rationalAlgebraFailure("Native source zero proof cannot replace original denominator authority.")
            }
            for local in 0..<2 {
                let bounds = local == 0 ? law.domain.u : law.domain.v
                let expected = try OriginalRationalParameterDomain(bounds, usage: &usage)
                guard let a = expected.lower,let b = expected.upper,
                    let c = chart.nativeDomains[role * 2 + local].lower,let d = chart.nativeDomains[role * 2 + local].upper,
                    try a.subtracting(c, usage: &usage).isZero,try b.subtracting(d, usage: &usage).isZero else {
                    throw rationalAlgebraFailure("Native source zero proof requires its full closed source domains.")
                }
            }
        }
    }
    private static func owner<B: RationalAlgebraAdmitting>(_ native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        law: OriginalRationalSurfacePolynomial,usage: inout B) throws {
        try native.validate(on: law.source,over: law.domain,tolerance: native.tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        try intersectionAlgebraStep(&usage)
        guard !law.source.isUPeriodic,!law.source.isVPeriodic,native.uCycle == 0,native.vCycle == 0,
            law.domain.u == native.uBounds,law.domain.v == native.vBounds,
            law.uSpanIndex == native.uSpanIndex,law.vSpanIndex == native.vSpanIndex,law.homogeneous.count == 4 else {
            throw rationalAlgebraFailure("Native source zero proof has a foreign source-issued support.")
        }
        for row in law.source.weights { for value in row {
            try intersectionAlgebraStep(&usage)
            guard value.isFinite,value > 0 else { throw rationalAlgebraFailure("Native source zero proof requires positive original denominators.") }
        } }
    }
    static func matching<B: RationalAlgebraAdmitting>(_ original: OriginalRationalSurfacePolynomial,
        _ other: OriginalRationalSurfacePolynomial,usage: inout B) throws {
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(original.source), using: { try usage.consumeExactWork($0) })
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(other.source), using: { try usage.consumeExactWork($0) })
        try intersectionAlgebraStep(&usage)
        guard original.source == other.source,original.domain.u == other.domain.u,original.domain.v == other.domain.v,
            original.uSpanIndex == other.uSpanIndex,original.vSpanIndex == other.vSpanIndex else {
            throw rationalAlgebraFailure("Native source zero proof belongs to another original law.")
        }
        for axis in 0..<4 {
            guard try original.homogeneous[axis].subtracting(other.homogeneous[axis], usage: &usage).isZero else {
                throw rationalAlgebraFailure("Native source zero proof cannot change original coefficients.")
            }
        }
    }
    static func constantCoordinate<B: RationalAlgebraAdmitting>(_ law: OriginalRationalSurfacePolynomial,
        axis: Int,usage: inout B) throws -> ExactRationalCoefficient? {
        for (power,weight) in law.homogeneous[3].originalCoefficients {
            try intersectionAlgebraStep(&usage)
            let value = law.homogeneous[axis].originalCoefficients[power] ?? .zero
            let candidate = try value.divided(by: weight, usage: &usage)
            if try law.homogeneous[axis].subtracting(law.homogeneous[3].scaled(by: candidate, usage: &usage), usage: &usage).isZero { return candidate }
            return nil
        }
        return nil
    }
    private static func coefficient<B: RationalAlgebraAdmitting>(_ law: ExactBivariatePolynomial,
        u: Int,v: Int,usage: inout B) throws -> ExactRationalCoefficient {
        try intersectionAlgebraStep(&usage)
        return law.originalCoefficients[try .init(u: u,v: v)] ?? .zero
    }
    private static func completed<B: RationalAlgebraAdmitting>(_ n: ExactBivariatePolynomial,
        alongU: Bool,usage: inout B) throws -> Candidate? {
        let originalLeading = try coefficient(n,u: alongU ? 4 : 0,v: alongU ? 0 : 4,usage: &usage)
        if originalLeading.isZero { return nil }
        let orientation = originalLeading.canonicalSign
        let original = try n.scaled(by: orientation > 0 ? .one : .one.negated, usage: &usage)
        let leading = originalLeading.isPositive ? originalLeading : originalLeading.negated
        let other = try coefficient(original,u: alongU ? 0 : 2,v: alongU ? 2 : 0,usage: &usage)
        if !other.isPositive { return nil }
        let two = try ExactRationalCoefficient.one.adding(.one, usage: &usage)
        let a = try coefficient(original,u: alongU ? 3 : 0,v: alongU ? 0 : 3,usage: &usage)
            .divided(by: leading.multiplied(by: two, usage: &usage), usage: &usage)
        let b = try coefficient(original,u: alongU ? 2 : 0,v: alongU ? 0 : 2,usage: &usage)
            .divided(by: leading, usage: &usage).subtracting(a.multiplied(by: a, usage: &usage), usage: &usage)
            .divided(by: two, usage: &usage)
        let d = try coefficient(original,u: alongU ? 0 : 1,v: alongU ? 1 : 0,usage: &usage)
            .divided(by: other.multiplied(by: two, usage: &usage), usage: &usage)
        let s = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
        let t = try ExactBivariatePolynomial.coordinate(alongU: !alongU, usage: &usage)
        let first = try s.multiplied(by: s, usage: &usage).adding(s.scaled(by: a, usage: &usage), usage: &usage)
            .adding(.constant(b, usage: &usage), usage: &usage)
        let second = try t.adding(.constant(d, usage: &usage), usage: &usage)
        let reconstruction = try first.multiplied(by: first, usage: &usage).scaled(by: leading, usage: &usage)
            .adding(second.multiplied(by: second, usage: &usage).scaled(by: other, usage: &usage), usage: &usage)
        guard try original.subtracting(reconstruction, usage: &usage).isZero else { return nil }
        return .init(orientation: orientation,original: original,first: first,second: second,
            firstCoefficient: leading,secondCoefficient: other,reconstruction: reconstruction)
    }
}
