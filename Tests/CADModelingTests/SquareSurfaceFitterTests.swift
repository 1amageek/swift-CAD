import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADModeling

/// Square's fit over a skewed, non-planar bilinear frame: Degree and Spans as minimums, hard sides
/// kept exactly, the fairness never worse than the exact sheet, the boundary flows, Free sides by
/// their weight and an undetermined frame refused.
@Suite("Square surface fitter")
struct SquareSurfaceFitterTests {
    private let tolerance = ModelingTolerance.standard
    private let featureID = FeatureID()

    /// Corners (0,0,0), (1,0,0), (0.5,1,0.6), (1.5,1,0.3): every side straight, the frame twisted.
    private var bilinear: BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                         controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                                         [Point3D(x: 0.5, y: 1, z: 0.6), Point3D(x: 1.5, y: 1, z: 0.3)]],
                         weights: [[1, 1], [1, 1]])
    }

    private func fit(_ constraints: [SquareSurfaceFitter.Constraint], options: SquareFitOptions) throws -> BSplineSurface3D {
        try SquareSurfaceFitter(tolerance: tolerance).fit(
            exact: bilinear,
            boundaries: constraints.map { .init(constraint: $0, flows: $0 != .none) },
            options: options, featureID: featureID
        )
    }

    private func jet(_ surface: BSplineSurface3D, _ u: Double, _ v: Double) throws -> BSplineSurface3D.DifferentialGeometry {
        try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
    }

    /// ∫∫ |S_uu|² + 2|S_uv|² + |S_vv|² by the midpoint rule on a 40 × 40 grid.
    private func bending(_ surface: BSplineSurface3D) throws -> Double {
        var sum = 0.0
        for a in 0..<40 {
            for b in 0..<40 {
                let d = try jet(surface, (Double(a) + 0.5) / 40, (Double(b) + 0.5) / 40)
                sum += d.secondDerivativeUU.dot(d.secondDerivativeUU) + 2 * d.secondDerivativeUV.dot(d.secondDerivativeUV)
                    + d.secondDerivativeVV.dot(d.secondDerivativeVV)
            }
        }
        return sum / 1600
    }

    @Test(.timeLimit(.minutes(1)))
    func degreeAndSpansAreTheNetAndHardSidesStayExact() throws {
        let surface = try fit(Array(repeating: .hard(order: 0), count: 4),
                              options: SquareFitOptions(uDegree: 4, vDegree: 3, uSpans: 2, vSpans: 3, boundaryFlow: .natural))
        #expect(surface.uDegree == 4 && surface.vDegree == 3)
        #expect(Set(surface.uKnots.filter { $0 > 0 && $0 < 1 }) == [0.5])
        #expect(Set(surface.vKnots.filter { $0 > 0 && $0 < 1 }).count == 2)
        for k in 0...10 {
            let t = Double(k) / 10
            for (u, v) in [(t, 0.0), (1.0, t), (t, 1.0), (0.0, t)] {
                let fitted = try surface.point(u: u, v: v, tolerance: tolerance)
                let exact = try bilinear.point(u: u, v: v, tolerance: tolerance)
                #expect((fitted - exact).length < 1e-12)
            }
        }
        // The exact sheet lies in the space, so the fair sheet bends no more than it.
        #expect(try bending(surface) <= bending(bilinear) + 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func normalFlowLeavesTheSidesPerpendicular() throws {
        func cosine(_ surface: BSplineSurface3D) throws -> Double {
            try (1...9).map { k -> Double in
                let d = try jet(surface, Double(k) / 10, 0)
                return abs(d.tangentU.dot(d.tangentV)) / (d.tangentU.length * d.tangentV.length)
            }.max() ?? 0
        }
        // Between two opposite sides alone, so no fixed neighbour pins the flow at the corners.
        let sides: [SquareSurfaceFitter.Constraint] = [.hard(order: 0), .none, .hard(order: 0), .none]
        let natural = try fit(sides, options: SquareFitOptions(boundaryFlow: .natural))
        let normal = try fit(sides, options: SquareFitOptions(weight: 1e6, boundaryFlow: .normal))
        #expect(try cosine(natural) > 0.1)
        #expect(try cosine(normal) < 1e-3)
    }

    @Test(.timeLimit(.minutes(1)))
    func nextFlowLeavesTheSidesInTheMeanPlane() throws {
        let next = try fit([.hard(order: 0), .none, .hard(order: 0), .none], options: SquareFitOptions(weight: 1e6, boundaryFlow: .next))
        // The exact sheet's mean unit normal on a 5 × 5 grid.
        var sum = Vector3D.zero
        for a in 0...4 {
            for b in 0...4 {
                let d = try jet(bilinear, Double(a) / 4, Double(b) / 4)
                sum = sum + (try d.tangentU.cross(d.tangentV).normalized(tolerance: 1e-12))
            }
        }
        let normal = try sum.normalized(tolerance: 1e-12)
        for k in 1...9 {
            let d = try jet(next, Double(k) / 10, 0)
            let direction = try d.tangentV.normalized(tolerance: 1e-12)
            #expect(abs(direction.dot(try d.tangentU.normalized(tolerance: 1e-12))) < 1e-3)
            #expect(abs(direction.dot(normal)) < 1e-3)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func adjacentFlowBlendsTheNeighbouringSides() throws {
        let adjacent = try fit(Array(repeating: .hard(order: 0), count: 4), options: SquareFitOptions(weight: 1e6, boundaryFlow: .adjacent))
        let left = Vector3D(x: 0.5, y: 1, z: 0.6), right = Vector3D(x: 0.5, y: 1, z: 0.3)
        for k in 1...9 {
            let t = Double(k) / 10
            let expected = left * (1 - t) + right * t
            #expect((try jet(adjacent, t, 0).tangentV - expected).length < 1e-3)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aFreeSideIsFollowedByItsWeight() throws {
        func deviation(_ weight: Double) throws -> Double {
            let surface = try fit([.loose, .hard(order: 0), .hard(order: 0), .hard(order: 0)],
                                  options: SquareFitOptions(weight: weight, boundaryFlow: .natural))
            return try (0...20).map { k -> Double in
                let t = Double(k) / 20
                return (try surface.point(u: t, v: 0, tolerance: tolerance) - bilinear.point(u: t, v: 0, tolerance: tolerance)).length
            }.max() ?? 0
        }
        let loose = try deviation(1e-4), strict = try deviation(1e6)
        #expect(loose > strict)
        #expect(strict < 1e-4)
    }

    @Test(.timeLimit(.minutes(1)))
    func twoOppositeSidesDetermineTheSheetAndOneDoesNot() throws {
        let ruled = try fit([.hard(order: 0), .none, .hard(order: 0), .none], options: SquareFitOptions(boundaryFlow: .natural))
        for k in 0...10 {
            let t = Double(k) / 10
            #expect((try ruled.point(u: t, v: 1, tolerance: tolerance) - bilinear.point(u: t, v: 1, tolerance: tolerance)).length < 1e-12)
        }
        #expect(throws: KernelError.self) {
            try fit([.hard(order: 0), .none, .none, .none], options: SquareFitOptions(boundaryFlow: .natural))
        }
    }
}
