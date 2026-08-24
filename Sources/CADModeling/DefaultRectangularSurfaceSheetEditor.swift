import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct DefaultRectangularSurfaceSheetEditor: RectangularSurfaceSheetEditing {
    package init() {}

    package func bounds(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> RectangularSurfaceParameterBounds {
        try details(bodyID: bodyID, model: model, tolerance: tolerance).bounds
    }

    package func resize(
        featureID: FeatureID,
        bodyID: BodyID,
        to bounds: RectangularSurfaceParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let sheet = try details(
            bodyID: bodyID,
            model: model,
            tolerance: tolerance
        )
        try rebuild(
            featureID: featureID,
            sheet: sheet,
            surface: sheet.surface,
            bounds: bounds,
            model: &model,
            tolerance: tolerance
        )
    }

    package func replaceSurface(
        featureID: FeatureID,
        bodyID: BodyID,
        with surface: Surface3D,
        bounds: RectangularSurfaceParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        let sheet = try details(
            bodyID: bodyID,
            model: model,
            tolerance: tolerance
        )
        guard model.geometry.surfaces[sheet.surfaceID] != nil else {
            throw TopologyError.missingReference(
                "Rectangular surface sheet geometry is missing."
            )
        }
        model.geometry.surfaces[sheet.surfaceID] = surface
        try rebuild(
            featureID: featureID,
            sheet: sheet,
            surface: surface,
            bounds: bounds,
            model: &model,
            tolerance: tolerance
        )
    }

    private func rebuild(
        featureID: FeatureID,
        sheet: SheetDetails,
        surface: Surface3D,
        bounds: RectangularSurfaceParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try validate(
            bounds: bounds,
            on: surface,
            tolerance: tolerance
        )

        var loop = sheet.loop
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        var vertexPositions: [VertexID: Point3D] = [:]
        for segment in sheet.segments {
            let parameterCurve = try resizedParameterCurve(
                segment,
                from: sheet.bounds,
                to: bounds,
                tolerance: tolerance
            )
            try parameterCurve.validate(on: surface, tolerance: tolerance)
            let canonicalParameterCurve = switch segment.coedge.orientation {
            case .forward:
                parameterCurve
            case .reversed:
                try parameterCurve.reversed(tolerance: tolerance)
            }
            let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: canonicalParameterCurve
            ))
            try curve.validate(tolerance: tolerance)

            guard var edge = model.edges[segment.coedge.edgeID] else {
                throw TopologyError.missingReference(
                    "Rectangular surface sheet edge is missing."
                )
            }
            let curveID = nextAvailableCurveID(
                model: model,
                topologyIDs: &topologyIDs
            )
            model.geometry.curves[curveID] = curve
            edge.curveID = curveID
            edge.trim = CurveTrim(startParameter: 0.0, endParameter: 1.0)
            model.edges[edge.id] = edge

            let startParameter = try parameterCurve.startParameter(
                tolerance: tolerance
            )
            let endParameter = try parameterCurve.endParameter(
                tolerance: tolerance
            )
            try record(
                try surface.point(
                    u: startParameter.u,
                    v: startParameter.v,
                    tolerance: tolerance
                ),
                for: segment.startVertexID,
                in: &vertexPositions,
                tolerance: tolerance
            )
            try record(
                try surface.point(
                    u: endParameter.u,
                    v: endParameter.v,
                    tolerance: tolerance
                ),
                for: segment.endVertexID,
                in: &vertexPositions,
                tolerance: tolerance
            )
            loop.coedges[segment.coedgeIndex].surfaceParameterCurve = parameterCurve
        }

        guard vertexPositions.count == 4 else {
            throw topologyFailure(
                tolerance: tolerance,
                message: "Rectangular surface sheet resize did not resolve four unique corners."
            )
        }
        for (vertexID, point) in vertexPositions {
            guard var vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference(
                    "Rectangular surface sheet vertex is missing."
                )
            }
            vertex.point = point
            model.vertices[vertexID] = vertex
        }
        model.loops[loop.id] = loop
        pruneUnreferencedCurves(in: &model)
    }

    private func details(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SheetDetails {
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 1,
              let faceID = shell.faceIDs.first,
              let face = model.faces[faceID],
              face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              loop.coedges.count == 4,
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw invalidInput(
                tolerance: tolerance,
                message: "Rectangular surface sheet editing requires one exact four-edge face with one outer loop."
            )
        }
        guard Set(loop.coedges.map(\.edgeID)).count == loop.coedges.count else {
            throw topologyFailure(
                tolerance: tolerance,
                message: "A rectangular sheet boundary must use four distinct edges."
            )
        }

        let parameterScale = try parameterScale(
            loop: loop,
            tolerance: tolerance
        )
        let parameterTolerance = max(
            tolerance.distance,
            tolerance.angle,
            tolerance.relative * parameterScale,
            Double.ulpOfOne * parameterScale * 256.0
        )
        var segments: [BoundarySegment] = []
        for (index, coedge) in loop.coedges.enumerated() {
            guard let edge = model.edges[coedge.edgeID],
                  let parameterCurve = coedge.surfaceParameterCurve else {
                throw topologyFailure(
                    tolerance: tolerance,
                    message: "Surface trim requires an exact pcurve on every boundary coedge."
                )
            }
            let startVertexID = switch coedge.orientation {
            case .forward: edge.startVertexID
            case .reversed: edge.endVertexID
            }
            let endVertexID = switch coedge.orientation {
            case .forward: edge.endVertexID
            case .reversed: edge.startVertexID
            }
            guard let segment = try axisAlignedSegment(
                coedgeIndex: index,
                coedge: coedge,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                parameterCurve: parameterCurve,
                parameterTolerance: parameterTolerance,
                tolerance: tolerance
            ) else {
                throw invalidInput(
                    tolerance: tolerance,
                    message: "Rectangular surface sheet editing requires four exact axis-aligned pcurve boundaries."
                )
            }
            segments.append(segment)
        }
        try validateParameterClosure(
            segments,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        )

        let endpoints = segments.flatMap { [$0.start, $0.end] }
        guard let lowerU = endpoints.map(\.u).min(),
              let upperU = endpoints.map(\.u).max(),
              let lowerV = endpoints.map(\.v).min(),
              let upperV = endpoints.map(\.v).max(),
              upperU - lowerU > parameterTolerance,
              upperV - lowerV > parameterTolerance else {
            throw topologyFailure(
                tolerance: tolerance,
                message: "Rectangular surface parameter bounds are degenerate."
            )
        }
        let bounds = RectangularSurfaceParameterBounds(
            lowerU: lowerU,
            upperU: upperU,
            lowerV: lowerV,
            upperV: upperV
        )
        try validateRectangle(
            segments,
            bounds: bounds,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        )
        try validate(bounds: bounds, on: surface, tolerance: tolerance)
        return SheetDetails(
            surfaceID: face.surfaceID,
            surface: surface,
            loop: loop,
            bounds: bounds,
            segments: segments
        )
    }

    private func axisAlignedSegment(
        coedgeIndex: Int,
        coedge: Coedge,
        startVertexID: VertexID,
        endVertexID: VertexID,
        parameterCurve: SurfaceParameterCurve,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> BoundarySegment? {
        let start = try parameterCurve.startParameter(tolerance: tolerance)
        let end = try parameterCurve.endParameter(tolerance: tolerance)
        let points: [SurfaceParameter]
        switch parameterCurve {
        case .constantU, .constantV, .affine:
            points = [start, end]
        case let .polyline(polyline):
            points = polyline
        case let .bSpline(curve):
            points = curve.controlPoints.map {
                SurfaceParameter(u: $0.x, v: $0.y)
            }
        case .harmonic,
             .sphericalGreatCircle,
             .certifiedImplicit,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic,
             .rigidImage:
            return nil
        case let .sameParameterImage(image):
            return try axisAlignedSegment(
                coedgeIndex: coedgeIndex,
                coedge: coedge,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                parameterCurve: image.source,
                parameterTolerance: parameterTolerance,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, _, _):
            guard let baseSegment = try axisAlignedSegment(
                coedgeIndex: coedgeIndex,
                coedge: coedge,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                parameterCurve: base,
                parameterTolerance: parameterTolerance,
                tolerance: tolerance
            ) else {
                return nil
            }
            return BoundarySegment(
                coedgeIndex: coedgeIndex,
                coedge: coedge,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                start: start,
                end: end,
                axis: baseSegment.axis
            )
        }
        guard points.count >= 2 else { return nil }
        let uValues = points.map(\.u)
        let vValues = points.map(\.v)
        let uSpread = (uValues.max() ?? 0.0) - (uValues.min() ?? 0.0)
        let vSpread = (vValues.max() ?? 0.0) - (vValues.min() ?? 0.0)
        let axis: ParameterAxis
        let varyingValues: [Double]
        if uSpread <= parameterTolerance,
           vSpread > parameterTolerance,
           abs(start.u - end.u) <= parameterTolerance {
            axis = .v
            varyingValues = vValues
        } else if vSpread <= parameterTolerance,
                  uSpread > parameterTolerance,
                  abs(start.v - end.v) <= parameterTolerance {
            axis = .u
            varyingValues = uValues
        } else {
            return nil
        }
        guard isMonotone(
            varyingValues,
            from: axis == .u ? start.u : start.v,
            to: axis == .u ? end.u : end.v,
            tolerance: parameterTolerance
        ) else {
            return nil
        }
        return BoundarySegment(
            coedgeIndex: coedgeIndex,
            coedge: coedge,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            start: start,
            end: end,
            axis: axis
        )
    }

    private func validateParameterClosure(
        _ segments: [BoundarySegment],
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    ) throws {
        for index in segments.indices {
            let current = segments[index]
            let next = segments[(index + 1) % segments.count]
            guard approximatelyEqual(
                current.end,
                next.start,
                tolerance: parameterTolerance
            ) else {
                throw topologyFailure(
                    residual: hypot(
                        current.end.u - next.start.u,
                        current.end.v - next.start.v
                    ),
                    tolerance: tolerance,
                    message: "Rectangular sheet pcurves do not form a closed parameter loop."
                )
            }
        }
    }

    private func validateRectangle(
        _ segments: [BoundarySegment],
        bounds: RectangularSurfaceParameterBounds,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    ) throws {
        var boundaries = Set<ParameterBoundary>()
        var corners = Set<ParameterCorner>()
        for segment in segments {
            let boundary: ParameterBoundary
            switch segment.axis {
            case .u:
                if approximatelyEqual(
                    segment.start.v,
                    bounds.lowerV,
                    tolerance: parameterTolerance
                ) {
                    boundary = .vLower
                } else if approximatelyEqual(
                    segment.start.v,
                    bounds.upperV,
                    tolerance: parameterTolerance
                ) {
                    boundary = .vUpper
                } else {
                    throw invalidInput(
                        tolerance: tolerance,
                        message: "A rectangular U boundary must lie on a V domain limit."
                    )
                }
                guard endpointPair(
                    segment.start.u,
                    segment.end.u,
                    lower: bounds.lowerU,
                    upper: bounds.upperU,
                    tolerance: parameterTolerance
                ) else {
                    throw invalidInput(
                        tolerance: tolerance,
                        message: "A rectangular U boundary must span both U domain limits."
                    )
                }
            case .v:
                if approximatelyEqual(
                    segment.start.u,
                    bounds.lowerU,
                    tolerance: parameterTolerance
                ) {
                    boundary = .uLower
                } else if approximatelyEqual(
                    segment.start.u,
                    bounds.upperU,
                    tolerance: parameterTolerance
                ) {
                    boundary = .uUpper
                } else {
                    throw invalidInput(
                        tolerance: tolerance,
                        message: "A rectangular V boundary must lie on a U domain limit."
                    )
                }
                guard endpointPair(
                    segment.start.v,
                    segment.end.v,
                    lower: bounds.lowerV,
                    upper: bounds.upperV,
                    tolerance: parameterTolerance
                ) else {
                    throw invalidInput(
                        tolerance: tolerance,
                        message: "A rectangular V boundary must span both V domain limits."
                    )
                }
            }
            guard boundaries.insert(boundary).inserted else {
                throw topologyFailure(
                    tolerance: tolerance,
                    message: "Rectangular sheet pcurves repeat a parameter boundary."
                )
            }
            for endpoint in [segment.start, segment.end] {
                corners.insert(try corner(
                    endpoint,
                    bounds: bounds,
                    parameterTolerance: parameterTolerance,
                    tolerance: tolerance
                ))
            }
        }
        guard boundaries.count == 4, corners.count == 4 else {
            throw topologyFailure(
                tolerance: tolerance,
                message: "Rectangular sheet pcurves must cover four boundaries and four corners exactly."
            )
        }
    }

    private func validate(
        bounds: RectangularSurfaceParameterBounds,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try ExactSurfaceParameterBoundsValidator().validate(
            bounds,
            on: surface,
            tolerance: tolerance
        )
    }

    private func resizedParameterCurve(
        _ segment: BoundarySegment,
        from old: RectangularSurfaceParameterBounds,
        to new: RectangularSurfaceParameterBounds,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        let scale = max(
            abs(old.lowerU), abs(old.upperU),
            abs(old.lowerV), abs(old.upperV),
            1.0
        )
        let parameterTolerance = max(
            tolerance.distance,
            tolerance.angle,
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        let start = try mapped(
            segment.start,
            from: old,
            to: new,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        )
        let end = try mapped(
            segment.end,
            from: old,
            to: new,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        )
        switch segment.axis {
        case .u:
            guard approximatelyEqual(
                start.v,
                end.v,
                tolerance: parameterTolerance
            ) else {
                throw topologyFailure(
                    tolerance: tolerance,
                    message: "Resized U boundary lost its constant V parameter."
                )
            }
            return .constantV(v: start.v, uStart: start.u, uEnd: end.u)
        case .v:
            guard approximatelyEqual(
                start.u,
                end.u,
                tolerance: parameterTolerance
            ) else {
                throw topologyFailure(
                    tolerance: tolerance,
                    message: "Resized V boundary lost its constant U parameter."
                )
            }
            return .constantU(u: start.u, vStart: start.v, vEnd: end.v)
        }
    }

    private func mapped(
        _ parameter: SurfaceParameter,
        from old: RectangularSurfaceParameterBounds,
        to new: RectangularSurfaceParameterBounds,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        SurfaceParameter(
            u: try mappedCoordinate(
                parameter.u,
                oldLower: old.lowerU,
                oldUpper: old.upperU,
                newLower: new.lowerU,
                newUpper: new.upperU,
                parameterTolerance: parameterTolerance,
                tolerance: tolerance
            ),
            v: try mappedCoordinate(
                parameter.v,
                oldLower: old.lowerV,
                oldUpper: old.upperV,
                newLower: new.lowerV,
                newUpper: new.upperV,
                parameterTolerance: parameterTolerance,
                tolerance: tolerance
            )
        )
    }

    private func mappedCoordinate(
        _ value: Double,
        oldLower: Double,
        oldUpper: Double,
        newLower: Double,
        newUpper: Double,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        if approximatelyEqual(value, oldLower, tolerance: parameterTolerance) {
            return newLower
        }
        if approximatelyEqual(value, oldUpper, tolerance: parameterTolerance) {
            return newUpper
        }
        throw topologyFailure(
            residual: min(abs(value - oldLower), abs(value - oldUpper)),
            tolerance: tolerance,
            message: "A rectangular trim endpoint is not on a source domain limit."
        )
    }

    private func record(
        _ point: Point3D,
        for vertexID: VertexID,
        in positions: inout [VertexID: Point3D],
        tolerance: ModelingTolerance
    ) throws {
        if let existing = positions[vertexID],
           !existing.isApproximatelyEqual(to: point, tolerance: tolerance.distance) {
            throw topologyFailure(
                residual: (existing - point).length,
                tolerance: tolerance,
                message: "Adjacent resized pcurves disagree on their shared vertex."
            )
        }
        positions[vertexID] = point
    }

    private func parameterScale(
        loop: Loop,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var scale = 1.0
        for coedge in loop.coedges {
            guard let curve = coedge.surfaceParameterCurve else { continue }
            let start = try curve.startParameter(tolerance: tolerance)
            let end = try curve.endParameter(tolerance: tolerance)
            scale = max(
                scale,
                abs(start.u), abs(start.v),
                abs(end.u), abs(end.v)
            )
        }
        return scale
    }

    private func isMonotone(
        _ values: [Double],
        from start: Double,
        to end: Double,
        tolerance: Double
    ) -> Bool {
        guard abs(end - start) > tolerance else { return false }
        let increasing = end > start
        for index in 1..<values.count {
            let delta = values[index] - values[index - 1]
            if increasing, delta < -tolerance { return false }
            if !increasing, delta > tolerance { return false }
        }
        return true
    }

    private func endpointPair(
        _ first: Double,
        _ second: Double,
        lower: Double,
        upper: Double,
        tolerance: Double
    ) -> Bool {
        approximatelyEqual(first, lower, tolerance: tolerance)
            && approximatelyEqual(second, upper, tolerance: tolerance)
            || approximatelyEqual(first, upper, tolerance: tolerance)
            && approximatelyEqual(second, lower, tolerance: tolerance)
    }

    private func corner(
        _ parameter: SurfaceParameter,
        bounds: RectangularSurfaceParameterBounds,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> ParameterCorner {
        let upperU: Bool
        if approximatelyEqual(
            parameter.u,
            bounds.lowerU,
            tolerance: parameterTolerance
        ) {
            upperU = false
        } else if approximatelyEqual(
            parameter.u,
            bounds.upperU,
            tolerance: parameterTolerance
        ) {
            upperU = true
        } else {
            throw topologyFailure(
                tolerance: tolerance,
                message: "A rectangular trim endpoint is not on a U corner."
            )
        }
        let upperV: Bool
        if approximatelyEqual(
            parameter.v,
            bounds.lowerV,
            tolerance: parameterTolerance
        ) {
            upperV = false
        } else if approximatelyEqual(
            parameter.v,
            bounds.upperV,
            tolerance: parameterTolerance
        ) {
            upperV = true
        } else {
            throw topologyFailure(
                tolerance: tolerance,
                message: "A rectangular trim endpoint is not on a V corner."
            )
        }
        return ParameterCorner(upperU: upperU, upperV: upperV)
    }

    private func approximatelyEqual(
        _ lhs: SurfaceParameter,
        _ rhs: SurfaceParameter,
        tolerance: Double
    ) -> Bool {
        approximatelyEqual(lhs.u, rhs.u, tolerance: tolerance)
            && approximatelyEqual(lhs.v, rhs.v, tolerance: tolerance)
    }

    private func approximatelyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    ) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func nextAvailableCurveID(
        model: BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> CurveID {
        while true {
            let curveID = topologyIDs.nextCurveID()
            if model.geometry.curves[curveID] == nil {
                return curveID
            }
        }
    }

    private func pruneUnreferencedCurves(in model: inout BRepModel) {
        let referencedCurveIDs = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter {
            referencedCurveIDs.contains($0.key)
        }
    }

    private func invalidInput(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .invalidInput,
            tolerance: tolerance,
            message: message
        )
    }

    private func topologyFailure(
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private enum ParameterAxis {
        case u
        case v
    }

    private enum ParameterBoundary: Hashable {
        case uLower
        case uUpper
        case vLower
        case vUpper
    }

    private struct ParameterCorner: Hashable {
        let upperU: Bool
        let upperV: Bool
    }

    private struct BoundarySegment {
        let coedgeIndex: Int
        let coedge: Coedge
        let startVertexID: VertexID
        let endVertexID: VertexID
        let start: SurfaceParameter
        let end: SurfaceParameter
        let axis: ParameterAxis
    }

    private struct SheetDetails {
        let surfaceID: SurfaceID
        let surface: Surface3D
        let loop: Loop
        let bounds: RectangularSurfaceParameterBounds
        let segments: [BoundarySegment]
    }
}
