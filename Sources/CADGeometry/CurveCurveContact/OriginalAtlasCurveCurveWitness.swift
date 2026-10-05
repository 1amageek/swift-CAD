import CADCore

/// Exact endpoint/representable-parameter witnesses supplement original atlas contraction.
struct OriginalAtlasCurveCurveWitness {
    func witness(first: Curve3D, firstOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
                 firstRange: ScalarInterval, second: Curve3D,
                 secondOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
                 secondRange: ScalarInterval, budget: inout NativeCurveCurveContactBudget) throws -> (Double, Double)? {
        func containsWord(_ source: Curve3D, depth: Int,
            budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            try budget.work(1)
            guard depth <= budget.remainingSourceDepth else { throw budget.exhausted() }
            switch source {
            case .originalAffineWord: return true
            case .rigidImage(let image): return try containsWord(image.source, depth: depth + 1, budget: &budget)
            case .affineImage(let image): return try containsWord(image.source, depth: depth + 1, budget: &budget)
            case .parameterImage(let image): return try containsWord(image.source, depth: depth + 1, budget: &budget)
            default: return false
            }
        }
        let firstWord = try containsWord(first, depth: 0, budget: &budget)
        let secondWord = try containsWord(second, depth: 0, budget: &budget)
        if firstWord || secondWord {
            let producer = OriginalAtlasCurveCurvePolynomial()
            if let a = try producer.prepare(source: first, owner: firstOwner, alongU: true, budget: &budget),
               let b = try producer.prepare(source: second, owner: secondOwner, alongU: false, budget: &budget) {
                let equations = try producer.equations(first: a, second: b, budget: &budget)
                for u in [firstRange.lower, firstRange.midpoint, firstRange.upper] {
                    let originalU = try ExactRationalCoefficient.originalDouble(u, usage: &budget)
                    for v in [secondRange.lower, secondRange.midpoint, secondRange.upper] {
                        let originalV = try ExactRationalCoefficient.originalDouble(v, usage: &budget)
                        var equal = true
                        for equation in equations {
                            if try !equation.evaluated(atU: originalU, v: originalV, usage: &budget).isZero {
                                equal = false; break
                            }
                        }
                        if equal { return (u, v) }
                    }
                }
            }
            if let equations = try OriginalAtlasCurveCurveFieldPolynomial().equations(
                first: first, firstOwner: firstOwner, second: second,
                secondOwner: secondOwner, budget: &budget), let original = equations.first {
                let previous = budget.enterOriginalWordAlgebra()
                defer { budget.restoreOriginalWordAlgebra(previous) }
                for u in [firstRange.lower, firstRange.midpoint, firstRange.upper] {
                    let originalU = try OriginalSingularFieldElement.constant(
                        .originalDouble(u, usage: &budget), in: original.context, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
                    for v in [secondRange.lower, secondRange.midpoint, secondRange.upper] {
                        let originalV = try OriginalSingularFieldElement.constant(
                            .originalDouble(v, usage: &budget), in: original.context, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
                        var equal = true
                        for equation in equations {
                            let residual = try equation.evaluated(atU: originalU, v: originalV,
                                maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
                            if case .zero = try residual.sign(maximumDepth: budget.maximumAlgebraicDepth, usage: &budget) {}
                            else { equal = false; break }
                        }
                        if equal { return (u, v) }
                    }
                }
            }
            // Missing original angular/procedural coefficient charts retain
            // the unresolved search. No rounded matrix witness follows.
            return nil
        }
        let arithmetic = OriginalCurveCurveWitness()
        func lineValue(origin: Point3D, direction: Vector3D, parameter: Double,
                       budget: inout NativeCurveCurveContactBudget) throws -> [[Double]]? {
            var homogeneous: [[Double]] = []
            try budget.work(4)
            for (origin, direction) in [(origin.x, direction.x), (origin.y, direction.y), (origin.z, direction.z)] {
                guard let delta = try arithmetic.multiply([direction], [parameter], budget: &budget) else { return nil }
                try budget.work(delta.count + 1)
                homogeneous.append(FloatingPointExpansion.sum([origin], delta))
            }
            homogeneous.append([1])
            return homogeneous
        }
        func transformed(_ original: [[Double]], basisX: Vector3D, basisY: Vector3D,
                         basisZ: Vector3D, translation: Vector3D,
                         budget: inout NativeCurveCurveContactBudget) throws -> [[Double]]? {
            try budget.work(4)
            var result: [[Double]] = []
            for (x, y, z, offset) in [(basisX.x, basisY.x, basisZ.x, translation.x),
                                     (basisX.y, basisY.y, basisZ.y, translation.y),
                                     (basisX.z, basisY.z, basisZ.z, translation.z)] {
                guard let a = try arithmetic.multiply([x], original[0], budget: &budget),
                      let b = try arithmetic.multiply([y], original[1], budget: &budget),
                      let c = try arithmetic.multiply([z], original[2], budget: &budget),
                      let d = try arithmetic.multiply([offset], original[3], budget: &budget) else { return nil }
                try budget.work(a.count + b.count + c.count + d.count)
                result.append(FloatingPointExpansion.sum(FloatingPointExpansion.sum(a, b),
                    FloatingPointExpansion.sum(c, d)))
            }
            result.append(original[3])
            return result
        }
        func value(_ source: Curve3D, owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
                   parameter: Double, depth: Int,
                   budget: inout NativeCurveCurveContactBudget) throws -> [[Double]]? {
            try budget.work(1)
            // Match the original representation depth admitted by preparation;
            // matrix composition is not parameter-cell subdivision.
            guard depth <= budget.remainingSourceDepth else { throw budget.exhausted() }
            switch source {
            case .bSpline(let native):
                guard owner.nativeIndex >= native.degree, owner.nativeIndex < native.controlPointCount else { return nil }
                let nativeParameter: Double
                if native.isPeriodic {
                    guard let cycle = owner.originalPeriodicCycle else { return nil }
                    let period = native.knots[native.controlPointCount] - native.knots[native.degree]
                    guard cycle.isFinite, cycle.rounded(.towardZero) == cycle,
                          abs(cycle) <= 9_007_199_254_740_990, period.isFinite, period > 0 else { return nil }
                    try budget.work(1)
                    let shift = try ExactRationalCoefficient.originalDouble(cycle, usage: &budget)
                        .multiplied(by: .originalDouble(period, usage: &budget), usage: &budget)
                    let bounds = try ExactRationalCoefficient.originalDouble(parameter, usage: &budget)
                        .subtracting(shift, usage: &budget).outwardInterval(usage: &budget)
                    guard bounds.lower == bounds.upper else { return nil }
                    nativeParameter = bounds.lower
                } else { nativeParameter = parameter }
                let nativeDomain = try ScalarInterval(lower: native.knots[owner.nativeIndex],
                    upper: native.knots[owner.nativeIndex + 1])
                return try arithmetic.homogeneous(native, nativeIndex: owner.nativeIndex,
                    nativeDomain: nativeDomain, parameter: nativeParameter, budget: &budget)
            case .line(let line):
                return try lineValue(origin: line.origin, direction: line.direction,
                    parameter: parameter, budget: &budget)
            case .analytic(.line(let origin, let direction)):
                return try lineValue(origin: origin, direction: direction,
                    parameter: parameter, budget: &budget)
            case .rigidImage(let image):
                guard let original = try value(image.source, owner: owner, parameter: parameter,
                    depth: depth + 1, budget: &budget) else { return nil }
                return try transformed(original, basisX: image.transform.basisX, basisY: image.transform.basisY,
                    basisZ: image.transform.basisZ, translation: image.transform.translation, budget: &budget)
            case .affineImage(let image):
                guard let original = try value(image.source, owner: owner, parameter: parameter,
                    depth: depth + 1, budget: &budget) else { return nil }
                return try transformed(original, basisX: image.transform.basisX, basisY: image.transform.basisY,
                    basisZ: image.transform.basisZ, translation: image.transform.translation, budget: &budget)
            case .parameterImage(let image):
                let mapped = try image.parameterGain.exactCoefficient(usage: &budget)
                    .multiplied(by: .originalDouble(parameter, usage: &budget), usage: &budget)
                    .adding(.originalDouble(image.offset, usage: &budget), usage: &budget)
                let bounds = try mapped.outwardInterval(usage: &budget)
                guard bounds.lower == bounds.upper else { return nil }
                let candidate = bounds.lower
                return try value(image.source, owner: owner, parameter: candidate,
                    depth: depth + 1, budget: &budget)
            default: return nil
            }
        }
        for a in [firstRange.lower, firstRange.midpoint, firstRange.upper] {
            guard let av = try value(first, owner: firstOwner, parameter: a, depth: 0, budget: &budget) else { continue }
            for b in [secondRange.lower, secondRange.midpoint, secondRange.upper] {
                guard let bv = try value(second, owner: secondOwner, parameter: b, depth: 0, budget: &budget) else { continue }
                var equal = true
                for axis in 0..<3 {
                    guard let lhs = try arithmetic.multiply(av[axis], bv[3], budget: &budget),
                          let rhs = try arithmetic.multiply(bv[axis], av[3], budget: &budget) else { equal = false; break }
                    try budget.work(lhs.count + rhs.count)
                    if FloatingPointExpansion.sign(FloatingPointExpansion.subtract(lhs, rhs)) != .zero { equal = false; break }
                }
                if equal { return (a, b) }
            }
        }
        return nil
    }
}
