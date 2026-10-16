import CADCore

/// Original unnormalized incidence coefficients; no constructed axis point is substituted.
public enum OriginalCurveIncidenceConstraint: Hashable, Sendable {
    case plane(origin: Point3D, normal: Vector3D)
    case axis(origin: Point3D, direction: Vector3D)
    case parameterPolynomial(ExactBivariatePolynomial)

    func numerators<B: ExactScalarAdmission & ~Copyable>(from source: OriginalRationalCurvePolynomial,
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        switch self {
        case .parameterPolynomial(let polynomial):
            guard polynomial.vDegree <= 0, polynomial.uDegree > 0 else {
                throw GeometryConversionError.invalidInput("Original parameter root requires a nonconstant univariate polynomial.")
            }
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage:&usage)
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
extension OriginalCurveIncidenceConstraint: Codable {
    private enum Keys: String, CodingKey { case plane, axis, parameterPolynomial }
    private enum Fields: String, CodingKey { case origin, normal, direction }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original incidence requires exactly one source case."))
        }
        switch key {
        case .plane, .axis:
            let fields = try container.nestedContainer(keyedBy: Fields.self, forKey: key)
            let expected: Set<Fields> = key == .plane ? [.origin, .normal] : [.origin, .direction]
            guard Set(fields.allKeys) == expected else {
                throw DecodingError.dataCorrupted(.init(codingPath: fields.codingPath,
                    debugDescription: "Original incidence fields are invalid."))
            }
            let origin = try fields.decode(Point3D.self, forKey: .origin)
            self = try key == .plane
                ? .plane(origin: origin, normal: fields.decode(Vector3D.self, forKey: .normal))
                : .axis(origin: origin, direction: fields.decode(Vector3D.self, forKey: .direction))
        case .parameterPolynomial:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Native root-span decoding lacks
            // the caller-admitted original polynomial codec. Production Native
            // document import must fail until the complete raw coefficients and
            // budgets are retained; portable encoding is not a Native substitute.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
                message: "Native original parameter-polynomial incidence decoding is incomplete.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .plane(let origin, let normal):
            var fields = container.nestedContainer(keyedBy: Fields.self, forKey: .plane)
            try fields.encode(origin, forKey: .origin); try fields.encode(normal, forKey: .normal)
        case .axis(let origin, let direction):
            var fields = container.nestedContainer(keyedBy: Fields.self, forKey: .axis)
            try fields.encode(origin, forKey: .origin); try fields.encode(direction, forKey: .direction)
        case .parameterPolynomial:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Native root-span encoding lacks
            // original polynomial coefficient persistence. Production Native
            // document export must fail rather than drop or round the root law.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
                message: "Native original parameter-polynomial incidence encoding is incomplete.")
        }
    }
}
#endif
