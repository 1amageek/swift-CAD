import Foundation
import Testing
import CADCore
import CADGeometry
@testable import CADModeling

@Suite("PolySpline G2 cap continuity admission")
struct PolySplineG2CapContinuityTests {
    @Test(.timeLimit(.minutes(1)))
    func collocationCanPassWhileProductionWholeEdgeAdmissionFails() throws {
        let nodes = (0...12).map { index in
            0.5 - 0.5 * cos(Double.pi * Double(index) / 12.0)
        }
        // Independent degree-12 Bernstein coefficients for the cardinal polynomial at node 1.
        // Its sampled values are within the allowance, while its coefficient hull is not.
        let coefficients = [
            0.0, 9.7825800901635098, -47.379441522031293, 124.9233427967238,
            -216.65120243552974, 262.60436632127357, -226.95334793780785,
            139.31779839432056, -59.150498377581243, 16.365535624645418,
            -2.599315088998992, 0.16955539654009044, 9.3132257461547852e-10,
        ]
        func bernstein(_ value: Double) -> Double {
            coefficients.enumerated().reduce(0.0) { partial, entry in
                let (index, coefficient) = entry
                let basis = binomial(12, index) * pow(value, Double(index)) * pow(1 - value, Double(12 - index))
                return partial + coefficient * basis
            }
        }
        let sampledMaximum = nodes.map { abs(bernstein($0)) }.max() ?? .infinity
        let wholeMaximum = stride(from: 0.0, through: 1.0, by: 0.0005)
            .map { abs(bernstein($0)) }.max() ?? .infinity
        let allowance = 1.000001
        #expect(sampledMaximum <= allowance)
        #expect(wholeMaximum > allowance)
        #expect(abs(bernstein(0.02143)) > allowance)

        let residual = coefficients.map {
            IntervalVector3DBounds(x: .exact($0), y: .exact(0), z: .exact(0))
        }
        let builder = PolySplineG2CapBuilder(tolerance: .standard)
        do {
            try builder.certifyAdmissionResidual(residual, allowance: allowance)
            Issue.record("The production residual admission unexpectedly accepted the coefficient hull.")
        } catch let error as KernelError {
            #expect(error.code == .singularSystem)
        } catch {
            Issue.record("The production residual admission returned an unexpected error: \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactZeroResidualAndRegularFrameUseProductionAdmission() throws {
        typealias I = OutwardScalarInterval
        let zero = I.exact(0.0)
        let residual = IntervalVector3DBounds(x: zero, y: zero, z: zero)
        let tangentU = IntervalVector3DBounds(x: I.exact(1.0), y: zero, z: zero)
        let tangentV = IntervalVector3DBounds(x: zero, y: I.exact(1.0), z: zero)
        let normal = tangentU.cross(tangentV)
        let builder = PolySplineG2CapBuilder(tolerance: .standard)
        try builder.certifyAdmissionResidual(Array(repeating: residual, count: 13), allowance: 1.0e-6)
        let net = [
            [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)],
        ]
        for fixingFirst in [false, true] {
            for atUpper in [false, true] {
                try builder.certifyAdmissionRegularity(net, fixingFirst: fixingFirst, atUpper: atUpper)
            }
        }
        for degree in [2, 8] {
            let uScale = 0.031
            let vScale = 0.007
            let independentNet = (0...degree).map { v in
                (0...degree).map { u in
                    Point3D(x: uScale * Double(u) / Double(degree),
                            y: vScale * Double(v) / Double(degree), z: 0)
                }
            }
            for fixingFirst in [false, true] {
                for atUpper in [false, true] {
                    try builder.certifyAdmissionRegularity(independentNet, fixingFirst: fixingFirst, atUpper: atUpper)
                }
            }
        }
        #expect(normal.lengthLowerBound > sin(ModelingTolerance.standard.angle))
    }

    @Test(.timeLimit(.minutes(1)))
    func productionRegularityRefusesDegenerateFrame() {
        let builder = PolySplineG2CapBuilder(tolerance: .standard)
        let degenerate = Array(repeating: Array(repeating: Point3D.origin, count: 2), count: 2)
        do {
            try builder.certifyAdmissionRegularity(degenerate, fixingFirst: false, atUpper: false)
            Issue.record("The production regularity admission unexpectedly accepted a degenerate frame.")
        } catch let error as KernelError {
            #expect(error.code == .singularSystem)
        } catch {
            Issue.record("The production regularity admission returned an unexpected error: \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func productionMatrixBudgetRefusesOverflowBeforeAllocation() {
        let builder = PolySplineG2CapBuilder(tolerance: .standard)
        do {
            try builder.checkedMatrixElementCountForAdmission((1 << 22) + 1, 1)
            Issue.record("The production matrix budget unexpectedly accepted an oversized allocation.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        } catch {
            Issue.record("The production matrix budget returned an unexpected error: \(error).")
        }
        do {
            try builder.checkedMatrixElementCountForAdmission(Int.max, 2)
            Issue.record("The production matrix budget unexpectedly accepted an overflowing allocation.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        } catch {
            Issue.record("The production matrix budget returned an unexpected error: \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledBuilderStopsBeforeInputValidation() async {
        let task = Task {
            try PolySplineG2CapBuilder(tolerance: .standard).caps(apex: .origin, sectors: [])
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        guard k > 0 else { return 1 }
        return (0..<k).reduce(1.0) { value, index in
            value * Double(n - index) / Double(index + 1)
        }
    }
}
