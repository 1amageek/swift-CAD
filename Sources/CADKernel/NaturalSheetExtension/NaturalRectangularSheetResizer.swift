import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Retains original rectangular face supports while resizing complete selected sides.
struct NaturalRectangularSheetResizer {
    let builder: NaturalSheetExtensionBuilder

    init(builder: NaturalSheetExtensionBuilder) {
        self.builder = builder
    }
    private enum Side: Int, CaseIterable { case vLower, uUpper, vUpper, uLower }

    func patches(
        selections: [(edgeID: EdgeID, faceID: FaceID, coedge: Coedge)],
        scope: BodyTopologyScope, distance: Double, outward: Bool = false, context: EvaluationContext
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch]? {
        guard !selections.isEmpty else { return nil }
        let model = context.brep
        let tolerance = context.tolerance
        let grouped = Dictionary(grouping: selections, by: \.faceID)
        var replacements: [FaceID: BRepSewingFacePatch] = [:]
        for faceID in grouped.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID],
                  let domain = try ExactRectangularPcurveDomainResolver().resolve(
                    face: face, model: model, tolerance: tolerance, using: &execution) else { return nil }
            if outward, case .bSpline = surface { return nil }
            var intervals: [Side: [(Double, Double)]] = [:]
            for selection in grouped[faceID] ?? [] {
                guard let pcurve = selection.coedge.surfaceParameterCurve,
                      let (side, lower, upper) = try interval(pcurve, on: surface, domain: domain, tolerance: tolerance, using: &execution) else { return nil }
                intervals[side, default: []].append((lower, upper))
            }
            var uLower = domain.uLower, uUpper = domain.uUpper
            var vLower = domain.vLower, vUpper = domain.vUpper
            for side in Side.allCases where intervals[side] != nil {
                let variesU = side == .uLower || side == .uUpper
                let acrossLower = variesU ? domain.vLower : domain.uLower
                let acrossUpper = variesU ? domain.vUpper : domain.uUpper
                let sorted = (intervals[side] ?? []).sorted { $0.0 < $1.0 }
                var covered = acrossLower
                for segment in sorted {
                    guard segment.0 <= covered, segment.0 >= acrossLower,
                          segment.1 <= acrossUpper, segment.1 > segment.0 else {
                        if outward { return nil }
                        throw incomplete(tolerance)
                    }
                    covered = max(covered, segment.1)
                }
                guard covered == acrossUpper else {
                    if outward { return nil }
                    throw incomplete(tolerance)
                }
                let isLower = side == .uLower || side == .vLower
                let origin = variesU ? (isLower ? domain.uLower : domain.uUpper)
                    : (isLower ? domain.vLower : domain.vUpper)
                let reach = try builder.parameterReach(on: surface,
                    variesU: variesU, fixedAcross: acrossLower + (acrossUpper - acrossLower) * 0.5,
                    from: origin, sign: (isLower ? 1.0 : -1.0) * (outward ? -1.0 : 1.0), distance: distance, tolerance: tolerance, using: &execution)
                switch side {
                case .uLower: uLower = reach
                case .uUpper: uUpper = reach
                case .vLower: vLower = reach
                case .vUpper: vUpper = reach
                }
            }
            let preservesDirection = outward
                ? uLower <= domain.uLower && uUpper >= domain.uUpper
                    && vLower <= domain.vLower && vUpper >= domain.vUpper
                : uLower >= domain.uLower && uUpper <= domain.uUpper
                    && vLower >= domain.vLower && vUpper <= domain.vUpper
            guard preservesDirection, uLower < uUpper, vLower < vUpper else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Sheet resizing reverses or consumes the original rectangular face.")
            }
            let stableID = "sheet-resize:face:\(faceID)"
            let faceParents = try context.subshapeIDs(for: .face(faceID), using: &execution)
            let sides: [SurfaceParameterCurve] = [
                .constantV(v: vLower, uStart: uLower, uEnd: uUpper),
                .constantU(u: uUpper, vStart: vLower, vEnd: vUpper),
                .constantV(v: vUpper, uStart: uUpper, uEnd: uLower),
                .constantU(u: uLower, vStart: vUpper, vEnd: vLower),
            ]
            var parents: [Side: [SubshapeID]] = [:]
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("A shortened face loop is missing.")
                }
                for coedge in loop.coedges {
                    guard let pcurve = coedge.surfaceParameterCurve,
                          let (side, _, _) = try interval(pcurve, on: surface, domain: domain, tolerance: tolerance, using: &execution) else { return nil }
                    parents[side, default: []] += try context.subshapeIDs(for: .edge(coedge.edgeID), using: &execution)
                }
            }
            let edges = try sides.enumerated().map { ordinal, pcurve in
                try BRepFaceCurveClipper.edge(pcurve, on: surface,
                    stableID: "\(stableID):edge:\(ordinal)",
                    parentSubshapeIDs: faceParents + (parents[Side.allCases[ordinal]] ?? []),
                    tolerance: tolerance, using: &execution)
            }
            let forward = BRepSewingFacePatch(stableID: stableID, surface: surface,
                orientation: .forward,
                loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                parentSubshapeIDs: faceParents)
            replacements[faceID] = try BRepSewingPatchOrientationAdapter().reorient(
                forward, to: face.orientation, tolerance: tolerance, using: &execution)
        }
        let faceIDs = scope.references.compactMap { reference -> FaceID? in
            if case let .face(id) = reference { return id }
            return nil
        }.sorted()
        return try faceIDs.map { faceID in
            if let patch = replacements[faceID] { return patch }
            return try SourceBRepFacePatchBuilder().build(faceID: faceID,
                stableID: "sheet-resize:retained:\(faceID)", from: model,
                sourceSubshapes: context.subshapes.entries, tolerance: tolerance, using: &execution).patch
        }
    }

    private func interval(_ curve: SurfaceParameterCurve, on surface: Surface3D,
        domain: ExactRectangularPcurveDomain, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (Side, Double, Double)? {
        guard let endpoints = try ExactRectangularPcurveDomainResolver().axisAlignedEndpoints(
            of: curve, on: surface,
            remainingSourceDepth: builder.limits.remainingSourceDepth ?? 16, tolerance: tolerance, using: &execution) else { return nil }
        let start = endpoints.start, end = endpoints.end
        if start.u == end.u, start.v != end.v {
            let lower = min(start.v, end.v), upper = max(start.v, end.v)
            if start.u == domain.uLower { return (.uLower, lower, upper) }
            if start.u == domain.uUpper { return (.uUpper, lower, upper) }
        } else if start.v == end.v, start.u != end.u {
            let lower = min(start.u, end.u), upper = max(start.u, end.u)
            if start.v == domain.vLower { return (.vLower, lower, upper) }
            if start.v == domain.vUpper { return (.vUpper, lower, upper) }
        }
        return nil
    }

    private func incomplete(_ tolerance: ModelingTolerance) -> KernelError {
        // FIXME(INCOMPLETE_IMPLEMENTATION): partial rectangular side selections need a finite
        // local cut arrangement. Production path: natural positive/negative SheetExtendFeatureEvaluator.
        // Do not publish a whole-side move until the selected original subinterval alone is cut.
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Rectangular sheet resizing requires a complete selected side.")
    }
}
