import CADCore
import CADGeometry

/// Proves that the original binary columns have a legal uniform orthogonal exchange image.
enum OriginalOrthogonalAffineRepresentability {
    static func scale<B: RationalAlgebraAdmitting>(of frame: AffineTransform3D,
        requiresUnitScale: Bool, format: ExchangeFileFormat = .step, usage: inout B) throws -> Double {
        try usage.visitExactCell(depth: 0)
        let xx = try dot(frame.basisX, frame.basisX, usage: &usage)
        let yy = try dot(frame.basisY, frame.basisY, usage: &usage)
        let zz = try dot(frame.basisZ, frame.basisZ, usage: &usage)
        guard xx.isPositive, xx == yy, xx == zz,
              try dot(frame.basisX, frame.basisY, usage: &usage).isZero,
              try dot(frame.basisX, frame.basisZ, usage: &usage).isZero,
              try dot(frame.basisY, frame.basisZ, usage: &usage).isZero else {
            throw loss("Original affine columns have shear or unequal scales that the format's uniform orthogonal operator cannot retain.")
        }
        let candidate = requiresUnitScale ? 1 : normCandidate(frame.basisX)
        guard candidate.isFinite, candidate > 0 else {
            throw loss("Original uniform scale has no finite positive output candidate.")
        }
        let exact = try ExactRationalCoefficient.originalDouble(candidate, usage: &usage)
        guard try exact.multiplied(by: exact, usage: &usage) == xx else {
            throw loss("Original uniform scale cannot be emitted as the candidate binary exchange scalar without changing its law.")
        }
        return candidate
    }
    private static func normCandidate(_ value: Vector3D) -> Double {
        let maximum = max(abs(value.x), max(abs(value.y), abs(value.z)))
        guard maximum > 0, maximum.isFinite else { return maximum }
        let x = value.x / maximum, y = value.y / maximum, z = value.z / maximum
        return (x * x + y * y + z * z).squareRoot() * maximum
    }
    static func normalizedFrame<B: RationalAlgebraAdmitting>(_ frame: AffineTransform3D,
        scale: Double, usage: inout B) throws -> AffineTransform3D {
        let exactScale = try ExactRationalCoefficient.originalDouble(scale, usage: &usage)
        func column(_ original: Vector3D, usage: inout B) throws -> Vector3D {
            let candidate = original / scale
            for (source, emitted) in [(original.x, candidate.x), (original.y, candidate.y), (original.z, candidate.z)] {
                let value = try ExactRationalCoefficient.originalDouble(emitted, usage: &usage)
                    .multiplied(by: exactScale, usage: &usage)
                guard value == (try ExactRationalCoefficient.originalDouble(source, usage: &usage)) else {
                    throw loss("Original uniform transform cannot be decomposed into the binary IGES matrix and scale without changing a coefficient.")
                }
            }
            return candidate
        }
        let x = try column(frame.basisX, usage: &usage)
        let y = try column(frame.basisY, usage: &usage)
        let z = try column(frame.basisZ, usage: &usage)
        return try AffineTransform3D(basisX: x, basisY: y, basisZ: z, translation: .zero)
    }
    private static func dot<B: RationalAlgebraAdmitting>(_ first: Vector3D, _ second: Vector3D,
        usage: inout B) throws -> ExactRationalCoefficient {
        let x = try ExactRationalCoefficient.originalDouble(first.x, usage: &usage)
            .multiplied(by: ExactRationalCoefficient.originalDouble(second.x, usage: &usage), usage: &usage)
        let y = try ExactRationalCoefficient.originalDouble(first.y, usage: &usage)
            .multiplied(by: ExactRationalCoefficient.originalDouble(second.y, usage: &usage), usage: &usage)
        let z = try ExactRationalCoefficient.originalDouble(first.z, usage: &usage)
            .multiplied(by: ExactRationalCoefficient.originalDouble(second.z, usage: &usage), usage: &usage)
        return try x.adding(y, usage: &usage).adding(z, usage: &usage)
    }
    private static func loss(_ description: String) -> ExchangePreservationError {
        .unacceptedLoss(.init(losses: [.init(domain: .placement, reason: .unrepresentableSource,
            description: description)]))
    }
}
