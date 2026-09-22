import CADCore
import Testing

@testable import CADGeometry

@Suite("Prepared surface differential enclosure")
struct PreparedSurfaceDifferentialEncloserTests {
  private let tolerance = ModelingTolerance(
    distance: 1.0e-10,
    angle: 1.0e-11,
    relative: 1.0e-12
  )

  @Test(.timeLimit(.minutes(1)))
  func preparedEvaluationIsExactlyEquivalentToOneShotEvaluation() throws {
    let bSpline = Surface3D.bSpline(makeCurvedSurface())
    let source = makeCurvedSurface()
    let rational = Surface3D.bSpline(BSplineSurface3D(
      uDegree: source.uDegree, vDegree: source.vDegree,
      uKnots: source.uKnots, vKnots: source.vKnots,
      controlPoints: source.controlPoints,
      weights: [[1, 0.9, 1], [0.9, 0.8, 0.9], [1, 0.9, 1]]))
    let ruled = Surface3D.procedural(
      .ruled(
        RuledSurface3D(
          startBoundary: .bSpline(makeBoundaryCurve(z: 0.0)),
          endBoundary: .bSpline(makeBoundaryCurve(z: 1.0))
        )))
    let surfaces: [Surface3D] = [
      .analytic(.sphere(center: .origin, radius: 2.0)),
      bSpline,
      rational,
      ruled,
      .procedural(
        .offset(
          OffsetSurface3D(
            source: bSpline,
            distance: 0.12
          ))),
    ]
    let parameters = SurfaceParameterBox(
      u: try ScalarInterval(lower: 0.25, upper: 0.45),
      v: try ScalarInterval(lower: 0.35, upper: 0.55)
    )

    for surface in surfaces {
      let prepared = try PreparedSurfaceDifferentialEncloser(
        surface: surface, tolerance: tolerance)
      for parameters in [parameters,
        SurfaceParameterBox(u: try ScalarInterval(lower: 0.65, upper: 0.85),
                            v: try ScalarInterval(lower: 0.1, upper: 0.2)), parameters] {
        let expected = try DefaultSurfaceDifferentialEncloser().intervalJet(
          of: surface,
          over: parameters,
          tolerance: tolerance
        )
        let actual = try prepared.intervalJet(
          over: parameters,
          tolerance: tolerance
        )

        expectExactlyEqual(actual, expected)
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func preparedDerivativeNetsAreReusedAcrossRepeatedBoxes() throws {
    let surface = makeCurvedSurface()
    let patch = RationalBezierSurfacePatch3D(controlPoints: surface.controlPoints,
      weights: surface.weights, uLower: 0, uUpper: 1, vLower: 0, vUpper: 1)
    let encloser = RationalBezierSurfaceJetEncloser()
    let prepared = try encloser.prepare(patch, tolerance: tolerance)
    let u = try ScalarInterval(lower: 0.2, upper: 0.4)
    let v = try ScalarInterval(lower: 0.6, upper: 0.8)
    let clock = ContinuousClock()
    var directSum = 0.0, preparedSum = 0.0
    let start = clock.now
    for _ in 0..<100 {
      directSum += try encloser.enclosure(of: patch, u: u, v: v,
                                        tolerance: tolerance).x.value.lower
    }
    let middle = clock.now
    for _ in 0..<100 {
      preparedSum += try encloser.enclosure(of: prepared, u: u, v: v,
                                          tolerance: tolerance).x.value.lower
    }
    let end = clock.now
    #expect(directSum == preparedSum)
    print("100 patch jets: direct=\(start.duration(to: middle)), prepared=\(middle.duration(to: end))")
  }

  @Test(.timeLimit(.minutes(1)))
  func preparedEvaluationStillRejectsABoxOutsideTheSurfaceDomain() throws {
    let surface = Surface3D.bSpline(makeCurvedSurface())
    let prepared = try PreparedSurfaceDifferentialEncloser(
      surface: surface,
      tolerance: tolerance
    )
    let invalidParameters = SurfaceParameterBox(
      u: try ScalarInterval(lower: -0.1, upper: 0.2),
      v: try ScalarInterval(lower: 0.3, upper: 0.6)
    )

    do {
      _ = try prepared.intervalJet(
        over: invalidParameters,
        tolerance: tolerance
      )
      Issue.record("Prepared evaluation must retain parameter-domain validation.")
    } catch let error as KernelError {
      #expect(error.phase == .geometry)
      #expect(error.code == .invalidInput)
      #expect(error.tolerance == tolerance)
    }
  }

  private func makeCurvedSurface() -> BSplineSurface3D {
    let zValues: [[Double]] = [
      [0.0, 0.05, 0.20],
      [0.075, 0.18, 0.35],
      [0.30, 0.42, 0.65],
    ]
    return BSplineSurface3D(
      uDegree: 2,
      vDegree: 2,
      uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      controlPoints: (0..<3).map { vIndex in
        (0..<3).map { uIndex in
          Point3D(
            x: Double(uIndex) * 0.5,
            y: Double(vIndex) * 0.5,
            z: zValues[vIndex][uIndex]
          )
        }
      }
    )
  }

  private func makeBoundaryCurve(z: Double) -> BSplineCurve3D {
    BSplineCurve3D(
      degree: 2,
      knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      controlPoints: [
        Point3D(x: 0.0, y: 0.0, z: z),
        Point3D(x: 0.5, y: 0.25, z: z + 0.1),
        Point3D(x: 1.0, y: 0.0, z: z),
      ]
    )
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
}
