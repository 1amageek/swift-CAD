extension OriginalRationalPolynomialRange {
    package func outward<B: RationalAlgebraAdmitting>(usage: inout B) throws -> OutwardScalarInterval {
        let a = try lower.outwardInterval(usage: &usage)
        let b = try upper.outwardInterval(usage: &usage)
        return OutwardScalarInterval(lower: a.lower, upper: b.upper)
    }
}
