import CADCore
import CADGeometry

/// Exact original IGES scalar interpretation without replacing lexical source values.
package enum OriginalIGESScalarSource {
    package static func coefficient(_ literal: String, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        try execution.consumeWork(literal.utf8.count)
        if literal.utf8.contains(68) || literal.utf8.contains(100) {
            let bytes = literal.utf8.count.multipliedReportingOverflow(by: 2)
            guard !bytes.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES exponent text storage overflows.") }
            try RationalAlgebraStorage.retainBytes(bytes.partialValue, usage: &execution)
            var normalizedBytes: [UInt8] = []; normalizedBytes.reserveCapacity(literal.utf8.count)
            for byte in literal.utf8 { normalizedBytes.append(byte == 68 || byte == 100 ? 69 : byte) }
            let normalized = String(decoding: normalizedBytes, as: UTF8.self)
            return try OriginalSTEPDecimal.coefficient(normalized, using: &execution)
        }
        return try OriginalSTEPDecimal.coefficient(literal, using: &execution)
    }
    package static func lengthGain(_ unit: LengthUnit, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
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
        return try ExactRationalCoefficient.originalDouble(numerator, usage: &execution)
            .divided(by: .originalDouble(denominator, usage: &execution), usage: &execution)
    }
    package static func view(of word: OriginalAffineOperationWord, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D {
        let prepared = try word.prepared(usage: &execution)
        let x = try prepared.applying(to: Vector3D.unitX, usage: &execution)
        let y = try prepared.applying(to: Vector3D.unitY, usage: &execution)
        let z = try prepared.applying(to: Vector3D.unitZ, usage: &execution)
        let origin = try prepared.applying(to: Point3D.origin, usage: &execution)
        return try AffineTransform3D(basisX: x, basisY: y, basisZ: z,
            translation: .init(x: origin.x, y: origin.y, z: origin.z))
    }
}
