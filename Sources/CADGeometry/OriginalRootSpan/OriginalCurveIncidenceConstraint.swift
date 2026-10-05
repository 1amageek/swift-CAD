import CADCore

/// Original unnormalized incidence coefficients; no constructed axis point is substituted.
public enum OriginalCurveIncidenceConstraint: Hashable, Sendable {
    case plane(origin: Point3D, normal: Vector3D)
    case axis(origin: Point3D, direction: Vector3D)
    case parameterPolynomial(ExactBivariatePolynomial)

    func numerators<B: RationalAlgebraAdmitting>(from source: OriginalRationalCurvePolynomial,
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        switch self {
        case .parameterPolynomial(let polynomial):
            guard polynomial.vDegree <= 0, polynomial.uDegree > 0 else {
                throw GeometryConversionError.invalidInput("Original parameter root requires a nonconstant univariate polynomial.")
            }
            try usage.retainExactStorage(1)
            return [polynomial]
        case .axis(let origin, let direction):
            return try source.axisIncidenceNumerators(origin: origin, direction: direction, usage: &usage)
        case .plane(let origin, let normal):
            try origin.validate(); try normal.validate()
            guard normal.x != 0 || normal.y != 0 || normal.z != 0 else {
                throw GeometryConversionError.invalidInput("Original root plane requires a nonzero original normal.")
            }
            return [try source.planeIncidenceNumerator(origin: origin, normal: normal, usage: &usage)]
        }
    }
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .plane(let origin, let normal):
            hasher.combine(0); hasher.combine(origin); hasher.combine(normal)
        case .axis(let origin, let direction):
            hasher.combine(1); hasher.combine(origin); hasher.combine(direction)
        case .parameterPolynomial(let polynomial):
            hasher.combine(2)
            let powers = polynomial.coefficients.keys.sorted {
                $0.u == $1.u ? $0.v < $1.v : $0.u < $1.u
            }
            for power in powers {
                hasher.combine(power)
                let value = polynomial.coefficients[power]!
                hasher.combine(value.canonicalSign)
                hasher.combine(value.canonicalNumeratorWords)
                hasher.combine(value.canonicalDenominatorWords)
            }
        }
    }
}

#if !hasFeature(Embedded)
extension OriginalCurveIncidenceConstraint: Codable {}
#endif
