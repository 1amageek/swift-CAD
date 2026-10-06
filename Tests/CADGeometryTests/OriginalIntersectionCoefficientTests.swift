import CADCore
@testable import CADGeometry
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OriginalIntersectionCoefficientTests {
    private struct Admission: RationalAlgebraAdmitting {
        var maximumWork = 20_000_000
        var maximumStorage = 20_000_000
        var maximumParameterDepth = 24
        var maximumCoefficientDepth = 24
        var work = 0
        var storage = 0
        var parameterVisits = 0
        var coefficientVisits = 0
        var parameterDepth = 0
        var coefficientDepth = 0
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw failure("work") }; work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw failure("storage") }; storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumParameterDepth else { throw failure("parameter depth") }
            parameterVisits += 1; parameterDepth = max(parameterDepth, depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumCoefficientDepth else { throw failure("coefficient depth") }
            coefficientVisits += 1; coefficientDepth = max(coefficientDepth, depth)
        }
        private func failure(_ domain: String) -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original coefficient test exhausted independent \(domain).")
        }
    }

    private func squareRoot(_ value: Int, coefficient: Bool, usage: inout Admission) throws -> OriginalSingularFieldElement {
        let context = try OriginalSingularFieldContext(usage: &usage)
        let radicand = try OriginalSingularFieldElement.constant(.natural(value, usage: &usage),
            in: context, maximumDepth: 24, usage: &usage)
        return try radicand.nonnegativeSquareRoot(inheritedDepth: 0, maximumDepth: 24,
            admissionDomain: coefficient ? .coefficient(maximumDepth: 24) : .parameter, usage: &usage)
    }

    @Test func actualNormalizedFrameKeepsCoefficientAuthorityWithoutParameterRefinement() throws {
        var usage = Admission(); usage.maximumParameterDepth = 0
        let context = try OriginalSingularFieldContext(usage: &usage)
        let frame = try OriginalRationalNormalizedFrame(family: .axis2, location: .zero,
            axis1: .unitZ, axis2: nil, axis3: Vector3D(x: 1, y: 1, z: 0), scale: nil,
            lengthGain: .one, adjustments: [], in: context, tolerance: .standard,
            normalizationPolicy: .dimensionlessOriginalDirections, inheritedDepth: 0, maximumDepth: 24, usage: &usage)
        let retained = try OriginalIntersectionCoefficient.prepare(original: frame.basisZ[0],
            maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        guard case .algebraic(let annihilator, let root) = retained.representation else {
            Issue.record("Original normalized direction was rounded into a rational coefficient."); return
        }
        #expect(annihilator.uDegree == 2)
        #expect(try root.value(maximumDepth: 0, usage: &usage).sign(maximumDepth: 0, usage: &usage) == .positive)
        #expect(retained.original.context === frame.basisZ[0].context)
        #expect(retained.parameterAdmissionDepth == 0)
        #expect(usage.parameterVisits == 0)
        #expect(usage.coefficientVisits > 0)
    }

    @Test func oppositeOriginalConjugatesRetainDifferentRealIsolations() throws {
        var usage = Admission()
        let value = try squareRoot(2, coefficient: true, usage: &usage)
        let opposite = try value.negated(maximumDepth: 0, usage: &usage)
        let first = try OriginalIntersectionCoefficient.prepare(original: value,
            maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        let second = try OriginalIntersectionCoefficient.prepare(original: opposite,
            maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        guard case .algebraic(let a, let positive) = first.representation,
            case .algebraic(let b, let negative) = second.representation else {
            Issue.record("Original square-root conjugates lost their law."); return
        }
        #expect(a == b)
        #expect(try positive.value(maximumDepth: 0, usage: &usage).sign(maximumDepth: 0, usage: &usage) == .positive)
        #expect(try negative.value(maximumDepth: 0, usage: &usage).sign(maximumDepth: 0, usage: &usage) == .negative)
        #expect(first.coefficientAdmissionDepth >= value.context.coefficientDepth)
    }

    @Test func actualEuclideanPolylineRetainsCorrelatedMultiRootCoefficients() throws {
        var usage = Admission(); usage.maximumParameterDepth = 0
        let source = try OriginalEuclideanPolyline3DParameterLaw(originalPoints: [
            .origin, Point3D(x: 1, y: 1, z: 0), Point3D(x: 2, y: 2, z: 1)
        ], inheritedDepth: 0, maximumAlgebraicDepth: 24, usage: &usage)
        let retained = try OriginalIntersectionCoefficient.prepare(original: source.totalLength,
            maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        guard case .algebraic(let annihilator, let root) = retained.representation else {
            Issue.record("Original sum of Euclidean segment lengths lost its algebraic authority."); return
        }
        #expect(annihilator.uDegree == 4)
        let three = try ExactRationalCoefficient.natural(3, usage: &usage)
        let station = try OriginalSingularFieldElement.constant(three, in: root.polynomial.context,
            maximumDepth: 0, usage: &usage)
        let value = try root.value(maximumDepth: 0, usage: &usage)
        #expect(try value.subtracting(station, maximumDepth: 0, usage: &usage)
            .sign(maximumDepth: 0, usage: &usage) == .positive)
        #expect(usage.parameterVisits == 0)
        #expect(retained.coefficientAdmissionDepth >= source.context.coefficientDepth)
    }

    @Test func retainedParameterSourceUsesBothIndependentAdmissionDomains() throws {
        var preparation = Admission()
        let value = try squareRoot(2, coefficient: false, usage: &preparation)
        var usage = Admission()
        let retained = try OriginalIntersectionCoefficient.prepare(original: value,
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        #expect(retained.parameterAdmissionDepth >= value.context.depth)
        #expect(usage.parameterVisits > 0)
        #expect(usage.coefficientVisits > 0)
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCoefficient.prepare(original: value,
                maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        }
    }

    @Test func reducibleOriginalLawSaturatesOnlyUnselectedDenominatorPoles() throws {
        var usage = Admission()
        let context = try OriginalSingularFieldContext(usage: &usage)
        let coefficients = try [6, -2, -3, 1].map { value in
            let magnitude = try ExactRationalCoefficient.natural(abs(value), usage: &usage)
            return try OriginalSingularFieldElement.constant(value < 0 ? magnitude.negated : magnitude,
                in: context, maximumDepth: 24, usage: &usage)
        }
        let polynomial = try OriginalSingularFieldPolynomial(context: context, coefficients: coefficients,
            maximumDepth: 24, usage: &usage)
        let roots = try OriginalSingularFieldRoot.allRealRoots(polynomial, inheritedDepth: 0,
            maximumDepth: 0, admissionDomain: .coefficient(maximumDepth: 24), usage: &usage)
        var selected: OriginalSingularFieldElement?
        for root in roots {
            let value = try root.value(maximumDepth: 0, usage: &usage)
            let two = try OriginalSingularFieldElement.constant(.natural(2, usage: &usage),
                in: value.context, maximumDepth: 0, usage: &usage)
            if try value.sign(maximumDepth: 0, usage: &usage) == .positive,
                try value.subtracting(two, maximumDepth: 0, usage: &usage)
                    .sign(maximumDepth: 0, usage: &usage) == .negative { selected = value }
        }
        let value = try #require(selected)
        let three = try OriginalSingularFieldElement.constant(.natural(3, usage: &usage),
            in: value.context, maximumDepth: 0, usage: &usage)
        let denominator = try value.subtracting(three, maximumDepth: 0, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: value.context,
            maximumDepth: 0, usage: &usage)
        let inverse = try one.divided(by: denominator, maximumDepth: 0, usage: &usage)
        let retained = try OriginalIntersectionCoefficient.prepare(original: inverse,
            maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        guard case .algebraic(let annihilator, let root) = retained.representation else {
            Issue.record("Original inverse coefficient lost its saturated law."); return
        }
        #expect(annihilator.uDegree == 2)
        #expect(try root.value(maximumDepth: 0, usage: &usage).sign(maximumDepth: 0, usage: &usage) == .negative)
        let zero = try value.subtracting(value, maximumDepth: 0, usage: &usage)
        #expect(throws: KernelError.self) { try one.divided(by: zero, maximumDepth: 0, usage: &usage) }
    }

    @Test func cancellationCannotPublishAnOriginalCoefficientOrSpendNewWork() async throws {
        let charged = try await Task {
            var preparation = Admission()
            let value = try squareRoot(2, coefficient: true, usage: &preparation)
            var usage = Admission()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try OriginalIntersectionCoefficient.prepare(original: value,
                    maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
                Issue.record("Cancelled coefficient transport published a replacement.")
            } catch is CancellationError { return usage.work }
            return -1
        }.value
        #expect(charged == 0)
    }

    @Test func independentLimitsAndRationalConstantsDoNotResetOrInventRootDepth() throws {
        var preparation = Admission()
        let value = try squareRoot(2, coefficient: true, usage: &preparation)
        var usage = Admission()
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCoefficient.prepare(original: value,
                maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        }
        var work = Admission(); work.maximumWork = 0
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCoefficient.prepare(original: value,
                maximumDepth: 24, maximumCoefficientDepth: 24, usage: &work)
        }
        var storage = Admission(); storage.maximumStorage = 0
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCoefficient.prepare(original: value,
                maximumDepth: 24, maximumCoefficientDepth: 24, usage: &storage)
        }
        let context = try OriginalSingularFieldContext(usage: &usage)
        let rational = try OriginalSingularFieldElement.constant(.one, in: context,
            maximumDepth: 0, usage: &usage)
        var fresh = Admission(); fresh.maximumCoefficientDepth = 0; fresh.maximumParameterDepth = 0
        let retained = try OriginalIntersectionCoefficient.prepare(original: rational,
            maximumDepth: 0, maximumCoefficientDepth: 0, usage: &fresh)
        guard case .rational(let exact) = retained.representation else {
            Issue.record("Original rational constant acquired an unrelated auxiliary root."); return
        }
        #expect(exact == .one)
        #expect(fresh.parameterVisits == 0 && fresh.coefficientVisits == 0)
    }
}
