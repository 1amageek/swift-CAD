import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Certified surface differential enclosures")
struct SurfaceDifferentialEncloserTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func analyticEnclosuresContainPositionAndSecondOrderJet() throws {
        let cases: [(Surface3D, SurfaceParameterBox)] = [
            (
                .plane(Plane3D(origin: .origin, normal: .unitZ)),
                try box(u: -1.2 ... 0.8, v: -0.7 ... 1.4)
            ),
            (
                .cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 2.0)),
                try box(u: 5.8 ... 6.7, v: -0.4 ... 1.1)
            ),
            (
                .analytic(.plane(origin: Point3D(x: 0.5, y: -0.3, z: 0.8), normal: .unitY)),
                try box(u: -0.8 ... 1.3, v: -1.1 ... 0.4)
            ),
            (
                .analytic(.cylinder(origin: .origin, axis: .unitX, radius: 1.7)),
                try box(u: 0.2 ... 2.1, v: -0.5 ... 1.5)
            ),
            (
                .analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: 0.43)),
                try box(u: 1.1 ... 3.4, v: 0.3 ... 2.2)
            ),
            (
                .analytic(.sphere(center: Point3D(x: 1.0, y: -2.0, z: 0.5), radius: 2.3)),
                try box(u: 0.4 ... 4.0, v: -0.9 ... 0.8)
            ),
            (
                .analytic(.torus(
                    center: Point3D(x: -0.2, y: 0.7, z: 1.1),
                    axis: .unitY,
                    majorRadius: 3.0,
                    minorRadius: 0.8
                )),
                try box(u: 4.9 ... 6.9, v: 0.7 ... 4.4)
            ),
        ]

        for (surface, parameters) in cases {
            let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
                of: surface,
                over: parameters,
                tolerance: tolerance
            )
            try verifySamples(
                of: surface,
                in: parameters,
                enclosure: enclosure,
                sampleCount: 9
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineEnclosureContainsTrimmedMultiSpanJet() throws {
        let surface = Surface3D.bSpline(makeRationalSurface())
        let parameters = try box(u: 0.13 ... 0.87, v: 0.17 ... 0.91)

        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )

        try verifySamples(
            of: surface,
            in: parameters,
            enclosure: enclosure,
            sampleCount: 13
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineEnclosureContractsOnMicroscopicParameterCell() throws {
        let surface = Surface3D.bSpline(makeRationalSurface())
        let parameters = try box(
            u: 0.369_999 ... 0.370_001,
            v: 0.629_999 ... 0.630_001
        )

        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )

        try verifySamples(
            of: surface,
            in: parameters,
            enclosure: enclosure,
            sampleCount: 5
        )
        #expect(enclosure.position.x.width < 1.0e-3)
        #expect(enclosure.position.y.width < 1.0e-3)
        #expect(enclosure.position.z.width < 1.0e-3)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineOffsetBoundsRemainConditionedOnMicroscopicParameterCell() throws {
        let source = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -0.02, y: 0.0, z: 0.004),
                    Point3D(x: 0.0, y: 0.0, z: -0.004),
                    Point3D(x: 0.02, y: 0.0, z: 0.004),
                ],
                [
                    Point3D(x: -0.02, y: 0.03, z: 0.004),
                    Point3D(x: 0.0, y: 0.03, z: -0.004),
                    Point3D(x: 0.02, y: 0.03, z: 0.004),
                ],
            ]
        ))
        let offset = Surface3D.procedural(.offset(OffsetSurface3D(
            source: source,
            distance: 0.0005
        )))
        let parameters = try box(
            u: 0.799_999_998 ... 0.799_999_999,
            v: 0.1 ... 0.100_000_000_745
        )

        let sourceEnclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: source,
            over: parameters,
            tolerance: ModelingTolerance.standard
        )
        let bounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(
            of: offset,
            over: parameters,
            tolerance: ModelingTolerance.standard
        )

        try verifySamples(
            of: source,
            in: parameters,
            enclosure: sourceEnclosure,
            sampleCount: 3
        )
        #expect(sourceEnclosure.tangentU.x.width < 1.0e-9)
        #expect(sourceEnclosure.secondDerivativeUU.z.width < 1.0e-9)
        #expect(bounds.tangentUMagnitudeUpperBound < 0.1)
        #expect(bounds.tangentVMagnitudeUpperBound < 0.1)
        #expect(bounds.unitNormalDerivativeUMagnitudeUpperBound < 100.0)
        #expect(bounds.unitNormalDerivativeVMagnitudeUpperBound < 100.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func affineBSplineEnclosureRemainsConditionedOnNearlyConstantParameter() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D.bilinearPatch(
            bottomLeft: .origin,
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        ))
        let parameters = SurfaceParameterBox(
            u: try ScalarInterval(lower: 0.5.nextDown, upper: 0.5.nextUp),
            v: try ScalarInterval(lower: 0.17, upper: 0.83)
        )

        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )

        try verifySamples(
            of: surface,
            in: parameters,
            enclosure: enclosure,
            sampleCount: 5
        )
        #expect(enclosure.tangentU.x.contains(1.0))
        #expect(enclosure.tangentU.y.contains(0.0))
        #expect(enclosure.tangentU.z.contains(0.0))
        #expect(enclosure.tangentU.x.width < 1.0e-3)
        #expect(enclosure.tangentV.y.width < 1.0e-3)
    }

    @Test(.timeLimit(.minutes(1)))
    func fullPeriodicSpanIncludesEveryTrigonometricExtremum() throws {
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 4.0,
            minorRadius: 1.0
        ))
        let parameters = try box(
            u: -Double.pi ... Double.pi,
            v: -Double.pi ... Double.pi
        )

        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )

        try verifySamples(
            of: surface,
            in: parameters,
            enclosure: enclosure,
            sampleCount: 17
        )
        #expect(enclosure.position.x.contains(-5.0))
        #expect(enclosure.position.x.contains(5.0))
        #expect(enclosure.position.y.contains(-5.0))
        #expect(enclosure.position.y.contains(5.0))
    }

    @Test(.timeLimit(.minutes(1)))
    func boxOutsideClosedDomainIsRejected() throws {
        let surface = Surface3D.bSpline(makeRationalSurface())
        let parameters = try box(u: -0.01 ... 0.5, v: 0.2 ... 0.8)

        #expect(throws: KernelError.self) {
            try DefaultSurfaceDifferentialEncloser().enclosure(
                of: surface,
                over: parameters,
                tolerance: tolerance
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func intervalUnaryCompositionContainsMixedThirdDerivative() throws {
        let u = SurfaceIntervalJet.parameterU(try ScalarInterval(
            lower: 0.2 - 1.0e-9,
            upper: 0.2 + 1.0e-9
        ))
        let v = SurfaceIntervalJet.parameterV(try ScalarInterval(
            lower: 0.3 - 1.0e-9,
            upper: 0.3 + 1.0e-9
        ))
        let argument = SurfaceIntervalJet.constant(4.0)
            + SurfaceIntervalJet.constant(2.0) * u
            + SurfaceIntervalJet.constant(3.0) * v
        let result = try #require(argument.squareRoot())
        let argumentAtCenter = 4.0 + 2.0 * 0.2 + 3.0 * 0.3
        let expected = 4.5 / pow(argumentAtCenter, 2.5)

        #expect(result.thirdDerivativeUUV.lower <= expected)
        #expect(result.thirdDerivativeUUV.upper >= expected)
    }

    private func verifySamples(
        of surface: Surface3D,
        in parameters: SurfaceParameterBox,
        enclosure: SurfaceDifferentialEnclosure,
        sampleCount: Int
    ) throws {
        for vIndex in 0..<sampleCount {
            let vFraction = Double(vIndex) / Double(sampleCount - 1)
            let v = parameters.v.lower + parameters.v.width * vFraction
            for uIndex in 0..<sampleCount {
                let uFraction = Double(uIndex) / Double(sampleCount - 1)
                let u = parameters.u.lower + parameters.u.width * uFraction
                let derivatives = try surface.parameterDerivatives(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect(enclosure.position.contains(derivatives.position))
                #expect(enclosure.tangentU.contains(derivatives.tangentU))
                #expect(enclosure.tangentV.contains(derivatives.tangentV))
                #expect(enclosure.secondDerivativeUU.contains(derivatives.secondDerivativeUU))
                #expect(enclosure.secondDerivativeUV.contains(derivatives.secondDerivativeUV))
                #expect(enclosure.secondDerivativeVV.contains(derivatives.secondDerivativeVV))
            }
        }
    }

    private func box(
        u: ClosedRange<Double>,
        v: ClosedRange<Double>
    ) throws -> SurfaceParameterBox {
        SurfaceParameterBox(
            u: try ScalarInterval(lower: u.lowerBound, upper: u.upperBound),
            v: try ScalarInterval(lower: v.lowerBound, upper: v.upperBound)
        )
    }

    private func makeRationalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.3),
                    Point3D(x: 2.0, y: 0.0, z: -0.2),
                    Point3D(x: 3.0, y: 0.0, z: 0.1),
                ],
                [
                    Point3D(x: -0.1, y: 1.0, z: 0.4),
                    Point3D(x: 1.1, y: 1.0, z: 1.0),
                    Point3D(x: 2.2, y: 1.0, z: 0.5),
                    Point3D(x: 3.1, y: 1.0, z: 0.2),
                ],
                [
                    Point3D(x: 0.2, y: 2.0, z: -0.1),
                    Point3D(x: 0.9, y: 2.0, z: 0.7),
                    Point3D(x: 2.0, y: 2.0, z: 0.9),
                    Point3D(x: 2.8, y: 2.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 3.0, z: 0.2),
                    Point3D(x: 1.2, y: 3.0, z: 0.1),
                    Point3D(x: 1.9, y: 3.0, z: 0.4),
                    Point3D(x: 3.0, y: 3.0, z: -0.2),
                ],
            ],
            weights: [
                [1.0, 0.8, 1.2, 1.0],
                [0.9, 1.3, 0.75, 1.1],
                [1.2, 0.85, 1.4, 0.95],
                [1.0, 1.1, 0.9, 1.25],
            ]
        )
    }
}
