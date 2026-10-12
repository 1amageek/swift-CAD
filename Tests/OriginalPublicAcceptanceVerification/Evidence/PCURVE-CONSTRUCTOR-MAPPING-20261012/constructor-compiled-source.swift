import CADCore
@testable import CADGeometry
import Foundation

/// Checks constructor inputs and independent position laws, not exact-query acceptance.
@main struct PcurveSourceMappingProbe {
    enum Failure: Error { case position(String), foreignHost(String) }

    static func main() throws {
        let tolerance = ModelingTolerance.standard
        let plane = Surface3D.plane(.init(origin: .origin, normal: .unitZ))
        let parabola = Curve3D.analytic(.parabola(.init(vertex: .origin,
            normal: .unitZ, axis: .unitX, focalLength: 0.5)))
        let projected = SurfaceParameterCurve.projectedAnalytic(
            try .init(curve: parabola, surface: plane, startParameter: -1,
                endParameter: 1, tolerance: tolerance))
        try check("PCURVE-PROJECTED-PARABOLA-01", surface: plane, pcurve: projected) { t in
            let q = 2 * t - 1
            return .init(x: q * q / 2, y: q, z: 0)
        }
        let harmonic = SurfaceParameterCurve.harmonic(center: .init(x: 0, y: 0),
            cosine: .init(x: 1, y: 0), sine: .init(x: 0, y: 1),
            startParameter: 0, endParameter: 1)
        try check("PCURVE-HARMONIC-01", surface: plane, pcurve: harmonic) { t in
            .init(x: -sin(t), y: cos(t), z: 0)
        }
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let greatCircle = SurfaceParameterCurve.sphericalGreatCircle(cosine: .unitY,
            sine: -.unitX, startParameter: -0.25, endParameter: 0.25)
        try check("PCURVE-SPHERICAL-GREAT-CIRCLE-01", surface: sphere, pcurve: greatCircle) { t in
            let theta = t / 2 - 0.25
            return .init(x: -2 * sin(theta), y: 2 * cos(theta), z: 0)
        }
        let affine = SurfaceParameterCurve.affine(origin: .init(x: 0.125, y: -0.25),
            direction: .init(x: 0.5, y: 0.5), startParameter: 0, endParameter: 1)
        let offset = OffsetSurface3D(source: plane, distance: 2)
        let forward = try offset.parameterCurveImage(transporting: affine, tolerance: tolerance)
        let destination = try forward.targetSurface(tolerance: tolerance)
        try check("PCURVE-OFFSET-FORWARD-01", surface: destination,
            pcurve: .offsetSurfaceImage(forward)) { t in
            .init(x: 0.25 - t / 2, y: 0.125 + t / 2, z: 2)
        }
        let native = Surface3D.bSpline(.init(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 1)]
            ]))
        let curvedOffset = OffsetSurface3D(source: native, distance: 0.25)
        let pullback = try curvedOffset.parameterCurvePullback(transporting:
            .affine(origin: .init(x: 0.125, y: 0.25), direction: .init(x: 0.5, y: 0.5),
                startParameter: 0, endParameter: 1), tolerance: tolerance)
        try check("PCURVE-OFFSET-PULLBACK-01", surface: native,
            pcurve: .offsetSurfaceImage(pullback)) { t in
            let u = 0.125 + t / 2, v = 0.25 + t / 2
            return .init(x: u, y: v, z: u * v)
        }
        do {
            try SurfaceParameterCurve.offsetSurfaceImage(pullback).validate(
                on: .procedural(.offset(curvedOffset)), tolerance: tolerance)
        } catch {
            print("PASS PCURVE-OFFSET-PULLBACK-FOREIGN-01 rejected wrong directed host")
            print("SCOPE constructor and numerical position checks only; exact public acceptance remains open")
            return
        }
        throw Failure.foreignHost("PCURVE-OFFSET-PULLBACK-FOREIGN-01")
    }

    static func check(_ id: String, surface: Surface3D, pcurve: SurfaceParameterCurve,
        expected: (Double) -> Point3D) throws {
        try pcurve.validate(on: surface, tolerance: .standard)
        let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve)
        for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let point = try Curve3D.surfaceLift(lift).point(at: t, tolerance: .standard)
            guard (point - expected(t)).length <= 1e-12 else { throw Failure.position(id) }
        }
        print("PASS", id, "constructor and independent position law")
    }
}
