import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct BooleanFaceArrangementBoundary: Sendable {
    enum SurfaceSide: Sendable {
        case first
        case second
    }

    let reference: BooleanFaceSplitComponentReference
    let segmentOrdinal: Int
    let faceID: FaceID
    let edge: BRepSewingEdge
    let forwardLeftAction: BooleanRegionSelectionAction
    let forwardRightAction: BooleanRegionSelectionAction
    // A component must partition both faces of its pair or neither, so a
    // kept-kept face is forced to split when its twin face partitions.
    var forcedPartitioning: Bool = false

    var isPartitioning: Bool {
        forcedPartitioning || forwardLeftAction != forwardRightAction
    }

    static func make(
        reference: BooleanFaceSplitComponentReference,
        geometry: BooleanFaceSplitComponentGeometry,
        face: Face,
        surfaceSide: SurfaceSide,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> [BooleanFaceArrangementBoundary] {
        try tolerance.validate()
        if case .tangent = geometry { return [] }
        if case .coincident = geometry {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Coincident Boolean faces require explicit coincident-region ownership resolution."
            )
        }
        let actions = try resolvedActions(
            reference: reference,
            face: face,
            regionSelectionGraph: regionSelectionGraph,
            tolerance: tolerance
        )
        let edges: [BRepSewingEdge]
        switch geometry {
        case let .transverseSegment(start, end):
            edges = [try lineEdge(
                start: start,
                end: end,
                surfaceSide: surfaceSide,
                stableID: stableID(reference, faceID: face.id, segmentOrdinal: 0),
                parentSubshapeIDs: parentSubshapeIDs,
                tolerance: tolerance
            )]
        case let .trimmedCurve(chain):
            edges = try chain.segments.enumerated().map { segmentOrdinal, intersection in
                try trimmedIntersectionEdge(
                    intersection,
                    surfaceSide: surfaceSide,
                    stableID: stableID(
                        reference,
                        faceID: face.id,
                        segmentOrdinal: segmentOrdinal
                    ),
                    parentSubshapeIDs: parentSubshapeIDs,
                    tolerance: tolerance
                )
            }
        case let .closedCurve(intersection):
            edges = try closedIntersectionEdges(
                intersection,
                surfaceSide: surfaceSide,
                reference: reference,
                faceID: face.id,
                parentSubshapeIDs: parentSubshapeIDs,
                tolerance: tolerance
            )
        case .tangent, .coincident:
            return []
        }
        return edges.enumerated().map { segmentOrdinal, edge in
            BooleanFaceArrangementBoundary(
                reference: reference,
                segmentOrdinal: segmentOrdinal,
                faceID: face.id,
                edge: edge,
                forwardLeftAction: face.orientation == .forward
                    ? actions.positive
                    : actions.negative,
                forwardRightAction: face.orientation == .forward
                    ? actions.negative
                    : actions.positive
            )
        }
    }

    private static func resolvedActions(
        reference: BooleanFaceSplitComponentReference,
        face: Face,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        tolerance: ModelingTolerance
    ) throws -> (negative: BooleanRegionSelectionAction, positive: BooleanRegionSelectionAction) {
        let decisions = regionSelectionGraph.decisions.filter {
            $0.sample.facePair == reference.facePair
                && $0.sample.componentID == reference.componentID
                && $0.sample.sourceFaceID == face.id
        }
        guard decisions.count == 2,
              Set(decisions.map(\.sample.side)) == Set([.negative, .positive]),
              decisions.allSatisfy({ $0.action != .partitionBoundary }),
              let negativeAction = decisions.first(where: {
                  $0.sample.side == .negative
              })?.action,
              let positiveAction = decisions.first(where: {
                  $0.sample.side == .positive
              })?.action else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Each Boolean arrangement boundary requires resolved decisions on both face regions."
            )
        }
        return (negativeAction, positiveAction)
    }

    private static func lineEdge(
        start: BooleanUVPoint,
        end: BooleanUVPoint,
        surfaceSide: SurfaceSide,
        stableID: String,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let offset = end.point - start.point
        let length = offset.length
        let direction = try offset.normalized(tolerance: tolerance.distance)
        let startParameter = surfaceParameter(start, side: surfaceSide)
        let endParameter = surfaceParameter(end, side: surfaceSide)
        let parameterDirection = Point2D(
            x: (endParameter.u - startParameter.u) / length,
            y: (endParameter.v - startParameter.v) / length
        )
        guard hypot(parameterDirection.x, parameterDirection.y) > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A transverse Boolean segment is degenerate in face parameter space."
            )
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: start.point, direction: direction)),
            startParameter: 0.0,
            endParameter: length,
            startPoint: start.point,
            endPoint: end.point,
            surfaceParameterCurve: .affine(
                origin: Point2D(x: startParameter.u, y: startParameter.v),
                direction: parameterDirection,
                startParameter: 0.0,
                endParameter: length
            ),
            parentSubshapeIDs: parentSubshapeIDs
        )
    }

    private static func trimmedIntersectionEdge(
        _ intersection: BooleanTrimmedFaceIntersection,
        surfaceSide: SurfaceSide,
        stableID: String,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let pcurve = surfaceParameterCurve(
            intersection.intersection,
            side: surfaceSide
        )
        let curveDomain = intersection.intersection.curve.parameterDomain
        // A segment of a closed intersection curve can cross the periodic
        // seam, arriving with an end parameter below its start; lifting the
        // end by one period expresses the same span monotonically.
        var endParameter = intersection.endParameter
        if case let .periodic(period) = curveDomain,
           endParameter <= intersection.startParameter {
            endParameter += period
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: intersection.intersection.curve,
            startParameter: intersection.startParameter,
            endParameter: endParameter,
            startPoint: intersection.start.point,
            endPoint: intersection.end.point,
            surfaceParameterCurve: try pcurve.trimmed(
                from: intersection.startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ),
            parentSubshapeIDs: parentSubshapeIDs
        )
    }

    private static func closedIntersectionEdges(
        _ intersection: BooleanClosedFaceIntersection,
        surfaceSide: SurfaceSide,
        reference: BooleanFaceSplitComponentReference,
        faceID: FaceID,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingEdge] {
        let bounds = try parameterBounds(
            intersection.intersection.curve.parameterDomain,
            tolerance: tolerance
        )
        let midpoint = bounds.lower + (bounds.upper - bounds.lower) * 0.5
        let parameters = [(bounds.lower, midpoint), (midpoint, bounds.upper)]
        let curve = intersection.intersection.curve
        let pcurve = surfaceParameterCurve(intersection.intersection, side: surfaceSide)
        return try parameters.enumerated().map { segmentOrdinal, interval in
            let startPoint = try curve.point(at: interval.0, tolerance: tolerance)
            let endPoint = try curve.point(at: interval.1, tolerance: tolerance)
            return BRepSewingEdge(
                stableID: stableID(
                    reference,
                    faceID: faceID,
                    segmentOrdinal: segmentOrdinal
                ),
                curve: curve,
                startParameter: interval.0,
                endParameter: interval.1,
                startPoint: startPoint,
                endPoint: endPoint,
                surfaceParameterCurve: try pcurve.trimmed(
                    from: interval.0,
                    to: interval.1,
                    curveDomain: curve.parameterDomain,
                    tolerance: tolerance
                ),
                parentSubshapeIDs: parentSubshapeIDs
            )
        }
    }

    private static func surfaceParameterCurve(
        _ intersection: SurfaceSurfaceIntersectionCurve,
        side: SurfaceSide
    ) -> SurfaceParameterCurve {
        switch side {
        case .first:
            return intersection.firstSurfaceParameterCurve
        case .second:
            return intersection.secondSurfaceParameterCurve
        }
    }

    private static func surfaceParameter(
        _ point: BooleanUVPoint,
        side: SurfaceSide
    ) -> SurfaceParameter {
        switch side {
        case .first:
            return SurfaceParameter(u: point.targetU, v: point.targetV)
        case .second:
            return SurfaceParameter(u: point.toolU, v: point.toolV)
        }
    }

    private static func parameterBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case let .periodic(period):
            return (0.0, period)
        case .unbounded:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A closed Boolean arrangement cannot consume an unbounded curve."
            )
        }
    }

    private static func stableID(
        _ reference: BooleanFaceSplitComponentReference,
        faceID: FaceID,
        segmentOrdinal: Int
    ) -> String {
        "face-intersection:\(reference.facePair.targetFaceID):\(reference.facePair.toolFaceID):\(reference.componentID.ordinal):face:\(faceID):segment:\(segmentOrdinal)"
    }
}
