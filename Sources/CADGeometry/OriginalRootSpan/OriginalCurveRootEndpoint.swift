import CADCore

/// Exact authored station or source-bound isolated algebraic incidence root.
public enum OriginalCurveRootEndpoint: Hashable, Sendable {
    case authored(Double)
    case algebraic(OriginalCurveRootBoundary)

    func exactIsolation<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws
        -> (lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, excludesLower: Bool, excludesUpper: Bool) {
        switch self {
        case .authored(let value):
            let station = try ExactRationalCoefficient.originalDouble(value, usage: &usage)
            return (station, station, false, false)
        case .algebraic(let root):
            return (root.isolationLower, root.isolationUpper, root.excludesLowerEndpoint, root.excludesUpperEndpoint)
        }
    }

    func refinedIsolation<B: ExactScalarAdmission & ~Copyable>(maximumWidth: Double,
        maximumSubdivisionDepth: Int, usage: inout B) throws
        -> (lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, excludesLower: Bool, excludesUpper: Bool) {
        if case .algebraic(let root) = self {
            let refined = try root.refinedIsolation(maximumWidth: maximumWidth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
            return (refined.lower, refined.upper, refined.excludesLowerEndpoint, refined.excludesUpperEndpoint)
        }
        return try exactIsolation(usage: &usage)
    }

    func bounds<B: ExactScalarAdmission & ~Copyable>(maximumWidth: Double,
        maximumSubdivisionDepth: Int, usage: inout B) throws -> ScalarInterval {
        switch self {
        case .authored(let value):
            guard value.isFinite else { throw GeometryConversionError.invalidInput("Original authored endpoint must be finite.") }
            try usage.consumeWork(1)
            return try .init(lower: value, upper: value)
        case .algebraic(let root):
            return try root.parameterBounds(maximumWidth: maximumWidth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        }
    }
}

#if !hasFeature(Embedded)
extension OriginalCurveRootEndpoint: Codable {}
#endif
