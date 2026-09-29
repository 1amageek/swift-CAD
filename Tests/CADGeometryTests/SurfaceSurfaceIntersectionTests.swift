import CADCore
import Foundation
import Testing

@testable import CADGeometry

@Suite("Surface-Surface Intersection")
struct SurfaceSurfaceIntersectionTests {
  private let intersector = DefaultSurfaceSurfaceIntersector()
  private let tolerance = ModelingTolerance.standard

  @Test
  func continuationBudgetsAreValidatedAsOnePublicContract() throws {
    #expect(throws: KernelError.self) {
      try SurfaceSurfaceIntersectionOptions(
        maximumContinuationPointCount: 8,
        maximumContinuationPointCountPerComponent: 9
      ).validate(tolerance: tolerance)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func parametricContinuationHonorsTheConfiguredPointBudget() throws {
    let (plane, graph) = proceduralTwoLineSurfaces()

    do {
      _ = try intersector.intersections(
        first: plane,
        second: graph,
        options: SurfaceSurfaceIntersectionOptions(
          maximumContinuationPointCount: 1,
          maximumContinuationPointCountPerComponent: 1
        ),
        tolerance: tolerance
      )
      Issue.record(
        "Parametric continuation must not exceed its configured point budget."
      )
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticOffsetSurfacesUseTheirExactIntersectionGeometryAndOriginalParameters() throws {
    let horizontal = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .plane(Plane3D(origin: .origin, normal: .unitZ)),
          distance: 1.0
        )))
    let vertical = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .analytic(.plane(origin: .origin, normal: .unitX)),
          distance: 2.0
        )))
    let planeSection = try intersector.intersections(
      first: horizontal,
      second: vertical,
      tolerance: tolerance
    )
    guard case .curve(let planeResult) = try #require(planeSection.first),
      case .line(let line) = planeResult.curve
    else {
      Issue.record("Perpendicular analytic offset planes must intersect in one exact line.")
      return
    }
    #expect(planeSection.count == 1)
    #expect(abs(line.origin.x - 2.0) <= tolerance.distance)
    #expect(abs(line.origin.z - 1.0) <= tolerance.distance)
    #expect(planeResult.maximumResidual <= tolerance.distance)

    let cylinder = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .analytic(
            .cylinder(
              origin: .origin,
              axis: .unitZ,
              radius: 2.0
            )),
          distance: 0.5
        )))
    let cylinderSection = try intersector.intersections(
      first: horizontal,
      second: cylinder,
      tolerance: tolerance
    )
    guard case .curve(let cylinderResult) = try #require(cylinderSection.first),
      case .circle(let circle) = cylinderResult.curve
    else {
      Issue.record("An offset plane and offset cylinder must retain exact circle geometry.")
      return
    }
    #expect(abs(circle.radius - 2.5) <= tolerance.distance)
    #expect(abs(circle.center.z - 1.0) <= tolerance.distance)
    for parameter in [0.0, Double.pi * 0.5, Double.pi] {
      let curvePoint = try cylinderResult.curve.point(
        at: parameter,
        tolerance: tolerance
      )
      let firstParameter = try cylinderResult.surfaceParameter(
        on: .first,
        atCurveParameter: parameter,
        tolerance: tolerance
      )
      let secondParameter = try cylinderResult.surfaceParameter(
        on: .second,
        atCurveParameter: parameter,
        tolerance: tolerance
      )
      let firstPoint = try horizontal.point(
        u: firstParameter.u,
        v: firstParameter.v,
        tolerance: tolerance
      )
      let secondPoint = try cylinder.point(
        u: secondParameter.u,
        v: secondParameter.v,
        tolerance: tolerance
      )
      #expect(
        curvePoint.isApproximatelyEqual(
          to: firstPoint,
          tolerance: tolerance.distance
        ))
      #expect(
        curvePoint.isApproximatelyEqual(
          to: secondPoint,
          tolerance: tolerance.distance
        ))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func noncanonicalProceduralOffsetsUseTheCertifiedParametricBackend() throws {
    let horizontalBase = BSplineSurface3D(
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
    let verticalBase = BSplineSurface3D(
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
    let horizontal = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(horizontalBase),
          distance: 0.25
        )))
    let vertical = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(verticalBase),
          distance: 0.1
        )))

    let intersections = try intersector.intersections(
      first: horizontal,
      second: vertical,
      tolerance: tolerance
    )
    guard intersections.count == 1,
      case .curve(let result) = intersections[0],
      case .implicit = result.truth
    else {
      Issue.record("Noncanonical procedural offsets must produce one certified implicit curve.")
      return
    }

    #expect(result.kind == .transverse)
    #expect(result.maximumResidual == tolerance.distance)
    try result.firstSurfaceParameterCurve.validate(
      on: horizontal,
      tolerance: tolerance
    )
    try result.secondSurfaceParameterCurve.validate(
      on: vertical,
      tolerance: tolerance
    )
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try result.curve.point(
        at: fraction,
        tolerance: tolerance
      )
      let firstParameter = try result.surfaceParameter(
        on: .first,
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let secondParameter = try result.surfaceParameter(
        on: .second,
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let firstPoint = try horizontal.point(
        u: firstParameter.u,
        v: firstParameter.v,
        tolerance: tolerance
      )
      let secondPoint = try vertical.point(
        u: secondParameter.u,
        v: secondParameter.v,
        tolerance: tolerance
      )
      #expect(
        point.isApproximatelyEqual(
          to: firstPoint,
          tolerance: tolerance.distance
        ))
      #expect(
        point.isApproximatelyEqual(
          to: secondPoint,
          tolerance: tolerance.distance
        ))
      #expect(abs(point.x - 0.6) <= tolerance.distance)
      #expect(abs(point.z - 0.25) <= tolerance.distance)
    }

    let encoded = try JSONEncoder().encode(intersections[0])
    let decoded = try JSONDecoder().decode(
      SurfaceSurfaceIntersection.self,
      from: encoded
    )
    #expect(decoded == intersections[0])
  }

  @Test(.timeLimit(.minutes(1)))
  func disjointNoncanonicalProceduralOffsetsReturnAProvenEmptySet() throws {
    let base = BSplineSurface3D(
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
    let first = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(base),
          distance: 0.25
        )))
    let second = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(base),
          distance: 2.25
        )))

    let intersections = try intersector.intersections(
      first: first,
      second: second,
      tolerance: tolerance
    )

    #expect(intersections.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func coincidentNoncanonicalProceduralOffsetsRemainAnExplicitFailure() throws {
    let base = BSplineSurface3D(
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
    let surface = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(base),
          distance: 0.25
        )))

    do {
      _ = try intersector.intersections(
        first: surface,
        second: surface,
        options: SurfaceSurfaceIntersectionOptions(
          maximumSubdivisionDepth: 0
        ),
        tolerance: tolerance
      )
      Issue.record(
        "An uncertified coincident procedural locus must not be returned as an empty or regular result."
      )
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  @Test(.timeLimit(.minutes(2)))
  func subdividedProceduralIntersectionAssemblesACompleteClosedCurveInBothOrders() throws {
    let plane = BSplineSurface3D(
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
    let radius = 0.25
    let offsetDistance = 0.01
    let sourceNormalScale = sqrt(1.0 + 4.0 * radius * radius)
    let sourceLevel =
      radius * radius
      + offsetDistance / sourceNormalScale
    let expectedRadius =
      radius
      * (1.0 - 2.0 * offsetDistance / sourceNormalScale)
    let quadraticCoefficients = [0.25, -0.25, 0.25]
    let graph = BSplineSurface3D(
      uDegree: 2,
      vDegree: 2,
      uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      controlPoints: (0..<3).map { vIndex in
        (0..<3).map { uIndex in
          Point3D(
            x: Double(uIndex) * 0.5,
            y: Double(vIndex) * 0.5,
            z: quadraticCoefficients[uIndex]
              + quadraticCoefficients[vIndex]
              - sourceLevel
          )
        }
      },
      weights: Array(
        repeating: Array(repeating: 1.0, count: 3),
        count: 3
      )
    )
    let planarSurface = Surface3D.bSpline(plane)
    let graphSurface = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(graph),
          distance: offsetDistance
        )))

    let forward = try intersector.intersections(
      first: planarSurface,
      second: graphSurface,
      options: .init(),
      tolerance: tolerance
    )
    let reversed = try intersector.intersections(
      first: graphSurface,
      second: planarSurface,
      options: .init(),
      tolerance: tolerance
    )
    for (intersections, first, second) in [
      (forward, planarSurface, graphSurface),
      (reversed, graphSurface, planarSurface),
    ] {
      guard intersections.count == 1,
        case .curve(let result) = intersections[0],
        case .implicit(let curve) = result.truth
      else {
        Issue.record(
          "A subdivided procedural circle must assemble into one certified implicit curve.")
        continue
      }
      #expect(curve.isClosed)
      #expect(curve.cells.count > 1)
      try result.firstSurfaceParameterCurve.validate(
        on: first,
        tolerance: tolerance
      )
      try result.secondSurfaceParameterCurve.validate(
        on: second,
        tolerance: tolerance
      )
      for fraction in stride(from: 0.0, through: 1.0, by: 1.0 / 16.0) {
        let point = try result.curve.point(
          at: fraction,
          tolerance: tolerance
        )
        let radialDistance = hypot(point.x - 0.5, point.y - 0.5)
        #expect(abs(point.z) <= tolerance.distance)
        #expect(abs(radialDistance - expectedRadius) <= tolerance.distance)
      }
    }
  }

  @Test(.timeLimit(.minutes(2)))
  func proceduralCompletenessSweepFindsEveryDisconnectedRegularComponent() throws {
    let (plane, graph) = proceduralTwoLineSurfaces()
    let intersections = try intersector.intersections(
      first: plane,
      second: graph,
      options: .init(),
      tolerance: tolerance
    )

    #expect(intersections.count == 2)
    var recoveredCenters: [Double] = []
    for intersection in intersections {
      guard case .curve(let result) = intersection,
        case .implicit(let curve) = result.truth
      else {
        Issue.record(
          "Every disconnected procedural component must retain certified implicit truth."
        )
        continue
      }
      #expect(curve.isClosed == false)
      try result.firstSurfaceParameterCurve.validate(
        on: plane,
        tolerance: tolerance
      )
      try result.secondSurfaceParameterCurve.validate(
        on: graph,
        tolerance: tolerance
      )
      let samples = try stride(
        from: 0.0,
        to: 1.0,
        by: 1.0 / 16.0
      ).map {
        try result.curve.point(
          at: $0,
          tolerance: tolerance
        )
      }
      let meanX =
        samples.reduce(0.0) { $0 + $1.x }
        / Double(samples.count)
      let expectedCenter = meanX < 0.5 ? 0.3 : 0.7
      recoveredCenters.append(expectedCenter)
      for point in samples {
        #expect(abs(point.z) <= tolerance.distance)
        #expect(abs(point.x - meanX) <= tolerance.distance * 2.0)
      }
      #expect(abs(meanX - expectedCenter) < 0.05)
    }
    #expect(recoveredCenters.sorted() == [0.3, 0.7])
  }

  @Test(.timeLimit(.minutes(1)))
  func parametricGaugeCertifiesAKnownRegularCircleArc() throws {
    let (planarSurface, graphSurface) = proceduralCircleSurfaces()
    for rootV in [0.5, 0.5625, 0.625] {
      let rootU =
        0.5
        + sqrt(
          0.25 * 0.25 - (rootV - 0.5) * (rootV - 0.5)
        )
      let parameterBox = SurfaceIntersectionParameterBox(
        firstU: try ScalarInterval(
          lower: rootU - 0.01,
          upper: rootU + 0.01
        ),
        firstV: try ScalarInterval(
          lower: rootV - 0.005,
          upper: rootV + 0.005
        ),
        secondU: try ScalarInterval(
          lower: rootU - 0.01,
          upper: rootU + 0.01
        ),
        secondV: try ScalarInterval(
          lower: rootV - 0.01,
          upper: rootV + 0.01
        )
      )
      let prover = try ParametricSurfaceIntersectionGraphProver(
        firstSurface: planarSurface,
        secondSurface: graphSurface,
        parameterBox: parameterBox,
        tolerance: tolerance
      )
      #expect(prover.rankCertifiedFreeParameters().contains(.firstV))
      let certificate = try prover.gaugeCertificate(
        freeParameter: .firstV,
        atNormalizedFraction: 0.5,
        tolerance: tolerance
      )
      guard case .uniqueRoot = certificate else {
        Issue.record(
          "A localized regular arc gauge must have one certified root; received \(String(describing: certificate))."
        )
        continue
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func parametricContractorExcludesACorrelatedNearMiss() throws {
    let (planarSurface, graphSurface) = proceduralCircleSurfaces()
    let parameterBox = SurfaceIntersectionParameterBox(
      firstU: try ScalarInterval(
        lower: 0.2495076238087935,
        upper: 0.24975381190439674
      ),
      firstV: try ScalarInterval(lower: 0.46875, upper: 0.5),
      secondU: try ScalarInterval(
        lower: 0.24975381190439674,
        upper: 0.25
      ),
      secondV: try ScalarInterval(lower: 0.46875, upper: 0.5)
    )
    let prover = try ParametricSurfaceIntersectionGraphProver(
      firstSurface: planarSurface,
      secondSurface: graphSurface,
      parameterBox: parameterBox,
      tolerance: tolerance
    )
    let freeParameters = prover.rankCertifiedFreeParameters()
    let certificates = try freeParameters.map {
      try prover.parameterizedGraphCertificate(
        freeParameter: $0,
        tolerance: tolerance
      )
    }
    let diagnostics = try freeParameters.map {
      try prover.parameterizedGraphDiagnostic(
        freeParameter: $0,
        tolerance: tolerance
      )
    }
    let boundaryCertificates =
      try SurfaceIntersectionParameterCoordinate
      .allCases.flatMap { coordinate in
        try [0.0, 1.0].map { fraction in
          try prover.gaugeCertificate(
            freeParameter: coordinate,
            atNormalizedFraction: fraction,
            tolerance: tolerance
          )
        }
      }

    let parameterizedExclusion = certificates.contains { certificate in
      if case .empty = certificate { return true }
      return false
    }
    let boundaryExclusion = boundaryCertificates.allSatisfy { certificate in
      if case .empty = certificate { return true }
      return false
    }
    #expect(
      parameterizedExclusion || boundaryExclusion,
      "A regular box whose residual components can only vanish at different parameter values must be excluded by contraction or its complete boundary proof. Certificates: \(String(describing: certificates)); boundary certificates: \(String(describing: boundaryCertificates)); diagnostics: \(diagnostics)"
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func parametricContractorClassifiesARegularBoundaryHandoff() throws {
    let (planarSurface, graphSurface) = proceduralCircleSurfaces()
    let parameterBox = SurfaceIntersectionParameterBox(
      firstU: try ScalarInterval(
        lower: 0.24999425437111153,
        upper: 0.25
      ),
      firstV: try ScalarInterval(lower: 0.375, upper: 0.5),
      secondU: try ScalarInterval(
        lower: 0.24999428591482442,
        upper: 0.25
      ),
      secondV: try ScalarInterval(lower: 0.375, upper: 0.5)
    )
    let prover = try ParametricSurfaceIntersectionGraphProver(
      firstSurface: planarSurface,
      secondSurface: graphSurface,
      parameterBox: parameterBox,
      tolerance: tolerance
    )
    let freeParameters = prover.rankCertifiedFreeParameters()
    let graphCertificates = try freeParameters.map {
      try prover.parameterizedGraphCertificate(
        freeParameter: $0,
        tolerance: tolerance
      )
    }
    let boundaryCertificates =
      try SurfaceIntersectionParameterCoordinate
      .allCases.flatMap { coordinate in
        try [0.0, 1.0].map { fraction in
          try prover.gaugeCertificate(
            freeParameter: coordinate,
            atNormalizedFraction: fraction,
            tolerance: tolerance
          )
        }
      }
    let contractsToHandoff = graphCertificates.contains { certificate in
      guard case .contracted(let bounds) = certificate else {
        return false
      }
      return bounds[0].lower > 0.99
        && bounds[2].lower > 0.99
        && bounds[3].lower > 0.99
        && bounds[0].upper >= 1.0
        && bounds[2].upper >= 1.0
        && bounds[3].upper >= 1.0
    }
    let excludesAtLeastOneOppositeFace = boundaryCertificates.contains {
      certificate in
      if case .empty = certificate { return true }
      return false
    }
    #expect(contractsToHandoff)
    #expect(excludesAtLeastOneOppositeFace)
  }

  @Test(.timeLimit(.minutes(1)))
  func ruledSurfaceIntersectionUsesExactGeometryAndOriginalParameterChart() throws {
    let ruled = Surface3D.procedural(
      .ruled(
        RuledSurface3D(
          startBoundary: .line(
            Line3D(
              origin: .origin,
              direction: .unitX
            )),
          endBoundary: .line(
            Line3D(
              origin: Point3D(x: 0.0, y: 1.0, z: 1.0),
              direction: .unitX
            ))
        )))
    let sectionPlane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 0.5, y: 0.0, z: 0.0),
        normal: .unitX
      ))

    let forward = try intersector.intersections(
      first: ruled,
      second: sectionPlane,
      tolerance: tolerance
    )
    try verifyRuledPlaneSection(
      forward,
      ruled: ruled,
      sectionPlane: sectionPlane,
      ruledRole: .first
    )
    let decodedForward = try JSONDecoder().decode(
      [SurfaceSurfaceIntersection].self,
      from: JSONEncoder().encode(forward)
    )
    #expect(decodedForward == forward)
    try verifyRuledPlaneSection(
      decodedForward,
      ruled: ruled,
      sectionPlane: sectionPlane,
      ruledRole: .first
    )

    let reverse = try intersector.intersections(
      first: sectionPlane,
      second: ruled,
      tolerance: tolerance
    )
    try verifyRuledPlaneSection(
      reverse,
      ruled: ruled,
      sectionPlane: sectionPlane,
      ruledRole: .second
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func twoRuledSurfacesIntersectThroughTheirExactRepresentations() throws {
    let diagonal = Surface3D.procedural(
      .ruled(
        RuledSurface3D(
          startBoundary: .line(
            Line3D(
              origin: .origin,
              direction: .unitX
            )),
          endBoundary: .line(
            Line3D(
              origin: Point3D(x: 0.0, y: 1.0, z: 1.0),
              direction: .unitX
            ))
        )))
    let vertical = Surface3D.procedural(
      .ruled(
        RuledSurface3D(
          startBoundary: .line(
            Line3D(
              origin: Point3D(x: 0.0, y: 0.5, z: -0.5),
              direction: .unitX
            )),
          endBoundary: .line(
            Line3D(
              origin: Point3D(x: 0.0, y: 0.5, z: 1.5),
              direction: .unitX
            ))
        )))

    let intersections = try intersector.intersections(
      first: diagonal,
      second: vertical,
      tolerance: tolerance
    )

    #expect(intersections.count == 1)
    guard case .curve(let result) = try #require(intersections.first) else {
      Issue.record("Two transverse ruled surfaces must produce one curve.")
      return
    }
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let firstParameter = try result.surfaceParameter(
        on: .first,
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let secondParameter = try result.surfaceParameter(
        on: .second,
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let firstPoint = try diagonal.point(
        u: firstParameter.u,
        v: firstParameter.v,
        tolerance: tolerance
      )
      let secondPoint = try vertical.point(
        u: secondParameter.u,
        v: secondParameter.v,
        tolerance: tolerance
      )
      #expect(
        firstPoint.isApproximatelyEqual(
          to: secondPoint,
          tolerance: tolerance.distance
        ))
      #expect(abs(firstPoint.y - 0.5) <= tolerance.distance)
      #expect(abs(firstPoint.z - 0.5) <= tolerance.distance)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func planePlaneProducesVerifiedLineAndCoincidence() throws {
    let horizontal = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
    let vertical = Surface3D.analytic(.plane(origin: .origin, normal: .unitX))

    let intersections = try intersector.intersections(
      first: horizontal,
      second: vertical,
      tolerance: tolerance
    )
    let intersection = try #require(intersections.first)
    guard case .curve(let result) = intersection,
      case .line(let line) = result.curve
    else {
      Issue.record("Perpendicular planes must intersect in a line.")
      return
    }
    #expect(intersections.count == 1)
    #expect(abs(line.direction.dot(.unitY)) >= 1.0 - tolerance.angle)
    #expect(result.maximumResidual <= tolerance.distance)

    let coincident = try intersector.intersections(
      first: horizontal,
      second: .analytic(
        .plane(
          origin: Point3D(x: 0.5, y: -0.25, z: 0.0),
          normal: -.unitZ
        )),
      tolerance: tolerance
    )
    #expect(coincident.count == 1)
    #expect(
      coincident.contains {
        if case .coincident = $0 { return true }
        return false
      })
  }

  @Test(.timeLimit(.minutes(1)))
  func planeSphereProducesCircleAndTangentPoint() throws {
    let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
    let section = try intersector.intersections(
      first: .plane(
        Plane3D(
          origin: Point3D(x: 0.0, y: 0.0, z: 1.0),
          normal: .unitZ
        )),
      second: sphere,
      tolerance: tolerance
    )
    guard case .curve(let result) = try #require(section.first),
      case .circle(let circle) = result.curve
    else {
      Issue.record("A secant plane must produce a circle on a sphere.")
      return
    }
    #expect(abs(circle.radius - sqrt(3.0)) <= tolerance.distance)
    #expect(
      circle.center.isApproximatelyEqual(
        to: Point3D(x: 0.0, y: 0.0, z: 1.0),
        tolerance: tolerance.distance
      ))

    let tangent = try intersector.intersections(
      first: .analytic(
        .plane(
          origin: Point3D(x: 0.0, y: 0.0, z: 2.0),
          normal: .unitZ
        )),
      second: sphere,
      tolerance: tolerance
    )
    guard case .point(let point) = try #require(tangent.first) else {
      Issue.record("A tangent plane must produce one verified point.")
      return
    }
    #expect(
      point.point.isApproximatelyEqual(
        to: Point3D(x: 0.0, y: 0.0, z: 2.0),
        tolerance: tolerance.distance
      ))
  }

  @Test(.timeLimit(.minutes(1)))
  func latitudeCircleRetainsAnalyticChartsInBothOrientations() throws {
    let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
    for sign in [-1.0, 1.0] {
      let plane = Surface3D.plane(Plane3D(
        origin: Point3D(x: 0, y: 0, z: 1),
        normal: Vector3D(x: 0, y: 0, z: sign)
      ))
      let intersections = try intersector.intersections(
        first: plane, second: sphere, tolerance: tolerance
      )
      guard case .curve(let result) = try #require(intersections.first),
            case .harmonic = result.firstSurfaceParameterCurve,
            case .affine = result.secondSurfaceParameterCurve else {
        Issue.record("A latitude circle must retain analytic plane and sphere charts.")
        continue
      }
      for parameter in [0.0, 0.7, 3.4, 2 * Double.pi] {
        let point = try result.curve.point(at: parameter, tolerance: tolerance)
        for (role, surface) in [(SurfaceIntersectionSurfaceRole.first, plane), (.second, sphere)] {
          let uv = try result.surfaceParameter(on: role, atCurveParameter: parameter, tolerance: tolerance)
          let lifted = try surface.point(u: uv.u, v: uv.v, tolerance: tolerance)
          #expect(lifted.isApproximatelyEqual(to: point, tolerance: tolerance.distance))
        }
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func coaxialSphereCylinderGreatCircleRetainsPoleSafeSpherePcurve() throws {
    let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
    let cylinder = Surface3D.analytic(
      .cylinder(
        origin: .origin,
        axis: .unitX,
        radius: 2.0
      ))

    let intersections = try intersector.intersections(
      first: sphere,
      second: cylinder,
      tolerance: tolerance
    )

    guard case .curve(let result) = try #require(intersections.first),
      case .sphericalGreatCircle = result.firstSurfaceParameterCurve
    else {
      Issue.record(
        "A coaxial tangent sphere-cylinder circle must use an exact spherical great-circle pcurve.")
      return
    }
    #expect(intersections.count == 1)
    #expect(result.kind == .tangent)
    #expect(result.maximumResidual <= tolerance.distance)
    for parameter in [0.0, Double.pi * 0.5, Double.pi, Double.pi * 1.5] {
      let curvePoint = try result.curve.point(
        at: parameter,
        tolerance: tolerance
      )
      let sphereParameter = try result.surfaceParameter(
        on: .first,
        atCurveParameter: parameter,
        tolerance: tolerance
      )
      let spherePoint = try sphere.point(
        u: sphereParameter.u,
        v: sphereParameter.v,
        tolerance: tolerance
      )
      #expect(
        curvePoint.isApproximatelyEqual(
          to: spherePoint,
          tolerance: tolerance.distance
        ))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func planeCylinderProducesParallelLinesAndObliqueEllipse() throws {
    let cylinder = Surface3D.analytic(
      .cylinder(
        origin: .origin,
        axis: .unitZ,
        radius: 2.0
      ))
    let parallelSection = try intersector.intersections(
      first: .plane(Plane3D(origin: .origin, normal: .unitX)),
      second: cylinder,
      tolerance: tolerance
    )
    #expect(parallelSection.count == 2)
    #expect(
      parallelSection.allSatisfy {
        guard case .curve(let result) = $0,
          case .line = result.curve
        else { return false }
        return result.maximumResidual <= tolerance.distance
      })

    let perpendicularSection = try intersector.intersections(
      first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
      second: cylinder,
      tolerance: tolerance
    )
    guard case .curve(let perpendicularResult) = try #require(perpendicularSection.first),
      case .circle(let perpendicularCircle) = perpendicularResult.curve
    else {
      Issue.record("A perpendicular plane must produce a circle on a cylinder.")
      return
    }
    #expect(abs(perpendicularCircle.radius - 2.0) <= tolerance.distance)
    #expect(perpendicularResult.maximumResidual <= tolerance.distance)

    let obliqueNormal = try Vector3D(x: 0.0, y: 1.0, z: 1.0).normalized(
      tolerance: tolerance.distance
    )
    let obliqueSection = try intersector.intersections(
      first: .analytic(.plane(origin: .origin, normal: obliqueNormal)),
      second: cylinder,
      tolerance: tolerance
    )
    guard case .curve(let result) = try #require(obliqueSection.first),
      case .analytic(.ellipse(_, _, _, let majorRadius, let minorRadius)) = result.curve
    else {
      Issue.record("An oblique plane must produce an ellipse on a cylinder.")
      return
    }
    #expect(abs(majorRadius - 2.0 * sqrt(2.0)) <= tolerance.distance)
    #expect(abs(minorRadius - 2.0) <= tolerance.distance)
    #expect(result.maximumResidual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func sphereSphereProducesCircleTangentAndCoincidence() throws {
    let first = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
    let second = Surface3D.analytic(
      .sphere(
        center: Point3D(x: 2.0, y: 0.0, z: 0.0),
        radius: 2.0
      ))
    let section = try intersector.intersections(
      first: first,
      second: second,
      tolerance: tolerance
    )
    guard case .curve(let result) = try #require(section.first),
      case .circle(let circle) = result.curve
    else {
      Issue.record("Two secant spheres must produce a circle.")
      return
    }
    #expect(
      circle.center.isApproximatelyEqual(
        to: Point3D(x: 1.0, y: 0.0, z: 0.0),
        tolerance: tolerance.distance
      ))
    #expect(abs(circle.radius - sqrt(3.0)) <= tolerance.distance)

    let tangent = try intersector.intersections(
      first: first,
      second: .analytic(
        .sphere(
          center: Point3D(x: 4.0, y: 0.0, z: 0.0),
          radius: 2.0
        )),
      tolerance: tolerance
    )
    #expect(
      tangent.contains {
        if case .point = $0 { return true }
        return false
      })

    let coincident = try intersector.intersections(
      first: first,
      second: first,
      tolerance: tolerance
    )
    #expect(
      coincident.contains {
        if case .coincident = $0 { return true }
        return false
      })
  }

  @Test(.timeLimit(.minutes(1)))
  func planeConeProducesClosedEllipseAndApexGeneratorLines() throws {
    let halfAngle = Double.pi / 6.0
    let cone = Surface3D.analytic(
      .cone(
        apex: .origin,
        axis: .unitZ,
        halfAngle: halfAngle
      ))
    let obliqueNormal = try Vector3D(x: 0.0, y: 0.5, z: sqrt(0.75)).normalized(
      tolerance: tolerance.distance
    )
    let closedSection = try intersector.intersections(
      first: .plane(
        Plane3D(
          origin: Point3D(x: 0.0, y: 0.0, z: 2.0),
          normal: obliqueNormal
        )),
      second: cone,
      tolerance: tolerance
    )
    guard case .curve(let closedResult) = try #require(closedSection.first),
      case .analytic(.ellipse) = closedResult.curve
    else {
      Issue.record("An elliptic plane-cone section must retain exact ellipse geometry.")
      return
    }
    #expect(closedResult.maximumResidual <= tolerance.distance)

    let generatorSection = try intersector.intersections(
      first: .plane(Plane3D(origin: .origin, normal: .unitY)),
      second: cone,
      tolerance: tolerance
    )
    #expect(generatorSection.count == 2)
    #expect(
      generatorSection.allSatisfy {
        guard case .curve(let result) = $0,
          case .line = result.curve
        else { return false }
        return result.kind == .transverse && result.maximumResidual <= tolerance.distance
      })

    let tangentNormal = try Vector3D(
      x: cos(halfAngle),
      y: 0.0,
      z: -sin(halfAngle)
    ).normalized(tolerance: tolerance.distance)
    let tangentSection = try intersector.intersections(
      first: .plane(Plane3D(origin: .origin, normal: tangentNormal)),
      second: cone,
      tolerance: tolerance
    )
    guard case .curve(let tangentResult) = try #require(tangentSection.first) else {
      Issue.record("A tangent plane through the cone apex must produce one generator.")
      return
    }
    #expect(tangentSection.count == 1)
    #expect(tangentResult.kind == .tangent)
    #expect(tangentResult.maximumResidual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func planeConeProducesExactUnboundedHyperbolaBranchesAndDualPcurves() throws {
    let plane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
        normal: .unitX
      ))
    let cone = Surface3D.analytic(
      .cone(
        apex: .origin,
        axis: .unitZ,
        halfAngle: Double.pi / 6.0
      ))

    let intersections = try intersector.intersections(
      first: plane,
      second: cone,
      tolerance: tolerance
    )

    #expect(intersections.count == 2)
    for intersection in intersections {
      guard case .curve(let result) = intersection,
        case .analytic(.hyperbola) = result.curve
      else {
        Issue.record("A hyperbolic plane-cone section must retain exact unbounded conic geometry.")
        continue
      }
      #expect(result.curve.parameterDomain == .unbounded)
      #expect(result.kind == .transverse)
      #expect(result.maximumResidual <= tolerance.distance)
      for parameter in [-1.0, 0.0, 1.0] {
        let point = try result.curve.point(at: parameter, tolerance: tolerance)
        let planeUV = try result.surfaceParameter(
          on: .first,
          atCurveParameter: parameter,
          tolerance: tolerance
        )
        let coneUV = try result.surfaceParameter(
          on: .second,
          atCurveParameter: parameter,
          tolerance: tolerance
        )
        let planePoint = try plane.point(u: planeUV.u, v: planeUV.v, tolerance: tolerance)
        let conePoint = try cone.point(u: coneUV.u, v: coneUV.v, tolerance: tolerance)
        #expect(point.isApproximatelyEqual(to: planePoint, tolerance: tolerance.distance))
        #expect(point.isApproximatelyEqual(to: conePoint, tolerance: tolerance.distance))
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func planeConeProducesExactUnboundedParabolaAndDualPcurves() throws {
    let halfAngle = Double.pi / 6.0
    let normal = try Vector3D(
      x: cos(halfAngle),
      y: 0.0,
      z: -sin(halfAngle)
    ).normalized(tolerance: tolerance.distance)
    let plane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: -normal.x, y: -normal.y, z: -normal.z),
        normal: normal
      ))
    let cone = Surface3D.analytic(
      .cone(
        apex: .origin,
        axis: .unitZ,
        halfAngle: halfAngle
      ))

    let intersections = try intersector.intersections(
      first: plane,
      second: cone,
      tolerance: tolerance
    )

    guard case .curve(let result) = try #require(intersections.first),
      case .analytic(.parabola) = result.curve
    else {
      Issue.record("A parabolic plane-cone section must retain exact unbounded conic geometry.")
      return
    }
    #expect(intersections.count == 1)
    #expect(result.curve.parameterDomain == .unbounded)
    #expect(result.kind == .transverse)
    #expect(result.maximumResidual <= tolerance.distance)
    for parameter in [-1.0, 0.0, 1.0] {
      let point = try result.curve.point(at: parameter, tolerance: tolerance)
      let planeUV = try result.surfaceParameter(
        on: .first,
        atCurveParameter: parameter,
        tolerance: tolerance
      )
      let coneUV = try result.surfaceParameter(
        on: .second,
        atCurveParameter: parameter,
        tolerance: tolerance
      )
      let planePoint = try plane.point(u: planeUV.u, v: planeUV.v, tolerance: tolerance)
      let conePoint = try cone.point(u: coneUV.u, v: coneUV.v, tolerance: tolerance)
      #expect(point.isApproximatelyEqual(to: planePoint, tolerance: tolerance.distance))
      #expect(point.isApproximatelyEqual(to: conePoint, tolerance: tolerance.distance))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func planeTorusProducesAxialMeridionalAndTangentSections() throws {
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let axialSection = try intersector.intersections(
      first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
      second: torus,
      tolerance: tolerance
    )
    let axialRadii = axialSection.compactMap { intersection -> Double? in
      guard case .curve(let result) = intersection,
        case .circle(let circle) = result.curve
      else { return nil }
      return circle.radius
    }.sorted()
    #expect(axialRadii.count == 2)
    #expect(abs(axialRadii[0] - 2.0) <= tolerance.distance)
    #expect(abs(axialRadii[1] - 4.0) <= tolerance.distance)

    let meridionalSection = try intersector.intersections(
      first: .plane(Plane3D(origin: .origin, normal: .unitY)),
      second: torus,
      tolerance: tolerance
    )
    #expect(meridionalSection.count == 2)
    #expect(
      meridionalSection.allSatisfy {
        guard case .curve(let result) = $0,
          case .circle(let circle) = result.curve
        else { return false }
        return abs(circle.radius - 1.0) <= tolerance.distance
          && result.maximumResidual <= tolerance.distance
      })

    let tangentSection = try intersector.intersections(
      first: .plane(
        Plane3D(
          origin: Point3D(x: 4.0, y: 0.0, z: 0.0),
          normal: .unitX
        )),
      second: torus,
      tolerance: tolerance
    )
    guard case .point(let tangentPoint) = try #require(tangentSection.first) else {
      Issue.record("A torus support plane must produce one verified tangent point.")
      return
    }
    #expect(tangentSection.count == 1)
    #expect(
      tangentPoint.point.isApproximatelyEqual(
        to: Point3D(x: 4.0, y: 0.0, z: 0.0),
        tolerance: tolerance.distance
      ))
  }

  @Test(.timeLimit(.minutes(1)))
  func planeTorusProducesVerifiedOffsetQuarticSection() throws {
    let plane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
        normal: .unitX
      ))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: plane,
      second: torus,
      tolerance: tolerance
    )

    #expect(intersections.count == 1)
    guard case .curve(let result) = try #require(intersections.first),
      case .analyticAnalytic = result.truth,
      case .analytic(.planeTorus) = result.curve
    else {
      Issue.record("An offset plane-torus section must produce exact algebraic truth.")
      return
    }
    #expect(result.maximumResidual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func planeTorusOffsetQuarticCertificateRoundTripsAndEvaluates() throws {
    let plane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
        normal: .unitX
      ))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: plane,
      second: torus,
      tolerance: tolerance
    )
    try verifyGeneralPlaneTorusCurves(
      intersections,
      plane: plane,
      torus: torus
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func planeTorusOffsetSectionIsOperandOrderInvariant() throws {
    let plane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
        normal: .unitX
      ))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: plane,
      second: torus,
      tolerance: tolerance
    )

    let reverse = try intersector.intersections(
      first: torus,
      second: plane,
      tolerance: tolerance
    )
    #expect(intersectionCurves(intersections) == intersectionCurves(reverse))
  }

  @Test(.timeLimit(.minutes(1)))
  func planeTorusProducesTwoVerifiedObliqueQuarticSections() throws {
    let normal = try Vector3D(x: 0.6, y: 0.2, z: 1.0).normalized(
      tolerance: tolerance.distance
    )
    let plane = Surface3D.analytic(.plane(origin: .origin, normal: normal))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: plane,
      second: torus,
      tolerance: tolerance
    )

    #expect(intersections.count == 2)
    try verifyGeneralPlaneTorusCurves(
      intersections,
      plane: plane,
      torus: torus
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func planeTorusInternalTangencyProducesCompleteMixedGraph() throws {
    let plane = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
        normal: .unitX
      ))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: plane,
      second: torus,
      tolerance: tolerance
    )
    try verifyInnerTangentPlaneTorusGraph(
      intersections,
      plane: plane,
      torus: torus,
      expectedContact: Point3D(x: 2.0, y: 0.0, z: 0.0)
    )

    let reversed = try intersector.intersections(
      first: torus,
      second: plane,
      tolerance: tolerance
    )
    #expect(intersectionCurves(reversed) == intersectionCurves(intersections))
  }

  @Test(.timeLimit(.minutes(1)))
  func obliquePlaneTorusInternalTangencyRetainsNodalBranches() throws {
    let normal = try Vector3D(x: 0.6, y: 0.2, z: 1.0).normalized(
      tolerance: tolerance.distance
    )
    let radialNormalLength = sqrt(normal.x * normal.x + normal.y * normal.y)
    let innerSupport = 3.0 * radialNormalLength - 1.0
    let plane = Surface3D.analytic(
      .plane(
        origin: .origin + normal * innerSupport,
        normal: normal
      ))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: plane,
      second: torus,
      tolerance: tolerance
    )
    guard case .curve(let firstCurve) = try #require(intersections.first) else {
      Issue.record("An oblique inner-support section must produce curve branches.")
      return
    }
    let contact = try firstCurve.curve.point(
      at: 0.0,
      tolerance: tolerance
    )
    try verifyInnerTangentPlaneTorusGraph(
      intersections,
      plane: plane,
      torus: torus,
      expectedContact: contact
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func nearbyPlaneTorusSectionsDoNotClaimNodalTangency() throws {
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    for offset in [1.99, 2.01] {
      let plane = Surface3D.plane(
        Plane3D(
          origin: Point3D(x: offset, y: 0.0, z: 0.0),
          normal: .unitX
        ))
      let intersections = try intersector.intersections(
        first: plane,
        second: torus,
        tolerance: tolerance
      )
      #expect(intersections.isEmpty == false)
      for intersection in intersections {
        guard case .curve(let result) = intersection,
          case .analyticAnalytic(let exact) = result.truth,
          let certificate = exact.planeTorusCurve
        else {
          Issue.record("A nearby regular section must retain certified plane-torus truth.")
          continue
        }
        #expect(certificate.componentKind != .negativeInnerTangencyBranch)
        #expect(certificate.componentKind != .positiveInnerTangencyBranch)
        #expect(result.kind == .transverse)
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func separatedConeTorusPairReturnsExactEmptyIntersection() throws {
    let cone = Surface3D.analytic(
      .cone(
        apex: Point3D(x: 0.25, y: 0.0, z: 0.0),
        axis: .unitZ,
        halfAngle: Double.pi / 6.0
      ))
    let torus = Surface3D.analytic(
      .torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
      ))
    let intersections = try intersector.intersections(
      first: cone,
      second: torus,
      tolerance: tolerance
    )

    #expect(intersections.isEmpty)
  }

  private func verifyGeneralPlaneTorusCurves(
    _ intersections: [SurfaceSurfaceIntersection],
    plane: Surface3D,
    torus: Surface3D
  ) throws {
    for intersection in intersections {
      guard case .curve(let result) = intersection,
        case .analyticAnalytic = result.truth,
        case .analytic(.planeTorus) = result.curve,
        case .periodic(let period) = result.curve.parameterDomain
      else {
        Issue.record("A regular general plane-torus section must use certified algebraic truth.")
        continue
      }
      let lower = 0.0
      let upper = period
      #expect(result.kind == .transverse)
      #expect(result.maximumResidual <= tolerance.distance)
      try result.firstSurfaceParameterCurve.validate(
        on: plane,
        tolerance: tolerance
      )
      try result.secondSurfaceParameterCurve.validate(
        on: torus,
        tolerance: tolerance
      )
      let encoded = try JSONEncoder().encode(intersection)
      let decoded = try JSONDecoder().decode(
        SurfaceSurfaceIntersection.self,
        from: encoded
      )
      #expect(decoded == intersection)
      for index in 0...24 {
        let parameter = lower + (upper - lower) * Double(index) / 24.0
        let point = try result.curve.point(
          at: parameter,
          tolerance: tolerance
        )
        let planeProjection = try plane.parameterProjection(
          of: point,
          tolerance: tolerance
        )
        let torusProjection = try torus.parameterProjection(
          of: point,
          tolerance: tolerance
        )
        #expect(planeProjection.residual <= tolerance.distance)
        #expect(torusProjection.residual <= tolerance.distance)
      }
      for fraction in [0.125, 0.5, 0.875] {
        let firstDifferential = try result.firstSurfaceParameterCurve
          .differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
          )
        let secondDifferential = try result.secondSurfaceParameterCurve
          .differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
          )
        #expect(firstDifferential.firstDerivative.x.isFinite)
        #expect(firstDifferential.firstDerivative.y.isFinite)
        #expect(secondDifferential.firstDerivative.x.isFinite)
        #expect(secondDifferential.firstDerivative.y.isFinite)
      }
    }
  }

  private func verifyInnerTangentPlaneTorusGraph(
    _ intersections: [SurfaceSurfaceIntersection],
    plane: Surface3D,
    torus: Surface3D,
    expectedContact: Point3D
  ) throws {
    #expect(intersections.count == 2)
    var componentKinds: Set<CertifiedPlaneTorusIntersectionCurve.ComponentKind> = []
    var interiorPoints: [Point3D] = []
    var contactRays: [Vector3D] = []

    for intersection in intersections {
      guard case .curve(let result) = intersection,
        case .analyticAnalytic(let exact) = result.truth,
        let certificate = exact.planeTorusCurve,
        case .analytic(.planeTorus) = result.curve,
        case .closed(let lower, let upper) = result.curve.parameterDomain
      else {
        Issue.record("An inner-support section must retain bounded certified plane-torus truth.")
        continue
      }
      componentKinds.insert(certificate.componentKind)
      #expect(result.kind == .mixed)
      #expect(abs(lower) <= tolerance.angle)
      #expect(abs(upper - 2.0 * Double.pi) <= tolerance.angle)
      #expect(result.maximumResidual <= tolerance.distance)

      let start = try result.curve.differentialGeometry(
        at: lower,
        tolerance: tolerance
      )
      let end = try result.curve.differentialGeometry(
        at: upper,
        tolerance: tolerance
      )
      #expect(
        start.position.isApproximatelyEqual(
          to: expectedContact,
          tolerance: tolerance.distance
        ))
      #expect(
        end.position.isApproximatelyEqual(
          to: expectedContact,
          tolerance: tolerance.distance
        ))
      #expect(start.firstDerivative.length > tolerance.distance)
      #expect(end.firstDerivative.length > tolerance.distance)
      #expect(abs(start.tangent.dot(end.tangent)) < 1.0 - tolerance.angle)
      let step = 1.0e-3
      let nearStart = try result.curve.point(
        at: lower + step,
        tolerance: tolerance
      )
      let startFirstOrder = start.firstDerivative * step
      let startSecondOrder = start.secondDerivative * (0.5 * step * step)
      let predictedNearStart = (start.position + startFirstOrder) + startSecondOrder
      let nearEnd = try result.curve.point(
        at: upper - step,
        tolerance: tolerance
      )
      let endFirstOrder = end.firstDerivative * -step
      let endSecondOrder = end.secondDerivative * (0.5 * step * step)
      let predictedNearEnd = (end.position + endFirstOrder) + endSecondOrder
      #expect((nearStart - predictedNearStart).length <= tolerance.distance * 8.0)
      #expect((nearEnd - predictedNearEnd).length <= tolerance.distance * 8.0)
      contactRays.append(start.tangent)
      contactRays.append(-end.tangent)

      interiorPoints.append(
        try result.curve.point(
          at: Double.pi,
          tolerance: tolerance
        ))
      try result.firstSurfaceParameterCurve.validate(
        on: plane,
        tolerance: tolerance
      )
      try result.secondSurfaceParameterCurve.validate(
        on: torus,
        tolerance: tolerance
      )
      for fraction in [0.0, 0.125, 0.5, 0.875, 1.0] {
        let curveDifferential = try exact.differential(
          atNormalizedFraction: fraction,
          tolerance: tolerance
        )
        for (surface, parameterCurve) in [
          (plane, result.firstSurfaceParameterCurve),
          (torus, result.secondSurfaceParameterCurve),
        ] {
          let parameterDifferential = try parameterCurve.differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
          )
          let surfaceDifferential = try surface.differentialGeometry(
            atU: parameterDifferential.parameter.u,
            v: parameterDifferential.parameter.v,
            tolerance: tolerance
          )
          let reconstructedPoint = surfaceDifferential.position
          let reconstructedTangent =
            surfaceDifferential.tangentU
            * parameterDifferential.firstDerivative.x
            + surfaceDifferential.tangentV
            * parameterDifferential.firstDerivative.y
          #expect(
            reconstructedPoint.isApproximatelyEqual(
              to: curveDifferential.position,
              tolerance: tolerance.distance
            ))
          #expect(
            (reconstructedTangent - curveDifferential.firstDerivative).length
              <= tolerance.relative * max(curveDifferential.firstDerivative.length, 1.0))
          #expect(parameterDifferential.secondDerivative.x.isFinite)
          #expect(parameterDifferential.secondDerivative.y.isFinite)
        }
      }

      let encoded = try JSONEncoder().encode(intersection)
      let decoded = try JSONDecoder().decode(
        SurfaceSurfaceIntersection.self,
        from: encoded
      )
      #expect(decoded == intersection)

      let encodedCertificate = try JSONEncoder().encode(certificate)
      var payload = try #require(
        JSONSerialization.jsonObject(
          with: encodedCertificate
        ) as? [String: Any])
      var shiftedRootPayload = payload
      shiftedRootPayload["lowerMinorAngle"] =
        certificate.lowerMinorAngle
        + 2.0 * Double.pi
      let shiftedRoot = try JSONSerialization.data(
        withJSONObject: shiftedRootPayload
      )
      do {
        _ = try JSONDecoder().decode(
          CertifiedPlaneTorusIntersectionCurve.self,
          from: shiftedRoot
        )
        Issue.record("A shifted nodal root must fail certificate decoding.")
      } catch {
      }
      payload["componentKind"] = "positiveFullBranch"
      let corrupted = try JSONSerialization.data(withJSONObject: payload)
      do {
        _ = try JSONDecoder().decode(
          CertifiedPlaneTorusIntersectionCurve.self,
          from: corrupted
        )
        Issue.record("A changed nodal component kind must fail certificate decoding.")
      } catch {
      }
    }

    #expect(
      componentKinds == [
        .negativeInnerTangencyBranch,
        .positiveInnerTangencyBranch,
      ])
    #expect(interiorPoints.count == 2)
    if interiorPoints.count == 2 {
      #expect(
        interiorPoints[0].isApproximatelyEqual(
          to: interiorPoints[1],
          tolerance: tolerance.distance
        ) == false)
    }
    #expect(contactRays.count == 4)
    for firstIndex in contactRays.indices {
      for secondIndex in contactRays.indices where secondIndex > firstIndex {
        #expect(
          contactRays[firstIndex].dot(contactRays[secondIndex])
            < 1.0 - tolerance.angle)
      }
    }
  }

  private func intersectionCurves(
    _ intersections: [SurfaceSurfaceIntersection]
  ) -> [Curve3D] {
    intersections.compactMap {
      guard case .curve(let result) = $0 else { return nil }
      return result.curve
    }
  }

  private func proceduralCircleSurfaces() -> (plane: Surface3D, graph: Surface3D) {
    let plane = BSplineSurface3D(
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
    let quadraticCoefficients = [0.25, -0.25, 0.25]
    let graph = BSplineSurface3D(
      uDegree: 2,
      vDegree: 2,
      uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      controlPoints: (0..<3).map { vIndex in
        (0..<3).map { uIndex in
          Point3D(
            x: Double(uIndex) * 0.5,
            y: Double(vIndex) * 0.5,
            z: quadraticCoefficients[uIndex]
              + quadraticCoefficients[vIndex]
              - 0.25 * 0.25
          )
        }
      },
      weights: Array(
        repeating: Array(repeating: 1.0, count: 3),
        count: 3
      )
    )
    return (
      .procedural(
        .offset(
          OffsetSurface3D(
            source: .bSpline(plane),
            distance: 0.0
          ))),
      .procedural(
        .offset(
          OffsetSurface3D(
            source: .bSpline(graph),
            distance: 0.0
          )))
    )
  }

  private func proceduralTwoLineSurfaces() -> (plane: Surface3D, graph: Surface3D) {
    let plane = BSplineSurface3D(
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
    let graph = BSplineSurface3D(
      uDegree: 2,
      vDegree: 1,
      uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: (0...1).map { vIndex in
        [0.21, -0.29, 0.21].enumerated().map { uIndex, height in
          Point3D(
            x: Double(uIndex) / 2.0,
            y: Double(vIndex),
            z: height
          )
        }
      },
      weights: Array(
        repeating: Array(repeating: 1.0, count: 3),
        count: 2
      )
    )
    return (
      .bSpline(plane),
      .procedural(
        .offset(
          OffsetSurface3D(
            source: .bSpline(graph),
            distance: 0.01
          )))
    )
  }

  private func verifyRuledPlaneSection(
    _ intersections: [SurfaceSurfaceIntersection],
    ruled: Surface3D,
    sectionPlane: Surface3D,
    ruledRole: SurfaceIntersectionSurfaceRole
  ) throws {
    #expect(intersections.count == 1)
    guard case .curve(let result) = try #require(intersections.first) else {
      Issue.record("A transverse ruled-surface section must produce one curve.")
      return
    }
    let planeRole: SurfaceIntersectionSurfaceRole =
      ruledRole == .first
      ? .second
      : .first
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let ruledParameter = try result.surfaceParameter(
        on: ruledRole,
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let planeParameter = try result.surfaceParameter(
        on: planeRole,
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let ruledPoint = try ruled.point(
        u: ruledParameter.u,
        v: ruledParameter.v,
        tolerance: tolerance
      )
      let planePoint = try sectionPlane.point(
        u: planeParameter.u,
        v: planeParameter.v,
        tolerance: tolerance
      )
      #expect(
        ruledPoint.isApproximatelyEqual(
          to: planePoint,
          tolerance: tolerance.distance
        ))
      #expect(abs(ruledPoint.x - 0.5) <= tolerance.distance)
      #expect(abs(ruledPoint.y - ruledPoint.z) <= tolerance.distance)
    }
  }
}
