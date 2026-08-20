@testable import CADGeometry
import CADCore
import Testing

@Suite("Certified Simple Polynomial Root Solver")
struct CertifiedSimplePolynomialRootSolverTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func certifiesMonotoneCubicAndQuarticRootCompleteness() throws {
        let solver = try makeSolver()
        let monotoneRoots = try solver.roots(coefficients: [0.0, 1.0, 0.0, 1.0])
        #expect(monotoneRoots.count == 1)
        #expect(monotoneRoots[0].lower <= 0.0)
        #expect(monotoneRoots[0].upper >= 0.0)

        let quarticRoots = try solver.roots(
            coefficients: [4.0, 0.0, -5.0, 0.0, 1.0]
        )
        #expect(quarticRoots.count == 4)
        for (root, expected) in zip(quarticRoots, [-2.0, -1.0, 1.0, 2.0]) {
            #expect(root.lower <= expected)
            #expect(root.upper >= expected)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func certifiesEverySimpleRootOfDegreeEightPolynomial() throws {
        let solver = try makeSolver()
        let expectedRoots = [-4.0, -3.0, -2.0, -1.0, 1.0, 2.0, 3.0, 4.0]
        let coefficients = expectedRoots.reduce([1.0]) { polynomial, root in
            var product = Array(repeating: 0.0, count: polynomial.count + 1)
            for index in polynomial.indices {
                product[index] -= polynomial[index] * root
                product[index + 1] += polynomial[index]
            }
            return product
        }

        let roots = try solver.roots(coefficients: coefficients)

        #expect(roots.count == expectedRoots.count)
        for (root, expected) in zip(roots, expectedRoots) {
            #expect(root.lower <= expected)
            #expect(root.upper >= expected)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedRootReturnsTypedSingularDiagnostic() throws {
        let solver = try makeSolver()
        do {
            _ = try solver.roots(coefficients: [1.0, -2.0, 1.0])
            Issue.record("A repeated polynomial root must not be certified as simple.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func reusableHornerBuffersPreserveExpansionSigns() {
        let coefficientSets = [
            [4.0, 0.0, -5.0, 0.0, 1.0],
            [1.0, -4.0, 6.0, -4.0, 1.0],
            [Double.leastNormalMagnitude, -1.0, 0.0, 1.0],
            [1.0e120, -3.0e80, 2.0e40, -1.0],
        ]
        let values = [
            -4.0,
            -2.0,
            -1.0.nextUp,
            -Double.ulpOfOne,
            0.0,
            Double.ulpOfOne,
            1.0.nextDown,
            2.0,
            4.0,
        ]

        for coefficients in coefficientSets {
            for value in values {
                var reference: [Double] = []
                for coefficient in coefficients.reversed() {
                    reference = FloatingPointExpansion.sum(
                        FloatingPointExpansion.product(reference, [value]),
                        [coefficient]
                    )
                }
                #expect(
                    FloatingPointExpansion.hornerSign(
                        coefficients: coefficients,
                        at: value
                    ) == FloatingPointExpansion.sign(reference)
                )
            }
        }
    }

    private func makeSolver() throws -> CertifiedSimplePolynomialRootSolver {
        try CertifiedSimplePolynomialRootSolver(
            rootTolerance: tolerance.angle * 0.25,
            coefficientTolerance: Double.ulpOfOne * 128.0,
            maximumRefinementIterations: 256,
            tolerance: tolerance
        )
    }
}
