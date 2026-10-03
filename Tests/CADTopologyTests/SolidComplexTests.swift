import CADCore
import CADGeometry
import CADTopology
import Testing

@Suite("Canonical face-connected solid cells")
struct SolidComplexTests {
    private let tolerance = ModelingTolerance.standard
    private let operation = DefaultShapeOperator()

    private struct Cell {
        let bodyID: BodyID
        let shellID: ShellID
        let interfaceFaceID: FaceID
        let interfaceLoopID: LoopID
    }

    private struct Fixture {
        var model: BRepModel
        let upper: Cell
        let lower: Cell
        let voidShellID: ShellID?

        var interface: SolidInterface {
            SolidInterface(first: SolidFaceUse(bodyID: upper.bodyID, faceID: upper.interfaceFaceID),
                           second: SolidFaceUse(bodyID: lower.bodyID, faceID: lower.interfaceFaceID))
        }

        var complex: SolidComplexTopology {
            SolidComplexTopology(bodyIDs: [upper.bodyID, lower.bodyID], interfaces: [interface])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentAdjacentCellsPreserveMaterialVoidAndInputOwnership() throws {
        let fixture = try adjacentCells(withVoid: true)
        let original = fixture.model
        try fixture.model.validate(level: .exact, tolerance: tolerance)
        let source = Shape(root: .solidComplex(fixture.complex), model: original)
        var result = try operation.extract(source, tolerance: tolerance)
        #expect(result.root == source.root)
        #expect(result.model == original)
        #expect(result.model.bodies.count == 2)
        #expect(result.model.faces.count == 12)
        #expect(result.model.edges.count == 18)
        #expect(result.model.vertices.count == 12)
        #expect(fixture.upper.interfaceFaceID != fixture.lower.interfaceFaceID)
        let voidID = try #require(fixture.voidShellID)
        let upper = try #require(result.model.bodies[fixture.upper.bodyID])
        let lower = try #require(result.model.bodies[fixture.lower.bodyID])
        #expect(upper.material != nil && lower.material != nil && upper.material != lower.material)
        #expect(upper.solidComponents == [SolidShellComponent(outerShellID: fixture.upper.shellID,
                                                            voidShellIDs: [voidID])])
        #expect(lower.solidComponents == [SolidShellComponent(outerShellID: fixture.lower.shellID)])
        #expect(result.model.shells[voidID]?.orientation == .reversed)
        #expect(abs(try result.model.volume(tolerance: tolerance) - (1.0/3.0 - 1.0/3072.0)) < 1e-10)
        let subshapes = try operation.subshapes(of: source, tolerance: tolerance)
        #expect(subshapes.contains(.solid(upper.id)) && subshapes.contains(.solid(lower.id)))
        let vertexID = try #require(result.model.vertices.keys.first)
        var editedModel = result.model
        editedModel.vertices[vertexID] = Vertex(id: vertexID, point: Point3D(x: 9, y: 8, z: 7))
        #expect(source.model == original)
        #expect(result.model == original)
        #expect(editedModel != source.model)
    }

    @Test(.timeLimit(.minutes(1)))
    func compoundDoesNotAssertTheConnectedInterfaceContract() throws {
        let fixture = try adjacentCells()
        let compound = Shape(root: .compound(fixture.complex.bodyIDs.map(ShapeReference.solid)), model: fixture.model)
        let result = try operation.extract(compound, tolerance: tolerance)
        #expect(result.root == compound.root)
        #expect(result.model.bodies.count == 2)
        let disconnected = SolidComplexTopology(bodyIDs: fixture.complex.bodyIDs)
        try expect(.disconnectedCells, disconnected, in: fixture.model)
        let single = SolidComplexTopology(bodyIDs: [fixture.upper.bodyID])
        try DefaultSolidComplexValidator().validate(single, in: fixture.model, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func duplicateCellsAndRepeatedInterfaceOwnershipAreRejected() throws {
        let fixture = try adjacentCells()
        try expect(.invalidSelection, SolidComplexTopology(bodyIDs: []), in: fixture.model)
        try expect(.invalidSelection, SolidComplexTopology(bodyIDs: [fixture.upper.bodyID,fixture.upper.bodyID]),
                   in: fixture.model)
        let repeated = SolidComplexTopology(bodyIDs: fixture.complex.bodyIDs,
                                            interfaces: [fixture.interface,fixture.interface])
        try expect(.repeatedFaceUse(fixture.interface.first), repeated, in: fixture.model)
    }

    @Test(.timeLimit(.minutes(1)))
    func foreignFaceAndSameEffectiveOrientationAreRejected() throws {
        var fixture = try adjacentCells()
        let foreign = SolidFaceUse(bodyID: fixture.lower.bodyID, faceID: fixture.upper.interfaceFaceID)
        let badInterface = SolidInterface(first: fixture.interface.first, second: foreign)
        try expect(.foreignFaceUse(foreign), SolidComplexTopology(bodyIDs: fixture.complex.bodyIDs,
                                                                 interfaces: [badInterface]), in: fixture.model)
        var face = try #require(fixture.model.faces[fixture.upper.interfaceFaceID])
        face.orientation = .forward
        fixture.model.faces[face.id] = face
        try fixture.model.validate(level: .exact, tolerance: tolerance)
        try expect(.sameOrientation(fixture.interface), fixture.complex, in: fixture.model)
    }

    @Test(.timeLimit(.minutes(1)))
    func complexNeverGrantsSharedShellOrVoidOwnership() throws {
        let fixture = try adjacentCells(withVoid: true)
        for sharedShell in [fixture.upper.shellID, try #require(fixture.voidShellID)] {
            var model = fixture.model
            var lower = try #require(model.bodies[fixture.lower.bodyID])
            lower.topology = sharedShell == fixture.upper.shellID
                ? .solid(components: [SolidShellComponent(outerShellID: sharedShell)])
                : .solid(components: [SolidShellComponent(outerShellID: fixture.lower.shellID,
                                                          voidShellIDs: [sharedShell])])
            model.bodies[lower.id] = lower
            #expect(throws: TopologyError.self) {
                try DefaultSolidComplexValidator().validate(fixture.complex, in: model, tolerance: tolerance)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aCellMustHaveOneExplicitMaterialComponent() throws {
        var fixture = try adjacentCells()
        let separate = try appendTetrahedron(to: &fixture.model,
            points: [Point3D(x:2,y:0,z:0),Point3D(x:3,y:0,z:0),
                     Point3D(x:2,y:1,z:0),Point3D(x:2,y:0,z:1)], lower: false)
        fixture.model.bodies[separate.bodyID] = nil
        var upper = try #require(fixture.model.bodies[fixture.upper.bodyID])
        upper.topology = .solid(components: [SolidShellComponent(outerShellID: fixture.upper.shellID),
                                             SolidShellComponent(outerShellID: separate.shellID)])
        fixture.model.bodies[upper.id] = upper
        try fixture.model.validate(level: .exact, tolerance: tolerance)
        try expect(.invalidCell(upper.id), fixture.complex, in: fixture.model)
    }

    @Test(.timeLimit(.minutes(1)))
    func wholeCanonicalBoundaryIncludesCurveTrimAndReversedPcurve() throws {
        for mutation in 0..<5 {
            var fixture = try adjacentCells()
            var loop = try #require(fixture.model.loops[fixture.lower.interfaceLoopID])
            let use = loop.coedges[0]
            var edge = try #require(fixture.model.edges[use.edgeID])
            switch mutation {
            case 0:
                // Same complete line locus, distinct canonical curve representation.
                let curve = try #require(fixture.model.geometry.curves[edge.curveID])
                guard case .line(let line) = curve else {
                    Issue.record("The fixture must contain canonical lines."); return
                }
                fixture.model.geometry.curves[edge.curveID] = .analytic(.line(origin:line.origin,direction:line.direction))
            case 1:
                var trim = try #require(edge.trim)
                trim.startParameter += 1e-12
                edge.trim = trim
                fixture.model.edges[edge.id] = edge
            case 2:
                // Same endpoints and complete straight trace, different full chart data.
                let pcurve = try #require(use.surfaceParameterCurve)
                let a = try pcurve.startParameter(tolerance:tolerance)
                let b = try pcurve.endParameter(tolerance:tolerance)
                loop.coedges[0].surfaceParameterCurve = .polyline([a,
                    SurfaceParameter(u:(a.u+b.u)*0.5,v:(a.v+b.v)*0.5),b])
                fixture.model.loops[loop.id] = loop
            case 3:
                // Exact cell validation permits endpoint snapping within its tolerance;
                // canonical interface identity still requires identical stored points.
                var vertex = try #require(fixture.model.vertices[edge.startVertexID])
                vertex.point = Point3D(x:vertex.point.x+1e-12,y:vertex.point.y,z:vertex.point.z)
                fixture.model.vertices[vertex.id] = vertex
            default:
                let face = try #require(fixture.model.faces[fixture.lower.interfaceFaceID])
                fixture.model.geometry.surfaces[face.surfaceID] = .plane(
                    Plane3D(origin:Point3D(x:1e-12,y:0,z:0),normal:.unitZ))
            }
            try fixture.model.validate(level: .exact, tolerance: tolerance)
            try expect(.unprovenInterface(fixture.interface), fixture.complex, in: fixture.model)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func matchingEndpointsAndMidpointDoNotProveTheFullBoundary() throws {
        var fixture = try adjacentCells()
        var loop = try #require(fixture.model.loops[fixture.lower.interfaceLoopID])
        let original = try #require(loop.coedges[0].surfaceParameterCurve)
        let a = try original.startParameter(tolerance:tolerance)
        let b = try original.endParameter(tolerance:tolerance)
        let du = b.u-a.u, dv = b.v-a.v, bump = 0.05
        let changed = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree:3,knots:[0,0,0,0,1,1,1,1],
            controlPoints:[Point2D(x:a.u,y:a.v),
                Point2D(x:a.u+du/3-dv*bump,y:a.v+dv/3+du*bump),
                Point2D(x:a.u+2*du/3+dv*bump,y:a.v+2*dv/3-du*bump),Point2D(x:b.u,y:b.v)]))
        for fraction in [0.0,0.5,1.0] {
            let expected = try original.parameter(atNormalizedFraction:fraction,tolerance:tolerance)
            let actual = try changed.parameter(atNormalizedFraction:fraction,tolerance:tolerance)
            #expect(abs(actual.u-expected.u) < 1e-12 && abs(actual.v-expected.v) < 1e-12)
        }
        let interior = try changed.parameter(atNormalizedFraction:0.25,tolerance:tolerance)
        let straight = try original.parameter(atNormalizedFraction:0.25,tolerance:tolerance)
        #expect(abs(interior.u-straight.u)+abs(interior.v-straight.v) > 0.001)
        loop.coedges[0].surfaceParameterCurve = changed
        fixture.model.loops[loop.id] = loop
        #expect(throws: KernelError.self) {
            try DefaultSolidComplexValidator().validate(fixture.complex,in:fixture.model,tolerance:tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func comparisonBudgetsAndCancellationRemainExplicit() async throws {
        let fixture = try adjacentCells()
        try expect(.invalidWorkLimit,fixture.complex,in:fixture.model,
                   options:SolidComplexValidationOptions(maximumEdgeComparisons:0))
        try expect(.comparisonLimitExceeded(limit:1),fixture.complex,in:fixture.model,
                   options:SolidComplexValidationOptions(maximumEdgeComparisons:1))
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            try DefaultSolidComplexValidator().validate(fixture.complex,in:fixture.model,tolerance:tolerance)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidImagesPreserveInterfaceCellMaterialAndCavityIdentity() throws {
        let fixture = try adjacentCells(withVoid:true)
        let source = Shape(root:.solidComplex(fixture.complex),model:fixture.model)
        let transforms = [RigidTransform3D.translated(by:Vector3D(x:2,y:3,z:4)),
            try RigidTransform3D.rotated(around:.origin,direction:Vector3D(x:1,y:2,z:3),angle:0.73,tolerance:tolerance),
            try RigidTransform3D.mirrored(across:.origin,normal:.unitX,tolerance:tolerance)]
        for transform in transforms {
            let result = try operation.transformed(source,by:transform,tolerance:tolerance)
            #expect(result.root == source.root)
            #expect(result.model.bodies == source.model.bodies)
            #expect(result.model.shells == source.model.shells)
            #expect(Set(result.model.faces.keys) == Set(source.model.faces.keys))
            #expect(Set(result.model.edges.keys) == Set(source.model.edges.keys))
            #expect(abs(try result.model.volume(tolerance:tolerance) - (1.0/3.0-1.0/3072.0)) < 1e-9)
            for (id,vertex) in source.model.vertices {
                #expect(result.model.vertices[id]?.point == transform.applying(to:vertex.point))
            }
        }
        #expect(source.model == fixture.model)
    }

    private func expect(_ expected: SolidComplexError, _ complex: SolidComplexTopology,
                        in model: BRepModel, options: SolidComplexValidationOptions = .init()) throws {
        do {
            try DefaultSolidComplexValidator().validate(complex,in:model,tolerance:tolerance,options:options)
            Issue.record("An invalid complex must return its explicit failure.")
        } catch let error as SolidComplexError { #expect(error == expected) }
    }

    private func adjacentCells(withVoid: Bool = false) throws -> Fixture {
        var model = BRepModel()
        let base = [Point3D.origin,Point3D(x:1,y:0,z:0),Point3D(x:0,y:1,z:0)]
        let upper = try appendTetrahedron(to:&model,points:base+[Point3D(x:0,y:0,z:1)],lower:false)
        let lower = try appendTetrahedron(to:&model,points:base+[Point3D(x:0,y:0,z:-1)],lower:true)
        var voidID: ShellID?
        if withVoid {
            let cavity = try appendTetrahedron(to:&model,points:[Point3D(x:0.125,y:0.125,z:0.125),
                Point3D(x:0.25,y:0.125,z:0.125),Point3D(x:0.125,y:0.25,z:0.125),
                Point3D(x:0.125,y:0.125,z:0.25)],lower:false)
            model.bodies[cavity.bodyID] = nil
            var shell = try #require(model.shells[cavity.shellID])
            shell.orientation = .reversed
            model.shells[shell.id] = shell
            var body = try #require(model.bodies[upper.bodyID])
            body.topology = .solid(components:[SolidShellComponent(outerShellID:upper.shellID,voidShellIDs:[shell.id])])
            model.bodies[body.id] = body
            voidID = shell.id
        }
        return Fixture(model:model,upper:upper,lower:lower,voidShellID:voidID)
    }

    private func appendTetrahedron(to model: inout BRepModel, points: [Point3D], lower: Bool) throws -> Cell {
        let vertices = points.map { Vertex(point:$0) }
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        var edgeIDs: [String:EdgeID] = [:]
        var faceIDs: [FaceID] = []
        var loopIDs: [LoopID] = []
        let boundaries = lower ? [[0,1,2],[0,3,1],[0,2,3],[1,3,2]] : [[0,2,1],[0,1,3],[0,3,2],[1,2,3]]
        for (faceIndex,indices) in boundaries.enumerated() {
            let a = points[indices[0]], b = points[indices[1]], c = points[indices[2]]
            let normal: Vector3D
            if faceIndex == 0 { normal = .unitZ }
            else { normal = try (b-a).cross(c-a).normalized(tolerance:tolerance.distance) }
            // Both cell-local interface faces use the same complete support chart.
            let surface = Surface3D.plane(Plane3D(origin:a,normal:normal))
            let surfaceID = SurfaceID()
            model.geometry.surfaces[surfaceID] = surface
            var uses: [Coedge] = []
            for index in indices.indices {
                let first = indices[index], last = indices[(index+1)%indices.count]
                let lo = min(first,last), hi = max(first,last), key = "\(lo):\(hi)"
                let edgeID: EdgeID
                if let existing = edgeIDs[key] { edgeID = existing }
                else {
                    let curveID = CurveID()
                    let direction = try (points[hi]-points[lo]).normalized(tolerance:tolerance.distance)
                    model.geometry.curves[curveID] = .line(Line3D(origin:points[lo],direction:direction))
                    let edge = Edge(curveID:curveID,startVertexID:vertices[lo].id,endVertexID:vertices[hi].id,
                                    trim:CurveTrim(startParameter:0,endParameter:(points[hi]-points[lo]).length))
                    edgeID = edge.id
                    model.edges[edge.id] = edge
                    edgeIDs[key] = edge.id
                }
                let start = try surface.parameterProjection(of:points[first],tolerance:tolerance)
                let end = try surface.parameterProjection(of:points[last],tolerance:tolerance)
                uses.append(Coedge(edgeID:edgeID,orientation:first == lo ? .forward : .reversed,
                    surfaceParameterCurve:.polyline([SurfaceParameter(u:start.u,v:start.v),SurfaceParameter(u:end.u,v:end.v)])))
            }
            // Move one loop start to exercise complete cyclic opposite matching.
            if lower && faceIndex == 0 { uses = Array(uses.dropFirst()) + [uses[0]] }
            let loop = Loop(coedges:uses)
            let face = Face(surfaceID:surfaceID,loops:[loop.id],
                            orientation:faceIndex == 0 && !lower ? .reversed : .forward)
            model.loops[loop.id] = loop
            model.faces[face.id] = face
            faceIDs.append(face.id); loopIDs.append(loop.id)
        }
        let shell = Shell(faceIDs:faceIDs)
        let body = Body(solidComponents:[SolidShellComponent(outerShellID:shell.id)],material:MaterialID())
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return Cell(bodyID:body.id,shellID:shell.id,interfaceFaceID:faceIDs[0],interfaceLoopID:loopIDs[0])
    }
}
