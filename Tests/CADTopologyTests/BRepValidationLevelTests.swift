import Testing
import CADCore
import CADGeometry
@testable import CADTopology

@Suite("B-rep validation levels")
struct BRepValidationLevelTests {
    @Test
    func exactValidationRequiresFaceLocalPcurves() throws {
        let model = makePlanarSheet(includePcurves: false)

        try model.validate(level: .modeling, tolerance: .standard)
        #expect(throws: KernelError.self) {
            try model.validate(level: .exact, tolerance: .standard)
        }
    }

    @Test
    func exactValidationAcceptsConsistentPlanarPcurves() throws {
        try makePlanarSheet(includePcurves: true).validate(level: .exact, tolerance: .standard)
    }

    @Test
    func exactBodyCertificatesComposeOwnershipClosedBodies() throws {
        let first = try ValidatedBRepModel(
            makePlanarSheet(includePcurves: true),
            tolerance: .standard
        )
        let second = try ValidatedBRepModel(
            makePlanarSheet(includePcurves: true),
            tolerance: .standard
        )
        let composed = merge(first.model, second.model)
        let firstBodyID = try #require(first.model.bodies.keys.first)
        let secondBodyID = try #require(second.model.bodies.keys.first)

        let validated = try ValidatedBRepModel(
            composingValidatedBodies: [firstBodyID: first, secondBodyID: second],
            as: composed,
            tolerance: .standard
        )

        #expect(validated.model == composed)
        #expect(validated.validationLevel == .exact)
    }

    @Test
    func exactBodyCertificateCompositionRejectsMissingCoverage() throws {
        let first = try ValidatedBRepModel(
            makePlanarSheet(includePcurves: true),
            tolerance: .standard
        )
        let second = try ValidatedBRepModel(
            makePlanarSheet(includePcurves: true),
            tolerance: .standard
        )
        let composed = merge(first.model, second.model)
        let firstBodyID = try #require(first.model.bodies.keys.first)

        #expect(throws: KernelError.self) {
            try ValidatedBRepModel(
                composingValidatedBodies: [firstBodyID: first],
                as: composed,
                tolerance: .standard
            )
        }
    }

    @Test
    func exactBodyCertificateCompositionRejectsMismatchedIdentity() throws {
        let certified = try ValidatedBRepModel(
            makePlanarSheet(includePcurves: true),
            tolerance: .standard
        )
        let certifiedBodyID = try #require(certified.model.bodies.keys.first)
        let outputBodyID = BodyID()
        var output = certified.model
        let certifiedBody = try #require(output.bodies[certifiedBodyID])
        output.bodies.removeValue(forKey: certifiedBodyID)
        output.bodies[outputBodyID] = Body(
            id: outputBodyID,
            topology: certifiedBody.topology,
            name: certifiedBody.name,
            material: certifiedBody.material
        )

        #expect(throws: KernelError.self) {
            try ValidatedBRepModel(
                composingValidatedBodies: [outputBodyID: certified],
                as: output,
                tolerance: .standard
            )
        }
    }

    @Test
    func exactBodyCertificateCompositionRejectsSharedOwnedIdentity() throws {
        let first = try ValidatedBRepModel(
            makePlanarSheet(includePcurves: true),
            tolerance: .standard
        )
        let firstBodyID = try #require(first.model.bodies.keys.first)
        let secondBodyID = BodyID()
        let firstBody = try #require(first.model.bodies[firstBodyID])
        var secondModel = first.model
        secondModel.bodies.removeValue(forKey: firstBodyID)
        secondModel.bodies[secondBodyID] = Body(
            id: secondBodyID,
            topology: firstBody.topology,
            name: firstBody.name,
            material: firstBody.material
        )
        let second = try ValidatedBRepModel(secondModel, tolerance: .standard)
        let composed = merge(first.model, second.model)

        #expect(throws: KernelError.self) {
            try ValidatedBRepModel(
                composingValidatedBodies: [firstBodyID: first, secondBodyID: second],
                as: composed,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func exactValidationAcceptsCertifiedImplicitLoopOnSphere() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 0.030))
        let boundedSurface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -0.045, y: -0.045, z: 0.0),
                    Point3D(x: 0.045, y: -0.045, z: 0.0),
                ],
                [
                    Point3D(x: -0.045, y: 0.045, z: 0.0),
                    Point3D(x: 0.045, y: 0.045, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 1.25],
                [0.8, 1.0],
            ]
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: boundedSurface,
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 4,
                maximumIterations: 48,
                maximumSeedCount: 1_024
            ),
            tolerance: .standard
        )
        let exactIntersections: [SurfaceSurfaceIntersectionCurve] = intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection,
                  case .analyticBSpline = curve.truth else {
                return nil
            }
            return curve
        }
        let exactIntersection = try #require(exactIntersections.only)
        let curve = exactIntersection.curve
        let pcurve = exactIntersection.firstSurfaceParameterCurve
        let vertexIDs = [VertexID(), VertexID()]
        let edgeIDs = [EdgeID(), EdgeID()]
        let curveID = CurveID()
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        let shellID = ShellID()
        let bodyID = BodyID()
        let fractions = [0.0, 0.5, 1.0]
        let points = try fractions.map {
            try curve.point(at: $0, tolerance: .standard)
        }
        let edges = Dictionary(uniqueKeysWithValues: edgeIDs.enumerated().map { index, edgeID in
            (edgeID, Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[(index + 1) % vertexIDs.count],
                trim: CurveTrim(
                    startParameter: fractions[index],
                    endParameter: fractions[index + 1]
                )
            ))
        })
        let coedges = try edgeIDs.enumerated().map { index, edgeID in
            Coedge(
                edgeID: edgeID,
                surfaceParameterCurve: try pcurve.trimmed(
                    from: fractions[index],
                    to: fractions[index + 1],
                    curveDomain: curve.parameterDomain,
                    tolerance: .standard
                )
            )
        }
        let model = BRepModel(
            geometry: GeometryStore(
                curves: [curveID: curve],
                surfaces: [surfaceID: sphere]
            ),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: coedges)],
            edges: edges,
            vertices: [
                vertexIDs[0]: Vertex(id: vertexIDs[0], point: points[0]),
                vertexIDs[1]: Vertex(id: vertexIDs[1], point: points[1]),
            ]
        )

        try model.validate(level: .exact, tolerance: .standard)
    }

    private func makePlanarSheet(includePcurves: Bool) -> BRepModel {
        let points = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let vertexIDs = points.map { _ in VertexID() }
        let edgeIDs = points.map { _ in EdgeID() }
        let curveIDs = points.map { _ in CurveID() }
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        let shellID = ShellID()
        let bodyID = BodyID()
        let directions = [Vector3D.unitX, Vector3D.unitY, -Vector3D.unitX, -Vector3D.unitY]
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]

        let vertices = Dictionary(uniqueKeysWithValues: vertexIDs.enumerated().map { index, id in
            (id, Vertex(id: id, point: points[index]))
        })
        let curves = Dictionary(uniqueKeysWithValues: curveIDs.enumerated().map { index, id in
            (id, Curve3D.line(Line3D(origin: points[index], direction: directions[index])))
        })
        let edges = Dictionary(uniqueKeysWithValues: edgeIDs.enumerated().map { index, id in
            (id, Edge(
                id: id,
                curveID: curveIDs[index],
                startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[(index + 1) % vertexIDs.count],
                trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
            ))
        })
        let coedges = edgeIDs.enumerated().map { index, edgeID in
            Coedge(
                edgeID: edgeID,
                surfaceParameterCurve: includePcurves ? pcurves[index] : nil
            )
        }

        return BRepModel(
            geometry: GeometryStore(
                curves: curves,
                surfaces: [
                    surfaceID: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                ]
            ),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: coedges)],
            edges: edges,
            vertices: vertices
        )
    }

    private func merge(_ first: BRepModel, _ second: BRepModel) -> BRepModel {
        var result = first
        merge(second.geometry.curves, into: &result.geometry.curves)
        merge(second.geometry.surfaces, into: &result.geometry.surfaces)
        merge(second.bodies, into: &result.bodies)
        merge(second.shells, into: &result.shells)
        merge(second.faces, into: &result.faces)
        merge(second.loops, into: &result.loops)
        merge(second.edges, into: &result.edges)
        merge(second.vertices, into: &result.vertices)
        return result
    }

    private func merge<Key: Hashable, Value>(
        _ source: PersistentMap<Key, Value>,
        into destination: inout PersistentMap<Key, Value>
    ) {
        for (key, value) in source {
            destination[key] = value
        }
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
