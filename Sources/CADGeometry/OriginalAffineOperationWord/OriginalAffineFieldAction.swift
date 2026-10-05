import CADCore

/// Exact algebraic cache actions; binary comparisons never replace original laws.
enum OriginalAffineFieldAction {
    static func coefficient<B: RationalAlgebraAdmitting>(_ frame: OriginalRationalNormalizedFrame,
        row: Int, column: Int, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let value = column == 0 ? frame.basisX[row] : column == 1 ? frame.basisY[row]
            : column == 2 ? frame.basisZ[row] : frame.translation[row]
        return try value.embedded(in: frame.context, maximumDepth: maximumDepth, usage: &usage)
    }
    static func cofactors<B: RationalAlgebraAdmitting>(_ frame: OriginalRationalNormalizedFrame,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        try OriginalAffineRationalMatrix.retain(9, of: OriginalSingularFieldElement.self, usage: &usage)
        var result: [OriginalSingularFieldElement] = []; result.reserveCapacity(9)
        for row in 0..<3 {
            for column in 0..<3 {
                try usage.consumeExactWork(1)
                let r0 = row == 0 ? 1 : 0, r1 = row == 2 ? 1 : 2
                let c0 = column == 0 ? 1 : 0, c1 = column == 2 ? 1 : 2
                let a = try coefficient(frame, row: r0, column: c0, maximumDepth: maximumDepth, usage: &usage)
                let b = try coefficient(frame, row: r1, column: c1, maximumDepth: maximumDepth, usage: &usage)
                let c = try coefficient(frame, row: r0, column: c1, maximumDepth: maximumDepth, usage: &usage)
                let d = try coefficient(frame, row: r1, column: c0, maximumDepth: maximumDepth, usage: &usage)
                var value = try a.multiplied(by: b, maximumDepth: maximumDepth, usage: &usage)
                    .subtracting(c.multiplied(by: d, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                if (row + column) % 2 != 0 { value = try value.negated(maximumDepth: maximumDepth, usage: &usage) }
                result.append(value)
            }
        }
        return result
    }
    static func cofactorInterval<B: RationalAlgebraAdmitting>(_ coefficients: [OriginalSingularFieldElement],
        row: Int, input: CoordinateEnclosure3D, maximumDepth: Int, usage: inout B) throws -> ScalarInterval {
        let context = coefficients[row * 3].context
        var lower = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        var upper = lower
        for column in 0..<3 {
            try usage.consumeExactWork(1)
            let c = coefficients[row * 3 + column]
            let negative: Bool
            switch try c.sign(maximumDepth: maximumDepth, usage: &usage) { case .negative: negative = true; default: negative = false }
            let interval = column == 0 ? input.x : column == 1 ? input.y : input.z
            let a = try OriginalSingularFieldElement.constant(.originalDouble(negative ? interval.upper : interval.lower, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage)
            let b = try OriginalSingularFieldElement.constant(.originalDouble(negative ? interval.lower : interval.upper, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage)
            lower = try lower.adding(c.multiplied(by: a, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            upper = try upper.adding(c.multiplied(by: b, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        }
        let a = try enclosure(lower, maximumDepth: maximumDepth, usage: &usage)
        let b = try enclosure(upper, maximumDepth: maximumDepth, usage: &usage)
        return try ScalarInterval(lower: a.lower, upper: b.upper)
    }
    static func determinant<B: RationalAlgebraAdmitting>(_ frame: OriginalRationalNormalizedFrame,
        cofactors: [OriginalSingularFieldElement], maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        var result = try OriginalSingularFieldElement.constant(.zero, in: frame.context, maximumDepth: maximumDepth, usage: &usage)
        for column in 0..<3 {
            try usage.consumeExactWork(1)
            let a = try coefficient(frame, row: 0, column: column, maximumDepth: maximumDepth, usage: &usage)
            result = try result.adding(a.multiplied(by: cofactors[column], maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
    static func squareRootUpper<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> Double {
        if let rational = try value.rationalValue(usage: &usage) {
            return try OriginalAffineRationalMatrix.squareRootUpper(rational, usage: &usage)
        }
        switch try value.sign(maximumDepth: maximumDepth, usage: &usage) {
        case .negative: throw rationalAlgebraFailure("Original squared norm is negative.")
        case .zero: return 0
        case .positive: break
        }
        let maximum = try ExactRationalCoefficient.originalDouble(Double.greatestFiniteMagnitude, usage: &usage)
        let square = try maximum.multiplied(by: maximum, usage: &usage)
        switch try compare(value, with: square, maximumDepth: maximumDepth, usage: &usage) {
        case .positive: throw rationalAlgebraFailure("Original norm exceeds finite binary range.")
        case .zero: return Double.greatestFiniteMagnitude
        case .negative: break
        }
        var lower: UInt64 = 0, upper = Double.greatestFiniteMagnitude.bitPattern
        while upper - lower > 1 {
            try usage.consumeExactWork(1)
            let middle = lower + (upper - lower) / 2
            let candidate = try ExactRationalCoefficient.originalDouble(Double(bitPattern: middle), usage: &usage)
            let square = try candidate.multiplied(by: candidate, usage: &usage)
            switch try compare(value, with: square, maximumDepth: maximumDepth, usage: &usage) {
            case .zero: return Double(bitPattern: middle)
            case .positive: lower = middle
            case .negative: upper = middle
            }
        }
        return Double(bitPattern: upper)
    }
    static func compare<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        with rational: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try value.subtracting(.constant(rational, in: value.context, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage)
    }
    /// IEEE finite positive bit patterns are monotone; each comparison is exact.
    static func enclosure<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> OutwardScalarInterval {
        if let rational = try value.rationalValue(usage: &usage) { return try rational.outwardInterval(usage: &usage) }
        let sign = try value.sign(maximumDepth: maximumDepth, usage: &usage)
        if case .zero = sign { return .exact(0) }
        let negative: Bool
        switch sign { case .negative: negative = true; default: negative = false }
        let magnitude: OriginalSingularFieldElement
        if negative { magnitude = try value.negated(maximumDepth: maximumDepth, usage: &usage) }
        else { magnitude = value }
        let maximum = Double.greatestFiniteMagnitude
        let maximumComparison = try compare(magnitude, with: .originalDouble(maximum, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        if case .positive = maximumComparison { throw rationalAlgebraFailure("Original algebraic action exceeds finite binary range.") }
        if case .zero = maximumComparison { return .exact(negative ? -maximum : maximum) }
        var lower: UInt64 = 0, upper = maximum.bitPattern
        while upper - lower > 1 {
            try usage.consumeExactWork(1)
            let middle = lower + (upper - lower) / 2
            let candidate = Double(bitPattern: middle)
            switch try compare(magnitude, with: .originalDouble(candidate, usage: &usage), maximumDepth: maximumDepth, usage: &usage) {
            case .zero: return .exact(negative ? -candidate : candidate)
            case .positive: lower = middle
            case .negative: upper = middle
            }
        }
        let a = Double(bitPattern: lower), b = Double(bitPattern: upper)
        return negative ? OutwardScalarInterval(lower: -b, upper: -a) : OutwardScalarInterval(lower: a, upper: b)
    }
    static func rounded<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> Double {
        let interval = try enclosure(value, maximumDepth: maximumDepth, usage: &usage)
        if interval.lower == interval.upper { return interval.lower }
        let a = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &usage)
        let b = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &usage)
        let two = try ExactRationalCoefficient.one.adding(.one, usage: &usage)
        let midpoint = try a.adding(b, usage: &usage).divided(by: two, usage: &usage)
        switch try compare(value, with: midpoint, maximumDepth: maximumDepth, usage: &usage) {
        case .negative: return interval.lower
        case .positive: return interval.upper
        case .zero: return interval.lower.bitPattern & 1 == 0 ? interval.lower : interval.upper
        }
    }
    static func interval<B: RationalAlgebraAdmitting>(_ frame: OriginalRationalNormalizedFrame,
        row: Int, input: CoordinateEnclosure3D, isPosition: Bool, maximumDepth: Int, usage: inout B) throws -> ScalarInterval {
        var lower: OriginalSingularFieldElement
        if isPosition { lower = try coefficient(frame, row: row, column: 3, maximumDepth: maximumDepth, usage: &usage) }
        else { lower = try .constant(.zero, in: frame.context, maximumDepth: maximumDepth, usage: &usage) }
        var upper = lower
        for column in 0..<3 {
            try usage.consumeExactWork(1)
            let c = try coefficient(frame, row: row, column: column, maximumDepth: maximumDepth, usage: &usage)
            let sign = try c.sign(maximumDepth: maximumDepth, usage: &usage)
            let negative: Bool
            switch sign { case .negative: negative = true; default: negative = false }
            let interval = column == 0 ? input.x : column == 1 ? input.y : input.z
            let a = try OriginalSingularFieldElement.constant(.originalDouble(negative ? interval.upper : interval.lower, usage: &usage), in: frame.context, maximumDepth: maximumDepth, usage: &usage)
            let b = try OriginalSingularFieldElement.constant(.originalDouble(negative ? interval.lower : interval.upper, usage: &usage), in: frame.context, maximumDepth: maximumDepth, usage: &usage)
            lower = try lower.adding(c.multiplied(by: a, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            upper = try upper.adding(c.multiplied(by: b, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        }
        let a = try enclosure(lower, maximumDepth: maximumDepth, usage: &usage)
        let b = try enclosure(upper, maximumDepth: maximumDepth, usage: &usage)
        return try ScalarInterval(lower: a.lower, upper: b.upper)
    }
}
