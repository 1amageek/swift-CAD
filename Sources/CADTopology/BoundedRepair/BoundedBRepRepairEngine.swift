import HashTreeCollections
import CADCore
import CADGeometry

struct BoundedBRepRepairEngine {
    func reconstructCurves(
        model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic],
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.checkpoint()
        let correspondence = DefaultCurveSurfaceCorrespondenceValidator()
        for faceID in try OriginalParameterQueryStorage.ordered(model.faces.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard var loop = model.loops[loopID] else { continue }
                var needsCoedgeCopy = true
                for index in loop.coedges.indices {
                    try execution.consumeWork(1)
                    let use = loop.coedges[index]
                    guard var edge = model.edges[use.edgeID] else { continue }
                    let originalCurve = model.geometry.curves[edge.curveID]
                    if originalCurve == nil, let pcurve = use.surfaceParameterCurve {
                        let canonical = use.orientation == .forward ? pcurve : try pcurve.reversed(tolerance: tolerance, using: &execution)
                        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: canonical))
                        try curve.validate(tolerance: tolerance, using: &execution)
                        guard let start = model.vertices[edge.startVertexID]?.point,
                              let end = model.vertices[edge.endVertexID]?.point,
                              try BRepRepairAudit().stationDisplacementUpperBound(of: curve, at: 0,
                                from: start, tolerance: tolerance, using: &execution) <= tolerance.distance,
                              try BRepRepairAudit().stationDisplacementUpperBound(of: curve, at: 1,
                                from: end, tolerance: tolerance, using: &execution) <= tolerance.distance else {
                            try appendDiagnostic(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                entityID: try BRepRepairAudit().describe(edge.id, using: &execution), message: "The lifted missing curve disagrees with its retained vertices."), to: &diagnostics, using: &execution)
                            continue
                        }
                        // Every existing incident pcurve is checked before canonical publication.
                        var admitted = true
                        for incidentFace in model.faces.values {
                            try execution.consumeWork(1)
                            guard let support = model.geometry.surfaces[incidentFace.surfaceID] else { continue }
                            for incidentLoopID in incidentFace.loops {
                                try execution.consumeWork(1)
                                guard let incidentLoop = model.loops[incidentLoopID] else { continue }
                                for incident in incidentLoop.coedges {
                                    try execution.consumeWork(1)
                                    guard incident.edgeID == edge.id else { continue }
                                    guard let local = incident.surfaceParameterCurve else { admitted = false; continue }
                                    do {
                                        try correspondence.validate(curve: curve,
                                            from: incident.orientation == .forward ? 0 : 1,
                                            to: incident.orientation == .forward ? 1 : 0,
                                            surface: support, parameterCurve: local, options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance, using: &execution)
                                    } catch {
                                        _ = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                                        admitted = false
                                    }
                                }
                            }
                        }
                        if admitted {
                            try OriginalParameterQueryStorage.set(curve, for: edge.curveID, in: &model.geometry.curves, using: &execution)
                            edge.trim = CurveTrim(startParameter: 0, endParameter: 1)
                            try OriginalParameterQueryStorage.set(edge, for: edge.id, in: &model.edges, using: &execution)
                            try appendChange(.init(action: .reconstructCurveRepresentations, scope: .pcurves,
                                affectedEntityIDs: try identifiers(edge.id, using: &execution),
                                message: "Reconstructed a missing canonical curve from its original surface lift after all incident correspondence proofs.",
                                maximumDisplacement: tolerance.distance,
                                generatedEntityIDs: try identifiers(edge.curveID, using: &execution)), to: &changes, using: &execution)
                        } else {
                            try appendDiagnostic(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                entityID: try BRepRepairAudit().describe(edge.id, using: &execution), message: "Incident pcurves do not establish one canonical lifted edge."), to: &diagnostics, using: &execution)
                        }
                    } else if let curve = originalCurve, let trim = edge.trim, use.surfaceParameterCurve == nil {
                        let start = use.orientation == .forward ? trim.startParameter : trim.endParameter
                        let end = use.orientation == .forward ? trim.endParameter : trim.startParameter
                        if let local = try retainedLiftPcurve(curve: curve, from: start, to: end,
                            surface: surface, tolerance: tolerance, using: &execution) {
                            do {
                                try correspondence.validate(curve: curve, from: start, to: end,
                                    surface: surface, parameterCurve: local,
                                    options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32,
                                        maximumCellCount: 65_536), tolerance: tolerance, using: &execution)
                                try admitCoedgeMutation(loop, needsCopy: &needsCoedgeCopy, using: &execution)
                                loop.coedges[index].surfaceParameterCurve = local
                                try appendChange(.init(action: .reconstructCurveRepresentations, scope: .pcurves,
                                    affectedEntityIDs: try identifiers(edge.id, using: &execution),
                                    message: "Reconstructed a missing directed pcurve from retained original hosting provenance after whole correspondence proof.",
                                    maximumDisplacement: tolerance.distance), to: &changes, using: &execution)
                            } catch {
                                _ = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                                try appendDiagnostic(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                    entityID: try BRepRepairAudit().describe(edge.id, using: &execution),
                                    message: "The retained original hosting pcurve could not establish whole directed correspondence."), to: &diagnostics, using: &execution)
                            }
                        } else {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Production reconstructCurveRepresentations
                            // still needs the Geometry complete original inverse-chart producer for
                            // spatial curves without matching retained hosting provenance. It must
                            // reconstruct and prove every directed support branch before this repair
                            // domain can be reported as complete; missing pcurves remain diagnostics.
                            try appendDiagnostic(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                entityID: try BRepRepairAudit().describe(edge.id, using: &execution),
                                message: "Missing pcurve has no matching retained original hosting provenance or complete inverse-chart producer."), to: &diagnostics, using: &execution)
                        }
                    } else if let curve = originalCurve, let trim = edge.trim, let local = use.surfaceParameterCurve {
                        let start = use.orientation == .forward ? trim.startParameter : trim.endParameter
                        let end = use.orientation == .forward ? trim.endParameter : trim.startParameter
                        do {
                            try correspondence.validate(curve: curve, from: start, to: end,
                                surface: surface, parameterCurve: local, options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance, using: &execution)
                        } catch {
                            _ = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                            let reversed = try local.reversed(tolerance: tolerance, using: &execution)
                            do {
                                try correspondence.validate(curve: curve, from: start, to: end,
                                    surface: surface, parameterCurve: reversed, options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance, using: &execution)
                                try admitCoedgeMutation(loop, needsCopy: &needsCoedgeCopy, using: &execution)
                                loop.coedges[index].surfaceParameterCurve = reversed
                                try appendChange(.init(action: .reconstructCurveRepresentations, scope: .pcurves,
                                    affectedEntityIDs: try identifiers(edge.id, using: &execution), message: "Reversed a pcurve after complete directed correspondence proof."), to: &changes, using: &execution)
                            } catch {
                                _ = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                                try appendDiagnostic(.init(action: .reconstructCurveRepresentations, code: .topologyFailure,
                                    entityID: try BRepRepairAudit().describe(edge.id, using: &execution), message: "Existing spatial curve and pcurve have no proved directed correspondence."), to: &diagnostics, using: &execution)
                            }
                        }
                    }
                }
                try OriginalParameterQueryStorage.set(loop, for: loopID, in: &model.loops, using: &execution)
            }
        }
        try execution.checkpoint()
    }

    private func retainedLiftPcurve(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try execution.consumeWork(1)
        guard start >= 0, start <= 1, end >= 0, end <= 1, start != end else { return nil }
        switch curve {
        case .surfaceLift(let lift):
            try GeometryStructuralComparisonWork.charge(surface: lift.surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
            guard lift.surface == surface else { return nil }
            let directed: SurfaceParameterCurve
            if min(start,end) == 0, max(start,end) == 1 { directed = lift.parameterCurve }
            else {
                directed = try lift.parameterCurve.subcurve(fromNormalizedFraction: min(start,end),
                    toNormalizedFraction: max(start,end), tolerance: tolerance, using: &execution)
            }
            return start < end ? directed : try directed.reversed(tolerance: tolerance, using: &execution)
        case .originalAffineWord(let image):
            guard case .surfaceLift(let lift) = image.source,
                case .procedural(.originalAffineWord(let target)) = surface else { return nil }
            try GeometryStructuralComparisonWork.charge(surface: lift.surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: target.source, using: &execution)
            try GeometryStructuralComparisonWork.charge(word: image.operationWord, using: &execution)
            try GeometryStructuralComparisonWork.charge(word: target.operationWord, using: &execution)
            guard lift.surface == target.source, image.operationWord == target.operationWord else { return nil }
            return .originalAffineWord(try OriginalAffineWordSurfaceParameterCurve(source: lift,
                target: target, startFraction: start, endFraction: end, tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution))
        case .affineImage(let image):
            guard case .surfaceLift(let lift) = image.source,
                case .procedural(.originalImage(let target)) = surface else { return nil }
            try GeometryStructuralComparisonWork.charge(surface: lift.surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: target.source, using: &execution)
            guard lift.surface == target.source, image.transform == target.transform else { return nil }
            return .originalImage(try OriginalImageSurfaceParameterCurve(source: lift, targetImage: target,
                startFraction: start, endFraction: end, tolerance: tolerance, using: &execution))
        default: return nil
        }
    }

    func sewVertices(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        var replacement: [VertexID: VertexID] = [:]
        var retained: [VertexID] = []
        var maximum = 0.0
        for id in try OriginalParameterQueryStorage.ordered(model.vertices.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let vertex = model.vertices[id] else { continue }
            if let owner = try OriginalParameterQueryStorage.first(retained, using: &execution, predicate: { candidate, execution in
                guard let point = model.vertices[candidate]?.point else { return false }
                return BRepRepairAudit().distanceUpperBound(point, vertex.point) <= tolerance.distance
            }), let point = model.vertices[owner]?.point {
                // Direct comparison to the final retained owner prevents chain-drift.
                try OriginalParameterQueryStorage.set(owner, for: id, in: &replacement, using: &execution)
                try execution.consumeWork(1)
                maximum = max(maximum, BRepRepairAudit().distanceUpperBound(point, vertex.point))
            } else { try OriginalParameterQueryStorage.append(id, to: &retained, using: &execution) }
        }
        for id in try OriginalParameterQueryStorage.ordered(model.edges.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard var edge = model.edges[id] else { continue }
            let start = replacement[edge.startVertexID] ?? edge.startVertexID
            let end = replacement[edge.endVertexID] ?? edge.endVertexID
            // Original closed and pole spans retain their parameter incidence.
            if start == end, try classifiedKind(of: edge, in: model,
                tolerance: tolerance, using: &execution) == .open { continue }
            edge.startVertexID = start; edge.endVertexID = end
            try OriginalParameterQueryStorage.set(edge, for: id, in: &model.edges, using: &execution)
        }
        var referenced = Set<VertexID>()
        for edge in model.edges.values {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &referenced, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &referenced, using: &execution)
        }
        var deleted = try OriginalParameterQueryStorage.filter(replacement.keys, using: &execution) { id, execution in
            !referenced.contains(id)
        }
        try OriginalParameterQueryStorage.sort(&deleted, using: &execution, less: <)
        for id in deleted { try remove(id, from: &model.vertices, using: &execution) }
        if !deleted.isEmpty {
            let affected = try descriptions(deleted, using: &execution)
            let deletedIDs = try descriptions(deleted, using: &execution)
            try appendChange(.init(action: .sewWireVertices, scope: .loops,
                affectedEntityIDs: affected,
                message: "Sewed endpoint references to deterministic retained vertices within the unchanged tolerance.",
                maximumDisplacement: maximum, deletedEntityIDs: deletedIDs), to: &changes, using: &execution)
        }
        try execution.checkpoint()
    }

    func removeDuplicateUses(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        for id in try OriginalParameterQueryStorage.ordered(model.loops.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard var loop = model.loops[id] else { continue }
            var retained: [Coedge] = []
            for use in loop.coedges {
                try execution.consumeWork(1)
                // Opposite seam uses have distinct pcurves/directions and survive.
                if try !OriginalParameterQueryStorage.contains(retained, using: &execution, predicate: { candidate, execution in
                    try sameUse(candidate, use, using: &execution)
                }) { try OriginalParameterQueryStorage.append(use, to: &retained, using: &execution) }
            }
            if try !sameUses(retained, loop.coedges, using: &execution) {
                loop.coedges = retained
                try OriginalParameterQueryStorage.set(loop, for: id, in: &model.loops, using: &execution)
                try appendChange(.init(action: .removeDuplicateWireUses, scope: .loops,
                    affectedEntityIDs: try identifiers(id, using: &execution),
                    message: "Removed exact duplicate coedge uses while retaining distinct periodic seam uses."),
                    to: &changes, using: &execution)
            }
        }
        try execution.checkpoint()
    }

    func collapseSmallEdges(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], collapsedCurves: inout [BRepRepairCollapsedCurve],
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        var originalPoints: [VertexID: Point3D] = [:]
        var vertexOwners: [VertexID: Set<VertexID>] = [:]
        for (id, vertex) in model.vertices {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.set(vertex.point, for: id, in: &originalPoints, using: &execution)
        }
        for id in model.vertices.keys {
            var owners = Set<VertexID>()
            try OriginalParameterQueryStorage.insert(id, in: &owners, using: &execution)
            try OriginalParameterQueryStorage.set(owners, for: id, in: &vertexOwners, using: &execution)
        }
        var needsLedgerCopy = true
        for id in try OriginalParameterQueryStorage.ordered(model.edges.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let edge = model.edges[id], edge.startVertexID != edge.endVertexID,
                let start = model.vertices[edge.startVertexID]?.point,
                let end = model.vertices[edge.endVertexID]?.point else { continue }
            guard try classifiedKind(of: edge, in: model,
                tolerance: tolerance, using: &execution) == .open else { continue }
            let length = try DefaultBRepEdgeLengthEvaluator().lengthEnclosure(of: edge, in: model,
                tolerance: tolerance, using: &execution)
            try execution.consumeWork(1)
            guard length.upperBound <= tolerance.distance,
                BRepRepairAudit().distanceUpperBound(start, end) <= tolerance.distance else { continue }
            guard let curve = model.geometry.curves[edge.curveID] else { continue }
            let interval = try DefaultBRepEdgeLengthEvaluator().parameterInterval(of: edge,
                curve: curve, in: model, tolerance: tolerance, using: &execution)
            let originalPosition = try DefaultCurveDifferentialEncloser().enclosure(of: curve,
                over: interval, tolerance: tolerance, using: &execution).position
            func distanceAxis(_ bounds: ScalarInterval, _ coordinate: Double) -> Double {
                max(abs((bounds.lower - coordinate).nextDown), abs((bounds.upper - coordinate).nextUp))
            }
            let x = distanceAxis(originalPosition.x, start.x), y = distanceAxis(originalPosition.y, start.y)
            let z = distanceAxis(originalPosition.z, start.z)
            try execution.consumeWork(1)
            let collapseDisplacement = BRepRepairAudit().magnitudeUpperBound(x, y, z)
            guard collapseDisplacement.isFinite, collapseDisplacement <= tolerance.distance else { continue }
            let affected = try OriginalParameterQueryStorage.filter(model.edges.values, using: &execution) { candidate, execution in
                candidate.id != id && (candidate.startVertexID == edge.endVertexID || candidate.endVertexID == edge.endVertexID)
            }
            guard try OriginalParameterQueryStorage.allSatisfy(affected, using: &execution, predicate: { candidate, execution in
                let other = candidate.startVertexID == edge.endVertexID ? candidate.endVertexID : candidate.startVertexID
                return other != edge.startVertexID
            }) else { continue }
            // Original endpoint comparisons prevent a sequence of small edges
            // from drifting farther than the caller's one distance allowance.
            let collapsedOwners: Set<VertexID>
            if let owners = vertexOwners[edge.endVertexID] { collapsedOwners = owners }
            else {
                var owners = Set<VertexID>()
                try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &owners, using: &execution)
                collapsedOwners = owners
            }
            guard try OriginalParameterQueryStorage.allSatisfy(collapsedOwners, using: &execution, predicate: { id, execution in
                guard let point = originalPoints[id] else { return false }
                return BRepRepairAudit().distanceUpperBound(point, start) <= tolerance.distance
            }) else { continue }
            var owners = vertexOwners[edge.startVertexID] ?? []
            // The local value shares its retained set backing until this union mutates it.
            try execution.retainStorage(count: owners.count, stride: MemoryLayout<VertexID>.stride)
            for owner in collapsedOwners { try OriginalParameterQueryStorage.insert(owner, in: &owners, using: &execution) }
            try OriginalParameterQueryStorage.set(owners, for: edge.startVertexID, in: &vertexOwners, using: &execution)
            try execution.consumeWork(1)
            vertexOwners[edge.endVertexID] = nil
            for index in collapsedCurves.indices {
                try execution.consumeWork(1)
                guard collapsedCurves[index].retainedVertexID == edge.endVertexID else { continue }
                if needsLedgerCopy {
                    try execution.retainStorage(count: collapsedCurves.count, stride: MemoryLayout<BRepRepairCollapsedCurve>.stride)
                    needsLedgerCopy = false
                }
                collapsedCurves[index].retainedVertexID = edge.startVertexID
            }
            if needsLedgerCopy && collapsedCurves.count < collapsedCurves.capacity {
                try execution.retainStorage(count: collapsedCurves.capacity, stride: MemoryLayout<BRepRepairCollapsedCurve>.stride)
            }
            needsLedgerCopy = false
            try OriginalParameterQueryStorage.append(.init(originalEdgeID: id, curve: curve, interval: interval,
                retainedVertexID: edge.startVertexID), to: &collapsedCurves, using: &execution)
            for candidate in affected {
                try execution.consumeWork(1)
                var repaired = candidate
                if repaired.startVertexID == edge.endVertexID { repaired.startVertexID = edge.startVertexID }
                if repaired.endVertexID == edge.endVertexID { repaired.endVertexID = edge.startVertexID }
                try OriginalParameterQueryStorage.set(repaired, for: repaired.id, in: &model.edges, using: &execution)
            }
            for loopID in try OriginalParameterQueryStorage.ordered(model.loops.keys, using: &execution, less: <) {
                try execution.consumeWork(1)
                guard var loop = model.loops[loopID] else { continue }
                try execution.retainStorage(count: loop.coedges.count, stride: MemoryLayout<Coedge>.stride)
                try loop.coedges.removeAll { use in
                    try execution.consumeWork(1)
                    return use.edgeID == id
                }
                try OriginalParameterQueryStorage.set(loop, for: loopID, in: &model.loops, using: &execution)
            }
            try remove(id, from: &model.edges, using: &execution)
            let stillUsed = try OriginalParameterQueryStorage.contains(model.edges.values, using: &execution) { candidate, execution in
                candidate.curveID == edge.curveID
            }
            if !stillUsed { try remove(edge.curveID, from: &model.geometry.curves, using: &execution) }
            try remove(edge.endVertexID, from: &model.vertices, using: &execution)
            var deleted = try identifiers(id, edge.endVertexID, using: &execution)
            if !stillUsed {
                try OriginalParameterQueryStorage.append(try BRepRepairAudit().describe(edge.curveID, using: &execution),
                    to: &deleted, using: &execution)
            }
            try appendChange(.init(action: .collapseSmallWireEdges, scope: .loops,
                affectedEntityIDs: try identifiers(id, using: &execution),
                message: "Collapsed a completely length-certified small edge under the unchanged displacement allowance.",
                maximumDisplacement: collapseDisplacement, deletedEntityIDs: deleted), to: &changes, using: &execution)
        }
        try execution.checkpoint()
    }

    func restoreCharts(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        for face in try OriginalParameterQueryStorage.ordered(model.faces.values, using: &execution, less: { $0.id < $1.id }) {
            try execution.consumeWork(1)
            guard let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            let topology = try SurfaceParameterTopology(surface: surface, using: &execution)
            guard topology.uPeriod != nil || topology.vPeriod != nil else { continue }
            for id in face.loops {
                try execution.consumeWork(1)
                guard var loop = model.loops[id],
                    try OriginalParameterQueryStorage.allSatisfy(loop.coedges, using: &execution, predicate: { use, execution in
                        use.surfaceParameterCurve != nil
                    }) else { continue }
                let curves = try OriginalParameterQueryStorage.compactMap(loop.coedges, using: &execution) { use, execution in
                    use.surfaceParameterCurve
                }
                let lifted = try SurfaceParameterLoopUnwrapper().unwrap(curves, on: surface, tolerance: tolerance,
                    context: "Periodic chart repair", maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                    maximumAlgebraicDepth: nil, using: &execution)
                let repaired = try OriginalParameterQueryStorage.map(lifted, using: &execution) { lift, execution in
                    lift.translatedCurve
                }
                if try !sameParameterCurves(repaired, curves, using: &execution) {
                    try execution.retainStorage(count: loop.coedges.count, stride: MemoryLayout<Coedge>.stride)
                    for index in loop.coedges.indices {
                        try execution.consumeWork(1)
                        loop.coedges[index].surfaceParameterCurve = repaired[index]
                    }
                    try OriginalParameterQueryStorage.set(loop, for: id, in: &model.loops, using: &execution)
                    try appendChange(.init(action: .restorePeriodicCharts, scope: .pcurves,
                        affectedEntityIDs: try identifiers(id, using: &execution),
                        message: "Restored a continuous original periodic chart using only exact whole-period translations."),
                        to: &changes, using: &execution)
                }
            }
        }
        try execution.checkpoint()
    }

    func sewShellEdges(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        var replacedEdges = Set<EdgeID>()
        for shell in try OriginalParameterQueryStorage.ordered(model.shells.values, using: &execution, less: { $0.id < $1.id }) {
            try execution.consumeWork(1)
            var canonical: [Edge] = []
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                guard let face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    guard var loop = model.loops[loopID] else { continue }
                    var needsCoedgeCopy = true
                    for index in loop.coedges.indices {
                        try execution.consumeWork(1)
                        let use = loop.coedges[index]
                        guard let edge = model.edges[use.edgeID], let curve = model.geometry.curves[edge.curveID] else { continue }
                        guard try classifiedKind(of: edge, in: model,
                            tolerance: tolerance, using: &execution) != .singular else { continue }
                        let match = try OriginalParameterQueryStorage.first(canonical, using: &execution) { candidate, execution in
                            guard let source = model.geometry.curves[candidate.curveID] else { return false }
                            try GeometryStructuralComparisonWork.charge(curve: source, using: &execution)
                            try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
                            guard source == curve else { return false }
                            let same = candidate.startVertexID == edge.startVertexID && candidate.endVertexID == edge.endVertexID && candidate.trim == edge.trim
                            let reverse = candidate.startVertexID == edge.endVertexID && candidate.endVertexID == edge.startVertexID
                                && candidate.trim?.startParameter == edge.trim?.endParameter && candidate.trim?.endParameter == edge.trim?.startParameter
                            return same || reverse
                        }
                        if let match, match.id != edge.id {
                            try OriginalParameterQueryStorage.insert(edge.id, in: &replacedEdges, using: &execution)
                            let reverse = match.trim != edge.trim
                                && match.trim?.startParameter == edge.trim?.endParameter
                                && match.trim?.endParameter == edge.trim?.startParameter
                            try admitCoedgeMutation(loop, needsCopy: &needsCoedgeCopy, using: &execution)
                            loop.coedges[index].edgeID = match.id
                            if reverse { loop.coedges[index].orientation = use.orientation == .forward ? .reversed : .forward }
                            try appendChange(.init(action: .sewShellEdges, scope: .watertight,
                                affectedEntityIDs: try identifiers(edge.id, match.id, using: &execution),
                                message: "Joined identical original curve spans and retained both face-local pcurves."),
                                to: &changes, using: &execution)
                        } else if match == nil { try OriginalParameterQueryStorage.append(edge, to: &canonical, using: &execution) }
                    }
                    try OriginalParameterQueryStorage.set(loop, for: loopID, in: &model.loops, using: &execution)
                }
            }
        }
        var referenced = Set<EdgeID>()
        for loop in model.loops.values {
            try execution.consumeWork(1)
            for use in loop.coedges { try OriginalParameterQueryStorage.insert(use.edgeID, in: &referenced, using: &execution) }
        }
        var removed = try OriginalParameterQueryStorage.filter(replacedEdges, using: &execution) { id, execution in !referenced.contains(id) }
        try OriginalParameterQueryStorage.sort(&removed, using: &execution, less: <)
        var replacedCurveIDs = Set<CurveID>()
        for id in removed {
            try execution.consumeWork(1)
            if let curveID = model.edges[id]?.curveID { try OriginalParameterQueryStorage.insert(curveID, in: &replacedCurveIDs, using: &execution) }
        }
        for id in removed { try remove(id, from: &model.edges, using: &execution) }
        var curveIDs = Set<CurveID>()
        for edge in model.edges.values { try OriginalParameterQueryStorage.insert(edge.curveID, in: &curveIDs, using: &execution) }
        var removedCurves = try OriginalParameterQueryStorage.filter(replacedCurveIDs, using: &execution) { id, execution in !curveIDs.contains(id) }
        try OriginalParameterQueryStorage.sort(&removedCurves, using: &execution, less: <)
        for id in removedCurves { try remove(id, from: &model.geometry.curves, using: &execution) }
        if !removed.isEmpty || !removedCurves.isEmpty {
            let first = try descriptions(removed, using: &execution), second = try descriptions(removedCurves, using: &execution)
            let deleted = try OriginalParameterQueryStorage.concatenated(first, second, using: &execution)
            try appendChange(.init(action: .sewShellEdges, scope: .references, affectedEntityIDs: deleted,
                message: "Removed representations made unreachable by shell edge sewing.", deletedEntityIDs: deleted),
                to: &changes, using: &execution)
        }
        try execution.checkpoint()
    }

    func orientShells(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic],
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        for shellID in try OriginalParameterQueryStorage.ordered(model.shells.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else { continue }
            var incidence: [EdgeID: [(FaceID, Orientation)]] = [:]
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                guard let face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    for use in model.loops[loopID]?.coedges ?? [] {
                        try execution.consumeWork(1)
                        var uses = incidence[use.edgeID] ?? []
                        // Reading the dictionary value shares its COW array before append.
                        if uses.count < uses.capacity {
                            try execution.retainStorage(count: uses.capacity, stride: MemoryLayout<(FaceID, Orientation)>.stride)
                        }
                        try OriginalParameterQueryStorage.append((faceID, use.orientation), to: &uses, using: &execution)
                        try OriginalParameterQueryStorage.set(uses, for: use.edgeID, in: &incidence, using: &execution)
                    }
                }
            }
            var flips: [FaceID: Bool] = [:]
            var consistent = true
            let seeds = try OriginalParameterQueryStorage.ordered(shell.faceIDs, using: &execution, less: <)
            for seed in seeds {
                try execution.consumeWork(1)
                guard flips[seed] == nil else { continue }
                try OriginalParameterQueryStorage.set(false, for: seed, in: &flips, using: &execution)
                var queue: [FaceID] = []
                try OriginalParameterQueryStorage.append(seed, to: &queue, using: &execution)
                var cursor = 0
                while cursor < queue.count {
                    try execution.consumeWork(1)
                    let current = queue[cursor]; cursor += 1
                    for uses in incidence.values {
                        try execution.consumeWork(1)
                        guard uses.count == 2,
                            try OriginalParameterQueryStorage.contains(uses, using: &execution, predicate: { use, execution in use.0 == current }) else { continue }
                        let a = uses[0], b = uses[1]
                        guard a.0 != b.0 else { continue }
                        let next = a.0 == current ? b.0 : a.0
                        let required = (flips[current] ?? false) != (a.1 == b.1)
                        if let known = flips[next] { if known != required { consistent = false } }
                        else {
                            try OriginalParameterQueryStorage.set(required, for: next, in: &flips, using: &execution)
                            try OriginalParameterQueryStorage.append(next, to: &queue, using: &execution)
                        }
                    }
                }
            }
            guard consistent else {
                try appendDiagnostic(.init(action: .orientShellFaces, code: .topologyFailure,
                    entityID: try BRepRepairAudit().describe(shellID, using: &execution),
                    message: "Shell incidence has contradictory orientation constraints."), to: &diagnostics, using: &execution)
                continue
            }
            var changed: [String] = []
            for faceID in try OriginalParameterQueryStorage.ordered(shell.faceIDs, using: &execution, less: <) {
                try execution.consumeWork(1)
                guard flips[faceID] == true, var face = model.faces[faceID] else { continue }
                try reverseLoops(of: face, in: &model, tolerance: tolerance, using: &execution)
                face.orientation = face.orientation == .forward ? .reversed : .forward
                try OriginalParameterQueryStorage.set(face, for: faceID, in: &model.faces, using: &execution)
                try OriginalParameterQueryStorage.append(try BRepRepairAudit().describe(faceID, using: &execution), to: &changed, using: &execution)
            }
            if !changed.isEmpty {
                try appendChange(.init(action: .orientShellFaces, scope: .orientation, affectedEntityIDs: changed,
                    message: "Reconciled shell coedge incidence and face orientation without changing support geometry."),
                    to: &changes, using: &execution)
            }
        }
        try execution.checkpoint()
    }

    func orientSolidComponents(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic],
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        var roles: [ShellID: Orientation] = [:]
        for bodyID in try OriginalParameterQueryStorage.ordered(model.bodies.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let components = model.bodies[bodyID]?.solidComponents else { continue }
            for component in components {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.set(.forward, for: component.outerShellID, in: &roles, using: &execution)
                for id in component.voidShellIDs { try OriginalParameterQueryStorage.set(.reversed, for: id, in: &roles, using: &execution) }
            }
        }
        for id in try OriginalParameterQueryStorage.ordered(roles.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard var shell = model.shells[id], let role = roles[id] else { continue }
            if shell.orientation != role {
                shell.orientation = role
                try OriginalParameterQueryStorage.set(shell, for: id, in: &model.shells, using: &execution)
                try appendChange(.init(action: .orientSolidComponents, scope: .orientation,
                    affectedEntityIDs: try identifiers(id, using: &execution),
                    message: "Restored explicit solid outer/void shell orientation without changing component ownership."),
                    to: &changes, using: &execution)
            }
        }
        for id in try OriginalParameterQueryStorage.ordered(roles.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let shell = model.shells[id] else { continue }
            let signed: TrimmedParametricSurfaceVolumeEvaluator.VolumeBounds
            do {
                signed = try TrimmedParametricSurfaceVolumeEvaluator().volumeBounds(of: shell, in: model,
                    tolerance: tolerance, using: &execution)
            } catch {
                let finding = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                try appendDiagnostic(.init(action: .orientSolidComponents, code: .topologyFailure,
                    entityID: try BRepRepairAudit().describe(id, using: &execution),
                    message: try BRepRepairAudit().composed(prefix: "Original signed-shell volume could not certify component orientation: ",
                        value: finding.message, suffix: ".", using: &execution)),
                    messageIsAdmitted: true, to: &diagnostics, using: &execution)
                continue
            }
            if signed.lower > 0 { continue }
            guard signed.upper < 0 else {
                try appendDiagnostic(.init(action: .orientSolidComponents, code: .topologyFailure,
                    entityID: try BRepRepairAudit().describe(id, using: &execution),
                    message: "Original signed-shell volume straddles zero; component orientation is unresolved."),
                    to: &diagnostics, using: &execution)
                continue
            }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                guard var face = model.faces[faceID] else { continue }
                try reverseLoops(of: face, in: &model, tolerance: tolerance, using: &execution)
                face.orientation = face.orientation == .forward ? .reversed : .forward
                try OriginalParameterQueryStorage.set(face, for: faceID, in: &model.faces, using: &execution)
            }
            try appendChange(.init(action: .orientSolidComponents, scope: .volume,
                affectedEntityIDs: try descriptions(shell.faceIDs, using: &execution),
                message: "Oriented an original volume-certified shell boundary outward before applying its explicit material/void role."),
                to: &changes, using: &execution)
        }
        try execution.checkpoint()
    }

    private func classifiedKind(of edge: Edge, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BRepEdgeGeometryKind {
        // Preserve the classifier ordinary entry's scalar limits without changing its nil local algebra policy.
        try execution.withProofScope(maximum: ExactScalarDepth(value: 32, coefficient: 32)) { execution in
            try BRepEdgeGeometryClassifier().kind(of: edge, in: model, tolerance: tolerance, using: &execution)
        }
    }

    private func reverseLoops(of face: Face, in model: inout BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard var loop = model.loops[loopID] else { continue }
            loop.coedges = try OriginalParameterQueryStorage.map(loop.coedges.reversed(), using: &execution) { use, execution in
                Coedge(edgeID: use.edgeID, orientation: use.orientation == .forward ? .reversed : .forward,
                    surfaceParameterCurve: try use.surfaceParameterCurve?.reversed(tolerance: tolerance, using: &execution))
            }
            try OriginalParameterQueryStorage.set(loop, for: loopID, in: &model.loops, using: &execution)
        }
    }

    private func admitCoedgeMutation(_ loop: Loop, needsCopy: inout Bool,
        using execution: inout OriginalQueryExecution) throws {
        guard needsCopy else { return }
        try execution.retainStorage(count: loop.coedges.count, stride: MemoryLayout<Coedge>.stride)
        needsCopy = false
    }

    private func sameUse(_ first: Coedge, _ second: Coedge,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        if let curve = first.surfaceParameterCurve { try GeometryStructuralComparisonWork.charge(parameterCurve: curve, using: &execution) }
        if let curve = second.surfaceParameterCurve { try GeometryStructuralComparisonWork.charge(parameterCurve: curve, using: &execution) }
        return first == second
    }

    private func sameUses(_ first: [Coedge], _ second: [Coedge],
        using execution: inout OriginalQueryExecution) throws -> Bool {
        guard first.count == second.count else { return false }
        for (a, b) in zip(first, second) { if try !sameUse(a, b, using: &execution) { return false } }
        return true
    }

    private func sameParameterCurves(_ first: [SurfaceParameterCurve], _ second: [SurfaceParameterCurve],
        using execution: inout OriginalQueryExecution) throws -> Bool {
        guard first.count == second.count else { return false }
        for (a, b) in zip(first, second) {
            try GeometryStructuralComparisonWork.charge(parameterCurve: a, using: &execution)
            try GeometryStructuralComparisonWork.charge(parameterCurve: b, using: &execution)
            if a != b { return false }
        }
        return true
    }

    private func descriptions<Tag, IDs: Sequence>(_ ids: IDs,
        using execution: inout OriginalQueryExecution) throws -> [String] where IDs.Element == TaggedID<Tag> {
        try OriginalParameterQueryStorage.map(ids, using: &execution) { id, execution in
            try BRepRepairAudit().describe(id, using: &execution)
        }
    }

    private func identifiers<Tag>(_ id: TaggedID<Tag>, using execution: inout OriginalQueryExecution) throws -> [String] {
        try descriptions(CollectionOfOne(id), using: &execution)
    }

    private func identifiers<FirstTag, SecondTag>(_ first: TaggedID<FirstTag>, _ second: TaggedID<SecondTag>,
        using execution: inout OriginalQueryExecution) throws -> [String] {
        var result: [String] = []
        try OriginalParameterQueryStorage.append(try BRepRepairAudit().describe(first, using: &execution), to: &result, using: &execution)
        try OriginalParameterQueryStorage.append(try BRepRepairAudit().describe(second, using: &execution), to: &result, using: &execution)
        return result
    }

    private func remove<Key: Hashable, Value>(_ key: Key, from values: inout PersistentMap<Key, Value>,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: MemoryLayout<(Key, Value)>.stride)
        values[key] = nil
    }

    private func appendChange(_ change: BRepRepairChange, to changes: inout [BRepRepairChange],
        using execution: inout OriginalQueryExecution) throws {
        let message = try BRepRepairAudit().text(change.message, using: &execution)
        try OriginalParameterQueryStorage.append(.init(action: change.action, scope: change.scope,
            affectedEntityIDs: change.affectedEntityIDs, message: message,
            maximumDisplacement: change.maximumDisplacement, toleranceIncrease: change.toleranceIncrease,
            generatedEntityIDs: change.generatedEntityIDs, deletedEntityIDs: change.deletedEntityIDs),
            to: &changes, using: &execution)
    }

    private func appendDiagnostic(_ diagnostic: BRepRepairDiagnostic, messageIsAdmitted: Bool = false,
        to diagnostics: inout [BRepRepairDiagnostic],
        using execution: inout OriginalQueryExecution) throws {
        let message = messageIsAdmitted ? diagnostic.message : try BRepRepairAudit().text(diagnostic.message, using: &execution)
        try OriginalParameterQueryStorage.append(.init(action: diagnostic.action, code: diagnostic.code,
            entityID: diagnostic.entityID, message: message), to: &diagnostics, using: &execution)
    }
}
