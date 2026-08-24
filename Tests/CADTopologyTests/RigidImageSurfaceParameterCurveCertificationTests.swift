import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing

@Suite("Rigid-image pcurve certification")
struct RigidImageSurfaceParameterCurveCertificationTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10,
        relative: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func directlyEvaluablePcurvesProduceCompleteCertifiedEnclosures() throws {
        let curves: [SurfaceParameterCurve] = [
            .affine(
                origin: Point2D(x: -0.3, y: 0.2),
                direction: Point2D(x: 0.9, y: -0.4),
                startParameter: 0.1,
                endParameter: 1.2
            ),
            .constantU(u: 0.4, vStart: -0.7, vEnd: 0.9),
            .constantV(v: -0.2, uStart: -0.8, uEnd: 0.6),
            .harmonic(
                center: Point2D(x: 0.1, y: -0.2),
                cosine: Point2D(x: 0.7, y: 0.2),
                sine: Point2D(x: -0.1, y: 0.5),
                startParameter: 0.2,
                endParameter: 1.6
            ),
            .polyline([
                SurfaceParameter(u: -0.5, v: -0.2),
                SurfaceParameter(u: 0.1, v: 0.7),
                SurfaceParameter(u: 0.8, v: -0.1),
            ]),
            .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: -0.6, y: 0.1),
                    Point2D(x: 0.2, y: 0.8),
                    Point2D(x: 0.7, y: -0.3),
                ],
                weights: [1.0, 0.65, 1.0]
            )),
        ]
        let encloser = CertifiedSurfaceParameterCurveEncloser()
        for curve in curves {
            let enclosures = try encloser.enclosures(
                for: curve,
                maximumWidth: 0.04,
                tolerance: tolerance
            )
            try verify(enclosures: enclosures, contain: curve)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func affineRigidImageMapsEnclosuresAndGreenAreaWithoutProjection() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.2, y: -0.1, z: 0.3),
            normal: Vector3D.unitZ
        ))
        let sourceCurve = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 0.2, y: -0.1),
            cosine: Point2D(x: 0.7, y: 0.2),
            sine: Point2D(x: -0.15, y: 0.45),
            startParameter: 0.15,
            endParameter: 1.75
        )
        let transform = try RigidTransform3D.mirrored(
            across: Point3D(x: 0.1, y: 0.2, z: -0.3),
            normal: Vector3D(x: 1.0, y: -2.0, z: 0.5),
            tolerance: tolerance
        )
        let image = try rigidImage(
            surface: surface,
            curve: sourceCurve,
            transform: transform
        )
        let curve = SurfaceParameterCurve.rigidImage(image)
        let enclosures = try CertifiedSurfaceParameterCurveEncloser()
            .enclosures(
                for: curve,
                maximumWidth: 0.03,
                tolerance: tolerance
            )
        try verify(enclosures: enclosures, contain: curve)

        let reversed = SurfaceParameterCurve.rigidImage(
            try image.reversed(tolerance: tolerance)
        )
        let partial = try CertifiedSurfaceParameterCurveEncloser()
            .enclosures(
                for: reversed,
                fromNormalizedFraction: 0.2,
                toNormalizedFraction: 0.8,
                maximumWidth: 0.03,
                tolerance: tolerance
            )
        try verify(
            enclosures: partial,
            contain: reversed,
            lowerFraction: 0.2,
            upperFraction: 0.8
        )

        let requestedWidth = 1.0e-8
        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: curve,
            uShift: 0.27,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let oracle = try numericalGreenArea(
            image: image,
            uShift: 0.27,
            stepCount: 32_768
        )
        #expect(bounds.lower <= oracle)
        #expect(bounds.upper >= oracle)
        #expect(bounds.width <= requestedWidth * 1.1)
    }

    @Test(.timeLimit(.minutes(1)))
    func rotatedSphereHasContinuousCertifiedChartEnclosuresAndArea() throws {
        let surface = Surface3D.analytic(.sphere(
            center: Point3D(x: -0.1, y: 0.2, z: 0.3),
            radius: 0.9
        ))
        let sourceCurve = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 0.45, y: 0.05),
            cosine: Point2D(x: 0.5, y: 0.12),
            sine: Point2D(x: -0.08, y: 0.09),
            startParameter: 0.1,
            endParameter: 1.7
        )
        let transform = try RigidTransform3D.rotated(
            around: Point3D(x: 0.3, y: -0.2, z: 0.4),
            direction: Vector3D(x: 1.0, y: -1.5, z: 2.0),
            angle: 0.87,
            tolerance: tolerance
        )
        let image = try rigidImage(
            surface: surface,
            curve: sourceCurve,
            transform: transform
        )
        #expect(try image.affineParameterTransform(tolerance: tolerance) == nil)
        let curve = SurfaceParameterCurve.rigidImage(image)
        let encoded = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(
            SurfaceParameterCurve.self,
            from: encoded
        )
        #expect(decoded == curve)

        let enclosures = try CertifiedSurfaceParameterCurveEncloser()
            .enclosures(
                for: decoded,
                maximumWidth: 0.035,
                tolerance: tolerance
            )
        try verify(enclosures: enclosures, contain: decoded)
        let sampledLongitudes = try (0...1_024).map { index in
            try decoded.parameter(
                atNormalizedFraction: Double(index) / 1_024.0,
                tolerance: tolerance
            ).u
        }
        #expect(zip(sampledLongitudes, sampledLongitudes.dropFirst())
            .allSatisfy { abs($0.1 - $0.0) < Double.pi })

        let requestedWidth = 2.0e-5
        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: decoded,
            uShift: -0.19,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let oracle = try numericalGreenArea(
            image: image,
            uShift: -0.19,
            stepCount: 65_536
        )
        #expect(bounds.lower <= oracle)
        #expect(bounds.upper >= oracle)
        #expect(bounds.width <= requestedWidth * 1.1)
    }

    @Test(.timeLimit(.minutes(1)))
    func transformedProceduralSurfacePreservesItsParameterChart() throws {
        let surface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .line(Line3D(origin: .origin, direction: .unitX)),
            endBoundary: .line(Line3D(
                origin: Point3D(x: 0.0, y: 1.0, z: 0.4),
                direction: .unitX
            ))
        )))
        let sourceCurve = SurfaceParameterCurve.affine(
            origin: Point2D(x: 0.1, y: 0.2),
            direction: Point2D(x: 0.7, y: 0.5),
            startParameter: 0.0,
            endParameter: 1.0
        )
        let transform = try RigidTransform3D.rotated(
            around: Point3D(x: 0.2, y: -0.1, z: 0.3),
            direction: Vector3D(x: 1.0, y: 2.0, z: -1.0),
            angle: 0.71,
            tolerance: tolerance
        )
        let image = try rigidImage(
            surface: surface,
            curve: sourceCurve,
            transform: transform
        )

        #expect(try image.affineParameterTransform(tolerance: tolerance) == .identity)
        for index in 0...32 {
            let fraction = Double(index) / 32.0
            let expected = try sourceCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let actual = try image.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            #expect(abs(actual.u - expected.u) <= tolerance.distance)
            #expect(abs(actual.v - expected.v) <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsTargetSurfaceThatIsNotTheExactRigidImage() throws {
        let sourceSurface = Surface3D.analytic(.sphere(center: .origin, radius: 1.0))
        let source = SurfaceLiftCurve3D(
            surface: sourceSurface,
            parameterCurve: .constantV(v: 0.2, uStart: 0.1, uEnd: 1.0)
        )
        let transform = try RigidTransform3D.rotated(
            around: .origin,
            direction: .unitX,
            angle: 0.4,
            tolerance: tolerance
        )
        #expect(throws: KernelError.self) {
            _ = try RigidImageSurfaceParameterCurve(
                source: source,
                targetSurface: .analytic(.sphere(
                    center: Point3D(x: 0.01, y: 0.0, z: 0.0),
                    radius: 1.0
                )),
                transform: transform,
                tolerance: tolerance
            )
        }
    }

    private func rigidImage(
        surface: Surface3D,
        curve: SurfaceParameterCurve,
        transform: RigidTransform3D
    ) throws -> RigidImageSurfaceParameterCurve {
        try RigidImageSurfaceParameterCurve(
            source: SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: curve
            ),
            targetSurface: try transform.applying(
                to: surface,
                tolerance: tolerance
            ),
            transform: transform,
            tolerance: tolerance
        )
    }

    private func verify(
        enclosures: [SurfaceParameterCurveEnclosure],
        contain curve: SurfaceParameterCurve,
        lowerFraction: Double = 0.0,
        upperFraction: Double = 1.0
    ) throws {
        #expect(enclosures.isEmpty == false)
        #expect(enclosures.allSatisfy { $0.maximumWidth <= 0.04 })
        #expect(abs(
            (enclosures.first?.lowerFraction ?? .infinity) - lowerFraction
        ) <= 1.0e-12)
        #expect(abs(
            (enclosures.last?.upperFraction ?? -.infinity) - upperFraction
        ) <= 1.0e-12)
        #expect(zip(enclosures, enclosures.dropFirst()).allSatisfy {
            abs($0.0.upperFraction - $0.1.lowerFraction) <= 1.0e-12
        })
        for enclosure in enclosures {
            for index in 0...8 {
                let fraction = enclosure.lowerFraction
                    + (enclosure.upperFraction - enclosure.lowerFraction)
                        * Double(index) / 8.0
                let parameter = try curve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                #expect(parameter.u >= enclosure.u.lower)
                #expect(parameter.u <= enclosure.u.upper)
                #expect(parameter.v >= enclosure.v.lower)
                #expect(parameter.v <= enclosure.v.upper)
            }
        }
    }

    private func numericalGreenArea(
        image: RigidImageSurfaceParameterCurve,
        uShift: Double,
        stepCount: Int
    ) throws -> Double {
        let step = 1.0 / Double(stepCount)
        func integrand(_ fraction: Double) throws -> Double {
            let differential = try image.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return (differential.parameter.u + uShift)
                * differential.firstDerivative.y
        }
        var result = try integrand(0.0) + integrand(1.0)
        for index in 1..<stepCount {
            result += (index.isMultiple(of: 2) ? 2.0 : 4.0)
                * (try integrand(Double(index) * step))
        }
        return result * step / 3.0
    }
}
