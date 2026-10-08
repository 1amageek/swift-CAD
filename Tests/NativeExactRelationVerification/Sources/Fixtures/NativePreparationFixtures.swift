import CADCore
@testable import CADGeometry

public enum NativePreparationFixtures {
    typealias Base = ExactRationalScalarDomain
    typealias Domain = ExactPolynomialDomain<Base>
    typealias Term = ExactPolynomialTerm<ExactRationalCoefficient>

    public static func verify() throws {
        try homogeneous()
        print("VERIFY ordered construction")
        try ordered()
        print("VERIFY inherited depth")
        try inheritedDepth()
        print("PASS homogeneous-only laws and checked ordered construction")
    }

    static func homogeneous() throws {
        for mode in 0..<4 {
            print("VERIFY homogeneous source case \(mode)")
            var surface = NativeExactFixtures.plane()
            if mode == 1 { surface.weights = [[1, 2], [3, 4]] }
            if mode == 2 { surface.uKnots = [-2, 0, 1, 3]; surface.vKnots = [-3, 0, 1, 4] }
            if mode == 3 {
                surface = .init(uDegree: 0, vDegree: 0, uKnots: [0, 1], vKnots: [0, 1],
                    controlPoints: [[.init(x: 0.25, y: 0.5, z: 0)]], weights: [[2]])
            }
            var a = try NativeExactFixtures.ledger()
            if mode == 3 {
                do {
                    _ = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                        try OriginalRationalSurfaceHomogeneous(source: surface, uSpanIndex: 0,
                            vSpanIndex: 0, tolerance: .standard, usage: &usage)
                    }
                    throw NativeExactFixtures.Failure.invalidEvidence
                } catch ExactScalarFailure.admissionRejected(let cause) {
                    guard case GeometryError.invalidDistance(0) = cause else { throw cause }
                }
                do { _ = try NativeExactFixtures.cs(DefaultCurveSurfaceIntersector(),
                    NativeExactFixtures.curve([-1, 1]), surface, using: &a)
                    throw NativeExactFixtures.Failure.invalidEvidence }
                catch NativeExactRelationFailure.scalar(.admissionRejected(let cause)) {
                    guard case GeometryError.invalidDistance(0) = cause else { throw cause }
                }
                continue
            }
            try ExactScalarNumericAccess.withAdmission(&a) { usage in
                let direct = try OriginalRationalSurfaceHomogeneous(source: surface,
                    uSpanIndex: surface.uDegree, vSpanIndex: surface.vDegree, tolerance: .standard, usage: &usage)
                let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard,
                    consumeWork: { try usage.consumeExactWork(1) },
                    consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
                let spans = try prepared.originalIntersectionNativeSpans(over: direct.domain, tolerance: .standard,
                    maximumSpanCount: 1, consumeWork: { try usage.consumeExactWork(1) },
                    consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
                guard let span = spans.first, spans.count == 1 else { throw NativeExactFixtures.Failure.invalidEvidence }
                let differential = try OriginalRationalSurfacePolynomial(source: surface, native: span,
                    domain: direct.domain, view: .init(x: 0, y: 0, z: 1), tolerance: .standard, usage: &usage)
                try NativeExactFixtures.require(direct.homogeneous == differential.homogeneous)
                let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
                let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
                let expected: [ExactBivariatePolynomial]
                if mode == 1 {
                    let uv = try u.multiplied(by: v, usage: &usage)
                    let two = try ExactRationalCoefficient.originalInteger(2, usage: &usage)
                    let three = try ExactRationalCoefficient.originalInteger(3, usage: &usage)
                    expected = try [u.scaled(by: two, usage: &usage).adding(uv.scaled(by: two, usage: &usage), usage: &usage),
                        v.scaled(by: three, usage: &usage).adding(uv, usage: &usage), .zero,
                        one.adding(u, usage: &usage).adding(v.scaled(by: two, usage: &usage), usage: &usage)]
                } else { expected = [u, v, .zero, one] }
                try NativeExactFixtures.require(direct.homogeneous == expected)
                try NativeExactFixtures.require(direct.source == surface && direct.domain.u.lower == 0 && direct.domain.u.upper == 1)
                do {
                    _ = try OriginalRationalSurfaceHomogeneous(source: surface, uSpanIndex: -1,
                        vSpanIndex: surface.vDegree, tolerance: .standard, usage: &usage)
                    throw NativeExactFixtures.Failure.invalidEvidence
                } catch is KernelError { }
            }
            var curve = NativeExactFixtures.curve([-1, 1])
            if mode == 1 { for index in curve.controlPoints.indices { curve.controlPoints[index].x = 0; curve.controlPoints[index].y = 0 } }
            let result = try NativeExactFixtures.cs(DefaultCurveSurfaceIntersector(), curve, surface, using: &a)
            try NativeExactFixtures.member(mode == 1 ? [(1, 2), (0, 1), (0, 1)] : [(1, 2), (1, 4), (1, 2)],
                result, expected: true, &a)
        }
    }

    static func construct<P: ExactPolynomialOrderedConstructing, A: ExactScalarAdmission & ~Copyable>(
        _ domain: P, _ terms: [ExactPolynomialTerm<P.Coefficient>], _ admission: inout A
    ) throws -> P.Polynomial {
        try domain.polynomial(orderedTerms: terms, using: &admission)
    }

    static func ordered() throws {
        var a = try NativeExactFixtures.ledger()
        let field = Base()
        let p = try Domain(field: field, variableCount: 2, using: &a)
        let one = try field.integer(1, using: &a), two = try field.integer(2, using: &a)
        var terms: [Term] = [.init(powers: [2, 0], coefficient: one), .init(powers: [1, 5], coefficient: two),
            .init(powers: [0, 1], coefficient: one)]
        let retained = try construct(p, terms, &a)
        let reference = try p.polynomial(terms: terms, using: &a)
        try NativeExactFixtures.require(try p.equals(retained, reference, using: &a))
        let shared = terms.withUnsafeBufferPointer { source in
            retained.terms.withUnsafeBufferPointer { source.baseAddress == $0.baseAddress }
        }
        try NativeExactFixtures.require(shared)
        terms.removeAll()
        try NativeExactFixtures.require(retained.terms.count == 3)
        for malformed: [Term] in [
            [.init(powers: [0], coefficient: one)], [.init(powers: [-1, 0], coefficient: one)],
            [.init(powers: [0, 0], coefficient: .zero)],
            [.init(powers: [0, 1], coefficient: one), .init(powers: [1, 0], coefficient: one)],
            [.init(powers: [1, 0], coefficient: one), .init(powers: [1, 0], coefficient: two)]
        ] {
            do { _ = try p.polynomial(orderedTerms: malformed, using: &a); throw NativeExactFixtures.Failure.invalidEvidence }
            catch is ExactPolynomialFailure { }
        }
        var limited = try NativeExactFixtures.ledger(work: 0)
        do { _ = try p.polynomial(orderedTerms: retained.terms, using: &limited); throw NativeExactFixtures.Failure.invalidEvidence }
        catch ExactPolynomialFailure.scalar(.resourceLimit(.work)) { }
        var zeroStorage = try NativeExactFixtures.ledger(bytes: 0)
        _ = try p.polynomial(orderedTerms: retained.terms, using: &zeroStorage)
        try NativeExactFixtures.require(zeroStorage.storageBytes == 0)
        let zero = try p.polynomial(orderedTerms: [], using: &a)
        try NativeExactFixtures.require(zero.terms.isEmpty)
        var measured = try OrderedConstructionAdmission()
        _ = try p.polynomial(orderedTerms: retained.terms, using: &measured)
        var cancelled = try OrderedConstructionAdmission(cancellingCall: measured.workCalls)
        do { _ = try p.polynomial(orderedTerms: retained.terms, using: &cancelled); throw NativeExactFixtures.Failure.invalidEvidence }
        catch ExactPolynomialFailure.scalar(.cancelled) { }

        typealias Field = ExactAlgebraicScalarDomain<Base>
        let first = try Field.base(field: field, maximumExtensionLevel: 1, using: &a)
        let second = try Field.base(field: field, maximumExtensionLevel: 1, using: &a)
        let foreign = try second.integer(1, using: &a)
        let domain = try ExactPolynomialDomain(field: first, variableCount: 1, using: &a)
        do { _ = try domain.polynomial(orderedTerms: [.init(powers: [0], coefficient: foreign)], using: &a)
            throw NativeExactFixtures.Failure.invalidEvidence }
        catch is ExactPolynomialFailure { }
    }

    static func inheritedDepth() throws {
        var a = try NativeExactFixtures.ledger()
        let root = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let two = try ExactRationalCoefficient.originalInteger(2, usage: &usage)
            let law = try ExactBivariatePolynomial.monomial(u: 2, v: 0, coefficient: .one, usage: &usage)
                .subtracting(.constant(two, usage: &usage), usage: &usage)
            let selected = try ExactUnivariateRootIsolator().isolate(law, lower: .one, upper: two,
                maximumDepth: 32, usage: &usage)[0]
            return try ExactAlgebraicRealRoot(polynomial: law, isolation: selected, usage: &usage)
                .refined(maximumWidth: .originalDouble(0.0625, usage: &usage), maximumDepth: 32, usage: &usage)
        }.value
        for axis: ExactScalarRootAxis in [.value, .coefficient] {
            let field = try OriginalExactScalarDomain(root: root, axis: axis, maximumValueDepth: 32,
                maximumCoefficientDepth: 32, using: &a)
            let coefficient = try field.generator(using: &a)
            let p = try ExactPolynomialDomain(field: field, variableCount: 1, using: &a)
            let value = try p.polynomial(orderedTerms: [.init(powers: [0], coefficient: coefficient)], using: &a)
            try NativeExactFixtures.require(value.depth.value > 0 || value.depth.coefficient > 0)
            var shallow = ExactScalarLedger(limits: try .init(work: 80_000_000, storageBytes: 1_073_741_824,
                valueDepth: axis == .value ? 0 : 32, coefficientDepth: axis == .coefficient ? 0 : 32))
            do { _ = try p.polynomial(orderedTerms: [], using: &shallow); throw NativeExactFixtures.Failure.invalidEvidence }
            catch is ExactPolynomialFailure { }
        }
    }
}
