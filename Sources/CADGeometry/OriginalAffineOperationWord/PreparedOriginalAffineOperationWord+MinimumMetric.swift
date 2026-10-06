import CADCore

extension PreparedOriginalAffineOperationWord {
    /// Proves the whole two- or three-dimensional original unit-direction metric.
    public func minimumImageLengthIsGreaterThan<B: RationalAlgebraAdmitting>(
        originalAxes: [Vector3D], originalLengths: [Double], physicalThreshold: Double,
        usage: inout B) throws -> Bool {
        guard originalAxes.count == originalLengths.count else {
            throw rationalAlgebraFailure("Original metric axes and lengths must correspond.")
        }
        try validateMetricInput(originalAxes, physicalThreshold: physicalThreshold, usage: &usage)
        try OriginalAffineRationalMatrix.retain(originalLengths.count, of: ExactRationalCoefficient.self, usage: &usage)
        var lengths: [ExactRationalCoefficient] = []; lengths.reserveCapacity(originalLengths.count)
        for length in originalLengths {
            try usage.consumeExactWork(1)
            guard length.isFinite, length >= 0 else { throw rationalAlgebraFailure("Original metric lengths must be finite and nonnegative.") }
            lengths.append(try .originalDouble(length, usage: &usage))
        }
        return try minimumMetric(originalAxes, lengths: lengths, physicalThreshold: physicalThreshold, usage: &usage)
    }

    /// Uses the exact original difference as every axis length, without binary subtraction.
    public func minimumImageDifferenceIsGreaterThan<B: RationalAlgebraAdmitting>(
        originalAxes: [Vector3D], originalLower: Double, originalUpper: Double,
        physicalThreshold: Double, usage: inout B) throws -> Bool {
        try validateMetricInput(originalAxes, physicalThreshold: physicalThreshold, usage: &usage)
        guard originalLower.isFinite, originalLower >= 0, originalUpper.isFinite,
              originalUpper >= originalLower else { throw rationalAlgebraFailure("Original metric gap requires ordered finite nonnegative lengths.") }
        let lower = try ExactRationalCoefficient.originalDouble(originalLower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(originalUpper, usage: &usage)
        let gap = try upper.subtracting(lower, usage: &usage)
        try OriginalAffineRationalMatrix.retain(originalAxes.count, of: ExactRationalCoefficient.self, usage: &usage)
        let lengths = Array(repeating: gap, count: originalAxes.count)
        return try minimumMetric(originalAxes, lengths: lengths, physicalThreshold: physicalThreshold, usage: &usage)
    }

    /// Proves the complete original radial gap measured perpendicular to the transformed axis.
    public func minimumProjectedImageDifferenceIsGreaterThan<B: RationalAlgebraAdmitting>(
        originalAxes: [Vector3D], originalAxis: Vector3D, originalLower: Double,
        originalUpper: Double, physicalThreshold: Double, usage: inout B) throws -> Bool {
        guard originalAxes.count == 2 else {
            throw rationalAlgebraFailure("Original projected metric requires two radial axes.")
        }
        try validateMetricInput(originalAxes, physicalThreshold: physicalThreshold, usage: &usage)
        try usage.consumeExactWork(3)
        try originalAxis.validate()
        guard originalLower.isFinite, originalLower >= 0, originalUpper.isFinite,
              originalUpper >= originalLower else {
            throw rationalAlgebraFailure("Original projected gap requires ordered finite nonnegative lengths.")
        }
        let lower = try ExactRationalCoefficient.originalDouble(originalLower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(originalUpper, usage: &usage)
        let gap = try upper.subtracting(lower, usage: &usage)
        try OriginalAffineRationalMatrix.retain(3, of: Vector3D.self, usage: &usage)
        var axes: [Vector3D] = []; axes.reserveCapacity(3)
        axes.append(originalAxes[0]); axes.append(originalAxes[1]); axes.append(originalAxis)
        try OriginalAffineRationalMatrix.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
        var lengths: [ExactRationalCoefficient] = []; lengths.reserveCapacity(3)
        lengths.append(gap); lengths.append(gap); lengths.append(.one)
        return try minimumMetric(axes, lengths: lengths, physicalThreshold: physicalThreshold,
            projectsLastAxis: true, usage: &usage)
    }

    private func validateMetricInput<B: RationalAlgebraAdmitting>(_ axes: [Vector3D],
        physicalThreshold: Double, usage: inout B) throws {
        guard (2...3).contains(axes.count), physicalThreshold.isFinite, physicalThreshold >= 0 else {
            throw rationalAlgebraFailure("Original minimum metric requires two or three axes and a finite nonnegative threshold.")
        }
        for axis in axes { try usage.consumeExactWork(3); try axis.validate() }
    }

    private func minimumMetric<B: RationalAlgebraAdmitting>(_ axes: [Vector3D],
        lengths: [ExactRationalCoefficient], physicalThreshold: Double, projectsLastAxis: Bool = false,
        usage: inout B) throws -> Bool {
        let threshold = try ExactRationalCoefficient.originalDouble(physicalThreshold, usage: &usage)
        let square = try threshold.multiplied(by: threshold, usage: &usage)
        let count = axes.count
        if source.isRational {
            try OriginalAffineRationalMatrix.retain(count * 3, of: ExactRationalCoefficient.self, usage: &usage)
            var columns = Array(repeating: ExactRationalCoefficient.zero, count: count * 3)
            for column in 0..<count {
                let x = try ExactRationalCoefficient.originalDouble(axes[column].x, usage: &usage)
                let y = try ExactRationalCoefficient.originalDouble(axes[column].y, usage: &usage)
                let z = try ExactRationalCoefficient.originalDouble(axes[column].z, usage: &usage)
                for row in 0..<3 {
                    try usage.consumeExactWork(3)
                    let first = try source.coefficients[row * 4].multiplied(by: x, usage: &usage)
                    let second = try source.coefficients[row * 4 + 1].multiplied(by: y, usage: &usage)
                    let third = try source.coefficients[row * 4 + 2].multiplied(by: z, usage: &usage)
                    columns[row * count + column] = try first.adding(second, usage: &usage)
                        .adding(third, usage: &usage).multiplied(by: lengths[column], usage: &usage)
                }
            }
            try OriginalAffineRationalMatrix.retain(count * count, of: ExactRationalCoefficient.self, usage: &usage)
            var gram = Array(repeating: ExactRationalCoefficient.zero, count: count * count)
            for first in 0..<count {
                for second in first..<count {
                    var value = ExactRationalCoefficient.zero
                    for row in 0..<3 {
                        try usage.consumeExactWork(1)
                        value = try value.adding(columns[row * count + first]
                            .multiplied(by: columns[row * count + second], usage: &usage), usage: &usage)
                    }
                    if first == second && !projectsLastAxis { value = try value.subtracting(square, usage: &usage) }
                    gram[first * count + second] = value; gram[second * count + first] = value
                }
            }
            if projectsLastAxis {
                return try rationalProjectedMetric(gram, thresholdSquare: square, usage: &usage)
            }
            return try rationalPositiveMetric(gram, count: count, usage: &usage)
        }
        guard let frame = source.normalizedFrame else { throw rationalAlgebraFailure("Original minimum metric lacks its field receipt.") }
        let depth = source.maximumDepth
        let zero = try OriginalSingularFieldElement.constant(.zero, in: frame.context, maximumDepth: depth, usage: &usage)
        try OriginalAffineRationalMatrix.retain(count * 3, of: OriginalSingularFieldElement.self, usage: &usage)
        var columns = Array(repeating: zero, count: count * 3)
        for column in 0..<count {
            let x = try OriginalSingularFieldElement.constant(.originalDouble(axes[column].x, usage: &usage), in: frame.context, maximumDepth: depth, usage: &usage)
            let y = try OriginalSingularFieldElement.constant(.originalDouble(axes[column].y, usage: &usage), in: frame.context, maximumDepth: depth, usage: &usage)
            let z = try OriginalSingularFieldElement.constant(.originalDouble(axes[column].z, usage: &usage), in: frame.context, maximumDepth: depth, usage: &usage)
            let length = try OriginalSingularFieldElement.constant(lengths[column], in: frame.context, maximumDepth: depth, usage: &usage)
            for row in 0..<3 {
                try usage.consumeExactWork(3)
                let a = try OriginalAffineFieldAction.coefficient(frame, row: row, column: 0, maximumDepth: depth, usage: &usage)
                let b = try OriginalAffineFieldAction.coefficient(frame, row: row, column: 1, maximumDepth: depth, usage: &usage)
                let c = try OriginalAffineFieldAction.coefficient(frame, row: row, column: 2, maximumDepth: depth, usage: &usage)
                columns[row * count + column] = try a.multiplied(by: x, maximumDepth: depth, usage: &usage)
                    .adding(b.multiplied(by: y, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
                    .adding(c.multiplied(by: z, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
                    .multiplied(by: length, maximumDepth: depth, usage: &usage)
            }
        }
        let shifted = try OriginalSingularFieldElement.constant(square, in: frame.context, maximumDepth: depth, usage: &usage)
        try OriginalAffineRationalMatrix.retain(count * count, of: OriginalSingularFieldElement.self, usage: &usage)
        var gram = Array(repeating: zero, count: count * count)
        for first in 0..<count {
            for second in first..<count {
                var value = zero
                for row in 0..<3 {
                    try usage.consumeExactWork(1)
                    value = try value.adding(columns[row * count + first].multiplied(by: columns[row * count + second],
                        maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
                }
                if first == second && !projectsLastAxis { value = try value.subtracting(shifted, maximumDepth: depth, usage: &usage) }
                gram[first * count + second] = value; gram[second * count + first] = value
            }
        }
        if projectsLastAxis {
            return try fieldProjectedMetric(gram, thresholdSquare: shifted, usage: &usage)
        }
        return try fieldPositiveMetric(gram, count: count, usage: &usage)
    }

    private func rationalProjectedMetric<B: RationalAlgebraAdmitting>(_ g: [ExactRationalCoefficient],
        thresholdSquare: ExactRationalCoefficient, usage: inout B) throws -> Bool {
        guard g[8].isPositive else {
            throw rationalAlgebraFailure("Original projected metric requires a nonzero transformed axis.")
        }
        try OriginalAffineRationalMatrix.retain(4, of: ExactRationalCoefficient.self, usage: &usage)
        var projected = Array(repeating: ExactRationalCoefficient.zero, count: 4)
        for first in 0..<2 {
            for second in first..<2 {
                try usage.consumeExactWork(1)
                var value = g[first * 3 + second]
                if first == second { value = try value.subtracting(thresholdSquare, usage: &usage) }
                value = try value.multiplied(by: g[8], usage: &usage)
                    .subtracting(g[first * 3 + 2].multiplied(by: g[2 * 3 + second], usage: &usage), usage: &usage)
                projected[first * 2 + second] = value; projected[second * 2 + first] = value
            }
        }
        return try rationalPositiveMetric(projected, count: 2, usage: &usage)
    }

    private func fieldProjectedMetric<B: RationalAlgebraAdmitting>(_ g: [OriginalSingularFieldElement],
        thresholdSquare: OriginalSingularFieldElement, usage: inout B) throws -> Bool {
        let depth = source.maximumDepth
        guard case .positive = try g[8].sign(maximumDepth: depth, usage: &usage) else {
            throw rationalAlgebraFailure("Original projected metric requires a nonzero transformed axis.")
        }
        let zero = try OriginalSingularFieldElement.constant(.zero, in: g[8].context,
            maximumDepth: depth, usage: &usage)
        try OriginalAffineRationalMatrix.retain(4, of: OriginalSingularFieldElement.self, usage: &usage)
        var projected = Array(repeating: zero, count: 4)
        for first in 0..<2 {
            for second in first..<2 {
                try usage.consumeExactWork(1)
                var value = g[first * 3 + second]
                if first == second { value = try value.subtracting(thresholdSquare, maximumDepth: depth, usage: &usage) }
                value = try value.multiplied(by: g[8], maximumDepth: depth, usage: &usage)
                    .subtracting(g[first * 3 + 2].multiplied(by: g[2 * 3 + second], maximumDepth: depth, usage: &usage),
                        maximumDepth: depth, usage: &usage)
                projected[first * 2 + second] = value; projected[second * 2 + first] = value
            }
        }
        return try fieldPositiveMetric(projected, count: 2, usage: &usage)
    }

    private func rationalPositiveMetric<B: RationalAlgebraAdmitting>(_ g: [ExactRationalCoefficient],
        count: Int, usage: inout B) throws -> Bool {
        guard g[0].isPositive else { return false }
        let minor = try g[0].multiplied(by: g[count + 1], usage: &usage)
            .subtracting(g[1].multiplied(by: g[count], usage: &usage), usage: &usage)
        guard minor.isPositive else { return false }
        if count == 2 { return true }
        let first = try g[4].multiplied(by: g[8], usage: &usage).subtracting(g[5].multiplied(by: g[7], usage: &usage), usage: &usage)
        let second = try g[3].multiplied(by: g[8], usage: &usage).subtracting(g[5].multiplied(by: g[6], usage: &usage), usage: &usage)
        let third = try g[3].multiplied(by: g[7], usage: &usage).subtracting(g[4].multiplied(by: g[6], usage: &usage), usage: &usage)
        let determinant = try g[0].multiplied(by: first, usage: &usage)
            .subtracting(g[1].multiplied(by: second, usage: &usage), usage: &usage)
            .adding(g[2].multiplied(by: third, usage: &usage), usage: &usage)
        return determinant.isPositive
    }
    private func fieldPositiveMetric<B: RationalAlgebraAdmitting>(_ g: [OriginalSingularFieldElement],
        count: Int, usage: inout B) throws -> Bool {
        let depth = source.maximumDepth
        guard case .positive = try g[0].sign(maximumDepth: depth, usage: &usage) else { return false }
        let minor = try g[0].multiplied(by: g[count + 1], maximumDepth: depth, usage: &usage)
            .subtracting(g[1].multiplied(by: g[count], maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        guard case .positive = try minor.sign(maximumDepth: depth, usage: &usage) else { return false }
        if count == 2 { return true }
        let first = try g[4].multiplied(by: g[8], maximumDepth: depth, usage: &usage)
            .subtracting(g[5].multiplied(by: g[7], maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        let second = try g[3].multiplied(by: g[8], maximumDepth: depth, usage: &usage)
            .subtracting(g[5].multiplied(by: g[6], maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        let third = try g[3].multiplied(by: g[7], maximumDepth: depth, usage: &usage)
            .subtracting(g[4].multiplied(by: g[6], maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        let determinant = try g[0].multiplied(by: first, maximumDepth: depth, usage: &usage)
            .subtracting(g[1].multiplied(by: second, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            .adding(g[2].multiplied(by: third, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        if case .positive = try determinant.sign(maximumDepth: depth, usage: &usage) { return true }
        return false
    }
}
