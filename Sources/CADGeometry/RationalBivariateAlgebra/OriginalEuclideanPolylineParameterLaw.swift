import CADCore

/// One common exact arc-length authority for the original authored UV polyline.
package struct OriginalEuclideanPolylineParameterLaw: Sendable {
    package struct Segment: Sendable {
        package let originalPointIndex: Int
        package let originalUStart: ExactRationalCoefficient
        package let originalVStart: ExactRationalCoefficient
        package let originalUDifference: ExactRationalCoefficient
        package let originalVDifference: ExactRationalCoefficient
        package let length: OriginalSingularFieldElement
        package let prefixLength: OriginalSingularFieldElement
        package let lowerFraction: OriginalSingularFieldElement
        package let upperFraction: OriginalSingularFieldElement
        package let fractionGain: OriginalSingularFieldElement
        package let sourceDepth: Int
    }
    private struct Pending: Sendable {
        let index: Int
        let u: ExactRationalCoefficient
        let v: ExactRationalCoefficient
        let du: ExactRationalCoefficient
        let dv: ExactRationalCoefficient
        let length: OriginalSingularFieldElement
    }
    package let originalPoints: [SurfaceParameter]
    package let context: OriginalSingularFieldContext
    package let totalLength: OriginalSingularFieldElement
    package let segments: [Segment]
    package let sourceDepth: Int

    /// Selects the original owning segment; a corner is not a smooth-jet authority.
    package func selectedSegment<B: ExactScalarAdmission & ~Copyable>(
        atOriginalFraction fraction: OriginalSingularFieldElement, preferFollowingAtJoin: Bool,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> Segment {
        var transport = OriginalSingularFieldTransport()
        let owner = try transport.importing(fraction.context, into: context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let value = try transport.applying(to: fraction, in: owner,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        var selected: Segment?
        for segment in segments {
            try usage.consumeWork(1)
            let lower = try segment.lowerFraction.embedded(in: owner, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let upper = try segment.upperFraction.embedded(in: owner, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            if case .negative = try value.subtracting(lower, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) { continue }
            if case .positive = try value.subtracting(upper, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) { continue }
            if case .some = selected {
                if preferFollowingAtJoin { selected = segment }
                break
            }
            selected = segment
        }
        guard let selected else { throw rationalAlgebraFailure("Original whole polyline fraction has no owning positive source segment.") }
        try RationalAlgebraStorage.retain(1, of: Segment.self, usage: &usage)
        return selected
    }

    package init<B: ExactScalarAdmission & ~Copyable>(originalPoints: [SurfaceParameter],
        inheritedDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try self.init(originalPoints:originalPoints,in:nil,inheritedDepth:inheritedDepth,
            maximumAlgebraicDepth:maximumAlgebraicDepth,usage:&usage)
    }

    /// Extends the retained original ancestor without re-preparing its roots.
    package init<B: ExactScalarAdmission & ~Copyable>(originalPoints: [SurfaceParameter],
        in initialContext: OriginalSingularFieldContext?,inheritedDepth: Int,
        maximumAlgebraicDepth: Int,usage: inout B) throws {
        guard originalPoints.count >= 2, inheritedDepth >= 0, maximumAlgebraicDepth >= inheritedDepth else {
            throw rationalAlgebraFailure("Original Euclidean polyline requires source points and admitted caller depth.")
        }
        for point in originalPoints {
            try usage.consumeWork(2)
            guard point.u.isFinite, point.v.isFinite else { throw rationalAlgebraFailure("Original polyline contains a nonfinite UV source point.") }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        let capacity = originalPoints.count - 1
        try RationalAlgebraStorage.retain(capacity, of: Pending.self, usage: &usage)
        var owner = try initialContext ?? OriginalSingularFieldContext(usage: &usage)
        var pending: [Pending] = []; pending.reserveCapacity(capacity)
        var total = try OriginalSingularFieldElement.constant(.zero, in: owner,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        for index in 0..<(originalPoints.count - 1) {
            try usage.consumeWork(1)
            let first = originalPoints[index], last = originalPoints[index + 1]
            let u = try ExactRationalCoefficient.originalDouble(first.u, usage: &usage)
            let v = try ExactRationalCoefficient.originalDouble(first.v, usage: &usage)
            let du = try ExactRationalCoefficient.originalDouble(last.u, usage: &usage).subtracting(u, usage: &usage)
            let dv = try ExactRationalCoefficient.originalDouble(last.v, usage: &usage).subtracting(v, usage: &usage)
            if du.isZero, dv.isZero { continue }
            let uMagnitude = du.isNegative ? du.negated : du
            let vMagnitude = dv.isNegative ? dv.negated : dv
            let magnitude = try uMagnitude.subtracting(vMagnitude, usage: &usage).isPositive ? uMagnitude : vMagnitude
            let scaledU = try du.divided(by: magnitude, usage: &usage)
            let scaledV = try dv.divided(by: magnitude, usage: &usage)
            let square = try scaledU.multiplied(by: scaledU, usage: &usage)
                .adding(scaledV.multiplied(by: scaledV, usage: &usage), usage: &usage)
            let radicand = try OriginalSingularFieldElement.constant(square, in: owner,
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let root = try radicand.nonnegativeSquareRoot(inheritedDepth: max(inheritedDepth, owner.coefficientDepth),
                maximumDepth: maximumAlgebraicDepth, admissionDomain: .coefficient(maximumDepth: maximumAlgebraicDepth), usage: &usage)
            let scale = try OriginalSingularFieldElement.constant(magnitude, in: root.context,
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let length = try root.multiplied(by: scale, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            guard case .positive = try length.sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) else {
                throw rationalAlgebraFailure("Original nonzero polyline segment has no positive exact Euclidean length.")
            }
            owner = length.context
            total = try total.embedded(in: owner, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .adding(length, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            pending.append(Pending(index: index, u: u, v: v, du: du, dv: dv, length: length))
        }
        guard !pending.isEmpty, case .positive = try total.sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original Euclidean polyline has no positive total source length.")
        }
        try RationalAlgebraStorage.retain(pending.count, of: Segment.self, usage: &usage)
        var result: [Segment] = []; result.reserveCapacity(pending.count)
        var prefix = try OriginalSingularFieldElement.constant(.zero, in: owner,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        for source in pending {
            let length = try source.length.embedded(in: owner, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let next = try prefix.adding(length, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let lower = try prefix.divided(by: total, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let upper = try next.divided(by: total, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let gain = try length.divided(by: total, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            result.append(Segment(originalPointIndex: source.index, originalUStart: source.u,
                originalVStart: source.v, originalUDifference: source.du, originalVDifference: source.dv,
                length: length, prefixLength: prefix, lowerFraction: lower, upperFraction: upper,
                fractionGain: gain, sourceDepth: max(inheritedDepth, owner.depth)))
            prefix = next
        }
        self.originalPoints = originalPoints; context = owner; totalLength = total
        segments = result; sourceDepth = max(inheritedDepth, owner.depth)
    }
}

package extension OriginalEuclideanPolylineParameterLaw.Segment {
    func originalLocalFraction<B: ExactScalarAdmission & ~Copyable>(atOriginalFraction fraction: OriginalSingularFieldElement,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        var transport = OriginalSingularFieldTransport()
        let owner = try transport.importing(fraction.context, into: lowerFraction.context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let value = try transport.applying(to: fraction, in: owner,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let local = try value.subtracting(lowerFraction.embedded(in: owner,
            maximumDepth: maximumAlgebraicDepth, usage: &usage), maximumDepth: maximumAlgebraicDepth, usage: &usage)
            .divided(by: fractionGain.embedded(in: owner, maximumDepth: maximumAlgebraicDepth, usage: &usage),
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
        if case .negative = try local.sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) {
            throw rationalAlgebraFailure("Original local polyline query precedes its owning exact segment.")
        }
        let one = try OriginalSingularFieldElement.constant(.one, in: owner,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        if case .positive = try local.subtracting(one, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            .sign(maximumDepth: maximumAlgebraicDepth, usage: &usage) {
            throw rationalAlgebraFailure("Original local polyline query exceeds its owning exact segment.")
        }
        return local
    }

    func originalUV<B: ExactScalarAdmission & ~Copyable>(atOriginalFraction fraction: OriginalSingularFieldElement,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement) {
        let local = try originalLocalFraction(atOriginalFraction: fraction,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        func coordinate(_ start: ExactRationalCoefficient, difference: ExactRationalCoefficient,
            usage: inout B) throws -> OriginalSingularFieldElement {
            let gain = try OriginalSingularFieldElement.constant(difference, in: local.context,
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let origin = try OriginalSingularFieldElement.constant(start, in: local.context,
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
            return try origin.adding(gain.multiplied(by: local, maximumDepth: maximumAlgebraicDepth, usage: &usage),
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
        }
        try RationalAlgebraStorage.retain(1, of: (OriginalSingularFieldElement, OriginalSingularFieldElement).self, usage: &usage)
        return try (coordinate(originalUStart, difference: originalUDifference, usage: &usage),
            coordinate(originalVStart, difference: originalVDifference, usage: &usage))
    }

    func originalFirstDerivative<B: ExactScalarAdmission & ~Copyable>(maximumAlgebraicDepth: Int,
        usage: inout B) throws -> (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement) {
        let u = try OriginalSingularFieldElement.constant(originalUDifference, in: fractionGain.context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
            .divided(by: fractionGain, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let v = try OriginalSingularFieldElement.constant(originalVDifference, in: fractionGain.context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
            .divided(by: fractionGain, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: (OriginalSingularFieldElement, OriginalSingularFieldElement).self, usage: &usage)
        return (u, v)
    }
}
