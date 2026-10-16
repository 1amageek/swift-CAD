import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): Kernel integration checks consume this
// request builder and ordinary KernelRollingBallFilletEvaluator publish its
// admitted cap-chain domain. General blend networks, whole-solid/global
// intersection admission, lineage and reevaluation must pass for complete support.
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
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try build(featureID: featureID, bodyID: bodyID, edgeID: edgeID,
            radius: radius, using: &execution)
    }

    func build(featureID: FeatureID, bodyID: BodyID, edgeID: EdgeID,
        radius: Double, using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        let contribution = try RollingBallIntersectionPolicy.contribution(tolerance: tolerance, using: &execution)
        let request = try execution.withContributionScope(contribution) { execution in
            try buildBody(featureID: featureID, bodyID: bodyID, edgeID: edgeID,
                radius: radius, contribution: contribution, using: &execution)
        }
        try execution.checkpoint()
        return request
    }

    private func buildBody(featureID: FeatureID, bodyID: BodyID, edgeID: EdgeID,
        radius: Double, contribution: OriginalQueryContributionHandle,
        using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        try execution.checkpoint()
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
        let capID: FaceID
        if caps.count == 1, let planePartner = caps.first {
            capID = planePartner
        } else if caps.isEmpty {
            for id in pair {
                guard case .bSpline(let support) = try surface(of: sourceFace(id)),
                      case .closed = support.uDomain, case .closed = support.vDomain else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary Fillet requires
                    // all original nonplanar support families and finite trimming.
                    // This curved partner route presently binds two native finite
                    // B-spline charts; other source laws need their own contact
                    // and endpoint authority before successful publication.
                    throw failure(.unsupportedCapability, "A curved fixed partner needs retained finite native support charts.")
                }
            }
            capID = pair.sorted { $0.description < $1.description }[0]
        } else {
            throw failure(.unsupportedCapability, "This request requires one plane partner or two original finite B-spline supports.")
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
            selectedEdge: edgeID, partner: capID, shell: shell, model: model, tolerance: tolerance, using: &execution))
        let affectedLoops = cap.loops.indices.filter { index in
            model.loops[cap.loops[index]]?.edges.contains { chain.contains($0.edgeID) } == true
        }
        guard affectedLoops.count == 1, let loopIndex = affectedLoops.first,
              let loop = model.loops[cap.loops[loopIndex]] else {
            throw failure(.unsupportedCapability, "A treatment must occupy one cap loop.")
        }
        let mask = loop.edges.map { chain.contains($0.edgeID) }
        let closedChain = mask.allSatisfy { $0 }
        let starts = mask.indices.filter { mask[$0] && !mask[($0 + mask.count - 1) % mask.count] }
        guard !chain.isEmpty, closedChain || starts.count == 1,
              let start = closedChain ? loop.edges.firstIndex(where: { $0.edgeID == edgeID }) : starts.first else {
            throw failure(.unsupportedCapability, "A treatment requires one connected nonempty cap chain.")
        }
        var ordered: [Int] = []
        var cursor = start
        while mask[cursor], ordered.count < mask.count {
            ordered.append(cursor); cursor = (cursor + 1) % mask.count
        }
        guard ordered.count == chain.count else { throw failure(.invalidInput, "The cap chain is disconnected.") }
        let faces = try ordered.map { try otherFace(loop.edges[$0].edgeID) }
        let neighborFaces = closedChain ? [] : try [otherFace(loop.edges[(start + mask.count - 1) % mask.count].edgeID),
                                                    otherFace(loop.edges[cursor].edgeID)]
        guard Set(faces.map(\.id) + neighborFaces.map(\.id) + [capID]).count == faces.count + neighborFaces.count + 1 else {
            throw failure(.unsupportedCapability, "A source face cannot participate twice in this treatment.")
        }
        // Index ancestry once; each operation below consumes only its own parents.
        var ancestry: [TopologyReference: [SubshapeID]] = [:]
        for (id, reference) in subshapes { ancestry[reference, default: []].append(id) }
        var concave: Bool?
        for index in ordered.indices {
            let classified = try OriginalEdgeDihedralClassifier().isConcave(
                edgeID: loop.edges[ordered[index]].edgeID, first: cap, second: faces[index],
                shell: shell, input: input, using: &execution)
            if let concave, concave != classified {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary Fillet requires
                // mixed convex/concave network composition on one original
                // partner. A single signed offset must not silently replace
                // the complete source network's varying material side.
                throw failure(.unsupportedCapability, "The original tangent chain requires mixed material-side composition.")
            }
            concave = classified
        }
        guard let concave else { throw failure(.invalidInput, "An original treatment requires a nonempty dihedral cover.") }
        let materialOffsetSign = concave ? 1.0 : -1.0
        let capOffset = OffsetSurface3D(source: capSurface,
            distance: (cap.orientation == shell.orientation ? 1 : -1) * materialOffsetSign * radius)
        var replacements: [FaceID: BRepSewingFacePatch] = [:]
        var blends: [RollingBallBlendSurface3D] = []
        var patches: [BRepSewingFacePatch] = []
        var rails: [BRepSewingEdge] = []
        for (index, face) in faces.enumerated() {
            try execution.consumeWork(1)
            let blend = try contactBlend(source: surface(of: face), face: face,
                shell: shell, cap: capOffset, radius: radius,
                materialOffsetSign: materialOffsetSign,
                completeCycle: closedChain && faces.count == 1, using: &execution)
            let edgeParents = ancestry[.edge(loop.edges[ordered[index]].edgeID)] ?? []
            let contact = try rail(blend.firstContact, stableID: "fillet-contact:\(face.id)", parents: edgeParents, using: &execution)
            let removedOnLeft = try blend.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: correspondence.maximumSubdivisionDepth,
                maximumCellCount: correspondence.maximumCellCount, using: &execution)
            let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
                faceID: face.id, boundaries: [.init(reference: .init(
                    facePair: .init(targetFaceID: face.id, toolFaceID: capID), componentID: .init(ordinal: 0)),
                    segmentOrdinal: 0, faceID: face.id, edge: contact,
                    forwardLeftAction: removedOnLeft ? .discard : .keep,
                    forwardRightAction: removedOnLeft ? .keep : .discard)],
                model: model, sourceSubshapes: subshapes, tolerance: tolerance, using: &execution)
            guard partition.isPartitioned, partition.patches.count == 1,
                  let retained = partition.patches.first,
                  let shared = try OriginalParameterQueryStorage.first(retained.loops.lazy.flatMap(\.edges), using: &execution, predicate: { edge, execution in
                      try GeometryStructuralComparisonWork.charge(curve: edge.curve, using: &execution)
                      try GeometryStructuralComparisonWork.charge(curve: contact.curve, using: &execution)
                      return edge.curve == contact.curve
                  }) else {
                throw failure(.topologyFailure, "A contact must retain exactly one original lateral region.")
            }
            replacements[face.id] = retained
            blends.append(blend)
            patches.append(try RollingBallBlendPatchBuilder().build(blend: blend,
                stableID: "fillet-blend:\(face.id)",
                orientation: shared.startParameter < shared.endParameter ? .reversed : .forward,
                parentSubshapeIDs: (ancestry[.face(face.id)] ?? []) + (ancestry[.face(capID)] ?? []) + edgeParents,
                tolerance: tolerance, using: &execution))
            rails.append(try rail(blend.secondContact, stableID: "fillet-cap-contact:\(face.id)", parents: edgeParents, using: &execution))
        }
        let adapter = BRepSewingPatchOrientationAdapter()
        if rails.count > 1, !near(rails[0].endPoint, rails[1].startPoint) && !near(rails[0].endPoint, rails[1].endPoint) {
            rails[0] = try adapter.reversed(rails[0], tolerance: tolerance, using: &execution)
        }
        for index in 1..<rails.count {
            if !near(rails[index - 1].endPoint, rails[index].startPoint) {
                rails[index] = try adapter.reversed(rails[index], tolerance: tolerance, using: &execution)
            }
            guard near(rails[index - 1].endPoint, rails[index].startPoint) else {
                throw failure(.topologyFailure, "Ordered cap contact rails are disconnected.")
            }
        }
        if closedChain, !near(rails[rails.count - 1].endPoint, rails[0].startPoint) {
            throw failure(.topologyFailure, "A closed cap contact chain does not close on its original cyclic seam.")
        }
        var singleSupport: RollingBallBlendSurface3D?
        var singleJunction: Double?
        var singleTerminals: [BRepSewingEdge] = []
        for (endIndex, position) in (closedChain ? [] : [0, rails.count - 1]).enumerated() {
            try execution.consumeWork(1)
            let coedge = loop.edges[ordered[position]]
            guard let edge = model.edges[coedge.edgeID] else { throw failure(.missingReference, "Missing terminal edge.") }
            let vertexID = (endIndex == 0) == (coedge.orientation == .forward) ? edge.startVertexID : edge.endVertexID
            guard let corner = model.vertices[vertexID]?.point else { throw failure(.missingReference, "Missing terminal vertex.") }
            let face = faces[position]
            let neighbor = neighborFaces[endIndex]
            let lateralUses = face.loops.flatMap { model.loops[$0]?.edges ?? [] }
                .filter { $0.edgeID == coedge.edgeID }
            guard lateralUses.count == 1, let lateralBoundary = lateralUses.first?.surfaceParameterCurve else {
                throw failure(.topologyFailure, "The selected lateral edge requires one source-chart boundary.")
            }
            let extended: RollingBallBlendSurface3D
            if let prepared = singleSupport {
                extended = prepared
            } else {
                let continued = try Self.continued(surface(of: face),
                    along: lateralBoundary, tolerance: tolerance, using: &execution)
                extended = try contactBlend(source: continued,
                    face: face, shell: shell, cap: capOffset, radius: radius,
                    materialOffsetSign: materialOffsetSign, using: &execution)
                if rails.count == 1 { singleSupport = extended }
            }
            let neighborSurface = try surface(of: neighbor)
            let continuedNeighbor = try Self.continued(neighborSurface, along: nil,
                tolerance: tolerance, using: &execution)
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .procedural(.rollingBall(extended)), second: continuedNeighbor,
                options: .init(maximumSubdivisionDepth: min(12, RollingBallIntersectionPolicy.maximumDepth),
                    maximumSubdivisionCells: 4096, maximumRootAttempts: 4096),
                tolerance: tolerance, using: &execution)
            guard intersections.count == 1, case .curve(let trim) = intersections[0],
                  case .implicit(let implicit) = trim.truth else {
                throw failure(.topologyFailure, "A terminal requires one certified implicit intersection.")
            }
            let transferred = try implicit.transferredParameterCurve(on: .second, to: neighborSurface,
                maximumSpanCount: 4096, options: correspondence, tolerance: tolerance, using: &execution)
            let boundary = try BRepSewingEdge(stableID: "fillet-neighbor-terminal:\(vertexID)",
                curve: trim.curve, startParameter: 0, endParameter: 1,
                startPoint: try trim.curve.point(at: 0, tolerance: tolerance, using: &execution),
                endPoint: try trim.curve.point(at: 1, tolerance: tolerance, using: &execution),
                surfaceParameterCurve: transferred,
                parentSubshapeIDs: (ancestry[.face(neighbor.id)] ?? []) + (ancestry[.edge(edge.id)] ?? []),
                using: &execution)
            let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
                faceID: neighbor.id, boundaries: [.init(reference: .init(
                    facePair: .init(targetFaceID: neighbor.id, toolFaceID: capID), componentID: .init(ordinal: 0)),
                    segmentOrdinal: 0, faceID: neighbor.id, edge: boundary,
                    forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true)],
                model: model, sourceSubshapes: subshapes, tolerance: tolerance, using: &execution)
            let retained = partition.patches.filter { patch in
                !patch.loops.contains { loop in loop.edges.contains { near($0.startPoint, corner) || near($0.endPoint, corner) } }
            }
            guard partition.isPartitioned, partition.patches.count == 2, retained.count == 1,
                  let neighborPatch = retained.first else {
                throw failure(.topologyFailure, "The terminal must separate exactly one removed corner region.")
            }
            replacements[neighbor.id] = neighborPatch
            let normal = blends[position]
            // A single span retains its original interior section between the
            // two terminals; either endpoint is not an opposite chain junction.
            let junction = rails.count == 1 ? 0.5
                : (endIndex == 0 ? rails[position].endParameter : rails[position].startParameter)
            let firstContact = try normal.firstContact.point(at: junction, tolerance: tolerance, using: &execution)
            let secondContact = try normal.secondContact.point(at: junction, tolerance: tolerance, using: &execution)
            let builder = RollingBallBlendPatchBuilder()
            let u: Double
            if let prepared = singleJunction {
                u = prepared
            } else {
                u = try builder.junctionParameter(blend: extended, firstContact: firstContact,
                    secondContact: secondContact, tolerance: tolerance, using: &execution)
                if rails.count == 1 { singleJunction = u }
            }
            let parameters = SurfaceParameterCurve.certifiedImplicit(try .init(
                intersection: implicit, role: .first, tolerance: tolerance, using: &execution))
            let terminal = try BRepSewingEdge(stableID: "fillet-blend-terminal:\(vertexID)",
                curve: boundary.curve, startParameter: 0, endParameter: 1,
                startPoint: boundary.startPoint, endPoint: boundary.endPoint,
                surfaceParameterCurve: parameters, parentSubshapeIDs: boundary.parentSubshapeIDs, using: &execution)
            let original = patches[position]
            let trimmed: BRepSewingFacePatch
            if rails.count == 1 {
                singleTerminals.append(terminal)
                if endIndex == 0 { continue }
                trimmed = try builder.build(blend: extended, stableID: original.stableID,
                    orientation: original.orientation, parentSubshapeIDs: original.parentSubshapeIDs,
                    retainingJunction: u, firstTerminal: singleTerminals[0],
                    secondTerminal: singleTerminals[1], tolerance: tolerance, using: &execution)
            } else {
                trimmed = try builder.build(blend: extended, stableID: original.stableID,
                    orientation: original.orientation, parentSubshapeIDs: original.parentSubshapeIDs,
                    retainingJunction: u, terminal: terminal, tolerance: tolerance, using: &execution)
            }
            guard var capRail = try OriginalParameterQueryStorage.first(trimmed.loops.lazy.flatMap(\.edges), using: &execution, predicate: { edge, execution in
                try GeometryStructuralComparisonWork.charge(curve: edge.curve, using: &execution)
                try GeometryStructuralComparisonWork.charge(curve: extended.secondContact, using: &execution)
                return edge.curve == extended.secondContact
            }) else {
                throw failure(.topologyFailure, "The trimmed blend lost its cap rail.")
            }
            if rails.count == 1 {
                func capPoint(_ boundary: BRepSewingEdge, using execution: inout OriginalQueryExecution) throws -> Point3D {
                    let uv = try boundary.surfaceParameterCurve.startParameter(tolerance: tolerance, using: &execution)
                    return abs(uv.v - 1) <= tolerance.relative ? boundary.startPoint : boundary.endPoint
                }
                let first = try capPoint(singleTerminals[0], using: &execution)
                let last = try capPoint(singleTerminals[1], using: &execution)
                if !near(capRail.startPoint, first) {
                    capRail = try adapter.reversed(capRail, tolerance: tolerance, using: &execution)
                }
                guard near(capRail.startPoint, first), near(capRail.endPoint, last) else {
                    throw failure(.topologyFailure, "Both native terminal cap vertices must follow the original cap-coedge traversal.")
                }
            } else {
                if !near(endIndex == 0 ? capRail.endPoint : capRail.startPoint, secondContact) {
                    capRail = try adapter.reversed(capRail, tolerance: tolerance, using: &execution)
                }
                guard near(endIndex == 0 ? capRail.endPoint : capRail.startPoint, secondContact) else {
                    throw failure(.topologyFailure, "The terminal cap contact does not join its adjacent rail.")
                }
            }
            rails[position] = capRail
            patches[position] = trimmed
        }
        let capPatch = try originalPatch(capID, using: &execution)
        let capReplacements = Dictionary(uniqueKeysWithValues: ordered.indices.map {
            (capPatch.loops[loopIndex].edges[ordered[$0]].stableID, rails[$0])
        })
        replacements[capID] = try RollingBallCapPatchBuilder().build(source: capPatch,
            replacing: capReplacements, tolerance: tolerance, using: &execution)
        let capacity = shell.faceIDs.count.addingReportingOverflow(patches.count)
        let patchBytes = capacity.partialValue.multipliedReportingOverflow(by: MemoryLayout<BRepSewingFacePatch>.stride)
        let originBytes = capacity.partialValue.multipliedReportingOverflow(by: MemoryLayout<FaceID?>.stride)
        guard !capacity.overflow, !patchBytes.overflow, !originBytes.overflow else {
            throw failure(.resourceLimitExceeded, "The complete fillet patch payload exceeds its representable capacity.")
        }
        try execution.retainStorage(bytes: patchBytes.partialValue)
        try execution.retainStorage(bytes: originBytes.partialValue)
        var complete: [BRepSewingFacePatch] = []
        var unchangedFaces: [FaceID?] = []
        complete.reserveCapacity(capacity.partialValue)
        unchangedFaces.reserveCapacity(capacity.partialValue)
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            if let replacement = replacements[faceID] {
                complete.append(replacement)
                unchangedFaces.append(nil)
            } else {
                // Only this immutable original-copy branch carries the input
                // receipt into finite trim classification. A replacement on the
                // same support cannot inherit an original face's trim authority.
                complete.append(try originalPatch(faceID, using: &execution))
                unchangedFaces.append(faceID)
            }
        }
        for patch in patches {
            try execution.consumeWork(1)
            complete.append(patch)
            unchangedFaces.append(nil)
        }
        try RollingBallInteriorIntersectionClassifier().rejectProvenCrossings(in: complete,
            generatedStart: complete.count - patches.count, tolerance: tolerance,
            unchangedFaces: unchangedFaces, originalInput: input,
            requestContribution: contribution, using: &execution)
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<BRepSewingShell>.stride)
        return try BRepSewingRequest(featureID: featureID, bodyKind: .solid,
            shells: [.init(stableID: "fillet-shell:\(shellID)", patches: complete, orientation: shell.orientation)],
            bodyParentSubshapeIDs: ancestry[.body(bodyID)] ?? [], using: &execution)
    }

    private func sourceFace(_ id: FaceID) throws -> Face {
        guard let face = model.faces[id] else { throw failure(.missingReference, "Missing source face.") }
        return face
    }

    private func surface(of face: Face) throws -> Surface3D {
        guard let surface = model.geometry.surfaces[face.surfaceID] else { throw failure(.missingReference, "Missing source surface.") }
        return surface
    }

    private func originalPatch(_ faceID: FaceID, using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "fillet-source:\(faceID)",
            from: model, sourceSubshapes: subshapes, tolerance: tolerance,
            using: &execution).patch
    }

    private func contactBlend(source: Surface3D, face: Face, shell: Shell,
                              cap: OffsetSurface3D, radius: Double,
                              materialOffsetSign: Double,
                              completeCycle: Bool = false,
                              using execution: inout OriginalQueryExecution) throws -> RollingBallBlendSurface3D {
        let offset = OffsetSurface3D(source: source,
            distance: (face.orientation == shell.orientation ? 1 : -1) * materialOffsetSign * radius)
        var options = SurfaceSurfaceIntersectionOptions()
        options.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth, RollingBallIntersectionPolicy.maximumDepth)
        options.maximumSubdivisionCells = min(options.maximumSubdivisionCells, 65_536)
        let contacts = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.offset(offset)), second: .procedural(.offset(cap)),
            options: options, tolerance: tolerance, using: &execution)
        guard contacts.count == 1, case .curve(let contact) = contacts[0] else {
            throw failure(.topologyFailure, "A lateral span requires exactly one bounded offset intersection.")
        }
        let lower: Double, upper: Double
        switch contact.curve.parameterDomain {
        case .closed(let a, let b):
            (lower, upper) = (a, b)
        case .periodic(let period):
            guard completeCycle, period.isFinite, period > 0,
                  try BRepEdgeGeometryClassifier().kind(curve: contact.curve,
                    from: 0, to: period, tolerance: tolerance, using: &execution) == .closed else {
                throw failure(.unsupportedCapability,
                    "A periodic offset intersection requires complete original closed-cycle selection.")
            }
            (lower, upper) = (0, period)
        case .unbounded:
            throw failure(.unsupportedCapability,
                "An unbounded offset intersection requires original finite endpoint trimming.")
        }
        let evaluator = try RollingBallSectionEvaluator(first: offset, second: cap, intersection: contact,
            tolerance: tolerance, using: &execution)
        return try evaluator.blendSurface(fromCurveParameter: lower,
                toCurveParameter: upper, options: correspondence, using: &execution)
    }

    private func rail(_ curve: Curve3D, stableID: String, parents: [SubshapeID],
        using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        guard case .surfaceLift(let lift) = curve else { throw failure(.topologyFailure, "A contact rail must retain its source chart.") }
        return try BRepSewingEdge(stableID: stableID, curve: curve, startParameter: 0, endParameter: 1,
            startPoint: try curve.point(at: 0, tolerance: tolerance, using: &execution),
            endPoint: try curve.point(at: 1, tolerance: tolerance, using: &execution),
            surfaceParameterCurve: lift.parameterCurve, parentSubshapeIDs: parents, using: &execution)
    }

    static func continued(_ surface: Surface3D, along boundary: SurfaceParameterCurve?,
                          tolerance: ModelingTolerance) throws -> Surface3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try continued(surface, along: boundary, tolerance: tolerance, using: &execution)
    }

    static func continued(_ surface: Surface3D, along boundary: SurfaceParameterCurve?,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Surface3D {
        try execution.consumeWork(1)
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
        try boundary?.validate(on: surface, tolerance: tolerance, using: &execution)
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
            maximumDeviation: tolerance.distance * 0.01, tolerance: tolerance, using: &execution).surface)
    }

    private func near(_ a: Point3D, _ b: Point3D) -> Bool { (a - b).length <= tolerance.distance }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
