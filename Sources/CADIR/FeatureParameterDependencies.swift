import CADCore

public extension FeatureOperation {
    var referencedParameterIDs: Set<ParameterID> {
        switch self {
        case let .sketch(sketch):
            return sketch.referencedParameterIDs
        case let .extrude(extrude):
            return extrude.distance.referencedParameterIDs
        case let .revolve(revolve):
            return revolve.angle.referencedParameterIDs
        case let .sweep(sweep):
            return sweep.options.twistAngle.referencedParameterIDs
                .union(sweep.options.endScale.referencedParameterIDs)
                .union(sweep.options.distanceFraction.referencedParameterIDs)
        case let .faceLoopOffset(offset):
            return offset.distance.referencedParameterIDs
        case let .edgeOffset(offset):
            return offset.distance.referencedParameterIDs
        case let .faceDraft(draft):
            return draft.angle.referencedParameterIDs
        case let .curveOffset(offset):
            return offset.distance.referencedParameterIDs
        case .loft,
             .boolean,
             .polySpline,
             .bSplineSurface,
             .faceKnife,
             .faceDelete,
             .bridgeCurve,
             .curveEdit,
             .curveTrim:
            return []
        }
    }
}

public extension Sketch {
    var referencedParameterIDs: Set<ParameterID> {
        let entityParameterIDs = entities.values.reduce(into: Set<ParameterID>()) { result, entity in
            result.formUnion(entity.referencedParameterIDs)
        }
        return dimensions.reduce(into: entityParameterIDs) { result, dimension in
            result.formUnion(dimension.referencedParameterIDs)
        }
    }
}

public extension SketchEntity {
    var referencedParameterIDs: Set<ParameterID> {
        switch self {
        case let .point(point):
            return point.referencedParameterIDs
        case let .line(line):
            return line.start.referencedParameterIDs.union(line.end.referencedParameterIDs)
        case let .circle(circle):
            return circle.center.referencedParameterIDs.union(circle.radius.referencedParameterIDs)
        case let .arc(arc):
            return arc.center.referencedParameterIDs
                .union(arc.radius.referencedParameterIDs)
                .union(arc.startAngle.referencedParameterIDs)
                .union(arc.endAngle.referencedParameterIDs)
        case let .spline(spline):
            return spline.controlPoints.reduce(into: Set<ParameterID>()) { result, point in
                result.formUnion(point.referencedParameterIDs)
            }
        }
    }
}

public extension SketchPoint {
    var referencedParameterIDs: Set<ParameterID> {
        x.referencedParameterIDs.union(y.referencedParameterIDs)
    }
}

public extension SketchDimension {
    var referencedParameterIDs: Set<ParameterID> {
        switch self {
        case let .distance(_, _, value),
             let .angle(_, _, value),
             let .radius(_, value),
             let .diameter(_, value):
            return value.referencedParameterIDs
        }
    }
}
