import CADCore

/// Immutable exact null-space action for one original derivative order.
package struct OriginalPlaneDerivativeProjection: Sendable {
    private struct Entry: Sendable {
        let normal: OriginalSupportingPlaneEquation.Vector
        let reciprocalNormSquared: ExactRationalCoefficient
        let bounds: IntervalVector3DBounds
        let reciprocalBounds: OutwardScalarInterval
    }
    package let constraints: [OriginalPlaneDerivativeConstraint]
    package let derivativeOrder: Int
    private let entries: [Entry]

    package init<B: RationalAlgebraAdmitting>(constraints: [OriginalPlaneDerivativeConstraint],
        derivativeOrder: Int, remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        guard (1...2).contains(derivativeOrder), remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original plane derivative projection has invalid source capabilities.")
        }
        try RationalAlgebraStorage.retain(min(3, constraints.count), of: Entry.self, usage: &usage)
        var basis: [Entry] = []; basis.reserveCapacity(min(3, constraints.count))
        for constraint in constraints {
            try usage.consumeExactWork(1)
            guard constraint.order.rawValue >= derivativeOrder else { continue }
            let equation = try OriginalSupportingPlaneEquation.prepared(source: constraint.surface,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth, usage: &usage)
            var normal = equation.normal
            for entry in basis {
                let coefficient = try normal.dot(entry.normal, usage: &usage)
                    .multiplied(by: entry.reciprocalNormSquared, usage: &usage)
                normal = try normal.subtracting(entry.normal.scaled(by: coefficient, usage: &usage), usage: &usage)
            }
            if normal.isZero { continue }
            let normSquared = try normal.dot(normal, usage: &usage)
            guard normSquared.isPositive else { throw GeometryConversionError.invalidInput("Original plane basis lost its positive exact squared norm.") }
            let reciprocal = try ExactRationalCoefficient.one.divided(by: normSquared, usage: &usage)
            guard basis.count < 3 else { throw GeometryConversionError.invalidInput("Original plane basis exceeds spatial dimension.") }
            basis.append(try .init(normal: normal, reciprocalNormSquared: reciprocal,
                bounds: .init(x: normal.x.outwardInterval(usage: &usage), y: normal.y.outwardInterval(usage: &usage),
                    z: normal.z.outwardInterval(usage: &usage)), reciprocalBounds: reciprocal.outwardInterval(usage: &usage)))
        }
        if derivativeOrder == 1, basis.count == 3 {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Independent original support planes leave no nonzero generated endpoint tangent.")
        }
        self.constraints = constraints; self.derivativeOrder = derivativeOrder; entries = basis
    }

    package var isIdentity: Bool { entries.isEmpty }

    package func projected(_ original: IntervalVector3DBounds,
        consumeWork: () throws -> Void) throws -> IntervalVector3DBounds {
        var result = original
        for entry in entries {
            for _ in 0..<18 { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
            let coefficient = (result.x * entry.bounds.x + result.y * entry.bounds.y + result.z * entry.bounds.z)
                * entry.reciprocalBounds
            result = .init(x: result.x - entry.bounds.x * coefficient,
                y: result.y - entry.bounds.y * coefficient, z: result.z - entry.bounds.z * coefficient)
        }
        return result
    }

    package func projectedExact<B: RationalAlgebraAdmitting>(
        _ original: OriginalSupportingPlaneEquation.Vector, usage: inout B) throws
        -> OriginalSupportingPlaneEquation.Vector {
        var result = original
        for entry in entries {
            let coefficient = try result.dot(entry.normal, usage: &usage)
                .multiplied(by: entry.reciprocalNormSquared, usage: &usage)
            result = try result.subtracting(entry.normal.scaled(by: coefficient, usage: &usage), usage: &usage)
        }
        return result
    }

    package func includes<B: RationalAlgebraAdmitting>(_ requested: OriginalPlaneDerivativeConstraint,
        usage: inout B) throws -> Bool {
        for original in constraints {
            try GeometryStructuralComparisonWork.charge(surface: original.surface, using: { try usage.consumeExactWork($0) })
            try GeometryStructuralComparisonWork.charge(surface: requested.surface, using: { try usage.consumeExactWork($0) })
            if original.surface == requested.surface, original.order.rawValue >= requested.order.rawValue { return true }
        }
        return false
    }
}
