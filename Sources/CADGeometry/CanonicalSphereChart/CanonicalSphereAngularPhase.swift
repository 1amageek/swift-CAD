import CADCore
import Foundation

/// Continuous symbolic angular source shared by ideal angular primitive adapters.
package enum CanonicalSphereAngularPhase {
    package static let piBounds = OutwardScalarInterval(
        lower: 0x1.921fb54442d18p+1, upper: 0x1.921fb54442d19p+1)
    package static let scaleBounds = OutwardScalarInterval(
        lower: 1, upper: (0x1.921fb54442d19p+1 / Double.pi).nextUp)

    package static func candidate(at label: Double, cosine: Bool) -> Double {
        valueBounds(at: label, cosine: cosine).midpoint
    }

    package static func valueBounds(at label: Double, cosine: Bool) -> OutwardScalarInterval {
        harmonic(of: .constant(label), cosine: cosine).value
    }

    package static func valueBounds(at label: Double, cosine: Bool,
        consumeWork: () throws -> Void) rethrows -> OutwardScalarInterval {
        try harmonic(of: .constant(label), cosine: cosine, consumeWork: consumeWork).value
    }

    /// Exact remainder of the original dyadic label by the original label period.
    /// Modular operands stay below 2^53, so their full-width product divided by
    /// the modulus has a representable UInt64 quotient and remainder.
    private static func originalRemainder(of label: Double) -> Double {
        originalRemainder(of: label, consumeWork: {})
    }

    private static func originalRemainder(of label: Double,
        consumeWork: () throws -> Void) rethrows -> Double {
        try consumeWork()
        let period = 2 * Double.pi
        guard label.isFinite, abs(label) >= period else { return label }
        let significandMask: UInt64 = 0x000f_ffff_ffff_ffff
        let implicitBit: UInt64 = 0x0010_0000_0000_0000
        let periodBits = period.bitPattern
        let modulus = (periodBits & significandMask) | implicitBit
        let periodExponent = Int((periodBits >> 52) & 0x7ff) - 1023 - 52
        let bits = label.bitPattern
        let originalExponent = Int((bits >> 52) & 0x7ff) - 1023 - 52
        let significand = (bits & significandMask) | implicitBit
        var exponent = originalExponent - periodExponent
        var remainder = significand % modulus
        var power: UInt64 = 2
        // At most eleven iterations for any finite binary64 source label.
        while exponent > 0 {
            try consumeWork()
            if exponent & 1 != 0 {
                remainder = modulus.dividingFullWidth(remainder.multipliedFullWidth(by: power)).remainder
            }
            exponent >>= 1
            if exponent > 0 {
                power = modulus.dividingFullWidth(power.multipliedFullWidth(by: power)).remainder
            }
        }
        let value = Double(sign: .plus, exponent: periodExponent, significand: Double(remainder))
        return label.sign == .minus ? -value : value
    }

    package static func canonicalValue(at label: Double, cosine: Bool) -> Double? {
        if label == 0 || label == 2 * Double.pi || label == -2 * Double.pi {
            return cosine ? 1 : 0
        }
        if label == Double.pi || label == -Double.pi { return cosine ? -1 : 0 }
        if label == Double.pi * 0.5 { return cosine ? 0 : 1 }
        if label == -Double.pi * 0.5 { return cosine ? 0 : -1 }
        if label == Double.pi * 1.5 { return cosine ? 0 : -1 }
        if label == -Double.pi * 1.5 { return cosine ? 0 : 1 }
        return nil
    }

    package static func harmonic(of label: SurfaceIntervalJet, cosine: Bool) -> SurfaceIntervalJet {
        harmonic(of: label, cosine: cosine, consumeWork: {})
    }

    package static func harmonic(of label: SurfaceIntervalJet, cosine: Bool,
        consumeWork: () throws -> Void) rethrows -> SurfaceIntervalJet {
        try consumeWork()
        let scale = SurfaceIntervalJet(value: scaleBounds,
            derivativeU: .exact(0), derivativeV: .exact(0),
            secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
            thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0),
            thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
        let originalPhase = label * scale
        let period = 2 * Double.pi
        let width = OutwardScalarInterval.exact(label.value.upper) - .exact(label.value.lower)
        if !width.isFinite || width.upper >= period {
            let full = OutwardScalarInterval(lower: -1, upper: 1)
            return SurfaceIntervalJet.applyingUnaryFunction(to: originalPhase,
                value: full, firstDerivative: full, secondDerivative: full, thirdDerivative: full)
        }
        let first = try originalRemainder(of: label.value.lower, consumeWork: consumeWork)
        let last = try originalRemainder(of: label.value.upper, consumeWork: consumeWork)
        let range: OutwardScalarInterval
        if first <= last {
            range = .init(lower: first, upper: last)
        } else {
            // A branch crossing is retained as one enclosing physical phase.
            // Outward addition preserves the source full-turn displacement.
            range = .init(lower: first, upper: (OutwardScalarInterval.exact(last) + .exact(period)).upper)
        }
        let reduced = range * scaleBounds
        let phase = SurfaceIntervalJet(value: reduced,
            derivativeU: originalPhase.derivativeU, derivativeV: originalPhase.derivativeV,
            secondDerivativeUU: originalPhase.secondDerivativeUU,
            secondDerivativeUV: originalPhase.secondDerivativeUV, secondDerivativeVV: originalPhase.secondDerivativeVV,
            thirdDerivativeUUU: originalPhase.thirdDerivativeUUU, thirdDerivativeUUV: originalPhase.thirdDerivativeUUV,
            thirdDerivativeUVV: originalPhase.thirdDerivativeUVV, thirdDerivativeVVV: originalPhase.thirdDerivativeVVV)
        if label.value.lower == label.value.upper,
           let sine = canonicalValue(at: first, cosine: false),
           let cos = canonicalValue(at: first, cosine: true) {
            return SurfaceIntervalJet.applyingUnaryFunction(to: phase,
                value: .exact(cosine ? cos : sine),
                firstDerivative: .exact(cosine ? -sine : cos),
                secondDerivative: .exact(cosine ? -cos : -sine),
                thirdDerivative: .exact(cosine ? sine : -cos))
        }
        return try cosine ? .cosine(of: phase, consumeWork: consumeWork) : .sine(of: phase, consumeWork: consumeWork)
    }

    static func candidateTaylor(at label: Double, alongU: Bool, cosine: Bool,
        order: Int) throws -> SurfaceTaylorScalarJet {
        let sine = candidate(at: label, cosine: false), cos = candidate(at: label, cosine: true)
        let cycle = cosine ? [cos, -sine, -cos, sine] : [sine, cos, -sine, -cos]
        var result = try SurfaceTaylorScalarJet(order: order)
        var scale = 1.0
        for index in 0...order {
            if index > 0 { scale *= scaleBounds.midpoint / Double(index) }
            try result.setCoefficient(cycle[index % 4] * scale,
                uOrder: alongU ? index : 0, vOrder: alongU ? 0 : index)
        }
        return result
    }

    package static func candidateLabel(ofPhysicalAngle angle: Double) -> Double {
        if angle == Double.pi * 0.5 || angle == -Double.pi * 0.5 || angle == 0
            || angle == Double.pi || angle == -Double.pi || angle == 2 * Double.pi
            || angle == -2 * Double.pi || angle == Double.pi * 1.5 || angle == -Double.pi * 1.5 { return angle }
        return angle / scaleBounds.midpoint
    }

    package static func physicalAngleBounds(of labels: ScalarInterval) throws -> ScalarInterval {
        let q = OutwardScalarInterval(lower: labels.lower, upper: labels.upper) * scaleBounds
        return try .init(lower: q.lower, upper: q.upper)
    }

    package static func originalLabelBounds(of angles: OutwardScalarInterval) throws -> ScalarInterval? {
        guard let q = angles.divided(by: scaleBounds) else { return nil }
        return try .init(lower: q.lower, upper: q.upper)
    }
}
