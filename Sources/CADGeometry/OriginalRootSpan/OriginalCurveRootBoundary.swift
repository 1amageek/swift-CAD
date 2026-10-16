import CADCore

/// Original source root endpoint with exact incidence independent of numeric evaluation.
public struct OriginalCurveRootBoundary: Hashable, Sendable {
    public let source: BSplineCurve3D
    public let spanIndex: Int
    public let constraint: OriginalCurveIncidenceConstraint
    public let isolationLower: ExactRationalCoefficient
    public let isolationUpper: ExactRationalCoefficient
    public let excludesLowerEndpoint: Bool
    public let excludesUpperEndpoint: Bool
    public let isolationDepth: Int
    public let certificationTolerance: ModelingTolerance
    private let polynomial: OriginalRationalCurvePolynomial
    private let root: ExactAlgebraicRealRoot
    package var retainedRootEndpoint: ExactMonotoneGraphEndpoint { .algebraic(root) }

    public init<B: ExactScalarAdmission & ~Copyable>(source: BSplineCurve3D, spanIndex: Int,
        constraint: OriginalCurveIncidenceConstraint, isolation: ExactUnivariateRootIsolator.Root,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try self.init(source: source, spanIndex: spanIndex, constraint: constraint,
            isolationLower: isolation.lower, isolationUpper: isolation.upper,
            excludesLowerEndpoint: isolation.excludesLowerEndpoint,
            excludesUpperEndpoint: isolation.excludesUpperEndpoint,
            isolationDepth: isolation.isolationDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, usage: &usage)
    }

    public init<B: ExactScalarAdmission & ~Copyable>(source: BSplineCurve3D, spanIndex: Int,
        constraint: OriginalCurveIncidenceConstraint, isolation: ScalarInterval,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        let lower = try ExactRationalCoefficient.originalDouble(isolation.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(isolation.upper, usage: &usage)
        try self.init(source: source, spanIndex: spanIndex, constraint: constraint,
            isolationLower: lower, isolationUpper: upper,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
    }

    public init<B: ExactScalarAdmission & ~Copyable>(source: BSplineCurve3D, spanIndex: Int,
        constraint: OriginalCurveIncidenceConstraint, isolationLower lower: ExactRationalCoefficient,
        isolationUpper upper: ExactRationalCoefficient, excludesLowerEndpoint: Bool = false,
        excludesUpperEndpoint: Bool = false, isolationDepth: Int = 0, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        guard maximumSubdivisionDepth >= 0, isolationDepth >= 0, isolationDepth <= maximumSubdivisionDepth,
              !(try upper.subtracting(lower, usage: &usage)).isNegative else {
            throw GeometryConversionError.invalidInput("Original root boundary needs ordered exact isolation and caller depth.")
        }
        let original = try OriginalRationalCurvePolynomial(source: source,
            spanIndex: spanIndex, tolerance: tolerance, usage: &usage)
        guard !(try lower.subtracting(original.lowerParameter, usage: &usage)).isNegative,
              !(try original.upperParameter.subtracting(upper, usage: &usage)).isNegative else {
            throw GeometryConversionError.invalidInput("Original root isolation extends beyond its owning native span.")
        }
        let numerators = try constraint.numerators(from: original, usage: &usage)
        var common: ExactBivariatePolynomial?
        for numerator in numerators where !numerator.isZero {
            common = try common.map { try ExactBivariateGCD().univariateGCD($0, numerator, usage: &usage) } ?? numerator
        }
        guard let common, common.uDegree > 0 else {
            throw GeometryConversionError.invalidInput("Original root boundary needs isolated incidence, not whole-span coincidence or a root-free source.")
        }
        let isolated = ExactUnivariateRootIsolator.Root(lower: lower, upper: upper,
            isRationalStation: lower == upper, isolationDepth: isolationDepth,
            excludesLowerEndpoint: excludesLowerEndpoint, excludesUpperEndpoint: excludesUpperEndpoint)
        let root = try ExactAlgebraicRealRoot(polynomial: common, isolation: isolated, usage: &usage)
        for numerator in numerators {
            guard case .zero = try root.sign(of: numerator,
                maximumDepth: maximumSubdivisionDepth, usage: &usage) else {
                throw GeometryConversionError.invalidInput("Original algebraic root does not satisfy every source incidence equation.")
            }
        }
        self.source = source; self.spanIndex = spanIndex; self.constraint = constraint
        isolationLower = lower; isolationUpper = upper
        self.excludesLowerEndpoint = excludesLowerEndpoint; self.excludesUpperEndpoint = excludesUpperEndpoint
        self.isolationDepth = isolationDepth; certificationTolerance = tolerance
        polynomial = original; self.root = root
    }

    /// Retains an already admitted unique native parameter root without rebuilding it.
    package static func retaining<B: ExactScalarAdmission & ~Copyable>(source: BSplineCurve3D,
        spanIndex: Int, coordinate: ExactAlgebraicRealRoot, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B, maximumAlgebraicDepth: Int = 32) throws -> Self {
        let original = try OriginalRationalCurvePolynomial(source: source,
            spanIndex: spanIndex, tolerance: tolerance, usage: &usage)
        return try retaining(prepared: original, coordinate: coordinate,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance,
            usage: &usage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    package static func retaining<B: ExactScalarAdmission & ~Copyable>(
        prepared original: OriginalRationalCurvePolynomial, coordinate: ExactAlgebraicRealRoot,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B,
        maximumAlgebraicDepth: Int = 32) throws -> Self {
        let isolation = coordinate.isolation
        guard case .bSpline = original.originalCurve, original.originalTranslation == 0,
            maximumSubdivisionDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
            maximumAlgebraicDepth >= isolation.isolationDepth, isolation.isolationDepth >= 0,
            coordinate.polynomial.vDegree <= 0, coordinate.polynomial.uDegree > 0 else {
            throw GeometryConversionError.invalidInput("Retained parameter root requires base-native source and independent caller algebra authority.")
        }
        guard !(try isolation.lower.subtracting(original.lowerParameter, usage: &usage)).isNegative,
            !(try original.upperParameter.subtracting(isolation.upper, usage: &usage)).isNegative else {
            throw GeometryConversionError.invalidInput("Retained parameter root extends beyond its original native owner.")
        }
        try usage.consumeWork(1)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(source: original.source, spanIndex: original.spanIndex, coordinate: coordinate,
            polynomial: original, tolerance: tolerance)
    }

    private init(source: BSplineCurve3D, spanIndex: Int, coordinate: ExactAlgebraicRealRoot,
        polynomial: OriginalRationalCurvePolynomial, tolerance: ModelingTolerance) {
        self.source = source; self.spanIndex = spanIndex
        constraint = .parameterPolynomial(coordinate.polynomial)
        isolationLower = coordinate.isolation.lower; isolationUpper = coordinate.isolation.upper
        excludesLowerEndpoint = coordinate.isolation.excludesLowerEndpoint
        excludesUpperEndpoint = coordinate.isolation.excludesUpperEndpoint
        isolationDepth = coordinate.isolation.isolationDepth; certificationTolerance = tolerance
        self.polynomial = polynomial; root = coordinate
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.source == b.source && a.spanIndex == b.spanIndex && a.constraint == b.constraint
            && a.isolationLower == b.isolationLower && a.isolationUpper == b.isolationUpper
            && a.excludesLowerEndpoint == b.excludesLowerEndpoint && a.excludesUpperEndpoint == b.excludesUpperEndpoint
            && a.isolationDepth == b.isolationDepth && a.certificationTolerance == b.certificationTolerance
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(source); hasher.combine(spanIndex); hasher.combine(constraint)
        func rational(_ value: ExactRationalCoefficient) {
            hasher.combine(value.canonicalSign); hasher.combine(value.canonicalNumeratorWords); hasher.combine(value.canonicalDenominatorWords)
        }
        rational(isolationLower); rational(isolationUpper)
        hasher.combine(excludesLowerEndpoint); hasher.combine(excludesUpperEndpoint); hasher.combine(isolationDepth)
        hasher.combine(certificationTolerance)
    }

    /// Refines only derived isolating state; original source fields stay unchanged.
    func refinedIsolation<B: ExactScalarAdmission & ~Copyable>(maximumWidth: Double,
        maximumSubdivisionDepth: Int, usage: inout B) throws -> ExactUnivariateRootIsolator.Root {
        guard maximumWidth.isFinite, maximumWidth > 0 else {
            throw GeometryConversionError.invalidInput("Original root refinement requires a finite positive width.")
        }
        return try root.refined(maximumWidth: .originalDouble(maximumWidth, usage: &usage),
            maximumDepth: maximumSubdivisionDepth, usage: &usage).isolation
    }

    /// Refines the original unique root, never treating a candidate midpoint as incidence.
    package func parameterBounds<B: ExactScalarAdmission & ~Copyable>(maximumWidth: Double,
        maximumSubdivisionDepth: Int, usage: inout B) throws -> ScalarInterval {
        let refined = try refinedIsolation(maximumWidth: maximumWidth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        let lower = try refined.lower.outwardInterval(usage: &usage)
        let upper = try refined.upper.outwardInterval(usage: &usage)
        return try .init(lower: lower.lower, upper: upper.upper)
    }

    package func positionBounds<B: ExactScalarAdmission & ~Copyable>(maximumParameterWidth: Double,
        maximumSubdivisionDepth: Int, usage: inout B) throws -> IntervalVector3DBounds {
        let isolation = try refinedIsolation(maximumWidth: maximumParameterWidth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        let weight = try OriginalRationalPolynomialRange(original: polynomial.homogeneous[3],
            lower: isolation.lower, upper: isolation.upper, usage: &usage)
        func coordinate(_ axis: Int, usage: inout B) throws -> OutwardScalarInterval {
            try OriginalRationalPolynomialRange(original: polynomial.homogeneous[axis],
                lower: isolation.lower, upper: isolation.upper, usage: &usage)
                .divided(by: weight, usage: &usage).outward(usage: &usage)
        }
        let x = try coordinate(0, usage: &usage)
        let y = try coordinate(1, usage: &usage)
        let z = try coordinate(2, usage: &usage)
        return .init(x: x, y: y, z: z)
    }

    package func sign<B:ExactScalarAdmission & ~Copyable>(of expression:ExactBivariatePolynomial,
        maximumSubdivisionDepth:Int,usage:inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try root.sign(of:expression,maximumDepth:maximumSubdivisionDepth,usage:&usage)
    }

    package func provesAxis(origin: Point3D, direction: Vector3D) -> Bool {
        constraint == .axis(origin: origin, direction: direction)
    }
}

#if !hasFeature(Embedded)
extension OriginalCurveRootBoundary: Codable {
    private enum CodingKeys: String, CodingKey {
        case source, spanIndex, constraint, isolationLower, isolationUpper
        case excludesLowerEndpoint, excludesUpperEndpoint, isolationDepth, certificationTolerance
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.source, .spanIndex, .constraint, .isolationLower, .isolationUpper,
            .excludesLowerEndpoint, .excludesUpperEndpoint, .isolationDepth, .certificationTolerance], in: decoder)
            var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
            try self.init(source: c.decode(BSplineCurve3D.self, forKey: .source),
                spanIndex: c.decode(Int.self, forKey: .spanIndex),
                constraint: c.decode(OriginalCurveIncidenceConstraint.self, forKey: .constraint),
                isolationLower: c.decode(ExactRationalCoefficient.self, forKey: .isolationLower),
                isolationUpper: c.decode(ExactRationalCoefficient.self, forKey: .isolationUpper),
                excludesLowerEndpoint: c.decode(Bool.self, forKey: .excludesLowerEndpoint),
                excludesUpperEndpoint: c.decode(Bool.self, forKey: .excludesUpperEndpoint),
                isolationDepth: c.decode(Int.self, forKey: .isolationDepth),
                maximumSubdivisionDepth: usage.limits.maximumValueDepth,
                tolerance: c.decode(ModelingTolerance.self, forKey: .certificationTolerance), usage: &usage)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source); try c.encode(spanIndex, forKey: .spanIndex)
        try c.encode(constraint, forKey: .constraint); try c.encode(isolationLower, forKey: .isolationLower)
        try c.encode(isolationUpper, forKey: .isolationUpper)
        try c.encode(excludesLowerEndpoint, forKey: .excludesLowerEndpoint)
        try c.encode(excludesUpperEndpoint, forKey: .excludesUpperEndpoint)
        try c.encode(isolationDepth, forKey: .isolationDepth)
        try c.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
#endif
