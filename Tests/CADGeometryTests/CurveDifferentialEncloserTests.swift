import CADCore
import Foundation
import Testing

@testable import CADGeometry

@Suite("Certified curve differential enclosures")
struct CurveDifferentialEncloserTests {
  @Test func intervalPullbackRetainsMixedTermsThroughThirdOrder() throws {
    for lower in [-0.6, 0.2] {
      let range = try ScalarInterval(lower: lower, upper: lower + 0.01)
      let t = SurfaceIntervalJet.parameterU(range)
      let u = t * t, v = t * t * t
      let su = SurfaceIntervalJet.parameterU(try ScalarInterval(lower: u.value.lower, upper: u.value.upper))
      let sv = SurfaceIntervalJet.parameterV(try ScalarInterval(lower: v.value.lower, upper: v.value.upper))
      let surface = SurfaceIntervalVectorJet(x: su * su * su + su * sv * sv,
        y: su * su * sv + sv * sv * sv, z: su * sv)
      let result = SurfaceParameterThirdOrderChainRule.intervalJet(surface: surface, u: u, v: v)
      // The composed coordinates are t^6 + t^8, t^7 + t^9, and t^5.
      for value in [range.lower, range.midpoint, range.upper] {
        let derivatives: [(SurfaceIntervalJet, Double, Double, Double)] = [
          (result.x, 6 * pow(value, 5) + 8 * pow(value, 7),
           30 * pow(value, 4) + 56 * pow(value, 6), 120 * pow(value, 3) + 336 * pow(value, 5)),
          (result.y, 7 * pow(value, 6) + 9 * pow(value, 8),
           42 * pow(value, 5) + 72 * pow(value, 7), 210 * pow(value, 4) + 504 * pow(value, 6)),
          (result.z, 5 * pow(value, 4), 20 * pow(value, 3), 60 * pow(value, 2))
        ]
        for (jet, first, second, third) in derivatives {
          #expect(jet.derivativeU.lower <= first && first <= jet.derivativeU.upper)
          #expect(jet.secondDerivativeUU.lower <= second && second <= jet.secondDerivativeUU.upper)
          #expect(jet.thirdDerivativeUUU.lower <= third && third <= jet.thirdDerivativeUUU.upper)
        }
      }
    }
  }

  private let tolerance = ModelingTolerance(
    distance: 1.0e-9,
    angle: 1.0e-10,
    relative: 1.0e-11
  )

  @Test(.timeLimit(.minutes(1)))
  func analyticEnclosuresContainSecondOrderDifferentials() throws {
    let hyperbola = Hyperbola3D(
      center: Point3D(x: 0.2, y: -0.5, z: 0.7),
      normal: .unitZ,
      transverseAxis: .unitX,
      transverseRadius: 1.3,
      conjugateRadius: 0.8
    )
    let parabola = Parabola3D(
      vertex: Point3D(x: -0.2, y: 0.4, z: 0.1),
      normal: .unitZ,
      axis: .unitX,
      focalLength: 0.9
    )
    let cases: [(Curve3D, ScalarInterval)] = [
      (
        .line(Line3D(origin: .origin, direction: .unitX)),
        try interval(-2.0...3.0)
      ),
      (
        .circle(Circle3D(center: .origin, normal: .unitZ, radius: 2.0)),
        try interval(5.7...6.8)
      ),
      (
        .analytic(
          .ellipse(
            center: Point3D(x: 0.3, y: -0.1, z: 0.8),
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.4,
            minorRadius: 0.7
          )),
        try interval(-0.8...2.2)
      ),
      (
        .analytic(.hyperbola(hyperbola)),
        try interval(-1.1...0.9)
      ),
      (
        .analytic(.parabola(parabola)),
        try interval(-1.7...2.3)
      ),
    ]

    for (curve, parameters) in cases {
      try verifySamples(
        of: curve,
        in: parameters,
        enclosure: DefaultCurveDifferentialEncloser().enclosure(
          of: curve,
          over: parameters,
          tolerance: tolerance
        ),
        sampleCount: 17
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rationalBSplineAndRigidImageEnclosuresContainDifferentials() throws {
    let source = Curve3D.bSpline(
      BSplineCurve3D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: [
          Point3D(x: 0.0, y: 0.0, z: 0.0),
          Point3D(x: 0.8, y: 1.2, z: -0.2),
          Point3D(x: 1.7, y: -0.4, z: 0.9),
          Point3D(x: 2.8, y: 0.6, z: 0.3),
        ],
        weights: [1.0, 0.7, 1.4, 0.9]
      ))
    let transform = try RigidTransform3D.rotated(
      around: Point3D(x: 0.2, y: -0.1, z: 0.4),
      direction: Vector3D(x: 1.0, y: 2.0, z: -0.5),
      angle: 0.73,
      tolerance: tolerance
    )
    let rigid = Curve3D.rigidImage(
      try RigidImageCurve3D(
        source: source,
        transform: transform,
        tolerance: tolerance
      ))
    let parameters = try interval(0.13...0.91)

    for curve in [source, rigid] {
      let enclosure = try DefaultCurveDifferentialEncloser().enclosure(
        of: curve,
        over: parameters,
        tolerance: tolerance
      )
      try verifySamples(
        of: curve,
        in: parameters,
        enclosure: enclosure,
        sampleCount: 23
      )
      let decoded = try JSONDecoder().decode(
        CurveDifferentialEnclosure.self,
        from: JSONEncoder().encode(enclosure)
      )
      #expect(decoded == enclosure)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func implicitGraphEnclosureContainsExactLineDifferentials() throws {
    let curve = Curve3D.implicit(try certifiedImplicitLine())
    let parameters = try interval(0.17...0.83)

    let enclosure = try DefaultCurveDifferentialEncloser().enclosure(
      of: curve,
      over: parameters,
      tolerance: tolerance
    )

    try verifySamples(
      of: curve,
      in: parameters,
      enclosure: enclosure,
      sampleCount: 15
    )
    #expect(enclosure.secondDerivative.contains(.zero))
  }

  @Test(.timeLimit(.minutes(1)))
  func intervalOutsideClosedDomainIsRejected() throws {
    let curve = Curve3D.bSpline(
      BSplineCurve3D(
        degree: 1,
        knots: [0.0, 0.0, 1.0, 1.0],
        controlPoints: [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)]
      ))

    #expect(throws: KernelError.self) {
      try DefaultCurveDifferentialEncloser().enclosure(
        of: curve,
        over: interval(-0.1...0.5),
        tolerance: tolerance
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func preparedEvaluationIsExactlyEquivalentToOneShotEvaluation() throws {
    let bSpline = Curve3D.bSpline(
      BSplineCurve3D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: [
          Point3D(x: 0.0, y: 0.0, z: 0.0),
          Point3D(x: 0.5, y: 0.8, z: -0.2),
          Point3D(x: 1.0, y: 0.1, z: 0.4),
        ],
        weights: [1.0, 0.8, 1.2]
      ))
    let rigidTransform = try RigidTransform3D.rotated(
      around: .origin,
      direction: Vector3D(x: 1.0, y: 2.0, z: 3.0),
      angle: 0.4,
      tolerance: tolerance
    )
    let affineTransform = try AffineTransform3D(
      basisX: Vector3D(x: 1.2, y: 0.1, z: 0.0),
      basisY: Vector3D(x: -0.2, y: 0.9, z: 0.2),
      basisZ: Vector3D(x: 0.1, y: 0.0, z: 1.1),
      translation: Vector3D(x: 0.3, y: -0.4, z: 0.2)
    )
    let curves: [Curve3D] = [
      .line(Line3D(origin: .origin, direction: .unitX)),
      bSpline,
      .implicit(try certifiedImplicitLine()),
      .rigidImage(
        try RigidImageCurve3D(
          source: bSpline,
          transform: rigidTransform,
          tolerance: tolerance
        )),
      .affineImage(
        try AffineImageCurve3D(
          source: bSpline,
          transform: affineTransform,
          tolerance: tolerance
        )),
      .surfaceLift(
        SurfaceLiftCurve3D(
          surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
          parameterCurve: .affine(
            origin: Point2D(x: 0.0, y: 0.0),
            direction: Point2D(x: 1.0, y: 0.5),
            startParameter: 0.0,
            endParameter: 1.0
          )
        )),
    ]
    let parameters = try interval(0.17...0.83)

    for curve in curves {
      let expected = try DefaultCurveDifferentialEncloser()
        .thirdOrderIntervalJet(
          of: curve,
          over: parameters,
          tolerance: tolerance
        )
      let actual = try PreparedCurveDifferentialEncloser(
        curve: curve,
        tolerance: tolerance
      ).thirdOrderIntervalJet(
        over: parameters,
        tolerance: tolerance
      )
      expectExactlyEqual(actual, expected)
    }
  }

  private func verifySamples(
    of curve: Curve3D,
    in parameters: ScalarInterval,
    enclosure: CurveDifferentialEnclosure,
    sampleCount: Int
  ) throws {
    for index in 0..<sampleCount {
      let fraction = Double(index) / Double(sampleCount - 1)
      let parameter = parameters.lower + parameters.width * fraction
      let derivatives = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      #expect(enclosure.position.contains(derivatives.position))
      #expect(enclosure.firstDerivative.contains(derivatives.firstDerivative))
      #expect(enclosure.secondDerivative.contains(derivatives.secondDerivative))
    }
  }

  private func expectExactlyEqual(
    _ actual: SurfaceIntervalVectorJet,
    _ expected: SurfaceIntervalVectorJet
  ) {
    let actualComponents = scalarComponents(of: actual)
    let expectedComponents = scalarComponents(of: expected)
    #expect(actualComponents.count == expectedComponents.count)
    for (actual, expected) in zip(actualComponents, expectedComponents) {
      #expect(actual.lower == expected.lower)
      #expect(actual.upper == expected.upper)
    }
  }

  private func scalarComponents(
    of jet: SurfaceIntervalVectorJet
  ) -> [OutwardScalarInterval] {
    scalarComponents(of: jet.x)
      + scalarComponents(of: jet.y)
      + scalarComponents(of: jet.z)
  }

  private func scalarComponents(
    of jet: SurfaceIntervalJet
  ) -> [OutwardScalarInterval] {
    [
      jet.value,
      jet.derivativeU,
      jet.derivativeV,
      jet.secondDerivativeUU,
      jet.secondDerivativeUV,
      jet.secondDerivativeVV,
      jet.thirdDerivativeUUU,
      jet.thirdDerivativeUUV,
      jet.thirdDerivativeUVV,
      jet.thirdDerivativeVVV,
    ]
  }

  private func certifiedImplicitLine() throws -> CertifiedImplicitIntersectionCurve {
    let first = horizontalSurface()
    let second = verticalSurface()
    let parameterBox = SurfaceIntersectionParameterBox(
      firstU: try interval(0.0...1.0),
      firstV: try interval(0.0...1.0),
      secondU: try interval(0.0...1.0),
      secondV: try interval(0.0...1.0)
    )
    let anchors = (
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: 0.0),
        second: SurfaceParameter(u: 1.0 / 3.0, v: 0.5)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: 0.5),
        second: SurfaceParameter(u: 0.5, v: 0.5)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: 1.0),
        second: SurfaceParameter(u: 2.0 / 3.0, v: 0.5)
      )
    )
    let cell = try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox,
      freeParameter: .firstV,
      direction: .forward,
      lowerAnchor: anchors.0,
      midpointAnchor: anchors.1,
      upperAnchor: anchors.2,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
    return try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [cell],
      isClosed: false,
      tolerance: tolerance
    )
  }

  private func horizontalSurface() -> BSplineSurface3D {
    BSplineSurface3D(
      uDegree: 1,
      vDegree: 1,
      uKnots: [0.0, 0.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [
        [
          Point3D(x: 0.0, y: 0.0, z: 0.0),
          Point3D(x: 1.0, y: 0.0, z: 0.0),
        ],
        [
          Point3D(x: 0.0, y: 1.0, z: 0.0),
          Point3D(x: 1.0, y: 1.0, z: 0.0),
        ],
      ],
      weights: [[1.0, 1.0], [1.0, 1.0]]
    )
  }

  private func verticalSurface() -> BSplineSurface3D {
    BSplineSurface3D(
      uDegree: 1,
      vDegree: 1,
      uKnots: [0.0, 0.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [
        [
          Point3D(x: 0.5, y: -1.0, z: -1.0),
          Point3D(x: 0.5, y: 2.0, z: -1.0),
        ],
        [
          Point3D(x: 0.5, y: -1.0, z: 1.0),
          Point3D(x: 0.5, y: 2.0, z: 1.0),
        ],
      ],
      weights: [[1.0, 1.0], [1.0, 1.0]]
    )
  }

  private func interval(_ range: ClosedRange<Double>) throws -> ScalarInterval {
    try ScalarInterval(lower: range.lowerBound, upper: range.upperBound)
  }
}
