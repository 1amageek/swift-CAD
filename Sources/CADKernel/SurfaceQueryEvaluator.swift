import Foundation
import CADCore
import CADIR
import CADTopology
import CADGeometry

public struct ResolvedSurface: Sendable, Hashable {
    public var reference: SurfaceReference
    public var faceID: FaceID
    public var surfaceID: SurfaceID
    public var surface: Surface3D

    public init(
        reference: SurfaceReference,
        faceID: FaceID,
        surfaceID: SurfaceID,
        surface: Surface3D
    ) {
        self.reference = reference
        self.faceID = faceID
        self.surfaceID = surfaceID
        self.surface = surface
    }
}

public struct SurfaceQueryFrame: Codable, Sendable, Hashable {
    public var reference: SurfaceParameterReference
    public var point: Point3D
    public var tangentU: Vector3D
    public var tangentV: Vector3D
    public var normal: Vector3D
    public var normalCurvatureU: Double
    public var normalCurvatureV: Double
    public var meanCurvature: Double
    public var gaussianCurvature: Double
    public var minimumPrincipalCurvature: Double
    public var maximumPrincipalCurvature: Double
    public var minimumPrincipalDirection: Vector3D
    public var maximumPrincipalDirection: Vector3D

    public init(
        reference: SurfaceParameterReference,
        geometry: Surface3D.DifferentialGeometry
    ) {
        self.reference = reference
        self.point = geometry.position
        self.tangentU = geometry.tangentU
        self.tangentV = geometry.tangentV
        self.normal = geometry.normal
        self.normalCurvatureU = geometry.normalCurvatureU
        self.normalCurvatureV = geometry.normalCurvatureV
        self.meanCurvature = geometry.meanCurvature
        self.gaussianCurvature = geometry.gaussianCurvature
        self.minimumPrincipalCurvature = geometry.minimumPrincipalCurvature
        self.maximumPrincipalCurvature = geometry.maximumPrincipalCurvature
        self.minimumPrincipalDirection = geometry.minimumPrincipalDirection
        self.maximumPrincipalDirection = geometry.maximumPrincipalDirection
    }
}

public struct SurfaceSpanQueryResult: Codable, Sendable, Hashable {
    public var reference: SurfaceSpanReference
    public var lowerParameter: Double
    public var upperParameter: Double

    public init(reference: SurfaceSpanReference, lowerParameter: Double, upperParameter: Double) {
        self.reference = reference
        self.lowerParameter = lowerParameter
        self.upperParameter = upperParameter
    }
}

public struct SurfaceTrimQueryResult: Codable, Sendable, Hashable {
    public var reference: SurfaceTrimReference
    public var loopID: LoopID
    public var edgeID: EdgeID
    public var curveID: CurveID
    public var orientation: Orientation
    public var parameterCurve: SurfaceParameterCurve
    public var startParameter: SurfaceParameter
    public var endParameter: SurfaceParameter

    public init(
        reference: SurfaceTrimReference,
        loopID: LoopID,
        edgeID: EdgeID,
        curveID: CurveID,
        orientation: Orientation,
        parameterCurve: SurfaceParameterCurve,
        startParameter: SurfaceParameter,
        endParameter: SurfaceParameter
    ) {
        self.reference = reference
        self.loopID = loopID
        self.edgeID = edgeID
        self.curveID = curveID
        self.orientation = orientation
        self.parameterCurve = parameterCurve
        self.startParameter = startParameter
        self.endParameter = endParameter
    }
}

public struct SurfaceProjectionOptions: Sendable, Hashable {
    public var limits: ProjectionResourceLimits
    public var respectsTrimBounds: Bool

    public init(
        limits: ProjectionResourceLimits = ProjectionResourceLimits(),
        respectsTrimBounds: Bool = true
    ) {
        self.limits = limits
        self.respectsTrimBounds = respectsTrimBounds
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
    }
}

public struct SurfaceProjectionResult: Codable, Sendable, Hashable {
    public var sourcePoint: Point3D
    public var parameterReference: SurfaceParameterReference
    public var projectedPoint: Point3D
    public var residual: Vector3D
    public var distance: Double
    public var frame: SurfaceQueryFrame
    public var iterations: Int
    public var converged: Bool

    public init(
        sourcePoint: Point3D,
        frame: SurfaceQueryFrame,
        iterations: Int,
        converged: Bool
    ) {
        self.sourcePoint = sourcePoint
        self.parameterReference = frame.reference
        self.projectedPoint = frame.point
        self.residual = sourcePoint - frame.point
        self.distance = self.residual.length
        self.frame = frame
        self.iterations = iterations
        self.converged = converged
    }
}

public enum SurfaceDirectionalProjectionRange: Sendable, Hashable {
    case line
    case ray

    fileprivate func accepts(_ signedDistance: Double, tolerance: ModelingTolerance) -> Bool {
        switch self {
        case .line:
            return true
        case .ray:
            return signedDistance >= -tolerance.distance
        }
    }
}

public struct SurfaceDirectionalProjectionOptions: Sendable, Hashable {
    public var limits: ProjectionResourceLimits
    public var range: SurfaceDirectionalProjectionRange
    public var respectsTrimBounds: Bool

    public init(
        limits: ProjectionResourceLimits = ProjectionResourceLimits(),
        range: SurfaceDirectionalProjectionRange = .line,
        respectsTrimBounds: Bool = true
    ) {
        self.limits = limits
        self.range = range
        self.respectsTrimBounds = respectsTrimBounds
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
    }
}

public struct SurfaceDirectionalProjectionResult: Codable, Sendable, Hashable {
    public var sourcePoint: Point3D
    public var direction: Vector3D
    public var signedDistanceAlongDirection: Double
    public var linePoint: Point3D
    public var parameterReference: SurfaceParameterReference
    public var projectedPoint: Point3D
    public var lineResidual: Vector3D
    public var lineDistance: Double
    public var frame: SurfaceQueryFrame
    public var iterations: Int
    public var converged: Bool

    public init(
        sourcePoint: Point3D,
        direction: Vector3D,
        signedDistanceAlongDirection: Double,
        frame: SurfaceQueryFrame,
        iterations: Int,
        converged: Bool
    ) {
        self.sourcePoint = sourcePoint
        self.direction = direction
        self.signedDistanceAlongDirection = signedDistanceAlongDirection
        self.linePoint = sourcePoint + direction * signedDistanceAlongDirection
        self.parameterReference = frame.reference
        self.projectedPoint = frame.point
        self.lineResidual = frame.point - self.linePoint
        self.lineDistance = self.lineResidual.length
        self.frame = frame
        self.iterations = iterations
        self.converged = converged
    }
}

public struct SurfaceQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let faceDomainResolver: any FaceQueryDomainResolving

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        faceDomainResolver = DefaultFaceQueryDomainResolver()
    }

    init(
        tolerance: ModelingTolerance,
        faceDomainResolver: any FaceQueryDomainResolving
    ) {
        self.tolerance = tolerance
        self.faceDomainResolver = faceDomainResolver
    }

    public func resolve(
        _ reference: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> ResolvedSurface {
        try reference.validate()
        let topologyReference = try document.topologyReference(for: reference.subshape)
        guard case let .face(faceID) = topologyReference else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                subshapeID: reference.subshape.subshapeID,
                tolerance: tolerance,
                message: "Stable surface reference did not resolve to a face."
            )
        }
        guard let face = document.brep.faces[faceID] else {
            throw FeatureEvaluationError.missingInput("Surface query references a missing face.")
        }
        guard let surface = document.brep.geometry.surfaces[face.surfaceID] else {
            throw FeatureEvaluationError.missingInput("Surface query references a missing surface.")
        }
        try surface.validate(tolerance: tolerance)
        return ResolvedSurface(
            reference: reference,
            faceID: faceID,
            surfaceID: face.surfaceID,
            surface: surface
        )
    }

    public func frame(
        at reference: SurfaceParameterReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceQueryFrame {
        try reference.validate()
        let resolved = try resolve(reference.surface, in: document)
        guard try resolved.surface.uDomain.contains(reference.u, tolerance: tolerance),
              try resolved.surface.vDomain.contains(reference.v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let geometry = try resolved.surface.differentialGeometry(
            atU: reference.u,
            v: reference.v,
            tolerance: tolerance
        )
        return SurfaceQueryFrame(reference: reference, geometry: geometry)
    }

    public func closestPoint(
        to point: Point3D,
        on reference: SurfaceReference,
        in document: EvaluatedDocument,
        options: SurfaceProjectionOptions = SurfaceProjectionOptions()
    ) throws -> SurfaceProjectionResult {
        try point.validate()
        try options.validate(tolerance: tolerance)
        let resolved = try resolve(reference, in: document)
        var unrestrictedOptions = options
        unrestrictedOptions.respectsTrimBounds = false
        let supportProjection: SurfaceProjectionResult = switch resolved.surface {
        case let .plane(plane):
            try closestPointOnPlane(
                point,
                plane: plane,
                resolved: resolved,
                model: document.brep,
                options: unrestrictedOptions
            )
        case let .cylinder(cylinder):
            try closestPointOnCylinder(
                point,
                cylinder: cylinder,
                reference: reference
            )
        case let .analytic(surface):
            try closestPointOnAnalyticSurface(
                point,
                surface: surface,
                resolved: resolved,
                model: document.brep,
                options: unrestrictedOptions
            )
        case let .bSpline(surface):
            try closestPointOnBSpline(
                point,
                surface: surface,
                reference: reference,
                options: unrestrictedOptions
            )
        case let .procedural(.offset(offset)):
            try closestPointOnProceduralOffset(
                point,
                offset: offset,
                resolved: resolved,
                model: document.brep,
                options: unrestrictedOptions
            )
        case let .procedural(.ruled(ruled)):
            try closestPointOnProceduralRuled(
                point,
                ruled: ruled,
                resolved: resolved,
                options: unrestrictedOptions
            )
        }
        guard options.respectsTrimBounds else {
            return supportProjection
        }
        let containment = try faceDomainResolver.makeContainmentSession(
            for: resolved.faceID,
            in: document.brep,
            tolerance: tolerance
        )
        let supportParameter = SurfaceParameter(
            u: supportProjection.parameterReference.u,
            v: supportProjection.parameterReference.v
        )
        if try containment.contains(
            supportParameter,
            on: resolved.faceID
        ) {
            return supportProjection
        }
        let boundary = try faceDomainResolver.closestBoundaryProjection(
            to: point,
            from: supportParameter,
            on: resolved.faceID,
            surface: resolved.surface,
            in: document.brep,
            maximumIterations: options.limits.maximumIterations,
            tolerance: tolerance
        )
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: reference,
                u: boundary.parameter.u,
                v: boundary.parameter.v
            ),
            surface: resolved.surface,
            iterations: boundary.iterations,
            converged: true
        )
    }

    public func project(
        _ point: Point3D,
        along direction: Vector3D,
        onto reference: SurfaceReference,
        in document: EvaluatedDocument,
        options: SurfaceDirectionalProjectionOptions = SurfaceDirectionalProjectionOptions()
    ) throws -> SurfaceDirectionalProjectionResult {
        try point.validate()
        try options.validate(tolerance: tolerance)
        let unitDirection = try direction.normalized(tolerance: tolerance.distance)
        let resolved = try resolve(reference, in: document)
        switch resolved.surface {
        case let .plane(plane):
            return try projectOntoPlane(
                point,
                direction: unitDirection,
                plane: plane,
                resolved: resolved,
                model: document.brep,
                options: options
            )
        case let .cylinder(cylinder):
            return try projectOntoCylinder(
                point,
                direction: unitDirection,
                cylinder: cylinder,
                reference: reference,
                range: options.range
            )
        case let .analytic(surface):
            return try projectOntoAnalyticSurface(
                point,
                direction: unitDirection,
                surface: surface,
                resolved: resolved,
                model: document.brep,
                options: options
            )
        case .bSpline:
            return try projectOntoGeneralSurface(
                point,
                direction: unitDirection,
                surface: resolved.surface,
                resolved: resolved,
                model: document.brep,
                options: options
            )
        case let .procedural(.offset(offset)):
            return try projectOntoProceduralOffset(
                point,
                direction: unitDirection,
                offset: offset,
                resolved: resolved,
                model: document.brep,
                options: options
            )
        case .procedural(.ruled):
            return try projectOntoGeneralSurface(
                point,
                direction: unitDirection,
                surface: resolved.surface,
                resolved: resolved,
                model: document.brep,
                options: options
            )
        }
    }

    public func controlPoint(
        _ reference: SurfaceControlPointReference,
        in document: EvaluatedDocument
    ) throws -> Point3D {
        try reference.validate()
        let surface = try exactBSpline(for: reference.surface, in: document)
        guard reference.vIndex < surface.controlPoints.count else {
            throw FeatureEvaluationError.missingInput("Surface control point V index could not be resolved.")
        }
        guard reference.uIndex < surface.controlPoints[reference.vIndex].count else {
            throw FeatureEvaluationError.missingInput("Surface control point U index could not be resolved.")
        }
        return surface.controlPoints[reference.vIndex][reference.uIndex]
    }

    public func knot(
        _ reference: SurfaceKnotReference,
        in document: EvaluatedDocument
    ) throws -> Double {
        try reference.validate()
        let surface = try exactBSpline(for: reference.surface, in: document)
        let knots = knotVector(for: reference.direction, surface: surface)
        guard reference.knotIndex < knots.count else {
            throw FeatureEvaluationError.missingInput("Surface knot index could not be resolved.")
        }
        return knots[reference.knotIndex]
    }

    public func span(
        _ reference: SurfaceSpanReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceSpanQueryResult {
        try reference.validate()
        let surface = try exactBSpline(for: reference.surface, in: document)
        let knots = knotVector(for: reference.direction, surface: surface)
        let degree = degree(for: reference.direction, surface: surface)
        var ordinal = 0
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        guard lowerIndex < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Surface has no queryable knot spans.")
        }
        for index in lowerIndex..<upperIndex {
            let lower = knots[index]
            let upper = knots[index + 1]
            guard upper - lower > tolerance.distance else {
                continue
            }
            if ordinal == reference.spanIndex {
                return SurfaceSpanQueryResult(
                    reference: reference,
                    lowerParameter: lower,
                    upperParameter: upper
                )
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Surface span index could not be resolved.")
    }

    public func trimCurve(
        _ reference: SurfaceTrimReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceTrimQueryResult {
        try reference.validate()
        let resolved = try resolve(reference.surface, in: document)
        guard let face = document.brep.faces[resolved.faceID] else {
            throw FeatureEvaluationError.missingInput("Surface trim query references a missing face.")
        }
        guard face.loops.indices.contains(reference.loopIndex) else {
            throw FeatureEvaluationError.missingInput("Surface trim loop index could not be resolved.")
        }
        let loopID = face.loops[reference.loopIndex]
        guard let loop = document.brep.loops[loopID] else {
            throw FeatureEvaluationError.missingInput("Surface trim query references a missing loop.")
        }
        guard loop.edges.indices.contains(reference.edgeIndex) else {
            throw FeatureEvaluationError.missingInput("Surface trim edge index could not be resolved.")
        }
        let orientedEdge = loop.edges[reference.edgeIndex]
        guard let edge = document.brep.edges[orientedEdge.edgeID],
              let curve = document.brep.geometry.curves[edge.curveID] else {
            throw FeatureEvaluationError.missingInput("Surface trim query references missing edge geometry.")
        }
        guard let startPoint = document.brep.vertices[startVertexID(for: orientedEdge, edge: edge)]?.point,
              let endPoint = document.brep.vertices[endVertexID(for: orientedEdge, edge: edge)]?.point else {
            throw FeatureEvaluationError.missingInput("Surface trim query references missing edge vertices.")
        }
        let parameters = try trimParameters(
            for: edge,
            orientedEdge: orientedEdge,
            curve: curve,
            surface: resolved.surface,
            startPoint: startPoint,
            endPoint: endPoint
        )
        try parameters.curve.validate(on: resolved.surface, tolerance: tolerance)
        return SurfaceTrimQueryResult(
            reference: reference,
            loopID: loopID,
            edgeID: edge.id,
            curveID: edge.curveID,
            orientation: orientedEdge.orientation,
            parameterCurve: parameters.curve,
            startParameter: parameters.start,
            endParameter: parameters.end
        )
    }

    private func exactBSpline(
        for reference: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> BSplineSurface3D {
        let resolved = try resolve(reference, in: document)
        guard case let .bSpline(surface) = resolved.surface else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface control-point, knot, and span selections require an exact B-spline surface."
            )
        }
        return surface
    }

    private func trimParameters(
        for edge: Edge,
        orientedEdge: Coedge,
        curve: Curve3D,
        surface: Surface3D,
        startPoint: Point3D,
        endPoint: Point3D
    ) throws -> (curve: SurfaceParameterCurve, start: SurfaceParameter, end: SurfaceParameter) {
        if let surfaceParameterCurve = orientedEdge.surfaceParameterCurve {
            return try exactTrimParameters(
                surfaceParameterCurve,
                on: surface,
                curve: curve,
                edge: edge,
                orientedEdge: orientedEdge,
                startPoint: startPoint,
                endPoint: endPoint
            )
        }

        let start = try surfaceParameter(for: startPoint, on: surface)
        let end = try surfaceParameter(for: endPoint, on: surface)

        if case .line = curve {
            return (compactParameterCurve(from: start, to: end), start, end)
        }

        guard let trim = edge.trim else {
            return (compactParameterCurve(from: start, to: end), start, end)
        }

        let startCurveParameter: Double
        let endCurveParameter: Double
        switch orientedEdge.orientation {
        case .forward:
            startCurveParameter = trim.startParameter
            endCurveParameter = trim.endParameter
        case .reversed:
            startCurveParameter = trim.endParameter
            endCurveParameter = trim.startParameter
        }

        let sampleCount = 17
        var points: [SurfaceParameter] = []
        points.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount - 1)
            let curveParameter = startCurveParameter + (endCurveParameter - startCurveParameter) * fraction
            let point = try curve.point(at: curveParameter, tolerance: tolerance)
            points.append(try surfaceParameter(for: point, on: surface))
        }
        return (.polyline(points), start, end)
    }

    private func exactTrimParameters(
        _ parameterCurve: SurfaceParameterCurve,
        on surface: Surface3D,
        curve: Curve3D,
        edge: Edge,
        orientedEdge: Coedge,
        startPoint: Point3D,
        endPoint: Point3D
    ) throws -> (curve: SurfaceParameterCurve, start: SurfaceParameter, end: SurfaceParameter) {
        try parameterCurve.validate(on: surface, tolerance: tolerance)
        let start = try parameterCurve.parameter(atNormalizedFraction: 0.0, tolerance: tolerance)
        let end = try parameterCurve.parameter(atNormalizedFraction: 1.0, tolerance: tolerance)
        let surfaceStart = try surface.point(u: start.u, v: start.v, tolerance: tolerance)
        let surfaceEnd = try surface.point(u: end.u, v: end.v, tolerance: tolerance)
        guard startPoint.isApproximatelyEqual(to: surfaceStart, tolerance: tolerance.distance),
              endPoint.isApproximatelyEqual(to: surfaceEnd, tolerance: tolerance.distance) else {
            throw FeatureEvaluationError.invalidGraph("Surface trim parameter curve endpoints do not match edge vertices.")
        }
        try validateExactTrimSamples(
            parameterCurve,
            on: surface,
            curve: curve,
            edge: edge,
            orientedEdge: orientedEdge,
            startPoint: startPoint,
            endPoint: endPoint
        )
        return (parameterCurve, start, end)
    }

    private func validateExactTrimSamples(
        _ parameterCurve: SurfaceParameterCurve,
        on surface: Surface3D,
        curve: Curve3D,
        edge: Edge,
        orientedEdge: Coedge,
        startPoint: Point3D,
        endPoint: Point3D
    ) throws {
        let startCurveParameter: Double
        let endCurveParameter: Double
        if let trim = edge.trim {
            switch orientedEdge.orientation {
            case .forward:
                startCurveParameter = trim.startParameter
                endCurveParameter = trim.endParameter
            case .reversed:
                startCurveParameter = trim.endParameter
                endCurveParameter = trim.startParameter
            }
        } else {
            startCurveParameter = 0.0
            endCurveParameter = 1.0
        }
        let sampleCount = 9
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount - 1)
            let curvePoint: Point3D
            if edge.trim != nil {
                let curveParameter = startCurveParameter + (endCurveParameter - startCurveParameter) * fraction
                curvePoint = try curve.point(at: curveParameter, tolerance: tolerance)
            } else {
                guard case .line = curve else {
                    throw FeatureEvaluationError.invalidGraph("Surface trim parameter curve requires a trimmed non-linear edge.")
                }
                curvePoint = interpolated(startPoint, endPoint, fraction: fraction)
            }
            let parameter = try parameterCurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
            let surfacePoint = try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
            guard curvePoint.isApproximatelyEqual(to: surfacePoint, tolerance: tolerance.distance) else {
                throw FeatureEvaluationError.invalidGraph("Surface trim parameter curve does not match edge geometry.")
            }
        }
    }

    private func interpolated(_ start: Point3D, _ end: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: start.z + (end.z - start.z) * fraction
        )
    }

    private func compactParameterCurve(
        from start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> SurfaceParameterCurve {
        if abs(start.u - end.u) <= tolerance.distance {
            return .constantU(u: start.u, vStart: start.v, vEnd: end.v)
        }
        if abs(start.v - end.v) <= tolerance.distance {
            return .constantV(v: start.v, uStart: start.u, uEnd: end.u)
        }
        return .polyline([start, end])
    }

    private func surfaceParameter(for point: Point3D, on surface: Surface3D) throws -> SurfaceParameter {
        switch surface {
        case let .plane(plane):
            return try planeParameter(for: point, on: plane)
        case let .cylinder(cylinder):
            return try cylinderParameter(for: point, on: cylinder)
        case let .analytic(surface):
            return try analyticSurfaceParameter(for: point, on: surface)
        case let .bSpline(surface):
            return try bSplineBoundaryParameter(for: point, on: surface)
        case .procedural:
            let projection = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return SurfaceParameter(u: projection.u, v: projection.v)
        }
    }

    private func closestPointOnProceduralOffset(
        _ point: Point3D,
        offset: OffsetSurface3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceProjectionOptions
    ) throws -> SurfaceProjectionResult {
        let proceduralSurface = Surface3D.procedural(.offset(offset))
        if let equivalent = try offset.exactSameParameterSurface(
            tolerance: tolerance
        ) {
            let equivalentResult: SurfaceProjectionResult
            switch equivalent {
            case let .plane(plane):
                equivalentResult = try closestPointOnPlane(
                    point,
                    plane: plane,
                    resolved: resolved,
                    model: model,
                    options: options
                )
            case let .cylinder(cylinder):
                equivalentResult = try closestPointOnCylinder(
                    point,
                    cylinder: cylinder,
                    reference: resolved.reference
                )
            case let .analytic(analytic):
                equivalentResult = try closestPointOnAnalyticSurface(
                    point,
                    surface: analytic,
                    resolved: resolved,
                    model: model,
                    options: options
                )
            case let .bSpline(spline):
                equivalentResult = try closestPointOnBSpline(
                    point,
                    surface: spline,
                    reference: resolved.reference,
                    options: options
                )
            case .procedural:
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Procedural closest-point reduction must terminate at a non-procedural surface."
                )
            }
            return try projectionResult(
                sourcePoint: point,
                reference: equivalentResult.parameterReference,
                surface: proceduralSurface,
                iterations: equivalentResult.iterations,
                converged: equivalentResult.converged
            )
        }
        let projection = try offset.closestParameterProjection(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: options.limits.maximumIterations,
                maximumSubdivisionDepth: options.limits.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.limits.maximumSubdivisionCells,
                maximumCandidateCount: options.limits.maximumCandidateCount
            ),
            tolerance: tolerance
        )
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: projection.u,
                v: projection.v
            ),
            surface: proceduralSurface,
            iterations: projection.iterations,
            converged: true
        )
    }

    private func closestPointOnProceduralRuled(
        _ point: Point3D,
        ruled: RuledSurface3D,
        resolved: ResolvedSurface,
        options: SurfaceProjectionOptions
    ) throws -> SurfaceProjectionResult {
        let surface = Surface3D.procedural(.ruled(ruled))
        let projection = try ruled.closestParameterProjection(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: options.limits.maximumIterations,
                maximumSubdivisionDepth: options.limits.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.limits.maximumSubdivisionCells,
                maximumCandidateCount: options.limits.maximumCandidateCount
            ),
            tolerance: tolerance
        )
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: projection.u,
                v: projection.v
            ),
            surface: surface,
            iterations: projection.iterations,
            converged: true
        )
    }

    private func projectOntoProceduralOffset(
        _ point: Point3D,
        direction: Vector3D,
        offset: OffsetSurface3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceDirectionalProjectionOptions
    ) throws -> SurfaceDirectionalProjectionResult {
        let proceduralSurface = Surface3D.procedural(.offset(offset))
        if let equivalent = try offset.exactSameParameterSurface(
            tolerance: tolerance
        ) {
            let equivalentResult: SurfaceDirectionalProjectionResult
            switch equivalent {
            case let .plane(plane):
                equivalentResult = try projectOntoPlane(
                    point,
                    direction: direction,
                    plane: plane,
                    resolved: resolved,
                    model: model,
                    options: options
                )
            case let .cylinder(cylinder):
                equivalentResult = try projectOntoCylinder(
                    point,
                    direction: direction,
                    cylinder: cylinder,
                    reference: resolved.reference,
                    range: options.range
                )
            case let .analytic(analytic):
                equivalentResult = try projectOntoAnalyticSurface(
                    point,
                    direction: direction,
                    surface: analytic,
                    resolved: resolved,
                    model: model,
                    options: options
                )
            case let .bSpline(spline):
                equivalentResult = try projectOntoGeneralSurface(
                    point,
                    direction: direction,
                    surface: .bSpline(spline),
                    resolved: resolved,
                    model: model,
                    options: options
                )
            case .procedural:
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Procedural directional reduction must terminate at a non-procedural surface."
                )
            }
            return try directionalProjectionResult(
                sourcePoint: point,
                direction: direction,
                signedDistanceAlongDirection: equivalentResult.signedDistanceAlongDirection,
                reference: equivalentResult.parameterReference,
                surface: proceduralSurface,
                iterations: equivalentResult.iterations,
                converged: equivalentResult.converged
            )
        }

        return try projectOntoGeneralSurface(
            point,
            direction: direction,
            surface: proceduralSurface,
            resolved: resolved,
            model: model,
            options: options
        )
    }

    private func projectOntoGeneralSurface(
        _ point: Point3D,
        direction: Vector3D,
        surface: Surface3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceDirectionalProjectionOptions
    ) throws -> SurfaceDirectionalProjectionResult {
        let searchDomain = try faceDomainResolver.directionalSearchDomain(
            from: point,
            direction: direction,
            on: resolved.faceID,
            in: model,
            tolerance: tolerance
        )
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: .line(Line3D(origin: point, direction: direction)),
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                curveRange: searchDomain.curve,
                surfaceURange: searchDomain.surface.u,
                surfaceVRange: searchDomain.surface.v,
                maximumSubdivisionDepth: options.limits.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.limits.maximumSubdivisionCells,
                maximumIterations: options.limits.maximumIterations,
                maximumCandidateCount: options.limits.maximumCandidateCount
            ),
            tolerance: tolerance
        )
        let containment = options.respectsTrimBounds
            ? try faceDomainResolver.makeContainmentSession(
                for: resolved.faceID,
                in: model,
                tolerance: tolerance
            )
            : nil
        var accepted: [CurveSurfaceIntersection] = []
        for intersection in intersections where options.range.accepts(
            intersection.curveParameter,
            tolerance: tolerance
        ) {
            if let containment,
               try containment.contains(
                   SurfaceParameter(
                       u: intersection.surfaceU,
                       v: intersection.surfaceV
                   ),
                   on: resolved.faceID
               ) == false {
                continue
            }
            accepted.append(intersection)
        }
        guard let selected = accepted.min(by: { lhs, rhs in
            switch options.range {
            case .line:
                abs(lhs.curveParameter) < abs(rhs.curveParameter)
            case .ray:
                lhs.curveParameter < rhs.curveParameter
            }
        }) else {
            throw FeatureEvaluationError.emptyResult(
                "Projection does not intersect the procedural face in the requested range."
            )
        }
        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: selected.curveParameter,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: selected.surfaceU,
                v: selected.surfaceV
            ),
            surface: surface,
            iterations: selected.iterations,
            converged: selected.residual <= tolerance.distance
        )
    }

    private func finiteInterval(
        _ domain: ParameterDomain
    ) throws -> ScalarInterval? {
        switch domain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            return nil
        }
    }

    private func analyticSurfaceParameter(
        for point: Point3D,
        on surface: AnalyticSurface3D
    ) throws -> SurfaceParameter {
        try surface.validate(tolerance: tolerance)
        switch surface {
        case let .plane(origin, normal):
            let offset = point - origin
            guard abs(offset.dot(normal)) <= tolerance.distance else {
                throw FeatureEvaluationError.emptyResult("Surface trim point is not on the analytic plane.")
            }
            let (basisU, basisV) = try analyticBasis(for: normal)
            return SurfaceParameter(u: offset.dot(basisU), v: offset.dot(basisV))
        case let .cylinder(origin, axis, radius):
            let offset = point - origin
            let parameter = try angularAxialParameter(offset: offset, axis: axis)
            let radial = offset - axis * parameter.v
            guard abs(radial.length - radius) <= tolerance.distance else {
                throw FeatureEvaluationError.emptyResult("Surface trim point is not on the analytic cylinder.")
            }
            return parameter
        case let .cone(apex, axis, halfAngle):
            let offset = point - apex
            let axialDistance = offset.dot(axis)
            let radial = offset - axis * axialDistance
            guard abs(radial.length - abs(axialDistance * tan(halfAngle))) <= tolerance.distance else {
                throw FeatureEvaluationError.emptyResult("Surface trim point is not on the analytic cone.")
            }
            let (basisU, basisV) = try analyticBasis(for: axis)
            let signedV = axialDistance / cos(halfAngle)
            let direction = signedV >= 0.0 ? radial : -radial
            let angle = direction.length > tolerance.distance
                ? normalizedAngle(atan2(direction.dot(basisV), direction.dot(basisU)))
                : 0.0
            return SurfaceParameter(u: angle, v: signedV)
        case let .sphere(center, radius):
            let offset = point - center
            guard abs(offset.length - radius) <= tolerance.distance else {
                throw FeatureEvaluationError.emptyResult("Surface trim point is not on the analytic sphere.")
            }
            let direction = try offset.normalized(tolerance: tolerance.distance)
            let (basisU, basisV) = try analyticBasis(for: .unitZ)
            return SurfaceParameter(
                u: normalizedAngle(atan2(direction.dot(basisV), direction.dot(basisU))),
                v: asin(min(max(direction.dot(.unitZ), -1.0), 1.0))
            )
        case let .torus(center, axis, majorRadius, minorRadius):
            let offset = point - center
            let axialDistance = offset.dot(axis)
            let radial = offset - axis * axialDistance
            let tubeDistance = hypot(radial.length - majorRadius, axialDistance)
            guard abs(tubeDistance - minorRadius) <= tolerance.distance else {
                throw FeatureEvaluationError.emptyResult("Surface trim point is not on the analytic torus.")
            }
            let (basisU, basisV) = try analyticBasis(for: axis)
            let radialDirection = radial.length > tolerance.distance
                ? try radial.normalized(tolerance: tolerance.distance)
                : basisU
            return SurfaceParameter(
                u: normalizedAngle(atan2(radialDirection.dot(basisV), radialDirection.dot(basisU))),
                v: normalizedAngle(atan2(axialDistance, radial.length - majorRadius))
            )
        }
    }

    private func planeParameter(for point: Point3D, on plane: Plane3D) throws -> SurfaceParameter {
        try plane.validate(tolerance: tolerance)
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let signedDistance = (point - plane.origin).dot(normal)
        guard abs(signedDistance) <= tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Surface trim point is not on the plane.")
        }
        let (basisU, basisV) = try planeBasis(for: normal)
        let offset = point - plane.origin
        return SurfaceParameter(u: offset.dot(basisU), v: offset.dot(basisV))
    }

    private func cylinderParameter(for point: Point3D, on cylinder: Cylinder3D) throws -> SurfaceParameter {
        try cylinder.validate(tolerance: tolerance)
        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let (radialU, radialV) = try planeBasis(for: axis)
        let offset = point - cylinder.origin
        let height = offset.dot(axis)
        let radialOffset = offset - axis * height
        guard abs(radialOffset.length - cylinder.radius) <= tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Surface trim point is not on the cylinder.")
        }
        let rawAngle = atan2(radialOffset.dot(radialV), radialOffset.dot(radialU))
        let angle = rawAngle >= 0.0 ? rawAngle : rawAngle + Double.pi * 2.0
        return SurfaceParameter(u: angle, v: height)
    }

    private func bSplineBoundaryParameter(
        for point: Point3D,
        on surface: BSplineSurface3D
    ) throws -> SurfaceParameter {
        try surface.validate(tolerance: tolerance)
        let uBounds = try parameterBounds(for: surface.uDomain)
        let vBounds = try parameterBounds(for: surface.vDomain)
        let corners = try [
            SurfaceBoundaryCorner(
                parameter: SurfaceParameter(u: uBounds.lower, v: vBounds.lower),
                point: surface.point(u: uBounds.lower, v: vBounds.lower, tolerance: tolerance)
            ),
            SurfaceBoundaryCorner(
                parameter: SurfaceParameter(u: uBounds.upper, v: vBounds.lower),
                point: surface.point(u: uBounds.upper, v: vBounds.lower, tolerance: tolerance)
            ),
            SurfaceBoundaryCorner(
                parameter: SurfaceParameter(u: uBounds.upper, v: vBounds.upper),
                point: surface.point(u: uBounds.upper, v: vBounds.upper, tolerance: tolerance)
            ),
            SurfaceBoundaryCorner(
                parameter: SurfaceParameter(u: uBounds.lower, v: vBounds.upper),
                point: surface.point(u: uBounds.lower, v: vBounds.upper, tolerance: tolerance)
            ),
        ]
        let segments = [
            (corners[0], corners[1]),
            (corners[1], corners[2]),
            (corners[2], corners[3]),
            (corners[3], corners[0]),
        ]

        var best: SurfaceBoundaryProjection?
        for segment in segments {
            let projection = boundaryProjection(point, from: segment.0, to: segment.1)
            if let currentBest = best {
                if projection.distance < currentBest.distance {
                    best = projection
                }
            } else {
                best = projection
            }
        }
        guard let best,
              best.distance <= tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Surface trim point is not on the B-spline boundary.")
        }
        return best.parameter
    }

    private func boundaryProjection(
        _ point: Point3D,
        from start: SurfaceBoundaryCorner,
        to end: SurfaceBoundaryCorner
    ) -> SurfaceBoundaryProjection {
        let segment = end.point - start.point
        let lengthSquared = segment.dot(segment)
        let fraction: Double
        if lengthSquared > 0.0 {
            fraction = min(max((point - start.point).dot(segment) / lengthSquared, 0.0), 1.0)
        } else {
            fraction = 0.0
        }
        let projectedPoint = start.point + segment * fraction
        return SurfaceBoundaryProjection(
            parameter: SurfaceParameter(
                u: start.parameter.u + (end.parameter.u - start.parameter.u) * fraction,
                v: start.parameter.v + (end.parameter.v - start.parameter.v) * fraction
            ),
            distance: (point - projectedPoint).length
        )
    }

    private func startVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }

    private func endVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.endVertexID
        case .reversed:
            return edge.startVertexID
        }
    }

    private func knotVector(
        for direction: SurfaceParameterDirection,
        surface: BSplineSurface3D
    ) -> [Double] {
        switch direction {
        case .u:
            return surface.uKnots
        case .v:
            return surface.vKnots
        }
    }

    private func degree(
        for direction: SurfaceParameterDirection,
        surface: BSplineSurface3D
    ) -> Int {
        switch direction {
        case .u:
            return surface.uDegree
        case .v:
            return surface.vDegree
        }
    }

    private func closestPointOnPlane(
        _ point: Point3D,
        plane: Plane3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceProjectionOptions
    ) throws -> SurfaceProjectionResult {
        try plane.validate(tolerance: tolerance)
        let (basisU, basisV) = try planeBasis(for: plane.normal)
        let offset = point - plane.origin
        let projected = PlanarTrimPoint2D(u: offset.dot(basisU), v: offset.dot(basisV))
        let resultPoint: PlanarTrimPoint2D
        if options.respectsTrimBounds,
           let trimDomain = try planarLineTrimDomain(
            for: resolved.faceID,
            plane: plane,
            model: model,
            basisU: basisU,
            basisV: basisV
           ),
           trimDomain.contains(projected, tolerance: tolerance) == false {
            resultPoint = trimDomain.closestBoundaryPoint(to: projected)
        } else {
            resultPoint = projected
        }
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: resultPoint.u,
                v: resultPoint.v
            ),
            surface: .plane(plane),
            iterations: 0,
            converged: true
        )
    }

    private func closestPointOnCylinder(
        _ point: Point3D,
        cylinder: Cylinder3D,
        reference: SurfaceReference
    ) throws -> SurfaceProjectionResult {
        try cylinder.validate(tolerance: tolerance)
        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let (radialU, radialV) = try planeBasis(for: axis)
        let offset = point - cylinder.origin
        let height = offset.dot(axis)
        let radialOffset = offset - axis * height
        let angle: Double
        if radialOffset.length > tolerance.distance {
            let rawAngle = atan2(radialOffset.dot(radialV), radialOffset.dot(radialU))
            angle = rawAngle >= 0.0 ? rawAngle : rawAngle + Double.pi * 2.0
        } else {
            angle = 0.0
        }
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(surface: reference, u: angle, v: height),
            surface: .cylinder(cylinder),
            iterations: 0,
            converged: true
        )
    }

    private func closestPointOnAnalyticSurface(
        _ point: Point3D,
        surface: AnalyticSurface3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceProjectionOptions
    ) throws -> SurfaceProjectionResult {
        try surface.validate(tolerance: tolerance)
        let parameter: SurfaceParameter
        switch surface {
        case let .plane(origin, normal):
            let (basisU, basisV) = try analyticBasis(for: normal)
            let offset = point - origin
            let projected = PlanarTrimPoint2D(u: offset.dot(basisU), v: offset.dot(basisV))
            if options.respectsTrimBounds,
               let trimDomain = try planarLineTrimDomain(
                for: resolved.faceID,
                plane: Plane3D(origin: origin, normal: normal),
                model: model,
                basisU: basisU,
                basisV: basisV
               ),
               trimDomain.contains(projected, tolerance: tolerance) == false {
                let boundary = trimDomain.closestBoundaryPoint(to: projected)
                parameter = SurfaceParameter(u: boundary.u, v: boundary.v)
            } else {
                parameter = SurfaceParameter(u: projected.u, v: projected.v)
            }
        case let .cylinder(origin, axis, _):
            let offset = point - origin
            parameter = try angularAxialParameter(offset: offset, axis: axis)
        case let .cone(apex, axis, halfAngle):
            let offset = point - apex
            let axialDistance = offset.dot(axis)
            let radial = offset - axis * axialDistance
            let (basisU, basisV) = try analyticBasis(for: axis)
            let radialDirection = radial.length > tolerance.distance
                ? try radial.normalized(tolerance: tolerance.distance)
                : basisU
            let positiveGenerator = radialDirection * sin(halfAngle) + axis * cos(halfAngle)
            let negativeGenerator = -radialDirection * sin(halfAngle) + axis * cos(halfAngle)
            let positiveV = offset.dot(positiveGenerator)
            let negativeV = offset.dot(negativeGenerator)
            let positiveDifference = offset - positiveGenerator * positiveV
            let negativeDifference = offset - negativeGenerator * negativeV
            let positiveResidual = positiveDifference.dot(positiveDifference)
            let negativeResidual = negativeDifference.dot(negativeDifference)
            if positiveResidual <= negativeResidual {
                parameter = SurfaceParameter(
                    u: normalizedAngle(atan2(radialDirection.dot(basisV), radialDirection.dot(basisU))),
                    v: positiveV
                )
            } else {
                parameter = SurfaceParameter(
                    u: normalizedAngle(atan2((-radialDirection).dot(basisV), (-radialDirection).dot(basisU))),
                    v: negativeV
                )
            }
        case let .sphere(center, _):
            let offset = point - center
            let direction = offset.length > tolerance.distance
                ? try offset.normalized(tolerance: tolerance.distance)
                : Vector3D.unitX
            let (basisU, basisV) = try analyticBasis(for: .unitZ)
            parameter = SurfaceParameter(
                u: normalizedAngle(atan2(direction.dot(basisV), direction.dot(basisU))),
                v: asin(min(max(direction.dot(.unitZ), -1.0), 1.0))
            )
        case let .torus(center, axis, majorRadius, _):
            let offset = point - center
            let axialDistance = offset.dot(axis)
            let radial = offset - axis * axialDistance
            let (basisU, basisV) = try analyticBasis(for: axis)
            let radialDirection = radial.length > tolerance.distance
                ? try radial.normalized(tolerance: tolerance.distance)
                : basisU
            parameter = SurfaceParameter(
                u: normalizedAngle(atan2(radialDirection.dot(basisV), radialDirection.dot(basisU))),
                v: normalizedAngle(atan2(axialDistance, radial.length - majorRadius))
            )
        }
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: parameter.u,
                v: parameter.v
            ),
            surface: .analytic(surface),
            iterations: 0,
            converged: true
        )
    }

    private func closestPointOnBSpline(
        _ point: Point3D,
        surface: BSplineSurface3D,
        reference: SurfaceReference,
        options: SurfaceProjectionOptions
    ) throws -> SurfaceProjectionResult {
        let projection = try surface.closestParameterProjection(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: options.limits.maximumIterations,
                maximumSubdivisionDepth: options.limits.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.limits.maximumSubdivisionCells,
                maximumCandidateCount: options.limits.maximumCandidateCount
            ),
            tolerance: tolerance
        )

        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: reference,
                u: projection.u,
                v: projection.v
            ),
            surface: .bSpline(surface),
            iterations: projection.iterations,
            converged: true
        )
    }

    private func projectOntoPlane(
        _ point: Point3D,
        direction: Vector3D,
        plane: Plane3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceDirectionalProjectionOptions
    ) throws -> SurfaceDirectionalProjectionResult {
        try plane.validate(tolerance: tolerance)
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let denominator = direction.dot(normal)
        guard abs(denominator) > tolerance.angle else {
            throw FeatureEvaluationError.emptyResult("Projection direction is parallel to the plane.")
        }
        let signedDistance = (plane.origin - point).dot(normal) / denominator
        guard options.range.accepts(signedDistance, tolerance: tolerance) else {
            throw FeatureEvaluationError.emptyResult("Projection target is outside the requested direction range.")
        }
        let projectedPoint = point + direction * signedDistance
        let (basisU, basisV) = try planeBasis(for: normal)
        let offset = projectedPoint - plane.origin
        let projected = PlanarTrimPoint2D(u: offset.dot(basisU), v: offset.dot(basisV))
        if options.respectsTrimBounds,
           let trimDomain = try planarLineTrimDomain(
            for: resolved.faceID,
            plane: plane,
            model: model,
            basisU: basisU,
            basisV: basisV
           ),
           trimDomain.contains(projected, tolerance: tolerance) == false {
            throw FeatureEvaluationError.emptyResult("Projection point lies outside the face trim bounds.")
        }
        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: signedDistance,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: projected.u,
                v: projected.v
            ),
            surface: .plane(plane),
            iterations: 0,
            converged: true
        )
    }

    private func projectOntoCylinder(
        _ point: Point3D,
        direction: Vector3D,
        cylinder: Cylinder3D,
        reference: SurfaceReference,
        range: SurfaceDirectionalProjectionRange
    ) throws -> SurfaceDirectionalProjectionResult {
        try cylinder.validate(tolerance: tolerance)
        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let (radialU, radialV) = try planeBasis(for: axis)
        let offset = point - cylinder.origin
        let radialPoint = offset - axis * offset.dot(axis)
        let radialDirection = direction - axis * direction.dot(axis)
        let quadraticA = radialDirection.dot(radialDirection)
        guard quadraticA > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Projection direction does not intersect the cylinder radius.")
        }
        let quadraticB = 2.0 * radialPoint.dot(radialDirection)
        let quadraticC = radialPoint.dot(radialPoint) - cylinder.radius * cylinder.radius
        let discriminant = quadraticB * quadraticB - 4.0 * quadraticA * quadraticC
        guard discriminant >= -tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Projection line does not intersect the cylinder.")
        }

        let root = sqrt(max(discriminant, 0.0))
        let denominator = 2.0 * quadraticA
        let candidates = [
            (-quadraticB - root) / denominator,
            (-quadraticB + root) / denominator,
        ].filter { value in
            value.isFinite && range.accepts(value, tolerance: tolerance)
        }
        guard let signedDistance = bestSignedDistance(candidates, range: range) else {
            throw FeatureEvaluationError.emptyResult("Cylinder projection is outside the requested direction range.")
        }

        let projectedPoint = point + direction * signedDistance
        let projectedOffset = projectedPoint - cylinder.origin
        let height = projectedOffset.dot(axis)
        let projectedRadial = projectedOffset - axis * height
        let rawAngle = atan2(projectedRadial.dot(radialV), projectedRadial.dot(radialU))
        let angle = rawAngle >= 0.0 ? rawAngle : rawAngle + Double.pi * 2.0
        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: signedDistance,
            reference: SurfaceParameterReference(surface: reference, u: angle, v: height),
            surface: .cylinder(cylinder),
            iterations: 0,
            converged: true
        )
    }

    private func projectOntoAnalyticSurface(
        _ point: Point3D,
        direction: Vector3D,
        surface: AnalyticSurface3D,
        resolved: ResolvedSurface,
        model: BRepModel,
        options: SurfaceDirectionalProjectionOptions
    ) throws -> SurfaceDirectionalProjectionResult {
        try surface.validate(tolerance: tolerance)
        let candidates: [Double]
        switch surface {
        case let .plane(origin, normal):
            let denominator = direction.dot(normal)
            guard abs(denominator) > tolerance.angle else {
                throw FeatureEvaluationError.emptyResult("Projection direction is parallel to the plane.")
            }
            candidates = [(origin - point).dot(normal) / denominator]
        case let .cylinder(origin, axis, radius):
            let offset = point - origin
            let radialPoint = offset - axis * offset.dot(axis)
            let radialDirection = direction - axis * direction.dot(axis)
            candidates = try quadraticRoots(
                a: radialDirection.dot(radialDirection),
                b: 2.0 * radialPoint.dot(radialDirection),
                c: radialPoint.dot(radialPoint) - radius * radius
            )
        case let .cone(apex, axis, halfAngle):
            let offset = point - apex
            let axialPoint = offset.dot(axis)
            let axialDirection = direction.dot(axis)
            let radialPoint = offset - axis * axialPoint
            let radialDirection = direction - axis * axialDirection
            let tangentSquared = pow(tan(halfAngle), 2.0)
            candidates = try quadraticRoots(
                a: radialDirection.dot(radialDirection) - axialDirection * axialDirection * tangentSquared,
                b: 2.0 * (
                    radialPoint.dot(radialDirection) - axialPoint * axialDirection * tangentSquared
                ),
                c: radialPoint.dot(radialPoint) - axialPoint * axialPoint * tangentSquared
            )
        case let .sphere(center, radius):
            let offset = point - center
            candidates = try quadraticRoots(
                a: direction.dot(direction),
                b: 2.0 * offset.dot(direction),
                c: offset.dot(offset) - radius * radius
            )
        case let .torus(center, axis, majorRadius, minorRadius):
            let offset = point - center
            let directionSquared = direction.dot(direction)
            let pointDirection = offset.dot(direction)
            let pointSquared = offset.dot(offset)
            let axialPoint = offset.dot(axis)
            let axialDirection = direction.dot(axis)
            let q0 = pointSquared + majorRadius * majorRadius - minorRadius * minorRadius
            let q1 = 2.0 * pointDirection
            let q2 = directionSquared
            let radial0 = pointSquared - axialPoint * axialPoint
            let radial1 = 2.0 * (pointDirection - axialPoint * axialDirection)
            let radial2 = directionSquared - axialDirection * axialDirection
            let majorFactor = 4.0 * majorRadius * majorRadius
            let coefficients = [
                q0 * q0 - majorFactor * radial0,
                2.0 * q0 * q1 - majorFactor * radial1,
                q1 * q1 + 2.0 * q0 * q2 - majorFactor * radial2,
                2.0 * q1 * q2,
                q2 * q2,
            ]
            candidates = try RealPolynomialRootSolver(
                rootTolerance: max(tolerance.distance * 0.001, Double.ulpOfOne * 64.0),
                residualTolerance: max(tolerance.angle * 0.001, Double.ulpOfOne * 64.0)
            ).realRoots(coefficients: coefficients)
        }
        let accepted = candidates.filter { candidate in
            candidate.isFinite && options.range.accepts(candidate, tolerance: tolerance)
        }
        guard let signedDistance = bestSignedDistance(accepted, range: options.range) else {
            throw FeatureEvaluationError.emptyResult(
                "Projection does not intersect the analytic surface in the requested range."
            )
        }
        let projectedPoint = point + direction * signedDistance
        let parameter = try analyticSurfaceParameter(for: projectedPoint, on: surface)

        if options.respectsTrimBounds,
           case let .plane(origin, normal) = surface {
            let (basisU, basisV) = try analyticBasis(for: normal)
            if let trimDomain = try planarLineTrimDomain(
                for: resolved.faceID,
                plane: Plane3D(origin: origin, normal: normal),
                model: model,
                basisU: basisU,
                basisV: basisV
            ), trimDomain.contains(
                PlanarTrimPoint2D(u: parameter.u, v: parameter.v),
                tolerance: tolerance
            ) == false {
                throw FeatureEvaluationError.emptyResult("Projection point lies outside the face trim bounds.")
            }
        }

        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: signedDistance,
            reference: SurfaceParameterReference(
                surface: resolved.reference,
                u: parameter.u,
                v: parameter.v
            ),
            surface: .analytic(surface),
            iterations: 0,
            converged: true
        )
    }

    private func projectionResult(
        sourcePoint: Point3D,
        reference: SurfaceParameterReference,
        surface: Surface3D,
        iterations: Int,
        converged: Bool
    ) throws -> SurfaceProjectionResult {
        let geometry = try surface.differentialGeometry(
            atU: reference.u,
            v: reference.v,
            tolerance: tolerance
        )
        let frame = SurfaceQueryFrame(reference: reference, geometry: geometry)
        return SurfaceProjectionResult(
            sourcePoint: sourcePoint,
            frame: frame,
            iterations: iterations,
            converged: converged
        )
    }

    private func directionalProjectionResult(
        sourcePoint: Point3D,
        direction: Vector3D,
        signedDistanceAlongDirection: Double,
        reference: SurfaceParameterReference,
        surface: Surface3D,
        iterations: Int,
        converged: Bool
    ) throws -> SurfaceDirectionalProjectionResult {
        guard converged else {
            throw KernelError(
                phase: .evaluation,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Surface directional projection did not produce a certified intersection."
            )
        }
        let geometry = try surface.differentialGeometry(
            atU: reference.u,
            v: reference.v,
            tolerance: tolerance
        )
        let frame = SurfaceQueryFrame(reference: reference, geometry: geometry)
        let result = SurfaceDirectionalProjectionResult(
            sourcePoint: sourcePoint,
            direction: direction,
            signedDistanceAlongDirection: signedDistanceAlongDirection,
            frame: frame,
            iterations: iterations,
            converged: true
        )
        guard result.lineDistance <= tolerance.distance else {
            throw KernelError(
                phase: .evaluation,
                code: .intersectionFailure,
                residual: result.lineDistance,
                tolerance: tolerance,
                message: "Surface directional projection exceeds the modeling tolerance."
            )
        }
        return result
    }

    private func parameterBounds(for domain: ParameterDomain) throws -> (lower: Double, upper: Double) {
        try domain.validate(tolerance: tolerance)
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case .unbounded, .periodic:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface projection requires finite bounded parameter domains."
            )
        }
    }

    private func bestSignedDistance(
        _ candidates: [Double],
        range: SurfaceDirectionalProjectionRange
    ) -> Double? {
        switch range {
        case .line:
            return candidates.min { lhs, rhs in
                abs(lhs) < abs(rhs)
            }
        case .ray:
            return candidates.min()
        }
    }

    private func planarLineTrimDomain(
        for faceID: FaceID,
        plane: Plane3D,
        model: BRepModel,
        basisU: Vector3D,
        basisV: Vector3D
    ) throws -> PlanarTrimDomain? {
        guard let face = model.faces[faceID] else {
            throw FeatureEvaluationError.missingInput("Surface trim query references a missing face.")
        }
        var loops: [PlanarTrimLoop] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw FeatureEvaluationError.missingInput("Surface trim query references a missing loop.")
            }
            for orientedEdge in loop.edges {
                guard let edge = model.edges[orientedEdge.edgeID],
                      let curve = model.geometry.curves[edge.curveID] else {
                    throw FeatureEvaluationError.missingInput("Surface trim query references missing edge geometry.")
                }
                guard case .line = curve else {
                    return nil
                }
            }
            let points = try model.orderedPoints(for: loopID)
            guard points.count >= 3 else {
                return nil
            }
            loops.append(PlanarTrimLoop(
                role: loop.role,
                points: points.map { point in
                    let offset = point - plane.origin
                    return PlanarTrimPoint2D(u: offset.dot(basisU), v: offset.dot(basisV))
                }
            ))
        }
        guard loops.contains(where: { $0.role == .outer }) else {
            return nil
        }
        return PlanarTrimDomain(loops: loops)
    }

    private func angularAxialParameter(
        offset: Vector3D,
        axis: Vector3D
    ) throws -> SurfaceParameter {
        let unitAxis = try axis.normalized(tolerance: tolerance.distance)
        let (basisU, basisV) = try analyticBasis(for: unitAxis)
        let axialDistance = offset.dot(unitAxis)
        let radial = offset - unitAxis * axialDistance
        let angle = radial.length > tolerance.distance
            ? normalizedAngle(atan2(radial.dot(basisV), radial.dot(basisU)))
            : 0.0
        return SurfaceParameter(u: angle, v: axialDistance)
    }

    private func analyticBasis(for normal: Vector3D) throws -> (Vector3D, Vector3D) {
        let unitNormal = try normal.normalized(tolerance: tolerance.distance)
        let reference = abs(unitNormal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
        let u = try unitNormal.cross(reference).normalized(tolerance: tolerance.distance)
        let v = try unitNormal.cross(u).normalized(tolerance: tolerance.distance)
        return (u, v)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func quadraticRoots(a: Double, b: Double, c: Double) throws -> [Double] {
        guard a.isFinite, b.isFinite, c.isFinite else {
            throw GeometryError.invalidDistance(a.isFinite ? (b.isFinite ? c : b) : a)
        }
        let coefficientTolerance = max(Double.ulpOfOne, tolerance.angle)
        if abs(a) <= coefficientTolerance {
            if abs(b) <= coefficientTolerance {
                return abs(c) <= tolerance.distance ? [0.0] : []
            }
            return [-c / b]
        }
        let discriminant = b * b - 4.0 * a * c
        let discriminantScale = max(1.0, max(abs(b * b), abs(4.0 * a * c)))
        let discriminantTolerance = tolerance.distance * discriminantScale
        guard discriminant >= -discriminantTolerance else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        if root <= coefficientTolerance {
            return [-b / (2.0 * a)]
        }
        let signedRoot = b >= 0.0 ? root : -root
        let q = -0.5 * (b + signedRoot)
        guard abs(q) > coefficientTolerance else {
            return [-b / (2.0 * a)]
        }
        return [q / a, c / q]
    }

    private func planeBasis(for normal: Vector3D) throws -> (Vector3D, Vector3D) {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalizedNormal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normalizedNormal).normalized(tolerance: tolerance.distance)
        let v = normalizedNormal.cross(u)
        return (u, v)
    }

}

private struct PlanarTrimDomain: Sendable, Hashable {
    var loops: [PlanarTrimLoop]

    func contains(_ point: PlanarTrimPoint2D, tolerance: ModelingTolerance) -> Bool {
        var insideOuter = false
        for loop in loops where loop.role == .outer {
            let containment = loop.containment(of: point, tolerance: tolerance)
            if containment.isOnBoundary {
                return true
            }
            if containment.isInside {
                insideOuter = true
            }
        }
        guard insideOuter else {
            return false
        }

        for loop in loops where loop.role == .inner {
            let containment = loop.containment(of: point, tolerance: tolerance)
            if containment.isOnBoundary {
                return true
            }
            if containment.isInside {
                return false
            }
        }
        return true
    }

    func closestBoundaryPoint(to point: PlanarTrimPoint2D) -> PlanarTrimPoint2D {
        var bestPoint = loops[0].closestBoundaryPoint(to: point)
        var bestDistance = bestPoint.squaredDistance(to: point)
        for loop in loops.dropFirst() {
            let candidate = loop.closestBoundaryPoint(to: point)
            let distance = candidate.squaredDistance(to: point)
            if distance < bestDistance {
                bestPoint = candidate
                bestDistance = distance
            }
        }
        return bestPoint
    }
}

private struct PlanarTrimLoop: Sendable, Hashable {
    var role: LoopRole
    var points: [PlanarTrimPoint2D]

    func containment(
        of point: PlanarTrimPoint2D,
        tolerance: ModelingTolerance
    ) -> PlanarTrimContainment {
        var isInside = false
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            if squaredDistance(point, toSegmentFrom: start, to: end) <= tolerance.distance * tolerance.distance {
                return PlanarTrimContainment(isInside: true, isOnBoundary: true)
            }
            let crosses = (start.v > point.v) != (end.v > point.v)
            if crosses {
                let intersectionU = start.u +
                    (point.v - start.v) * (end.u - start.u) / (end.v - start.v)
                if intersectionU > point.u {
                    isInside.toggle()
                }
            }
        }
        return PlanarTrimContainment(isInside: isInside, isOnBoundary: false)
    }

    func closestBoundaryPoint(to point: PlanarTrimPoint2D) -> PlanarTrimPoint2D {
        var bestPoint = closestPoint(point, toSegmentFrom: points[0], to: points[1])
        var bestDistance = bestPoint.squaredDistance(to: point)
        for index in points.indices {
            let candidate = closestPoint(
                point,
                toSegmentFrom: points[index],
                to: points[(index + 1) % points.count]
            )
            let distance = candidate.squaredDistance(to: point)
            if distance < bestDistance {
                bestPoint = candidate
                bestDistance = distance
            }
        }
        return bestPoint
    }

    private func closestPoint(
        _ point: PlanarTrimPoint2D,
        toSegmentFrom start: PlanarTrimPoint2D,
        to end: PlanarTrimPoint2D
    ) -> PlanarTrimPoint2D {
        let segmentU = end.u - start.u
        let segmentV = end.v - start.v
        let lengthSquared = segmentU * segmentU + segmentV * segmentV
        guard lengthSquared > 0.0 else {
            return start
        }
        let projection = ((point.u - start.u) * segmentU + (point.v - start.v) * segmentV) / lengthSquared
        let clampedProjection = min(max(projection, 0.0), 1.0)
        return PlanarTrimPoint2D(
            u: start.u + segmentU * clampedProjection,
            v: start.v + segmentV * clampedProjection
        )
    }

    private func squaredDistance(
        _ point: PlanarTrimPoint2D,
        toSegmentFrom start: PlanarTrimPoint2D,
        to end: PlanarTrimPoint2D
    ) -> Double {
        point.squaredDistance(to: closestPoint(point, toSegmentFrom: start, to: end))
    }
}

private struct PlanarTrimContainment: Sendable, Hashable {
    var isInside: Bool
    var isOnBoundary: Bool
}

private struct PlanarTrimPoint2D: Sendable, Hashable {
    var u: Double
    var v: Double

    func squaredDistance(to other: PlanarTrimPoint2D) -> Double {
        let deltaU = u - other.u
        let deltaV = v - other.v
        return deltaU * deltaU + deltaV * deltaV
    }
}


private struct SurfaceBoundaryCorner: Sendable, Hashable {
    var parameter: SurfaceParameter
    var point: Point3D
}

private struct SurfaceBoundaryProjection: Sendable, Hashable {
    var parameter: SurfaceParameter
    var distance: Double
}
