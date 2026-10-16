import CADCore

/// Requested-order derivatives of an original homogeneous native curve span.
struct OriginalNativeCurveHigherTaylor {
    static func enclosure<A: ExactScalarAdmission & ~Copyable>(of span: RationalBezierCurveJetEncloser.NativeSpan,
        over range: ScalarInterval, order: Int, tolerance: ModelingTolerance,
        continuation: Bool = false, normalizedRange:OutwardScalarInterval? = nil,
        derivativesInNormalizedParameter:Bool = false, using execution: inout A) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let nativeWidth = OutwardScalarInterval.exact(span.upper) - .exact(span.lower)
        let width = derivativesInNormalizedParameter ? OutwardScalarInterval.exact(1) : nativeWidth
        let q:OutwardScalarInterval
        if let normalizedRange {
            guard normalizedRange.isFinite, normalizedRange.lower >= 0, normalizedRange.upper <= 1,
                  !continuation else {
                throw GeometryConversionError.invalidInput("Original local homogeneous interval exceeds its owning chart.")
            }
            q = normalizedRange
        } else {
            guard nativeWidth.lower > 0, let raw = (OutwardScalarInterval(lower:range.lower,upper:range.upper)
                - .exact(span.lower)).divided(by:nativeWidth),raw.isFinite else {
                throw GeometryConversionError.invalidInput("Original higher curve span has no finite normalized interval.")
            }
            if !continuation && (range.lower < span.lower || range.upper > span.upper) {
                throw GeometryConversionError.invalidInput("Original higher curve interval exceeds its owning native span.")
            }
            q = continuation ? raw : .init(lower:max(0,raw.lower),upper:min(1,raw.upper))
        }
        func value(_ coefficients: [OutwardScalarInterval]) throws -> OutwardScalarInterval {
            guard !coefficients.isEmpty else { return .exact(0) }
            try OriginalCoefficientAllocation.reserve(count: coefficients.count,
                of: OutwardScalarInterval.self, using: &execution)
            var level = coefficients
            while level.count > 1 {
                try CurrentTaskCancellationChecker().checkCancellation()
                for i in 0..<(level.count - 1) {
                    try execution.consumeWork(1)
                    level[i] = level[i] * (.exact(1) - q) + level[i + 1] * q
                }
                level.removeLast()
            }
            return level[0]
        }
        func scalar(_ axis: Int) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, using: &execution)
            var coefficients = span.coefficients[axis]
            for k in 0...order {
                var bound = try value(coefficients)
                if axis == 3, let weight = span.commonWeight { bound = .exact(k == 0 ? weight : 0) }
                if k > 1 { for divisor in 2...k {
                    try execution.consumeWork(1)
                    guard let scaled = bound.divided(by: .exact(Double(divisor))), scaled.isFinite else {
                        throw GeometryConversionError.resourceLimitExceeded("Original higher curve factorial scaling failed.")
                    }
                    bound = scaled
                } }
                try result.set(bound, k, 0)
                if coefficients.count > 1 {
                    try OriginalCoefficientAllocation.reserve(count: coefficients.count - 1,
                        of: OutwardScalarInterval.self, using: &execution)
                    var next: [OutwardScalarInterval] = []
                    next.reserveCapacity(coefficients.count - 1)
                    for i in 0..<(coefficients.count - 1) {
                        try execution.consumeWork(1)
                        guard let derivative = ((coefficients[i + 1] - coefficients[i])
                            * .exact(Double(coefficients.count - 1))).divided(by: width), derivative.isFinite else {
                            throw GeometryConversionError.resourceLimitExceeded("Original higher homogeneous differentiation failed.")
                        }
                        next.append(derivative)
                    }
                    coefficients = next
                } else {
                    try OriginalCoefficientAllocation.reserve(count: 1,
                        of: OutwardScalarInterval.self, using: &execution)
                    coefficients = [.exact(0)]
                }
            }
            return result
        }
        var denominator = try scalar(3)
        if !continuation {
            guard let positive = try denominator.coefficient(0, 0).intersection(with: span.weightRange) else {
                throw GeometryConversionError.invalidInput("Original higher denominator contradicts its positive source hull.")
            }
            try denominator.set(positive, 0, 0)
        }
        guard try denominator.coefficient(0, 0).lower > 0 else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                message: "Original higher rational curve has no positive denominator on the whole interval.")
        }
        let inverse = try denominator.reciprocal(using: &execution)
        return try .init(x: scalar(0).multiplied(by: inverse, using: &execution),
            y: scalar(1).multiplied(by: inverse, using: &execution),
            z: scalar(2).multiplied(by: inverse, using: &execution))
    }
}
