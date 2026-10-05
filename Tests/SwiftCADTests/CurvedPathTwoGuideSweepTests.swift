import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Two Point guides steer a section along a curved path (Sweep2's rule, inferred for Plasticity's
/// Sweep with two guides, decided 2026-10-05): at every station the section is deformed by the
/// linear map of the plane across the path taking its two contacts to where the guides cross it.
@Suite("Curved path two-guide sweep")
struct CurvedPathTwoGuideSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// The planar cubic path in the ZX plane from the origin (sketch x is world z, y is world x).
    private let controls: [(z: Double, x: Double)] = [(0, 0), (0.02, 0), (0.04, 0.01), (0.05, 0.03)]

    private func path(_ t: Double) -> (z: Double, x: Double, dz: Double, dx: Double) {
        let b = [(1 - t) * (1 - t) * (1 - t), 3 * (1 - t) * (1 - t) * t, 3 * (1 - t) * t * t, t * t * t]
        let d = [-3 * (1 - t) * (1 - t), 3 * (1 - t) * (1 - 3 * t), 3 * t * (2 - 3 * t), 3 * t * t]
        return (zip(b, controls).map { $0 * $1.z }.reduce(0, +), zip(b, controls).map { $0 * $1.x }.reduce(0, +),
                zip(d, controls).map { $0 * $1.z }.reduce(0, +), zip(d, controls).map { $0 * $1.x }.reduce(0, +))
    }

    /// The path offset by `distance` within its plane, to its left-hand side about +y (world +x at
    /// the start): the point and its derivative in t.
    private func offset(_ t: Double, by distance: Double) -> (point: Point3D, derivative: Vector3D) {
        let h = 1e-6
        func at(_ s: Double) -> Point3D {
            let p = path(s)
            let speed = (p.dz * p.dz + p.dx * p.dx).squareRoot()
            return Point3D(x: p.x + distance * p.dz / speed, y: 0, z: p.z - distance * p.dx / speed)
        }
        return (at(t), (at(t + h) - at(t - h)) * (1 / (2 * h)))
    }

    /// ∫₀¹ f(t)·|P′(t)| dt by composite Gauss–Legendre quadrature.
    private func integral(_ f: (Double) -> Double) -> Double {
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        return (0..<256).reduce(0.0) { sum, index in
            let lower = Double(index) / 256, half = 0.5 / 256
            return sum + zip(nodes, weights).reduce(0.0) { total, pair in
                let t = lower + half * (1 + pair.0)
                let p = path(t)
                return total + pair.1 * f(t) * (p.dz * p.dz + p.dx * p.dx).squareRoot()
            } * half
        }
    }

    @Test(.timeLimit(.minutes(4)))
    func twoPointGuidesStretchTheSectionBetweenThem() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 4 mm square about the path start, square to it.
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let route = try builder.sketch(on: .zx) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: controls.map { SketchPoint(x: length($0.z), y: length($0.x)) }))
        }
        // The first guide from the top edge's middle rising along y from 2 mm to 4 mm off the path;
        // the second from the right edge's middle running 2 mm beside the path within its plane.
        let rising = FeatureID()
        let lifted = (0..<4).map { i in
            Point3D(x: controls[i].x, y: 0.002 + 0.002 * Double(i) / 3, z: controls[i].z)
        }
        try builder.append(id: rising, name: "Rising", operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: [
            SpatialPathKnot(position: lifted[0], outgoing: lifted[1] - lifted[0]),
            SpatialPathKnot(position: lifted[3], incoming: lifted[2] - lifted[3]),
        ])))
        let beside = FeatureID()
        let count = 64
        let knots = (0...count).map { k -> SpatialPathKnot in
            let t = Double(k) / Double(count)
            let (point, derivative) = offset(t, by: 0.002)
            let step = derivative * (1 / (3 * Double(count)))
            return SpatialPathKnot(position: point, incoming: k == 0 ? .zero : step * -1, outgoing: k == count ? .zero : step)
        }
        try builder.append(id: beside, name: "Beside", operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: knots)))
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = .point
        options.approximationTolerance = length(1e-7)
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile.featureID)), along: route.featureID,
                              guides: [rising, beside], options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "sweep2"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The rising guide stretches the square across the path by (2 + 2t) / 2; the one beside it
        // keeps its width: the section's area is 16 mm² · (1 + t), its centroid on the path.
        let expected = integral { t in 0.004 * 0.004 * (1 + t) }
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 1e-10, "\(volume) vs \(expected)")
        // Every point of both guides lies on the swept sides.
        let surfaces = evaluated.brep.faces.values.compactMap { evaluated.brep.geometry.surfaces[$0.surfaceID] }
        func distanceToSides(_ point: Point3D) -> Double {
            surfaces.compactMap { surface -> Double? in
                // A face the point does not project onto (one far from it) has no foot; the
                // nearest face that has one is the one the point lies on.
                do {
                    let foot = try surface.parameterProjection(of: point, tolerance: .standard)
                    return (try surface.point(u: foot.u, v: foot.v, tolerance: .standard) - point).length
                } catch {
                    return nil
                }
            }.min() ?? .infinity
        }
        for k in 1..<8 {
            let t = Double(k) / 8
            let p = path(t)
            let rise = 0.002 + 0.002 * t
            #expect(distanceToSides(Point3D(x: p.x, y: rise, z: p.z)) < 1e-6, "rising guide at \(t)")
            #expect(distanceToSides(offset(t, by: 0.002).point) < 1e-6, "beside guide at \(t)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func twoGuidesOnOneLineThroughThePathAreRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let route = try builder.sketch(on: .zx) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: controls.map { SketchPoint(x: length($0.z), y: length($0.x)) }))
        }
        // The top and bottom edges' middles: both on the y line through the path.
        let guides = try [0.002, -0.002].map { y -> FeatureID in
            let id = FeatureID()
            let lifted = (0..<4).map { i in Point3D(x: controls[i].x, y: y, z: controls[i].z) }
            try builder.append(id: id, name: nil, operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: [
                SpatialPathKnot(position: lifted[0], outgoing: lifted[1] - lifted[0]),
                SpatialPathKnot(position: lifted[3], incoming: lifted[2] - lifted[3]),
            ])))
            return id
        }
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = .point
        options.approximationTolerance = length(1e-7)
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile.featureID)), along: route.featureID,
                              guides: guides, options: options)
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "sweep2"))
        }
    }
}
