import CADCore

/// Actual common real edge fiber over one retained original UV incidence.
struct OriginalProjectedNativeFiber: Sendable {
    enum Parameters: Sendable {
        case isolated(root: OriginalSingularFieldRoot, value: OriginalSingularFieldElement, multiplicity: Int)
        case wholeNativeRange
    }
    let context: OriginalSingularFieldContext
    let originalUV: ExactBivariateSystemRoot
    let horizontal: OriginalSingularFieldPolynomial
    let vertical: OriginalSingularFieldPolynomial
    let common: OriginalSingularFieldPolynomial
    let parameters: [Parameters]

    init(original: OriginalProjectedNativePolynomialPair, at point: ExactBivariateSystemRoot,
        usage: inout SurfaceSilhouetteUsage) throws {
        originalUV = point
        let context = try OriginalSingularFieldContext(original: point, usage: &usage)
        self.context = context
        let horizontal = try original.horizontal.specialized(in: context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let vertical = try original.vertical.specialized(in: context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        self.horizontal = horizontal; self.vertical = vertical
        let common = try OriginalSingularFieldPolynomial.gcd(horizontal, vertical,
            maximumDepth: usage.maximumDepth, usage: &usage)
        self.common = common
        if common.isZero {
            guard horizontal.isZero, vertical.isZero else {
                throw rationalAlgebraFailure("Original projected fiber GCD contradicts its source equations.")
            }
            try RationalAlgebraStorage.retain(1, of: Parameters.self, usage: &usage)
            parameters = [.wholeNativeRange]; return
        }
        if common.degree == 0 { parameters = []; return }
        let lower = try ExactRationalCoefficient.originalDouble(original.edgeRange.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(original.edgeRange.upper, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
        let coordinate = try OriginalSingularFieldPolynomial(context: context, coefficients: [zero, one],
            maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        let first = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [.constant(lower, in: context, maximumDepth: usage.maximumDepth, usage: &usage)],
            maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        let last = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [.constant(upper, in: context, maximumDepth: usage.maximumDepth, usage: &usage)],
            maximumDepth: usage.maximumDepth, usage: &usage)
        let lowDifference = try coordinate.subtracting(first, maximumDepth: usage.maximumDepth, usage: &usage)
        let highDifference = try last.subtracting(coordinate, maximumDepth: usage.maximumDepth, usage: &usage)
        var values: [Parameters] = []
        for root in try OriginalSingularFieldRoot.allRealRoots(common,
            inheritedDepth: context.depth, maximumDepth: usage.maximumDepth, usage: &usage) {
            if case .negative = try root.sign(of: lowDifference, maximumDepth: usage.maximumDepth, usage: &usage) { continue }
            if case .negative = try root.sign(of: highDifference, maximumDepth: usage.maximumDepth, usage: &usage) { continue }
            // Both ORIGINAL screen laws must vanish, not merely their resultant.
            guard case .zero = try root.sign(of: horizontal, maximumDepth: usage.maximumDepth, usage: &usage),
                case .zero = try root.sign(of: vertical, maximumDepth: usage.maximumDepth, usage: &usage) else {
                throw rationalAlgebraFailure("Lifted projected edge fiber violates an original screen equation.")
            }
            var differentiated = common
            var multiplicity = 0
            while !differentiated.isZero {
                guard case .zero = try root.sign(of: differentiated, maximumDepth: usage.maximumDepth, usage: &usage) else { break }
                multiplicity = try rationalAlgebraCount(multiplicity, 1)
                differentiated = try differentiated.differentiated(maximumDepth: usage.maximumDepth, usage: &usage)
            }
            guard multiplicity > 0 else { throw rationalAlgebraFailure("Projected original fiber has no root multiplicity.") }
            let value = try root.value(maximumDepth: usage.maximumDepth, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: Parameters.self, usage: &usage)
            values.append(.isolated(root: root, value: value, multiplicity: multiplicity))
        }
        parameters = values
    }
}
