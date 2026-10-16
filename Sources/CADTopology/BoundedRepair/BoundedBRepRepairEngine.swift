import HashTreeCollections
import CADCore
import CADGeometry

struct BoundedBRepRepairEngine {
    func reconstructCurves(
        model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic]
    ) throws {
        let correspondence = DefaultCurveSurfaceCorrespondenceValidator()
        for faceID in model.faces.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard var loop = model.loops[loopID] else { continue }
                for index in loop.coedges.indices {
                    let use = loop.coedges[index]
                    guard var edge = model.edges[use.edgeID] else { continue }
                    let originalCurve = model.geometry.curves[edge.curveID]
                    if originalCurve == nil, let pcurve = use.surfaceParameterCurve {
                        let canonical = use.orientation == .forward ? pcurve : try pcurve.reversed(tolerance: tolerance)
                        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: canonical))
                        try curve.validate(tolerance: tolerance)
                        guard let start = model.vertices[edge.startVertexID]?.point,
                              let end = model.vertices[edge.endVertexID]?.point,
                              try BRepRepairAudit().stationDisplacementUpperBound(of: curve, at: 0,
                                from: start, tolerance: tolerance) <= tolerance.distance,
                              try BRepRepairAudit().stationDisplacementUpperBound(of: curve, at: 1,
                                from: end, tolerance: tolerance) <= tolerance.distance else {
                            diagnostics.append(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                entityID: String(describing: edge.id), message: "The lifted missing curve disagrees with its retained vertices."))
                            continue
                        }
                        // Every existing incident pcurve is checked before canonical publication.
                        var admitted = true
                        for incidentFace in model.faces.values {
                            guard let support = model.geometry.surfaces[incidentFace.surfaceID] else { continue }
                            for incidentLoopID in incidentFace.loops {
                                guard let incidentLoop = model.loops[incidentLoopID] else { continue }
                                for incident in incidentLoop.coedges where incident.edgeID == edge.id {
                                    guard let local = incident.surfaceParameterCurve else { admitted = false; continue }
                                    do {
                                        try correspondence.validate(curve: curve,
                                            from: incident.orientation == .forward ? 0 : 1,
                                            to: incident.orientation == .forward ? 1 : 0,
                                            surface: support, parameterCurve: local, options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance)
                                    } catch is CancellationError { throw CancellationError() }
                                    catch { admitted = false }
                                }
                            }
                        }
                        if admitted {
                            model.geometry.curves[edge.curveID] = curve
                            edge.trim = CurveTrim(startParameter: 0, endParameter: 1)
                            model.edges[edge.id] = edge
                            changes.append(.init(action: .reconstructCurveRepresentations, scope: .pcurves,
                                affectedEntityIDs: [String(describing: edge.id)],
                                message: "Reconstructed a missing canonical curve from its original surface lift after all incident correspondence proofs.",
                                maximumDisplacement: tolerance.distance,
                                generatedEntityIDs: [String(describing: edge.curveID)]))
                        } else {
                            diagnostics.append(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                entityID: String(describing: edge.id), message: "Incident pcurves do not establish one canonical lifted edge."))
                        }
                    } else if let curve = originalCurve, let trim = edge.trim, use.surfaceParameterCurve == nil {
                        let start = use.orientation == .forward ? trim.startParameter : trim.endParameter
                        let end = use.orientation == .forward ? trim.endParameter : trim.startParameter
                        if let local = try retainedLiftPcurve(curve: curve, from: start, to: end,
                            surface: surface, tolerance: tolerance) {
                            do {
                                try correspondence.validate(curve: curve, from: start, to: end,
                                    surface: surface, parameterCurve: local,
                                    options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32,
                                        maximumCellCount: 65_536), tolerance: tolerance)
                                loop.coedges[index].surfaceParameterCurve = local
                                changes.append(.init(action: .reconstructCurveRepresentations, scope: .pcurves,
                                    affectedEntityIDs: [String(describing: edge.id)],
                                    message: "Reconstructed a missing directed pcurve from retained original hosting provenance after whole correspondence proof.",
                                    maximumDisplacement: tolerance.distance))
                            } catch is CancellationError { throw CancellationError() }
                            catch {
                                diagnostics.append(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                    entityID: String(describing: edge.id),
                                    message: "The retained original hosting pcurve could not establish whole directed correspondence."))
                            }
                        } else {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Production reconstructCurveRepresentations
                            // still needs the Geometry complete original inverse-chart producer for
                            // spatial curves without matching retained hosting provenance. It must
                            // reconstruct and prove every directed support branch before this repair
                            // domain can be reported as complete; missing pcurves remain diagnostics.
                            diagnostics.append(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                entityID: String(describing: edge.id),
                                message: "Missing pcurve has no matching retained original hosting provenance or complete inverse-chart producer."))
                        }
                    } else if let curve = originalCurve, let trim = edge.trim, let local = use.surfaceParameterCurve {
                        let start = use.orientation == .forward ? trim.startParameter : trim.endParameter
                        let end = use.orientation == .forward ? trim.endParameter : trim.startParameter
                        do {
                            try correspondence.validate(curve: curve, from: start, to: end,
                                surface: surface, parameterCurve: local, options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            let reversed = try local.reversed(tolerance: tolerance)
                            do {
                                try correspondence.validate(curve: curve, from: start, to: end,
                                    surface: surface, parameterCurve: reversed, options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance)
                                loop.coedges[index].surfaceParameterCurve = reversed
                                changes.append(.init(action: .reconstructCurveRepresentations, scope: .pcurves,
                                    affectedEntityIDs: [String(describing: edge.id)], message: "Reversed a pcurve after complete directed correspondence proof."))
                            } catch is CancellationError { throw CancellationError() }
                            catch {
                                diagnostics.append(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                    entityID: String(describing: edge.id), message: "Existing spatial curve and pcurve have no proved directed correspondence."))
                            }
                        }
                    }
                }
                model.loops[loopID] = loop
            }
        }
    }

    private func retainedLiftPcurve(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, tolerance: ModelingTolerance) throws -> SurfaceParameterCurve? {
        guard start >= 0, start <= 1, end >= 0, end <= 1, start != end else { return nil }
        switch curve {
        case .surfaceLift(let lift) where lift.surface == surface:
            let directed: SurfaceParameterCurve
            if min(start,end) == 0, max(start,end) == 1 { directed = lift.parameterCurve }
            else {
                directed = try lift.parameterCurve.subcurve(fromNormalizedFraction: min(start,end),
                    toNormalizedFraction: max(start,end), tolerance: tolerance)
            }
            return start < end ? directed : try directed.reversed(tolerance: tolerance)
        case .originalAffineWord(let image):
            guard case .surfaceLift(let lift) = image.source,
                case .procedural(.originalAffineWord(let target)) = surface,
                lift.surface == target.source, image.operationWord == target.operationWord else { return nil }
            return .originalAffineWord(try OriginalAffineWordSurfaceParameterCurve(source: lift,
                target: target, startFraction: start, endFraction: end, tolerance: tolerance))
        case .affineImage(let image):
            guard case .surfaceLift(let lift) = image.source,
                case .procedural(.originalImage(let target)) = surface,
                lift.surface == target.source, image.transform == target.transform else { return nil }
            return .originalImage(try OriginalImageSurfaceParameterCurve(source: lift, targetImage: target,
                startFraction: start, endFraction: end, tolerance: tolerance))
        default: return nil
        }
    }

    func sewVertices(model: inout BRepModel, tolerance: ModelingTolerance, changes: inout [BRepRepairChange]) throws {
        var replacement: [VertexID: VertexID] = [:]
        var retained: [VertexID] = []
        var maximum = 0.0
        for id in model.vertices.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let vertex = model.vertices[id] else { continue }
            if let owner = retained.first(where: { candidate in
                guard let point = model.vertices[candidate]?.point else { return false }
                return BRepRepairAudit().distanceUpperBound(point, vertex.point) <= tolerance.distance
            }), let point = model.vertices[owner]?.point {
                // Direct comparison to the final retained owner prevents chain-drift.
                replacement[id] = owner
                maximum = max(maximum, BRepRepairAudit().distanceUpperBound(point, vertex.point))
            } else { retained.append(id) }
        }
        for id in model.edges.keys.sorted() {
            guard var edge = model.edges[id] else { continue }
            let start = replacement[edge.startVertexID] ?? edge.startVertexID
            let end = replacement[edge.endVertexID] ?? edge.endVertexID
            // Original closed and pole spans retain their parameter incidence.
            if start == end, try BRepEdgeGeometryClassifier().kind(of: edge, in: model,
                tolerance: tolerance) == .open { continue }
            edge.startVertexID = start; edge.endVertexID = end
            model.edges[id] = edge
        }
        let referenced = Set(model.edges.values.flatMap { [$0.startVertexID, $0.endVertexID] })
        let deleted = replacement.keys.filter { !referenced.contains($0) }.sorted()
        for id in deleted { model.vertices[id] = nil }
        if !deleted.isEmpty {
            changes.append(.init(action: .sewWireVertices, scope: .loops,
                affectedEntityIDs: deleted.map { String(describing: $0) },
                message: "Sewed endpoint references to deterministic retained vertices within the unchanged tolerance.",
                maximumDisplacement: maximum, deletedEntityIDs: deleted.map { String(describing: $0) }))
        }
    }

    func removeDuplicateUses(model: inout BRepModel, tolerance: ModelingTolerance, changes: inout [BRepRepairChange]) throws {
        for id in model.loops.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard var loop=model.loops[id] else {continue}
            var retained:[Coedge]=[]
            for use in loop.coedges {
                // Opposite seam uses have distinct pcurves/directions and survive.
                if !retained.contains(use){retained.append(use)}
            }
            if retained != loop.coedges {
                loop.coedges=retained;model.loops[id]=loop
                changes.append(.init(action:.removeDuplicateWireUses,scope:.loops,
                    affectedEntityIDs:[String(describing:id)],message:"Removed exact duplicate coedge uses while retaining distinct periodic seam uses."))
            }
        }
    }

    func collapseSmallEdges(model: inout BRepModel,tolerance:ModelingTolerance,changes:inout[BRepRepairChange],
        collapsedCurves: inout [BRepRepairCollapsedCurve]) throws {
        let originalPoints=Dictionary(uniqueKeysWithValues:model.vertices.map{($0.key,$0.value.point)})
        var vertexOwners=Dictionary(uniqueKeysWithValues:model.vertices.keys.map{($0,Set([$0]))})
        for id in model.edges.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let edge=model.edges[id],edge.startVertexID != edge.endVertexID,
                let start=model.vertices[edge.startVertexID]?.point,
                let end=model.vertices[edge.endVertexID]?.point else{continue}
            guard try BRepEdgeGeometryClassifier().kind(of: edge, in: model, tolerance: tolerance) == .open else { continue }
            let length=try DefaultBRepEdgeLengthEvaluator().lengthEnclosure(of:edge,in:model,tolerance:tolerance)
            guard length.upperBound <= tolerance.distance, BRepRepairAudit().distanceUpperBound(start, end) <= tolerance.distance else{continue}
            guard let curve = model.geometry.curves[edge.curveID] else { continue }
            let interval = try DefaultBRepEdgeLengthEvaluator().parameterInterval(of: edge,
                curve: curve, in: model, tolerance: tolerance)
            let originalPosition = try DefaultCurveDifferentialEncloser().enclosure(of: curve,
                over: interval, tolerance: tolerance).position
            func distanceAxis(_ bounds: ScalarInterval, _ coordinate: Double) -> Double {
                max(abs((bounds.lower-coordinate).nextDown), abs((bounds.upper-coordinate).nextUp))
            }
            let x = distanceAxis(originalPosition.x, start.x), y = distanceAxis(originalPosition.y, start.y)
            let z = distanceAxis(originalPosition.z, start.z)
            let collapseDisplacement = BRepRepairAudit().magnitudeUpperBound(x,y,z)
            guard collapseDisplacement.isFinite, collapseDisplacement <= tolerance.distance else { continue }
            let affected=model.edges.values.filter{$0.id != id && ($0.startVertexID==edge.endVertexID || $0.endVertexID==edge.endVertexID)}
            guard affected.allSatisfy({ candidate in
                let other=candidate.startVertexID==edge.endVertexID ? candidate.endVertexID:candidate.startVertexID
                return other != edge.startVertexID
            })else{continue}
            // Original endpoint comparisons prevent a sequence of small edges
            // from drifting farther than the caller's one distance allowance.
            let collapsedOwners=vertexOwners[edge.endVertexID] ?? Set([edge.endVertexID])
            guard collapsedOwners.allSatisfy({ originalPoints[$0].map{BRepRepairAudit().distanceUpperBound($0, start) <= tolerance.distance} ?? false })else{continue}
            vertexOwners[edge.startVertexID,default:[]].formUnion(collapsedOwners)
            vertexOwners[edge.endVertexID]=nil
            for index in collapsedCurves.indices where collapsedCurves[index].retainedVertexID == edge.endVertexID {
                collapsedCurves[index].retainedVertexID = edge.startVertexID
            }
            collapsedCurves.append(.init(originalEdgeID: id, curve: curve, interval: interval,
                retainedVertexID: edge.startVertexID))
            for candidate in affected {
                var repaired=candidate
                if repaired.startVertexID==edge.endVertexID{repaired.startVertexID=edge.startVertexID}
                if repaired.endVertexID==edge.endVertexID{repaired.endVertexID=edge.startVertexID}
                model.edges[repaired.id]=repaired
            }
            for loopID in model.loops.keys.sorted(){
                guard var loop=model.loops[loopID]else{continue}
                loop.coedges.removeAll{$0.edgeID==id};model.loops[loopID]=loop
            }
            model.edges[id]=nil
            let stillUsed=model.edges.values.contains{$0.curveID==edge.curveID}
            if !stillUsed{model.geometry.curves[edge.curveID]=nil}
            model.vertices[edge.endVertexID]=nil
            changes.append(.init(action:.collapseSmallWireEdges,scope:.loops,
                affectedEntityIDs:[String(describing:id)],message:"Collapsed a completely length-certified small edge under the unchanged displacement allowance.",
                maximumDisplacement:collapseDisplacement,deletedEntityIDs:[String(describing:id),String(describing:edge.endVertexID)]+(stillUsed ? []:[String(describing:edge.curveID)])))
        }
    }

    func restoreCharts(model:inout BRepModel,tolerance:ModelingTolerance,changes:inout[BRepRepairChange])throws{
        for face in model.faces.values.sorted(by:{$0.id<$1.id}){
            guard let surface=model.geometry.surfaces[face.surfaceID]else{continue}
            let topology=try SurfaceParameterTopology(surface:surface)
            guard topology.uPeriod != nil || topology.vPeriod != nil else{continue}
            for id in face.loops{
                try CurrentTaskCancellationChecker().checkCancellation()
                guard var loop=model.loops[id],loop.coedges.allSatisfy({$0.surfaceParameterCurve != nil})else{continue}
                let curves=loop.coedges.compactMap({ $0.surfaceParameterCurve })
                let lifted=try SurfaceParameterLoopUnwrapper().unwrap(curves,on:surface,tolerance:tolerance,context:"Periodic chart repair")
                let repaired=lifted.map({ $0.translatedCurve })
                if repaired != curves{
                    for index in loop.coedges.indices{loop.coedges[index].surfaceParameterCurve=repaired[index]}
                    model.loops[id]=loop
                    changes.append(.init(action:.restorePeriodicCharts,scope:.pcurves,
                        affectedEntityIDs:[String(describing:id)],message:"Restored a continuous original periodic chart using only exact whole-period translations."))
                }
            }
        }
    }

    func sewShellEdges(model:inout BRepModel,tolerance:ModelingTolerance,changes:inout[BRepRepairChange])throws{
        var replacedEdges=Set<EdgeID>()
        for shell in model.shells.values.sorted(by:{$0.id<$1.id}){
            var canonical:[Edge]=[]
            for faceID in shell.faceIDs{
                guard let face=model.faces[faceID]else{continue}
                for loopID in face.loops{
                    guard var loop=model.loops[loopID]else{continue}
                    for index in loop.coedges.indices{
                        try CurrentTaskCancellationChecker().checkCancellation()
                        let use=loop.coedges[index]
                        guard let edge=model.edges[use.edgeID],let curve=model.geometry.curves[edge.curveID]else{continue}
                        guard try BRepEdgeGeometryClassifier().kind(of:edge,in:model,tolerance:tolerance) != .singular else{continue}
                        let match=canonical.first{candidate in
                            guard model.geometry.curves[candidate.curveID]==curve else{return false}
                            let same=candidate.startVertexID==edge.startVertexID && candidate.endVertexID==edge.endVertexID && candidate.trim==edge.trim
                            let reverse=candidate.startVertexID==edge.endVertexID && candidate.endVertexID==edge.startVertexID
                                && candidate.trim?.startParameter==edge.trim?.endParameter && candidate.trim?.endParameter==edge.trim?.startParameter
                            return same || reverse
                        }
                        if let match,match.id != edge.id{
                            replacedEdges.insert(edge.id)
                            let reverse = match.trim != edge.trim
                                && match.trim?.startParameter == edge.trim?.endParameter
                                && match.trim?.endParameter == edge.trim?.startParameter
                            loop.coedges[index].edgeID=match.id
                            if reverse{loop.coedges[index].orientation=use.orientation == .forward ? .reversed:.forward}
                            changes.append(.init(action:.sewShellEdges,scope:.watertight,
                                affectedEntityIDs:[String(describing:edge.id),String(describing:match.id)],
                                message:"Joined identical original curve spans and retained both face-local pcurves."))
                        }else if match==nil{canonical.append(edge)}
                    }
                    model.loops[loopID]=loop
                }
            }
        }
        let referenced=Set(model.loops.values.flatMap{$0.coedges.map({ $0.edgeID })})
        let removed=replacedEdges.filter{!referenced.contains($0)}.sorted()
        let replacedCurveIDs=Set(removed.compactMap{model.edges[$0]?.curveID})
        for id in removed{model.edges[id]=nil}
        let curveIDs=Set(model.edges.values.map({ $0.curveID }))
        let removedCurves=replacedCurveIDs.filter{!curveIDs.contains($0)}.sorted()
        for id in removedCurves{model.geometry.curves[id]=nil}
        if !removed.isEmpty || !removedCurves.isEmpty {
            let deleted=removed.map{String(describing:$0)}+removedCurves.map{String(describing:$0)}
            changes.append(.init(action:.sewShellEdges,scope:.references,affectedEntityIDs:deleted,
                message:"Removed representations made unreachable by shell edge sewing.",deletedEntityIDs:deleted))
        }
    }

    func orientShells(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic]) throws {
        for shellID in model.shells.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let shell = model.shells[shellID] else { continue }
            var incidence: [EdgeID: [(FaceID, Orientation)]] = [:]
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    for use in model.loops[loopID]?.coedges ?? [] { incidence[use.edgeID, default: []].append((faceID, use.orientation)) }
                }
            }
            var flips: [FaceID: Bool] = [:]
            var consistent = true
            for seed in shell.faceIDs.sorted() where flips[seed] == nil {
                flips[seed] = false
                var queue = [seed]; var cursor = 0
                while cursor < queue.count {
                    let current = queue[cursor]; cursor += 1
                    for uses in incidence.values where uses.count == 2 && uses.contains(where: { $0.0 == current }) {
                        let a = uses[0], b = uses[1]
                        guard a.0 != b.0 else { continue }
                        let next = a.0 == current ? b.0 : a.0
                        let required = (flips[current] ?? false) != (a.1 == b.1)
                        if let known = flips[next] { if known != required { consistent = false } }
                        else { flips[next] = required; queue.append(next) }
                    }
                }
            }
            guard consistent else {
                diagnostics.append(.init(action: .orientShellFaces, code: .topologyFailure,
                    entityID: String(describing: shellID), message: "Shell incidence has contradictory orientation constraints.")); continue
            }
            var changed: [String] = []
            for faceID in shell.faceIDs.sorted() where flips[faceID] == true {
                guard var face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    guard var loop = model.loops[loopID] else { continue }
                    loop.coedges = try loop.coedges.reversed().map { use in
                        Coedge(edgeID: use.edgeID, orientation: use.orientation == .forward ? .reversed : .forward,
                            surfaceParameterCurve: try use.surfaceParameterCurve?.reversed(tolerance: tolerance))
                    }
                    model.loops[loopID] = loop
                }
                face.orientation = face.orientation == .forward ? .reversed : .forward
                model.faces[faceID] = face; changed.append(String(describing: faceID))
            }
            if !changed.isEmpty { changes.append(.init(action: .orientShellFaces, scope: .orientation,
                affectedEntityIDs: changed, message: "Reconciled shell coedge incidence and face orientation without changing support geometry.")) }
        }
    }
    func orientSolidComponents(model: inout BRepModel,tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange],diagnostics: inout [BRepRepairDiagnostic]) throws {
        var roles: [ShellID: Orientation] = [:]
        for bodyID in model.bodies.keys.sorted() {
            guard let components = model.bodies[bodyID]?.solidComponents else { continue }
            for component in components {
                roles[component.outerShellID] = .forward
                for id in component.voidShellIDs { roles[id] = .reversed }
            }
        }
        for id in roles.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard var shell = model.shells[id],let role = roles[id] else { continue }
            if shell.orientation != role {
                shell.orientation = role; model.shells[id] = shell
                changes.append(.init(action: .orientSolidComponents,scope: .orientation,
                    affectedEntityIDs: [String(describing: id)],
                    message: "Restored explicit solid outer/void shell orientation without changing component ownership."))
            }
        }
        for id in roles.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let shell = model.shells[id] else { continue }
            let signed: TrimmedParametricSurfaceVolumeEvaluator.VolumeBounds
            do { signed = try TrimmedParametricSurfaceVolumeEvaluator().volumeBounds(of: shell,in: model,tolerance: tolerance) }
            catch is CancellationError { throw CancellationError() }
            catch {
                diagnostics.append(.init(action: .orientSolidComponents,code: .topologyFailure,
                    entityID: String(describing: id),
                    message: "Original signed-shell volume could not certify component orientation: \(KernelError.wrapping(error, phase: .topology, tolerance: tolerance).message)."))
                continue
            }
            if signed.lower > 0 { continue }
            guard signed.upper < 0 else {
                diagnostics.append(.init(action: .orientSolidComponents,code: .topologyFailure,
                    entityID: String(describing: id),
                    message: "Original signed-shell volume straddles zero; component orientation is unresolved."))
                continue
            }
            for faceID in shell.faceIDs {
                guard var face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    guard var loop = model.loops[loopID] else { continue }
                    loop.coedges = try loop.coedges.reversed().map { use in
                        Coedge(edgeID: use.edgeID,orientation: use.orientation == .forward ? .reversed : .forward,
                            surfaceParameterCurve: try use.surfaceParameterCurve?.reversed(tolerance: tolerance))
                    }
                    model.loops[loopID] = loop
                }
                face.orientation = face.orientation == .forward ? .reversed : .forward
                model.faces[faceID] = face
            }
            changes.append(.init(action: .orientSolidComponents,scope: .volume,
                affectedEntityIDs: shell.faceIDs.map { String(describing: $0) },
                message: "Oriented an original volume-certified shell boundary outward before applying its explicit material/void role."))
        }
    }

}
