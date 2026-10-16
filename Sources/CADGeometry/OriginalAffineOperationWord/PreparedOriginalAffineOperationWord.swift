import CADCore

/// Reuses an immutable original action under the caller's cumulative admission.
public struct PreparedOriginalAffineOperationWord: Hashable, Sendable {
    public let source: OriginalAffineOperationWord
    init(source: OriginalAffineOperationWord) { self.source = source }
    public var orientationSign: Int { source.orientationSign }

    /// Exposes immutable exact field authority to same-package original producers.
    package func originalNormalizedFrame<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws
        -> (frame: OriginalRationalNormalizedFrame, maximumAlgebraicDepth: Int)? {
        try usage.consumeWork(1)
        guard let frame = source.normalizedFrame else { return nil }
        try OriginalAffineRationalMatrix.retain(1,
            of: (frame: OriginalRationalNormalizedFrame, maximumAlgebraicDepth: Int).self, usage: &usage)
        return (frame, source.maximumDepth)
    }

    public func linearCoefficient(row: Int, column: Int) throws -> ExactRationalCoefficient {
        guard (0..<3).contains(row), (0..<3).contains(column) else {
            throw rationalAlgebraFailure("Original affine coefficient index is out of range.")
        }
        guard source.isRational else {
            throw rationalAlgebraFailure("An algebraic coefficient requires the exact coefficient enclosure path.")
        }
        return source.coefficients[row * 4 + column]
    }
    public func translationCoefficient(row: Int) throws -> ExactRationalCoefficient {
        guard (0..<3).contains(row) else { throw rationalAlgebraFailure("Original affine row is out of range.") }
        guard source.isRational else {
            throw rationalAlgebraFailure("An algebraic translation requires the exact coefficient enclosure path.")
        }
        return source.coefficients[row * 4 + 3]
    }
    public func coefficientEnclosure<B: ExactScalarAdmission & ~Copyable>(row: Int, column: Int,
        usage: inout B) throws -> ScalarInterval {
        guard (0..<3).contains(row), (0..<4).contains(column) else {
            throw rationalAlgebraFailure("Original affine coefficient index is out of range.")
        }
        if let frame = source.normalizedFrame {
            let value = try OriginalAffineFieldAction.coefficient(frame, row: row, column: column,
                maximumDepth: source.maximumDepth, usage: &usage)
            let interval = try OriginalAffineFieldAction.enclosure(value, maximumDepth: source.maximumDepth, usage: &usage)
            return try ScalarInterval(lower: interval.lower, upper: interval.upper)
        }
        let interval = try source.coefficients[row * 4 + column].outwardInterval(usage: &usage)
        return try ScalarInterval(lower: interval.lower, upper: interval.upper)
    }
    /// Applies raw direction and raw scale before final outward conversion.
    public func enclosure<B: ExactScalarAdmission & ~Copyable>(ofOriginalVector vector: Vector3D,
        originalScale: Double, usage: inout B) throws -> CoordinateEnclosure3D {
        try vector.validate()
        guard originalScale.isFinite else { throw GeometryError.invalidCoordinate(originalScale) }
        let scale = try ExactRationalCoefficient.originalDouble(originalScale, usage: &usage)
        let x = try scaledVectorInterval(row: 0, vector: vector, scale: scale, usage: &usage)
        let y = try scaledVectorInterval(row: 1, vector: vector, scale: scale, usage: &usage)
        let z = try scaledVectorInterval(row: 2, vector: vector, scale: scale, usage: &usage)
        return .init(x: x, y: y, z: z)
    }

    private func scaledVectorInterval<B: ExactScalarAdmission & ~Copyable>(row: Int, vector: Vector3D,
        scale: ExactRationalCoefficient, usage: inout B) throws -> ScalarInterval {
        let result: OutwardScalarInterval
        if let frame = source.normalizedFrame {
            var sum = try OriginalSingularFieldElement.constant(.zero, in: frame.context,
                maximumDepth: source.maximumDepth, usage: &usage)
            for column in 0..<3 {
                try usage.consumeWork(1)
                let component = column == 0 ? vector.x : column == 1 ? vector.y : vector.z
                let original = try ExactRationalCoefficient.originalDouble(component, usage: &usage)
                    .multiplied(by: scale, usage: &usage)
                let factor = try OriginalSingularFieldElement.constant(original, in: frame.context,
                    maximumDepth: source.maximumDepth, usage: &usage)
                let coefficient = try OriginalAffineFieldAction.coefficient(frame, row: row, column: column,
                    maximumDepth: source.maximumDepth, usage: &usage)
                sum = try sum.adding(coefficient.multiplied(by: factor, maximumDepth: source.maximumDepth, usage: &usage),
                    maximumDepth: source.maximumDepth, usage: &usage)
            }
            result = try OriginalAffineFieldAction.enclosure(sum, maximumDepth: source.maximumDepth, usage: &usage)
        } else {
            var sum = ExactRationalCoefficient.zero
            for column in 0..<3 {
                try usage.consumeWork(1)
                let component = column == 0 ? vector.x : column == 1 ? vector.y : vector.z
                let original = try ExactRationalCoefficient.originalDouble(component, usage: &usage)
                    .multiplied(by: scale, usage: &usage)
                sum = try sum.adding(source.coefficients[row * 4 + column].multiplied(by: original, usage: &usage), usage: &usage)
            }
            result = try sum.outwardInterval(usage: &usage)
        }
        guard result.isFinite else { throw rationalAlgebraFailure("Original scaled vector image exceeds finite bounds.") }
        return try .init(lower: result.lower, upper: result.upper)
    }

    public func applying<B: ExactScalarAdmission & ~Copyable>(to point: Point3D, usage: inout B) throws -> Point3D {
        if let frame = source.normalizedFrame {
            let values = try frame.applying(to: Vector3D(x: point.x, y: point.y, z: point.z), asPoint: true,
                maximumDepth: source.maximumDepth, usage: &usage)
            let x = try OriginalAffineFieldAction.rounded(values[0], maximumDepth: source.maximumDepth, usage: &usage)
            let y = try OriginalAffineFieldAction.rounded(values[1], maximumDepth: source.maximumDepth, usage: &usage)
            let z = try OriginalAffineFieldAction.rounded(values[2], maximumDepth: source.maximumDepth, usage: &usage)
            return Point3D(x: x, y: y, z: z)
        }
        let x = try scalar(row: 0, input: Vector3D(x: point.x, y: point.y, z: point.z), isPosition: true, usage: &usage)
        let y = try scalar(row: 1, input: Vector3D(x: point.x, y: point.y, z: point.z), isPosition: true, usage: &usage)
        let z = try scalar(row: 2, input: Vector3D(x: point.x, y: point.y, z: point.z), isPosition: true, usage: &usage)
        return Point3D(x: x, y: y, z: z)
    }
    public func applying<B: ExactScalarAdmission & ~Copyable>(to vector: Vector3D, usage: inout B) throws -> Vector3D {
        if let frame = source.normalizedFrame {
            let values = try frame.applying(to: vector, asPoint: false, maximumDepth: source.maximumDepth, usage: &usage)
            let x = try OriginalAffineFieldAction.rounded(values[0], maximumDepth: source.maximumDepth, usage: &usage)
            let y = try OriginalAffineFieldAction.rounded(values[1], maximumDepth: source.maximumDepth, usage: &usage)
            let z = try OriginalAffineFieldAction.rounded(values[2], maximumDepth: source.maximumDepth, usage: &usage)
            return Vector3D(x: x, y: y, z: z)
        }
        let x = try scalar(row: 0, input: vector, isPosition: false, usage: &usage)
        let y = try scalar(row: 1, input: vector, isPosition: false, usage: &usage)
        let z = try scalar(row: 2, input: vector, isPosition: false, usage: &usage)
        return Vector3D(x: x, y: y, z: z)
    }
    private func scalar<B: ExactScalarAdmission & ~Copyable>(row: Int, input: Vector3D,
        isPosition: Bool, usage: inout B) throws -> Double {
        var value: ExactRationalCoefficient = isPosition ? source.coefficients[row * 4 + 3] : .zero
        for column in 0..<3 {
            try usage.consumeWork(1)
            let scalar = column == 0 ? input.x : column == 1 ? input.y : input.z
            let original = try ExactRationalCoefficient.originalDouble(scalar, usage: &usage)
            value = try value.adding(source.coefficients[row * 4 + column].multiplied(by: original, usage: &usage), usage: &usage)
        }
        return try OriginalAffineRationalMatrix.rounded(value, usage: &usage)
    }
    /// Computes exact extrema before outward conversion, including cancellation.
    public func enclosure<B: ExactScalarAdmission & ~Copyable>(of input: CoordinateEnclosure3D,
        isPosition: Bool, usage: inout B) throws -> CoordinateEnclosure3D {
        let x = try interval(row: 0, input: input, isPosition: isPosition, usage: &usage)
        let y = try interval(row: 1, input: input, isPosition: isPosition, usage: &usage)
        let z = try interval(row: 2, input: input, isPosition: isPosition, usage: &usage)
        return CoordinateEnclosure3D(x: x, y: y, z: z)
    }
    private func interval<B: ExactScalarAdmission & ~Copyable>(row: Int, input: CoordinateEnclosure3D,
        isPosition: Bool, usage: inout B) throws -> ScalarInterval {
        if let frame = source.normalizedFrame {
            return try OriginalAffineFieldAction.interval(frame, row: row, input: input, isPosition: isPosition,
                maximumDepth: source.maximumDepth, usage: &usage)
        }
        return try rationalInterval(row: row, input: input, isPosition: isPosition,
            coefficients: source.coefficients, usage: &usage)
    }
    private func rationalInterval<B: ExactScalarAdmission & ~Copyable>(row: Int, input: CoordinateEnclosure3D,
        isPosition: Bool, coefficients: [ExactRationalCoefficient], usage: inout B) throws -> ScalarInterval {
        var lower: ExactRationalCoefficient = isPosition ? coefficients[row * 4 + 3] : .zero
        var upper = lower
        for column in 0..<3 {
            try usage.consumeWork(1)
            let interval = column == 0 ? input.x : column == 1 ? input.y : input.z
            let coefficient = coefficients[row * 4 + column]
            let low = try ExactRationalCoefficient.originalDouble(coefficient.isNegative ? interval.upper : interval.lower, usage: &usage)
            let high = try ExactRationalCoefficient.originalDouble(coefficient.isNegative ? interval.lower : interval.upper, usage: &usage)
            lower = try lower.adding(coefficient.multiplied(by: low, usage: &usage), usage: &usage)
            upper = try upper.adding(coefficient.multiplied(by: high, usage: &usage), usage: &usage)
        }
        let lo = try lower.outwardInterval(usage: &usage), hi = try upper.outwardInterval(usage: &usage)
        return try ScalarInterval(lower: lo.lower, upper: hi.upper)
    }
    /// Transports an original cross-product normal by Cof(A), including reflections.
    public func applyingCofactor<B: ExactScalarAdmission & ~Copyable>(to input: CoordinateEnclosure3D,
        usage: inout B) throws -> CoordinateEnclosure3D {
        let x: ScalarInterval, y: ScalarInterval, z: ScalarInterval
        if source.isRational {
            x = try rationalInterval(row: 0, input: input, isPosition: false, coefficients: source.cofactorCoefficients, usage: &usage)
            y = try rationalInterval(row: 1, input: input, isPosition: false, coefficients: source.cofactorCoefficients, usage: &usage)
            z = try rationalInterval(row: 2, input: input, isPosition: false, coefficients: source.cofactorCoefficients, usage: &usage)
        } else {
            x = try OriginalAffineFieldAction.cofactorInterval(source.normalizedCofactors, row: 0, input: input, maximumDepth: source.maximumDepth, usage: &usage)
            y = try OriginalAffineFieldAction.cofactorInterval(source.normalizedCofactors, row: 1, input: input, maximumDepth: source.maximumDepth, usage: &usage)
            z = try OriginalAffineFieldAction.cofactorInterval(source.normalizedCofactors, row: 2, input: input, maximumDepth: source.maximumDepth, usage: &usage)
        }
        return CoordinateEnclosure3D(x: x, y: y, z: z)
    }

    /// Rigorous Frobenius upper bounds, with exact products before final square roots.
    public func conditionBounds<B: ExactScalarAdmission & ~Copyable>(usage: inout B)
        throws -> (linearNormUpper: Double, cofactorConditionUpper: Double) {
        if source.isRational {
            var a = ExactRationalCoefficient.zero, c = ExactRationalCoefficient.zero
            for row in 0..<3 {
                for column in 0..<3 {
                    try usage.consumeWork(1)
                    let x = source.coefficients[row * 4 + column], y = source.cofactorCoefficients[row * 4 + column]
                    a = try a.adding(x.multiplied(by: x, usage: &usage), usage: &usage)
                    c = try c.adding(y.multiplied(by: y, usage: &usage), usage: &usage)
                }
            }
            let d2 = try source.determinantCoefficient.multiplied(by: source.determinantCoefficient, usage: &usage)
            let conditionSquared = try a.multiplied(by: c, usage: &usage).divided(by: d2, usage: &usage)
            let linear = try OriginalAffineRationalMatrix.squareRootUpper(a, usage: &usage)
            let condition = try OriginalAffineRationalMatrix.squareRootUpper(conditionSquared, usage: &usage)
            return (linear, condition)
        }
        guard let frame = source.normalizedFrame, let determinant = source.normalizedDeterminant else {
            throw rationalAlgebraFailure("Original word is missing its immutable action receipt.")
        }
        let depth = source.maximumDepth
        var a = try OriginalSingularFieldElement.constant(.zero, in: frame.context, maximumDepth: depth, usage: &usage)
        var c = a
        for row in 0..<3 {
            for column in 0..<3 {
                try usage.consumeWork(1)
                let x = try OriginalAffineFieldAction.coefficient(frame, row: row, column: column, maximumDepth: depth, usage: &usage)
                let y = source.normalizedCofactors[row * 3 + column]
                a = try a.adding(x.multiplied(by: x, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
                c = try c.adding(y.multiplied(by: y, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            }
        }
        let d2 = try determinant.multiplied(by: determinant, maximumDepth: depth, usage: &usage)
        let conditionSquared = try a.multiplied(by: c, maximumDepth: depth, usage: &usage)
            .divided(by: d2, maximumDepth: depth, usage: &usage)
        let linear = try OriginalAffineFieldAction.squareRootUpper(a, maximumDepth: depth, usage: &usage)
        let condition = try OriginalAffineFieldAction.squareRootUpper(conditionSquared, maximumDepth: depth, usage: &usage)
        return (linear, condition)
    }

    /// Proves the exact image equals an authored binary point, without rounded equality.
    public func maps<B: ExactScalarAdmission & ~Copyable>(_ original: Point3D, exactlyTo target: Point3D,
        usage: inout B) throws -> Bool {
        try original.validate(); try target.validate()
        if let frame = source.normalizedFrame {
            let values = try frame.applying(to: Vector3D(x: original.x, y: original.y, z: original.z),
                asPoint: true, maximumDepth: source.maximumDepth, usage: &usage)
            for row in 0..<3 {
                try usage.consumeWork(1)
                let scalar = row == 0 ? target.x : row == 1 ? target.y : target.z
                let rational = try ExactRationalCoefficient.originalDouble(scalar, usage: &usage)
                switch try OriginalAffineFieldAction.compare(values[row], with: rational,
                    maximumDepth: source.maximumDepth, usage: &usage) {
                case .zero: break
                default: return false
                }
            }
            return true
        }
        for row in 0..<3 {
            var value = source.coefficients[row * 4 + 3]
            for column in 0..<3 {
                try usage.consumeWork(1)
                let scalar = column == 0 ? original.x : column == 1 ? original.y : original.z
                let rational = try ExactRationalCoefficient.originalDouble(scalar, usage: &usage)
                value = try value.adding(source.coefficients[row * 4 + column].multiplied(by: rational, usage: &usage), usage: &usage)
            }
            let scalar = row == 0 ? target.x : row == 1 ? target.y : target.z
            let rational = try ExactRationalCoefficient.originalDouble(scalar, usage: &usage)
            if try !value.subtracting(rational, usage: &usage).isZero { return false }
        }
        return true
    }

}
