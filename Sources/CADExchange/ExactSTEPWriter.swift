import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct ExactSTEPWriter {
    let resourceLimits: ExchangeResourceLimits
    let tolerance: ModelingTolerance

    func write(
        brep: BRepModel,
        units: UnitSystem,
        to sink: any ByteSink
    ) throws {
        var table = EntityTable(
            maximumEntities: resourceLimits.maximumEntities,
            tolerance: tolerance
        )
        let applicationContext = try table.add("APPLICATION_CONTEXT('managed model based 3d engineering')")
        let productContext = try table.add("PRODUCT_CONTEXT('',#\(applicationContext),'mechanical')")
        let product = try table.add("PRODUCT('SWIFTCAD','SWIFTCAD','',(#\(productContext)))")
        let formation = try table.add("PRODUCT_DEFINITION_FORMATION('','',#\(product))")
        let definitionContext = try table.add("PRODUCT_DEFINITION_CONTEXT('part definition',#\(applicationContext),'design')")
        let definition = try table.add("PRODUCT_DEFINITION('design','',#\(formation),#\(definitionContext))")
        let definitionShape = try table.add("PRODUCT_DEFINITION_SHAPE('','',#\(definition))")
        let lengthUnit = try lengthUnitEntity(units.length, table: &table)
        let angleUnit = try table.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
        let solidAngleUnit = try table.add("(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT())")
        let uncertainty = number(units.length.fromInternal(tolerance.distance))
        let context = try table.add(
            "(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#\(try table.add("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(uncertainty)),#\(lengthUnit),'distance_accuracy_value','confusion accuracy')")))) GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(lengthUnit),#\(angleUnit),#\(solidAngleUnit))) REPRESENTATION_CONTEXT('',''))"
        )
        var vertexEntities: [VertexID: Int] = [:]
        for vertexID in brep.vertices.keys.sorted() {
            guard let vertex = brep.vertices[vertexID] else {
                throw exchangeError(.missingReference, "STEP vertex table is incomplete.")
            }
            let point = try cartesianPoint(vertex.point, units: units.length, table: &table)
            vertexEntities[vertexID] = try table.add("VERTEX_POINT('',#\(point))")
        }
        let parameterContext = try table.add(
            "(GEOMETRIC_REPRESENTATION_CONTEXT(2) PARAMETRIC_REPRESENTATION_CONTEXT() REPRESENTATION_CONTEXT('2D SPACE',''))"
        )
        var surfaceEntities: [SurfaceID: Int] = [:]
        var surfaceEntityByGeometry: [Surface3D: Int] = [:]
        for faceID in brep.faces.keys.sorted() {
            guard let face = brep.faces[faceID],
                  let surface = brep.geometry.surfaces[face.surfaceID] else {
                throw exchangeError(.missingReference, "STEP face surface is missing.")
            }
            if surfaceEntities[face.surfaceID] == nil {
                let entity = try exactSurfaceEntity(
                    surface,
                    units: units.length,
                    table: &table
                )
                surfaceEntities[face.surfaceID] = entity
                surfaceEntityByGeometry[surface] = entity
            }
        }
        var curveEntities: [EdgeID: Int] = [:]
        var edgeSameSense: [EdgeID: Bool] = [:]
        var exactIntersectionAssociations: [EdgeID: [SurfaceCurveAssociation]] = [:]
        for edgeID in brep.edges.keys.sorted() {
            guard let edge = brep.edges[edgeID],
                  let startPoint = brep.vertices[edge.startVertexID]?.point,
                  let endPoint = brep.vertices[edge.endVertexID]?.point,
                  let curve = brep.geometry.curves[edge.curveID] else {
                throw exchangeError(.missingReference, "STEP edge geometry is incomplete.")
            }
            switch curve {
            case let .line(line):
                let origin = try cartesianPoint(line.origin, units: units.length, table: &table)
                let direction = try directionEntity(line.direction, table: &table)
                let vector = try table.add("VECTOR('',#\(direction),1.)")
                curveEntities[edgeID] = try table.add("LINE('',#\(origin),#\(vector))")
                let directionResidual = (endPoint - startPoint).dot(line.direction)
                guard abs(directionResidual) > tolerance.distance else {
                    throw exchangeError(.topologyFailure, "STEP line direction is perpendicular to its edge span.")
                }
                edgeSameSense[edgeID] = directionResidual > 0.0
            case let .bSpline(bSpline):
                guard let trim = edge.trim,
                      case let .closed(lower, upper) = bSpline.domain else {
                    throw exchangeError(
                        .topologyFailure,
                        "STEP B-spline edges require a finite explicit trim interval."
                    )
                }
                guard trim.startParameter >= lower - tolerance.distance,
                      trim.startParameter <= upper + tolerance.distance,
                      trim.endParameter >= lower - tolerance.distance,
                      trim.endParameter <= upper + tolerance.distance,
                      abs(trim.endParameter - trim.startParameter) > tolerance.distance else {
                    throw exchangeError(
                        .topologyFailure,
                        "STEP B-spline edge trim is outside its finite knot domain."
                    )
                }
                let basis = try bSplineCurveEntity(
                    bSpline,
                    units: units.length,
                    table: &table
                )
                let followsBasis = trim.endParameter > trim.startParameter
                curveEntities[edgeID] = try table.add(
                    "TRIMMED_CURVE('SWIFTCAD_BSPLINE_TRIM',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(followsBasis ? ".T." : ".F."),.PARAMETER.)"
                )
                edgeSameSense[edgeID] = true
            case let .circle(circle):
                let trim = try requiredPeriodicTrim(edge, label: "circle")
                curveEntities[edgeID] = try circleEntity(
                    circle,
                    units: units.length,
                    table: &table
                )
                edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
            case let .analytic(analytic):
                if case let .planeTorus(planeTorus) = analytic {
                    guard let trim = edge.trim else {
                        throw exchangeError(
                            .topologyFailure,
                            "STEP plane-torus intersection edges require an explicit trim."
                        )
                    }
                    let transfer = try ExactPlaneTorusTransferBuilder().build(
                        curve: planeTorus,
                        trim: trim,
                        tolerance: tolerance
                    )
                    curveEntities[edgeID] = try bSplineCurveEntity(
                        transfer.curve,
                        units: units.length,
                        table: &table
                    )
                    edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
                    let exactSurfaces = [planeTorus.planeSurface, planeTorus.torusSurface]
                    exactIntersectionAssociations[edgeID] = try exactSurfaces.map { surface in
                        let entity: Int
                        if let existing = surfaceEntityByGeometry[surface] {
                            entity = existing
                        } else {
                            entity = try exactSurfaceEntity(
                                surface,
                                units: units.length,
                                table: &table
                            )
                            surfaceEntityByGeometry[surface] = entity
                        }
                        return SurfaceCurveAssociation(entity: entity, isPcurve: false)
                    }
                } else {
                    let result = try analyticCurveEntity(
                        analytic,
                        edge: edge,
                        startPoint: startPoint,
                        endPoint: endPoint,
                        units: units.length,
                        table: &table
                    )
                    curveEntities[edgeID] = result.entity
                    edgeSameSense[edgeID] = result.sameSense
                }
            case let .implicit(implicit):
                guard let trim = edge.trim else {
                    throw exchangeError(
                        .topologyFailure,
                        "STEP implicit intersection edges require an explicit trim."
                    )
                }
                let source = try ExactImplicitIntersectionTransferSource.resolve(
                    edgeID: edgeID,
                    in: brep,
                    tolerance: tolerance
                )
                guard source.curve == implicit else {
                    throw exchangeError(
                        .topologyFailure,
                        "STEP implicit edge curve disagrees with its certified pcurve provenance."
                    )
                }
                let transfer = try ExactImplicitIntersectionTransferBuilder().build(
                    source: source,
                    trim: trim,
                    tolerance: tolerance
                )
                curveEntities[edgeID] = try bSplineCurveEntity(
                    transfer.curve,
                    units: units.length,
                    table: &table
                )
                edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
                exactIntersectionAssociations[edgeID] = try [
                    source.firstSurface,
                    source.secondSurface,
                ].map { surface in
                    let entity: Int
                    if let existing = surfaceEntityByGeometry[surface] {
                        entity = existing
                    } else {
                        entity = try exactSurfaceEntity(
                            surface,
                            units: units.length,
                            table: &table
                        )
                        surfaceEntityByGeometry[surface] = entity
                    }
                    return SurfaceCurveAssociation(entity: entity, isPcurve: false)
                }
            case let .surfaceLift(lift):
                guard let trim = edge.trim else {
                    throw exchangeError(
                        .topologyFailure,
                        "STEP surface-lift edges require an explicit normalized trim."
                    )
                }
                let transfer = try ExactSurfaceLiftTransferBuilder().build(
                    lift: lift,
                    trim: trim,
                    tolerance: tolerance
                )
                curveEntities[edgeID] = try bSplineCurveEntity(
                    transfer.curve,
                    name: "SWIFTCAD_SURFACE_LIFT",
                    units: units.length,
                    table: &table
                )
                edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
            case .certifiedIntersection:
                throw exchangeError(
                    .unsupportedCapability,
                    "STEP export of certified intersection curves requires an exact transfer representation."
                )
            }
        }
        var edgeAssociations = exactIntersectionAssociations
        for faceID in brep.faces.keys.sorted() {
            guard let face = brep.faces[faceID],
                  let surface = brep.geometry.surfaces[face.surfaceID],
                  let surfaceEntity = surfaceEntities[face.surfaceID] else {
                throw exchangeError(.missingReference, "STEP face surface is missing.")
            }
            for loopID in face.loops {
                guard let loop = brep.loops[loopID] else {
                    throw exchangeError(.missingReference, "STEP face loop is missing.")
                }
                for coedge in loop.coedges {
                    guard let parameterCurve = coedge.surfaceParameterCurve,
                          let edge = brep.edges[coedge.edgeID],
                          let sameSense = edgeSameSense[coedge.edgeID],
                          let start = brep.vertices[edge.startVertexID]?.point,
                          let end = brep.vertices[edge.endVertexID]?.point else {
                        throw exchangeError(.topologyFailure, "STEP exact coedge p-curve is incomplete.")
                    }
                    let association = try pcurveEntity(
                        parameterCurve: parameterCurve,
                        parameterCurveFollowsModel: (coedge.orientation == .forward) == sameSense,
                        modelStart: sameSense ? start : end,
                        modelEnd: sameSense ? end : start,
                        surface: surface,
                        surfaceEntity: surfaceEntity,
                        units: units.length,
                        parameterContext: parameterContext,
                        table: &table
                    )
                    if edgeAssociations[coedge.edgeID, default: []].contains(association) == false {
                        edgeAssociations[coedge.edgeID, default: []].append(association)
                    }
                    guard edgeAssociations[coedge.edgeID, default: []].count <= 2 else {
                        throw exchangeError(
                            .unsupportedCapability,
                            "STEP SURFACE_CURVE supports at most two exact face-surface associations."
                        )
                    }
                }
            }
        }
        var edgeEntities: [EdgeID: Int] = [:]
        for edgeID in brep.edges.keys.sorted() {
            guard let edge = brep.edges[edgeID],
                  let startVertex = vertexEntities[edge.startVertexID],
                  let endVertex = vertexEntities[edge.endVertexID],
                  let curve = curveEntities[edgeID],
                  let associations = edgeAssociations[edgeID],
                  !associations.isEmpty,
                  let sameSense = edgeSameSense[edgeID] else {
                throw exchangeError(.missingReference, "STEP edge geometry or p-curve is missing.")
            }
            let masterRepresentation = associations.allSatisfy(\.isPcurve)
                ? ".PCURVE_S1."
                : ".CURVE_3D."
            let surfaceCurve = try table.add(
                "SURFACE_CURVE('',#\(curve),(\(associations.map { "#\($0.entity)" }.joined(separator: ","))),\(masterRepresentation))"
            )
            edgeEntities[edgeID] = try table.add(
                "EDGE_CURVE('',#\(startVertex),#\(endVertex),#\(surfaceCurve),\(sameSense ? ".T." : ".F."))"
            )
        }
        var faceEntities: [FaceID: Int] = [:]
        for faceID in brep.faces.keys.sorted() {
            guard let face = brep.faces[faceID],
                  let surface = surfaceEntities[face.surfaceID] else {
                throw exchangeError(
                    .unsupportedCapability,
                    "STEP face surface has no exported exact entity."
                )
            }
            var bounds: [Int] = []
            for loopID in face.loops {
                guard let loop = brep.loops[loopID] else {
                    throw exchangeError(.missingReference, "STEP face loop is missing.")
                }
                let orientedEdges = try loop.coedges.map { coedge -> Int in
                    guard let edge = edgeEntities[coedge.edgeID] else {
                        throw exchangeError(.missingReference, "STEP loop edge is missing.")
                    }
                    let orientation = coedge.orientation == .forward ? ".T." : ".F."
                    return try table.add("ORIENTED_EDGE('',*,*,#\(edge),\(orientation))")
                }
                let loopEntity = try table.add(
                    "EDGE_LOOP('',(\(orientedEdges.map { "#\($0)" }.joined(separator: ","))))"
                )
                let boundType = loop.role == .outer ? "FACE_OUTER_BOUND" : "FACE_BOUND"
                bounds.append(try table.add("\(boundType)('',#\(loopEntity),.T.)"))
            }
            let orientation = face.orientation == .forward ? ".T." : ".F."
            faceEntities[faceID] = try table.add(
                "ADVANCED_FACE('',(\(bounds.map { "#\($0)" }.joined(separator: ","))),#\(surface),\(orientation))"
            )
        }
        var representationItems: [Int] = []
        for bodyID in brep.bodies.keys.sorted() {
            guard let body = brep.bodies[bodyID] else {
                throw exchangeError(.missingReference, "STEP body is missing.")
            }
            var shellEntities: [Int] = []
            for shellID in body.shellIDs {
                guard let shell = brep.shells[shellID] else {
                    throw exchangeError(.missingReference, "STEP shell is missing.")
                }
                let faces = try shell.faceIDs.map { faceID -> String in
                    guard let entity = faceEntities[faceID] else {
                        throw exchangeError(.missingReference, "STEP shell face is missing.")
                    }
                    return "#\(entity)"
                }
                let shellType = body.kind == .solid ? "CLOSED_SHELL" : "OPEN_SHELL"
                let shellEntity = try table.add("\(shellType)('',(\(faces.joined(separator: ","))))")
                shellEntities.append(shellEntity)
            }
            if body.kind == .solid {
                let orientedShells = try zip(body.shellIDs, shellEntities).map { pair in
                    let (shellID, entity) = pair
                    guard let shell = brep.shells[shellID] else {
                        throw exchangeError(.missingReference, "STEP solid shell is missing.")
                    }
                    return (orientation: shell.orientation, entity: entity)
                }
                let outerShells = orientedShells.filter { $0.orientation == .forward }
                let voidShells = orientedShells.filter { $0.orientation == .reversed }
                guard outerShells.count == 1, let outer = outerShells.first else {
                    throw exchangeError(
                        .unsupportedCapability,
                        "STEP exact solids require one forward outer shell and zero or more reversed void shells."
                    )
                }
                if voidShells.isEmpty {
                    representationItems.append(try table.add(
                        "MANIFOLD_SOLID_BREP('',#\(outer.entity))"
                    ))
                } else {
                    let orientedVoids = try voidShells.map { shell in
                        try table.add(
                            "ORIENTED_CLOSED_SHELL('',*,#\(shell.entity),.F.)"
                        )
                    }
                    representationItems.append(try table.add(
                        "BREP_WITH_VOIDS('',#\(outer.entity),(\(orientedVoids.map { "#\($0)" }.joined(separator: ","))))"
                    ))
                }
            } else {
                representationItems.append(try table.add(
                    "SHELL_BASED_SURFACE_MODEL('',(\(shellEntities.map { "#\($0)" }.joined(separator: ","))))"
                ))
            }
        }
        let representation = try table.add(
            "SHAPE_REPRESENTATION('',(\(representationItems.map { "#\($0)" }.joined(separator: ","))),#\(context))"
        )
        _ = try table.add("SHAPE_DEFINITION_REPRESENTATION(#\(definitionShape),#\(representation))")
        let timestamp = "2000-01-01T00:00:00"
        let text = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('SwiftCAD exact B-rep'),'2;1');
        FILE_NAME('swiftcad.step','\(timestamp)',(''),(''),'swift-CAD','','');
        FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
        ENDSEC;
        DATA;
        \(table.serialized())
        ENDSEC;
        END-ISO-10303-21;
        """
        let data = Data(text.utf8)
        guard data.count <= resourceLimits.maximumBytes else {
            throw exchangeError(.resourceLimitExceeded, "STEP output exceeds the configured byte limit.")
        }
        try data.withUnsafeBytes { bytes in
            try sink.write(bytes)
        }
    }

    private func pcurveEntity(
        parameterCurve: SurfaceParameterCurve,
        parameterCurveFollowsModel: Bool,
        modelStart: Point3D,
        modelEnd: Point3D,
        surface: Surface3D,
        surfaceEntity: Int,
        units: LengthUnit,
        parameterContext: Int,
        table: inout EntityTable
    ) throws -> SurfaceCurveAssociation {
        let directedCurve = parameterCurveFollowsModel
            ? parameterCurve
            : try parameterCurve.reversed(tolerance: tolerance)
        let origin = try directedCurve.startParameter(tolerance: tolerance)
        let directionPoint = try directedCurve.endParameter(tolerance: tolerance)
        let surfaceStart = try surface.point(
            u: origin.u,
            v: origin.v,
            tolerance: tolerance
        )
        let surfaceEnd = try surface.point(
            u: directionPoint.u,
            v: directionPoint.v,
            tolerance: tolerance
        )
        guard surfaceStart.isApproximatelyEqual(
            to: modelStart,
            tolerance: tolerance.distance
        ), surfaceEnd.isApproximatelyEqual(
            to: modelEnd,
            tolerance: tolerance.distance
        ) else {
            throw exchangeError(
                .topologyFailure,
                "STEP p-curve endpoints disagree with the model-curve direction."
            )
        }

        if try usesModelCurveOnly(directedCurve, on: surface) {
            return SurfaceCurveAssociation(entity: surfaceEntity, isPcurve: false)
        }

        let curveEntity = try parameterCurveEntity(
            directedCurve,
            surface: surface,
            units: units,
            table: &table
        )
        let representation = try table.add(
            "DEFINITIONAL_REPRESENTATION('',(#\(curveEntity)),#\(parameterContext))"
        )
        return SurfaceCurveAssociation(
            entity: try table.add("PCURVE('',#\(surfaceEntity),#\(representation))"),
            isPcurve: true
        )
    }

    private func parameterCurveEntity(
        _ curve: SurfaceParameterCurve,
        surface: Surface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let origin = try curve.startParameter(tolerance: tolerance)
        let directionPoint = try curve.endParameter(tolerance: tolerance)
        switch curve {
        case .affine, .constantU, .constantV:
            return try parameterLineEntity(
                origin: origin,
                end: directionPoint,
                surface: surface,
                units: units,
                table: &table
            )
        case let .polyline(points) where points.count == 2:
            return try parameterLineEntity(
                origin: origin,
                end: directionPoint,
                surface: surface,
                units: units,
                table: &table
            )
        case let .polyline(points):
            return try parameterBSplineEntity(
                ExactPolylineBSplineBuilder(tolerance: tolerance).build(points: points),
                surface: surface,
                units: units,
                table: &table
            )
        case let .bSpline(curve):
            return try parameterBSplineEntity(
                curve,
                surface: surface,
                units: units,
                table: &table
            )
        case let .harmonic(center, cosine, sine, _, _):
            return try parameterEllipseEntity(
                center: center,
                cosine: cosine,
                sine: sine,
                surface: surface,
                units: units,
                table: &table
            )
        case let .projectedAnalytic(projected):
            return try parameterBSplineEntity(
                try ExactProjectedAnalyticPcurveBSplineBuilder().build(
                    projected,
                    tolerance: tolerance
                ),
                surface: surface,
                units: units,
                table: &table
            )
        case let .periodicTranslation(base, uShift, vShift):
            let translated = SurfaceParameterCurve.periodicTranslation(
                base: base,
                uShift: uShift,
                vShift: vShift
            ).materializingPeriodicTranslation()
            if case .periodicTranslation = translated {
                throw exchangeError(
                    .unsupportedCapability,
                    "STEP cannot materialize this translated certificate-backed p-curve."
                )
            }
            return try parameterCurveEntity(
                translated,
                surface: surface,
                units: units,
                table: &table
            )
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair:
            throw exchangeError(
                .unsupportedCapability,
                "STEP p-curve export requires an exact transferable line, polyline, ellipse, or rational B-spline."
            )
        }
    }

    private func usesModelCurveOnly(
        _ curve: SurfaceParameterCurve,
        on surface: Surface3D
    ) throws -> Bool {
        switch curve {
        case let .projectedAnalytic(projected):
            guard case .analytic(.cone) = surface else { return false }
            guard projected.surface == surface else {
                throw exchangeError(
                    .topologyFailure,
                    "STEP projected analytic p-curve support disagrees with its face surface."
                )
            }
            return true
        case .sphericalGreatCircle:
            guard case .analytic(.sphere) = surface else { return false }
            return true
        case let .certifiedAnalyticPair(certified):
            guard certified.intersection.surface(for: certified.role) == surface else {
                throw exchangeError(
                    .topologyFailure,
                    "STEP certified analytic-pair p-curve support disagrees with its face surface."
                )
            }
            return true
        case let .certifiedImplicit(certified):
            return surface == .bSpline(
                certified.role == .first
                    ? certified.intersection.firstSurface
                    : certified.intersection.secondSurface
            )
        case let .certifiedAnalyticImplicit(certified):
            return surface == certified.intersection.analyticSurface
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
            return false
        case let .periodicTranslation(base, _, _):
            return try usesModelCurveOnly(base, on: surface)
        }
    }

    private func parameterLineEntity(
        origin: SurfaceParameter,
        end: SurfaceParameter,
        surface: Surface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let serializedOrigin = ExactSurfaceParameterCodec.encode(origin, on: surface, unit: units)
        let serializedEnd = ExactSurfaceParameterCodec.encode(end, on: surface, unit: units)
        let delta = Vector3D(
            x: serializedEnd.u - serializedOrigin.u,
            y: serializedEnd.v - serializedOrigin.v,
            z: 0.0
        )
        let direction = try delta.normalized(tolerance: tolerance.distance)
        let point2D = try table.add(
            "CARTESIAN_POINT('',(\(number(serializedOrigin.u)),\(number(serializedOrigin.v))))"
        )
        let direction2D = try table.add("DIRECTION('',(\(number(direction.x)),\(number(direction.y))))")
        let vector2D = try table.add("VECTOR('',#\(direction2D),1.)")
        return try table.add("LINE('',#\(point2D),#\(vector2D))")
    }

    private func parameterEllipseEntity(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        surface: Surface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let encodedCenter = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x, v: center.y),
            on: surface,
            unit: units
        )
        let encodedCosinePoint = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x + cosine.x, v: center.y + cosine.y),
            on: surface,
            unit: units
        )
        let encodedSinePoint = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x + sine.x, v: center.y + sine.y),
            on: surface,
            unit: units
        )
        let ellipse = try STEPParameterEllipse(
            center: Point2D(x: encodedCenter.u, y: encodedCenter.v),
            cosine: Point2D(
                x: encodedCosinePoint.u - encodedCenter.u,
                y: encodedCosinePoint.v - encodedCenter.v
            ),
            sine: Point2D(
                x: encodedSinePoint.u - encodedCenter.u,
                y: encodedSinePoint.v - encodedCenter.v
            ),
            tolerance: ExactSurfaceParameterCodec.encodedTolerance(on: surface, unit: units, tolerance: tolerance)
        )
        let point = try table.add(
            "CARTESIAN_POINT('',(\(number(ellipse.center.x)),\(number(ellipse.center.y))))"
        )
        let direction = try table.add(
            "DIRECTION('',(\(number(ellipse.majorDirection.x)),\(number(ellipse.majorDirection.y))))"
        )
        let placement = try table.add("AXIS2_PLACEMENT_2D('',#\(point),#\(direction))")
        return try table.add(
            "ELLIPSE('SWIFTCAD_PCURVE',#\(placement),\(number(ellipse.majorRadius)),\(number(ellipse.minorRadius)))"
        )
    }

    private func parameterBSplineEntity(
        _ curve: BSplineCurve2D,
        surface: Surface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        try curve.validate(tolerance: tolerance)
        var points: [Int] = []
        for point in curve.controlPoints {
            let encoded = ExactSurfaceParameterCodec.encode(
                SurfaceParameter(u: point.x, v: point.y),
                on: surface,
                unit: units
            )
            points.append(try table.add(
                "CARTESIAN_POINT('',(\(number(encoded.u)),\(number(encoded.v))))"
            ))
        }
        let knotData = compressedKnots(curve.knots)
        let entity = "(BOUNDED_CURVE() "
            + "B_SPLINE_CURVE(\(curve.degree),(\(references(points))),.UNSPECIFIED.,.F.,.F.) "
            + "B_SPLINE_CURVE_WITH_KNOTS((\(integers(knotData.multiplicities))),(\(numbers(knotData.values))),.UNSPECIFIED.) "
            + "CURVE() GEOMETRIC_REPRESENTATION_ITEM() "
            + "RATIONAL_B_SPLINE_CURVE((\(numbers(curve.weights)))) REPRESENTATION_ITEM('SWIFTCAD_PCURVE'))"
        return try table.add(entity)
    }

    private func cartesianPoint(
        _ point: Point3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        try table.add(
            "CARTESIAN_POINT('',(\(number(units.fromInternal(point.x))),\(number(units.fromInternal(point.y))),\(number(units.fromInternal(point.z)))))"
        )
    }

    private func directionEntity(
        _ vector: Vector3D,
        table: inout EntityTable
    ) throws -> Int {
        try table.add("DIRECTION('',(\(number(vector.x)),\(number(vector.y)),\(number(vector.z))))")
    }

    private func exactSurfaceEntity(
        _ surface: Surface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        switch surface {
        case let .plane(plane):
            return try planeEntity(plane, units: units, table: &table)
        case let .bSpline(bSpline):
            return try bSplineSurfaceEntity(bSpline, units: units, table: &table)
        case let .cylinder(cylinder):
            return try cylinderEntity(cylinder, units: units, table: &table)
        case let .analytic(analytic):
            return try analyticSurfaceEntity(analytic, units: units, table: &table)
        }
    }

    private func planeEntity(
        _ plane: Plane3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let origin = try cartesianPoint(plane.origin, units: units, table: &table)
        let normal = try directionEntity(plane.normal, table: &table)
        let surface = Surface3D.plane(plane)
        let frame = try surface.differentialGeometry(
            atU: 0.0,
            v: 0.0,
            tolerance: tolerance
        )
        let reference = try directionEntity(frame.tangentU, table: &table)
        let placement = try table.add("AXIS2_PLACEMENT_3D('',#\(origin),#\(normal),#\(reference))")
        return try table.add("PLANE('',#\(placement))")
    }

    private func cylinderEntity(
        _ cylinder: Cylinder3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let reference = try ExactAnalyticFrame.directBasis(for: cylinder.axis, tolerance: tolerance).u
        let placement = try axisPlacementEntity(
            origin: cylinder.origin,
            axis: cylinder.axis,
            reference: reference,
            units: units,
            table: &table
        )
        return try table.add(
            "CYLINDRICAL_SURFACE('',#\(placement),\(number(units.fromInternal(cylinder.radius))))"
        )
    }

    private func analyticSurfaceEntity(
        _ surface: AnalyticSurface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let name = "'SWIFTCAD_ANALYTIC'"
        switch surface {
        case let .plane(origin, normal):
            let reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
            let placement = try axisPlacementEntity(
                origin: origin,
                axis: normal,
                reference: reference,
                units: units,
                table: &table
            )
            return try table.add("PLANE(\(name),#\(placement))")
        case let .cylinder(origin, axis, radius):
            let reference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
            let placement = try axisPlacementEntity(
                origin: origin,
                axis: axis,
                reference: reference,
                units: units,
                table: &table
            )
            return try table.add(
                "CYLINDRICAL_SURFACE(\(name),#\(placement),\(number(units.fromInternal(radius))))"
            )
        case let .cone(apex, axis, halfAngle):
            let reference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
            let placement = try axisPlacementEntity(
                origin: apex,
                axis: axis,
                reference: reference,
                units: units,
                table: &table
            )
            return try table.add(
                "CONICAL_SURFACE(\(name),#\(placement),0.,\(number(halfAngle)))"
            )
        case let .sphere(center, radius):
            let frame = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance)
            let placement = try axisPlacementEntity(
                origin: center,
                axis: .unitZ,
                reference: frame.u,
                units: units,
                table: &table
            )
            return try table.add(
                "SPHERICAL_SURFACE(\(name),#\(placement),\(number(units.fromInternal(radius))))"
            )
        case let .torus(center, axis, majorRadius, minorRadius):
            let reference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
            let placement = try axisPlacementEntity(
                origin: center,
                axis: axis,
                reference: reference,
                units: units,
                table: &table
            )
            return try table.add(
                "TOROIDAL_SURFACE(\(name),#\(placement),\(number(units.fromInternal(majorRadius))),\(number(units.fromInternal(minorRadius))))"
            )
        }
    }

    private func circleEntity(
        _ circle: Circle3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let reference = try ExactAnalyticFrame.directBasis(for: circle.normal, tolerance: tolerance).u
        let placement = try axisPlacementEntity(
            origin: circle.center,
            axis: circle.normal,
            reference: reference,
            units: units,
            table: &table
        )
        return try table.add(
            "CIRCLE('',#\(placement),\(number(units.fromInternal(circle.radius))))"
        )
    }

    private func analyticCurveEntity(
        _ curve: AnalyticCurve3D,
        edge: Edge,
        startPoint: Point3D,
        endPoint: Point3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> (entity: Int, sameSense: Bool) {
        switch curve {
        case let .line(origin, direction):
            let point = try cartesianPoint(origin, units: units, table: &table)
            let directionEntity = try self.directionEntity(direction, table: &table)
            let vector = try table.add("VECTOR('',#\(directionEntity),1.)")
            let signedSpan = (endPoint - startPoint).dot(direction)
            guard abs(signedSpan) > tolerance.distance else {
                throw exchangeError(.topologyFailure, "STEP analytic line direction is inconsistent with its edge.")
            }
            return (
                try table.add("LINE('SWIFTCAD_ANALYTIC',#\(point),#\(vector))"),
                signedSpan > 0.0
            )
        case let .circle(center, normal, radius):
            let trim = try requiredPeriodicTrim(edge, label: "analytic circle")
            let entity = try analyticCircleEntity(
                center: center,
                normal: normal,
                radius: radius,
                name: "SWIFTCAD_ANALYTIC",
                units: units,
                table: &table
            )
            return (entity, trim.endParameter > trim.startParameter)
        case let .arc(center, normal, radius, _, _):
            guard let trim = edge.trim else {
                throw exchangeError(
                    .topologyFailure,
                    "STEP analytic arc requires a finite explicit trim interval."
                )
            }
            let basis = try analyticCircleEntity(
                center: center,
                normal: normal,
                radius: radius,
                name: "SWIFTCAD_ARC_BASIS",
                units: units,
                table: &table
            )
            let sameSense = trim.endParameter > trim.startParameter
            let entity = try table.add(
                "TRIMMED_CURVE('SWIFTCAD_ARC',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(sameSense ? ".T." : ".F."),.PARAMETER.)"
            )
            return (entity, true)
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            let trim = try requiredPeriodicTrim(edge, label: "analytic ellipse")
            let placement = try axisPlacementEntity(
                origin: center,
                axis: normal,
                reference: majorAxis,
                units: units,
                table: &table
            )
            let entity = try table.add(
                "ELLIPSE('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(majorRadius))),\(number(units.fromInternal(minorRadius))))"
            )
            return (entity, trim.endParameter > trim.startParameter)
        case let .hyperbola(curve):
            guard let trim = edge.trim,
                  trim.startParameter.isFinite,
                  trim.endParameter.isFinite,
                  abs(trim.endParameter - trim.startParameter) > tolerance.relative else {
                throw exchangeError(
                    .topologyFailure,
                    "STEP hyperbola edges require a finite nonzero trim."
                )
            }
            let placement = try axisPlacementEntity(
                origin: curve.center,
                axis: curve.normal,
                reference: curve.transverseAxis,
                units: units,
                table: &table
            )
            let entity = try table.add(
                "HYPERBOLA('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(curve.transverseRadius))),\(number(units.fromInternal(curve.conjugateRadius))))"
            )
            return (entity, trim.endParameter > trim.startParameter)
        case let .parabola(curve):
            guard let trim = edge.trim,
                  trim.startParameter.isFinite,
                  trim.endParameter.isFinite,
                  abs(trim.endParameter - trim.startParameter) > tolerance.distance else {
                throw exchangeError(
                    .topologyFailure,
                    "STEP parabola edges require a finite nonzero trim."
                )
            }
            let placement = try axisPlacementEntity(
                origin: curve.vertex,
                axis: curve.normal,
                reference: curve.axis,
                units: units,
                table: &table
            )
            let entity = try table.add(
                "PARABOLA('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(curve.focalLength))))"
            )
            return (entity, trim.endParameter > trim.startParameter)
        case .planeTorus:
            throw exchangeError(
                .unsupportedCapability,
                "STEP certified plane-torus transfer requires an exact surface-curve association writer."
            )
        }
    }

    private func analyticCircleEntity(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        name: String,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        let placement = try axisPlacementEntity(
            origin: center,
            axis: normal,
            reference: reference,
            units: units,
            table: &table
        )
        return try table.add(
            "CIRCLE('\(name)',#\(placement),\(number(units.fromInternal(radius))))"
        )
    }

    private func requiredPeriodicTrim(_ edge: Edge, label: String) throws -> CurveTrim {
        guard let trim = edge.trim,
              trim.startParameter.isFinite,
              trim.endParameter.isFinite,
              abs(trim.endParameter - trim.startParameter) > tolerance.angle,
              abs(trim.endParameter - trim.startParameter)
                < 2.0 * Double.pi - tolerance.angle else {
            throw exchangeError(
                .topologyFailure,
                "STEP \(label) edge requires a finite trim shorter than one period."
            )
        }
        return trim
    }

    private func axisPlacementEntity(
        origin: Point3D,
        axis: Vector3D,
        reference: Vector3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let point = try cartesianPoint(origin, units: units, table: &table)
        let axisEntity = try directionEntity(axis, table: &table)
        let referenceEntity = try directionEntity(reference, table: &table)
        return try table.add(
            "AXIS2_PLACEMENT_3D('',#\(point),#\(axisEntity),#\(referenceEntity))"
        )
    }

    private func bSplineCurveEntity(
        _ curve: BSplineCurve3D,
        name: String = "",
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        var points: [Int] = []
        for point in curve.controlPoints {
            points.append(try cartesianPoint(point, units: units, table: &table))
        }
        let knotData = compressedKnots(curve.knots)
        let entity = "(BOUNDED_CURVE() "
            + "B_SPLINE_CURVE(\(curve.degree),(\(references(points))),.UNSPECIFIED.,.F.,.F.) "
            + "B_SPLINE_CURVE_WITH_KNOTS((\(integers(knotData.multiplicities))),(\(numbers(knotData.values))),.UNSPECIFIED.) "
            + "CURVE() GEOMETRIC_REPRESENTATION_ITEM() "
            + "RATIONAL_B_SPLINE_CURVE((\(numbers(curve.weights)))) REPRESENTATION_ITEM('\(name)'))"
        return try table.add(entity)
    }

    private func bSplineSurfaceEntity(
        _ surface: BSplineSurface3D,
        units: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        var pointRows: [[Int]] = []
        for row in surface.controlPoints {
            var pointRow: [Int] = []
            for point in row {
                pointRow.append(try cartesianPoint(point, units: units, table: &table))
            }
            pointRows.append(pointRow)
        }
        let uKnots = compressedKnots(surface.uKnots)
        let vKnots = compressedKnots(surface.vKnots)
        let controlNet = pointRows.map { "(\(references($0)))" }.joined(separator: ",")
        let weightNet = surface.weights.map { "(\(numbers($0)))" }.joined(separator: ",")
        let entity = "(BOUNDED_SURFACE() "
            + "B_SPLINE_SURFACE(\(surface.uDegree),\(surface.vDegree),(\(controlNet)),.UNSPECIFIED.,.F.,.F.,.F.) "
            + "B_SPLINE_SURFACE_WITH_KNOTS((\(integers(uKnots.multiplicities))),(\(integers(vKnots.multiplicities))),(\(numbers(uKnots.values))),(\(numbers(vKnots.values))),.UNSPECIFIED.) "
            + "GEOMETRIC_REPRESENTATION_ITEM() "
            + "RATIONAL_B_SPLINE_SURFACE((\(weightNet))) REPRESENTATION_ITEM('') SURFACE())"
        return try table.add(entity)
    }

    private func compressedKnots(_ knots: [Double]) -> (values: [Double], multiplicities: [Int]) {
        var values: [Double] = []
        var multiplicities: [Int] = []
        for knot in knots {
            if let last = values.last, last == knot {
                multiplicities[multiplicities.count - 1] += 1
            } else {
                values.append(knot)
                multiplicities.append(1)
            }
        }
        return (values, multiplicities)
    }

    private func references(_ values: [Int]) -> String {
        values.map { "#\($0)" }.joined(separator: ",")
    }

    private func integers(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ",")
    }

    private func numbers(_ values: [Double]) -> String {
        values.map(number).joined(separator: ",")
    }

    private func lengthUnitEntity(
        _ unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        switch unit {
        case .micrometer:
            return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MICRO.,.METRE.))")
        case .meter:
            return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
        case .millimeter:
            return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))")
        case .centimeter:
            return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.CENTI.,.METRE.))")
        case .kilometer:
            return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.METRE.))")
        case .inch, .foot:
            let dimensions = try table.add("DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.)")
            let metre = try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
            let measure = try table.add(
                "LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(number(unit.metersPerUnit))),#\(metre))"
            )
            let name = unit == .inch ? "INCH" : "FOOT"
            return try table.add(
                "(CONVERSION_BASED_UNIT('\(name)',#\(measure)) LENGTH_UNIT() NAMED_UNIT(#\(dimensions)))"
            )
        }
    }

    private func number(_ value: Double) -> String {
        String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func exchangeError(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .exchange, code: code, tolerance: tolerance, message: message)
    }

    private struct SurfaceCurveAssociation: Hashable {
        let entity: Int
        let isPcurve: Bool
    }

    private struct EntityTable {
        let maximumEntities: Int
        let tolerance: ModelingTolerance
        var entities: [String] = []

        mutating func add(_ entity: String) throws -> Int {
            guard entities.count < maximumEntities else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "STEP output exceeds the configured entity limit."
                )
            }
            entities.append(entity)
            return entities.count
        }

        func serialized() -> String {
            entities.enumerated().map { index, entity in
                "#\(index + 1)=\(entity);"
            }.joined(separator: "\n")
        }
    }
}
