public extension ExactBivariatePolynomial {
    func evaluated<B: ExactScalarAdmission & ~Copyable>(atU u: ExactRationalCoefficient,
        v: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient {
        var result = ExactRationalCoefficient.zero
        for term in try orderedTerms(usage: &usage) {
            let a = try Self.power(u, exponent: term.key.u, usage: &usage)
            let b = try Self.power(v, exponent: term.key.v, usage: &usage)
            result = try result.adding(term.value.multiplied(by: a, usage: &usage)
                .multiplied(by: b, usage: &usage), usage: &usage)
        }
        return result
    }

    func restricted<B: ExactScalarAdmission & ~Copyable>(alongU: Bool, station: ExactRationalCoefficient,
        usage: inout B) throws -> Self {
        var result = Self.zero
        for term in try orderedTerms(usage: &usage) {
            let scale = try Self.power(station, exponent: alongU ? term.key.u : term.key.v, usage: &usage)
            let value = try term.value.multiplied(by: scale, usage: &usage)
            let power = try Power(u: alongU ? term.key.v : term.key.u, v: 0)
            if !value.isZero {
                try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage)
                result = try result.adding(Self([power: value]), usage: &usage)
            }
        }
        return result
    }

    package func orderedTerms<B: ExactScalarAdmission & ~Copyable>(usage: inout B)
        throws -> [(key: Power, value: ExactRationalCoefficient)] {
        let count = coefficients.count
        let levels = count <= 1 ? 0 : Int.bitWidth - (count - 1).leadingZeroBitCount
        try usage.consumeWork(exactScalarCount(count, levels + 1, multiply: true))
        try RationalAlgebraStorage.retain(count, of: (key: Power, value: ExactRationalCoefficient).self, usage: &usage)
        return coefficients.sorted { a, b in a.key.v == b.key.v ? a.key.u < b.key.u : a.key.v < b.key.v }
    }

    private static func power<B: ExactScalarAdmission & ~Copyable>(_ source: ExactRationalCoefficient,
        exponent: Int, usage: inout B) throws -> ExactRationalCoefficient {
        var result = ExactRationalCoefficient.one, factor = source, remaining = exponent
        while remaining > 0 {
            try usage.consumeWork(1)
            if remaining & 1 == 1 { result = try result.multiplied(by: factor, usage: &usage) }
            remaining >>= 1
            if remaining > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
        }
        return result
    }
}
