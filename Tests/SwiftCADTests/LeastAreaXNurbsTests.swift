import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Patch's Faces Minimal (inferred with the user 2026-10-05): the least-area sheet through the
/// boundary. Enneper's surface over the disc of radius 1/2 is the least-area surface its boundary
/// spans, of area π((1 + R²)³ − 1)/3.
@Suite("Least-area XNURBS")
struct LeastAreaXNurbsTests {
    private let scale = 0.01
    private let radius = 0.5

    /// Enneper's surface at polar (r, θ), scaled to millimetres, and its θ-derivative.
    private func enneper(_ r: Double, _ theta: Double) -> (point: Point3D, derivative: Vector3D) {
        func at(_ t: Double) -> Point3D {
            let (u, v) = (r * cos(t), r * sin(t))
            return Point3D(x: scale * (u - u * u * u / 3 + u * v * v), y: scale * (v - v * v * v / 3 + v * u * u), z: scale * (u * u - v * v))
        }
        let h = 1e-6
        return (at(theta), (at(theta + h) - at(theta - h)) * (1 / (2 * h)))
    }

    private func area(minimizes: Bool) throws -> Double {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // The boundary in four quarters, each 16 cubic Hermite pieces.
        let quarters = try (0..<4).map { quarter -> FeatureID in
            let count = 16
            let knots = (0...count).map { k -> SpatialPathKnot in
                let theta = Double.pi / 2 * (Double(quarter) + Double(k) / Double(count))
                let (point, derivative) = enneper(radius, theta)
                let step = derivative * (Double.pi / 2 / Double(count) / 3)
                return SpatialPathKnot(position: point, incoming: k == 0 ? .zero : step * -1, outgoing: k == count ? .zero : step)
            }
            let id = FeatureID()
            try builder.append(id: id, name: nil, operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: knots)))
            return id
        }
        _ = try builder.xnurbs(XNurbsFeature(boundaries: quarters.map { SquareSide(curve: CurveSectionReference(featureID: $0)) },
                                             quality: .auto, minimizesArea: minimizes))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "enneper"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        // The face's area: |Su × Sv| by Gauss points over its parameter square, those inside its
        // trimming loop (its pcurves sampled into a polygon) summed.
        let face = try #require(evaluated.brep.faces.values.first)
        let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
        var region: [SurfaceParameter] = []
        for loopID in face.loops {
            for coedge in try #require(evaluated.brep.loops[loopID]).coedges {
                let pcurve = try #require(coedge.surfaceParameterCurve)
                region += try (0..<64).map { try pcurve.parameter(atNormalizedFraction: Double($0) / 64, tolerance: .standard) }
            }
        }
        let (us, vs) = (region.map(\.u), region.map(\.v))
        let (u0, u1, v0, v1) = (us.min() ?? 0, us.max() ?? 1, vs.min() ?? 0, vs.max() ?? 1)
        let nodes = [-0.7745966692414834, 0, 0.7745966692414834], weights = [0.5555555555555556, 0.8888888888888888, 0.5555555555555556]
        var total = 0.0
        let cells = 64
        for i in 0..<cells {
            for j in 0..<cells {
                for (a, wa) in zip(nodes, weights) {
                    for (b, wb) in zip(nodes, weights) {
                        let u = u0 + (u1 - u0) * (Double(i) + 0.5 * (1 + a)) / Double(cells)
                        let v = v0 + (v1 - v0) * (Double(j) + 0.5 * (1 + b)) / Double(cells)
                        var inside = false
                        for (p, q) in zip(region, region.dropFirst() + region.prefix(1)) where (p.v > v) != (q.v > v) {
                            if u < p.u + (v - p.v) * (q.u - p.u) / (q.v - p.v) { inside.toggle() }
                        }
                        guard inside else { continue }
                        let jet = try surface.differentialGeometry(u: u, v: v, tolerance: .standard)
                        total += jet.tangentU.cross(jet.tangentV).length * wa * wb * 0.25 * (u1 - u0) * (v1 - v0) / Double(cells * cells)
                    }
                }
            }
        }
        return total
    }

    @Test(.timeLimit(.minutes(6)))
    func enneperBoundarySpansEnneperSurface() throws {
        let expected = Double.pi * (pow(1 + radius * radius, 3) - 1) / 3 * scale * scale
        // The fair sheet (flatness 0.95) is the comparison: the least-area one is smaller.
        let fair = try area(minimizes: false)
        let least = try area(minimizes: true)
        #expect(abs(least - expected) / expected < 2e-3, "\(least) vs \(expected)")
        #expect(least < fair)
    }
}
