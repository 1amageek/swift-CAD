import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct ExactSTEPReader {
    let entities: [Int: String]
    let lengthUnit: LengthUnit
    let processingBudget: ExchangeProcessingBudget
    let tolerance: ModelingTolerance

    func read() throws -> BRepModel {
        try processingBudget.check(format: .step)
        var builder = Builder(
            entities: entities,
            lengthUnit: lengthUnit,
            processingBudget: processingBudget,
                tolerance: tolerance
        )
        let model = try builder.build()
        try processingBudget.check(format: .step)
        try model.validate(level: .exact, tolerance: tolerance)
        return model
    }
}

private extension ExactSTEPReader {
    struct Builder {
        let entities: [Int: String]
        let lengthUnit: LengthUnit
        let processingBudget: ExchangeProcessingBudget
        let tolerance: ModelingTolerance

        var geometry = GeometryStore()
        var bodies: [BodyID: Body] = [:]
        var shells: [ShellID: Shell] = [:]
        var faces: [FaceID: Face] = [:]
        var loops: [LoopID: Loop] = [:]
        var edges: [EdgeID: Edge] = [:]
        var vertices: [VertexID: Vertex] = [:]

        var pointCache: [Int: Point3D] = [:]
        var directionCache: [Int: Vector3D] = [:]
        var lineCache: [Int: CurveID] = [:]
        var curveTrimCache: [Int: CurveTrim] = [:]
        var planeCache: [Int: SurfaceID] = [:]
        var vertexCache: [Int: VertexID] = [:]
        var edgeCache: [Int: EdgeID] = [:]
        var edgeGeometryEntities: [EdgeID: Int] = [:]
        var edgeCurveSameSense: [EdgeID: Bool] = [:]
        var intersectionPcurves: [CurveID: [Surface3D: SurfaceParameterCurve]] = [:]
        var surfaceLiftTransferCurves: Set<CurveID> = []
        var shellOwners: Set<Int> = []
        var orientedShellOwners: Set<Int> = []
        var faceOwners: Set<Int> = []
        var loopOwners: Set<Int> = []

        mutating func build() throws -> BRepModel {
            var representationItemCount = 0
            for entityID in entities.keys.sorted() {
                try processingBudget.check(format: .step)
                guard let entity = entities[entityID] else {
                    continue
                }
                if entity.trimmingCharacters(in: .whitespacesAndNewlines).first == "(" {
                    continue
                }
                switch try entityName(entity) {
                case "MANIFOLD_SOLID_BREP":
                    let arguments = try arguments(of: entity, named: "MANIFOLD_SOLID_BREP")
                    guard arguments.count == 2 else {
                        throw invalid("STEP MANIFOLD_SOLID_BREP #\(entityID) is malformed.")
                    }
                    let shellEntityID = try reference(arguments[1], label: "closed shell")
                    let shellID = try buildShell(shellEntityID, expectedName: "CLOSED_SHELL")
                    let bodyID: BodyID = taggedID(namespace: 0x535445505F424F44, entityID: entityID)
                    bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: .solid)
                    representationItemCount += 1
                case "BREP_WITH_VOIDS":
                    let arguments = try arguments(of: entity, named: "BREP_WITH_VOIDS")
                    guard arguments.count == 3 else {
                        throw invalid("STEP BREP_WITH_VOIDS #\(entityID) is malformed.")
                    }
                    let outerEntityID = try reference(arguments[1], label: "outer closed shell")
                    let voidEntityIDs = try referenceList(arguments[2], label: "oriented void shell list")
                    guard !voidEntityIDs.isEmpty else {
                        throw invalid("STEP BREP_WITH_VOIDS #\(entityID) has no void shells.")
                    }
                    var shellIDs = [try buildShell(outerEntityID, expectedName: "CLOSED_SHELL")]
                    for voidEntityID in voidEntityIDs {
                        try processingBudget.check(format: .step)
                        shellIDs.append(try buildVoidShell(voidEntityID))
                    }
                    let bodyID: BodyID = taggedID(namespace: 0x535445505F424F44, entityID: entityID)
                    bodies[bodyID] = Body(id: bodyID, shellIDs: shellIDs, kind: .solid)
                    representationItemCount += 1
                case "SHELL_BASED_SURFACE_MODEL":
                    let arguments = try arguments(of: entity, named: "SHELL_BASED_SURFACE_MODEL")
                    guard arguments.count == 2 else {
                        throw invalid("STEP SHELL_BASED_SURFACE_MODEL #\(entityID) is malformed.")
                    }
                    let shellEntityIDs = try referenceList(arguments[1], label: "open shell list")
                    guard !shellEntityIDs.isEmpty else {
                        throw invalid("STEP sheet body #\(entityID) has no shells.")
                    }
                    var shellIDs: [ShellID] = []
                    for shellEntityID in shellEntityIDs {
                        try processingBudget.check(format: .step)
                        shellIDs.append(try buildShell(shellEntityID, expectedName: "OPEN_SHELL"))
                    }
                    let bodyID: BodyID = taggedID(namespace: 0x535445505F424F44, entityID: entityID)
                    bodies[bodyID] = Body(id: bodyID, shellIDs: shellIDs, kind: .sheet)
                    representationItemCount += 1
                default:
                    continue
                }
            }
            guard representationItemCount > 0 else {
                throw unsupported("STEP input does not contain an exact manifold solid or sheet model.")
            }
            return BRepModel(
                geometry: geometry,
                bodies: bodies,
                shells: shells,
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            )
        }

        mutating func buildShell(_ entityID: Int, expectedName: String) throws -> ShellID {
            guard shellOwners.insert(entityID).inserted else {
                throw unsupported("STEP shell #\(entityID) is shared by multiple bodies.")
            }
            let entity = try requiredEntity(entityID, label: "shell")
            let arguments = try arguments(of: entity, named: expectedName)
            guard arguments.count == 2 else {
                throw invalid("STEP shell #\(entityID) is malformed.")
            }
            let faceEntityIDs = try referenceList(arguments[1], label: "shell face list")
            guard !faceEntityIDs.isEmpty else {
                throw invalid("STEP shell #\(entityID) has no faces.")
            }
            let faceIDs = try faceEntityIDs.map { try buildFace($0) }
            let shellID: ShellID = taggedID(namespace: 0x535445505F53484C, entityID: entityID)
            shells[shellID] = Shell(id: shellID, faceIDs: faceIDs, orientation: .forward)
            return shellID
        }

        mutating func buildVoidShell(_ entityID: Int) throws -> ShellID {
            guard orientedShellOwners.insert(entityID).inserted else {
                throw unsupported("STEP oriented void shell #\(entityID) is referenced more than once.")
            }
            let entity = try requiredEntity(entityID, label: "oriented void shell")
            let arguments = try arguments(of: entity, named: "ORIENTED_CLOSED_SHELL")
            guard arguments.count == 4,
                  arguments[1].trimmingCharacters(in: .whitespacesAndNewlines) == "*",
                  try boolean(arguments[3]) == false else {
                throw unsupported(
                    "STEP oriented void shell #\(entityID) must derive its faces and use orientation FALSE."
                )
            }
            let baseEntityID = try reference(arguments[2], label: "void closed shell")
            let shellID = try buildShell(baseEntityID, expectedName: "CLOSED_SHELL")
            guard var shell = shells[shellID] else {
                throw missing("STEP void closed shell #\(baseEntityID)")
            }
            shell.orientation = .reversed
            shells[shellID] = shell
            return shellID
        }

        mutating func buildFace(_ entityID: Int) throws -> FaceID {
            guard faceOwners.insert(entityID).inserted else {
                throw unsupported("STEP face #\(entityID) is shared by multiple shells.")
            }
            let entity = try requiredEntity(entityID, label: "face")
            let arguments = try arguments(of: entity, named: "ADVANCED_FACE")
            guard arguments.count == 4 else {
                throw invalid("STEP ADVANCED_FACE #\(entityID) is malformed.")
            }
            let surfaceEntityID = try reference(arguments[2], label: "face surface")
            let surfaceID = try buildSurface(surfaceEntityID)
            guard let surface = geometry.surfaces[surfaceID] else {
                throw missing("STEP face surface #\(surfaceEntityID)")
            }
            let boundEntityIDs = try referenceList(arguments[1], label: "face bound list")
            guard !boundEntityIDs.isEmpty else {
                throw invalid("STEP face #\(entityID) has no bounds.")
            }
            var loopIDs: [LoopID] = []
            for boundEntityID in boundEntityIDs {
                try processingBudget.check(format: .step)
                loopIDs.append(try buildLoop(
                    boundEntityID,
                    surfaceEntityID: surfaceEntityID,
                    surface: surface
                ))
            }
            let faceID: FaceID = taggedID(namespace: 0x535445505F464143, entityID: entityID)
            faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: loopIDs,
                orientation: try orientation(arguments[3])
            )
            return faceID
        }

        mutating func buildLoop(
            _ boundEntityID: Int,
            surfaceEntityID: Int,
            surface: Surface3D
        ) throws -> LoopID {
            let bound = try requiredEntity(boundEntityID, label: "face bound")
            let boundName = try entityName(bound)
            guard boundName == "FACE_OUTER_BOUND" || boundName == "FACE_BOUND" else {
                throw unsupported("STEP face bound #\(boundEntityID) is not an exact edge bound.")
            }
            let boundArguments = try arguments(of: bound, named: boundName)
            guard boundArguments.count == 3 else {
                throw invalid("STEP face bound #\(boundEntityID) is malformed.")
            }
            let loopEntityID = try reference(boundArguments[1], label: "edge loop")
            guard loopOwners.insert(loopEntityID).inserted else {
                throw unsupported("STEP edge loop #\(loopEntityID) is shared by multiple faces.")
            }
            let loopEntity = try requiredEntity(loopEntityID, label: "edge loop")
            let loopArguments = try arguments(of: loopEntity, named: "EDGE_LOOP")
            guard loopArguments.count == 2 else {
                throw invalid("STEP EDGE_LOOP #\(loopEntityID) is malformed.")
            }
            var orientedEntityIDs = try referenceList(loopArguments[1], label: "oriented edge list")
            let boundOrientation = try boolean(boundArguments[2])
            if !boundOrientation {
                orientedEntityIDs.reverse()
            }
            var coedges: [Coedge] = []
            for orientedEntityID in orientedEntityIDs {
                try processingBudget.check(format: .step)
                let orientedEntity = try requiredEntity(orientedEntityID, label: "oriented edge")
                let orientedArguments = try arguments(of: orientedEntity, named: "ORIENTED_EDGE")
                guard orientedArguments.count == 5 else {
                    throw invalid("STEP ORIENTED_EDGE #\(orientedEntityID) is malformed.")
                }
                let edgeEntityID = try reference(orientedArguments[3], label: "edge curve")
                let edgeID = try buildEdge(edgeEntityID)
                var edgeOrientation = try orientation(orientedArguments[4])
                if !boundOrientation {
                    edgeOrientation = edgeOrientation == .forward ? .reversed : .forward
                }
                let parameterCurve = try parameterCurve(
                    for: edgeID,
                    orientation: edgeOrientation,
                    surfaceEntityID: surfaceEntityID,
                    surface: surface
                )
                try reconstructSurfaceLiftIfNeeded(
                    edgeID: edgeID,
                    orientation: edgeOrientation,
                    surface: surface,
                    orientedParameterCurve: parameterCurve
                )
                coedges.append(Coedge(
                    edgeID: edgeID,
                    orientation: edgeOrientation,
                    surfaceParameterCurve: parameterCurve
                ))
            }
            let loopID: LoopID = taggedID(namespace: 0x535445505F4C4F50, entityID: loopEntityID)
            loops[loopID] = Loop(
                id: loopID,
                role: boundName == "FACE_OUTER_BOUND" ? .outer : .inner,
                coedges: coedges
            )
            return loopID
        }

        mutating func buildEdge(_ entityID: Int) throws -> EdgeID {
            if let cached = edgeCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "edge curve")
            let arguments = try arguments(of: entity, named: "EDGE_CURVE")
            guard arguments.count == 5 else {
                throw invalid("STEP EDGE_CURVE #\(entityID) is malformed.")
            }
            let startVertexID = try buildVertex(reference(arguments[1], label: "edge start vertex"))
            let endVertexID = try buildVertex(reference(arguments[2], label: "edge end vertex"))
            let geometryEntityID = try reference(arguments[3], label: "edge geometry")
            let curveID = try buildCurve(geometryEntityID)
            let sameSense = try boolean(arguments[4])
            let edgeID: EdgeID = taggedID(namespace: 0x535445505F454447, entityID: entityID)
            edges[edgeID] = Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                trim: curveTrimCache[geometryEntityID]
            )
            if let reconstructed = try associatedPlaneTorusCurve(
                surfaceCurveEntityID: geometryEntityID,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                geometry.curves[curveID] = .analytic(.planeTorus(reconstructed))
            } else if let reconstructed = try associatedImplicitIntersection(
                surfaceCurveEntityID: geometryEntityID,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                geometry.curves[curveID] = reconstructed.curve
                intersectionPcurves[curveID] = [
                    reconstructed.firstSurface: reconstructed.firstSurfaceParameterCurve,
                    reconstructed.secondSurface: reconstructed.secondSurfaceParameterCurve,
                ]
            }
            guard let curve = geometry.curves[curveID],
                  let startPoint = vertices[startVertexID]?.point,
                  let endPoint = vertices[endVertexID]?.point else {
                throw missing("STEP edge curve geometry")
            }
            switch curve {
            case let .line(lineGeometry):
                let signedSpan = (endPoint - startPoint).dot(lineGeometry.direction)
                guard abs(signedSpan) > tolerance.distance,
                      (signedSpan > 0.0) == sameSense else {
                    throw invalid("STEP EDGE_CURVE #\(entityID) has an inconsistent same_sense value.")
                }
            case .bSpline:
                guard let geometryTrim = curveTrimCache[geometryEntityID] else {
                    throw invalid("STEP B-spline EDGE_CURVE has no explicit finite trim interval.")
                }
                let edgeTrim = sameSense
                    ? geometryTrim
                    : CurveTrim(
                        startParameter: geometryTrim.endParameter,
                        endParameter: geometryTrim.startParameter
                    )
                let expectedStart = try curve.point(
                    at: edgeTrim.startParameter,
                    tolerance: tolerance
                )
                let expectedEnd = try curve.point(
                    at: edgeTrim.endParameter,
                    tolerance: tolerance
                )
                guard startPoint.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ), endPoint.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ) else {
                    throw invalid(
                        "STEP B-spline EDGE_CURVE #\(entityID) endpoints disagree with same_sense."
                    )
                }
                edges[edgeID]?.trim = edgeTrim
            case .circle:
                let trim = try periodicEdgeTrim(
                    curve: curve,
                    startPoint: startPoint,
                    endPoint: endPoint,
                    followsCurve: sameSense,
                    label: "STEP circle EDGE_CURVE #\(entityID)"
                )
                edges[edgeID]?.trim = trim
            case let .analytic(analytic):
                switch analytic {
                case let .line(_, direction):
                    let signedSpan = (endPoint - startPoint).dot(direction)
                    guard abs(signedSpan) > tolerance.distance,
                          (signedSpan > 0.0) == sameSense else {
                        throw invalid("STEP analytic line EDGE_CURVE #\(entityID) has inconsistent orientation.")
                    }
                case .circle, .ellipse:
                    let trim = try periodicEdgeTrim(
                        curve: curve,
                        startPoint: startPoint,
                        endPoint: endPoint,
                        followsCurve: sameSense,
                        label: "STEP analytic conic EDGE_CURVE #\(entityID)"
                    )
                    edges[edgeID]?.trim = trim
                case .hyperbola, .parabola:
                    let startParameter = try curve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    ).parameter
                    let endParameter = try curve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    ).parameter
                    let parameterTolerance: Double
                    switch analytic {
                    case .hyperbola:
                        parameterTolerance = tolerance.relative
                    case .parabola:
                        parameterTolerance = tolerance.distance
                    case .line, .circle, .arc, .ellipse, .planeTorus:
                        throw invalid("STEP open-conic dispatch is inconsistent.")
                    }
                    guard abs(endParameter - startParameter) > parameterTolerance,
                          (endParameter > startParameter) == sameSense else {
                        throw invalid("STEP analytic open conic EDGE_CURVE #\(entityID) has inconsistent orientation.")
                    }
                    edges[edgeID]?.trim = CurveTrim(
                        startParameter: startParameter,
                        endParameter: endParameter
                    )
                case .arc:
                    guard sameSense, curveTrimCache[geometryEntityID] != nil else {
                        throw invalid("STEP analytic arc EDGE_CURVE #\(entityID) has inconsistent trim semantics.")
                    }
                case .planeTorus:
                    let trim = try periodicEdgeTrim(
                        curve: curve,
                        startPoint: startPoint,
                        endPoint: endPoint,
                        followsCurve: sameSense,
                        label: "STEP plane-torus EDGE_CURVE #\(entityID)"
                    )
                    edges[edgeID]?.trim = trim
                }
            case .implicit:
                guard let declaredTrim = curveTrimCache[geometryEntityID] else {
                    throw invalid("STEP implicit intersection edge has no derived transfer interval.")
                }
                let expectedStart = try curve.point(
                    at: declaredTrim.startParameter,
                    tolerance: tolerance
                )
                let expectedEnd = try curve.point(
                    at: declaredTrim.endParameter,
                    tolerance: tolerance
                )
                if startPoint.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ), endPoint.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ) {
                    edges[edgeID]?.trim = declaredTrim
                    guard sameSense else {
                        throw invalid("STEP implicit intersection EDGE_CURVE has inconsistent same_sense.")
                    }
                } else if startPoint.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ), endPoint.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ) {
                    edges[edgeID]?.trim = CurveTrim(
                        startParameter: declaredTrim.endParameter,
                        endParameter: declaredTrim.startParameter
                    )
                    guard sameSense == false else {
                        throw invalid("STEP reversed implicit intersection EDGE_CURVE has inconsistent same_sense.")
                    }
                } else {
                    throw invalid(
                        "STEP implicit intersection edge vertices disagree with its derived transfer interval."
                    )
                }
            case .surfaceLift:
                throw invalid("STEP curve decoding produced a surface-lift runtime curve without a source certificate.")
            }
            edgeGeometryEntities[edgeID] = geometryEntityID
            edgeCurveSameSense[edgeID] = sameSense
            edgeCache[entityID] = edgeID
            return edgeID
        }

        mutating func associatedPlaneTorusCurve(
            surfaceCurveEntityID: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> CertifiedPlaneTorusIntersectionCurve? {
            guard let startPoint, let endPoint else { return nil }
            let entity = try requiredEntity(surfaceCurveEntityID, label: "surface curve")
            guard try entityName(entity) == "SURFACE_CURVE" else { return nil }
            let arguments = try arguments(of: entity, named: "SURFACE_CURVE")
            guard arguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(surfaceCurveEntityID) is malformed.")
            }
            let associated = try referenceList(
                arguments[2],
                label: "surface curve associated geometry"
            )
            var surfaces: [Surface3D] = []
            for associatedEntityID in associated {
                let associatedEntity = try requiredEntity(
                    associatedEntityID,
                    label: "surface curve associated geometry"
                )
                if try entityName(associatedEntity) == "PCURVE" { continue }
                let surfaceID = try buildSurface(associatedEntityID)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("STEP associated intersection surface")
                }
                surfaces.append(surface)
            }
            guard surfaces.count == 2 else { return nil }
            let plane = surfaces.first(where: { surface in
                switch surface {
                case .plane, .analytic(.plane): return true
                case .cylinder, .analytic, .bSpline: return false
                }
            })
            let torus = surfaces.first(where: { surface in
                if case .analytic(.torus) = surface { return true }
                return false
            })
            guard let plane, let torus else { return nil }
            let candidates = try CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: torus,
                options: SurfaceSurfaceIntersectionOptions(),
                tolerance: tolerance
            )
            var matches: [CertifiedPlaneTorusIntersectionCurve] = []
            for candidate in candidates {
                let exactCurve = Curve3D.analytic(.planeTorus(candidate))
                do {
                    _ = try exactCurve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try exactCurve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "STEP plane-torus surface association matches multiple exact intersection components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "STEP plane-torus surface association does not match its edge endpoints."
                )
            }
            return match
        }

        mutating func associatedImplicitIntersection(
            surfaceCurveEntityID: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> (
            curve: Curve3D,
            firstSurface: Surface3D,
            secondSurface: Surface3D,
            firstSurfaceParameterCurve: SurfaceParameterCurve,
            secondSurfaceParameterCurve: SurfaceParameterCurve
        )? {
            guard let startPoint, let endPoint else { return nil }
            let entity = try requiredEntity(surfaceCurveEntityID, label: "surface curve")
            guard try entityName(entity) == "SURFACE_CURVE" else { return nil }
            let arguments = try arguments(of: entity, named: "SURFACE_CURVE")
            guard arguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(surfaceCurveEntityID) is malformed.")
            }
            let associated = try referenceList(
                arguments[2],
                label: "surface curve associated geometry"
            )
            var surfaces: [Surface3D] = []
            for associatedEntityID in associated {
                let associatedEntity = try requiredEntity(
                    associatedEntityID,
                    label: "surface curve associated geometry"
                )
                if try entityName(associatedEntity) == "PCURVE" { continue }
                let surfaceID = try buildSurface(associatedEntityID)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("STEP associated implicit-intersection surface")
                }
                surfaces.append(surface)
            }
            guard surfaces.count == 2,
                  surfaces.contains(where: { surface in
                      if case .bSpline = surface { return true }
                      return false
                  }) else {
                return nil
            }
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: surfaces[0],
                second: surfaces[1],
                tolerance: tolerance
            )
            var matches: [SurfaceSurfaceIntersectionCurve] = []
            for intersection in intersections {
                guard case let .curve(candidate) = intersection else { continue }
                switch candidate.truth {
                case .implicit, .analyticBSpline:
                    break
                case .parametric, .analyticAnalytic, .quadraticTangency:
                    continue
                }
                do {
                    _ = try candidate.curve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try candidate.curve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "STEP implicit surface association matches multiple exact intersection components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "STEP implicit surface association does not match its edge endpoints."
                )
            }
            return (
                match.curve,
                surfaces[0],
                surfaces[1],
                match.firstSurfaceParameterCurve,
                match.secondSurfaceParameterCurve
            )
        }

        func periodicEdgeTrim(
            curve: Curve3D,
            startPoint: Point3D,
            endPoint: Point3D,
            followsCurve: Bool,
            label: String
        ) throws -> CurveTrim {
            let period = 2.0 * Double.pi
            let startParameter = try curve.parameterProjection(
                of: startPoint,
                tolerance: tolerance
            ).parameter
            var endParameter = try curve.parameterProjection(
                of: endPoint,
                tolerance: tolerance
            ).parameter
            if followsCurve {
                while endParameter <= startParameter + tolerance.angle {
                    endParameter += period
                }
            } else {
                while endParameter >= startParameter - tolerance.angle {
                    endParameter -= period
                }
            }
            let span = abs(endParameter - startParameter)
            guard span > tolerance.angle,
                  span < period - tolerance.angle else {
                throw unsupported("\(label) has a degenerate or full-period trim interval.")
            }
            return CurveTrim(
                startParameter: startParameter,
                endParameter: endParameter
            )
        }

        mutating func buildVertex(_ entityID: Int) throws -> VertexID {
            if let cached = vertexCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "vertex point")
            let arguments = try arguments(of: entity, named: "VERTEX_POINT")
            guard arguments.count == 2 else {
                throw invalid("STEP VERTEX_POINT #\(entityID) is malformed.")
            }
            let point = try buildPoint(reference(arguments[1], label: "vertex geometry"))
            let vertexID: VertexID = taggedID(namespace: 0x535445505F565458, entityID: entityID)
            vertices[vertexID] = Vertex(id: vertexID, point: point)
            vertexCache[entityID] = vertexID
            return vertexID
        }

        mutating func buildCurve(_ entityID: Int) throws -> CurveID {
            if let cached = lineCache[entityID] {
                return cached
            }
            let edgeGeometry = try requiredEntity(entityID, label: "edge geometry")
            let geometryName = try entityName(edgeGeometry)
            let curveEntityID: Int
            if geometryName == "SURFACE_CURVE" {
                let surfaceCurveArguments = try arguments(of: edgeGeometry, named: "SURFACE_CURVE")
                guard surfaceCurveArguments.count == 4 else {
                    throw invalid("STEP SURFACE_CURVE #\(entityID) is malformed.")
                }
                curveEntityID = try reference(surfaceCurveArguments[1], label: "surface curve 3D curve")
                _ = try referenceList(surfaceCurveArguments[2], label: "surface curve associated geometry")
                let masterRepresentation = surfaceCurveArguments[3]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard masterRepresentation == ".PCURVE_S1."
                        || masterRepresentation == ".CURVE_3D." else {
                    throw unsupported("STEP SURFACE_CURVE #\(entityID) has an unsupported master representation.")
                }
            } else if geometryName == "LINE"
                || geometryName == "CIRCLE"
                || geometryName == "ELLIPSE"
                || geometryName == "HYPERBOLA"
                || geometryName == "PARABOLA"
                || geometryName == "TRIMMED_CURVE"
                || geometryName.isEmpty {
                curveEntityID = entityID
            } else {
                throw unsupported("STEP edge geometry #\(entityID) is not a supported exact curve.")
            }
            if let cached = lineCache[curveEntityID] {
                lineCache[entityID] = cached
                if let trim = curveTrimCache[curveEntityID] {
                    curveTrimCache[entityID] = trim
                }
                return cached
            }
            let entity = try requiredEntity(curveEntityID, label: "curve")
            let curveID: CurveID = taggedID(namespace: 0x535445505F435256, entityID: curveEntityID)
            let concreteName = try entityName(entity)
            if concreteName == "LINE" {
                let lineArguments = try arguments(of: entity, named: "LINE")
                guard lineArguments.count == 3 else {
                    throw unsupported("STEP edge geometry #\(curveEntityID) is not a supported LINE.")
                }
                let origin = try buildPoint(reference(lineArguments[1], label: "line origin"))
                let vectorEntityID = try reference(lineArguments[2], label: "line vector")
                let vectorEntity = try requiredEntity(vectorEntityID, label: "vector")
                let vectorArguments = try arguments(of: vectorEntity, named: "VECTOR")
                guard vectorArguments.count == 3 else {
                    throw invalid("STEP VECTOR #\(vectorEntityID) is malformed.")
                }
                let direction = try buildDirection(reference(vectorArguments[1], label: "vector direction"))
                let magnitude = try number(vectorArguments[2], label: "vector magnitude")
                guard magnitude > 0.0 else {
                    throw invalid("STEP VECTOR #\(vectorEntityID) has a non-positive magnitude.")
                }
                let line = Line3D(origin: origin, direction: direction)
                try line.validate(tolerance: tolerance)
                geometry.curves[curveID] = .line(line)
            } else if concreteName == "CIRCLE" {
                let parsed = try parseCircle(entity, entityID: curveEntityID)
                let expectedReference = try parsed.isAnalytic
                    ? ExactAnalyticFrame.analyticBasis(for: parsed.normal, tolerance: tolerance).u
                    : ExactAnalyticFrame.directBasis(for: parsed.normal, tolerance: tolerance).u
                let circleArguments = try arguments(of: entity, named: "CIRCLE")
                let placement = try buildAxisPlacement(
                    reference(circleArguments[1], label: "circle placement")
                )
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP circle #\(curveEntityID) uses an unsupported parameter frame.")
                }
                if parsed.isAnalytic {
                    geometry.curves[curveID] = .analytic(.circle(
                        center: parsed.center,
                        normal: parsed.normal,
                        radius: parsed.radius
                    ))
                } else {
                    geometry.curves[curveID] = .circle(Circle3D(
                        center: parsed.center,
                        normal: parsed.normal,
                        radius: parsed.radius
                    ))
                }
            } else if concreteName == "ELLIPSE" {
                let ellipseArguments = try arguments(of: entity, named: "ELLIPSE")
                guard ellipseArguments.count == 4, isAnalyticMarker(ellipseArguments[0]) else {
                    throw unsupported("STEP ellipse #\(curveEntityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(ellipseArguments[1], label: "ellipse placement")
                )
                let ellipse = AnalyticCurve3D.ellipse(
                    center: placement.origin,
                    normal: placement.axis,
                    majorAxis: placement.reference,
                    majorRadius: lengthUnit.toInternal(
                        try number(ellipseArguments[2], label: "ellipse major radius")
                    ),
                    minorRadius: lengthUnit.toInternal(
                        try number(ellipseArguments[3], label: "ellipse minor radius")
                    )
                )
                try ellipse.validate(tolerance: tolerance)
                geometry.curves[curveID] = .analytic(ellipse)
            } else if concreteName == "HYPERBOLA" {
                let hyperbolaArguments = try arguments(of: entity, named: "HYPERBOLA")
                guard hyperbolaArguments.count == 4,
                      isAnalyticMarker(hyperbolaArguments[0]) else {
                    throw unsupported("STEP hyperbola #\(curveEntityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(hyperbolaArguments[1], label: "hyperbola placement")
                )
                let hyperbola = Hyperbola3D(
                    center: placement.origin,
                    normal: placement.axis,
                    transverseAxis: placement.reference,
                    transverseRadius: lengthUnit.toInternal(
                        try number(hyperbolaArguments[2], label: "hyperbola transverse radius")
                    ),
                    conjugateRadius: lengthUnit.toInternal(
                        try number(hyperbolaArguments[3], label: "hyperbola conjugate radius")
                    )
                )
                try hyperbola.validate(tolerance: tolerance)
                geometry.curves[curveID] = .analytic(.hyperbola(hyperbola))
            } else if concreteName == "PARABOLA" {
                let parabolaArguments = try arguments(of: entity, named: "PARABOLA")
                guard parabolaArguments.count == 3,
                      isAnalyticMarker(parabolaArguments[0]) else {
                    throw unsupported("STEP parabola #\(curveEntityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(parabolaArguments[1], label: "parabola placement")
                )
                let parabola = Parabola3D(
                    vertex: placement.origin,
                    normal: placement.axis,
                    axis: placement.reference,
                    focalLength: lengthUnit.toInternal(
                        try number(parabolaArguments[2], label: "parabola focal distance")
                    )
                )
                try parabola.validate(tolerance: tolerance)
                geometry.curves[curveID] = .analytic(.parabola(parabola))
            } else if concreteName == "TRIMMED_CURVE" {
                let trimmedArguments = try arguments(of: entity, named: "TRIMMED_CURVE")
                guard trimmedArguments.count == 6,
                      trimmedArguments[5].uppercased() == ".PARAMETER." else {
                    throw unsupported("STEP trimmed curve #\(curveEntityID) is outside the supported parameter-trim contract.")
                }
                let marker = trimmedArguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let basisEntityID = try reference(trimmedArguments[1], label: "trimmed curve basis")
                let startParameter = try trimmingParameter(trimmedArguments[2])
                let endParameter = try trimmingParameter(trimmedArguments[3])
                let senseAgreement = try boolean(trimmedArguments[4])
                guard abs(endParameter - startParameter) > tolerance.distance,
                      senseAgreement == (endParameter > startParameter) else {
                    throw invalid("STEP trimmed curve #\(curveEntityID) has inconsistent parameter orientation.")
                }
                let trim = CurveTrim(startParameter: startParameter, endParameter: endParameter)
                switch marker {
                case "'SWIFTCAD_ARC'":
                    let basisEntity = try requiredEntity(basisEntityID, label: "trimmed curve basis")
                    let parsed = try parseCircle(basisEntity, entityID: basisEntityID)
                    guard parsed.isAnalytic else {
                        throw unsupported("STEP analytic arc #\(curveEntityID) requires an analytic circle basis.")
                    }
                    let lower = min(startParameter, endParameter)
                    let upper = max(startParameter, endParameter)
                    let arc = AnalyticCurve3D.arc(
                        center: parsed.center,
                        normal: parsed.normal,
                        radius: parsed.radius,
                        startAngle: lower,
                        endAngle: upper
                    )
                    try arc.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .analytic(arc)
                case "'SWIFTCAD_BSPLINE_TRIM'":
                    let basisEntity = try requiredEntity(
                        basisEntityID,
                        label: "B-spline trim basis"
                    )
                    let basisCurve = Curve3D.bSpline(try buildBSplineCurve(
                        basisEntity,
                        entityID: basisEntityID
                    ))
                    guard try basisCurve.parameterDomain.containsSpan(
                            from: startParameter,
                            to: endParameter,
                            tolerance: tolerance
                          ) else {
                        throw unsupported("STEP B-spline trim #\(curveEntityID) requires a bounded rational B-spline basis containing its trim interval.")
                    }
                    geometry.curves[curveID] = basisCurve
                default:
                    throw unsupported("STEP trimmed curve #\(curveEntityID) has an unsupported semantic marker.")
                }
                curveTrimCache[curveEntityID] = trim
                curveTrimCache[entityID] = trim
            } else {
                let bSpline = try buildBSplineCurve(entity, entityID: curveEntityID)
                geometry.curves[curveID] = .bSpline(bSpline)
                let representationArguments = try complexArguments(
                    of: entity,
                    named: "REPRESENTATION_ITEM"
                )
                guard representationArguments.count == 1 else {
                    throw invalid(
                        "STEP B-spline curve #\(curveEntityID) has malformed representation metadata."
                    )
                }
                if representationArguments[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    == "'SWIFTCAD_SURFACE_LIFT'" {
                    surfaceLiftTransferCurves.insert(curveID)
                }
                guard case let .closed(lower, upper) = bSpline.domain else {
                    throw invalid("STEP B-spline curve #\(curveEntityID) has no finite knot domain.")
                }
                let trim = CurveTrim(startParameter: lower, endParameter: upper)
                curveTrimCache[curveEntityID] = trim
                curveTrimCache[entityID] = trim
            }
            lineCache[curveEntityID] = curveID
            lineCache[entityID] = curveID
            return curveID
        }

        mutating func reconstructSurfaceLiftIfNeeded(
            edgeID: EdgeID,
            orientation: Orientation,
            surface: Surface3D,
            orientedParameterCurve: SurfaceParameterCurve
        ) throws {
            guard let edge = edges[edgeID],
                  surfaceLiftTransferCurves.contains(edge.curveID) else {
                return
            }
            guard case let .bSpline(derivedCurve) = geometry.curves[edge.curveID],
                  let sameSense = edgeCurveSameSense[edgeID],
                  case let .closed(lower, upper) = derivedCurve.domain else {
                throw invalid("STEP surface-lift transfer has incomplete derived curve metadata.")
            }
            let edgeParameterCurve = orientation == .forward
                ? orientedParameterCurve
                : try orientedParameterCurve.reversed(tolerance: tolerance)
            let modelParameterCurve = sameSense
                ? edgeParameterCurve
                : try edgeParameterCurve.reversed(tolerance: tolerance)
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: .bSpline(derivedCurve),
                from: lower,
                to: upper,
                surface: surface,
                parameterCurve: modelParameterCurve,
                options: CurveSurfaceCorrespondenceValidationOptions(
                    maximumSubdivisionDepth: 24,
                    maximumCellCount: 65_536
                ),
                tolerance: tolerance
            )
            let lift = SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: modelParameterCurve
            )
            try lift.validate(tolerance: tolerance)
            geometry.curves[edge.curveID] = .surfaceLift(lift)
            edges[edgeID]?.trim = sameSense
                ? CurveTrim(startParameter: 0.0, endParameter: 1.0)
                : CurveTrim(startParameter: 1.0, endParameter: 0.0)
        }

        mutating func parseCircle(
            _ entity: String,
            entityID: Int
        ) throws -> (center: Point3D, normal: Vector3D, radius: Double, isAnalytic: Bool) {
            let circleArguments = try arguments(of: entity, named: "CIRCLE")
            guard circleArguments.count == 3 else {
                throw invalid("STEP CIRCLE #\(entityID) is malformed.")
            }
            let placement = try buildAxisPlacement(
                reference(circleArguments[1], label: "circle placement")
            )
            let radius = lengthUnit.toInternal(try number(circleArguments[2], label: "circle radius"))
            let circle = Circle3D(center: placement.origin, normal: placement.axis, radius: radius)
            try circle.validate(tolerance: tolerance)
            return (
                placement.origin,
                placement.axis,
                radius,
                isAnalyticMarker(circleArguments[0])
                    || circleArguments[0].trimmingCharacters(in: .whitespacesAndNewlines) == "'SWIFTCAD_ARC_BASIS'"
            )
        }

        func trimmingParameter(_ text: String) throws -> Double {
            let values = try splitTopLevel(tupleContent(text, label: "trimmed curve parameter set"))
            guard values.count == 1 else {
                throw unsupported("STEP trimmed curve parameter set must contain exactly one parameter value.")
            }
            let parameterArguments = try arguments(of: values[0], named: "PARAMETER_VALUE")
            guard parameterArguments.count == 1 else {
                throw invalid("STEP PARAMETER_VALUE is malformed.")
            }
            return try number(parameterArguments[0], label: "trimmed curve parameter")
        }

        mutating func buildSurface(_ entityID: Int) throws -> SurfaceID {
            if let cached = planeCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "surface")
            let surfaceName = try entityName(entity)
            if surfaceName.isEmpty {
                let surface = try buildBSplineSurface(entity, entityID: entityID)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .bSpline(surface)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "CYLINDRICAL_SURFACE" {
                let cylinderArguments = try arguments(of: entity, named: "CYLINDRICAL_SURFACE")
                guard cylinderArguments.count == 3 else {
                    throw invalid("STEP CYLINDRICAL_SURFACE #\(entityID) is malformed.")
                }
                let placement = try buildAxisPlacement(
                    reference(cylinderArguments[1], label: "cylinder placement")
                )
                let isAnalytic = isAnalyticMarker(cylinderArguments[0])
                let expectedReference = try isAnalytic
                    ? ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                    : ExactAnalyticFrame.directBasis(for: placement.axis, tolerance: tolerance).u
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP cylinder #\(entityID) uses an unsupported parameter frame.")
                }
                let cylinder = Cylinder3D(
                    origin: placement.origin,
                    axis: placement.axis,
                    radius: lengthUnit.toInternal(try number(cylinderArguments[2], label: "cylinder radius"))
                )
                try cylinder.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = isAnalytic
                    ? .analytic(.cylinder(
                        origin: cylinder.origin,
                        axis: cylinder.axis,
                        radius: cylinder.radius
                    ))
                    : .cylinder(cylinder)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "CONICAL_SURFACE" {
                let coneArguments = try arguments(of: entity, named: "CONICAL_SURFACE")
                guard coneArguments.count == 4, isAnalyticMarker(coneArguments[0]) else {
                    throw unsupported("STEP conical surface #\(entityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(coneArguments[1], label: "cone placement")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                let encodedRadius = try number(coneArguments[2], label: "cone placement radius")
                let halfAngle = try number(coneArguments[3], label: "cone half angle")
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle,
                      abs(lengthUnit.toInternal(encodedRadius)) <= tolerance.distance else {
                    throw unsupported("STEP cone #\(entityID) uses an unsupported placement or non-apex radius.")
                }
                let analytic = AnalyticSurface3D.cone(
                    apex: placement.origin,
                    axis: placement.axis,
                    halfAngle: halfAngle
                )
                try analytic.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .analytic(analytic)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "SPHERICAL_SURFACE" {
                let sphereArguments = try arguments(of: entity, named: "SPHERICAL_SURFACE")
                guard sphereArguments.count == 3, isAnalyticMarker(sphereArguments[0]) else {
                    throw unsupported("STEP spherical surface #\(entityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(sphereArguments[1], label: "sphere placement")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance).u
                guard placement.axis.dot(.unitZ) >= 1.0 - tolerance.angle,
                      placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP sphere #\(entityID) uses an unsupported parameter frame.")
                }
                let analytic = AnalyticSurface3D.sphere(
                    center: placement.origin,
                    radius: lengthUnit.toInternal(try number(sphereArguments[2], label: "sphere radius"))
                )
                try analytic.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .analytic(analytic)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "TOROIDAL_SURFACE" {
                let torusArguments = try arguments(of: entity, named: "TOROIDAL_SURFACE")
                guard torusArguments.count == 4, isAnalyticMarker(torusArguments[0]) else {
                    throw unsupported("STEP toroidal surface #\(entityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(torusArguments[1], label: "torus placement")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP torus #\(entityID) uses an unsupported parameter frame.")
                }
                let analytic = AnalyticSurface3D.torus(
                    center: placement.origin,
                    axis: placement.axis,
                    majorRadius: lengthUnit.toInternal(
                        try number(torusArguments[2], label: "torus major radius")
                    ),
                    minorRadius: lengthUnit.toInternal(
                        try number(torusArguments[3], label: "torus minor radius")
                    )
                )
                try analytic.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .analytic(analytic)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            let planeArguments = try arguments(of: entity, named: "PLANE")
            guard planeArguments.count == 2 else {
                throw unsupported("STEP face geometry #\(entityID) is not a supported PLANE.")
            }
            let placement = try buildAxisPlacement(
                reference(planeArguments[1], label: "plane placement")
            )
            let plane = Plane3D(origin: placement.origin, normal: placement.axis)
            try plane.validate(tolerance: tolerance)
            let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
            if isAnalyticMarker(planeArguments[0]) {
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP analytic plane #\(entityID) uses an unsupported parameter frame.")
                }
                geometry.surfaces[surfaceID] = .analytic(.plane(
                    origin: plane.origin,
                    normal: plane.normal
                ))
            } else {
                geometry.surfaces[surfaceID] = .plane(plane)
            }
            planeCache[entityID] = surfaceID
            return surfaceID
        }

        mutating func buildBSplineCurve(_ entity: String, entityID: Int) throws -> BSplineCurve3D {
            let curveArguments = try complexArguments(of: entity, named: "B_SPLINE_CURVE")
            let knotArguments = try complexArguments(of: entity, named: "B_SPLINE_CURVE_WITH_KNOTS")
            let rationalArguments = try complexArguments(of: entity, named: "RATIONAL_B_SPLINE_CURVE")
            guard curveArguments.count == 5,
                  knotArguments.count == 3,
                  rationalArguments.count == 1,
                  try boolean(curveArguments[3]) == false,
                  try boolean(curveArguments[4]) == false else {
                throw unsupported("STEP B-spline curve #\(entityID) must be open and non-self-intersecting.")
            }
            let degree = try integer(curveArguments[0], label: "B-spline curve degree")
            let pointIDs = try referenceList(curveArguments[1], label: "B-spline curve control points")
            var controlPoints: [Point3D] = []
            for pointID in pointIDs {
                controlPoints.append(try buildPoint(pointID))
            }
            let multiplicities = try integerList(knotArguments[0], label: "B-spline curve knot multiplicities")
            let distinctKnots = try arbitraryNumberList(knotArguments[1], label: "B-spline curve knots")
            let weights = try arbitraryNumberList(rationalArguments[0], label: "B-spline curve weights")
            let curve = BSplineCurve3D(
                degree: degree,
                knots: try expandedKnots(
                    values: distinctKnots,
                    multiplicities: multiplicities,
                    label: "B-spline curve"
                ),
                controlPoints: controlPoints,
                weights: weights
            )
            try curve.validate(tolerance: tolerance)
            return curve
        }

        mutating func buildBSplineSurface(_ entity: String, entityID: Int) throws -> BSplineSurface3D {
            let surfaceArguments = try complexArguments(of: entity, named: "B_SPLINE_SURFACE")
            let knotArguments = try complexArguments(of: entity, named: "B_SPLINE_SURFACE_WITH_KNOTS")
            let rationalArguments = try complexArguments(of: entity, named: "RATIONAL_B_SPLINE_SURFACE")
            guard surfaceArguments.count == 7,
                  knotArguments.count == 5,
                  rationalArguments.count == 1,
                  try boolean(surfaceArguments[4]) == false,
                  try boolean(surfaceArguments[5]) == false,
                  try boolean(surfaceArguments[6]) == false else {
                throw unsupported("STEP B-spline surface #\(entityID) must be open and non-self-intersecting.")
            }
            let uDegree = try integer(surfaceArguments[0], label: "B-spline surface U degree")
            let vDegree = try integer(surfaceArguments[1], label: "B-spline surface V degree")
            let controlRows = try tupleRows(surfaceArguments[2], label: "B-spline surface control net")
            var controlPoints: [[Point3D]] = []
            for row in controlRows {
                let pointIDs = try referenceList(row, label: "B-spline surface control row")
                var points: [Point3D] = []
                for pointID in pointIDs {
                    points.append(try buildPoint(pointID))
                }
                controlPoints.append(points)
            }
            let uMultiplicities = try integerList(knotArguments[0], label: "B-spline surface U multiplicities")
            let vMultiplicities = try integerList(knotArguments[1], label: "B-spline surface V multiplicities")
            let uValues = try arbitraryNumberList(knotArguments[2], label: "B-spline surface U knots")
            let vValues = try arbitraryNumberList(knotArguments[3], label: "B-spline surface V knots")
            let weightRows = try tupleRows(rationalArguments[0], label: "B-spline surface weight net")
            let weights = try weightRows.map {
                try arbitraryNumberList($0, label: "B-spline surface weight row")
            }
            let surface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: try expandedKnots(
                    values: uValues,
                    multiplicities: uMultiplicities,
                    label: "B-spline surface U"
                ),
                vKnots: try expandedKnots(
                    values: vValues,
                    multiplicities: vMultiplicities,
                    label: "B-spline surface V"
                ),
                controlPoints: controlPoints,
                weights: weights
            )
            try surface.validate(tolerance: tolerance)
            return surface
        }

        mutating func buildPoint(_ entityID: Int) throws -> Point3D {
            if let cached = pointCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "cartesian point")
            let arguments = try arguments(of: entity, named: "CARTESIAN_POINT")
            guard arguments.count == 2 else {
                throw invalid("STEP CARTESIAN_POINT #\(entityID) is malformed.")
            }
            let values = try numberList(arguments[1], expectedCount: 3, label: "cartesian coordinates")
            let point = Point3D(
                x: lengthUnit.toInternal(values[0]),
                y: lengthUnit.toInternal(values[1]),
                z: lengthUnit.toInternal(values[2])
            )
            try point.validate()
            pointCache[entityID] = point
            return point
        }

        mutating func buildDirection(_ entityID: Int) throws -> Vector3D {
            if let cached = directionCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "direction")
            let arguments = try arguments(of: entity, named: "DIRECTION")
            guard arguments.count == 2 else {
                throw invalid("STEP DIRECTION #\(entityID) is malformed.")
            }
            let values = try numberList(arguments[1], expectedCount: 3, label: "direction ratios")
            let direction = try Vector3D(x: values[0], y: values[1], z: values[2]).normalized(
                tolerance: tolerance.distance
            )
            directionCache[entityID] = direction
            return direction
        }

        mutating func buildAxisPlacement(
            _ entityID: Int
        ) throws -> (origin: Point3D, axis: Vector3D, reference: Vector3D) {
            let entity = try requiredEntity(entityID, label: "axis placement")
            let placementArguments = try arguments(of: entity, named: "AXIS2_PLACEMENT_3D")
            guard placementArguments.count == 4 else {
                throw invalid("STEP AXIS2_PLACEMENT_3D #\(entityID) is malformed.")
            }
            let origin = try buildPoint(reference(placementArguments[1], label: "placement origin"))
            let axis = try buildDirection(reference(placementArguments[2], label: "placement axis"))
            let referenceDirection = try buildDirection(
                reference(placementArguments[3], label: "placement reference direction")
            )
            guard abs(axis.dot(referenceDirection)) <= tolerance.angle else {
                throw invalid("STEP axis placement #\(entityID) has non-orthogonal axes.")
            }
            return (origin, axis, referenceDirection)
        }

        func parameterCurve(
            for edgeID: EdgeID,
            orientation: Orientation,
            surfaceEntityID: Int,
            surface: Surface3D
        ) throws -> SurfaceParameterCurve {
            guard let edge = edges[edgeID],
                  let startVertex = vertices[edge.startVertexID],
                  let endVertex = vertices[edge.endVertexID],
                  let edgeGeometryEntityID = edgeGeometryEntities[edgeID] else {
                throw missing("STEP exact edge topology")
            }
            let edgeGeometryEntity = try requiredEntity(edgeGeometryEntityID, label: "surface curve")
            guard try entityName(edgeGeometryEntity) == "SURFACE_CURVE" else {
                throw unsupported("STEP exact coedge requires an explicit SURFACE_CURVE p-curve.")
            }
            let surfaceCurveArguments = try arguments(of: edgeGeometryEntity, named: "SURFACE_CURVE")
            guard surfaceCurveArguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(edgeGeometryEntityID) is malformed.")
            }
            let associatedGeometry = try referenceList(
                surfaceCurveArguments[2],
                label: "surface curve associated geometry"
            )
            guard let curve = geometry.curves[edge.curveID],
                  let curveSameSense = edgeCurveSameSense[edgeID] else {
                throw missing("STEP edge 3D curve")
            }
            let modelStart = curveSameSense ? startVertex.point : endVertex.point
            let modelEnd = curveSameSense ? endVertex.point : startVertex.point
            var matchingPcurves: [Int] = []
            for pcurveEntityID in associatedGeometry {
                try processingBudget.check(format: .step)
                let pcurveEntity = try requiredEntity(pcurveEntityID, label: "p-curve")
                guard try entityName(pcurveEntity) == "PCURVE" else {
                    continue
                }
                let pcurveArguments = try arguments(of: pcurveEntity, named: "PCURVE")
                guard pcurveArguments.count == 3 else {
                    throw invalid("STEP PCURVE #\(pcurveEntityID) is malformed.")
                }
                if try reference(pcurveArguments[1], label: "p-curve basis surface") == surfaceEntityID {
                    matchingPcurves.append(pcurveEntityID)
                }
            }
            let masterRepresentation = surfaceCurveArguments[3]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if matchingPcurves.isEmpty,
               masterRepresentation == ".CURVE_3D.",
               let sourceParameterCurve = intersectionPcurves[edge.curveID]?[surface] {
                let startParameter = try curve.parameterProjection(
                    of: modelStart,
                    tolerance: tolerance
                ).parameter
                let endParameter = try curve.parameterProjection(
                    of: modelEnd,
                    tolerance: tolerance
                ).parameter
                guard endParameter > startParameter + tolerance.relative else {
                    throw invalid(
                        "STEP implicit intersection model direction has a non-increasing trim interval."
                    )
                }
                let modelParameterCurve = try sourceParameterCurve.trimmed(
                    from: startParameter,
                    to: endParameter,
                    curveDomain: curve.parameterDomain,
                    tolerance: tolerance
                )
                let edgeParameterCurve = curveSameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                return orientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
            }
            if matchingPcurves.isEmpty,
               masterRepresentation == ".CURVE_3D.",
               case let .analytic(.planeTorus(planeTorus)) = curve,
               associatedGeometry.contains(surfaceEntityID) {
                let role: SurfaceIntersectionSurfaceRole
                if surface == planeTorus.planeSurface {
                    role = .first
                } else if surface == planeTorus.torusSurface {
                    role = .second
                } else {
                    throw invalid(
                        "STEP plane-torus coedge surface is not one of its exact source surfaces."
                    )
                }
                let exactIntersection = try CertifiedAnalyticAnalyticIntersectionCurve(
                    planeTorusCurve: planeTorus,
                    firstSurface: planeTorus.planeSurface,
                    secondSurface: planeTorus.torusSurface,
                    tolerance: tolerance
                )
                let period = 2.0 * Double.pi
                let startParameter = try curve.parameterProjection(
                    of: modelStart,
                    tolerance: tolerance
                ).parameter
                var endParameter = try curve.parameterProjection(
                    of: modelEnd,
                    tolerance: tolerance
                ).parameter
                while endParameter <= startParameter + tolerance.angle {
                    endParameter += period
                }
                guard endParameter - startParameter <= period + tolerance.angle else {
                    throw invalid("STEP plane-torus coedge trim exceeds one period.")
                }
                let modelParameterCurve = SurfaceParameterCurve.certifiedAnalyticPair(
                    try CertifiedAnalyticPairSurfaceParameterCurve(
                        intersection: exactIntersection,
                        role: role,
                        startFraction: startParameter / period,
                        endFraction: endParameter / period,
                        tolerance: tolerance
                    )
                )
                let edgeParameterCurve = curveSameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                return orientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
            }
            if matchingPcurves.isEmpty,
               masterRepresentation == ".CURVE_3D.",
               associatedGeometry.filter({ $0 == surfaceEntityID }).count == 1 {
                let modelParameterCurve = try ExactAssociatedSurfacePcurveBuilder().build(
                    curve: curve,
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    surface: surface,
                    tolerance: tolerance
                )
                let edgeParameterCurve = curveSameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                return orientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
            }
            guard matchingPcurves.count == 1, let pcurveEntityID = matchingPcurves.first else {
                throw invalid("STEP coedge requires exactly one p-curve for face surface #\(surfaceEntityID).")
            }
            let pcurveEntity = try requiredEntity(pcurveEntityID, label: "p-curve")
            let pcurveArguments = try arguments(of: pcurveEntity, named: "PCURVE")
            let representationEntityID = try reference(pcurveArguments[2], label: "p-curve representation")
            let representationEntity = try requiredEntity(representationEntityID, label: "p-curve representation")
            let representationArguments = try arguments(
                of: representationEntity,
                named: "DEFINITIONAL_REPRESENTATION"
            )
            guard representationArguments.count == 3 else {
                throw invalid("STEP DEFINITIONAL_REPRESENTATION #\(representationEntityID) is malformed.")
            }
            let curveEntityIDs = try referenceList(representationArguments[1], label: "p-curve item list")
            guard curveEntityIDs.count == 1, let curveEntityID = curveEntityIDs.first else {
                throw invalid("STEP p-curve representation must contain exactly one curve.")
            }
            let curveEntity = try requiredEntity(curveEntityID, label: "2D p-curve")
            let modelParameterCurve: SurfaceParameterCurve
            switch try entityName(curveEntity) {
            case "LINE":
                modelParameterCurve = try parameterLineCurve(
                    try line2D(curveEntityID),
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    surface: surface,
                    pcurveEntityID: pcurveEntityID
                )
            case "ELLIPSE":
                modelParameterCurve = try parameterEllipseCurve(
                    try ellipse2D(curveEntityID),
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    modelCurve: curve,
                    surface: surface,
                    pcurveEntityID: pcurveEntityID
                )
            case "":
                modelParameterCurve = try parameterBSplineCurve(
                    curveEntity,
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    surface: surface,
                    pcurveEntityID: pcurveEntityID
                )
            default:
                throw unsupported("STEP PCURVE #\(pcurveEntityID) uses an unsupported 2D curve.")
            }
            let edgeParameterCurve = curveSameSense
                ? modelParameterCurve
                : try modelParameterCurve.reversed(tolerance: tolerance)
            return orientation == .forward
                ? edgeParameterCurve
                : try edgeParameterCurve.reversed(tolerance: tolerance)
        }

        func parameterLineCurve(
            _ parameterLine: (originX: Double, originY: Double, directionX: Double, directionY: Double),
            modelStart: Point3D,
            modelEnd: Point3D,
            surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameterCurve {
            let encodedOrigin = SurfaceParameter(
                u: parameterLine.originX,
                v: parameterLine.originY
            )
            let modelParameterStart = try ExactSurfaceParameterCodec.decode(
                encodedOrigin,
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let reconstructedStart = try surface.point(
                u: modelParameterStart.u,
                v: modelParameterStart.v,
                    tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) origin disagrees with its 3D curve.")
            }
            let projectedEnd = try surface.parameterProjection(
                of: modelEnd,
                    tolerance: tolerance
            )
            let modelParameterEnd = try matchingParameterEnd(
                projectedEnd,
                line: parameterLine,
                on: surface,
                pcurveEntityID: pcurveEntityID
            )
            let reconstructedEnd = try surface.point(
                u: modelParameterEnd.u,
                v: modelParameterEnd.v,
                    tolerance: tolerance
            )
            guard reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) end disagrees with its 3D curve.")
            }
            return .polyline([
                modelParameterStart,
                modelParameterEnd,
            ])
        }

        func parameterEllipseCurve(
            _ ellipse: STEPParameterEllipse,
            modelStart: Point3D,
            modelEnd: Point3D,
            modelCurve: Curve3D,
            surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameterCurve {
            let startMatch = try matchingEllipseParameter(
                try surface.parameterProjection(
                    of: modelStart,
                        tolerance: tolerance
                ),
                ellipse: ellipse,
                on: surface,
                pcurveEntityID: pcurveEntityID
            )
            let endMatch = try matchingEllipseParameter(
                try surface.parameterProjection(
                    of: modelEnd,
                        tolerance: tolerance
                ),
                ellipse: ellipse,
                on: surface,
                pcurveEntityID: pcurveEntityID
            )
            let reconstructedStart = try surface.point(
                u: startMatch.parameter.u,
                v: startMatch.parameter.v,
                    tolerance: tolerance
            )
            let reconstructedEnd = try surface.point(
                u: endMatch.parameter.u,
                v: endMatch.parameter.v,
                    tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ), reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) ellipse endpoints disagree with its 3D curve.")
            }

            let modelParameter = try modelCurve.parameterProjection(
                of: modelStart,
                    tolerance: tolerance
            ).parameter
            let modelTangent = try modelCurve.differentialGeometry(
                at: modelParameter,
                    tolerance: tolerance
            ).tangent
            let encodedDerivative = ellipse.derivative(at: startMatch.ellipseParameter)
            let decodedOrigin = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x, v: ellipse.center.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let decodedDerivativePoint = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(
                    u: ellipse.center.x + encodedDerivative.x,
                    v: ellipse.center.y + encodedDerivative.y
                ),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let differential = try surface.differentialGeometry(
                atU: startMatch.parameter.u,
                v: startMatch.parameter.v,
                    tolerance: tolerance
            )
            let surfaceTangent = differential.tangentU
                * (decodedDerivativePoint.u - decodedOrigin.u)
                + differential.tangentV
                * (decodedDerivativePoint.v - decodedOrigin.v)
            let alignment = surfaceTangent.dot(modelTangent)
            guard abs(alignment) > tolerance.angle else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) ellipse tangent is inconsistent with its 3D curve.")
            }

            var endParameter = endMatch.ellipseParameter
            if alignment > 0.0 {
                while endParameter <= startMatch.ellipseParameter + tolerance.angle {
                    endParameter += 2.0 * Double.pi
                }
            } else {
                while endParameter >= startMatch.ellipseParameter - tolerance.angle {
                    endParameter -= 2.0 * Double.pi
                }
            }
            guard abs(endParameter - startMatch.ellipseParameter)
                    <= 2.0 * Double.pi + tolerance.angle else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) ellipse trim exceeds one period.")
            }

            let decodedCenter = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x, v: ellipse.center.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let major = ellipse.majorVector
            let minor = ellipse.minorVector
            let decodedMajor = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x + major.x, v: ellipse.center.y + major.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let decodedMinor = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x + minor.x, v: ellipse.center.y + minor.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            return .harmonic(
                center: Point2D(x: decodedCenter.u, y: decodedCenter.v),
                cosine: Point2D(
                    x: decodedMajor.u - decodedCenter.u,
                    y: decodedMajor.v - decodedCenter.v
                ),
                sine: Point2D(
                    x: decodedMinor.u - decodedCenter.u,
                    y: decodedMinor.v - decodedCenter.v
                ),
                startParameter: startMatch.ellipseParameter,
                endParameter: endParameter
            )
        }

        func parameterBSplineCurve(
            _ entity: String,
            modelStart: Point3D,
            modelEnd: Point3D,
            surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameterCurve {
            let curveArguments = try complexArguments(of: entity, named: "B_SPLINE_CURVE")
            let knotArguments = try complexArguments(of: entity, named: "B_SPLINE_CURVE_WITH_KNOTS")
            let rationalArguments = try complexArguments(of: entity, named: "RATIONAL_B_SPLINE_CURVE")
            guard curveArguments.count == 5,
                  knotArguments.count == 3,
                  rationalArguments.count == 1,
                  try boolean(curveArguments[3]) == false,
                  try boolean(curveArguments[4]) == false else {
                throw unsupported("STEP p-curve B-spline must be open and non-self-intersecting.")
            }
            let degree = try integer(curveArguments[0], label: "p-curve B-spline degree")
            let pointIDs = try referenceList(curveArguments[1], label: "p-curve control points")
            var controlPoints: [Point2D] = []
            for pointID in pointIDs {
                let pointEntity = try requiredEntity(pointID, label: "2D B-spline control point")
                let pointArguments = try arguments(of: pointEntity, named: "CARTESIAN_POINT")
                guard pointArguments.count == 2 else {
                    throw invalid("STEP 2D B-spline control point #\(pointID) is malformed.")
                }
                let values = try numberList(
                    pointArguments[1],
                    expectedCount: 2,
                    label: "2D B-spline control point"
                )
                let decoded = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(u: values[0], v: values[1]),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance
                )
                controlPoints.append(Point2D(x: decoded.u, y: decoded.v))
            }
            let multiplicities = try integerList(
                knotArguments[0],
                label: "p-curve B-spline knot multiplicities"
            )
            let distinctKnots = try arbitraryNumberList(
                knotArguments[1],
                label: "p-curve B-spline knots"
            )
            let curve = BSplineCurve2D(
                degree: degree,
                knots: try expandedKnots(
                    values: distinctKnots,
                    multiplicities: multiplicities,
                    label: "p-curve B-spline"
                ),
                controlPoints: controlPoints,
                weights: try arbitraryNumberList(
                    rationalArguments[0],
                    label: "p-curve B-spline weights"
                )
            )
            try curve.validate(tolerance: tolerance)
            let parameterCurve = SurfaceParameterCurve.bSpline(curve)
            let start = try parameterCurve.startParameter(tolerance: tolerance)
            let end = try parameterCurve.endParameter(tolerance: tolerance)
            let reconstructedStart = try surface.point(
                u: start.u,
                v: start.v,
                    tolerance: tolerance
            )
            let reconstructedEnd = try surface.point(
                u: end.u,
                v: end.v,
                    tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ), reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) B-spline endpoints disagree with its 3D curve.")
            }
            return parameterCurve
        }

        func matchingParameterEnd(
            _ projection: SurfaceParameterProjection,
            line: (originX: Double, originY: Double, directionX: Double, directionY: Double),
            on surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameter {
            let base = SurfaceParameter(u: projection.u, v: projection.v)
            let uOffsets = periodicOffsets(for: surface.uDomain)
            let vOffsets = periodicOffsets(for: surface.vDomain)
            let tolerance = ExactSurfaceParameterCodec.encodedTolerance(on: surface, unit: lengthUnit, tolerance: tolerance)
            var best: (parameter: SurfaceParameter, distance: Double)?
            for uOffset in uOffsets {
                for vOffset in vOffsets {
                    let candidate = SurfaceParameter(
                        u: base.u + uOffset,
                        v: base.v + vOffset
                    )
                    let encoded = ExactSurfaceParameterCodec.encode(candidate, on: surface, unit: lengthUnit)
                    let offsetX = encoded.u - line.originX
                    let offsetY = encoded.v - line.originY
                    let residual = abs(offsetX * line.directionY - offsetY * line.directionX)
                    let distance = offsetX * line.directionX + offsetY * line.directionY
                    guard residual <= tolerance, distance > tolerance else {
                        continue
                    }
                    if best == nil || distance < best!.distance {
                        best = (candidate, distance)
                    }
                }
            }
            guard let best else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) has no continuous periodic endpoint match.")
            }
            return best.parameter
        }

        func matchingEllipseParameter(
            _ projection: SurfaceParameterProjection,
            ellipse: STEPParameterEllipse,
            on surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> (parameter: SurfaceParameter, ellipseParameter: Double) {
            let uOffsets = periodicOffsets(for: surface.uDomain)
            let vOffsets = periodicOffsets(for: surface.vDomain)
            let tolerance = ExactSurfaceParameterCodec.encodedTolerance(on: surface, unit: lengthUnit, tolerance: tolerance)
            var best: (parameter: SurfaceParameter, ellipseParameter: Double, residual: Double)?
            for uOffset in uOffsets {
                for vOffset in vOffsets {
                    let candidate = SurfaceParameter(
                        u: projection.u + uOffset,
                        v: projection.v + vOffset
                    )
                    let encoded = ExactSurfaceParameterCodec.encode(candidate, on: surface, unit: lengthUnit)
                    let point = Point2D(x: encoded.u, y: encoded.v)
                    let residual = ellipse.residual(of: point)
                    guard residual <= tolerance else {
                        continue
                    }
                    let match = (
                        parameter: candidate,
                        ellipseParameter: ellipse.parameter(of: point),
                        residual: residual
                    )
                    if let current = best {
                        if match.residual < current.residual {
                            best = match
                        }
                    } else {
                        best = match
                    }
                }
            }
            guard let best else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) has no exact ellipse endpoint match.")
            }
            return (best.parameter, best.ellipseParameter)
        }

        func periodicOffsets(for domain: ParameterDomain) -> [Double] {
            guard case let .periodic(period) = domain else {
                return [0.0]
            }
            return [-period, 0.0, period]
        }

        func line2D(_ entityID: Int) throws -> (
            originX: Double,
            originY: Double,
            directionX: Double,
            directionY: Double
        ) {
            let entity = try requiredEntity(entityID, label: "2D line")
            let lineArguments = try arguments(of: entity, named: "LINE")
            guard lineArguments.count == 3 else {
                throw invalid("STEP 2D LINE #\(entityID) is malformed.")
            }
            let pointEntityID = try reference(lineArguments[1], label: "2D line origin")
            let pointEntity = try requiredEntity(pointEntityID, label: "2D cartesian point")
            let pointArguments = try arguments(of: pointEntity, named: "CARTESIAN_POINT")
            guard pointArguments.count == 2 else {
                throw invalid("STEP 2D CARTESIAN_POINT #\(pointEntityID) is malformed.")
            }
            let point = try numberList(pointArguments[1], expectedCount: 2, label: "2D coordinates")
            let vectorEntityID = try reference(lineArguments[2], label: "2D line vector")
            let vectorEntity = try requiredEntity(vectorEntityID, label: "2D vector")
            let vectorArguments = try arguments(of: vectorEntity, named: "VECTOR")
            guard vectorArguments.count == 3,
                  try number(vectorArguments[2], label: "2D vector magnitude") > 0.0 else {
                throw invalid("STEP 2D VECTOR #\(vectorEntityID) is malformed.")
            }
            let directionEntityID = try reference(vectorArguments[1], label: "2D vector direction")
            let directionEntity = try requiredEntity(directionEntityID, label: "2D direction")
            let directionArguments = try arguments(of: directionEntity, named: "DIRECTION")
            guard directionArguments.count == 2 else {
                throw invalid("STEP 2D DIRECTION #\(directionEntityID) is malformed.")
            }
            let direction = try numberList(directionArguments[1], expectedCount: 2, label: "2D direction ratios")
            let normalized = try normalized2D(x: direction[0], y: direction[1])
            return (
                point[0],
                point[1],
                normalized.x,
                normalized.y
            )
        }

        func ellipse2D(_ entityID: Int) throws -> STEPParameterEllipse {
            let entity = try requiredEntity(entityID, label: "2D ellipse")
            let ellipseArguments = try arguments(of: entity, named: "ELLIPSE")
            guard ellipseArguments.count == 4 else {
                throw invalid("STEP 2D ELLIPSE #\(entityID) is malformed.")
            }
            let placementEntityID = try reference(ellipseArguments[1], label: "2D ellipse placement")
            let placementEntity = try requiredEntity(placementEntityID, label: "2D axis placement")
            let placementArguments = try arguments(of: placementEntity, named: "AXIS2_PLACEMENT_2D")
            guard placementArguments.count == 3 else {
                throw invalid("STEP AXIS2_PLACEMENT_2D #\(placementEntityID) is malformed.")
            }
            let pointEntityID = try reference(placementArguments[1], label: "2D placement origin")
            let pointEntity = try requiredEntity(pointEntityID, label: "2D cartesian point")
            let pointArguments = try arguments(of: pointEntity, named: "CARTESIAN_POINT")
            guard pointArguments.count == 2 else {
                throw invalid("STEP 2D CARTESIAN_POINT #\(pointEntityID) is malformed.")
            }
            let center = try numberList(pointArguments[1], expectedCount: 2, label: "2D coordinates")
            let directionEntityID = try reference(placementArguments[2], label: "2D placement direction")
            let directionEntity = try requiredEntity(directionEntityID, label: "2D direction")
            let directionArguments = try arguments(of: directionEntity, named: "DIRECTION")
            guard directionArguments.count == 2 else {
                throw invalid("STEP 2D DIRECTION #\(directionEntityID) is malformed.")
            }
            let direction = try numberList(
                directionArguments[1],
                expectedCount: 2,
                label: "2D direction ratios"
            )
            let normalized = try normalized2D(x: direction[0], y: direction[1])
            return try STEPParameterEllipse(
                center: Point2D(x: center[0], y: center[1]),
                majorDirection: Point2D(x: normalized.x, y: normalized.y),
                majorRadius: try number(ellipseArguments[2], label: "2D ellipse major radius"),
                minorRadius: try number(ellipseArguments[3], label: "2D ellipse minor radius"),
                tolerance: tolerance.distance
            )
        }

        func normalized2D(x: Double, y: Double) throws -> (x: Double, y: Double) {
            let length = hypot(x, y)
            guard length.isFinite, length > tolerance.distance else {
                throw invalid("STEP 2D direction has zero length.")
            }
            return (x / length, y / length)
        }

        func requiredEntity(_ entityID: Int, label: String) throws -> String {
            guard let entity = entities[entityID] else {
                throw missing("\(label) #\(entityID)")
            }
            return entity
        }

        func entityName(_ entity: String) throws -> String {
            let trimmed = entity.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "(" {
                return ""
            }
            guard let opening = trimmed.firstIndex(of: "("), opening > trimmed.startIndex else {
                throw invalid("STEP entity syntax is malformed.")
            }
            return String(trimmed[..<opening]).uppercased()
        }

        func isAnalyticMarker(_ text: String) -> Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines) == "'SWIFTCAD_ANALYTIC'"
        }

        func complexArguments(of entity: String, named name: String) throws -> [String] {
            let marker = "\(name)("
            guard let markerRange = entity.range(of: marker) else {
                throw unsupported("STEP complex entity does not contain \(name).")
            }
            let opening = entity.index(before: markerRange.upperBound)
            var cursor = entity.index(after: opening)
            let contentStart = cursor
            var depth = 1
            var inString = false
            while cursor < entity.endIndex {
                let character = entity[cursor]
                if character == "'" {
                    inString.toggle()
                } else if !inString {
                    if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                        if depth == 0 {
                            return try splitTopLevel(String(entity[contentStart..<cursor]))
                        }
                    }
                }
                cursor = entity.index(after: cursor)
            }
            throw invalid("STEP complex \(name) component is unterminated.")
        }

        func arguments(of entity: String, named expectedName: String) throws -> [String] {
            let trimmed = entity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard try entityName(trimmed) == expectedName,
                  let opening = trimmed.firstIndex(of: "("),
                  trimmed.last == ")" else {
                throw unsupported("STEP entity is not a supported \(expectedName).")
            }
            let contentStart = trimmed.index(after: opening)
            let contentEnd = trimmed.index(before: trimmed.endIndex)
            return try splitTopLevel(String(trimmed[contentStart..<contentEnd]))
        }

        func splitTopLevel(_ text: String) throws -> [String] {
            var values: [String] = []
            var depth = 0
            var inString = false
            var start = text.startIndex
            var cursor = text.startIndex
            while cursor < text.endIndex {
                let character = text[cursor]
                if character == "'" {
                    let next = text.index(after: cursor)
                    if inString, next < text.endIndex, text[next] == "'" {
                        cursor = text.index(after: next)
                        continue
                    }
                    inString.toggle()
                } else if !inString {
                    if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                    } else if character == ",", depth == 0 {
                        values.append(String(text[start..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines))
                        start = text.index(after: cursor)
                    }
                    guard depth >= 0 else {
                        throw invalid("STEP tuple syntax is malformed.")
                    }
                }
                cursor = text.index(after: cursor)
            }
            guard !inString, depth == 0 else {
                throw invalid("STEP tuple syntax is unterminated.")
            }
            values.append(String(text[start..<text.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines))
            guard values.allSatisfy({ !$0.isEmpty }) else {
                throw invalid("STEP tuple contains an empty value.")
            }
            return values
        }

        func reference(_ text: String, label: String) throws -> Int {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.first == "#",
                  value.dropFirst().allSatisfy(\.isNumber),
                  let entityID = Int(value.dropFirst()) else {
                throw invalid("STEP \(label) reference is malformed.")
            }
            return entityID
        }

        func referenceList(_ text: String, label: String) throws -> [Int] {
            let content = try tupleContent(text, label: label)
            return try splitTopLevel(content).map { try reference($0, label: label) }
        }

        func numberList(_ text: String, expectedCount: Int, label: String) throws -> [Double] {
            let content = try tupleContent(text, label: label)
            let values = try splitTopLevel(content).map { try number($0, label: label) }
            guard values.count == expectedCount else {
                throw invalid("STEP \(label) must contain \(expectedCount) values.")
            }
            return values
        }

        func arbitraryNumberList(_ text: String, label: String) throws -> [Double] {
            let content = try tupleContent(text, label: label)
            return try splitTopLevel(content).map { try number($0, label: label) }
        }

        func integerList(_ text: String, label: String) throws -> [Int] {
            let content = try tupleContent(text, label: label)
            return try splitTopLevel(content).map { try integer($0, label: label) }
        }

        func tupleRows(_ text: String, label: String) throws -> [String] {
            try splitTopLevel(tupleContent(text, label: label))
        }

        func expandedKnots(
            values: [Double],
            multiplicities: [Int],
            label: String
        ) throws -> [Double] {
            guard !values.isEmpty, values.count == multiplicities.count,
                  multiplicities.allSatisfy({ $0 > 0 }) else {
                throw invalid("STEP \(label) knot data is inconsistent.")
            }
            var knots: [Double] = []
            for (value, multiplicity) in zip(values, multiplicities) {
                knots.append(contentsOf: repeatElement(value, count: multiplicity))
            }
            return knots
        }

        func tupleContent(_ text: String, label: String) throws -> String {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.first == "(", value.last == ")" else {
                throw invalid("STEP \(label) tuple is malformed.")
            }
            return String(value.dropFirst().dropLast())
        }

        func number(_ text: String, label: String) throws -> Double {
            guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
                throw invalid("STEP \(label) is not a finite number.")
            }
            return value
        }

        func integer(_ text: String, label: String) throws -> Int {
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw invalid("STEP \(label) is not an integer.")
            }
            return value
        }

        func boolean(_ text: String) throws -> Bool {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case ".T.": true
            case ".F.": false
            default: throw invalid("STEP logical value is malformed.")
            }
        }

        func orientation(_ text: String) throws -> Orientation {
            try boolean(text) ? .forward : .reversed
        }

        func taggedID<Tag>(namespace: UInt64, entityID: Int) -> TaggedID<Tag> {
            TaggedID<Tag>(highBits: namespace, lowBits: UInt64(entityID))
        }

        func invalid(_ message: String) -> ImportError {
            .invalidData(message)
        }

        func missing(_ label: String) -> ImportError {
            .missingRequiredEntity(label)
        }

        func unsupported(_ message: String) -> KernelError {
            KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: message
            )
        }
    }
}
