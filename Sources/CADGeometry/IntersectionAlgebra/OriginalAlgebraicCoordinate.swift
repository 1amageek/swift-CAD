/// A retained exact cell sample; it never represents the whole cell's range.
public struct OriginalAlgebraicCoordinate: Sendable {
    public struct Enclosure: Sendable {
        public let lower: ExactRationalCoefficient
        public let upper: ExactRationalCoefficient
        public let sourceDepth: Int
        public let coefficientAdmissionDepth: Int
        package let retained: OriginalSingularFieldValueIsolation

        /// Refines the same original value while preserving both causal depth domains.
        public func refined<A: ExactScalarAdmission & ~Copyable>(maximumWidth: ExactRationalCoefficient, maximumDepth: Int,
            maximumCoefficientDepth: Int, usage: inout A) throws -> Self {
            guard sourceDepth <= maximumDepth, coefficientAdmissionDepth <= maximumCoefficientDepth,
                maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
                throw rationalAlgebraFailure("Original scalar refinement cannot reset its independent source depths.")
            }
            let result=try intersectionSourceCalculation(originalParameterDepth:0,originalCoefficientDepth:retained.original.context.coefficientDepth,
                inheritedParameterDepth:0,inheritedCoefficientDepth:coefficientAdmissionDepth,
                maximumDepth:maximumDepth,maximumCoefficientDepth:maximumCoefficientDepth,usage:&usage) { admission in
                try intersectionAlgebraStep(&admission)
                return try retained.refined(maximumWidth:maximumWidth,maximumDepth:maximumDepth,usage:&admission)
            }
            return Self(result.value,coefficientDepth:result.coefficientDepth)
        }

        private init(_ retained: OriginalSingularFieldValueIsolation, coefficientDepth: Int) {
            self.retained = retained; lower = retained.lower; upper = retained.upper; sourceDepth = retained.sourceDepth
            coefficientAdmissionDepth = max(coefficientDepth, retained.original.context.coefficientDepth)
        }
        package init<A: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldElement, inheritedDepth: Int,
            inheritedCoefficientDepth: Int, maximumDepth: Int, maximumCoefficientDepth: Int,
            usage: inout A,
            certifiedBounds: (lower: ExactRationalCoefficient, upper: ExactRationalCoefficient)? = nil) throws {
            let parameterDepth = max(inheritedDepth, original.context.depth)
            let coefficientDepth = max(inheritedCoefficientDepth, original.context.coefficientDepth)
            guard parameterDepth <= maximumDepth, coefficientDepth <= maximumCoefficientDepth,
                maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
                throw rationalAlgebraFailure("Original scalar enclosure cannot reset its independent source depths.")
            }
            let result=try intersectionSourceCalculation(originalParameterDepth:0,originalCoefficientDepth:original.context.coefficientDepth,
                inheritedParameterDepth:0,inheritedCoefficientDepth:coefficientDepth,
                maximumDepth:maximumDepth,maximumCoefficientDepth:maximumCoefficientDepth,usage:&usage) { admission in
                try intersectionAlgebraStep(&admission)
                if let certifiedBounds {
                    return try OriginalSingularFieldValueIsolation(original:original,lower:certifiedBounds.lower,
                        upper:certifiedBounds.upper,inheritedDepth:parameterDepth,maximumDepth:maximumDepth,usage:&admission)
                }
                return try OriginalSingularFieldValueIsolation(original:original,inheritedDepth:parameterDepth,
                    maximumDepth:maximumDepth,usage:&admission)
            }
            self.init(result.value,coefficientDepth:result.coefficientDepth)
        }
    }
    package let original: OriginalSingularFieldElement
    package let inheritedDepth: Int
    package let inheritedCoefficientDepth: Int
    private let certifiedBounds: (lower: ExactRationalCoefficient, upper: ExactRationalCoefficient)?

    package init(original: OriginalSingularFieldElement, inheritedDepth: Int,
        inheritedCoefficientDepth: Int = 0,
        certifiedBounds: (lower: ExactRationalCoefficient, upper: ExactRationalCoefficient)? = nil) {
        self.certifiedBounds = certifiedBounds
        self.original = original; self.inheritedDepth = max(inheritedDepth, original.context.depth)
        self.inheritedCoefficientDepth = max(inheritedCoefficientDepth, original.context.coefficientDepth)
    }

    /// Issues one exact rational scalar without an auxiliary algebraic root.
    public static func rational<A: ExactScalarAdmission & ~Copyable>(_ value: ExactRationalCoefficient, usage: inout A) throws -> Self {
        let context = try OriginalSingularFieldContext(usage:&usage)
        return try .init(original:.constant(value,in:context,maximumDepth:0,usage:&usage),inheritedDepth:0)
    }

    public func enclosed<A: ExactScalarAdmission & ~Copyable>(maximumDepth: Int, maximumCoefficientDepth: Int,
        usage: inout A) throws -> Enclosure {
        try Enclosure(original: original, inheritedDepth: inheritedDepth,
            inheritedCoefficientDepth: inheritedCoefficientDepth, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &usage, certifiedBounds: certifiedBounds)
    }
}
