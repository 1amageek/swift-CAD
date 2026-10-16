import CADCore

/// Source-owned wave position. No rounded candidate curve is used as authority.
public struct OriginalApexSphereConeSurfaceValues: Sendable {
    public typealias Field = OriginalApexSphereConeSurfaceSnapshot.Field
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let slant: Field.Value
    public let x: Field.Value
    public let y: Field.Value
    public let z: Field.Value
    public let proofDepth: ExactScalarDepth
    static func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalApexSphereConeSurfaceSnapshot,
        chart: Int, halfAngle t: Field.Value, using a: inout A) throws -> Self {
        try a.withProofScope { a in
            let f = source.field
            let t = try f.importing(t, using: &a)
            let one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
            let square = try f.multiplying(t, t, using: &a), q = try f.adding(one, square, using: &a)
            var sine = try f.dividing(f.multiplying(two, t, using: &a), q, using: &a)
            var cosine = try f.dividing(f.subtracting(one, square, using: &a), q, using: &a)
            if chart == 1 { sine = try f.negated(sine, using: &a); cosine = try f.negated(cosine, using: &a) }
            let slant = try f.multiplying(f.multiplying(two, source.sine, using: &a), sine, using: &a)
            let radial = try f.multiplying(source.sine, slant, using: &a)
            let x = try f.subtracting(one, f.multiplying(radial, sine, using: &a), using: &a)
            let y = try f.multiplying(radial, cosine, using: &a)
            let z = try f.multiplying(source.cosine, slant, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(field: f, sine: sine, cosine: cosine, slant: slant, x: x, y: y, z: z, proofDepth: try a.depth)
            try a.checkpoint(); return result
        }
    }
}
