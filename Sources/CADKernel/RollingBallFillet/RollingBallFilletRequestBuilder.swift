import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): Kernel integration checks consume this
// request builder; feature evaluation does not publish it yet. Whole-solid and
// global intersection admission, lineage and reevaluation must pass first.
struct RollingBallFilletRequestBuilder {
    private let input: ValidatedBRepModel
    private let subshapes: [SubshapeID: TopologyReference]
    private var model: BRepModel { input.model }
    private var tolerance: ModelingTolerance { input.tolerance }
    private let correspondence = CurveSurfaceCorrespondenceValidationOptions(
        maximumSubdivisionDepth: 20, maximumCellCount: 65_536)

    init(input: ValidatedBRepModel, subshapes: [SubshapeID: TopologyReference]) {
        self.input = input
        self.subshapes = subshapes
    }

    func build(featureID: FeatureID, bodyID: BodyID, edgeID: EdgeID,
               radius: Double) throws -> BRepSewingRequest {
        try Task.checkCancellation()
        guard input.validationLevel != .modeling, radius.isFinite, radius > tolerance.distance else {
            throw failure(.invalidInput, "A fillet requires exact input and a finite positive radius.")
        }
        guard let body = model.bodies[bodyID], body.kind == .solid,
              body.shellIDs.count == 1, let shellID = body.shellIDs.first,
              let shell = model.shells[shellID] else {
            throw failure(.unsupportedCapability, "Rolling-ball composition requires a single-shell solid.")
        }
        var incident: [EdgeID: [FaceID]] = [:]
        for faceID in shell.faceIDs {
            let face = try sourceFace(faceID)
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw failure(.missingReference, "Missing source loop.") }
                for coedge in loop.edges { incident[coedge.edgeID, default: []].append(faceID) }
            }
        }
        guard let pair = incident[edgeID], pair.count == 2, Set(pair).count == 2 else {
            throw failure(.invalidInput, "The selected edge must join two faces of the target body.")
        }
        let caps = try pair.filter { if case .plane = try surface(of: sourceFace($0)) { return true }; return false }
        guard caps.count == 1, let capID = caps.first else {
            throw failure(.unsupportedCapability, "The selected chain requires one planar partner.")
        }
        let cap = try sourceFace(capID)
        let capSurface = try surface(of: cap)
        func otherFace(_ edge: EdgeID) throws -> Face {
            guard let pair = incident[edge], pair.count == 2,
                  pair.filter({ $0 == capID }).count == 1,
                  let other = pair.first(where: { $0 != capID }) else {
                throw failure(.invalidInput, "A cap edge requires two distinct incident faces.")
            }
            return try sourceFace(other)
        }
        let chain = Set(try RollingBallTangentChainResolver().resolve(
            selectedEdge: edgeID, partner: capID, shell: shell, model: model, tolerance: tolerance))
        let affectedLoops = cap.loops.indices.filter { index in
            model.loops[cap.loops[index]]?.edges.contains { chain.contains($0.edgeID) } == true
        }
        guard affectedLoops.count == 1, let loopIndex = affectedLoops.first,
              let loop = model.loops[cap.loops[loopIndex]] else {
            throw failure(.unsupportedCapability, "A treatment must occupy one cap loop.")
        }
        let mask = loop.edges.map { chain.contains($0.edgeID) }
        let starts = mask.indices.filter { mask[$0] && !mask[($0 + mask.count - 1) % mask.count] }
        guard chain.count >= 2, starts.count == 1, let start = starts.first else {
            throw failure(.unsupportedCapability, "A treatment requires one open multi-span cap chain.")
        }
        var ordered: [Int] = []
        var cursor = start
        while mask[cursor] { ordered.append(cursor); cursor = (cursor + 1) % mask.count }
        guard ordered.count == chain.count else { throw failure(.invalidInput, "The cap chain is disconnected.") }
        let faces = try ordered.map { try otherFace(loop.edges[$0].edgeID) }
        let neighborFaces = try [otherFace(loop.edges[(start + mask.count - 1) % mask.count].edgeID),
                                 otherFace(loop.edges[cursor].edgeID)]
        guard Set(faces.map(\.id) + neighborFaces.map(\.id) + [capID]).count == faces.count + 3 else {
            throw failure(.unsupportedCapability, "A source face cannot participate twice in this treatment.")
        }
        // Index ancestry once; each operation below consumes only its own parents.
        var ancestry: [TopologyReference: [SubshapeID]] = [:]
        for (id, reference) in subshapes { ancestry[reference, default: []].append(id) }
        let capOffset = OffsetSurface3D(source: capSurface,
            distance: cap.orientation == shell.orientation ? -radius : radius)
        var replacements: [FaceID: BRepSewingFacePatch] = [:]
        var blends: [RollingBallBlendSurface3D] = []
        var patches: [BRepSewingFacePatch] = []
        var rails: [BRepSewingEdge] = []
        for (index, face) in faces.enumerated() {
            try Task.checkCancellation()
            let blend = try contactBlend(source: surface(of: face), face: face,
                shell: shell, cap: capOffset, radius: radius)
            let edgeParents = ancestry[.edge(loop.edges[ordered[index]].edgeID)] ?? []
            let contact = try rail(blend.firstContact, stableID: "fillet-contact:\(face.id)", parents: edgeParents)
            let removedOnLeft = try blend.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: correspondence.maximumSubdivisionDepth,
                maximumCellCount: correspondence.maximumCellCount)
            let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
                faceID: face.id, boundaries: [.init(reference: .init(
                    facePair: .init(targetFaceID: face.id, toolFaceID: capID), componentID: .init(ordinal: 0)),
                    segmentOrdinal: 0, faceID: face.id, edge: contact,
                    forwardLeftAction: removedOnLeft ? .discard : .keep,
                    forwardRightAction: removedOnLeft ? .keep : .discard)],
                model: model, sourceSubshapes: subshapes, tolerance: tolerance)
            guard partition.isPartitioned, partition.patches.count == 1,
                  let retained = partition.patches.first,
                  let shared = retained.loops.lazy.flatMap(\.edges).first(where: { $0.curve == contact.curve }) else {
                throw failure(.topologyFailure, "A contact must retain exactly one original lateral region.")
            }
            replacements[face.id] = retained
            blends.append(blend)
            patches.append(try RollingBallBlendPatchBuilder().build(blend: blend,
                stableID: "fillet-blend:\(face.id)",
                orientation: shared.startParameter < shared.endParameter ? .reversed : .forward,
                parentSubshapeIDs: (ancestry[.face(face.id)] ?? []) + (ancestry[.face(capID)] ?? []) + edgeParents,
                tolerance: tolerance))
            rails.append(try rail(blend.secondContact, stableID: "fillet-cap-contact:\(face.id)", parents: edgeParents))
        }
        let adapter = BRepSewingPatchOrientationAdapter()
        if !near(rails[0].endPoint, rails[1].startPoint) && !near(rails[0].endPoint, rails[1].endPoint) {
            rails[0] = try adapter.reversed(rails[0], tolerance: tolerance)
        }
        for index in 1..<rails.count {
            if !near(rails[index - 1].endPoint, rails[index].startPoint) {
                rails[index] = try adapter.reversed(rails[index], tolerance: tolerance)
            }
            guard near(rails[index - 1].endPoint, rails[index].startPoint) else {
                throw failure(.topologyFailure, "Ordered cap contact rails are disconnected.")
            }
        }
        for (endIndex, position) in [0, rails.count - 1].enumerated() {
            try Task.checkCancellation()
            let coedge = loop.edges[ordered[position]]
            guard let edge = model.edges[coedge.edgeID] else { throw failure(.missingReference, "Missing terminal edge.") }
            let vertexID = (position == 0) == (coedge.orientation == .forward) ? edge.startVertexID : edge.endVertexID
            guard let corner = model.vertices[vertexID]?.point else { throw failure(.missingReference, "Missing terminal vertex.") }
            let face = faces[position]
            let neighbor = neighborFaces[endIndex]
            let lateralUses = face.loops.flatMap { model.loops[$0]?.edges ?? [] }
                .filter { $0.edgeID == coedge.edgeID }
            guard lateralUses.count == 1, let lateralBoundary = lateralUses.first?.surfaceParameterCurve else {
                throw failure(.topologyFailure, "The selected lateral edge requires one source-chart boundary.")
            }
            let extended = try contactBlend(source: Self.continued(surface(of: face),
                along: lateralBoundary, tolerance: tolerance),
                face: face, shell: shell, cap: capOffset, radius: radius)
            let neighborSurface = try surface(of: neighbor)
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .procedural(.rollingBall(extended)), second: Self.continued(neighborSurface,
                    along: nil, tolerance: tolerance),
                options: .init(maximumSubdivisionCells: 4096, maximumRootAttempts: 4096), tolerance: tolerance)
            guard intersections.count == 1, case .curve(let trim) = intersections[0],
                  case .implicit(let implicit) = trim.truth else {
                throw failure(.topologyFailure, "A terminal requires one certified implicit intersection.")
            }
            let transferred = try implicit.transferredParameterCurve(on: .second, to: neighborSurface,
                maximumSpanCount: 4096, options: correspondence, tolerance: tolerance)
            let boundary = BRepSewingEdge(stableID: "fillet-neighbor-terminal:\(vertexID)",
                curve: trim.curve, startParameter: 0, endParameter: 1,
                startPoint: try trim.curve.point(at: 0, tolerance: tolerance),
                endPoint: try trim.curve.point(at: 1, tolerance: tolerance),
                surfaceParameterCurve: transferred,
                parentSubshapeIDs: (ancestry[.face(neighbor.id)] ?? []) + (ancestry[.edge(edge.id)] ?? []))
            let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
                faceID: neighbor.id, boundaries: [.init(reference: .init(
                    facePair: .init(targetFaceID: neighbor.id, toolFaceID: capID), componentID: .init(ordinal: 0)),
                    segmentOrdinal: 0, faceID: neighbor.id, edge: boundary,
                    forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true)],
                model: model, sourceSubshapes: subshapes, tolerance: tolerance)
            let retained = partition.patches.filter { patch in
                !patch.loops.contains { loop in loop.edges.contains { near($0.startPoint, corner) || near($0.endPoint, corner) } }
            }
            guard partition.isPartitioned, partition.patches.count == 2, retained.count == 1,
                  let neighborPatch = retained.first else {
                throw failure(.topologyFailure, "The terminal must separate exactly one removed corner region.")
            }
            replacements[neighbor.id] = neighborPatch
            let normal = blends[position]
            let junction = position == 0 ? rails[position].endParameter : rails[position].startParameter
            let firstContact = try normal.firstContact.point(at: junction, tolerance: tolerance)
            let secondContact = try normal.secondContact.point(at: junction, tolerance: tolerance)
            let builder = RollingBallBlendPatchBuilder()
            let u = try builder.junctionParameter(blend: extended, firstContact: firstContact,
                secondContact: secondContact, tolerance: tolerance)
            let parameters = SurfaceParameterCurve.certifiedImplicit(try .init(
                intersection: implicit, role: .first, tolerance: tolerance))
            let terminal = BRepSewingEdge(stableID: "fillet-blend-terminal:\(vertexID)",
                curve: boundary.curve, startParameter: 0, endParameter: 1,
                startPoint: boundary.startPoint, endPoint: boundary.endPoint,
                surfaceParameterCurve: parameters, parentSubshapeIDs: boundary.parentSubshapeIDs)
            let original = patches[position]
            let trimmed = try builder.build(blend: extended, stableID: original.stableID,
                orientation: original.orientation, parentSubshapeIDs: original.parentSubshapeIDs,
                retainingJunction: u, terminal: terminal, tolerance: tolerance)
            guard var capRail = trimmed.loops.lazy.flatMap(\.edges).first(where: { $0.curve == extended.secondContact }) else {
                throw failure(.topologyFailure, "The trimmed blend lost its cap rail.")
            }
            if !near(position == 0 ? capRail.endPoint : capRail.startPoint, secondContact) {
                capRail = try adapter.reversed(capRail, tolerance: tolerance)
            }
            guard near(position == 0 ? capRail.endPoint : capRail.startPoint, secondContact) else {
                throw failure(.topologyFailure, "The terminal cap contact does not join its adjacent rail.")
            }
            rails[position] = capRail
            patches[position] = trimmed
        }
        let capPatch = try originalPatch(capID)
        let capReplacements = Dictionary(uniqueKeysWithValues: ordered.indices.map {
            (capPatch.loops[loopIndex].edges[ordered[$0]].stableID, rails[$0])
        })
        replacements[capID] = try RollingBallCapPatchBuilder().build(source: capPatch,
            replacing: capReplacements, tolerance: tolerance)
        var complete: [BRepSewingFacePatch] = []
        complete.reserveCapacity(shell.faceIDs.count + patches.count)
        for faceID in shell.faceIDs {
            try Task.checkCancellation()
            complete.append(try replacements[faceID] ?? originalPatch(faceID))
        }
        complete.append(contentsOf: patches)
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
            shells: [.init(stableID: "fillet-shell:\(shellID)", patches: complete, orientation: shell.orientation)],
            bodyParentSubshapeIDs: ancestry[.body(bodyID)] ?? [])
    }

    private func sourceFace(_ id: FaceID) throws -> Face {
        guard let face = model.faces[id] else { throw failure(.missingReference, "Missing source face.") }
        return face
    }

    private func surface(of face: Face) throws -> Surface3D {
        guard let surface = model.geometry.surfaces[face.surfaceID] else { throw failure(.missingReference, "Missing source surface.") }
        return surface
    }

    private func originalPatch(_ faceID: FaceID) throws -> BRepSewingFacePatch {
        try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "fillet-source:\(faceID)",
            from: model, sourceSubshapes: subshapes, tolerance: tolerance).patch
    }

    private func contactBlend(source: Surface3D, face: Face, shell: Shell,
                              cap: OffsetSurface3D, radius: Double) throws -> RollingBallBlendSurface3D {
        let offset = OffsetSurface3D(source: source,
            distance: face.orientation == shell.orientation ? -radius : radius)
        let contacts = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.offset(offset)), second: .procedural(.offset(cap)), tolerance: tolerance)
        guard contacts.count == 1, case .curve(let contact) = contacts[0],
              case .closed(let lower, let upper) = contact.curve.parameterDomain else {
            throw failure(.topologyFailure, "A lateral span requires exactly one bounded offset intersection.")
        }
        return try RollingBallSectionEvaluator(first: offset, second: cap, intersection: contact,
            tolerance: tolerance).blendSurface(fromCurveParameter: lower,
                toCurveParameter: upper, options: correspondence)
    }

    private func rail(_ curve: Curve3D, stableID: String, parents: [SubshapeID]) throws -> BRepSewingEdge {
        guard case .surfaceLift(let lift) = curve else { throw failure(.topologyFailure, "A contact rail must retain its source chart.") }
        return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: 0, endParameter: 1,
            startPoint: try curve.point(at: 0, tolerance: tolerance),
            endPoint: try curve.point(at: 1, tolerance: tolerance),
            surfaceParameterCurve: lift.parameterCurve, parentSubshapeIDs: parents)
    }

    static func continued(_ surface: Surface3D, along boundary: SurfaceParameterCurve?,
                          tolerance: ModelingTolerance) throws -> Surface3D {
        try tolerance.validate()
        func refusal() -> KernelError {
            KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                message: "Terminal continuation requires a finite Bezier chart and a complete isoparametric boundary.")
        }
        guard case .bSpline(let spline) = surface,
              case .closed(let u0, let u1) = spline.uDomain,
              case .closed(let v0, let v1) = spline.vDomain else {
            throw refusal()
        }
        let extendU: Bool
        let extendV: Bool
        try boundary?.validate(on: surface, tolerance: tolerance)
        func spans(_ start: Double, _ end: Double, _ lower: Double, _ upper: Double) -> Bool {
            abs(min(start, end) - lower) <= tolerance.relative
                && abs(max(start, end) - upper) <= tolerance.relative
        }
        switch boundary {
        case nil:
            (extendU, extendV) = (true, true)
        case .constantU(let u, let start, let end):
            guard (abs(u - u0) <= tolerance.relative || abs(u - u1) <= tolerance.relative),
                  spans(start, end, v0, v1) else { throw refusal() }
            (extendU, extendV) = (false, true)
        case .constantV(let v, let start, let end):
            guard (abs(v - v0) <= tolerance.relative || abs(v - v1) <= tolerance.relative),
                  spans(start, end, u0, u1) else { throw refusal() }
            (extendU, extendV) = (true, false)
        default:
            throw refusal()
        }
        let du = extendU ? (u1 - u0) * 0.25 : 0
        let dv = extendV ? (v1 - v0) * 0.25 : 0
        return .bSpline(try spline.continuedBezierSupport(
            over: SurfaceParameterBox(u: ScalarInterval(lower: u0 - du, upper: u1 + du),
                v: ScalarInterval(lower: v0 - dv, upper: v1 + dv)),
            maximumDeviation: tolerance.distance * 0.01, tolerance: tolerance).surface)
    }

    private func near(_ a: Point3D, _ b: Point3D) -> Bool { (a - b).length <= tolerance.distance }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
