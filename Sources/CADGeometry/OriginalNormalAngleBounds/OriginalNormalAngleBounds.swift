import CADCore

/// Physical normal-angle bounds; intrinsic parameter labels are not used here.
package enum OriginalNormalAngleBounds {
    package static func safeChordLimit<B: RationalAlgebraAdmitting>(angle: Double,
        usage: inout B) throws -> Double {
        guard angle.isFinite, angle > 0 else {
            throw GeometryConversionError.invalidInput("Normal angle tolerance must be finite and positive.")
        }
        if angle >= CanonicalSphereAngularPhase.piBounds.upper { return 2 }
        let result = try chordBounds(angle: angle, usage: &usage)
        guard result.lower > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Physical normal angle has no positive representable safe chord threshold.")
        }
        return min(2, result.lower)
    }

    package static func upperAngle<B: RationalAlgebraAdmitting>(chord: Double,
        usage: inout B) throws -> Double {
        guard chord.isFinite, chord >= 0, chord <= 2 else {
            throw GeometryConversionError.invalidInput("Unit-normal chord must be finite and within zero through two.")
        }
        if chord == 0 { return 0 }
        var lower = 0.0, upper = CanonicalSphereAngularPhase.piBounds.upper
        if chord == 2 { return upper }
        while true {
            try usage.consumeExactWork(1); try Task.checkCancellation()
            let middle = lower + (upper - lower) * 0.5
            guard middle > lower, middle < upper else { return upper }
            // Every representable interior station is below mathematical pi:
            // the retained pi enclosure has adjacent binary64 endpoints.
            let value = try chordBounds(angle: middle, usage: &usage)
            if value.upper < chord { lower = middle }
            else if value.lower >= chord { upper = middle }
            else { return upper }
        }
    }

    private static func chordBounds<B: RationalAlgebraAdmitting>(angle: Double,
        usage: inout B) throws -> OutwardScalarInterval {
        guard angle.isFinite, angle >= 0, angle <= CanonicalSphereAngularPhase.piBounds.upper else {
            throw GeometryConversionError.invalidInput("Physical chord proof requires a finite angle in the original half-turn.")
        }
        if angle == 0 { return .exact(0) }
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let x = try ExactRationalCoefficient.originalDouble(angle, usage: &usage).divided(by: two, usage: &usage)
        let squared = try x.multiplied(by: x, usage: &usage)
        var sum = x, term = x, order = 0
        while true {
            try usage.consumeExactWork(1); try Task.checkCancellation()
            let twice = try rationalAlgebraCount(order, 2, multiply: true)
            let a = try rationalAlgebraCount(twice, 2)
            let b = try rationalAlgebraCount(twice, 3)
            let divisor = try ExactRationalCoefficient.natural(a, usage: &usage)
                .multiplied(by: .natural(b, usage: &usage), usage: &usage)
            let next = try term.multiplied(by: squared, usage: &usage).divided(by: divisor, usage: &usage)
            let subtracting = order & 1 == 0
            let adjacent = try sum.adding(subtracting ? next.negated : next, usage: &usage)
            let low = try (subtracting ? adjacent : sum).multiplied(by: two, usage: &usage)
                .outwardInterval(usage: &usage)
            let high = try (subtracting ? sum : adjacent).multiplied(by: two, usage: &usage)
                .outwardInterval(usage: &usage)
            let lower = max(0, low.lower), upper = min(2, high.upper)
            guard lower.isFinite, upper.isFinite, lower <= upper else {
                throw rationalAlgebraFailure("Original physical sine bounds are inconsistent.")
            }
            if upper <= lower.nextUp { return .init(lower: lower, upper: upper) }
            sum = adjacent; term = next; order = try rationalAlgebraCount(order, 1)
        }
    }
}
