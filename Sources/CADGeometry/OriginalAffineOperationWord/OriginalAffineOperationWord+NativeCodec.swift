#if !hasFeature(Embedded)
extension OriginalAffineOperationWord: Codable {
    private enum Keys: String, CodingKey { case factors }
    public init(from decoder: any Decoder) throws {
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        try usage.visitCell(axis: .value, depth: 0)
        try NativeOriginalAffineWordCodec.keys(decoder, allowed: ["factors"])
        let object = try decoder.container(keyedBy: Keys.self)
        var source = try object.nestedUnkeyedContainer(forKey: .factors)
        guard let count = source.count else { throw NativeRationalSourceDecodingError.unboundedWordContainer }
        try usage.consumeWork(count)
        try OriginalAffineRationalMatrix.retain(count, of: OriginalAffineOperation.self, usage: &usage)
        var factors: [OriginalAffineOperation] = []; factors.reserveCapacity(count)
        while !source.isAtEnd { factors.append(try source.decode(OriginalAffineOperation.self)) }
        try usage.consumeWork(factors.count)
        let needsNormalized = factors.contains { value in
            switch value { case .normalizedForward, .normalizedInverse: true; default: false }
        }
        let maximumDepth = try OriginalAffineWordDecodingContext.maximumAlgebraicDepth(from: decoder)
        if needsNormalized {
            let tolerance = try OriginalAffineWordDecodingContext.tolerance(from: decoder)
            try self.init(factors: factors, tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        } else {
            let rational = try Self(factors: factors, usage: &usage)
            self.init(originalFactors: rational.factors, coefficients: rational.coefficients,
                cofactors: rational.cofactorCoefficients, determinant: rational.determinantCoefficient,
                maximumDepth: maximumDepth, orientationSign: rational.orientationSign)
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(factors, forKey: .factors)
    }
}
#endif
