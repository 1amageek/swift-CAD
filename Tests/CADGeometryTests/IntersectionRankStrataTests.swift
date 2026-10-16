import CADCore
@testable import CADGeometry
import Testing

@Suite("Original rational intersection rank strata")
struct IntersectionRankStrataTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var work = 0, storage = 0, cells = 0
        var maximumWork = 10_000_000, maximumStorage = 10_000_000
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
                  message: "Original rank test caller exhausted its independent allowance.")
        }
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value

            guard depth >= 0, depth <= 24, cells < 100_000 else { throw exhausted() }; cells += 1
        
                case .coefficient:
                    let depth = mapped.coefficient

            throw rationalAlgebraFailure("Rational rank witnesses cannot create coefficient roots.")
        
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func indexedHigherMinorsPreserveOriginalJacobianRowsAndColumns() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let product = try x.multiplied(by: y, usage: &usage)
        let jacobian = try ExactIntersectionJacobian.prepare(equations: [product, z], variableCount: 3, usage: &usage)
        #expect(jacobian.minors.count == 9)
        #expect(jacobian.entries[0] == [y, x, try .zero(variableCount: 3)])
        let yz = try geometryTestRequire(jacobian.minors.first { $0.rows == [0, 1] && $0.columns == [0, 2] })
        let xz = try geometryTestRequire(jacobian.minors.first { $0.rows == [0, 1] && $0.columns == [1, 2] })
        let xy = try geometryTestRequire(jacobian.minors.first { $0.rows == [0, 1] && $0.columns == [0, 1] })
        #expect(yz.order == 2 && yz.polynomial == y)
        #expect(xz.polynomial == x && xy.polynomial.isZero)
        let full = try ExactIntersectionJacobian.prepare(equations: [x, y, z], variableCount: 3, usage: &usage)
        #expect(full.minors.count == 19)
        #expect(full.minors.last?.order == 3)
        #expect(full.minors.last?.polynomial == (try .constant(variableCount: 3, value: .one, usage: &usage)))
    }

    @Test(.timeLimit(.minutes(1)))
    func crossingIsSplitIntoFourOpenRaysAndAnOriginalRankZeroPoint() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let equation = try x.multiplied(by: y, usage: &usage)
        let result = try OriginalRationalIntersectionStrata.prepare(equations: [equation], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(result.strata.count == 5)
        var origin = 0, rays = 0
        for stratum in result.strata {
            let cell = result.partition.cells[stratum.cellIndex]
            #expect(cell.signs[0] == .zero)
            if cell.dimension == 0 {
                origin += 1
                #expect(stratum.originalJacobianRank == 0)
                for coordinate in cell.coordinates {
                    #expect(try coordinate.sign(maximumDepth: 24, usage: &usage) == .zero)
                }
            } else {
                rays += 1
                #expect(cell.dimension == 1 && stratum.originalJacobianRank == 1)
            }
        }
        #expect(origin == 1 && rays == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedOriginalEquationIsNotSilentlyRadicalized() throws {
        var usage = Admission()
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let squared = try y.multiplied(by: y, usage: &usage)
        let repeated = try OriginalRationalIntersectionStrata.prepare(equations: [squared], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(repeated.strata.count == 1 && repeated.strata[0].originalJacobianRank == 0)
        #expect(repeated.partition.cells[repeated.strata[0].cellIndex].dimension == 1)
        let reduced = try OriginalRationalIntersectionStrata.prepare(equations: [y], variableCount: 2,
            domains: [nil, nil], maximumDepth: 24, usage: &usage)
        #expect(reduced.strata.count == 1 && reduced.strata[0].originalJacobianRank == 1)
        #expect(repeated.jacobian.equations == [squared] && reduced.jacobian.equations == [y])
    }

    @Test(.timeLimit(.minutes(1)))
    func zeroEquationsAndDomainWitnessesDoNotCreateFalseConstraints() throws {
        var usage = Admission()
        let result = try OriginalRationalIntersectionStrata.prepare(equations: [], variableCount: 2,
            domains: [try .init(lower: 0, upper: 0), nil], maximumDepth: 24, usage: &usage)
        #expect(result.jacobian.minors.isEmpty && result.strata.count == 1)
        #expect(result.strata[0].originalJacobianRank == 0)
        #expect(result.partition.cells[result.strata[0].cellIndex].dimension == 1)
        #expect(result.partition.partitionSignOffset == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func determinantBindingAndCallerLimitsRejectIncompleteRankEvidence() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        var invalid = [x]
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try ExactIntersectionDeterminant.evaluate(&invalid, size: 2, variableCount: 2, usage: &usage)
        }
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try ExactIntersectionDeterminant.evaluate(&invalid, size: 1, variableCount: 3, usage: &usage)
        }
        // Independent refusals retain observed counters, not another admission's proof scopes.
        let observed = (work: usage.work, storage: usage.storage, cells: usage.cells,
            maximumWork: usage.maximumWork, maximumStorage: usage.maximumStorage)
        var work = Admission(work: observed.work, storage: observed.storage, cells: observed.cells,
            maximumWork: observed.work, maximumStorage: observed.maximumStorage)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalRationalIntersectionStrata.prepare(equations: [x], variableCount: 2,
                domains: [nil, nil], maximumDepth: 24, usage: &work)
        }
        var storage = Admission(work: observed.work, storage: observed.storage, cells: observed.cells,
            maximumWork: observed.maximumWork, maximumStorage: observed.storage)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            _ = try OriginalRationalIntersectionStrata.prepare(equations: [x], variableCount: 2,
                domains: [nil, nil], maximumDepth: 24, usage: &storage)
        }
    }
}
