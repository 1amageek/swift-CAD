import CADCore
import CADGeometry

/// Original curve authority retained independently of construction coefficients.
package struct OriginalCurveSpanParameterChart: Sendable {
    package enum Mapping: Sendable {
        case affine
        case circularRational
        case hyperbolicRational
    }

    package let identity: OriginalCurveSpanChartIdentity
    package let source: OriginalCurveSpanSource
    package var curve: Curve3D { source.curve }
    package let startParameter: Double
    package let endParameter: Double
    package let mapping: Mapping
    package let constructionBudget: OriginalQueryBudget?
    package let constructionLimits: OriginalQueryExecutionLimits?
    package let constructionContributions: [OriginalQueryContributionHandle]
    package let exactFirstFraction: ExactRationalCoefficient
    package let exactLastFraction: ExactRationalCoefficient
    private let firstFraction: OutwardScalarInterval
    private let lastFraction: OutwardScalarInterval

    package init(curve: Curve3D, startParameter: Double, endParameter: Double,
        mapping: Mapping = .affine) {
        self.init(source: OriginalCurveSpanSource(curve: curve),
            startParameter: startParameter, endParameter: endParameter, mapping: mapping,
            exactFirstFraction: .zero, exactLastFraction: .one,
            firstFraction: .exact(0), lastFraction: .exact(1))
    }

    package init(source: OriginalCurveSpanSource, startParameter: Double,
        endParameter: Double, mapping: Mapping = .affine) {
        self.init(source: source, startParameter: startParameter,
            endParameter: endParameter, mapping: mapping,
            exactFirstFraction: .zero, exactLastFraction: .one,
            firstFraction: .exact(0), lastFraction: .exact(1))
    }

    private init(source: OriginalCurveSpanSource, startParameter: Double,
        endParameter: Double, mapping: Mapping,
        exactFirstFraction: ExactRationalCoefficient,
        exactLastFraction: ExactRationalCoefficient,
        firstFraction: OutwardScalarInterval, lastFraction: OutwardScalarInterval,
        constructionBudget: OriginalQueryBudget? = nil,
        constructionLimits: OriginalQueryExecutionLimits? = nil,
        constructionContributions: [OriginalQueryContributionHandle]? = nil) {
        identity = OriginalCurveSpanChartIdentity()
        self.source = source
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.mapping = mapping
        self.constructionBudget = constructionBudget ?? source.budget
        self.constructionLimits = constructionLimits ?? source.limits
        self.constructionContributions = constructionContributions ?? source.contributions
        self.exactFirstFraction = exactFirstFraction
        self.exactLastFraction = exactLastFraction
        self.firstFraction = firstFraction
        self.lastFraction = lastFraction
    }

    package func isNativeIdentity(in domain: ScalarInterval) -> Bool {
        guard case .affine = mapping else { return false }
        return startParameter == domain.lower && endParameter == domain.upper
            && firstFraction.lower == 0 && firstFraction.upper == 0
            && lastFraction.lower == 1 && lastFraction.upper == 1
    }

    package func reversed() -> Self {
        Self(source: source, startParameter: startParameter, endParameter: endParameter,
            mapping: mapping, exactFirstFraction: exactLastFraction,
            exactLastFraction: exactFirstFraction,
            firstFraction: lastFraction, lastFraction: firstFraction,
            constructionBudget: constructionBudget, constructionLimits: constructionLimits, constructionContributions: constructionContributions)
    }

    package func replacingCurve(_ curve: Curve3D) -> Self {
        replacingSource(OriginalCurveSpanSource(curve: curve))
    }

    package func replacingSource(_ source: OriginalCurveSpanSource) -> Self {
        Self(source: source, startParameter: startParameter,
            endParameter: endParameter, mapping: mapping,
            exactFirstFraction: exactFirstFraction, exactLastFraction: exactLastFraction,
            firstFraction: firstFraction, lastFraction: lastFraction,
            constructionBudget: constructionBudget, constructionLimits: constructionLimits, constructionContributions: constructionContributions)
    }

    package func admittingConstruction(using execution: inout OriginalQueryExecution) throws -> Self {
        try Self(source: source, startParameter: startParameter, endParameter: endParameter,
            mapping: mapping, exactFirstFraction: exactFirstFraction,
            exactLastFraction: exactLastFraction, firstFraction: firstFraction,
            lastFraction: lastFraction, constructionBudget: execution.budget, constructionLimits: execution.effectiveLimits,
            constructionContributions: try execution.retainActiveContributionHandles())
    }

    package var parameterSource: OriginalCurveConstructionParameterSource {
        let law: OriginalCurveConstructionParameterLaw
        switch mapping {
        case .affine: law = .affine
        case .circularRational: law = .circularRational
        case .hyperbolicRational: law = .hyperbolicRational
        }
        return OriginalCurveConstructionParameterSource(source: curve,
            startParameter: startParameter, endParameter: endParameter, law: law,
            firstFraction: exactFirstFraction, lastFraction: exactLastFraction)
    }

    package func persistentCurve(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        return .originalConstructionChart(try OriginalCurveConstructionChartImage(
            parameterSource: parameterSource, tolerance: tolerance,
            maximumSpanCount: execution.effectiveLimits.maximumSpans,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            using: &execution))
    }

    package func restricted(from lower: Double, to upper: Double,
        in domain: ParameterDomain, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Self {
        guard case let .closed(a, b) = domain, a <= lower, lower < upper, upper <= b else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original span restriction needs its retained construction domain.")
        }
        if case .affine = mapping, startParameter == a, endParameter == b,
           firstFraction.lower == 0, firstFraction.upper == 0,
           lastFraction.lower == 1, lastFraction.upper == 1 {
            let result = Self(source: source, startParameter: lower, endParameter: upper)
            return try result.admittingConstruction(using: &execution)
        }
        let origin = try ExactRationalCoefficient.originalDouble(a, usage: &execution)
        let width = try ExactRationalCoefficient.originalDouble(b, usage: &execution)
            .subtracting(origin, usage: &execution)
        let gain = try exactLastFraction.subtracting(exactFirstFraction, usage: &execution)
        func station(_ label: Double, usage: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
            let value = try ExactRationalCoefficient.originalDouble(label, usage: &usage)
                .subtracting(origin, usage: &usage).divided(by: width, usage: &usage)
            return try exactFirstFraction.adding(gain.multiplied(by: value, usage: &usage), usage: &usage)
        }
        let first = try lower == a ? exactFirstFraction : station(lower, usage: &execution)
        let last = try upper == b ? exactLastFraction : station(upper, usage: &execution)
        return Self(source: source, startParameter: startParameter, endParameter: endParameter,
            mapping: mapping, exactFirstFraction: first, exactLastFraction: last,
            firstFraction: try first.outwardInterval(usage: &execution),
            lastFraction: try last.outwardInterval(usage: &execution),
            constructionBudget: execution.budget, constructionLimits: execution.effectiveLimits,
            constructionContributions: try execution.retainActiveContributionHandles())
    }

    /// Capability only: nil retains the need for an original exact endpoint chart.
    package func authoredEndpointParameter(atEnd: Bool,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double? {
        let fraction = atEnd ? lastFraction : firstFraction
        switch mapping {
        case .affine:
            break
        case .circularRational, .hyperbolicRational:
            guard (fraction.lower == 0 && fraction.upper == 0)
                || (fraction.lower == 1 && fraction.upper == 1) else { return nil }
        }
        let bounds = try parameterBounds(atNormalizedFraction: atEnd ? 1 : 0,
            tolerance: tolerance, using: &execution)
        return bounds.lower == bounds.upper ? bounds.lower : nil
    }

    package func parameterBounds(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        guard fraction.isFinite, fraction >= 0, fraction <= 1,
              startParameter.isFinite, endParameter.isFinite,
              startParameter != endParameter else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original span station requires finite directed source endpoints.")
        }
        let mappedFraction = fraction == 0 ? firstFraction : fraction == 1 ? lastFraction
            : firstFraction + (lastFraction - firstFraction) * .exact(fraction)
        let originalFraction = OutwardScalarInterval(lower: max(0, mappedFraction.lower),
            upper: min(1, mappedFraction.upper))
        if originalFraction.lower == 0, originalFraction.upper == 0 { return .exact(startParameter) }
        if originalFraction.lower == 1, originalFraction.upper == 1 { return .exact(endParameter) }
        switch mapping {
        case .affine:
            let native = OutwardScalarInterval.exact(startParameter)
                + (.exact(endParameter) - .exact(startParameter)) * originalFraction
            return .init(lower: max(min(startParameter, endParameter), native.lower),
                upper: min(max(startParameter, endParameter), native.upper))
        case .circularRational:
            return try OriginalCircularRationalParameterLaw(start: startParameter,
                end: endParameter).jet(over: originalFraction, throughOrder: 0,
                    tolerance: tolerance, using: &execution).value
        case .hyperbolicRational:
            return try OriginalHyperbolicRationalParameterLaw(start: startParameter,
                end: endParameter).jet(over: originalFraction, throughOrder: 0,
                    tolerance: tolerance, using: &execution).value
        }
    }

    /// Closed original label derivatives in the retained construction fraction.
    package func parameterJet(overNormalizedFraction range: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> IntervalDerivativeJet {
        try execution.consumeWork(1)
        guard range.lower >= 0, range.upper <= 1, order >= 0, order <= 5,
              startParameter.isFinite, endParameter.isFinite, startParameter != endParameter else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original chart jet requires a contained construction interval and finite directed source labels.")
        }
        let fractionGain = lastFraction - firstFraction
        let proposed = firstFraction + fractionGain * .init(lower: range.lower, upper: range.upper)
        guard let fraction = proposed.intersection(with: .init(lower: 0, upper: 1)) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original construction chart lost its retained source fraction.")
        }
        switch mapping {
        case .affine:
            let gain = OutwardScalarInterval.exact(endParameter) - .exact(startParameter)
            var native = OutwardScalarInterval.exact(startParameter) + gain * fraction
            if range.lower == 0, range.upper == 0,
               let endpoint = try authoredEndpointParameter(atEnd: false, tolerance: tolerance, using: &execution) { native = .exact(endpoint) }
            if range.lower == 1, range.upper == 1,
               let endpoint = try authoredEndpointParameter(atEnd: true, tolerance: tolerance, using: &execution) { native = .exact(endpoint) }
            try execution.retainStorage(bytes:(order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
            var fields: [OutwardScalarInterval] = []
            fields.reserveCapacity(order + 1); fields.append(native)
            if order > 0 { fields.append(gain * fractionGain) }
            while fields.count <= order { try execution.consumeWork(1); fields.append(.exact(0)) }
            return .init(derivatives: fields)
        case .circularRational, .hyperbolicRational:
            let original: IntervalDerivativeJet
            switch mapping {
            case .circularRational:
                original = try OriginalCircularRationalParameterLaw(start: startParameter,
                    end: endParameter).jet(over: fraction, throughOrder: order, tolerance: tolerance,
                        using: &execution)
            case .hyperbolicRational:
                original = try OriginalHyperbolicRationalParameterLaw(start: startParameter,
                    end: endParameter).jet(over: fraction, throughOrder: order, tolerance: tolerance,
                        using: &execution)
            case .affine:
                throw GeometryConversionError.invalidInput("Original nonlinear parameter dispatch lost its chart kind.")
            }
            try execution.retainStorage(bytes:(order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
            var fields: [OutwardScalarInterval] = []
            fields.reserveCapacity(order + 1)
            var power = OutwardScalarInterval.exact(1)
            for index in 0...order {
                try execution.consumeWork(1)
                fields.append(original.derivatives[index] * power)
                power = power * fractionGain
            }
            return .init(derivatives: fields)

        }
    }

    /// A convenience query owns fresh local scope state and the retained cumulative owner.
    package func authoredEndpointParameter(atEnd: Bool, tolerance: ModelingTolerance) throws -> Double? {
        var execution: OriginalQueryExecution
        if let budget = constructionBudget, let limits = constructionLimits {
            execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: constructionContributions)
        } else {
            let owner = try CurvedSweepSourceBudget(tolerance: tolerance)
            execution = try owner.execution()
        }
        return try authoredEndpointParameter(atEnd: atEnd, tolerance: tolerance, using: &execution)
    }
}
