import CADCore

/// Exact row-major 3x4 affine cache operations; no floating matrix is manufactured.
enum OriginalAffineRationalMatrix {
    static func retain<T, B: RationalAlgebraAdmitting>(_ count: Int, of type: T.Type,
                                                     usage: inout B) throws {
        let bytes = try rationalAlgebraCount(count, MemoryLayout<T>.stride, multiply: true)
        let words = try rationalAlgebraCount(bytes, MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
        try usage.retainExactStorage(words)
    }
    static func identity<B: RationalAlgebraAdmitting>(usage: inout B) throws -> [ExactRationalCoefficient] {
        try retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        return [.one, .zero, .zero, .zero, .zero, .one, .zero, .zero, .zero, .zero, .one, .zero]
    }
    static func original<B: RationalAlgebraAdmitting>(_ source: AffineTransform3D,
                                                     usage: inout B) throws -> [ExactRationalCoefficient] {
        try source.validate(); try usage.consumeExactWork(12)
        try retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        let x = source.basisX, y = source.basisY, z = source.basisZ, t = source.translation
        // Fixed-size original scalars remain on the stack; each rational limb is
        // separately admitted by originalDouble before allocation.
        var result: [ExactRationalCoefficient] = []; result.reserveCapacity(12)
        result.append(try .originalDouble(x.x, usage: &usage))
        result.append(try .originalDouble(y.x, usage: &usage))
        result.append(try .originalDouble(z.x, usage: &usage))
        result.append(try .originalDouble(t.x, usage: &usage))
        result.append(try .originalDouble(x.y, usage: &usage))
        result.append(try .originalDouble(y.y, usage: &usage))
        result.append(try .originalDouble(z.y, usage: &usage))
        result.append(try .originalDouble(t.y, usage: &usage))
        result.append(try .originalDouble(x.z, usage: &usage))
        result.append(try .originalDouble(y.z, usage: &usage))
        result.append(try .originalDouble(z.z, usage: &usage))
        result.append(try .originalDouble(t.z, usage: &usage))
        return result
    }
    static func original<B: RationalAlgebraAdmitting>(_ operation: OriginalAffineOperation,
        usage: inout B) throws -> [ExactRationalCoefficient]? {
        switch operation {
        case .forward(let transform), .inverse(let transform):
            return try original(transform, usage: &usage)
        case .rationalForward(let source), .rationalInverse(let source):
            try source.validateOriginalPayload(usage: &usage)
            return source.coefficients
        case .normalizedForward, .normalizedInverse: return nil
        }
    }

    static func minor<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        excludingRow row: Int, column: Int, usage: inout B) throws -> ExactRationalCoefficient {
        let r0 = row == 0 ? 1 : 0, r1 = row == 2 ? 1 : 2
        let c0 = column == 0 ? 1 : 0, c1 = column == 2 ? 1 : 2
        let first = try a[r0 * 4 + c0].multiplied(by: a[r1 * 4 + c1], usage: &usage)
        let second = try a[r0 * 4 + c1].multiplied(by: a[r1 * 4 + c0], usage: &usage)
        return try first.subtracting(second, usage: &usage)
    }
    static func determinant<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
                                                        usage: inout B) throws -> ExactRationalCoefficient {
        var value = ExactRationalCoefficient.zero
        for column in 0..<3 {
            try usage.consumeExactWork(1)
            let cofactor = try minor(a, excludingRow: 0, column: column, usage: &usage)
            let product = try a[column].multiplied(by: column == 1 ? cofactor.negated : cofactor, usage: &usage)
            value = try value.adding(product, usage: &usage)
        }
        return value
    }
    static func cofactors<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        usage: inout B) throws -> [ExactRationalCoefficient] {
        try retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        var result = Array(repeating: ExactRationalCoefficient.zero, count: 12)
        for row in 0..<3 {
            for column in 0..<3 {
                try usage.consumeExactWork(1)
                let value = try minor(a, excludingRow: row, column: column, usage: &usage)
                result[row * 4 + column] = (row + column) % 2 == 0 ? value : value.negated
            }
        }
        return result
    }
    static func inverse<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        determinant: ExactRationalCoefficient, usage: inout B) throws -> [ExactRationalCoefficient] {
        try retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        var result = Array(repeating: ExactRationalCoefficient.zero, count: 12)
        for row in 0..<3 {
            for column in 0..<3 {
                try usage.consumeExactWork(1)
                let cofactor = try minor(a, excludingRow: column, column: row, usage: &usage)
                result[row * 4 + column] = try ((row + column) % 2 == 0 ? cofactor : cofactor.negated)
                    .divided(by: determinant, usage: &usage)
            }
            var translation = ExactRationalCoefficient.zero
            for column in 0..<3 {
                try usage.consumeExactWork(1)
                translation = try translation.adding(result[row * 4 + column]
                    .multiplied(by: a[column * 4 + 3], usage: &usage), usage: &usage)
            }
            result[row * 4 + 3] = translation.negated
        }
        return result
    }
    static func compose<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        after b: [ExactRationalCoefficient], usage: inout B) throws -> [ExactRationalCoefficient] {
        try retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        var result = Array(repeating: ExactRationalCoefficient.zero, count: 12)
        for row in 0..<3 {
            for column in 0..<4 {
                var value: ExactRationalCoefficient = column == 3 ? a[row * 4 + 3] : .zero
                for k in 0..<3 {
                    try usage.consumeExactWork(1)
                    value = try value.adding(a[row * 4 + k].multiplied(by: b[k * 4 + column], usage: &usage), usage: &usage)
                }
                result[row * 4 + column] = value
            }
        }
        return result
    }
    static func squareRootUpper<B: RationalAlgebraAdmitting>(_ value: ExactRationalCoefficient,
        usage: inout B) throws -> Double {
        guard !value.isNegative else { throw rationalAlgebraFailure("Original squared norm is negative.") }
        if value.isZero { return 0 }
        let maximum = try ExactRationalCoefficient.originalDouble(Double.greatestFiniteMagnitude, usage: &usage)
        let difference = try value.subtracting(maximum.multiplied(by: maximum, usage: &usage), usage: &usage)
        guard !difference.isPositive else { throw rationalAlgebraFailure("Original norm exceeds finite binary range.") }
        if difference.isZero { return Double.greatestFiniteMagnitude }
        var lower: UInt64 = 0, upper = Double.greatestFiniteMagnitude.bitPattern
        while upper - lower > 1 {
            try usage.consumeExactWork(1)
            let middle = lower + (upper - lower) / 2
            let candidate = try ExactRationalCoefficient.originalDouble(Double(bitPattern: middle), usage: &usage)
            let comparison = try value.subtracting(candidate.multiplied(by: candidate, usage: &usage), usage: &usage)
            if comparison.isZero { return Double(bitPattern: middle) }
            if comparison.isPositive { lower = middle } else { upper = middle }
        }
        return Double(bitPattern: upper)
    }
    static func rounded<B: RationalAlgebraAdmitting>(_ value: ExactRationalCoefficient,
                                                    usage: inout B) throws -> Double {
        let interval = try value.outwardInterval(usage: &usage)
        if interval.lower == interval.upper { return interval.lower }
        let lower = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &usage)
        let two = try ExactRationalCoefficient.one.adding(.one, usage: &usage)
        let midpoint = try lower.adding(upper, usage: &usage).divided(by: two, usage: &usage)
        let comparison = try value.subtracting(midpoint, usage: &usage)
        if comparison.isZero { return interval.lower.bitPattern & 1 == 0 ? interval.lower : interval.upper }
        return comparison.isPositive ? interval.upper : interval.lower
    }
}
