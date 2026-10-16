import CADCore

/// Shared original coefficient/guard theorem for certified and primitive routes.
struct OriginalCoaxialConeCylinderCoefficients: Sendable {
    let field: OriginalPhysicalAngleScalarDomain
    let radius: OriginalPhysicalAngleValue
    let positiveSlant: OriginalPhysicalAngleValue
    let positiveHeight: OriginalPhysicalAngleValue
    let labelPeriod: OriginalPhysicalAngleValue
    let proofDepth: ExactScalarDepth
    static func prepare<A: ExactScalarAdmission & ~Copyable>(radius: Double,
        field f: OriginalPhysicalAngleScalarDomain, using a: inout A) throws -> Self {
        try a.withProofScope { a in
            try a.checkpoint(); try a.consumeWork(1)
            let r = try f.binary64(exactly: radius, using: &a)
            let sine = try f.sine(using: &a), cosine = try f.cosine(using: &a)
            guard try f.sign(of: r, using: &a) == .positive,
                try f.sign(of: sine, using: &a) == .positive,
                try f.sign(of: cosine, using: &a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
            let slant = try f.dividing(r, sine, using: &a)
            let height = try f.multiplying(cosine, slant, using: &a)
            let period = try f.binary64(exactly: 2 * Double.pi, using: &a)
            let radial = try f.multiplying(sine, slant, using: &a)
            guard try f.compare(f.multiplying(radial, radial, using: &a), f.multiplying(r, r, using: &a), using: &a) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            let depth = try a.depth
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(field: f, radius: r, positiveSlant: slant, positiveHeight: height,
                labelPeriod: period, proofDepth: depth)
            try a.checkpoint(); return result
        }
    }
}
