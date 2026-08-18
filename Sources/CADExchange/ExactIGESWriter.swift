import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct ExactIGESWriter {
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
        var curvePointers: [EdgeID: Int] = [:]
        var edgeSameSense: [EdgeID: Bool] = [:]
        var surfaceLiftEdges: Set<EdgeID> = []
        for edgeID in brep.edges.keys.sorted() {
            guard let edge = brep.edges[edgeID],
                  let start = brep.vertices[edge.startVertexID]?.point,
                  let end = brep.vertices[edge.endVertexID]?.point,
                  let curve = brep.geometry.curves[edge.curveID] else {
                throw exchangeError(.missingReference, "IGES edge geometry is incomplete.")
            }
            switch curve {
            case let .line(line):
                let signedSpan = (end - start).dot(line.direction)
                guard abs(signedSpan) > tolerance.distance else {
                    throw exchangeError(.topologyFailure, "IGES edge curve direction is inconsistent with its vertices.")
                }
                edgeSameSense[edgeID] = signedSpan > 0.0
                curvePointers[edgeID] = try table.add(
                    type: 110,
                    form: 0,
                    label: "CURVE",
                    parameters: lineParameters(start: start, end: end, unit: units.length)
                )
            case let .bSpline(bSpline):
                guard let trim = edge.trim else {
                    throw exchangeError(.topologyFailure, "IGES B-spline edge requires an explicit trim interval.")
                }
                edgeSameSense[edgeID] = true
                curvePointers[edgeID] = try table.add(
                    type: 126,
                    form: 0,
                    label: "NURBSCRV",
                    parameters: bSplineCurveParameters(
                        bSpline,
                        startParameter: trim.startParameter,
                        endParameter: trim.endParameter,
                        unit: units.length
                    )
                )
            case let .circle(circle):
                let trim = try requiredPeriodicTrim(edge, label: "circle")
                let sameSense = trim.endParameter > trim.startParameter
                edgeSameSense[edgeID] = sameSense
                let basis = try ExactAnalyticFrame.directBasis(for: circle.normal, tolerance: tolerance)
                curvePointers[edgeID] = try circularArcEntity(
                    center: circle.center,
                    normal: circle.normal,
                    reference: basis.u,
                    label: "CIRCARC",
                    modelStart: sameSense ? start : end,
                    modelEnd: sameSense ? end : start,
                    unit: units.length,
                    table: &table
                )
            case let .analytic(analytic):
                if case let .planeTorus(planeTorus) = analytic {
                    guard let trim = edge.trim else {
                        throw exchangeError(
                            .topologyFailure,
                            "IGES plane-torus intersection edges require an explicit trim."
                        )
                    }
                    let transfer = try ExactPlaneTorusTransferBuilder().build(
                        curve: planeTorus,
                        trim: trim,
                        tolerance: tolerance
                    )
                    guard case let .closed(lower, upper) = transfer.curve.domain else {
                        throw exchangeError(
                            .topologyFailure,
                            "IGES plane-torus transfer produced an unbounded derived curve."
                        )
                    }
                    let modelCurve = try table.add(
                        type: 126,
                        form: 0,
                        label: "INTMODEL",
                        parameters: bSplineCurveParameters(
                            transfer.curve,
                            startParameter: lower,
                            endParameter: upper,
                            unit: units.length
                        )
                    )
                    let planeSurface = try exactSurfaceEntity(
                        planeTorus.planeSurface,
                        unit: units.length,
                        table: &table
                    )
                    let torusSurface = try exactSurfaceEntity(
                        planeTorus.torusSurface,
                        unit: units.length,
                        table: &table
                    )
                    guard case let .bSpline(planePcurve) = transfer.planePcurve,
                          case let .bSpline(torusPcurve) = transfer.torusPcurve else {
                        throw exchangeError(
                            .topologyFailure,
                            "IGES plane-torus transfer requires verified rational p-curves."
                        )
                    }
                    let planeParameterCurve = try parameterBSplineEntity(
                        planePcurve,
                        surface: planeTorus.planeSurface,
                        unit: units.length,
                        table: &table
                    )
                    let torusParameterCurve = try parameterBSplineEntity(
                        torusPcurve,
                        surface: planeTorus.torusSurface,
                        unit: units.length,
                        table: &table
                    )
                    let torusCurveOnSurface = try table.add(
                        type: 142,
                        form: 0,
                        label: "INTTORUS",
                        parameters: "142,1,\(torusSurface),\(torusParameterCurve),\(modelCurve),3;"
                    )
                    curvePointers[edgeID] = try table.add(
                        type: 142,
                        form: 0,
                        label: "INTPLANE",
                        parameters: "142,1,\(planeSurface),\(planeParameterCurve),\(torusCurveOnSurface),3;"
                    )
                    edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
                } else {
                    let result = try analyticCurveEntity(
                        analytic,
                        edge: edge,
                        start: start,
                        end: end,
                        unit: units.length,
                        table: &table
                    )
                    edgeSameSense[edgeID] = result.sameSense
                    curvePointers[edgeID] = result.pointer
                }
            case let .implicit(implicit):
                guard let trim = edge.trim else {
                    throw exchangeError(
                        .topologyFailure,
                        "IGES implicit intersection edges require an explicit trim."
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
                        "IGES implicit intersection pcurve provenance disagrees with its model curve."
                    )
                }
                let transfer = try ExactImplicitIntersectionTransferBuilder().build(
                    source: source,
                    trim: trim,
                    tolerance: tolerance
                )
                guard case let .closed(lower, upper) = transfer.curve.domain,
                      case let .bSpline(firstPcurve) = transfer.firstPcurve,
                      case let .bSpline(secondPcurve) = transfer.secondPcurve else {
                    throw exchangeError(
                        .topologyFailure,
                        "IGES implicit intersection transfer requires finite verified rational splines."
                    )
                }
                let modelCurve = try table.add(
                    type: 126,
                    form: 0,
                    label: "INTMODEL",
                    parameters: bSplineCurveParameters(
                        transfer.curve,
                        startParameter: lower,
                        endParameter: upper,
                        unit: units.length
                    )
                )
                let firstSurface = try exactSurfaceEntity(
                    source.firstSurface,
                    unit: units.length,
                    table: &table
                )
                let secondSurface = try exactSurfaceEntity(
                    source.secondSurface,
                    unit: units.length,
                    table: &table
                )
                let firstParameterCurve = try parameterBSplineEntity(
                    firstPcurve,
                    surface: source.firstSurface,
                    unit: units.length,
                    table: &table
                )
                let secondParameterCurve = try parameterBSplineEntity(
                    secondPcurve,
                    surface: source.secondSurface,
                    unit: units.length,
                    table: &table
                )
                let secondCurveOnSurface = try table.add(
                    type: 142,
                    form: 0,
                    label: "INTSECOND",
                    parameters: "142,1,\(secondSurface),\(secondParameterCurve),\(modelCurve),3;"
                )
                curvePointers[edgeID] = try table.add(
                    type: 142,
                    form: 0,
                    label: "INTFIRST",
                    parameters: "142,1,\(firstSurface),\(firstParameterCurve),\(secondCurveOnSurface),3;"
                )
                edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
            case let .surfaceLift(lift):
                guard let trim = edge.trim else {
                    throw exchangeError(
                        .topologyFailure,
                        "IGES surface-lift edges require an explicit normalized trim."
                    )
                }
                let transfer = try ExactSurfaceLiftTransferBuilder().build(
                    lift: lift,
                    trim: trim,
                    tolerance: tolerance
                )
                guard case let .closed(lower, upper) = transfer.curve.domain else {
                    throw exchangeError(
                        .topologyFailure,
                        "IGES surface-lift transfer produced an unbounded derived curve."
                    )
                }
                let modelCurve = try table.add(
                    type: 126,
                    form: 0,
                    label: "LIFTMODEL",
                    parameters: bSplineCurveParameters(
                        transfer.curve,
                        startParameter: lower,
                        endParameter: upper,
                        unit: units.length
                    )
                )
                let sourceSurface = try exactSurfaceEntity(
                    lift.surface,
                    unit: units.length,
                    table: &table
                )
                let sourceParameterCurve = try parameterCurveEntity(
                    transfer.parameterCurve,
                    surface: lift.surface,
                    unit: units.length,
                    table: &table
                )
                curvePointers[edgeID] = try table.add(
                    type: 142,
                    form: 0,
                    label: "SURFLIFT",
                    parameters: "142,1,\(sourceSurface),\(sourceParameterCurve),\(modelCurve),3;"
                )
                edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
                surfaceLiftEdges.insert(edgeID)
            case .certifiedIntersection:
                throw exchangeError(
                    .unsupportedCapability,
                    "IGES export of certified intersection curves requires an exact transfer representation."
                )
            }
        }

        var surfacePointers: [SurfaceID: Int] = [:]
        for faceID in brep.faces.keys.sorted() {
            guard let face = brep.faces[faceID],
                  let surface = brep.geometry.surfaces[face.surfaceID] else {
                throw exchangeError(.missingReference, "IGES face surface is missing.")
            }
            if surfacePointers[face.surfaceID] == nil {
                switch surface {
                case let .plane(plane):
                    let point = try table.add(
                        type: 116,
                        form: 0,
                        label: "ORIGIN",
                        parameters: pointParameters(plane.origin, unit: units.length)
                    )
                    let normal = try table.add(
                        type: 123,
                        form: 0,
                        label: "NORMAL",
                        parameters: directionParameters(plane.normal)
                    )
                    let frame = try surface.differentialGeometry(
                        atU: 0.0,
                        v: 0.0,
                        tolerance: tolerance
                    )
                    let reference = try table.add(
                        type: 123,
                        form: 0,
                        label: "REFDIR",
                        parameters: directionParameters(frame.tangentU)
                    )
                    surfacePointers[face.surfaceID] = try table.add(
                        type: 190,
                        form: 1,
                        label: "PLANE",
                        parameters: "190,\(point),\(normal),\(reference);"
                    )
                case let .bSpline(bSpline):
                    surfacePointers[face.surfaceID] = try table.add(
                        type: 128,
                        form: 0,
                        label: "NURBSSRF",
                        parameters: bSplineSurfaceParameters(bSpline, unit: units.length)
                    )
                case let .cylinder(cylinder):
                    let point = try table.add(
                        type: 116,
                        form: 0,
                        label: "ORIGIN",
                        parameters: pointParameters(cylinder.origin, unit: units.length)
                    )
                    let axis = try table.add(
                        type: 123,
                        form: 0,
                        label: "AXIS",
                        parameters: directionParameters(cylinder.axis)
                    )
                    let frame = try surface.differentialGeometry(
                        atU: 0.0,
                        v: 0.0,
                        tolerance: tolerance
                    )
                    let reference = try table.add(
                        type: 123,
                        form: 0,
                        label: "REFDIR",
                        parameters: directionParameters(frame.normal)
                    )
                    surfacePointers[face.surfaceID] = try table.add(
                        type: 192,
                        form: 1,
                        label: "CYLINDER",
                        parameters: "192,\(point),\(axis),\(number(units.length.fromInternal(cylinder.radius))),\(reference);"
                    )
                case let .analytic(analytic):
                    surfacePointers[face.surfaceID] = try analyticSurfaceEntity(
                        analytic,
                        unit: units.length,
                        table: &table
                    )
                }
            }
        }

        let vertexIDs = brep.vertices.keys.sorted()
        var vertexIndices: [VertexID: Int] = [:]
        var vertexParameters = ["502", "\(vertexIDs.count)"]
        for (offset, vertexID) in vertexIDs.enumerated() {
            guard let vertex = brep.vertices[vertexID] else {
                throw exchangeError(.missingReference, "IGES vertex is missing.")
            }
            vertexIndices[vertexID] = offset + 1
            vertexParameters.append(contentsOf: coordinates(vertex.point, unit: units.length))
        }
        let vertexListPointer = try table.add(
            type: 502,
            form: 1,
            label: "VERTICES",
            parameters: vertexParameters.joined(separator: ",") + ";"
        )

        let edgeIDs = brep.edges.keys.sorted()
        var edgeIndices: [EdgeID: Int] = [:]
        var edgeParameters = ["504", "\(edgeIDs.count)"]
        for (offset, edgeID) in edgeIDs.enumerated() {
            guard let edge = brep.edges[edgeID],
                  let curvePointer = curvePointers[edgeID],
                  let startIndex = vertexIndices[edge.startVertexID],
                  let endIndex = vertexIndices[edge.endVertexID] else {
                throw exchangeError(.missingReference, "IGES edge topology is incomplete.")
            }
            edgeIndices[edgeID] = offset + 1
            edgeParameters.append(contentsOf: [
                "\(curvePointer)",
                "\(vertexListPointer)",
                "\(startIndex)",
                "\(vertexListPointer)",
                "\(endIndex)",
            ])
        }
        let edgeListPointer = try table.add(
            type: 504,
            form: 1,
            label: "EDGES",
            parameters: edgeParameters.joined(separator: ",") + ";"
        )

        var loopPointers: [LoopID: Int] = [:]
        for faceID in brep.faces.keys.sorted() {
            guard let face = brep.faces[faceID],
                  let surface = brep.geometry.surfaces[face.surfaceID] else {
                throw exchangeError(.missingReference, "IGES face surface is missing.")
            }
            for loopID in face.loops {
                guard let loop = brep.loops[loopID] else {
                    throw exchangeError(.missingReference, "IGES loop is missing.")
                }
                var parameters = ["508", "\(loop.coedges.count)"]
                for coedge in loop.coedges {
                    guard let parameterCurve = coedge.surfaceParameterCurve,
                          let edge = brep.edges[coedge.edgeID],
                          let edgeIndex = edgeIndices[coedge.edgeID],
                          let sameSense = edgeSameSense[coedge.edgeID],
                          let start = brep.vertices[edge.startVertexID]?.point,
                          let end = brep.vertices[edge.endVertexID]?.point else {
                        throw exchangeError(.topologyFailure, "IGES coedge topology or p-curve is incomplete.")
                    }
                    let modelStart = sameSense ? start : end
                    let modelEnd = sameSense ? end : start
                    let coedgeAgreesWithModelCurve = (coedge.orientation == .forward) == sameSense
                    let directedCurve = coedgeAgreesWithModelCurve
                        ? parameterCurve
                        : try parameterCurve.reversed(tolerance: tolerance)
                    let startUV = try directedCurve.startParameter(tolerance: tolerance)
                    let endUV = try directedCurve.endParameter(tolerance: tolerance)
                    let reconstructedStart = try surface.point(
                        u: startUV.u,
                        v: startUV.v,
                        tolerance: tolerance
                    )
                    let reconstructedEnd = try surface.point(
                        u: endUV.u,
                        v: endUV.v,
                        tolerance: tolerance
                    )
                    guard reconstructedStart.isApproximatelyEqual(
                        to: modelStart,
                        tolerance: tolerance.distance
                    ), reconstructedEnd.isApproximatelyEqual(
                        to: modelEnd,
                        tolerance: tolerance.distance
                    ) else {
                        throw exchangeError(
                            .topologyFailure,
                            "IGES p-curve endpoints disagree with the model-curve direction."
                        )
                    }
                    if surfaceLiftEdges.contains(coedge.edgeID) || usesModelCurveOnly(
                        directedCurve,
                        on: surface
                    ) {
                        parameters.append(contentsOf: [
                            "0",
                            "\(edgeListPointer)",
                            "\(edgeIndex)",
                            boolean(coedgeAgreesWithModelCurve),
                            "0",
                        ])
                        continue
                    }
                    let pcurvePointer = try parameterCurveEntity(
                        directedCurve,
                        surface: surface,
                        unit: units.length,
                        table: &table
                    )
                    parameters.append(contentsOf: [
                        "0",
                        "\(edgeListPointer)",
                        "\(edgeIndex)",
                        boolean(coedgeAgreesWithModelCurve),
                        "1",
                        boolean(false),
                        "\(pcurvePointer)",
                    ])
                }
                loopPointers[loopID] = try table.add(
                    type: 508,
                    form: 1,
                    label: "LOOP",
                    parameters: parameters.joined(separator: ",") + ";"
                )
            }
        }

        var facePointers: [FaceID: Int] = [:]
        for faceID in brep.faces.keys.sorted() {
            guard let face = brep.faces[faceID],
                  let surfacePointer = surfacePointers[face.surfaceID] else {
                throw exchangeError(.missingReference, "IGES face is incomplete.")
            }
            let orderedLoops = face.loops.sorted { lhs, rhs in
                (brep.loops[lhs]?.role == .outer ? 0 : 1) < (brep.loops[rhs]?.role == .outer ? 0 : 1)
            }
            guard orderedLoops.first.flatMap({ brep.loops[$0] })?.role == .outer else {
                throw exchangeError(.topologyFailure, "IGES face requires one outer loop.")
            }
            let pointers = try orderedLoops.map { loopID -> String in
                guard let pointer = loopPointers[loopID] else {
                    throw exchangeError(.missingReference, "IGES face loop is missing.")
                }
                return "\(pointer)"
            }
            facePointers[faceID] = try table.add(
                type: 510,
                form: 1,
                label: "FACE",
                parameters: (["510", "\(surfacePointer)", "\(pointers.count)", boolean(true)] + pointers)
                    .joined(separator: ",") + ";"
            )
        }

        let groupedSheetShellIDs = Set(brep.bodies.values.flatMap { body in
            body.kind == .sheet && body.shellIDs.count > 1 ? body.shellIDs : []
        })
        var shellPointers: [ShellID: Int] = [:]
        for shellID in brep.shells.keys.sorted() {
            guard let shell = brep.shells[shellID] else {
                throw exchangeError(.missingReference, "IGES shell is missing.")
            }
            var parameters = ["514", "\(shell.faceIDs.count)"]
            for faceID in shell.faceIDs {
                guard let face = brep.faces[faceID], let pointer = facePointers[faceID] else {
                    throw exchangeError(.missingReference, "IGES shell face is missing.")
                }
                parameters.append("\(pointer)")
                parameters.append(boolean(face.orientation == .forward))
            }
            shellPointers[shellID] = try table.add(
                type: 514,
                form: 1,
                label: "SHELL",
                statusNumber: groupedSheetShellIDs.contains(shellID) ? 20_000 : 0,
                parameters: parameters.joined(separator: ",") + ";"
            )
        }

        for bodyID in brep.bodies.keys.sorted() {
            guard let body = brep.bodies[bodyID] else {
                throw exchangeError(.missingReference, "IGES body is missing.")
            }
            if body.kind == .sheet {
                if body.shellIDs.count > 1 {
                    let pointers = try body.shellIDs.sorted().map { shellID -> String in
                        guard let pointer = shellPointers[shellID] else {
                            throw exchangeError(.missingReference, "IGES sheet body shell is missing.")
                        }
                        return "\(pointer)"
                    }
                    _ = try table.add(
                        type: 402,
                        form: 7,
                        label: "SHEETBDY",
                        statusNumber: 300,
                        parameters: (["402", "\(pointers.count)"] + pointers)
                            .joined(separator: ",") + ";"
                    )
                }
                continue
            }
            let components = try brep.solidShellComponents(
                for: bodyID,
                tolerance: tolerance
            )
            for component in components {
                guard let outerPointer = shellPointers[component.outerShellID] else {
                    throw exchangeError(.missingReference, "IGES solid outer shell is missing.")
                }
                var parameters = [
                    "186",
                    "\(outerPointer)",
                    boolean(true),
                    "\(component.voidShellIDs.count)",
                ]
                for voidShellID in component.voidShellIDs {
                    guard let pointer = shellPointers[voidShellID] else {
                        throw exchangeError(.missingReference, "IGES solid void shell is missing.")
                    }
                    parameters.append("\(pointer)")
                    parameters.append(boolean(false))
                }
                _ = try table.add(
                    type: 186,
                    form: 0,
                    label: "SOLID",
                    parameters: parameters.joined(separator: ",") + ";"
                )
            }
        }

        let data = try table.serialize(unit: units.length, maximumBytes: resourceLimits.maximumBytes)
        try data.withUnsafeBytes { bytes in
            try sink.write(bytes)
        }
    }

    private func lineParameters(start: Point3D, end: Point3D, unit: LengthUnit) -> String {
        (["110"] + coordinates(start, unit: unit) + coordinates(end, unit: unit)).joined(separator: ",") + ";"
    }

    private func isLinear(_ curve: SurfaceParameterCurve) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV:
            true
        case let .polyline(points):
            points.count == 2
        case let .bSpline(curve):
            curve.degree == 1 && curve.controlPointCount == 2
        case .harmonic, .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            false
        case let .periodicTranslation(base, _, _):
            isLinear(base)
        }
    }

    private func usesModelCurveOnly(
        _ curve: SurfaceParameterCurve,
        on surface: Surface3D
    ) -> Bool {
        switch curve {
        case let .projectedAnalytic(projected):
            guard case .analytic(.cone) = surface else { return false }
            return projected.surface == surface
        case .sphericalGreatCircle:
            guard case .analytic(.sphere) = surface else { return false }
            return true
        case let .certifiedAnalyticPair(certified):
            return certified.intersection.surface(for: certified.role) == surface
        case let .certifiedImplicit(certified):
            let source = certified.role == .first
                ? certified.intersection.firstSurface
                : certified.intersection.secondSurface
            return surface == .bSpline(source)
        case let .certifiedAnalyticImplicit(certified):
            return certified.intersection.analyticSurface == surface
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
            return false
        case let .periodicTranslation(base, _, _):
            return usesModelCurveOnly(base, on: surface)
        }
    }

    private func line2DParameters(
        startU: Double,
        startV: Double,
        endU: Double,
        endV: Double
    ) -> String {
        [
            "110",
            number(startU),
            number(startV),
            "0",
            number(endU),
            number(endV),
            "0",
        ].joined(separator: ",") + ";"
    }

    private func parameterCurveEntity(
        _ curve: SurfaceParameterCurve,
        surface: Surface3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let start = try curve.startParameter(tolerance: tolerance)
        let end = try curve.endParameter(tolerance: tolerance)
        let encodedStart = ExactSurfaceParameterCodec.encode(
            start,
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedEnd = ExactSurfaceParameterCodec.encode(
            end,
            on: surface,
            unit: unit,
            convention: .iges
        )
        if isLinear(curve) {
            return try table.add(
                type: 110,
                form: 0,
                label: "PCURVE",
                parameters: line2DParameters(
                    startU: encodedStart.u,
                    startV: encodedStart.v,
                    endU: encodedEnd.u,
                    endV: encodedEnd.v
                )
            )
        }
        switch curve {
        case let .bSpline(bSpline):
            return try parameterBSplineEntity(
                bSpline,
                surface: surface,
                unit: unit,
                table: &table
            )
        case let .polyline(points):
            return try parameterBSplineEntity(
                ExactPolylineBSplineBuilder(tolerance: tolerance).build(points: points),
                surface: surface,
                unit: unit,
                table: &table
            )
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return try parameterHarmonicEntity(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter,
                encodedStart: encodedStart,
                encodedEnd: encodedEnd,
                surface: surface,
                unit: unit,
                table: &table
            )
        case let .projectedAnalytic(projected):
            return try parameterBSplineEntity(
                try ExactProjectedAnalyticPcurveBSplineBuilder().build(
                    projected,
                    tolerance: tolerance
                ),
                surface: surface,
                unit: unit,
                table: &table
            )
        case .periodicTranslation:
            let translated = curve.materializingPeriodicTranslation()
            if case .periodicTranslation = translated {
                throw exchangeError(
                    .unsupportedCapability,
                    "IGES cannot materialize this translated certificate-backed p-curve."
                )
            }
            return try parameterCurveEntity(
                translated,
                surface: surface,
                unit: unit,
                table: &table
            )
        case .affine, .constantU, .constantV:
            throw exchangeError(
                .topologyFailure,
                "IGES linear pcurve dispatch failed to recognize a linear curve."
            )
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair:
            throw exchangeError(
                .unsupportedCapability,
                "IGES pcurve export requires an exact transferable line, polyline, ellipse, or rational B-spline."
            )
        }
    }

    private func parameterHarmonicEntity(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double,
        encodedStart: SurfaceParameter,
        encodedEnd: SurfaceParameter,
        surface: Surface3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let encodedCenter = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x, v: center.y),
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedCosinePoint = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x + cosine.x, v: center.y + cosine.y),
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedSinePoint = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x + sine.x, v: center.y + sine.y),
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedCosine = Point2D(
            x: encodedCosinePoint.u - encodedCenter.u,
            y: encodedCosinePoint.v - encodedCenter.v
        )
        let encodedSine = Point2D(
            x: encodedSinePoint.u - encodedCenter.u,
            y: encodedSinePoint.v - encodedCenter.v
        )
        let signedOrientation = (
            encodedCosine.x * encodedSine.y - encodedCosine.y * encodedSine.x
        ) * (endParameter - startParameter)
        if signedOrientation > 0.0 {
            return try parameterEllipseEntity(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter,
                encodedStart: encodedStart,
                encodedEnd: encodedEnd,
                surface: surface,
                unit: unit,
                table: &table
            )
        }

        let curve = try ExactHarmonicArcBSplineBuilder(tolerance: tolerance).build(
            center: center,
            cosine: cosine,
            sine: sine,
            startParameter: startParameter,
            endParameter: endParameter
        )
        return try parameterBSplineEntity(
            curve,
            surface: surface,
            unit: unit,
            table: &table
        )
    }

    private func parameterEllipseEntity(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double,
        encodedStart: SurfaceParameter,
        encodedEnd: SurfaceParameter,
        surface: Surface3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let encodedCenter = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x, v: center.y),
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedCosinePoint = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x + cosine.x, v: center.y + cosine.y),
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedSinePoint = ExactSurfaceParameterCodec.encode(
            SurfaceParameter(u: center.x + sine.x, v: center.y + sine.y),
            on: surface,
            unit: unit,
            convention: .iges
        )
        let encodedCosine = Point2D(
            x: encodedCosinePoint.u - encodedCenter.u,
            y: encodedCosinePoint.v - encodedCenter.v
        )
        let encodedSine = Point2D(
            x: encodedSinePoint.u - encodedCenter.u,
            y: encodedSinePoint.v - encodedCenter.v
        )
        guard (encodedCosine.x * encodedSine.y - encodedCosine.y * encodedSine.x)
                * (endParameter - startParameter) > 0.0 else {
            throw exchangeError(
                .unsupportedCapability,
                "IGES type 104 p-curves require counterclockwise model-curve parameterization."
            )
        }
        let ellipse = try STEPParameterEllipse(
            center: Point2D(x: encodedCenter.u, y: encodedCenter.v),
            cosine: encodedCosine,
            sine: encodedSine,
            tolerance: ExactSurfaceParameterCodec.encodedTolerance(on: surface, unit: unit, tolerance: tolerance)
        )
        let x = ellipse.majorDirection
        let y = Point2D(x: -x.y, y: x.x)
        let inverseMajorSquared = 1.0 / (ellipse.majorRadius * ellipse.majorRadius)
        let inverseMinorSquared = 1.0 / (ellipse.minorRadius * ellipse.minorRadius)
        let a = x.x * x.x * inverseMajorSquared + y.x * y.x * inverseMinorSquared
        let b = 2.0 * (
            x.x * x.y * inverseMajorSquared + y.x * y.y * inverseMinorSquared
        )
        let c = x.y * x.y * inverseMajorSquared + y.y * y.y * inverseMinorSquared
        let d = -2.0 * a * ellipse.center.x - b * ellipse.center.y
        let e = -b * ellipse.center.x - 2.0 * c * ellipse.center.y
        let f = a * ellipse.center.x * ellipse.center.x
            + b * ellipse.center.x * ellipse.center.y
            + c * ellipse.center.y * ellipse.center.y
            - 1.0
        let parameters = [
            "104", number(a), number(b), number(c), number(d), number(e), number(f), "0",
            number(encodedStart.u), number(encodedStart.v),
            number(encodedEnd.u), number(encodedEnd.v),
        ]
        return try table.add(
            type: 104,
            form: 1,
            label: "PCONIC",
            parameters: parameters.joined(separator: ",") + ";"
        )
    }

    private func parameterBSplineEntity(
        _ curve: BSplineCurve2D,
        surface: Surface3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        try curve.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = curve.domain else {
            throw exchangeError(.invalidInput, "IGES p-curve B-spline requires a finite domain.")
        }
        var values = [
            "126",
            "\(curve.controlPointCount - 1)",
            "\(curve.degree)",
            boolean(false),
            boolean(false),
            boolean(!curve.isRational),
            boolean(false),
        ]
        values.append(contentsOf: curve.knots.map(number))
        values.append(contentsOf: curve.weights.map(number))
        for point in curve.controlPoints {
            let encoded = ExactSurfaceParameterCodec.encode(
                SurfaceParameter(u: point.x, v: point.y),
                on: surface,
                unit: unit,
                convention: .iges
            )
            values.append(contentsOf: [number(encoded.u), number(encoded.v), "0"])
        }
        values.append(contentsOf: [number(lower), number(upper), "0", "0", "1"])
        return try table.add(
            type: 126,
            form: 0,
            label: "PCNURBS",
            parameters: values.joined(separator: ",") + ";"
        )
    }

    private func circularArcParameters(
        modelStart: Point3D,
        modelEnd: Point3D,
        unit: LengthUnit
    ) -> String {
        [
            "100",
            "0",
            "0",
            "0",
            number(unit.fromInternal(modelStart.x)),
            number(unit.fromInternal(modelStart.y)),
            number(unit.fromInternal(modelEnd.x)),
            number(unit.fromInternal(modelEnd.y)),
        ].joined(separator: ",") + ";"
    }

    private func circularArcEntity(
        center: Point3D,
        normal: Vector3D,
        reference: Vector3D,
        label: String,
        modelStart: Point3D,
        modelEnd: Point3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let yAxis = try normal.cross(reference).normalized(
            tolerance: tolerance.distance
        )
        let transformation = try transformationEntity(
            origin: center,
            xAxis: reference,
            yAxis: yAxis,
            zAxis: normal,
            unit: unit,
            table: &table
        )
        let startOffset = modelStart - center
        let endOffset = modelEnd - center
        let localStart = Point3D(
            x: startOffset.dot(reference),
            y: startOffset.dot(yAxis),
            z: 0.0
        )
        let localEnd = Point3D(
            x: endOffset.dot(reference),
            y: endOffset.dot(yAxis),
            z: 0.0
        )
        return try table.add(
            type: 100,
            form: 0,
            label: label,
            transformationPointer: transformation,
            parameters: circularArcParameters(
                modelStart: localStart,
                modelEnd: localEnd,
                unit: unit
            )
        )
    }

    private func analyticCurveEntity(
        _ curve: AnalyticCurve3D,
        edge: Edge,
        start: Point3D,
        end: Point3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> (pointer: Int, sameSense: Bool) {
        switch curve {
        case let .line(_, direction):
            let signedSpan = (end - start).dot(direction)
            guard abs(signedSpan) > tolerance.distance else {
                throw exchangeError(.topologyFailure, "IGES analytic line is inconsistent with its vertices.")
            }
            return (
                try table.add(
                    type: 110,
                    form: 0,
                    label: "ANALINE",
                    parameters: lineParameters(
                        start: signedSpan > 0.0 ? start : end,
                        end: signedSpan > 0.0 ? end : start,
                        unit: unit
                    )
                ),
                signedSpan > 0.0
            )
        case let .circle(center, normal, _):
            let trim = try requiredPeriodicTrim(edge, label: "analytic circle")
            let sameSense = trim.endParameter > trim.startParameter
            let basis = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance)
            return (
                try circularArcEntity(
                    center: center,
                    normal: normal,
                    reference: basis.u,
                    label: "ANACIRCL",
                    modelStart: sameSense ? start : end,
                    modelEnd: sameSense ? end : start,
                    unit: unit,
                    table: &table
                ),
                sameSense
            )
        case let .arc(center, normal, _, startAngle, endAngle):
            guard let trim = edge.trim,
                  trim.startParameter >= startAngle - tolerance.angle,
                  trim.startParameter <= endAngle + tolerance.angle,
                  trim.endParameter >= startAngle - tolerance.angle,
                  trim.endParameter <= endAngle + tolerance.angle,
                  abs(trim.endParameter - trim.startParameter) > tolerance.angle,
                  abs(trim.endParameter - trim.startParameter)
                    < 2.0 * Double.pi - tolerance.angle else {
                throw exchangeError(
                    .topologyFailure,
                    "IGES analytic arc requires a finite sub-period trim inside its arc domain."
                )
            }
            let sameSense = trim.endParameter > trim.startParameter
            let basis = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance)
            return (
                try circularArcEntity(
                    center: center,
                    normal: normal,
                    reference: basis.u,
                    label: "ANAARC",
                    modelStart: sameSense ? start : end,
                    modelEnd: sameSense ? end : start,
                    unit: unit,
                    table: &table
                ),
                sameSense
            )
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            let trim = try requiredPeriodicTrim(edge, label: "analytic ellipse")
            let sameSense = trim.endParameter > trim.startParameter
            let minorAxis = try normal.cross(majorAxis).normalized(
                tolerance: tolerance.distance
            )
            let transformation = try transformationEntity(
                origin: center,
                xAxis: majorAxis,
                yAxis: minorAxis,
                zAxis: normal,
                unit: unit,
                table: &table
            )
            let modelStart = sameSense ? start : end
            let modelEnd = sameSense ? end : start
            let startOffset = modelStart - center
            let endOffset = modelEnd - center
            let localStart = Point2D(x: startOffset.dot(majorAxis), y: startOffset.dot(minorAxis))
            let localEnd = Point2D(x: endOffset.dot(majorAxis), y: endOffset.dot(minorAxis))
            let major = unit.fromInternal(majorRadius)
            let minor = unit.fromInternal(minorRadius)
            let parameters = [
                "104",
                number(minor * minor),
                "0",
                number(major * major),
                "0",
                "0",
                number(-major * major * minor * minor),
                "0",
                number(unit.fromInternal(localStart.x)),
                number(unit.fromInternal(localStart.y)),
                number(unit.fromInternal(localEnd.x)),
                number(unit.fromInternal(localEnd.y)),
            ].joined(separator: ",") + ";"
            return (
                try table.add(
                    type: 104,
                    form: 1,
                    label: "ANAELIPS",
                    transformationPointer: transformation,
                    parameters: parameters
                ),
                sameSense
            )
        case let .hyperbola(curve):
            guard let trim = edge.trim,
                  trim.startParameter.isFinite,
                  trim.endParameter.isFinite,
                  abs(trim.endParameter - trim.startParameter) > tolerance.relative else {
                throw exchangeError(
                    .topologyFailure,
                    "IGES hyperbola edges require a finite nonzero trim."
                )
            }
            let sameSense = trim.endParameter > trim.startParameter
            let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
                tolerance: tolerance.distance
            )
            let transformation = try transformationEntity(
                origin: curve.center,
                xAxis: curve.transverseAxis,
                yAxis: conjugateAxis,
                zAxis: curve.normal,
                unit: unit,
                table: &table
            )
            let modelStart = sameSense ? start : end
            let modelEnd = sameSense ? end : start
            let startOffset = modelStart - curve.center
            let endOffset = modelEnd - curve.center
            let transverse = unit.fromInternal(curve.transverseRadius)
            let conjugate = unit.fromInternal(curve.conjugateRadius)
            let parameters = [
                "104",
                number(conjugate * conjugate),
                "0",
                number(-(transverse * transverse)),
                "0",
                "0",
                number(-(transverse * transverse * conjugate * conjugate)),
                "0",
                number(unit.fromInternal(startOffset.dot(curve.transverseAxis))),
                number(unit.fromInternal(startOffset.dot(conjugateAxis))),
                number(unit.fromInternal(endOffset.dot(curve.transverseAxis))),
                number(unit.fromInternal(endOffset.dot(conjugateAxis))),
            ].joined(separator: ",") + ";"
            return (
                try table.add(
                    type: 104,
                    form: 2,
                    label: "ANAHYPER",
                    transformationPointer: transformation,
                    parameters: parameters
                ),
                sameSense
            )
        case let .parabola(curve):
            guard let trim = edge.trim,
                  trim.startParameter.isFinite,
                  trim.endParameter.isFinite,
                  abs(trim.endParameter - trim.startParameter) > tolerance.distance else {
                throw exchangeError(
                    .topologyFailure,
                    "IGES parabola edges require a finite nonzero trim."
                )
            }
            let sameSense = trim.endParameter > trim.startParameter
            let transverseAxis = try curve.normal.cross(curve.axis).normalized(
                tolerance: tolerance.distance
            )
            let transformation = try transformationEntity(
                origin: curve.vertex,
                xAxis: curve.axis,
                yAxis: transverseAxis,
                zAxis: curve.normal,
                unit: unit,
                table: &table
            )
            let modelStart = sameSense ? start : end
            let modelEnd = sameSense ? end : start
            let startOffset = modelStart - curve.vertex
            let endOffset = modelEnd - curve.vertex
            let parameters = [
                "104",
                "0",
                "0",
                "1",
                number(-4.0 * unit.fromInternal(curve.focalLength)),
                "0",
                "0",
                "0",
                number(unit.fromInternal(startOffset.dot(curve.axis))),
                number(unit.fromInternal(startOffset.dot(transverseAxis))),
                number(unit.fromInternal(endOffset.dot(curve.axis))),
                number(unit.fromInternal(endOffset.dot(transverseAxis))),
            ].joined(separator: ",") + ";"
            return (
                try table.add(
                    type: 104,
                    form: 3,
                    label: "ANAPARAB",
                    transformationPointer: transformation,
                    parameters: parameters
                ),
                sameSense
            )
        case .planeTorus:
            throw exchangeError(
                .unsupportedCapability,
                "IGES plane-torus intersection transfer requires an exact curve-on-surface entity writer."
            )
        }
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
                "IGES \(label) edge requires a finite trim shorter than one period."
            )
        }
        return trim
    }

    private func transformationEntity(
        origin: Point3D,
        xAxis: Vector3D,
        yAxis: Vector3D,
        zAxis: Vector3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let transformation = try IGESTransformation(
            xAxis: xAxis,
            yAxis: yAxis,
            zAxis: zAxis,
            translation: origin,
            tolerance: tolerance
        )
        let values = [
            "124",
            number(transformation.xAxis.x),
            number(transformation.yAxis.x),
            number(transformation.zAxis.x),
            number(unit.fromInternal(transformation.translation.x)),
            number(transformation.xAxis.y),
            number(transformation.yAxis.y),
            number(transformation.zAxis.y),
            number(unit.fromInternal(transformation.translation.y)),
            number(transformation.xAxis.z),
            number(transformation.yAxis.z),
            number(transformation.zAxis.z),
            number(unit.fromInternal(transformation.translation.z)),
        ]
        return try table.add(
            type: 124,
            form: 0,
            label: "XFORM",
            parameters: values.joined(separator: ",") + ";"
        )
    }

    private func bSplineCurveParameters(
        _ curve: BSplineCurve3D,
        startParameter: Double,
        endParameter: Double,
        unit: LengthUnit
    ) -> String {
        var values = [
            "126",
            "\(curve.controlPointCount - 1)",
            "\(curve.degree)",
            boolean(false),
            boolean(false),
            boolean(!curve.isRational),
            boolean(false),
        ]
        values.append(contentsOf: curve.knots.map(number))
        values.append(contentsOf: curve.weights.map(number))
        for point in curve.controlPoints {
            values.append(contentsOf: coordinates(point, unit: unit))
        }
        values.append(number(startParameter))
        values.append(number(endParameter))
        values.append(contentsOf: ["0", "0", "1"])
        return values.joined(separator: ",") + ";"
    }

    private func bSplineSurfaceParameters(
        _ surface: BSplineSurface3D,
        unit: LengthUnit
    ) -> String {
        var values = [
            "128",
            "\(surface.uControlPointCount - 1)",
            "\(surface.vControlPointCount - 1)",
            "\(surface.uDegree)",
            "\(surface.vDegree)",
            boolean(false),
            boolean(false),
            boolean(!surface.isRational),
            boolean(false),
            boolean(false),
        ]
        values.append(contentsOf: surface.uKnots.map(number))
        values.append(contentsOf: surface.vKnots.map(number))
        for row in surface.weights {
            values.append(contentsOf: row.map(number))
        }
        for row in surface.controlPoints {
            for point in row {
                values.append(contentsOf: coordinates(point, unit: unit))
            }
        }
        if case let .closed(uLower, uUpper) = surface.uDomain,
           case let .closed(vLower, vUpper) = surface.vDomain {
            values.append(contentsOf: [number(uLower), number(uUpper), number(vLower), number(vUpper)])
        }
        return values.joined(separator: ",") + ";"
    }

    private func exactSurfaceEntity(
        _ surface: Surface3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        switch surface {
        case let .plane(plane):
            let point = try table.add(
                type: 116,
                form: 0,
                label: "ORIGIN",
                parameters: pointParameters(plane.origin, unit: unit)
            )
            let normal = try table.add(
                type: 123,
                form: 0,
                label: "NORMAL",
                parameters: directionParameters(plane.normal)
            )
            let frame = try surface.differentialGeometry(
                atU: 0.0,
                v: 0.0,
                tolerance: tolerance
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(frame.tangentU)
            )
            return try table.add(
                type: 190,
                form: 1,
                label: "PLANE",
                parameters: "190,\(point),\(normal),\(reference);"
            )
        case let .bSpline(bSpline):
            return try table.add(
                type: 128,
                form: 0,
                label: "NURBSSRF",
                parameters: bSplineSurfaceParameters(bSpline, unit: unit)
            )
        case let .cylinder(cylinder):
            let point = try table.add(
                type: 116,
                form: 0,
                label: "ORIGIN",
                parameters: pointParameters(cylinder.origin, unit: unit)
            )
            let axis = try table.add(
                type: 123,
                form: 0,
                label: "AXIS",
                parameters: directionParameters(cylinder.axis)
            )
            let frame = try surface.differentialGeometry(
                atU: 0.0,
                v: 0.0,
                tolerance: tolerance
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(frame.normal)
            )
            return try table.add(
                type: 192,
                form: 1,
                label: "CYLINDER",
                parameters: "192,\(point),\(axis),\(number(unit.fromInternal(cylinder.radius))),\(reference);"
            )
        case let .analytic(analytic):
            return try analyticSurfaceEntity(analytic, unit: unit, table: &table)
        }
    }

    private func pointParameters(_ point: Point3D, unit: LengthUnit) -> String {
        (["116"] + coordinates(point, unit: unit) + ["0"]).joined(separator: ",") + ";"
    }

    private func directionParameters(_ vector: Vector3D) -> String {
        ["123", number(vector.x), number(vector.y), number(vector.z)].joined(separator: ",") + ";"
    }

    private func analyticSurfaceEntity(
        _ surface: AnalyticSurface3D,
        unit: LengthUnit,
        table: inout EntityTable
    ) throws -> Int {
        let type: Int
        let label: String
        let parameters: String
        switch surface {
        case let .plane(origin, normal):
            let basis = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance)
            let point = try table.add(
                type: 116,
                form: 0,
                label: "ORIGIN",
                parameters: pointParameters(origin, unit: unit)
            )
            let axis = try table.add(
                type: 123,
                form: 0,
                label: "NORMAL",
                parameters: directionParameters(normal)
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(basis.u)
            )
            type = 190
            label = "ANAPLANE"
            parameters = "190,\(point),\(axis),\(reference);"
        case let .cylinder(origin, axis, radius):
            let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
            let point = try table.add(
                type: 116,
                form: 0,
                label: "ORIGIN",
                parameters: pointParameters(origin, unit: unit)
            )
            let axisPointer = try table.add(
                type: 123,
                form: 0,
                label: "AXIS",
                parameters: directionParameters(axis)
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(basis.u)
            )
            type = 192
            label = "ANACYL"
            parameters = "192,\(point),\(axisPointer),\(number(unit.fromInternal(radius))),\(reference);"
        case let .cone(apex, axis, halfAngle):
            let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
            let point = try table.add(
                type: 116,
                form: 0,
                label: "APEX",
                parameters: pointParameters(apex, unit: unit)
            )
            let axisPointer = try table.add(
                type: 123,
                form: 0,
                label: "AXIS",
                parameters: directionParameters(axis)
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(basis.u)
            )
            type = 194
            label = "ANACONE"
            parameters = "194,\(point),\(axisPointer),0,\(number(halfAngle)),\(reference);"
        case let .sphere(center, radius):
            let axis = Vector3D.unitZ
            let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
            let point = try table.add(
                type: 116,
                form: 0,
                label: "CENTER",
                parameters: pointParameters(center, unit: unit)
            )
            let axisPointer = try table.add(
                type: 123,
                form: 0,
                label: "AXIS",
                parameters: directionParameters(axis)
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(basis.u)
            )
            type = 196
            label = "ANASPHER"
            parameters = "196,\(point),\(number(unit.fromInternal(radius))),\(axisPointer),\(reference);"
        case let .torus(center, axis, majorRadius, minorRadius):
            let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
            let point = try table.add(
                type: 116,
                form: 0,
                label: "CENTER",
                parameters: pointParameters(center, unit: unit)
            )
            let axisPointer = try table.add(
                type: 123,
                form: 0,
                label: "AXIS",
                parameters: directionParameters(axis)
            )
            let reference = try table.add(
                type: 123,
                form: 0,
                label: "REFDIR",
                parameters: directionParameters(basis.u)
            )
            type = 198
            label = "ANATORUS"
            parameters = "198,\(point),\(axisPointer),\(number(unit.fromInternal(majorRadius))),\(number(unit.fromInternal(minorRadius))),\(reference);"
        }
        return try table.add(
            type: type,
            form: 1,
            label: label,
            parameters: parameters
        )
    }

    private func coordinates(_ point: Point3D, unit: LengthUnit) -> [String] {
        [
            number(unit.fromInternal(point.x)),
            number(unit.fromInternal(point.y)),
            number(unit.fromInternal(point.z)),
        ]
    }

    private func boolean(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func number(_ value: Double) -> String {
        String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func exchangeError(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .exchange, code: code, tolerance: tolerance, message: message)
    }
}

private extension ExactIGESWriter {
    struct EntityTable {
        struct Entity {
            let type: Int
            let form: Int
            let label: String
            let transformationPointer: Int
            let statusNumber: Int
            let parameters: String
        }

        let maximumEntities: Int
        let tolerance: ModelingTolerance
        var entities: [Entity] = []

        mutating func add(
            type: Int,
            form: Int,
            label: String,
            transformationPointer: Int = 0,
            statusNumber: Int = 0,
            parameters: String
        ) throws -> Int {
            guard entities.count < maximumEntities else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "IGES output exceeds the configured entity limit."
                )
            }
            entities.append(Entity(
                type: type,
                form: form,
                label: label,
                transformationPointer: transformationPointer,
                statusNumber: statusNumber,
                parameters: parameters
            ))
            return entities.count * 2 - 1
        }

        func serialize(unit: LengthUnit, maximumBytes: Int) throws -> Data {
            let startRecords = sectionRecords("SwiftCAD exact B-rep", section: "S")
            let globalRecords = sectionRecords(globalParameters(unit: unit), section: "G")
            var directoryRecords: [String] = []
            var parameterRecords: [String] = []
            var parameterSequence = 1
            for (offset, entity) in entities.enumerated() {
                let entityIndex = offset + 1
                let directoryPointer = entityIndex * 2 - 1
                let records = parameterSectionRecords(
                    entity.parameters,
                    directoryPointer: directoryPointer,
                    startSequence: parameterSequence
                )
                directoryRecords.append(contentsOf: directorySectionRecords(
                    entity: entity,
                    parameterPointer: parameterSequence,
                    parameterLineCount: records.count,
                    entityIndex: entityIndex
                ))
                parameterRecords.append(contentsOf: records)
                parameterSequence += records.count
            }
            let terminate = terminateRecord(
                startCount: startRecords.count,
                globalCount: globalRecords.count,
                directoryCount: directoryRecords.count,
                parameterCount: parameterRecords.count
            )
            let text = (startRecords + globalRecords + directoryRecords + parameterRecords + [terminate])
                .joined(separator: "\n")
            let data = Data(text.utf8)
            guard data.count <= maximumBytes else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "IGES output exceeds the configured byte limit."
                )
            }
            return data
        }

        private func globalParameters(unit: LengthUnit) -> String {
            [
                "1H,", "1H;", hollerith("SWFT"), hollerith("swiftcad-exact.igs"),
                hollerith("Swift-CAD"), hollerith("Swift-CAD"),
                "32", "38", "6", "308", "15", "1.0", "2", "\(unitFlag(unit))",
                hollerith(unitName(unit)), "1", "0.001", "15H20000101.000000", "1.0E-9", "0.0",
                "8HSwiftCAD", "9HSwift-CAD", "11", "0", "15H20000101.000000",
            ].joined(separator: ",") + ";"
        }

        private func directorySectionRecords(
            entity: Entity,
            parameterPointer: Int,
            parameterLineCount: Int,
            entityIndex: Int
        ) -> [String] {
            let first = [
                integer(entity.type), integer(parameterPointer), integer(0), integer(0), integer(0),
                integer(0), integer(entity.transformationPointer), integer(0), status(entity.statusNumber),
            ].joined()
            let second = [
                integer(entity.type), integer(0), integer(0), integer(parameterLineCount), integer(entity.form),
                integer(0), integer(0), text(entity.label), integer(entityIndex),
            ].joined()
            return [
                record(first, section: "D", sequence: entityIndex * 2 - 1),
                record(second, section: "D", sequence: entityIndex * 2),
            ]
        }

        private func parameterSectionRecords(
            _ data: String,
            directoryPointer: Int,
            startSequence: Int
        ) -> [String] {
            let characters = Array(data)
            var records: [String] = []
            var offset = 0
            var sequence = startSequence
            while offset < characters.count {
                let end = min(offset + 64, characters.count)
                let chunk = String(characters[offset..<end])
                records.append(record(
                    chunk.padding(toLength: 64, withPad: " ", startingAt: 0) + integer(directoryPointer),
                    section: "P",
                    sequence: sequence
                ))
                offset = end
                sequence += 1
            }
            return records
        }

        private func sectionRecords(_ content: String, section: Character) -> [String] {
            let characters = Array(content)
            var records: [String] = []
            var offset = 0
            var sequence = 1
            repeat {
                let end = min(offset + 72, characters.count)
                records.append(record(String(characters[offset..<end]), section: section, sequence: sequence))
                offset = end
                sequence += 1
            } while offset < characters.count
            return records
        }

        private func terminateRecord(
            startCount: Int,
            globalCount: Int,
            directoryCount: Int,
            parameterCount: Int
        ) -> String {
            let content = "S\(integer(startCount).dropFirst())G\(integer(globalCount).dropFirst())D\(integer(directoryCount).dropFirst())P\(integer(parameterCount).dropFirst())"
            return record(content, section: "T", sequence: 1)
        }

        private func record(_ content: String, section: Character, sequence: Int) -> String {
            String(content.prefix(72)).padding(toLength: 72, withPad: " ", startingAt: 0)
                + String(section)
                + String(format: "%7d", locale: Locale(identifier: "en_US_POSIX"), sequence)
        }

        private func status(_ value: Int) -> String {
            String(format: "%08d", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        private func integer(_ value: Int) -> String {
            String(format: "%8d", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        private func text(_ value: String) -> String {
            String(value.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
        }

        private func hollerith(_ value: String) -> String {
            "\(value.count)H\(value)"
        }

        private func unitFlag(_ unit: LengthUnit) -> Int {
            switch unit {
            case .inch: 1
            case .millimeter: 2
            case .foot: 4
            case .meter: 6
            case .kilometer: 7
            case .micrometer: 9
            case .centimeter: 10
            }
        }

        private func unitName(_ unit: LengthUnit) -> String {
            switch unit {
            case .micrometer: "MICRON"
            case .meter: "M"
            case .millimeter: "MM"
            case .centimeter: "CM"
            case .kilometer: "KM"
            case .inch: "IN"
            case .foot: "FT"
            }
        }
    }
}
