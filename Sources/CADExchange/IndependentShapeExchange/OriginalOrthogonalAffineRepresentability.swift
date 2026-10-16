import CADCore
import CADGeometry

/// Proves that the original binary columns have a legal uniform orthogonal exchange image.
enum OriginalOrthogonalAffineRepresentability {
    static func scale(of frame: AffineTransform3D,
        requiresUnitScale: Bool, format: ExchangeFileFormat = .step, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.visitCell(axis: .value, depth: 0)
        let xx = try dot(frame.basisX, frame.basisX, using: &execution)
        let yy = try dot(frame.basisY, frame.basisY, using: &execution)
        let zz = try dot(frame.basisZ, frame.basisZ, using: &execution)
        guard xx.isPositive, xx == yy, xx == zz,
              try dot(frame.basisX, frame.basisY, using: &execution).isZero,
              try dot(frame.basisX, frame.basisZ, using: &execution).isZero,
              try dot(frame.basisY, frame.basisZ, using: &execution).isZero else {
            throw loss("Original affine columns have shear or unequal scales that the format's uniform orthogonal operator cannot retain.")
        }
        let candidate = requiresUnitScale ? 1 : normCandidate(frame.basisX)
        guard candidate.isFinite, candidate > 0 else {
            throw loss("Original uniform scale has no finite positive output candidate.")
        }
        let exact = try ExactRationalCoefficient.originalDouble(candidate, usage: &execution)
        guard try exact.multiplied(by: exact, usage: &execution) == xx else {
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
    static func normalizedFrame(_ frame: AffineTransform3D,
        scale: Double, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D {
        let exactScale = try ExactRationalCoefficient.originalDouble(scale, usage: &execution)
        func column(_ original: Vector3D, using execution: inout OriginalQueryExecution) throws -> Vector3D {
            let candidate = original / scale
            for (source, emitted) in [(original.x, candidate.x), (original.y, candidate.y), (original.z, candidate.z)] {
                let value = try ExactRationalCoefficient.originalDouble(emitted, usage: &execution)
                    .multiplied(by: exactScale, usage: &execution)
                guard value == (try ExactRationalCoefficient.originalDouble(source, usage: &execution)) else {
                    throw loss("Original uniform transform cannot be decomposed into the binary IGES matrix and scale without changing a coefficient.")
                }
            }
            return candidate
        }
        let x = try column(frame.basisX, using: &execution)
        let y = try column(frame.basisY, using: &execution)
        let z = try column(frame.basisZ, using: &execution)
        return try AffineTransform3D(basisX: x, basisY: y, basisZ: z, translation: .zero)
    }
    private static func dot(_ first: Vector3D, _ second: Vector3D,
        using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        let x = try ExactRationalCoefficient.originalDouble(first.x, usage: &execution)
            .multiplied(by: ExactRationalCoefficient.originalDouble(second.x, usage: &execution), usage: &execution)
        let y = try ExactRationalCoefficient.originalDouble(first.y, usage: &execution)
            .multiplied(by: ExactRationalCoefficient.originalDouble(second.y, usage: &execution), usage: &execution)
        let z = try ExactRationalCoefficient.originalDouble(first.z, usage: &execution)
            .multiplied(by: ExactRationalCoefficient.originalDouble(second.z, usage: &execution), usage: &execution)
        return try x.adding(y, usage: &execution).adding(z, usage: &execution)
    }
    private static func loss(_ description: String) -> ExchangePreservationError {
        .unacceptedLoss(.init(losses: [.init(domain: .placement, reason: .unrepresentableSource,
            description: description)]))
    }
}
