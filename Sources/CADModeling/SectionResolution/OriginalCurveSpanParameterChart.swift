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
    package let constructionAdmission: GeometryConversionAdmission?
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
        constructionAdmission: GeometryConversionAdmission? = nil) {
        identity = OriginalCurveSpanChartIdentity()
        self.source = source
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.mapping = mapping
        self.constructionAdmission = constructionAdmission ?? source.admission
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
            constructionAdmission: constructionAdmission)
    }

    package func replacingCurve(_ curve: Curve3D) -> Self {
        replacingSource(OriginalCurveSpanSource(curve: curve))
    }

    package func replacingSource(_ source: OriginalCurveSpanSource) -> Self {
        Self(source: source, startParameter: startParameter,
            endParameter: endParameter, mapping: mapping,
            exactFirstFraction: exactFirstFraction, exactLastFraction: exactLastFraction,
            firstFraction: firstFraction, lastFraction: lastFraction,
            constructionAdmission: constructionAdmission)
    }

    package func admittingConstruction(_ admission: GeometryConversionAdmission) -> Self {
        Self(source: source, startParameter: startParameter, endParameter: endParameter,
            mapping: mapping, exactFirstFraction: exactFirstFraction,
            exactLastFraction: exactLastFraction, firstFraction: firstFraction,
            lastFraction: lastFraction, constructionAdmission: admission)
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
        admission: GeometryConversionAdmission) throws -> Curve3D {
        var usage = ExactAdmission(admission: admission, tolerance: tolerance)
        return .originalConstructionChart(try OriginalCurveConstructionChartImage(
            parameterSource: parameterSource, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage))
    }

    package func restricted(from lower: Double, to upper: Double,
        in domain: ParameterDomain, tolerance: ModelingTolerance) throws -> Self {
        guard case let .closed(a, b) = domain, a <= lower, lower < upper, upper <= b else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original span restriction needs its retained construction domain.")
        }
        if case .affine = mapping, startParameter == a, endParameter == b,
           firstFraction.lower == 0, firstFraction.upper == 0,
           lastFraction.lower == 1, lastFraction.upper == 1 {
            let result = Self(source: source, startParameter: lower, endParameter: upper)
            return constructionAdmission.map { result.admittingConstruction($0) } ?? result
        }
        let admission = try constructionAdmission ?? CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission()
        var usage = ExactAdmission(admission: admission, tolerance: tolerance)
        let origin = try ExactRationalCoefficient.originalDouble(a, usage: &usage)
        let width = try ExactRationalCoefficient.originalDouble(b, usage: &usage)
            .subtracting(origin, usage: &usage)
        let gain = try exactLastFraction.subtracting(exactFirstFraction, usage: &usage)
        func station(_ label: Double, usage: inout ExactAdmission) throws -> ExactRationalCoefficient {
            let value = try ExactRationalCoefficient.originalDouble(label, usage: &usage)
                .subtracting(origin, usage: &usage).divided(by: width, usage: &usage)
            return try exactFirstFraction.adding(gain.multiplied(by: value, usage: &usage), usage: &usage)
        }
        let first = try lower == a ? exactFirstFraction : station(lower, usage: &usage)
        let last = try upper == b ? exactLastFraction : station(upper, usage: &usage)
        return Self(source: source, startParameter: startParameter, endParameter: endParameter,
            mapping: mapping, exactFirstFraction: first, exactLastFraction: last,
            firstFraction: try first.outwardInterval(usage: &usage),
            lastFraction: try last.outwardInterval(usage: &usage),
            constructionAdmission: admission)
    }

    /// Capability only: nil retains the need for an original exact endpoint chart.
    package func authoredEndpointParameter(atEnd: Bool,
        tolerance: ModelingTolerance) throws -> Double? {
        let fraction = atEnd ? lastFraction : firstFraction
        switch mapping {
        case .affine:
            break
        case .circularRational, .hyperbolicRational:
            guard (fraction.lower == 0 && fraction.upper == 0)
                || (fraction.lower == 1 && fraction.upper == 1) else { return nil }
        }
        let bounds = try parameterBounds(atNormalizedFraction: atEnd ? 1 : 0,
            tolerance: tolerance)
        return bounds.lower == bounds.upper ? bounds.lower : nil
    }

    package func parameterBounds(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {},
        consumeStorage: (Int) throws -> Void = { _ in }) throws -> OutwardScalarInterval {
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
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).value
        case .hyperbolicRational:
            return try OriginalHyperbolicRationalParameterLaw(start: startParameter,
                end: endParameter).jet(over: originalFraction, throughOrder: 0,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).value
        }
    }

    /// Closed original label derivatives in the retained construction fraction.
    package func parameterJet(overNormalizedFraction range: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: (Int) throws -> Void) throws -> IntervalDerivativeJet {
        try consumeWork()
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
               let endpoint = try authoredEndpointParameter(atEnd: false, tolerance: tolerance) { native = .exact(endpoint) }
            if range.lower == 1, range.upper == 1,
               let endpoint = try authoredEndpointParameter(atEnd: true, tolerance: tolerance) { native = .exact(endpoint) }
            try consumeStorage((order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
            var fields: [OutwardScalarInterval] = []
            fields.reserveCapacity(order + 1); fields.append(native)
            if order > 0 { fields.append(gain * fractionGain) }
            while fields.count <= order { try consumeWork(); fields.append(.exact(0)) }
            return .init(derivatives: fields)
        case .circularRational, .hyperbolicRational:
            let original: IntervalDerivativeJet
            switch mapping {
            case .circularRational:
                original = try OriginalCircularRationalParameterLaw(start: startParameter,
                    end: endParameter).jet(over: fraction, throughOrder: order, tolerance: tolerance,
                        consumeWork: consumeWork, consumeStorage: consumeStorage)
            case .hyperbolicRational:
                original = try OriginalHyperbolicRationalParameterLaw(start: startParameter,
                    end: endParameter).jet(over: fraction, throughOrder: order, tolerance: tolerance,
                        consumeWork: consumeWork, consumeStorage: consumeStorage)
            case .affine:
                throw GeometryConversionError.invalidInput("Original nonlinear parameter dispatch lost its chart kind.")
            }
            try consumeStorage((order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
            var fields: [OutwardScalarInterval] = []
            fields.reserveCapacity(order + 1)
            var power = OutwardScalarInterval.exact(1)
            for index in 0...order {
                try consumeWork()
                fields.append(original.derivatives[index] * power)
                power = power * fractionGain
            }
            return .init(derivatives: fields)

        }
    }

    private struct ExactAdmission: RationalAlgebraAdmitting {
        let admission: GeometryConversionAdmission
        let tolerance: ModelingTolerance
        mutating func consumeExactWork(_ count: Int) throws { try admission.chargeWork(count) }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original chart exact storage overflows.")
            }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= 32 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original chart exact algebra depth is exhausted.")
            }
            try admission.chargeWork()
        }
    }
}
