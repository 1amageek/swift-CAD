/// A retained exact cell sample; it never represents the whole cell's range.
public struct OriginalAlgebraicCoordinate: Sendable {
    public struct Enclosure: Sendable {
        public let lower: ExactRationalCoefficient
        public let upper: ExactRationalCoefficient
        public let sourceDepth: Int
        public let coefficientAdmissionDepth: Int
        package let retained: OriginalSingularFieldValueIsolation

        /// Refines the same original value while preserving both causal depth domains.
        public func refined(maximumWidth: ExactRationalCoefficient, maximumDepth: Int,
            maximumCoefficientDepth: Int, usage: OriginalRelationUsage) throws -> Self {
            guard sourceDepth <= maximumDepth, coefficientAdmissionDepth <= maximumCoefficientDepth,
                maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
                throw rationalAlgebraFailure("Original scalar refinement cannot reset its independent source depths.")
            }
            var admission = Self.admission(original: retained.original, parameterDepth: sourceDepth,
                coefficientDepth: coefficientAdmissionDepth, maximumDepth: maximumDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, usage: usage)
            try intersectionAlgebraStep(&admission)
            let value = try retained.refined(maximumWidth: maximumWidth, maximumDepth: maximumDepth, usage: &admission)
            return Self(value, coefficientDepth: admission.coefficientDepth)
        }
        private init(_ retained: OriginalSingularFieldValueIsolation, coefficientDepth: Int) {
            self.retained = retained; lower = retained.lower; upper = retained.upper; sourceDepth = retained.sourceDepth
            coefficientAdmissionDepth = max(coefficientDepth, retained.original.context.coefficientDepth)
        }
        private static func admission(original: OriginalSingularFieldElement, parameterDepth: Int,
            coefficientDepth: Int, maximumDepth: Int, maximumCoefficientDepth: Int,
            usage: OriginalRelationUsage) -> OriginalSourceScalarAdmission<OriginalRelationUsage> {
            // The value isolation already maps parameter refinement to its causal baseline.
            // Keep this outer parameter mapping identical and map coefficient refinement only.
            .init(base: usage, maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth,
                originalParameterDepth: 0, originalCoefficientDepth: original.context.coefficientDepth,
                inheritedParameterDepth: 0, inheritedCoefficientDepth: coefficientDepth,
                parameterDepth: parameterDepth, coefficientDepth: coefficientDepth)
        }
        package init(original: OriginalSingularFieldElement, inheritedDepth: Int,
            inheritedCoefficientDepth: Int, maximumDepth: Int, maximumCoefficientDepth: Int,
            usage: OriginalRelationUsage) throws {
            let parameterDepth = max(inheritedDepth, original.context.depth)
            let coefficientDepth = max(inheritedCoefficientDepth, original.context.coefficientDepth)
            guard parameterDepth <= maximumDepth, coefficientDepth <= maximumCoefficientDepth,
                maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
                throw rationalAlgebraFailure("Original scalar enclosure cannot reset its independent source depths.")
            }
            var admission = Self.admission(original: original, parameterDepth: parameterDepth,
                coefficientDepth: coefficientDepth, maximumDepth: maximumDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, usage: usage)
            try intersectionAlgebraStep(&admission)
            let value = try OriginalSingularFieldValueIsolation(original: original, inheritedDepth: parameterDepth,
                maximumDepth: maximumDepth, usage: &admission)
            self.init(value, coefficientDepth: admission.coefficientDepth)
        }
    }
    package let original: OriginalSingularFieldElement
    package let inheritedDepth: Int
    package let inheritedCoefficientDepth: Int

    package init(original: OriginalSingularFieldElement, inheritedDepth: Int,
        inheritedCoefficientDepth: Int = 0) {
        self.original = original; self.inheritedDepth = max(inheritedDepth, original.context.depth)
        self.inheritedCoefficientDepth = max(inheritedCoefficientDepth, original.context.coefficientDepth)
    }

    /// Issues one exact rational scalar without an auxiliary algebraic root.
    public static func rational(_ value: ExactRationalCoefficient, usage: OriginalRelationUsage) throws -> Self {
        var admission = usage
        let context = try OriginalSingularFieldContext(usage: &admission)
        return try .init(original: .constant(value, in: context, maximumDepth: 0, usage: &admission), inheritedDepth: 0)
    }

    public func enclosed(maximumDepth: Int, maximumCoefficientDepth: Int,
        usage: OriginalRelationUsage) throws -> Enclosure {
        try Enclosure(original: original, inheritedDepth: inheritedDepth,
            inheritedCoefficientDepth: inheritedCoefficientDepth, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: usage)
    }
}
