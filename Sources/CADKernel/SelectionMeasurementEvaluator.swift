import Foundation
import CADCore
import CADIR
import CADModeling
import CADTopology

public struct SelectionMeasurementEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let edgeQueryEvaluator: EdgeQueryEvaluator
    private let curveQueryEvaluator: CurveQueryEvaluator
    private let surfaceQueryEvaluator: SurfaceQueryEvaluator

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        self.edgeQueryEvaluator = EdgeQueryEvaluator(tolerance: tolerance)
        self.curveQueryEvaluator = CurveQueryEvaluator(tolerance: tolerance)
        self.surfaceQueryEvaluator = SurfaceQueryEvaluator(tolerance: tolerance)
    }

    public func point(
        for selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        try selection.validate()
        switch selection {
        case let .subshape(reference):
            return try topologyPoint(
                for: try document.topologyReference(for: reference),
                stableReference: reference,
                selection: selection,
                in: document
            )
        case let .edge(reference):
            return try edgePoint(for: reference, selection: selection, in: document)
        case let .curve(reference):
            return try curvePoint(for: reference, selection: selection, in: document)
        case let .sketchPoint(reference):
            return try sketchPoint(for: reference, selection: selection, in: document)
        case let .surface(reference):
            return try surfacePoint(for: reference, selection: selection, in: document)
        }
    }

    public func distance(
        from first: SelectionReference,
        to second: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionDistanceMeasurement {
        if let projectedDistance = try projectedCurveDistance(from: first, to: second, in: document) {
            return projectedDistance
        }
        return try SelectionDistanceMeasurement(
            first: point(for: first, in: document),
            second: point(for: second, in: document)
        )
    }

    public func angle(
        between first: SelectionReference,
        and second: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionAngleMeasurement {
        try SelectionAngleMeasurement(
            first: point(for: first, in: document),
            second: point(for: second, in: document),
            tolerance: tolerance
        )
    }

    private func topologyPoint(
        for reference: TopologyReference,
        stableReference: StableSubshapeReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        switch reference {
        case .body:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Body selection does not define a unique measurement point."
            )
        case .face:
            return try surfacePoint(
                for: .whole(SurfaceReference(subshape: stableReference)),
                selection: selection,
                in: document
            )
        case .edge:
            return try edgePoint(
                for: .whole(EdgeReference(subshape: stableReference)),
                selection: selection,
                in: document
            )
        case let .vertex(vertexID):
            guard let vertex = document.brep.vertices[vertexID] else {
                throw FeatureEvaluationError.missingInput("Selection vertex could not be resolved.")
            }
            return SelectionMeasurementPoint(selection: selection, point: vertex.point)
        }
    }

    private func edgePoint(
        for reference: EdgeSubobjectReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let frame: EdgeQueryFrame
        switch reference {
        case let .whole(edge):
            frame = try edgeQueryEvaluator.midpoint(of: edge, in: document)
        case let .parameter(parameter):
            frame = try edgeQueryEvaluator.frame(at: parameter, in: document)
        }
        return SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            tangent: frame.tangent,
            curvature: frame.curvature
        )
    }

    private func curvePoint(
        for reference: CurveSubobjectReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        switch reference {
        case let .whole(curve):
            return try measurementPoint(
                from: curveQueryEvaluator.midpoint(of: curve, in: document),
                selection: selection
            )
        case let .parameter(parameter):
            return try measurementPoint(
                from: curveQueryEvaluator.point(at: parameter, in: document),
                selection: selection
            )
        case let .center(center):
            return SelectionMeasurementPoint(
                selection: selection,
                point: try curveQueryEvaluator.center(center, in: document)
            )
        case let .span(span):
            let spanResult = try curveQueryEvaluator.span(span, in: document)
            let parameter = (spanResult.lowerParameter + spanResult.upperParameter) * 0.5
            return try measurementPoint(
                from: curveQueryEvaluator.point(
                    at: CurveParameterReference(curve: span.curve, parameter: parameter),
                    in: document
                ),
                selection: selection
            )
        case let .controlPoint(controlPoint):
            return SelectionMeasurementPoint(
                selection: selection,
                point: try curveQueryEvaluator.controlPoint(controlPoint, in: document)
            )
        case let .knot(knot):
            let parameter = try curveQueryEvaluator.knot(knot, in: document)
            return try measurementPoint(
                from: curveQueryEvaluator.point(
                    at: CurveParameterReference(curve: knot.curve, parameter: parameter),
                    in: document
                ),
                selection: selection
            )
        }
    }

    private func sketchPoint(
        for reference: SketchPointSelectionReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        guard let feature = document.document.designGraph.nodes[reference.featureID],
              case let .sketch(sketch) = feature.operation else {
            throw FeatureEvaluationError.missingInput("Sketch point selection feature could not be resolved.")
        }
        guard let entity = sketch.entities[reference.entityID] else {
            throw FeatureEvaluationError.missingInput("Sketch point selection entity could not be resolved.")
        }
        guard case let .point(point) = entity else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Sketch point selection reference must target a sketch point entity."
            )
        }
        let resolvedPoint = try resolveSketchPoint(point, parameters: document.parameters)
        return SelectionMeasurementPoint(
            selection: selection,
            point: try mapTo3D(resolvedPoint, on: sketch.plane)
        )
    }

    private func surfacePoint(
        for reference: SurfaceSubobjectReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        switch reference {
        case let .whole(surface):
            return try measurementPoint(
                from: representativeFrame(for: surface, in: document),
                selection: selection
            )
        case let .parameter(parameter):
            return try measurementPoint(
                from: surfaceQueryEvaluator.frame(at: parameter, in: document),
                selection: selection
            )
        case let .span(span):
            return try surfaceSpanPoint(for: span, selection: selection, in: document)
        case let .controlPoint(controlPoint):
            return SelectionMeasurementPoint(
                selection: selection,
                point: try surfaceQueryEvaluator.controlPoint(controlPoint, in: document)
            )
        case .knot:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Surface knot selection does not define a unique measurement point."
            )
        case let .trim(trim):
            return try surfaceTrimPoint(for: trim, selection: selection, in: document)
        case let .trimSpan(span):
            return try surfaceTrimSpanPoint(for: span, selection: selection, in: document)
        case let .trimKnot(knot):
            return try surfaceTrimKnotPoint(for: knot, selection: selection, in: document)
        }
    }

    private func surfaceSpanPoint(
        for span: SurfaceSpanReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let representative = try representativeFrame(for: span.surface, in: document)
        let spanResult = try surfaceQueryEvaluator.span(span, in: document)
        let spanParameter = (spanResult.lowerParameter + spanResult.upperParameter) * 0.5
        let parameter: SurfaceParameterReference
        switch span.direction {
        case .u:
            parameter = SurfaceParameterReference(
                surface: span.surface,
                u: spanParameter,
                v: representative.reference.v
            )
        case .v:
            parameter = SurfaceParameterReference(
                surface: span.surface,
                u: representative.reference.u,
                v: spanParameter
            )
        }
        return try measurementPoint(
            from: surfaceQueryEvaluator.frame(at: parameter, in: document),
            selection: selection
        )
    }

    private func surfaceTrimPoint(
        for trim: SurfaceTrimReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let result = try surfaceQueryEvaluator.trimCurve(trim, in: document)
        let parameter = try result.parameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
        let frame = try surfaceFrame(for: parameter, on: trim.surface, in: document)
        let tangent = try trimTangent(from: result.parameterCurve, on: trim.surface, in: document)
        return SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            tangent: tangent,
            normal: frame.normal,
            curvature: frame.meanCurvature
        )
    }

    private func surfaceTrimSpanPoint(
        for span: SurfaceTrimSpanReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let result = try surfaceQueryEvaluator.trimCurve(span.trim, in: document)
        guard case let .bSpline(curve) = result.parameterCurve else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Surface trim p-curve span selection requires a B-spline parameter curve."
            )
        }
        let curveParameter = try trimSpanParameter(span.spanIndex, on: curve)
        return try surfaceTrimParameterPoint(
            curveParameter: curveParameter,
            curve: curve,
            trim: span.trim,
            selection: selection,
            in: document
        )
    }

    private func surfaceTrimKnotPoint(
        for knot: SurfaceTrimKnotReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let result = try surfaceQueryEvaluator.trimCurve(knot.trim, in: document)
        guard case let .bSpline(curve) = result.parameterCurve else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Surface trim p-curve knot selection requires a B-spline parameter curve."
            )
        }
        guard curve.knots.indices.contains(knot.knotIndex) else {
            throw FeatureEvaluationError.missingInput("Surface trim p-curve knot index could not be resolved.")
        }
        let curveParameter = curve.knots[knot.knotIndex]
        guard try curve.domain.contains(curveParameter, tolerance: tolerance) else {
            throw FeatureEvaluationError.missingInput("Surface trim p-curve knot is outside the curve domain.")
        }
        return try surfaceTrimParameterPoint(
            curveParameter: curveParameter,
            curve: curve,
            trim: knot.trim,
            selection: selection,
            in: document
        )
    }

    private func surfaceTrimParameterPoint(
        curveParameter: Double,
        curve: BSplineCurve2D,
        trim: SurfaceTrimReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let point = try curve.point(at: curveParameter, tolerance: tolerance)
        let parameter = SurfaceParameter(u: point.x, v: point.y)
        let frame = try surfaceFrame(for: parameter, on: trim.surface, in: document)
        let tangent = try surfaceTrimTangent(from: curve, at: curveParameter, using: frame)
        return SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            tangent: tangent,
            normal: frame.normal,
            curvature: frame.meanCurvature
        )
    }

    private func trimSpanParameter(_ spanIndex: Int, on curve: BSplineCurve2D) throws -> Double {
        try curve.validate(tolerance: tolerance)
        let lowerIndex = curve.degree
        let upperIndex = curve.knots.count - curve.degree - 1
        guard lowerIndex < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Surface trim p-curve has no queryable knot spans.")
        }
        var ordinal = 0
        for index in lowerIndex..<upperIndex {
            let lower = curve.knots[index]
            let upper = curve.knots[index + 1]
            guard upper - lower > tolerance.distance else {
                continue
            }
            if ordinal == spanIndex {
                return (lower + upper) * 0.5
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Surface trim p-curve span index could not be resolved.")
    }

    private func surfaceFrame(
        for parameter: SurfaceParameter,
        on surface: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceQueryFrame {
        try surfaceQueryEvaluator.frame(
            at: SurfaceParameterReference(surface: surface, u: parameter.u, v: parameter.v),
            in: document
        )
    }

    private func surfaceTrimTangent(
        from curve: BSplineCurve2D,
        at curveParameter: Double,
        using frame: SurfaceQueryFrame
    ) throws -> Vector3D? {
        let geometry = try curve.differentialGeometry(at: curveParameter, tolerance: tolerance)
        let tangent = (frame.tangentU * geometry.firstDerivative.x)
            + (frame.tangentV * geometry.firstDerivative.y)
        try tangent.validate()
        let length = tangent.length
        guard length.isFinite else {
            throw GeometryError.invalidVectorLength(length)
        }
        guard length > tolerance.distance else {
            return nil
        }
        return tangent / length
    }

    private func representativeFrame(
        for reference: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceQueryFrame {
        let resolved = try surfaceQueryEvaluator.resolve(reference, in: document)
        if let centroid = centroidOfFace(resolved.faceID, in: document) {
            return try surfaceQueryEvaluator.closestPoint(
                to: centroid,
                on: reference,
                in: document
            ).frame
        }
        let parameter = try midpointParameter(on: resolved.surface, reference: reference)
        return try surfaceQueryEvaluator.frame(at: parameter, in: document)
    }

    private func centroidOfFace(_ faceID: FaceID, in document: EvaluatedDocument) -> Point3D? {
        guard let face = document.brep.faces[faceID] else {
            return nil
        }
        var points: [Point3D] = []
        for loopID in face.loops {
            guard let loop = document.brep.loops[loopID] else {
                continue
            }
            for orientedEdge in loop.edges {
                guard let edge = document.brep.edges[orientedEdge.edgeID] else {
                    continue
                }
                let vertexID = startVertexID(for: orientedEdge, edge: edge)
                guard let vertex = document.brep.vertices[vertexID] else {
                    continue
                }
                points.append(vertex.point)
            }
        }
        guard points.isEmpty == false else {
            return nil
        }
        let scale = 1.0 / Double(points.count)
        let sum = points.reduce((x: 0.0, y: 0.0, z: 0.0)) { partial, point in
            (
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        return Point3D(x: sum.x * scale, y: sum.y * scale, z: sum.z * scale)
    }

    private func midpointParameter(
        on surface: Surface3D,
        reference: SurfaceReference
    ) throws -> SurfaceParameterReference {
        SurfaceParameterReference(
            surface: reference,
            u: try midpoint(of: surface.uDomain),
            v: try midpoint(of: surface.vDomain)
        )
    }

    private func midpoint(of domain: ParameterDomain) throws -> Double {
        switch domain {
        case .unbounded:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Unbounded surface selection requires face topology to define a representative point."
            )
        case let .closed(lower, upper):
            return (lower + upper) * 0.5
        case let .periodic(period):
            return period * 0.5
        }
    }

    private func trimTangent(
        from parameterCurve: SurfaceParameterCurve,
        on surface: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> Vector3D {
        let lowerFraction = 0.5 - 1.0e-5
        let upperFraction = 0.5 + 1.0e-5
        let lower = try parameterCurve.parameter(atNormalizedFraction: lowerFraction, tolerance: tolerance)
        let upper = try parameterCurve.parameter(atNormalizedFraction: upperFraction, tolerance: tolerance)
        let lowerFrame = try surfaceQueryEvaluator.frame(
            at: SurfaceParameterReference(surface: surface, u: lower.u, v: lower.v),
            in: document
        )
        let upperFrame = try surfaceQueryEvaluator.frame(
            at: SurfaceParameterReference(surface: surface, u: upper.u, v: upper.v),
            in: document
        )
        return try (upperFrame.point - lowerFrame.point).normalized(tolerance: tolerance.distance)
    }

    private func measurementPoint(
        from point: CurveQueryPoint,
        selection: SelectionReference
    ) throws -> SelectionMeasurementPoint {
        SelectionMeasurementPoint(
            selection: selection,
            point: point.point,
            tangent: point.tangent,
            curvature: point.curvature
        )
    }

    private func projectedCurveDistance(
        from first: SelectionReference,
        to second: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionDistanceMeasurement? {
        if case .curve(.whole(let curve)) = first,
           try supportsProjectionDistancePoint(second, in: document) {
            let secondPoint = try point(for: second, in: document)
            let projection = try curveQueryEvaluator.closestPoint(
                to: secondPoint.point,
                on: curve,
                in: document
            )
            let firstPoint = try measurementPoint(from: projection.queryPoint, selection: first)
            return try SelectionDistanceMeasurement(first: firstPoint, second: secondPoint)
        }
        if case .curve(.whole(let curve)) = second,
           try supportsProjectionDistancePoint(first, in: document) {
            let firstPoint = try point(for: first, in: document)
            let projection = try curveQueryEvaluator.closestPoint(
                to: firstPoint.point,
                on: curve,
                in: document
            )
            let secondPoint = try measurementPoint(from: projection.queryPoint, selection: second)
            return try SelectionDistanceMeasurement(first: firstPoint, second: secondPoint)
        }
        return nil
    }

    private func supportsProjectionDistancePoint(
        _ selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> Bool {
        switch selection {
        case let .subshape(stableReference):
            let topologyReference = try document.topologyReference(for: stableReference)
            if case .vertex = topologyReference { return true }
            return false
        case .sketchPoint:
            return true
        case let .edge(edge):
            if case .parameter = edge {
                return true
            }
            return false
        case let .curve(curve):
            switch curve {
            case .parameter, .center, .controlPoint, .knot:
                return true
            case .whole, .span:
                return false
            }
        case let .surface(surface):
            switch surface {
            case .parameter, .controlPoint, .trimSpan, .trimKnot:
                return true
            case .whole, .span, .knot, .trim:
                return false
            }
        }
    }

    private func measurementPoint(
        from frame: SurfaceQueryFrame,
        selection: SelectionReference
    ) throws -> SelectionMeasurementPoint {
        SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            normal: frame.normal,
            curvature: frame.meanCurvature
        )
    }

    private func resolveSketchPoint(
        _ point: SketchPoint,
        parameters: ResolvedParameterTable
    ) throws -> Point2D {
        let resolver = ParameterResolver()
        let x = try resolver.evaluate(point.x, parameters: parameters, variables: [:])
        let y = try resolver.evaluate(point.y, parameters: parameters, variables: [:])
        guard x.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "selection.sketchPoint.x",
                expected: .length,
                actual: x.kind
            )
        }
        guard y.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "selection.sketchPoint.y",
                expected: .length,
                actual: y.kind
            )
        }
        guard x.value.isFinite else {
            throw GeometryError.invalidCoordinate(x.value)
        }
        guard y.value.isFinite else {
            throw GeometryError.invalidCoordinate(y.value)
        }
        return Point2D(x: x.value, y: y.value)
    }

    private func mapTo3D(_ point: Point2D, on plane: SketchPlane) throws -> Point3D {
        switch plane {
        case .xy:
            return Point3D(x: point.x, y: point.y, z: 0.0)
        case .yz:
            return Point3D(x: 0.0, y: point.x, z: point.y)
        case .zx:
            return Point3D(x: point.y, y: 0.0, z: point.x)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return plane.origin + (u * point.x) + (v * point.y)
        }
    }

    private func startVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }
}
