import CADCore
import CADGeometry
import CADIR
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): Native machining tests consume this patch
// builder, but no feature publishes it yet. Source-face trimming, end closure,
// volumetric validity and lineage must succeed before fillet integration.
package struct RollingBallBlendPatchBuilder {
    package enum TerminalBoundary {
        case start(BRepSewingEdge)
        case end(BRepSewingEdge)
    }

    package init() {}

    package func build(
        blend: RollingBallBlendSurface3D,
        stableID: String,
        orientation: Orientation,
        parentSubshapeIDs: [SubshapeID],
        retainingJunction junction: Double,
        terminal: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        try tolerance.validate()
        guard junction.isFinite, junction > 0, junction < 1,
              case .certifiedImplicit(let parameters) = terminal.surfaceParameterCurve else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "A terminal requires a native implicit boundary and an interior retained junction.")
        }
        let jet = try ImplicitCurveIntervalJetEncloser(
            intersection: parameters.intersection, tolerance: tolerance).parameterIntervalJet(
                of: parameters.intersection,
                over: ScalarInterval(lower: min(parameters.startFraction, parameters.endFraction),
                                     upper: max(parameters.startFraction, parameters.endFraction)),
                tolerance: tolerance)
        let bounds = jet[parameters.role == .first ? .firstU : .secondU].value
        let atStart: Bool
        if bounds.upper < junction - tolerance.relative {
            atStart = true
        } else if bounds.lower > junction + tolerance.relative {
            atStart = false
        } else {
            throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                message: "The whole terminal boundary must separate from the retained junction.")
        }
        let first = try terminal.surfaceParameterCurve.startParameter(tolerance: tolerance)
        let boundary = abs(first.v - (atStart ? 1 : 0)) <= tolerance.relative
            ? terminal : try BRepSewingPatchOrientationAdapter().reversed(terminal, tolerance: tolerance)
        return try build(blend: blend, stableID: stableID, orientation: orientation,
            parentSubshapeIDs: parentSubshapeIDs,
            uRange: ScalarInterval(lower: atStart ? 0 : junction, upper: atStart ? junction : 1),
            terminal: atStart ? .start(boundary) : .end(boundary), tolerance: tolerance)
    }

    package func junctionParameter(
        blend: RollingBallBlendSurface3D,
        firstContact: Point3D,
        secondContact: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try blend.validate()
        try firstContact.validate()
        try secondContact.validate()
        let rail = try ValidatedCurve3D(blend.firstContact, tolerance: tolerance)
        let projection = try rail.parameterProjection(of: firstContact)
        let partner = try blend.secondContact.point(at: projection.parameter, tolerance: tolerance)
        guard (partner - secondContact).length <= tolerance.distance else {
            throw KernelError(phase: .topology, code: .topologyFailure,
                residual: (partner - secondContact).length, tolerance: tolerance,
                message: "Adjacent blend contacts do not share one section parameter.")
        }
        return projection.parameter
    }

    package func build(
        blend: RollingBallBlendSurface3D,
        stableID: String,
        orientation: Orientation,
        parentSubshapeIDs: [SubshapeID],
        uRange: ScalarInterval? = nil,
        terminal: TerminalBoundary? = nil,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        try tolerance.validate()
        try blend.validate()
        let lower = uRange?.lower ?? 0
        let upper = uRange?.upper ?? 1
        guard lower >= 0, upper <= 1, upper - lower > tolerance.relative else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "A blend patch requires a nondegenerate retained U interval inside its support.")
        }
        let surface = Surface3D.procedural(.rollingBall(blend))
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: lower, uEnd: upper),
            .constantU(u: upper, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: upper, uEnd: lower),
            .constantU(u: lower, vStart: 1, vEnd: 0),
        ]
        let curves: [Curve3D] = [
            blend.firstContact,
            .surfaceLift(.init(surface: surface, parameterCurve: pcurves[1])),
            blend.secondContact,
            .surfaceLift(.init(surface: surface, parameterCurve: pcurves[3])),
        ]
        var edges = try curves.indices.map { index in
            let start = index == 2 ? upper : (index == 0 ? lower : 0)
            let end = index == 2 ? lower : (index == 0 ? upper : 1)
            return BRepSewingEdge(
                stableID: "\(stableID):edge:\(index)", curve: curves[index],
                startParameter: start, endParameter: end,
                startPoint: try curves[index].point(at: start, tolerance: tolerance),
                endPoint: try curves[index].point(at: end, tolerance: tolerance),
                surfaceParameterCurve: pcurves[index])
        }
        if let terminal {
            let boundary: BRepSewingEdge
            let atStart: Bool
            switch terminal {
            case .start(let edge): (boundary, atStart) = (edge, true)
            case .end(let edge): (boundary, atStart) = (edge, false)
            }
            try boundary.validate(on: surface, tolerance: tolerance)
            let first = try boundary.surfaceParameterCurve.startParameter(tolerance: tolerance)
            let last = try boundary.surfaceParameterCurve.endParameter(tolerance: tolerance)
            guard abs(first.v - (atStart ? 1 : 0)) <= tolerance.relative,
                  abs(last.v - (atStart ? 0 : 1)) <= tolerance.relative,
                  first.u >= lower, first.u <= upper, last.u >= lower, last.u <= upper,
                  case .certifiedImplicit(let parameters) = boundary.surfaceParameterCurve else {
                throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                    message: "A terminal blend boundary requires an oriented native implicit span between its contact rails.")
            }
            let jet = try ImplicitCurveIntervalJetEncloser(
                intersection: parameters.intersection, tolerance: tolerance).parameterIntervalJet(
                    of: parameters.intersection,
                    over: ScalarInterval(lower: min(parameters.startFraction, parameters.endFraction),
                                         upper: max(parameters.startFraction, parameters.endFraction)),
                    tolerance: tolerance)
            let derivative = jet[parameters.role == .first ? .firstV : .secondV].firstDerivative
            let increasing = (parameters.endFraction > parameters.startFraction) != atStart
            guard increasing ? derivative.lower > 0 : derivative.upper < 0 else {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                    message: "The terminal boundary is not certified monotone across the blend section.")
            }
            let uBounds = jet[parameters.role == .first ? .firstU : .secondU].value
            guard uBounds.lower >= lower - tolerance.relative,
                  uBounds.upper <= upper + tolerance.relative,
                  atStart ? uBounds.upper < upper - tolerance.relative
                    : uBounds.lower > lower + tolerance.relative else {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                    message: "The terminal boundary must stay inside the retained support and separate from its opposite end.")
            }
            for index in [0, 2] {
                let start = atStart ? (index == 0 ? last.u : upper) : (index == 0 ? lower : last.u)
                let end = atStart ? (index == 0 ? upper : first.u) : (index == 0 ? first.u : lower)
                guard (index == 0 ? end - start : start - end) > tolerance.relative else {
                    throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                        message: "A terminal trim must retain a nondegenerate contact rail.")
                }
                let old = edges[index]
                let startPoint = atStart
                    ? (index == 0 ? boundary.endPoint : old.startPoint)
                    : (index == 0 ? old.startPoint : boundary.endPoint)
                let endPoint = atStart
                    ? (index == 0 ? old.endPoint : boundary.startPoint)
                    : (index == 0 ? boundary.startPoint : old.endPoint)
                edges[index] = BRepSewingEdge(stableID: old.stableID, curve: old.curve,
                    startParameter: start, endParameter: end, startPoint: startPoint, endPoint: endPoint,
                    surfaceParameterCurve: .constantV(v: index == 0 ? 0 : 1, uStart: start, uEnd: end))
            }
            edges[atStart ? 3 : 1] = boundary
        }
        let patch = BRepSewingFacePatch(
            stableID: stableID, surface: surface, orientation: .forward,
            loops: [.init(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: parentSubshapeIDs)
        try patch.validate(tolerance: tolerance)
        return try BRepSewingPatchOrientationAdapter().reorient(
            patch, to: orientation, tolerance: tolerance)
    }
}
