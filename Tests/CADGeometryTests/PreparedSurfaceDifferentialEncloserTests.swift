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
    let ruled = Surface3D.procedural(
      .ruled(
        RuledSurface3D(
          startBoundary: .bSpline(makeBoundaryCurve(z: 0.0)),
          endBoundary: .bSpline(makeBoundaryCurve(z: 1.0))
        )))
    let surfaces: [Surface3D] = [
      .analytic(.sphere(center: .origin, radius: 2.0)),
      bSpline,
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
      let expected = try DefaultSurfaceDifferentialEncloser().intervalJet(
        of: surface,
        over: parameters,
        tolerance: tolerance
      )
      let prepared = try PreparedSurfaceDifferentialEncloser(
        surface: surface,
        tolerance: tolerance
      )
      let actual = try prepared.intervalJet(
        over: parameters,
        tolerance: tolerance
      )

      expectExactlyEqual(actual, expected)
    }
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
