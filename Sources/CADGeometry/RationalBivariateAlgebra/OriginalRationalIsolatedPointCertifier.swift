/// Exact whole-polynomial isolated point proof, including higher-order flat contacts.
package struct OriginalRationalIsolatedPointCertifier {
    package static func provesOnlyZero<B: ExactScalarAdmission & ~Copyable>(
        at root: ExactBivariateCriticalPoint, maximumDepth: Int, usage: inout B) throws -> Bool {
        guard !root.original.isZero else { return false }
        if try evenTaylor(at: root, maximumDepth: maximumDepth, usage: &usage) { return true }
        if try OriginalRationalSeparableIsolatedPointCertifier.provesOnlyZero(at: root,
            maximumDepth: maximumDepth, usage: &usage) { return true }
        return try OriginalRationalSumOfSquaresIsolatedPointCertifier.provesOnlyZero(at: root,
            maximumDepth: maximumDepth, usage: &usage)
    }

    private static func evenTaylor<B: ExactScalarAdmission & ~Copyable>(at root: ExactBivariateCriticalPoint,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        let source = root.original
        var commonSign: ExactAlgebraicRealRoot.Sign?
        var pureU = false, pureV = false
        var uDerivative = source
        for uOrder in 0...source.uDegree {
            var derivative = uDerivative
            for vOrder in 0...source.vDegree {
                try usage.consumeWork(1)
                let sign = try root.sign(of: derivative, maximumDepth: maximumDepth, usage: &usage)
                switch sign {
                case .zero: break
                case .negative, .positive:
                    guard uOrder % 2 == 0, vOrder % 2 == 0, (uOrder > 0 || vOrder > 0) else { return false }
                    if let previous = commonSign {
                        switch (previous, sign) {
                        case (.negative, .negative), (.positive, .positive): break
                        default: return false
                        }
                    } else { commonSign = sign }
                    if uOrder > 0, vOrder == 0 { pureU = true }
                    if vOrder > 0, uOrder == 0 { pureV = true }
                }
                if vOrder < source.vDegree {
                    derivative = try derivative.differentiated(alongU: false, usage: &usage)
                }
            }
            if uOrder < source.uDegree {
                uDerivative = try uDerivative.differentiated(alongU: true, usage: &usage)
            }
        }
        return commonSign != nil && pureU && pureV
    }
}
