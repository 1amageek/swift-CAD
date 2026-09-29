import CADCore
import Testing
@testable import CADGeometry

@Suite("Native rational offset transition", .timeLimit(.minutes(1)))
struct RationalOffsetTransitionTests {
  private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)

  @Test func sweepHeightDoesNotDependOnProfileParameter() throws {
    let surface = source()
    let patches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface: surface, tolerance: tolerance)
    #expect(patches.count == 1)
    #expect(patches.first?.controlPoints == surface.controlPoints)
    #expect(patches.first?.weights == surface.weights)
    let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.2, upper: 0.8),
                                  v: try ScalarInterval(lower: 0.8, upper: 1))
    let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
      of: .bSpline(surface), over: box, tolerance: tolerance)
    // Every row has constant Z and identical profile weights; W(u) cancels.
    #expect(abs(jet.z.derivativeU.lower) < 1e-12)
    #expect(abs(jet.z.derivativeU.upper) < 1e-12)
  }

  @Test func remoteOffsetBoxExcludesCapHeight() throws {
    let surface = Surface3D.procedural(.offset(OffsetSurface3D(
      source: .bSpline(source()), distance: -0.0001)))
    let box = SurfaceParameterBox(
      u: try ScalarInterval(lower: 0, upper: 0.2952190500983024),
      v: try ScalarInterval(lower: 0, upper: 0.22992083415628778))
    let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
      of: surface, over: box, tolerance: tolerance)
    #expect(jet.z.value.upper < 0.0099)
  }

  @Test func nativeTransitionProducesOneCertifiedContactComponent() throws {
    let first = Surface3D.procedural(.offset(OffsetSurface3D(source: .bSpline(source()), distance: -0.0001)))
    let second = Surface3D.procedural(.offset(OffsetSurface3D(
      source: .plane(Plane3D(origin: Point3D(x: 0.029383780798362995, y: -0.0026159942648551634, z: 0.01), normal: .unitZ)), distance: -0.0001)))
    let results = try DefaultSurfaceSurfaceIntersector().intersections(
      first: first, second: second,
      options: .init(maximumSubdivisionCells: 4096, maximumRootAttempts: 4096), tolerance: tolerance)
    #expect(results.count == 1)
    guard case let .curve(component) = try #require(results.first),
          case let .closed(lower, upper) = component.curve.parameterDomain else {
      Issue.record("The native transition requires a bounded contact curve."); return
    }
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try component.curve.point(at: lower + (upper - lower) * fraction, tolerance: tolerance)
      let uvA = try component.surfaceParameter(on: .first, atNormalizedFraction: fraction, tolerance: tolerance)
      let uvB = try component.surfaceParameter(on: .second, atNormalizedFraction: fraction, tolerance: tolerance)
      let a = try first.point(u: uvA.u, v: uvA.v, tolerance: tolerance)
      let b = try second.point(u: uvB.u, v: uvB.v, tolerance: tolerance)
      #expect((point - a).length <= tolerance.distance)
      #expect((point - b).length <= tolerance.distance)
    }
    let evaluator = try RollingBallSectionEvaluator(
      first: OffsetSurface3D(source: .bSpline(source()), distance: -0.0001),
      second: OffsetSurface3D(source: .plane(Plane3D(
        origin: Point3D(x: 0.029383780798362995, y: -0.0026159942648551634, z: 0.01),
        normal: .unitZ)), distance: -0.0001),
      intersection: component, tolerance: tolerance)
    let rail = Curve3D.surfaceLift(try evaluator.contactCurve(
      on: .first, fromCurveParameter: lower, toCurveParameter: upper,
      options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536)))
    let blend = try evaluator.blendSurface(fromCurveParameter: lower, toCurveParameter: upper,
      options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
    let validator = DefaultCurveSurfaceCorrespondenceValidator()
    let boundaryOptions = CurveSurfaceCorrespondenceValidationOptions(
      maximumSubdivisionDepth: 1, maximumCellCount: 1)
    for v in [0.0, 1.0] {
      for span in [(0.0, 1.0), (0.8, 0.2)] {
        try validator.validate(curve: v == 0 ? blend.firstContact : blend.secondContact,
          from: span.0, to: span.1, surface: .procedural(.rollingBall(blend)),
          parameterCurve: .constantV(v: v, uStart: span.0, uEnd: span.1),
          options: boundaryOptions, tolerance: tolerance)
      }
    }
    #expect(throws: KernelError.self) {
      try validator.validate(curve: blend.secondContact, from: 0, to: 1,
        surface: .procedural(.rollingBall(blend)),
        parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1),
        options: boundaryOptions, tolerance: tolerance)
    }
    let wrongRadius = RollingBallBlendSurface3D(centerSpine: blend.centerSpine,
      firstContact: blend.firstContact, secondContact: blend.secondContact,
      radius: blend.radius * 2, tolerance: tolerance)
    #expect(try wrongRadius.contactBoundaryDeviation(onFirst: true) == nil)
    let interval = try ScalarInterval(lower: 0.4, upper: 0.6)
    let direct = try #require(try DefaultCurveDifferentialEncloser().directJet(
      rail, parameters: interval, tolerance: tolerance))
    let range = try #require(try DefaultCurveSpatialDerivativeRangeResolver().derivativeRange(
      curve: rail, interval: interval, tolerance: tolerance))
    #expect(range.x == (try ScalarInterval(lower: direct.x.derivativeU.lower, upper: direct.x.derivativeU.upper)))
    #expect(range.y == (try ScalarInterval(lower: direct.y.derivativeU.lower, upper: direct.y.derivativeU.upper)))
    #expect(range.z == (try ScalarInterval(lower: direct.z.derivativeU.lower, upper: direct.z.derivativeU.upper)))
    let prepared = try PreparedCurveDifferentialEncloser(curve: rail, tolerance: tolerance)
    for bounds in [(0.1, 0.2), (0.4, 0.6), (0.8, 0.9)] {
      let span = try ScalarInterval(lower: bounds.0, upper: bounds.1)
      let expected = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
        of: rail, over: span, tolerance: tolerance)
      let actual = try prepared.thirdOrderIntervalJet(over: span, tolerance: tolerance)
      let components: [KeyPath<SurfaceIntervalVectorJet, SurfaceIntervalJet>] = [\.x, \.y, \.z]
      let derivatives: [KeyPath<SurfaceIntervalJet, OutwardScalarInterval>] = [
        \.value, \.derivativeU, \.derivativeV, \.secondDerivativeUU,
        \.secondDerivativeUV, \.secondDerivativeVV, \.thirdDerivativeUUU,
        \.thirdDerivativeUUV, \.thirdDerivativeUVV, \.thirdDerivativeVVV]
      for component in components {
        for derivative in derivatives {
          let a = actual[keyPath: component][keyPath: derivative]
          let b = expected[keyPath: component][keyPath: derivative]
          #expect(a.lower == b.lower)
          #expect(a.upper == b.upper)
        }
      }
    }
  }

  // Captured without approximation from span 17 of the native 32-tooth helical fixture.
  private func source() -> BSplineSurface3D {
    BSplineSurface3D(uDegree: 2, vDegree: 3,
      uKnots: [0,0,0,1,1,1], vKnots: [0,0,0,0,1,1,1,1],
      controlPoints: [
      [Point3D(x: -0.029780568169755543, y: -0.004921277021059068, z: 0.005),
       Point3D(x: -0.029103301569088205, y: -0.00486921333019939, z: 0.005),
       Point3D(x: -0.0289758206405986, y: -0.005536408420976335, z: 0.005)],
      [Point3D(x: -0.029944610737124178, y: -0.003928591415400549, z: 0.006666666666666666),
       Point3D(x: -0.029265608680094847, y: -0.0038991032778964503, z: 0.006666666666666666),
       Point3D(x: -0.029160367587964482, y: -0.004570547732956381, z: 0.006666666666666666)],
      [Point3D(x: -0.030058977430385173, y: -0.0029276985067880294, z: 0.008333333333333333),
       Point3D(x: -0.029379369637260372, y: -0.0029208727300879915, z: 0.008333333333333333),
       Point3D(x: -0.029296580989534478, y: -0.003595453624800582, z: 0.008333333333333333)],
      [Point3D(x: -0.030123097272530847, y: -0.0019235952643703344, z: 0.01),
       Point3D(x: -0.029444016487721388, y: -0.0019394055138306117, z: 0.01),
       Point3D(x: -0.029383780798362978, y: -0.0026159942648551495, z: 0.01)]
      ], weights: Array(repeating: [1,0.7455996185514348,1], count: 4))
  }
}
