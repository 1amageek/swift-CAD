import CADCore

extension OriginalSingularFieldElement {
    /// One query keeps every refinement receipt locally; repeated callers retain the isolation port.
    package func enclosure(maximumWidth: ExactRationalCoefficient? = nil, inheritedDepth: Int = 0,
        maximumDepth: Int, usage: inout some ExactScalarAdmission & ~Copyable) throws -> OutwardScalarInterval {
        if let maximumWidth, !maximumWidth.isPositive {
            throw rationalAlgebraFailure("Original field enclosure requires positive caller width.")
        }
        var retained = try OriginalSingularFieldValueIsolation(original: self,
            inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage)
        if retained.lower.isZero, retained.upper.isZero { return .exact(0) }
        var width = maximumWidth ?? .one
        while true {
            retained = try retained.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
            let result = try retained.enclosure(usage: &usage)
            if result.isFinite, result.excludesZero { return result }
            if try retained.upper.subtracting(retained.lower, usage: &usage).isZero {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original field value has no finite nonzero binary enclosure.")
            }
            width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        }
    }
}
