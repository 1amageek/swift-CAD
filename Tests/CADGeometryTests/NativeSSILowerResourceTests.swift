import CADCore
@testable import CADGeometry
import Testing

@Suite(.timeLimit(.minutes(1)))
struct NativeSSILowerResourceTests {
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        var visits = 0
        var coefficientVisits = 0
        var maximumWork = 80_000_000
        var maximumStorage = 1_073_741_824
        var maximumVisits = 262_144
        var maximumDepth = 32
        var maximumCoefficientDepth = 32
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw failure() }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw failure() }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...maximumDepth).contains(depth), visits < maximumVisits else { throw failure() }
            visits += 1
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...maximumCoefficientDepth).contains(depth), coefficientVisits < maximumVisits else { throw failure() }
            coefficientVisits += 1
        }
        private func failure() -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Native SSI lower proof exhausted an independent original allowance.")
        }
    }

    @Test func projectionPreservesDistinctCutsRepeatedSupportAndRawSources() throws {
        var construction = Admission()
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 2, at: 0, usage: &construction)
        let two = try ExactRationalCoefficient.natural(2, usage: &construction)
        var expected: [ExactIntersectionPolynomial] = []
        var sources: [ExactIntersectionPolynomial] = []
        for offset in 0..<48 {
            let bound = try ExactIntersectionPolynomial.constant(variableCount: 2,
                value: .natural(offset, usage: &construction), usage: &construction)
            let law = try x.subtracting(bound, usage: &construction)
            expected.append(law)
            sources.append(law)
            sources.append(try law.multiplied(by: law, usage: &construction).scaled(by: two, usage: &construction))
        }
        var usage = Admission()
        let result = try ExactIntersectionProjection.prepare(sources: sources, variableCount: 2, axis: 1, usage: &usage)
        #expect(result.sources == sources)
        #expect(result.polynomials == expected)
        #expect(usage.visits == 0 && usage.coefficientVisits == 0)
        #expect(usage.work > 0 && usage.storage > 0)
        var work = Admission(); work.maximumWork = 0
        #expect(throws: KernelError.self) {
            try ExactIntersectionProjection.prepare(sources: sources, variableCount: 2, axis: 1, usage: &work)
        }
        var storage = Admission(); storage.maximumStorage = 0
        #expect(throws: KernelError.self) {
            try ExactIntersectionProjection.prepare(sources: sources, variableCount: 2, axis: 1, usage: &storage)
        }
        #expect(throws: KernelError.self) {
            try ExactIntersectionProjection.prepare(sources: sources, variableCount: 3, axis: 1, usage: &construction)
        }
    }

    private func rootFixture(coefficient: Bool = false, usage: inout Admission) throws
        -> (OriginalSingularFieldRoot, OriginalSingularFieldElement,
            OriginalSingularFieldPolynomial, OriginalSingularFieldPolynomial, OriginalSingularFieldPolynomial) {
        let parent = try OriginalSingularFieldContext(usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: parent, maximumDepth: 32, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: parent, maximumDepth: 32, usage: &usage)
        let minusTwo = try OriginalSingularFieldElement.constant(.natural(2, usage: &usage).negated,
            in: parent, maximumDepth: 32, usage: &usage)
        let law = try OriginalSingularFieldPolynomial(context: parent,
            coefficients: [minusTwo, zero, one], maximumDepth: 32, usage: &usage)
        let root = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .one, upper: try .natural(2, usage: &usage),
                excludesLower: false, excludesUpper: false, depth: 5),
            admissionDomain: coefficient ? .coefficient(maximumDepth: 32) : .parameter)
        let value = try root.value(maximumDepth: 32, usage: &usage)
        guard case .extended(let coordinate, let unit) = value.storage else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "The original quadratic fixture lost its retained extension storage.")
        }
        let negativeUnit = try unit.negated(maximumDepth: 32, usage: &usage)
        return (root, value, coordinate, unit, negativeUnit)
    }

    @Test func rationalOperandUsesOnlyTheNecessaryOriginalRootVisits() throws {
        var preparation = Admission()
        let (root, value, coordinate, unit, negativeUnit) = try rootFixture(usage: &preparation)
        var reference = Admission()
        #expect(try root.sign(of: coordinate, maximumDepth: 32, usage: &reference) == .positive)
        #expect(reference.visits > 0)
        for (numerator, denominator, expected) in [
            (coordinate, unit, ExactAlgebraicRealRoot.Sign.positive),
            (unit, coordinate, .positive), (negativeUnit, coordinate, .negative),
            (coordinate, negativeUnit, .negative)
        ] {
            var usage = Admission(); usage.maximumVisits = reference.visits
            let fraction = OriginalSingularFieldElement(context: value.context,
                storage: .extended(numerator, denominator))
            #expect(try fraction.sign(maximumDepth: 32, usage: &usage) == expected)
            #expect(usage.visits == reference.visits && usage.coefficientVisits == 0)
        }
        var depth = Admission(); depth.maximumDepth = 4
        #expect(throws: KernelError.self) { try value.sign(maximumDepth: 4, usage: &depth) }
        var cells = Admission(); cells.maximumVisits = 0
        #expect(throws: KernelError.self) { try value.sign(maximumDepth: 32, usage: &cells) }
        var work = Admission(); work.maximumWork = 0
        #expect(throws: KernelError.self) { try value.sign(maximumDepth: 32, usage: &work) }
        let (_, coefficientValue, _, _, _) = try rootFixture(coefficient: true, usage: &preparation)
        var coefficient = Admission(); coefficient.maximumCoefficientDepth = 4
        #expect(throws: KernelError.self) { try coefficientValue.sign(maximumDepth: 0, usage: &coefficient) }
        #expect(coefficient.visits == 0)
    }

    @Test func denominatorAndParentAuthorityRemainMandatory() throws {
        var usage = Admission()
        let (root, value, coordinate, unit, _) = try rootFixture(usage: &usage)
        let rootZeroDenominator = OriginalSingularFieldElement(context: value.context,
            storage: .extended(unit, root.polynomial))
        #expect(throws: KernelError.self) { try rootZeroDenominator.sign(maximumDepth: 32, usage: &usage) }
        let zero = try OriginalSingularFieldPolynomial(context: unit.context,
            coefficients: [], maximumDepth: 32, usage: &usage)
        let invalid = OriginalSingularFieldElement(context: value.context, storage: .extended(coordinate, zero))
        #expect(throws: KernelError.self) { try invalid.sign(maximumDepth: 32, usage: &usage) }
        let foreign = try OriginalSingularFieldContext(usage: &usage)
        let foreignUnit = try OriginalSingularFieldPolynomial(context: foreign,
            coefficients: [.constant(.one, in: foreign, maximumDepth: 32, usage: &usage)],
            maximumDepth: 32, usage: &usage)
        let unrelated = OriginalSingularFieldElement(context: value.context, storage: .extended(coordinate, foreignUnit))
        var query = Admission(); query.maximumVisits = 0
        #expect(throws: KernelError.self) { try unrelated.sign(maximumDepth: 32, usage: &query) }
        #expect(query.visits == 0 && query.work == 0)
    }

    @Test(arguments: [false, true])
    func rationalLeadingClosureKeepsOriginalZerosAndBothDomainEnds(negativeLeading: Bool) throws {
        var usage = Admission()
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let leading = negativeLeading ? two.negated : two
        let law = try y.subtracting(x, usage: &usage).scaled(by: leading, usage: &usage)
        let interval = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let fixed = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law, z], variableCount: 3,
            exactDomains: [interval, interval, fixed], thomEncoding: true, maximumDepth: 32, usage: &usage)
        let interior = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let closure = try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
            allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 32, usage: &usage)
        guard case .quantified(let proof) = closure.proof else {
            Issue.record("The rational leading-coefficient fixture must execute the original quantified closure."); return
        }
        let reduction = try #require(closure.predicateReduction)
        guard case .rationalLeadingCoefficient(let retained) = reduction.authority else {
            Issue.record("A rational leading coefficient was incorrectly issued as a source guard."); return
        }
        let selectedLaw = closure.originalPredicates[reduction.equationIndex]
        let selectedLeading = try #require(try selectedLaw.axisCoefficients(at: 5, usage: &usage).last)
        #expect(retained == (try #require(try selectedLeading.leading(usage: &usage)).coefficient))
        #expect(reduction.candidateCoordinate == 5)
        #expect(closure.candidateCoordinateMap == [4, 5, 2])
        #expect(proof.tower.variableCount == 5)
        #expect(closure.originalPredicates[reduction.equationIndex] ==
            (try closure.source.polynomials[reduction.equationIndex]
                .remapped(to: 6, coordinates: [4, 5, 2], usage: &usage)))
        #expect(closure.originalPredicates.contains(try law.remapped(to: 6, coordinates: [4, 5, 2], usage: &usage)))
        let retainedZero = try #require(closure.source.polynomials.firstIndex(of: z))
        #expect(closure.source.signs[retainedZero] == .zero)
        #expect(!proof.tower.levels[0].sources[retainedZero].isZero)
        var lowerEnd = false, upperEnd = false
        for index in closure.includedCells {
            let cell = closure.freePartition.cells[index]
            let field = try OriginalIntersectionFieldEvaluation.evaluated(law, context: cell.context,
                coordinates: cell.coordinates, maximumDepth: 32, usage: &usage)
            #expect(try field.sign(maximumDepth: 32, usage: &usage) == .zero)
            #expect(try cell.coordinates[2].sign(maximumDepth: 32, usage: &usage) == .zero)
            if cell.dimension == 0, let value = try cell.coordinates[0].rationalValue(usage: &usage) {
                lowerEnd = lowerEnd || value == .zero
                upperEnd = upperEnd || value == .one
            }
        }
        #expect(lowerEnd && upperEnd)
        // Reverse candidate order to exercise both signs of the very same
        // issued original equation, without replacing its source authority.
        let permutation = negativeLeading ? [0, 1, 2, 3, 5, 4] : [0, 1, 2, 3, 4, 5]
        let candidateMap = negativeLeading ? [5, 4, 2] : [4, 5, 2]
        var original: [ExactIntersectionPolynomial] = []
        for polynomial in closure.originalPredicates {
            original.append(try polynomial.remapped(to: 6, coordinates: permutation, usage: &usage))
        }
        var generators: [ExactIntersectionPolynomial] = []
        for equation in try #require(closure.predicateIdeal).originalEquations {
            generators.append(try equation.remapped(to: 6, coordinates: permutation, usage: &usage))
        }
        let ideal = try ExactIntersectionIdeal.prepare(equations: generators, variableCount: 6, usage: &usage)
        var reduced = original
        let oriented = try #require(try OriginalPositiveGuardPolynomialReduction.prepare(polynomials: &reduced,
            original: original, source: closure.source, candidateCoordinates: candidateMap, candidateCoordinate: 5,
            ideal: ideal, radiusIndex: closure.source.signs.count, usage: &usage))
        guard case .rationalLeadingCoefficient(let coefficient) = oriented.authority else {
            Issue.record("A rational coefficient must remain its own exact source authority."); return
        }
        #expect(coefficient.isNegative == negativeLeading)
        #expect(reduced.allSatisfy { $0.variableCount == 5 })
        #expect(!reduced[retainedZero].isZero)
        var foreign = original
        foreign[oriented.equationIndex] = try .coordinate(variableCount: 6, at: 5, usage: &usage)
        var invalid = foreign
        #expect(throws: KernelError.self) {
            try OriginalPositiveGuardPolynomialReduction.prepare(polynomials: &invalid,
                original: foreign, source: closure.source, candidateCoordinates: candidateMap, candidateCoordinate: 5,
                ideal: ideal, radiusIndex: closure.source.signs.count, usage: &usage)
        }
        var noWork = Admission(); noWork.maximumWork = 0
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
                allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 32, usage: &noWork)
        }
        var noStorage = Admission(); noStorage.maximumStorage = 0
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
                allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 32, usage: &noStorage)
        }
    }

    @Test(arguments: [false, true])
    func nonlinearOriginalLawPermutesOnlyExistentialCandidates(negativeLeading: Bool) async throws {
        var usage = Admission()
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let u = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let square = try u.multiplied(by: u, usage: &usage)
        let law = negativeLeading ? try square.subtracting(x, usage: &usage) :
            try square.adding(x, usage: &usage)
        let interval = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let xDomain = negativeLeading ? interval :
            try OriginalRationalParameterDomain(lower: .one.negated, upper: .zero, usage: &usage)
        let fixed = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law, z], variableCount: 3,
            exactDomains: [xDomain, interval, fixed], thomEncoding: true, maximumDepth: 32, usage: &usage)
        let interior = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let source = try OriginalIntersectionCellCondition(partition: partition, cellIndex: interior, usage: &usage)
        let candidateMap = [4, 5, 2], freeMap = [0, 1, 2]
        var original: [ExactIntersectionPolynomial] = []
        var generators: [ExactIntersectionPolynomial] = []
        for index in source.polynomials.indices {
            let candidate = try source.polynomials[index].remapped(to: 6, coordinates: candidateMap, usage: &usage)
            original.append(candidate)
            if source.signs[index] == .zero && !source.polynomials[index].isZero {
                generators.append(candidate)
                generators.append(try source.polynomials[index].remapped(to: 6, coordinates: freeMap, usage: &usage))
            }
        }
        let radius = try ExactIntersectionPolynomial.coordinate(variableCount: 6, at: 3, usage: &usage)
        original.append(radius)
        for axis in 0..<2 {
            let free = try ExactIntersectionPolynomial.coordinate(variableCount: 6, at: axis, usage: &usage)
            let candidate = try ExactIntersectionPolynomial.coordinate(variableCount: 6, at: candidateMap[axis], usage: &usage)
            let difference = try free.subtracting(candidate, usage: &usage)
            original.append(try radius.subtracting(difference, usage: &usage))
            original.append(try radius.adding(difference, usage: &usage))
        }
        // Include explicit closed candidate domain atoms in addition to the
        // retained original parent-path boundary witnesses.
        let candidateX = try ExactIntersectionPolynomial.coordinate(variableCount: 6, at: 4, usage: &usage)
        let candidateU = try ExactIntersectionPolynomial.coordinate(variableCount: 6, at: 5, usage: &usage)
        let one = try ExactIntersectionPolynomial.constant(variableCount: 6, value: .one, usage: &usage)
        original.append(candidateU)
        original.append(try one.subtracting(candidateU, usage: &usage))
        original.append(negativeLeading ? candidateX : try candidateX.adding(one, usage: &usage))
        original.append(negativeLeading ? try one.subtracting(candidateX, usage: &usage) :
            try candidateX.scaled(by: .one.negated, usage: &usage))
        let ideal = try ExactIntersectionIdeal.prepare(equations: generators, variableCount: 6, usage: &usage)
        let boundOriginal = original
        var reduced = original
        let reduction = try #require(try OriginalPositiveGuardPolynomialReduction.prepare(polynomials: &reduced,
            original: original, source: source, candidateCoordinates: candidateMap, candidateCoordinate: 5,
            ideal: ideal, radiusIndex: source.signs.count, usage: &usage))
        #expect(original == boundOriginal && ideal.originalEquations == generators)
        #expect(reduction.originalCandidateCoordinate == 4 && reduction.candidateCoordinate == 5)
        guard case .existentialSuffix(let forward, let inverse) = reduction.coordinateTransport else {
            Issue.record("The original nonlinear law did not retain its existential transport receipt."); return
        }
        #expect(forward == [0, 1, 2, 3, 5, 4] && inverse == [0, 1, 2, 3, 5, 4])
        for axis in forward.indices { #expect(inverse[forward[axis]] == axis) }
        #expect(reduced.allSatisfy { $0.variableCount == 5 })
        guard case .rationalLeadingCoefficient(let coefficient) = reduction.authority else {
            Issue.record("The transported original equation lost its rational coefficient authority."); return
        }
        #expect(coefficient.isNegative == negativeLeading)
        #expect(original[reduction.equationIndex] ==
            (try source.polynomials[reduction.equationIndex]
                .remapped(to: 6, coordinates: candidateMap, usage: &usage)))
        #expect(original.contains(try law.remapped(to: 6, coordinates: candidateMap, usage: &usage)))
        let retainedZero = try #require(source.polynomials.firstIndex(of: z))
        #expect(!reduced[retainedZero].isZero)
        let half = try ExactRationalCoefficient.one.divided(by: .natural(2, usage: &usage), usage: &usage)
        for candidateValue in [ExactRationalCoefficient.zero, half, .one] {
            let squareValue = try candidateValue.multiplied(by: candidateValue, usage: &usage)
            let xValue = negativeLeading ? squareValue : squareValue.negated
            for freeValue in [ExactRationalCoefficient.zero, .one] {
                for radiusValue in [ExactRationalCoefficient.one.negated, .zero, .one] {
                    let values: [ExactRationalCoefficient] = [freeValue, freeValue, .zero,
                        radiusValue, xValue, candidateValue]
                    var working = Array(repeating: ExactRationalCoefficient.zero, count: 6)
                    for axis in forward.indices { working[forward[axis]] = values[axis] }
                    let lowered = Array(working.prefix(5))
                    #expect(try original[reduction.equationIndex].evaluated(at: values, usage: &usage) == .zero)
                    // |A| is exactly one here: value equality also establishes
                    // every atom sign, including zero at both closed ends.
                    for index in original.indices {
                        #expect(try original[index].evaluated(at: values, usage: &usage) ==
                            reduced[index].evaluated(at: lowered, usage: &usage))
                    }
                }
            }
        }
        var foreign = original
        foreign[reduction.equationIndex] = try .coordinate(variableCount: 6, at: 4, usage: &usage)
        var invalid = foreign
        #expect(throws: KernelError.self) {
            try OriginalPositiveGuardPolynomialReduction.prepare(polynomials: &invalid, original: foreign,
                source: source, candidateCoordinates: [4, 5, 2], candidateCoordinate: 5,
                ideal: ideal, radiusIndex: source.signs.count, usage: &usage)
        }
        for storageRefusal in [false, true] {
            var bounded = Admission()
            if storageRefusal { bounded.maximumStorage = 0 } else { bounded.maximumWork = 0 }
            var predicates = original
            #expect(throws: KernelError.self) {
                try OriginalPositiveGuardPolynomialReduction.prepare(polynomials: &predicates,
                    original: original, source: source, candidateCoordinates: [4, 5, 2],
                    candidateCoordinate: 5, ideal: ideal, radiusIndex: source.signs.count, usage: &bounded)
            }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var cancelled = Admission(), predicates = original
            #expect(throws: CancellationError.self) {
                try OriginalPositiveGuardPolynomialReduction.prepare(polynomials: &predicates,
                    original: original, source: source, candidateCoordinates: [4, 5, 2],
                    candidateCoordinate: 5, ideal: ideal, radiusIndex: source.signs.count, usage: &cancelled)
            }
        }
        await task.value
    }

    private func nativeFoldPartition(usage: inout Admission) throws -> OriginalRationalIntersectionCells {
        let first = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [-1, -1, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [[.init(x: -1, y: -1, z: 0), .init(x: 1, y: -1, z: 0)],
                [.init(x: -1, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let second = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-1, -1, -1, 1, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [[.init(x: 1, y: -1, z: 0), .init(x: -1, y: -1, z: 0), .init(x: 1, y: -1, z: 0)],
                [.init(x: 1, y: 1, z: 0), .init(x: -1, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let box = SurfaceParameterBox(u: try .init(lower: -1, upper: 1), v: try .init(lower: -1, upper: 1))
        func original(_ surface: BSplineSurface3D) throws -> OriginalRationalSurfacePolynomial {
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard,
                consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
            let spans = try prepared.originalNativeSpans(over: box, tolerance: .standard, maximumSpanCount: 1,
                consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
            return try .init(source: surface, native: spans[0], domain: box, view: .init(x: 0, y: 0, z: 1),
                tolerance: .standard, usage: &usage)
        }
        let source = try original(first), target = try original(second)
        let system = try OriginalRationalIntersectionSystem(first: source, second: target, usage: &usage)
        let guarded = try OriginalGuardedIntersectionEquations.prepare(equations: system.equations,
            denominatorGuards: system.denominatorGuards, variableCount: 4, squareFreeRepeatedFactors: true,
            reducePureEvenPowerZeroSets: true, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: guarded.normalizedEquations, variableCount: 4, usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &usage)
        return try OriginalRationalIntersectionStrata.prepare(ideal: ideal, exactDomains: Array(repeating: domain, count: 4),
            nonzeroPolynomials: system.denominatorGuards, thomEncoding: true, originalRankEquations: guarded.originalEquations,
            maximumDepth: 32, usage: &usage).partition
    }

    @Test func originalNativeFoldHasAffineBasesAndUniqueClosedSheetFibers() async throws {
        var usage = Admission()
        let partition = try nativeFoldPartition(usage: &usage)
        var sheets: [(sign: ExactAlgebraicRealRoot.Sign, base: Int, cells: [Int])] = []
        let branches = partition.solutionCells.filter { partition.cells[$0].dimension == 2 }
        #expect(branches.count == 4)
        for index in branches {
            let proof = try #require(try OriginalFiniteBranchClosure.prepare(partition: partition,
                cellIndex: index, maximumDepth: 32, usage: &usage))
            let prefix = try #require(proof.affinePrefix)
            #expect(proof.freeAxis == 1 && prefix.baseAxis == 1 && prefix.sourcePath.count == 4)
            #expect(proof.sectionWitnesses.count == 2)
            #expect(proof.includedCells.count == 9 && prefix.fibers.count == 9)
            for axis in 0...prefix.baseAxis {
                for polynomial in partition.tower.levels[3 - axis].sources {
                    for term in try polynomial.orderedTerms(usage: &usage) {
                        var degree = 0
                        for coordinate in 0..<4 { degree += try term.key.exponent(at: coordinate) }
                        #expect(degree <= 1)
                    }
                }
            }
            let branchSign = try partition.cells[index].coordinates[2].sign(maximumDepth: 32, usage: &usage)
            #expect(branchSign != .zero)
            var corners = 0, edges = 0, interior = 0
            for fiber in prefix.fibers {
                let cell = partition.cells[fiber.fullCell], base = partition.cells[fiber.baseCell]
                #expect(cell.dimension == base.dimension && proof.includedCells.contains(fiber.fullCell))
                if cell.dimension == 0 { corners += 1 }
                if cell.dimension == 1 { edges += 1 }
                if cell.dimension == 2 { interior += 1 }
                let x = cell.coordinates[0], y = cell.coordinates[1], z = cell.coordinates[2], w = cell.coordinates[3]
                #expect(try z.multiplied(by: z, maximumDepth: 32, usage: &usage)
                    .subtracting(x, maximumDepth: 32, usage: &usage).sign(maximumDepth: 32, usage: &usage) == .zero)
                #expect(try w.subtracting(y, maximumDepth: 32, usage: &usage).sign(maximumDepth: 32, usage: &usage) == .zero)
                let sign = try z.sign(maximumDepth: 32, usage: &usage)
                #expect(sign == .zero || sign == branchSign)
            }
            #expect(corners == 4 && edges == 4 && interior == 1)
            sheets.append((branchSign, prefix.sourcePath[1], proof.includedCells))
        }
        for positive in sheets where positive.sign == .positive {
            let negative = try #require(sheets.first { $0.sign == .negative && $0.base == positive.base })
            let shared = positive.cells.filter { negative.cells.contains($0) }
            #expect(shared.count == 3)
            for index in shared {
                #expect(try partition.cells[index].coordinates[0].sign(maximumDepth: 32, usage: &usage) == .zero)
                #expect(try partition.cells[index].coordinates[2].sign(maximumDepth: 32, usage: &usage) == .zero)
            }
        }
        let source = try #require(branches.first)
        for storageRefusal in [false, true] {
            var bounded = Admission()
            if storageRefusal { bounded.maximumStorage = 0 } else { bounded.maximumWork = 0 }
            #expect(throws: KernelError.self) {
                try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: source,
                    maximumDepth: 32, usage: &bounded)
            }
        }
        var depth = Admission()
        #expect(throws: KernelError.self) {
            try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: source, maximumDepth: 0, usage: &depth)
        }
        #expect(throws: KernelError.self) {
            try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: -1, maximumDepth: 32, usage: &usage)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var cancelled = Admission()
            #expect(throws: CancellationError.self) {
                try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: source,
                    maximumDepth: 32, usage: &cancelled)
            }
        }
        await task.value
        var pruning = Admission()
        let pruned = try OriginalRationalIntersectionCells.prepare(equations: partition.equations, variableCount: 4,
            exactDomains: partition.domains, partitionPolynomials: partition.partitionPolynomials,
            nonzeroPolynomials: partition.nonzeroPolynomials, thomEncoding: true, pruneDomainPrefixes: true,
            maximumDepth: 32, usage: &pruning)
        #expect(!pruned.excludedDomainPrefixes.isEmpty)
        for index in pruned.solutionCells where pruned.cells[index].dimension == 2 {
            let proof = try #require(try OriginalFiniteBranchClosure.prepare(partition: pruned,
                cellIndex: index, maximumDepth: 32, usage: &pruning))
            #expect(proof.includedCells.count == 9)
        }
    }

    @Test func unsupportedAffineGraphFibersNeverIssuePartialClosure() throws {
        var usage = Admission()
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 4, at: 0, usage: &usage)
        let y = try ExactIntersectionPolynomial.coordinate(variableCount: 4, at: 1, usage: &usage)
        let w = try ExactIntersectionPolynomial.coordinate(variableCount: 4, at: 2, usage: &usage)
        let z = try ExactIntersectionPolynomial.coordinate(variableCount: 4, at: 3, usage: &usage)
        let one = try ExactIntersectionPolynomial.constant(variableCount: 4, value: .one, usage: &usage)
        let interval = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let unbounded = try OriginalRationalParameterDomain(lower: nil, upper: nil, usage: &usage)
        let pole = try x.multiplied(by: z, usage: &usage).subtracting(one, usage: &usage)
        let split = try x.multiplied(by: z.multiplied(by: z, usage: &usage).subtracting(one, usage: &usage), usage: &usage)
        for law in [pole, split] {
            let partition = try OriginalRationalIntersectionCells.prepare(equations: [w, law], variableCount: 4,
                exactDomains: [interval, interval, unbounded, unbounded], thomEncoding: true, maximumDepth: 32, usage: &usage)
            var selected: Int?
            for index in partition.solutionCells where partition.cells[index].dimension == 2 {
                if try partition.cells[index].coordinates[0].sign(maximumDepth: 32, usage: &usage) == .positive {
                    selected = index; break
                }
            }
            let source = try #require(selected)
            #expect(try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: source,
                maximumDepth: 32, usage: &usage) == nil)
            // The pole has no finite fiber at x=0; the split has an entire
            // z sector there. Neither supports a unique bounded section graph.
            var boundary: [Int] = []
            for index in partition.solutionCells {
                if try partition.cells[index].coordinates[0].rationalValue(usage: &usage) == .zero,
                    case .sector = partition.cells[index].kind { boundary.append(index) }
            }
            if law == split { #expect(!boundary.isEmpty) } else { #expect(boundary.isEmpty) }
        }
        let graph = try z.multiplied(by: z, usage: &usage).subtracting(x, usage: &usage)
        let circle = try x.multiplied(by: x, usage: &usage)
            .adding(y.multiplied(by: y, usage: &usage), usage: &usage).subtracting(one, usage: &usage)
        let nonlinear = try OriginalRationalIntersectionCells.prepare(equations: [w, graph], variableCount: 4,
            exactDomains: [interval, interval, unbounded, unbounded], partitionPolynomials: [circle],
            thomEncoding: true, maximumDepth: 32, usage: &usage)
        for index in nonlinear.solutionCells where nonlinear.cells[index].dimension == 2 {
            #expect(try OriginalFiniteBranchClosure.prepare(partition: nonlinear, cellIndex: index,
                maximumDepth: 32, usage: &usage) == nil)
        }
    }

    @Test func cancellationPropagatesThroughBothChangedPaths() async throws {
        var preparation = Admission()
        let (_, value, _, _, _) = try rootFixture(usage: &preparation)
        let law = try ExactIntersectionPolynomial.coordinate(variableCount: 2, at: 0, usage: &preparation)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var usage = Admission()
            #expect(throws: CancellationError.self) { try value.sign(maximumDepth: 32, usage: &usage) }
            #expect(throws: CancellationError.self) {
                try ExactIntersectionProjection.prepare(sources: [law], variableCount: 2, axis: 1, usage: &usage)
            }
        }
        await task.value
    }
}
