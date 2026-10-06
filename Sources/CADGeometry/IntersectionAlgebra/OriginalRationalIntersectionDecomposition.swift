/// Complete real parameter coverage for one retained native source-chart product.
package struct OriginalRationalIntersectionDecomposition: Sendable {
    package enum Coverage: Sendable {
        case excludedNativeProduct(coordinate: Int)
        case parameterCells(OriginalRationalIntersectionStrata,
            OriginalRationalIntersectionIncidence, OriginalRationalParameterComponents)
    }
    package let system: OriginalRationalIntersectionSystem
    package let nativeDomains: [OriginalRationalParameterDomain]
    package let requestedDomains: [OriginalRationalParameterDomain]
    package let effectiveDomains: [OriginalRationalParameterDomain]?
    package let coverage: Coverage
    package let guardedEquations: OriginalGuardedIntersectionEquations?

    private init(system: OriginalRationalIntersectionSystem,
        nativeDomains: [OriginalRationalParameterDomain], requestedDomains: [OriginalRationalParameterDomain],
        effectiveDomains: [OriginalRationalParameterDomain]?, coverage: Coverage,
        guardedEquations: OriginalGuardedIntersectionEquations? = nil) {
        self.system = system; self.nativeDomains = nativeDomains; self.requestedDomains = requestedDomains
        self.effectiveDomains = effectiveDomains; self.coverage = coverage
        self.guardedEquations = guardedEquations
    }

    package static func prepare<B: RationalAlgebraAdmitting>(system: OriginalRationalIntersectionSystem,
        requestedDomains: [OriginalRationalParameterDomain]? = nil,
        pruneExcludedPrefixes: Bool = false, normalizeDenominatorFactors: Bool = false, isolatedOnly: Bool = false,
        reducePureEvenPowerZeroSets: Bool = false, preferIsolatedCells: Bool = false,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard maximumDepth >= 0, (3...4).contains(system.variableCount),
            requestedDomains == nil || requestedDomains?.count == system.variableCount else {
            throw rationalAlgebraFailure("Native CS/SSI decomposition requires every original coordinate and a valid caller depth.")
        }
        let native = try nativeDomains(system: system, usage: &usage)
        let requested = requestedDomains ?? native
        try RationalAlgebraStorage.retain(system.variableCount, of: OriginalRationalParameterDomain.self, usage: &usage)
        var effective: [OriginalRationalParameterDomain] = []; effective.reserveCapacity(system.variableCount)
        for axis in native.indices {
            try intersectionAlgebraStep(&usage)
            guard let domain = try native[axis].intersecting(requested[axis], usage: &usage) else {
                return Self(system: system, nativeDomains: native, requestedDomains: requested,
                    effectiveDomains: nil, coverage: .excludedNativeProduct(coordinate: axis))
            }
            effective.append(domain)
        }
        let guarded: OriginalGuardedIntersectionEquations?
        if normalizeDenominatorFactors {
            guarded = try .prepare(equations: system.equations, denominatorGuards: system.denominatorGuards,
                variableCount: system.variableCount, squareFreeRepeatedFactors: isolatedOnly || preferIsolatedCells,
                reducePureEvenPowerZeroSets: reducePureEvenPowerZeroSets, usage: &usage)
        } else { guarded = nil }
        let ideal = try ExactIntersectionIdeal.prepare(equations: guarded?.normalizedEquations ?? system.equations,
            variableCount: system.variableCount, usage: &usage)
        let strata = try OriginalRationalIntersectionStrata.prepare(ideal: ideal, exactDomains: effective,
            nonzeroPolynomials: system.denominatorGuards, thomEncoding: true,
            originalRankEquations: guarded?.originalEquations,
            isolatedOnly: isolatedOnly, preferIsolatedCells: preferIsolatedCells,
            pruneExcludedPrefixes: pruneExcludedPrefixes, maximumDepth: maximumDepth, usage: &usage)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: strata.partition,
            maximumDepth: maximumDepth, usage: &usage)
        let components = try incidence.connectedComponents(usage: &usage)
        return Self(system: system, nativeDomains: native, requestedDomains: requested,
            effectiveDomains: effective, coverage: .parameterCells(strata, incidence, components), guardedEquations: guarded)
    }

    private static func nativeDomains<B: RationalAlgebraAdmitting>(system: OriginalRationalIntersectionSystem,
        usage: inout B) throws -> [OriginalRationalParameterDomain] {
        try RationalAlgebraStorage.retain(system.variableCount, of: OriginalRationalParameterDomain.self, usage: &usage)
        var result: [OriginalRationalParameterDomain] = []; result.reserveCapacity(system.variableCount)
        if let curve = system.curveSource {
            result.append(try .init(lower: curve.lowerParameter, upper: curve.upperParameter, usage: &usage))
        }
        let first = system.firstSurfaceSource.domain
        result.append(try .init(first.u, usage: &usage)); result.append(try .init(first.v, usage: &usage))
        if let second = system.secondSurfaceSource?.domain {
            result.append(try .init(second.u, usage: &usage)); result.append(try .init(second.v, usage: &usage))
        }
        guard result.count == system.variableCount else {
            throw rationalAlgebraFailure("A retained native system lost one original source-chart role.")
        }
        return result
    }
}
