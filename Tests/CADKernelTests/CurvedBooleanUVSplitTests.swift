import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation
import Testing

@testable import CADKernel

@Suite("Curved Boolean UV Split")
struct CurvedBooleanUVSplitTests {
  private let tolerance = ModelingTolerance.standard

  @Test(.timeLimit(.minutes(1)))
  func cylinderPlaneCircleIsClippedToExactHalfCircleInterval() throws {
    let cylinderSurface = Surface3D.analytic(
      .cylinder(
        origin: .origin,
        axis: .unitZ,
        radius: 1.0
      ))
    let planeSurface = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
    let cylinderSurfaceID = SurfaceID()
    let planeSurfaceID = SurfaceID()
    let cylinderPoints = [
      try cylinderSurface.point(u: 0.0, v: -1.0, tolerance: tolerance),
      try cylinderSurface.point(u: Double.pi, v: -1.0, tolerance: tolerance),
      try cylinderSurface.point(u: Double.pi, v: 1.0, tolerance: tolerance),
      try cylinderSurface.point(u: 0.0, v: 1.0, tolerance: tolerance),
    ]
    let planePoints = [
      Point3D(x: -2.0, y: -2.0, z: 0.0),
      Point3D(x: 2.0, y: -2.0, z: 0.0),
      Point3D(x: 2.0, y: 2.0, z: 0.0),
      Point3D(x: -2.0, y: 2.0, z: 0.0),
    ]
    let cylinderFace = try makeFace(
      surfaceID: cylinderSurfaceID,
      surface: cylinderSurface,
      points: cylinderPoints
    )
    let planeFace = try makeFace(
      surfaceID: planeSurfaceID,
      surface: planeSurface,
      points: planePoints
    )
    let model = BRepModel(
      geometry: GeometryStore(
        curves: cylinderFace.curves.merging(planeFace.curves) { current, _ in current },
        surfaces: [
          cylinderSurfaceID: cylinderSurface,
          planeSurfaceID: planeSurface,
        ]
      ),
      faces: [
        cylinderFace.face.id: cylinderFace.face,
        planeFace.face.id: planeFace.face,
      ],
      loops: [
        cylinderFace.loop.id: cylinderFace.loop,
        planeFace.loop.id: planeFace.loop,
      ],
      edges: cylinderFace.edges.merging(planeFace.edges) { current, _ in current },
      vertices: cylinderFace.vertices.merging(planeFace.vertices) { current, _ in current }
    )
    let pair = BooleanFacePairCandidate(
      targetFaceID: cylinderFace.face.id,
      toolFaceID: planeFace.face.id
    )
    let surfaceIntersection = try #require(
      DefaultSurfaceSurfaceIntersector().intersections(
        first: cylinderSurface,
        second: planeSurface,
        tolerance: tolerance
      ).first)
    let positiveY = Point3D(x: 0.0, y: 1.0, z: 0.0)
    let negativeY = Point3D(x: 0.0, y: -1.0, z: 0.0)
    let graph = BooleanIntersectionGraph(
      facePairs: [pair],
      boundaryContacts: [
        BooleanBoundaryContact(
          edgeID: cylinderFace.edgeIDs[3],
          curveFaceID: cylinderFace.face.id,
          surfaceFaceID: planeFace.face.id,
          geometry: .points([try contact(at: positiveY)])
        ),
        BooleanBoundaryContact(
          edgeID: cylinderFace.edgeIDs[1],
          curveFaceID: cylinderFace.face.id,
          surfaceFaceID: planeFace.face.id,
          geometry: .points([try contact(at: negativeY)])
        ),
      ],
      faceIntersections: [
        BooleanFaceSurfaceIntersection(
          facePair: pair,
          geometry: surfaceIntersection
        )
      ]
    )

    let splitGraph = try DefaultBooleanUVFaceSplitter().splitGraph(
      intersectionGraph: graph,
      model: model,
      tolerance: tolerance
    )
    let split = try #require(splitGraph.splits.first)
    let chains = split.components.compactMap { component -> BooleanTrimmedFaceIntersectionChain? in
      guard case .trimmedCurve(let chain) = component.geometry else { return nil }
      return chain
    }
    let curves = chains.flatMap(\.segments)
    guard curves.isEmpty == false else {
      Issue.record("A partially trimmed circle must remain an exact trimmed curve.")
      return
    }
    let curve = try #require(curves.first)
    #expect(chains.count == 1)
    #expect(curves.count == 1)
    #expect(abs(curve.startParameter - Double.pi * 0.5) <= tolerance.angle)
    #expect(abs(curve.endParameter - Double.pi * 1.5) <= tolerance.angle)
    #expect(curve.start.point.isApproximatelyEqual(to: positiveY, tolerance: tolerance.distance))
    #expect(curve.end.point.isApproximatelyEqual(to: negativeY, tolerance: tolerance.distance))
    #expect(curve.intersection.maximumResidual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func boundedClosedBSplineIntersectionUsesDualPcurvesForCompleteLoop() throws {
    let planarSurface = Surface3D.bSpline(
      BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: surfaceControlPoints(centerHeight: 0.0)
      ))
    let raisedSurface = Surface3D.bSpline(
      BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: surfaceControlPoints(centerHeight: 1.0)
      ))
    let planarSurfaceID = SurfaceID()
    let raisedSurfaceID = SurfaceID()
    let planarFace = Face(surfaceID: planarSurfaceID, loops: [])
    let raisedFace = Face(surfaceID: raisedSurfaceID, loops: [])
    let targetShell = Shell(faceIDs: [planarFace.id])
    let toolShell = Shell(faceIDs: [raisedFace.id])
    let targetBody = Body(
      solidComponents: [SolidShellComponent(outerShellID: targetShell.id)]
    )
    let toolBody = Body(
      solidComponents: [SolidShellComponent(outerShellID: toolShell.id)]
    )
    let model = BRepModel(
      geometry: GeometryStore(surfaces: [
        planarSurfaceID: planarSurface,
        raisedSurfaceID: raisedSurface,
      ]),
      bodies: [
        targetBody.id: targetBody,
        toolBody.id: toolBody,
      ],
      shells: [
        targetShell.id: targetShell,
        toolShell.id: toolShell,
      ],
      faces: [
        planarFace.id: planarFace,
        raisedFace.id: raisedFace,
      ]
    )
    let pair = BooleanFacePairCandidate(
      targetFaceID: planarFace.id,
      toolFaceID: raisedFace.id
    )
    let curveControlPoints = [
      Point3D(x: 0.0, y: 0.0, z: 0.0),
      Point3D(x: 1.0, y: 0.0, z: 0.0),
      Point3D(x: 1.0, y: 1.0, z: 0.0),
      Point3D(x: 0.0, y: 1.0, z: 0.0),
      Point3D(x: 0.0, y: 0.0, z: 0.0),
    ]
    let curveKnots = [10.0, 10.0, 11.0, 12.0, 13.0, 14.0, 14.0]
    let intersectionCurve = Curve3D.bSpline(
      BSplineCurve3D(
        degree: 1,
        knots: curveKnots,
        controlPoints: curveControlPoints
      ))
    let parameterCurve = SurfaceParameterCurve.bSpline(
      BSplineCurve2D(
        degree: 1,
        knots: curveKnots,
        controlPoints: curveControlPoints.map { Point2D(x: $0.x, y: $0.y) }
      ))
    let anchor = try SurfaceParameterProjection(
      u: 0.0,
      v: 0.0,
      point: curveControlPoints[0],
      residual: 0.0
    )
    let intersection = try SurfaceSurfaceIntersectionCurve(
      truth: .parametric(intersectionCurve),
      derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
        curve: intersectionCurve,
        firstSurfaceParameterCurve: parameterCurve,
        secondSurfaceParameterCurve: parameterCurve,
        maximumResidualUpperBound: 0.0,
        tolerance: tolerance
      ),
      kind: .transverse,
      firstSurfaceAnchor: anchor,
      secondSurfaceAnchor: anchor,
      tolerance: tolerance
    )
    let graph = BooleanIntersectionGraph(
      facePairs: [pair],
      boundaryContacts: [],
      faceIntersections: [
        BooleanFaceSurfaceIntersection(
          facePair: pair,
          geometry: .curve(intersection)
        )
      ]
    )

    let splitGraph = try DefaultBooleanUVFaceSplitter(
      facePointContainment: AlwaysContainsFacePointTester()
    ).splitGraph(
      intersectionGraph: graph,
      model: model,
      tolerance: tolerance
    )

    let split = try #require(splitGraph.splits.first)
    let component = try #require(split.components.first)
    guard case .closedCurve(let closedCurve) = component.geometry else {
      Issue.record("A bounded B-spline with coincident endpoints must form a closed UV split.")
      return
    }
    #expect(closedCurve.samples.count == 32)
    #expect(closedCurve.samples.allSatisfy { $0.uvPoint.residual <= tolerance.distance })
    #expect(
      closedCurve.samples.contains { sample in
        sample.uvPoint.targetU > tolerance.distance
          && sample.uvPoint.targetU < 1.0 - tolerance.distance
          && abs(sample.uvPoint.targetV) <= tolerance.distance
      })
    #expect(closedCurve.samples[1].curveParameter > 10.0)
    #expect(closedCurve.intersection.firstSurfaceParameterCurve == parameterCurve)
    #expect(closedCurve.intersection.secondSurfaceParameterCurve == parameterCurve)

    let classificationGraph = try DefaultBooleanRegionClassifier().classificationGraph(
      uvSplitGraph: splitGraph,
      targetBodyIDs: [targetBody.id],
      toolBodyID: toolBody.id,
      model: model,
      operands: BooleanOperandContext(solidities: .volumes, pointClassifier: BoundaryBandSolidPointClassifier()),
      tolerance: tolerance
    )
    #expect(classificationGraph.samples.count == 4)
    #expect(classificationGraph.samples.allSatisfy { $0.classification == .outside })
    do {
      _ = try DefaultBooleanRegionClassifier().classificationGraph(
        uvSplitGraph: splitGraph,
        targetBodyIDs: [targetBody.id],
        toolBodyID: toolBody.id,
        model: model,
        operands: BooleanOperandContext(solidities: .volumes, pointClassifier: AlwaysBoundarySolidPointClassifier()),
        tolerance: tolerance
      )
      Issue.record("Persistent boundary classifications must return a typed failure.")
    } catch let error as KernelError {
      #expect(error.code == .classificationFailure)
      #expect(error.phase == .classification)
    }
  }

  @Test(.timeLimit(.minutes(3)))
  func generalProceduralImplicitLoopReachesBooleanSplitAndExactSewing() throws {
    let (planarSurface, graphSurface) = proceduralCircularIntersectionSurfaces()
    let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
      first: planarSurface,
      second: graphSurface,
      tolerance: tolerance
    )
    guard intersections.count == 1,
      case .curve(let intersection) = intersections[0],
      case .implicit(let implicit) = intersection.truth
    else {
      Issue.record(
        "A procedural Boolean fixture must retain certified implicit truth."
      )
      return
    }
    #expect(implicit.isClosed)

    let planarSurfaceID = SurfaceID()
    let graphSurfaceID = SurfaceID()
    let planarFace = Face(surfaceID: planarSurfaceID, loops: [])
    let graphFace = Face(surfaceID: graphSurfaceID, loops: [])
    let pair = BooleanFacePairCandidate(
      targetFaceID: planarFace.id,
      toolFaceID: graphFace.id
    )
    let model = BRepModel(
      geometry: GeometryStore(surfaces: [
        planarSurfaceID: planarSurface,
        graphSurfaceID: graphSurface,
      ]),
      faces: [
        planarFace.id: planarFace,
        graphFace.id: graphFace,
      ]
    )
    let splitGraph = try DefaultBooleanUVFaceSplitter(
      facePointContainment: AlwaysContainsFacePointTester()
    ).splitGraph(
      intersectionGraph: BooleanIntersectionGraph(
        facePairs: [pair],
        boundaryContacts: [],
        faceIntersections: [
          BooleanFaceSurfaceIntersection(
            facePair: pair,
            geometry: .curve(intersection)
          )
        ]
      ),
      model: model,
      tolerance: tolerance
    )

    #expect(splitGraph.splits.count == 1)
    let split = try #require(splitGraph.splits.first)
    #expect(split.components.count == 1)
    let component = try #require(split.components.first)
    guard case .closedCurve(let closedCurve) = component.geometry,
      case .implicit = closedCurve.intersection.truth
    else {
      Issue.record(
        "The Boolean UV split must preserve the procedural implicit loop."
      )
      return
    }
    #expect(closedCurve.samples.count == 32)
    #expect(
      closedCurve.samples.allSatisfy {
        $0.uvPoint.residual <= tolerance.distance
      })

    let sewingLoops = try ClosedIntersectionSewingLoopBuilder().loops(
      for: closedCurve,
      firstStableID: "procedural-plane-loop",
      secondStableID: "procedural-graph-loop",
      tolerance: tolerance
    )
    let sewingResult = try DefaultBRepSewer().sew(
      BRepSewingRequest(
        featureID: FeatureID(),
        bodyKind: .sheet,
        shells: [
          BRepSewingShell(
            stableID: "procedural-intersection-shell",
            patches: [
              BRepSewingFacePatch(
                stableID: "procedural-plane-face",
                surface: planarSurface,
                orientation: .forward,
                loops: [sewingLoops.first]
              ),
              BRepSewingFacePatch(
                stableID: "procedural-graph-face",
                surface: graphSurface,
                orientation: .forward,
                loops: [sewingLoops.second]
              ),
            ]
          )
        ]
      ),
      tolerance: tolerance
    )
    #expect(sewingResult.validatedBRep.validationLevel == .exact)
    #expect(sewingResult.brep.faces.count == 2)
    #expect(sewingResult.brep.edges.count == 2)
    #expect(sewingResult.brep.vertices.count == 2)
    try sewingResult.brep.validate(level: .exact, tolerance: tolerance)
  }

  private func contact(at point: Point3D) throws -> CurveSurfaceIntersection {
    try CurveSurfaceIntersection(
      point: point,
      curveParameter: 0.0,
      surfaceU: 0.0,
      surfaceV: 0.0,
      kind: .transverse,
      residual: 0.0,
      iterations: 0
    )
  }

  private func makeFace(
    surfaceID: SurfaceID,
    surface: Surface3D,
    points: [Point3D]
  ) throws -> FaceFixture {
    let vertexIDs = points.map { _ in VertexID() }
    let edgeIDs = points.map { _ in EdgeID() }
    let loopID = LoopID()
    let faceID = FaceID()
    let vertices = Dictionary(
      uniqueKeysWithValues: zip(vertexIDs, points).map {
        ($0.0, Vertex(id: $0.0, point: $0.1))
      })
    var curves: [CurveID: Curve3D] = [:]
    var pcurves: [SurfaceParameterCurve] = []
    let edges: [EdgeID: Edge] = try Dictionary(
      uniqueKeysWithValues: edgeIDs.indices.map { index in
        let edgeID = edgeIDs[index]
        let start = points[index]
        let end = points[(index + 1) % points.count]
        let startParameter = try surface.parameterProjection(
          of: start,
          tolerance: tolerance
        )
        let endParameter = try surface.parameterProjection(
          of: end,
          tolerance: tolerance
        )
        let pcurve = SurfaceParameterCurve.polyline([
          SurfaceParameter(u: startParameter.u, v: startParameter.v),
          SurfaceParameter(u: endParameter.u, v: endParameter.v),
        ])
        pcurves.append(pcurve)
        let curveID = CurveID()
        curves[curveID] = .surfaceLift(
          SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: pcurve
          ))
        return (
          edgeID,
          Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: vertexIDs[index],
            endVertexID: vertexIDs[(index + 1) % vertexIDs.count]
          )
        )
      }
    )
    let loop = Loop(
      id: loopID,
      role: .outer,
      coedges: zip(edgeIDs, pcurves).map {
        Coedge(edgeID: $0.0, surfaceParameterCurve: $0.1)
      }
    )
    return FaceFixture(
      face: Face(id: faceID, surfaceID: surfaceID, loops: [loopID]),
      loop: loop,
      edges: edges,
      curves: curves,
      vertices: vertices,
      edgeIDs: edgeIDs
    )
  }

  private func surfaceControlPoints(centerHeight: Double) -> [[Point3D]] {
    [0.0, 0.5, 1.0].map { v in
      [0.0, 0.5, 1.0].map { u in
        let isCenter = u == 0.5 && v == 0.5
        return Point3D(
          x: u,
          y: v,
          z: isCenter ? centerHeight : 0.0
        )
      }
    }
  }

  private func proceduralCircularIntersectionSurfaces() -> (
    plane: Surface3D,
    graph: Surface3D
  ) {
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
    return (
      plane: .bSpline(plane),
      graph: .procedural(
        .offset(
          OffsetSurface3D(
            source: .bSpline(graph),
            distance: offsetDistance
          )))
    )
  }

  private struct AlwaysContainsFacePointTester: FacePointContainmentTesting {
    func contains(
      _ point: Point3D,
      on faceID: FaceID,
      in model: BRepModel,
      tolerance: ModelingTolerance
    ) throws -> Bool {
      _ = point
      _ = faceID
      _ = model
      try tolerance.validate()
      return true
    }
  }

  private struct BoundaryBandSolidPointClassifier: SolidPointClassifying {
    func classify(
      _ point: Point3D,
      in bodyID: BodyID,
      model: BRepModel,
      tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
      _ = point
      _ = bodyID
      _ = model
      try tolerance.validate()
      return abs(point.y) <= tolerance.distance * 24.0 ? .boundary : .outside
    }
  }

  private struct AlwaysBoundarySolidPointClassifier: SolidPointClassifying {
    func classify(
      _ point: Point3D,
      in bodyID: BodyID,
      model: BRepModel,
      tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
      _ = point
      _ = bodyID
      _ = model
      try tolerance.validate()
      return .boundary
    }
  }

  private struct FaceFixture {
    let face: Face
    let loop: Loop
    let edges: [EdgeID: Edge]
    let curves: [CurveID: Curve3D]
    let vertices: [VertexID: Vertex]
    let edgeIDs: [EdgeID]
  }
}
