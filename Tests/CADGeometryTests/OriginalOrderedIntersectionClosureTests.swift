import CADCore
@testable import CADGeometry
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OriginalOrderedIntersectionClosureTests {
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var work = 0, storage = 0
        var maximumWork = 20_000_000, maximumStorage = 20_000_000
        var maximumParameterDepth = 24, maximumCoefficientDepth = 24
        var coefficientVisits = 0, coefficientDepth = 0
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw failure("work") }; work += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            guard count >= 0, count <= maximumStorage - storage else { throw failure("storage") }; storage += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
        
        private func failure(_ domain: String) -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original ordered-closure test exhausted \(domain), work \(work), storage \(storage).")
        }
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value

            guard depth >= 0, depth <= maximumParameterDepth else { throw failure("parameter depth") }
        
                case .coefficient:
                    let depth = mapped.coefficient

            guard depth >= 0, depth <= maximumCoefficientDepth else { throw failure("coefficient depth") }
            coefficientVisits += 1; coefficientDepth = max(coefficientDepth, depth)
        
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        var maximumTestValueDepth: Int { maximumParameterDepth }
    }

    private func source(region: Bool, usage: inout Admission) throws -> OriginalOrderedIntersectionCells {
        let rational = try OriginalSingularFieldContext(usage: &usage)
        let root = try OriginalSingularFieldElement.constant(.natural(2, usage: &usage), in: rational,
            maximumDepth: 0, usage: &usage).nonnegativeSquareRoot(inheritedDepth: 0,
                maximumDepth: 24, admissionDomain: .coefficient(maximumDepth: 24), usage: &usage)
        let count = region ? 2 : 1
        var terms: [OriginalOrderedIntersectionPolynomial.Term] = []
        if !region {
            let one = try OriginalSingularFieldElement.constant(.one, in: root.context, maximumDepth: 24, usage: &usage)
            terms.append(.init(power: try .init([1], variableCount: 1, usage: &usage), coefficient: one))
        }
        let coefficient = region ? root : try root.negated(maximumDepth: 24, usage: &usage)
        terms.append(.init(power: try .init(Array(repeating: 0, count: count), variableCount: count, usage: &usage), coefficient: coefficient))
        let polynomial = try OriginalOrderedIntersectionPolynomial(variableCount: count, terms: terms,
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let predicate = try ExactIntersectionBooleanProgram(polynomialCount: 1,
            instructions: region ? [.literal(true)] : [.atom(0, .positive)], usage: &usage)
        let domain = try OriginalRationalParameterDomain(nil, usage: &usage)
        return try OriginalOrderedIntersectionCells.prepare(polynomials: [polynomial], predicate: predicate,
            variableCount: count, domains: Array(repeating: domain, count: count), maximumDepth: 24,
            maximumCoefficientDepth: 24, usage: &usage)
    }

    @Test func affineRegionClosurePreservesExactlyItsOriginalCoefficientPrefix() throws {
        var usage = Admission()
        let original = try source(region: true, usage: &usage)
        let index = try #require(original.partition.solutionCells.first)
        let closure = try OriginalIntersectionCellClosure.prepare(partition: original.partition,
            cellIndex: index, maximumDepth: 24, usage: &usage)
        guard case .affineCell = closure.proof else { Issue.record("Fixed-fiber affine theorem was not selected."); return }
        #expect(closure.includedCells == [index])
        #expect(closure.source.fixedCoefficientCellIndex != nil)
        #expect(original.partition.cells[index].dimension == 2)
        #expect(try OriginalRationalIntersectionIncidence.prepare(partition: original.partition,
            maximumDepth: 24, usage: &usage).connectedComponents(usage: &usage).components.count == 1)
    }

    @Test(arguments: [false, true])
    func actualQuantifiedClosureSharesCoefficientsAndIncludesEveryOriginalBoundary(region: Bool) throws {
        var usage = Admission()
        let original = try source(region: region, usage: &usage)
        let index = try #require(original.partition.solutionCells.first)
        let before = usage.coefficientVisits
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: original.partition,
            allowAffineClosureProofs: false, allowFiniteBranchClosureProofs: false,
            maximumDepth: 24, usage: &usage)
        let closure = try #require(incidence.closures.first)
        guard case .quantified(let proof) = closure.proof else {
            Issue.record("Forced original ordered closure did not execute its quantified path."); return
        }
        #expect(proof.coefficientVariableCount == 1)
        #expect(proof.maximumCoefficientDepth == 24)
        #expect(proof.tower.variableCount == 1 + 2 * original.geometricVariableCount + 1)
        #expect(proof.quantifiers.count == original.geometricVariableCount + 1)
        #expect(usage.coefficientVisits > before)
        var boundary = false, interior = false
        for truth in proof.freeCells {
            let cell = closure.freePartition.cells[truth.cellIndex]
            let coefficientSign = try cell.coordinates[0].sign(maximumDepth: 24, usage: &usage)
            var expected = region ? coefficientSign == .positive : coefficientSign == .negative
            if !region {
                let side = try cell.coordinates[1].adding(cell.coordinates[0], maximumDepth: 24, usage: &usage)
                    .sign(maximumDepth: 24, usage: &usage)
                expected = expected && side != .negative
                if truth.value && side == .zero { boundary = true }
                if truth.value && side == .positive { interior = true }
            }
            #expect(truth.value == expected)
            #expect(cell.coefficientAdmissionDepth >= original.partition.cells[index].coefficientAdmissionDepth)
        }
        #expect(!proof.freeCells.isEmpty)
        #expect(try incidence.connectedComponents(usage: &usage).components.count == 1)
        if region {
            #expect(incidence.attachments.count == closure.includedCells.count)
            #expect(incidence.attachments.allSatisfy { $0.targetCellIndex == index })
            #expect(closure.includedCells.contains { closure.freePartition.cells[$0].dimension == 2 })
        }
        else { #expect(boundary && interior) }
    }

    @Test func generalClosureRejectsIndependentLimitExhaustionBeforePublication() throws {
        var preparation = Admission()
        let original = try source(region: false, usage: &preparation)
        let index = try #require(original.partition.solutionCells.first)
        var coefficient = Admission(); coefficient.maximumCoefficientDepth = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalIntersectionCellClosure.prepare(partition: original.partition, cellIndex: index,
                allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &coefficient)
        }
        var parameter = Admission(); parameter.maximumParameterDepth = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalIntersectionCellClosure.prepare(partition: original.partition, cellIndex: index,
                allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &parameter)
        }
        var storage = Admission(); storage.maximumStorage = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalIntersectionCellClosure.prepare(partition: original.partition, cellIndex: index,
                allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &storage)
        }
        var work = Admission(); work.maximumWork = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalIntersectionCellClosure.prepare(partition: original.partition, cellIndex: index,
                allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &work)
        }
    }

    @Test func anUnfixedCoefficientSectorCannotIssueGeometricClosure() throws {
        var usage = Admission()
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 2,
            domains: [nil, nil], thomEncoding: true, coefficientVariableCount: 1,
            maximumCoefficientDepth: 24, maximumDepth: 24, usage: &usage)
        let index = try #require(partition.solutionCells.first)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: index, maximumDepth: 24, usage: &usage)
        }
    }
}
