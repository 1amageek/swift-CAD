import CADCore
@testable import CADGeometry
import Testing

@Suite("Complete rational real intersection cells")
struct RationalIntersectionCellTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var work = 0, storage = 0, cells = 0
        var maximumWork = 10_000_000, maximumStorage = 10_000_000
        var maximumCells = 100_000, maximumDepth = 24
        var cancelAtFirstCell = false
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw exhausted() }; work += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            guard count >= 0, count <= maximumStorage - storage else { throw exhausted() }; storage += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
        
        private func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                  message: "Real-cell test allowance exhausted: work=\(work), storage=\(storage), cells=\(cells).")
        }
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value

            guard depth >= 0, depth <= maximumDepth, cells < maximumCells else { throw exhausted() }
            cells += 1
            if cancelAtFirstCell { withUnsafeCurrentTask { $0?.cancel() } }
        
                case .coefficient:
                    let depth = mapped.coefficient

            throw rationalAlgebraFailure("Original rational cells cannot invent coefficient extensions.")
        
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func positiveComplexDimensionCanHaveOneRealPointOrNoRealPoint() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let squares = try x.multiplied(by: x, usage: &usage).adding(y.multiplied(by: y, usage: &usage), usage: &usage)
        let point = try OriginalRationalIntersectionCells.prepare(equations: [squares], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(point.solutionCells.count == 1)
        let origin = point.cells[try #require(point.solutionCells.first)]
        #expect(origin.dimension == 0 && origin.signs == [.zero])
        for value in origin.coordinates { #expect(try value.sign(maximumDepth: 24, usage: &usage) == .zero) }
        let one = try Polynomial.constant(variableCount: 2, value: .one, usage: &usage)
        let absent = try OriginalRationalIntersectionCells.prepare(equations: [squares.adding(one, usage: &usage)],
            variableCount: 2, domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(absent.solutionCells.isEmpty)
        #expect(absent.cells.count == 2 && absent.stacks.count == 2)
        #expect(absent.cells.last?.dimension == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func parabolaIncludesBothOpenBranchesAndTheirCriticalPoint() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let equation = try y.multiplied(by: y, usage: &usage).subtracting(x, usage: &usage)
        let result = try OriginalRationalIntersectionCells.prepare(equations: [equation], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(result.solutionCells.count == 3)
        var points = 0, curves = 0
        for index in result.solutionCells {
            let cell = result.cells[index]
            #expect(cell.signs == [.zero])
            if cell.dimension == 0 { points += 1 } else if cell.dimension == 1 { curves += 1 }
            let value = try OriginalIntersectionFieldEvaluation.evaluated(equation, context: cell.context,
                coordinates: cell.coordinates, maximumDepth: 24, usage: &usage)
            #expect(try value.sign(maximumDepth: 24, usage: &usage) == .zero)
        }
        #expect(points == 1 && curves == 2)
        for (index, stack) in result.stacks.enumerated() {
            #expect(stack.children.count == 2 * stack.roots.count + 1)
            #expect(stack.children.allSatisfy { result.cells[$0].stackIndex == index })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nullifiedFiberIsAWholeRealLineAndRepeatedRootsRemainDistinctCells() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let product = try x.multiplied(by: y, usage: &usage)
        let axes = try OriginalRationalIntersectionCells.prepare(equations: [product], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(axes.solutionCells.count == 3)
        #expect(axes.solutionCells.allSatisfy { axes.cells[$0].dimension == 1 })
        let nullified = try geometryTestRequire(axes.stacks.first { $0.axis == 1 && $0.sourceDegrees == [-1] })
        #expect(nullified.roots.isEmpty && nullified.children.count == 1)
        let square = try y.multiplied(by: y, usage: &usage)
        let repeated = try OriginalRationalIntersectionCells.prepare(equations: [square], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(repeated.solutionCells.count == 1)
        #expect(repeated.cells[try #require(repeated.solutionCells.first)].dimension == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func wholeSpaceAndExactClosedDomainsAreSelectedByWholeCellSigns() throws {
        var usage = Admission()
        let all = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(all.solutionCells.count == 1 && all.cells[1].dimension == 2)
        let domains: [ScalarInterval?] = [try .init(lower: 1, upper: 1), try .init(lower: -2, upper: 2)]
        let restricted = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 2,
            domains: domains, maximumDepth: 24, usage: &usage)
        #expect(restricted.solutionCells.count == 3)
        #expect(restricted.solutionCells.map { restricted.cells[$0].dimension }.sorted() == [0, 0, 1])
        for index in restricted.solutionCells {
            let cell = restricted.cells[index]
            #expect(cell.signs[0] == .zero && cell.signs[1] == .zero)
            #expect(cell.signs[2] != .negative && cell.signs[3] != .positive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func irrationalCellsRetainEveryLiftUnderOriginalFieldIdentity() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let two = try Polynomial.constant(variableCount: 2, value: .natural(2, usage: &usage), usage: &usage)
        let equations = try [x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage),
            y.multiplied(by: y, usage: &usage).subtracting(x, usage: &usage)]
        let result = try OriginalRationalIntersectionCells.prepare(equations: equations, variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(result.solutionCells.count == 2)
        var signs: [ExactAlgebraicRealRoot.Sign] = []
        for index in result.solutionCells {
            let cell = result.cells[index]
            #expect(cell.dimension == 0 && cell.signs == [.zero, .zero])
            #expect(try cell.coordinates[0].sign(maximumDepth: 24, usage: &usage) == .positive)
            signs.append(try cell.coordinates[1].sign(maximumDepth: 24, usage: &usage))
        }
        #expect(signs.contains(.positive) && signs.contains(.negative))
    }

    @Test(.timeLimit(.minutes(1)))
    func neighboringDoubleEndpointDoesNotBecomeIntersectionOrRequireBisectionOfKnownLinearRoots() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &usage)
        let source = try x.subtracting(one, usage: &usage)
        let included = try OriginalRationalIntersectionCells.prepare(equations: [source], variableCount: 1,
            domains: [try .init(lower: 1, upper: 1)], maximumDepth: 24, usage: &usage)
        #expect(included.solutionCells.count == 1)
        let excluded = try OriginalRationalIntersectionCells.prepare(equations: [source], variableCount: 1,
            domains: [try .init(lower: Double(1).nextUp, upper: 2)], maximumDepth: 24, usage: &usage)
        #expect(excluded.solutionCells.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactRationalSectorSamplesDoNotResetInheritedRootRefinementDepth() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let two = try Polynomial.constant(variableCount: 2, value: .natural(2, usage: &usage), usage: &usage)
        let source = try x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage)
        let result = try OriginalRationalIntersectionCells.prepare(equations: [source], variableCount: 2,
            domains: [try .init(lower: -1, upper: 1), nil], maximumDepth: 24, usage: &usage)
        var inheritedRationalSamples = 0
        for stack in result.stacks {
            if let parent = stack.parentCell {
                for index in stack.children {
                    #expect(result.cells[index].admissionDepth >= result.cells[parent].admissionDepth)
                }
            }
            if stack.axis == 0 {
                for index in stack.children {
                    let cell = result.cells[index]
                    // Known linear sections have exact point isolations at depth zero.
                    // Rational sector samples must retain the refinements of their bounding irrational roots.
                    if case .sector = cell.kind, cell.context.depth == 0, cell.admissionDepth > 0 {
                        inheritedRationalSamples += 1
                    }
                }
            }
        }
        #expect(inheritedRationalSamples > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func overlappingOriginalRootBracketsAreNotAnEqualityPredicate() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let square = try x.multiplied(by: x, usage: &usage)
        let two = try Polynomial.constant(variableCount: 1, value: .natural(2, usage: &usage), usage: &usage)
        let three = try Polynomial.constant(variableCount: 1, value: .natural(3, usage: &usage), usage: &usage)
        let distinct = try OriginalRationalIntersectionCells.prepare(
            equations: [square.subtracting(two, usage: &usage), square.subtracting(three, usage: &usage)],
            variableCount: 1, domains: [nil], maximumDepth: 24, usage: &usage)
        #expect(distinct.stacks[0].roots.count == 4 && distinct.solutionCells.isEmpty)
        let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &usage)
        let shared = try OriginalRationalIntersectionCells.prepare(
            equations: [square.subtracting(one, usage: &usage), x.subtracting(one, usage: &usage)],
            variableCount: 1, domains: [nil], maximumDepth: 24, usage: &usage)
        #expect(shared.stacks[0].roots.count == 2 && shared.solutionCells.count == 1)
        let retained = shared.cells[try #require(shared.solutionCells.first)]
        #expect(retained.signs == [.zero, .zero] && retained.dimension == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalFieldSubstitutionRejectsUnrelatedOwnersEvenForZeroEquations() throws {
        var usage = Admission()
        let first = try OriginalSingularFieldContext(usage: &usage)
        let second = try OriginalSingularFieldContext(usage: &usage)
        let coordinate = try OriginalSingularFieldElement.constant(.zero, in: first,
            maximumDepth: 24, usage: &usage)
        let zero = try Polynomial.zero(variableCount: 1)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalIntersectionFieldEvaluation.evaluated(zero, context: second,
                coordinates: [coordinate], maximumDepth: 24, usage: &usage)
        }
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalIntersectionFieldEvaluation.power(coordinate, exponent: -1,
                maximumDepth: 24, usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cellWorkStorageAndDepthFailuresCannotPublishPartialCoverage() throws {
        var usage = Admission()
        let source = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        // Independent refusals retain observed counters, not another admission's proof scopes.
        let observed = (work: usage.work, storage: usage.storage, cells: usage.cells,
            maximumWork: usage.maximumWork, maximumStorage: usage.maximumStorage,
            maximumCells: usage.maximumCells, maximumDepth: usage.maximumDepth,
            cancelAtFirstCell: usage.cancelAtFirstCell)
        var cells = Admission(work: observed.work, storage: observed.storage, cells: observed.cells,
            maximumWork: observed.maximumWork, maximumStorage: observed.maximumStorage,
            maximumCells: 0, maximumDepth: observed.maximumDepth,
            cancelAtFirstCell: observed.cancelAtFirstCell)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
                domains: [nil], maximumDepth: 24, usage: &cells)
        }
        #expect(cells.work > observed.work && cells.cells == 0)
        var work = Admission(work: observed.work, storage: observed.storage, cells: observed.cells,
            maximumWork: observed.work, maximumStorage: observed.maximumStorage,
            maximumCells: observed.maximumCells, maximumDepth: observed.maximumDepth,
            cancelAtFirstCell: observed.cancelAtFirstCell)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalRationalIntersectionCells.prepare(equations: [source], variableCount: 1,
                domains: [nil], maximumDepth: 24, usage: &work)
        }
        var storage = Admission(work: observed.work, storage: observed.storage, cells: observed.cells,
            maximumWork: observed.maximumWork, maximumStorage: observed.storage,
            maximumCells: observed.maximumCells, maximumDepth: observed.maximumDepth,
            cancelAtFirstCell: observed.cancelAtFirstCell)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalRationalIntersectionCells.prepare(equations: [source], variableCount: 1,
                domains: [nil], maximumDepth: 24, usage: &storage)
        }
        var depth = Admission(work: observed.work, storage: observed.storage, cells: observed.cells,
            maximumWork: observed.maximumWork, maximumStorage: observed.maximumStorage,
            maximumCells: observed.maximumCells, maximumDepth: 0,
            cancelAtFirstCell: observed.cancelAtFirstCell)
        let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &depth)
        let twoRoots = try source.multiplied(by: source, usage: &depth).subtracting(one, usage: &depth)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalRationalIntersectionCells.prepare(equations: [twoRoots], variableCount: 1,
                domains: [nil], maximumDepth: 0, usage: &depth)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationWithinFirstStackRestoresTheChargedOriginalLedger() async throws {
        let visits = try await Task { () throws -> Int in
            var usage = Admission(); usage.cancelAtFirstCell = true
            do {
                _ = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
                    domains: [nil], maximumDepth: 24, usage: &usage)
                Issue.record("Cancelled real-cell lifting cannot return a complete cover.")
            } catch let error where geometryTestIsCancelled(error) { return usage.cells }
            return -1
        }.value
        #expect(visits == 1)
    }
}
