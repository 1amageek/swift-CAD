import CADCore
import Foundation
import Testing

@testable import CADGeometry

@Suite("Certified Implicit Intersection Curve")
struct CertifiedImplicitIntersectionCurveTests {
  private let tolerance = ModelingTolerance.standard

  @Test func lowerOrderEvaluationRetainsNonlinearImplicitDerivatives() throws {
    let first = Surface3D.bSpline(horizontalSurface())
    let second = Surface3D.bSpline(BSplineSurface3D(uDegree: 3, vDegree: 1,
      uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
      controlPoints: [-0.5, 0.5].map { z in
        [Point3D(x: 0, y: 0, z: z), Point3D(x: 0, y: 1.0 / 3, z: z),
         Point3D(x: 0, y: 2.0 / 3, z: z), Point3D(x: 1, y: 1, z: z)]
      }, weights: [[1, 1, 1, 1], [1, 1, 1, 1]]))
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try .init(first: .init(u: t * t * t, v: t), second: .init(u: t, v: 0.5))
    }
    let cell = try CertifiedImplicitIntersectionGraphCell(
      parameterBox: .init(firstU: ScalarInterval(lower: 0, upper: 1),
        firstV: ScalarInterval(lower: 0.4, upper: 0.6),
        secondU: ScalarInterval(lower: 0.35, upper: 0.65), secondV: ScalarInterval(lower: 0, upper: 1)),
      freeParameter: .firstV, direction: .forward,
      lowerAnchor: anchor(0.4), midpointAnchor: anchor(0.5), upperAnchor: anchor(0.6),
      firstSurface: first, secondSurface: second, tolerance: tolerance)
    let implicit = try CertifiedImplicitIntersectionCurve(firstSurface: first, secondSurface: second,
      cells: [cell], isClosed: false, tolerance: tolerance)
    for fraction in [0.0, 0.17, 0.63, 1.0] {
      let t = 0.4 + 0.2 * fraction
      let lower = try Curve3D.implicit(implicit).differentialGeometry(at: fraction, tolerance: tolerance)
      let full = try implicit.differential(atNormalizedFraction: fraction, tolerance: tolerance)
      #expect((lower.position - Point3D(x: t * t * t, y: t, z: 0)).length <= tolerance.distance)
      #expect((lower.firstDerivative - Vector3D(x: 0.6 * t * t, y: 0.2, z: 0)).length <= tolerance.relative)
      #expect((lower.secondDerivative - Vector3D(x: 0.24 * t, y: 0, z: 0)).length <= tolerance.relative)
      #expect((lower.firstDerivative - full.firstDerivative).length <= tolerance.relative)
      #expect((lower.secondDerivative - full.secondDerivative).length <= tolerance.relative)
      #expect(abs(full.thirdDerivative.x - 0.048) <= tolerance.relative)
    }
  }

  @Test func implicitLiftBoundsRespectRequestedSubinterval() throws {
    let intersection = try certifiedLineCurve()
    for role in [SurfaceIntersectionSurfaceRole.first, .second] {
      for (start, end) in [(0.2, 0.8), (0.8, 0.2)] {
        let pcurve = try CertifiedImplicitSurfaceParameterCurve(
          intersection: intersection, role: role,
          startFraction: start, endFraction: end, tolerance: tolerance)
        let lift = SurfaceLiftCurve3D(
          surface: role == .first ? intersection.firstSurface : intersection.secondSurface,
          parameterCurve: .certifiedImplicit(pcurve))
        let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
          of: .surfaceLift(lift), over: ScalarInterval(lower: 0.25, upper: 0.75), tolerance: tolerance)
        #expect(jet.y.derivativeU.lower <= end - start && jet.y.derivativeU.upper >= end - start)
        #expect(jet.y.derivativeU.width < 1e-6)
        #expect(jet.x.derivativeU.absoluteUpperBound < 1e-6)
        #expect(jet.z.thirdDerivativeUUU.absoluteUpperBound < 1e-6)
        for width in [0.01, tolerance.relative * 0.5] {
          let interval = try ScalarInterval(lower: 0.25, upper: 0.25 + width)
          let box = try lift.boundingBox(over: interval, tolerance: tolerance)
          #expect(box.maximum.y - box.minimum.y <= abs(end - start) * width + tolerance.distance * 16)
          for fraction in [interval.lower, interval.midpoint, interval.upper] {
            let point = try lift.point(atNormalizedFraction: fraction, tolerance: tolerance)
            #expect(point.x >= box.minimum.x && point.x <= box.maximum.x)
            #expect(point.y >= box.minimum.y && point.y <= box.maximum.y)
            #expect(point.z >= box.minimum.z && point.z <= box.maximum.z)
          }
        }
      }
    }
  }

  @Test func tinyImplicitIntervalsRetainLocalPositionBounds() throws {
    let curve = try certifiedLineCurve()
    for encloser in [ImplicitCurveIntervalJetEncloser(),
                     try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)] {
      for lower in [0.0, 0.5, 1.0 - tolerance.relative * 0.5] {
        let interval = try ScalarInterval(lower: lower, upper: min(1, lower + tolerance.relative * 0.5))
        let jet = try encloser.parameterIntervalJet(of: curve, over: interval, tolerance: tolerance)
        let free = jet[.firstV]
        #expect(free.value.contains(interval.lower))
        #expect(free.value.contains(interval.upper))
        #expect(free.value.width < tolerance.relative * 32)
        #expect(free.firstDerivative.contains(1))
        #expect(free.secondDerivative.contains(0))
        #expect(free.thirdDerivative.contains(0))
      }
    }
  }

  @Test func implicitPcurveLiftRetainsTrimmedAndReversedDerivativeBounds() throws {
    let intersection = try certifiedLineCurve()
    for role in [SurfaceIntersectionSurfaceRole.first, .second] {
      for (start, end) in [(0.2, 0.8), (0.8, 0.2)] {
        let pcurve = try CertifiedImplicitSurfaceParameterCurve(
          intersection: intersection, role: role,
          startFraction: start, endFraction: end, tolerance: tolerance)
        let lift = SurfaceLiftCurve3D(
          surface: role == .first ? intersection.firstSurface : intersection.secondSurface,
          parameterCurve: .certifiedImplicit(pcurve))
        let interval = try ScalarInterval(lower: 0.25, upper: 0.75)
        let bounder = SurfaceLiftDifferentialBounder()
        let first = try #require(try bounder.firstDerivativeMagnitude(
          lift: lift, interval: interval, tolerance: tolerance))
        let second = try #require(try bounder.secondDerivativeMagnitude(
          lift: lift, interval: interval, tolerance: tolerance))
        let third = try #require(try bounder.thirdDerivativeMagnitude(
          lift: lift, interval: interval, tolerance: tolerance))
        #expect(first.isFinite && first >= 0.6 && first < 0.61)
        #expect(second.isFinite && second >= 0 && second < 1e-6)
        #expect(third.isFinite && third >= 0 && third < 1e-6)
        let bounds = try #require(try bounder.parameterBounds(.certifiedImplicit(pcurve), tolerance: tolerance))
        for fraction in [0.25, 0.5, 0.75] {
          let uv = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
          #expect(bounds.u.contains(uv.u) && bounds.v.contains(uv.v))
          let actual = try lift.differentialGeometry(atNormalizedFraction: fraction, tolerance: tolerance)
          #expect(actual.firstDerivative.length <= first)
          #expect(actual.secondDerivative.length <= second)
        }
      }
    }
  }

  @Test func planarSupportConnectsMultipleCellsAndRoundTrips() throws {
    let first = Surface3D.bSpline(horizontalSurface())
    let second = Surface3D.plane(Plane3D(
      origin: Point3D(x: 0.5, y: 0, z: 0), normal: .unitX))
    func anchor(_ y: Double) throws -> SurfaceIntersectionParameterPair {
      let p = try second.parameterProjection(
        of: Point3D(x: 0.5, y: y, z: 0), tolerance: tolerance)
      return try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: y),
        second: SurfaceParameter(u: p.u, v: p.v))
    }
    func cell(_ lower: Double, _ upper: Double) throws -> CertifiedImplicitIntersectionGraphCell {
      try CertifiedImplicitIntersectionGraphCell(
        parameterBox: SurfaceIntersectionParameterBox(
          firstU: ScalarInterval(lower: 0, upper: 1),
          firstV: ScalarInterval(lower: lower, upper: upper),
          secondU: ScalarInterval(lower: -2, upper: 2),
          secondV: ScalarInterval(lower: -2, upper: 2)),
        freeParameter: .firstV, direction: .forward,
        lowerAnchor: anchor(lower), midpointAnchor: anchor((lower + upper) / 2),
        upperAnchor: anchor(upper), firstSurface: first, secondSurface: second,
        tolerance: tolerance)
    }
    let lower = try cell(0, 0.5)
    let upper = try cell(0.5, 1)
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first, secondSurface: second, cells: [lower, upper],
      isClosed: false, tolerance: tolerance)
    let decoded = try JSONDecoder().decode(
      CertifiedImplicitIntersectionCurve.self, from: JSONEncoder().encode(curve))
    #expect(decoded == curve)
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try decoded.point(atNormalizedFraction: fraction, tolerance: tolerance)
      #expect(point.isApproximatelyEqual(to: Point3D(x: 0.5, y: fraction, z: 0),
        tolerance: tolerance.distance))
    }
    let disconnected = try cell(0.6, 1)
    do {
      _ = try CertifiedImplicitIntersectionCurve(
        firstSurface: first, secondSurface: second, cells: [lower, disconnected],
        isClosed: false, tolerance: tolerance)
      Issue.record("Disconnected planar-support graph cells must be rejected.")
    } catch let error as KernelError {
      #expect(error.code == .intersectionFailure)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func evaluatesTheUniqueRootOfARevalidatedKrawczykGraph() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let cell = try graphCell(first: first, second: second)
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [cell],
      isClosed: false,
      tolerance: tolerance
    )
    #expect(curve.maximumResidualUpperBound == tolerance.distance)

    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try curve.point(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let parameters = try curve.parameterPair(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      #expect(abs(point.x - 0.5) <= tolerance.distance)
      #expect(abs(point.y - fraction) <= tolerance.distance)
      #expect(abs(point.z) <= tolerance.distance)
      #expect(abs(parameters.first.u - 0.5) <= tolerance.distance)
      #expect(abs(parameters.first.v - fraction) <= tolerance.distance)
      #expect(abs(parameters.second.u - ((fraction + 1.0) / 3.0)) <= tolerance.distance)
      #expect(abs(parameters.second.v - 0.5) <= tolerance.distance)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsACellWhoseClaimedFreeParameterDoesNotReproduceTheProof() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let box = try parameterBox()
    let anchors = try anchorParameters()

    #expect(throws: KernelError.self) {
      _ = try CertifiedImplicitIntersectionGraphCell(
        parameterBox: box,
        freeParameter: .firstU,
        direction: .forward,
        lowerAnchor: anchors.lower,
        midpointAnchor: anchors.midpoint,
        upperAnchor: anchors.upper,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func proceduralSurfaceCellReconstructsARepresentationIndependentGraphProof() throws {
    let first = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(horizontalSurface()),
          distance: 0.25
        )))
    let second = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(verticalSurface()),
          distance: 0.1
        )))
    let anchors = try proceduralAnchorParameters()
    let cell = try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox(),
      freeParameter: .firstV,
      direction: .forward,
      lowerAnchor: anchors.lower,
      midpointAnchor: anchors.midpoint,
      upperAnchor: anchors.upper,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [cell],
      isClosed: false,
      tolerance: tolerance
    )

    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try curve.point(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      #expect(abs(point.x - 0.6) <= tolerance.distance)
      #expect(abs(point.y - fraction) <= tolerance.distance)
      #expect(abs(point.z - 0.25) <= tolerance.distance)
    }

    let derivativeBounds = try cell.parameterDerivativeBounds(
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
    #expect(derivativeBounds.count == 4)
    #expect(derivativeBounds[0].contains(0.0))
    #expect(derivativeBounds[1].contains(1.0))
    #expect(derivativeBounds[2].contains(1.0 / 3.0))
    #expect(derivativeBounds[3].contains(0.0))

    let firstPcurve = CertifiedImplicitSurfaceParameterCurve(
      validatedIntersection: curve,
      role: .first
    )
    let secondPcurve = CertifiedImplicitSurfaceParameterCurve(
      validatedIntersection: curve,
      role: .second
    )
    try firstPcurve.validate(on: first, tolerance: tolerance)
    try secondPcurve.validate(on: second, tolerance: tolerance)

    let bounds = try curve.boundingBox(
      fromNormalizedFraction: 0.0,
      toNormalizedFraction: 1.0,
      tolerance: tolerance
    )
    #expect(
      bounds.contains(
        Point3D(x: 0.6, y: 0.5, z: 0.25),
        tolerance: tolerance.distance
      ))

    let encoded = try JSONEncoder().encode(curve)
    let decoded = try JSONDecoder().decode(
      CertifiedImplicitIntersectionCurve.self,
      from: encoded
    )
    #expect(decoded == curve)
    try decoded.validate(tolerance: tolerance)
  }

  @Test(.timeLimit(.minutes(1)))
  func proceduralSurfaceCellRejectsAnIncorrectGraphCoordinate() throws {
    let first = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(horizontalSurface()),
          distance: 0.25
        )))
    let second = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(verticalSurface()),
          distance: 0.1
        )))
    let anchors = try proceduralAnchorParameters()

    #expect(throws: KernelError.self) {
      _ = try CertifiedImplicitIntersectionGraphCell(
        parameterBox: parameterBox(),
        freeParameter: .firstU,
        direction: .forward,
        lowerAnchor: anchors.lower,
        midpointAnchor: anchors.midpoint,
        upperAnchor: anchors.upper,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func strictRoundTripReconstructsAndRevalidatesTheCertificate() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )

    let encoded = try JSONEncoder().encode(curve)
    let decoded = try JSONDecoder().decode(
      CertifiedImplicitIntersectionCurve.self,
      from: encoded
    )

    #expect(decoded == curve)
    try decoded.validate(tolerance: tolerance)
  }

  @Test(.timeLimit(.minutes(1)))
  func certificateCannotBeReusedAtAStricterTolerance() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
    let stricterTolerance = ModelingTolerance(
      distance: tolerance.distance * 0.5,
      angle: tolerance.angle * 0.5,
      relative: tolerance.relative * 0.5
    )

    #expect(throws: KernelError.self) {
      try curve.validate(tolerance: stricterTolerance)
    }
    let admitted = try ValidatedCurve3D(.implicit(curve), tolerance: tolerance)
    for parameter in [0.0, 0.5, 1.0] {
      #expect(try admitted.point(at: parameter) == curve.point(
        atNormalizedFraction: parameter, tolerance: tolerance))
    }
    #expect(throws: KernelError.self) {
      try ValidatedCurve3D(.implicit(curve), tolerance: stricterTolerance)
    }
    #expect(throws: KernelError.self) {
      try PreparedCurveDifferentialEncloser(curve: .implicit(curve), tolerance: stricterTolerance)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func intersectsThirdBSplineWithCertifiedParametricCompleteness() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
    let target = BSplineSurface3D(
      uDegree: 1,
      vDegree: 1,
      uKnots: [0.0, 0.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [
        [
          Point3D(x: 0.0, y: 0.25, z: -1.0),
          Point3D(x: 1.0, y: 0.25, z: -1.0),
        ],
        [
          Point3D(x: 0.0, y: 0.25, z: 1.0),
          Point3D(x: 1.0, y: 0.25, z: 1.0),
        ],
      ],
      weights: [[1.0, 1.0], [1.0, 1.0]]
    )

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: .bSpline(target),
      options: CurveSurfaceIntersectionOptions(),
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(intersection.kind == .transverse)
    #expect(abs(intersection.curveParameter - 0.25) <= tolerance.relative)
    #expect(
      intersection.point.isApproximatelyEqual(
        to: Point3D(x: 0.5, y: 0.25, z: 0.0),
        tolerance: tolerance.distance
      ))
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func singularThirdBSplineContactFailsExplicitly() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
    let options = CurveSurfaceIntersectionOptions(
      maximumSubdivisionDepth: 0
    )

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: .bSpline(tangentParaboloid()),
        options: options,
        tolerance: tolerance
      )
      Issue.record("A singular uncertified contact must fail explicitly.")
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func intersectsExactPlaneThroughCertifiedRationalPatch() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 0.0, y: 0.25, z: 0.0),
        normal: .unitY
      ))

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: target,
      options: CurveSurfaceIntersectionOptions(),
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(intersection.kind == .transverse)
    #expect(abs(intersection.curveParameter - 0.25) <= tolerance.relative)
    #expect(
      intersection.point.isApproximatelyEqual(
        to: Point3D(x: 0.5, y: 0.25, z: 0.0),
        tolerance: tolerance.distance
      ))
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func legacyPlaneRemapsExplicitParameterRanges() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 0.0, y: 0.25, z: 0.0),
        normal: .unitY
      ))
    let options = CurveSurfaceIntersectionOptions(
      surfaceURange: try ScalarInterval(lower: -0.6, upper: -0.4),
      surfaceVRange: try ScalarInterval(lower: -0.1, upper: 0.1)
    )

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: target,
      options: options,
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(abs(intersection.surfaceU + 0.5) <= tolerance.relative)
    #expect(abs(intersection.surfaceV) <= tolerance.relative)
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticCylinderRemapsIntoShiftedPeriodicRange() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.cylinder(
      Cylinder3D(
        origin: .origin,
        axis: .unitZ,
        radius: 1.0
      ))
    let expectedAngle = Double.pi / 3.0
    let shiftedAngle = expectedAngle + 2.0 * Double.pi
    let options = CurveSurfaceIntersectionOptions(
      surfaceURange: try ScalarInterval(
        lower: shiftedAngle - 0.1,
        upper: shiftedAngle + 0.1
      ),
      surfaceVRange: try ScalarInterval(lower: -0.1, upper: 0.1)
    )

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: target,
      options: options,
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(intersection.kind == .transverse)
    #expect(abs(intersection.surfaceU - shiftedAngle) <= tolerance.angle)
    #expect(abs(intersection.surfaceV) <= tolerance.distance)
    #expect(
      abs(intersection.curveParameter - sqrt(0.75))
        <= tolerance.relative)
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func exactImplicitSourceSurfaceReportsContinuousCoincidence() throws {
    let curve = try certifiedLineCurve()

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: curve.firstSurface,
        options: CurveSurfaceIntersectionOptions(),
        tolerance: tolerance
      )
      Issue.record("An exact source surface must report coincidence.")
    } catch let error as KernelError {
      #expect(error.code == .nonDiscreteIntersection)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func singularAnalyticContactFailsExplicitly() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.analytic(
      .sphere(
        center: Point3D(x: 0.6, y: 0.5, z: 0.0),
        radius: 0.1
      ))
    let options = CurveSurfaceIntersectionOptions(
      surfaceURange: try ScalarInterval(
        lower: Double.pi * 0.5 - 0.1,
        upper: Double.pi * 0.5 + 0.1
      ),
      surfaceVRange: try ScalarInterval(lower: -0.1, upper: 0.1),
      maximumSubdivisionDepth: 0,
      maximumPeriodicSeamAttempts: 1
    )

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: target,
        options: options,
        tolerance: tolerance
      )
      Issue.record("A singular analytic contact must fail explicitly.")
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  @Test
  func rejectsInvalidPeriodicSeamAttemptBudget() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.cylinder(
      Cylinder3D(
        origin: .origin,
        axis: .unitZ,
        radius: 1.0
      ))

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: target,
        options: CurveSurfaceIntersectionOptions(
          maximumPeriodicSeamAttempts: 0
        ),
        tolerance: tolerance
      )
      Issue.record("An invalid seam-attempt budget must be rejected.")
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  private func certifiedLineCurve()
    throws -> CertifiedImplicitIntersectionCurve
  {
    let first = horizontalSurface()
    let second = verticalSurface()
    return try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
  }

  private func tangentParaboloid() -> BSplineSurface3D {
    let uX = [0.5625, 0.3125, 1.0625]
    let vX = [1.0, -1.0, 1.0]
    let uY = [0.0, 0.5, 1.0]
    let vZ = [-1.0, 0.0, 1.0]
    let controlPoints = uX.indices.map { uIndex in
      vX.indices.map { vIndex in
        Point3D(
          x: uX[uIndex] + vX[vIndex],
          y: uY[uIndex],
          z: vZ[vIndex]
        )
      }
    }
    return BSplineSurface3D(
      uDegree: 2,
      vDegree: 2,
      uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      controlPoints: controlPoints,
      weights: Array(
        repeating: Array(repeating: 1.0, count: 3),
        count: 3
      )
    )
  }

  private func graphCell(
    first: BSplineSurface3D,
    second: BSplineSurface3D
  ) throws -> CertifiedImplicitIntersectionGraphCell {
    let anchors = try anchorParameters()
    return try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox(),
      freeParameter: .firstV,
      direction: .forward,
      lowerAnchor: anchors.lower,
      midpointAnchor: anchors.midpoint,
      upperAnchor: anchors.upper,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
  }

  private func parameterBox() throws -> SurfaceIntersectionParameterBox {
    SurfaceIntersectionParameterBox(
      firstU: try ScalarInterval(lower: 0.0, upper: 1.0),
      firstV: try ScalarInterval(lower: 0.0, upper: 1.0),
      secondU: try ScalarInterval(lower: 0.0, upper: 1.0),
      secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
    )
  }

  private func anchorParameters() throws -> (
    lower: SurfaceIntersectionParameterPair,
    midpoint: SurfaceIntersectionParameterPair,
    upper: SurfaceIntersectionParameterPair
  ) {
    (
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
  }

  private func proceduralAnchorParameters() throws -> (
    lower: SurfaceIntersectionParameterPair,
    midpoint: SurfaceIntersectionParameterPair,
    upper: SurfaceIntersectionParameterPair
  ) {
    (
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.6, v: 0.0),
        second: SurfaceParameter(u: 1.0 / 3.0, v: 0.625)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.6, v: 0.5),
        second: SurfaceParameter(u: 0.5, v: 0.625)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.6, v: 1.0),
        second: SurfaceParameter(u: 2.0 / 3.0, v: 0.625)
      )
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
}
