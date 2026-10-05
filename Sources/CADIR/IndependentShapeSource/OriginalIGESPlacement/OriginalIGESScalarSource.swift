import CADCore
import CADGeometry

/// Exact original IGES scalar interpretation without replacing lexical source values.
package enum OriginalIGESScalarSource {
    package static func coefficient<B: RationalAlgebraAdmitting>(_ literal: String, usage: inout B) throws -> ExactRationalCoefficient {
        try usage.consumeExactWork(literal.utf8.count)
        if literal.utf8.contains(68) || literal.utf8.contains(100) {
            let bytes = literal.utf8.count.multipliedReportingOverflow(by: 2)
            guard !bytes.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES exponent text storage overflows.") }
            try RationalAlgebraStorage.retainBytes(bytes.partialValue, usage: &usage)
            var normalizedBytes: [UInt8] = []; normalizedBytes.reserveCapacity(literal.utf8.count)
            for byte in literal.utf8 { normalizedBytes.append(byte == 68 || byte == 100 ? 69 : byte) }
            let normalized = String(decoding: normalizedBytes, as: UTF8.self)
            return try OriginalSTEPDecimal.coefficient(normalized, usage: &usage)
        }
        return try OriginalSTEPDecimal.coefficient(literal, usage: &usage)
    }
    package static func lengthGain<B: RationalAlgebraAdmitting>(_ unit: LengthUnit, usage: inout B) throws -> ExactRationalCoefficient {
        let numerator: Double, denominator: Double
        switch unit {
        case .meter: numerator = 1; denominator = 1
        case .micrometer: numerator = 1; denominator = 1_000_000
        case .millimeter: numerator = 1; denominator = 1_000
        case .centimeter: numerator = 1; denominator = 100
        case .kilometer: numerator = 1_000; denominator = 1
        case .inch: numerator = 127; denominator = 5_000
        case .foot: numerator = 381; denominator = 1_250
        }
        return try ExactRationalCoefficient.originalDouble(numerator, usage: &usage)
            .divided(by: .originalDouble(denominator, usage: &usage), usage: &usage)
    }
    package static func view<B: RationalAlgebraAdmitting>(of word: OriginalAffineOperationWord, usage: inout B) throws -> AffineTransform3D {
        let prepared = try word.prepared(usage: &usage)
        let x = try prepared.applying(to: Vector3D.unitX, usage: &usage)
        let y = try prepared.applying(to: Vector3D.unitY, usage: &usage)
        let z = try prepared.applying(to: Vector3D.unitZ, usage: &usage)
        let origin = try prepared.applying(to: Point3D.origin, usage: &usage)
        return try AffineTransform3D(basisX: x, basisY: y, basisZ: z,
            translation: .init(x: origin.x, y: origin.y, z: origin.z))
    }
}
