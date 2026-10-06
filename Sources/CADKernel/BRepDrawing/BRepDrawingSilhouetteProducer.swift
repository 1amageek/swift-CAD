import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BRepDrawingSilhouetteProducer: BRepDrawingSilhouetteProducing {
    private struct Cell {
        let range: ScalarInterval
        let depth: Int
    }

    private let producer: any SurfaceSilhouetteProducing
    private let containment: any FacePointContainmentTesting
    private let trimPartitions: any SurfaceSilhouetteTrimPartitionProviding

    public init(producer: any SurfaceSilhouetteProducing = DefaultSurfaceSilhouetteProducer(),
                containment: any FacePointContainmentTesting = DefaultFacePointContainmentTester(),
                trimPartitions: any SurfaceSilhouetteTrimPartitionProviding = OriginalSurfaceSilhouetteTrimPartitionProducer()) {
        self.producer = producer
        self.containment = containment
        self.trimPartitions = trimPartitions
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The public drawing path composes original
    // silhouette enclosures and trimmed-face membership. Complete critical roots,
    // tangent/coincident boundary events and all source charts must be certified
    // before full D1 admission; unresolved domains fail without a partial result.
    public func silhouettes(in evaluated: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
                            maximumSourceFaces: Int, maximumProjectedSpans: Int,
                            maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
                            usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes {
        return try extract(evaluated.brep, in: evaluated, placement: nil, onto: frame,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            usage: &usage)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This actual placed drawing path preserves
    // original word geometry and shared caller admission. Whole lower BRep/trim
    // equality and foreground-depth visibility still precede complete D1 publication.
    public func silhouettes(_ placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
        onto frame: OrthographicProjectionFrame, maximumSourceEntities: Int,
        maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes {
        guard case .some = evaluated.validatedSourceReceipt else {
            throw failure(.unsupportedCapability, "Placed silhouette requires an original producer-bound source.", evaluated.configuration.tolerance)
        }
        let tolerance = evaluated.configuration.tolerance
        let closure = try BRepDrawingBodyClosure().make(placement.bodyID, in: evaluated.brep,
            maximumEntities: maximumSourceEntities, tolerance: tolerance, usage: &usage)
        let word: OriginalAffineOperationWord
        if let original = placement.operationWord {
            try original.validateOriginal(tolerance: tolerance, maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
            word = original
        } else {
            try usage.preparationStorageCallback(MemoryLayout<OriginalAffineOperation>.stride)
            word = try OriginalAffineOperationWord(factors: [.forward(placement.transform)], usage: &usage)
        }
        let image = try DefaultShapeOperator().transformed(validatedModel: closure, by: word,
            maximumSubdivisionDepth: min(32, usage.maximumDepth), remainingSourceDepth: usage.maximumSourceDepth,
            consumeWork: usage.preparationProofWorkCallback, consumeStorage: usage.preparationStorageCallback)
        return try extract(image, in: evaluated, placement: placement, onto: frame,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            usage: &usage)
    }

    private func extract(_ model: BRepModel, in evaluated: EvaluatedDocument,
        placement: BRepDrawingPlacement?, onto frame: OrthographicProjectionFrame,
        maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes {
        let tolerance = evaluated.configuration.tolerance
        guard maximumSourceFaces > 0, maximumProjectedSpans > 0,
              maximumControlPointCount > 0, maximumBoundaryCurveCount > 0,
              model.faces.count <= maximumSourceFaces else {
            throw failure(.resourceLimitExceeded, "Silhouette source allowances are invalid or exhausted.", tolerance)
        }
        // Preserve the finite-face backend's existing intrinsic 48-level ceiling.
        // A stricter supplied geometric depth remains authoritative.
        let preparationSubdivisionDepth = min(48, usage.maximumDepth)
        let preparationWork = usage.preparationWorkCallback
        let preparationProofWork = usage.preparationProofWorkCallback
        let preparationStorage = usage.preparationStorageCallback
        try usage.consumeWork()
        guard case .some = evaluated.validatedSourceReceipt else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public/manual and Native-decoded
            // artifacts have no immutable producer source binding. Their complete
            // bounded semantic validator must precede all-domain D1 admission;
            // no legacy traversal or uncharged equality can fabricate that binding.
            throw failure(.unsupportedCapability,
                "Original silhouette preparation requires a producer-bound validated source.", tolerance)
        }
        _ = try ValidatedBRepModel(model, tolerance: tolerance,
            maximumSubdivisionDepth: preparationSubdivisionDepth, remainingSourceDepth: usage.maximumSourceDepth,
            consumeWork: preparationWork, consumeStorage: preparationStorage,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
        let faceIDs = try orderedSourceIDs(model.faces.keys, usage: &usage)
        let preparedMembership = try containment.preparedContainmentSession(for: faceIDs,
            in: model, tolerance: tolerance, maximumSubdivisionDepth: preparationSubdivisionDepth,
            remainingSourceDepth: usage.maximumSourceDepth, maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
            consumeWork: preparationProofWork, consumeStorage: preparationStorage)
        try retainRecord(ParameterMembership.self, usage: &usage)
        let membership = ParameterMembership(source: preparedMembership, tolerance: tolerance)
        try retainRecord(BRepDrawingSourceSnapshot.self, usage: &usage)
        let sourceSnapshot = BRepDrawingSourceSnapshot(evaluated)
        var contacts: [BRepDrawingSilhouetteContact] = []
        var algebraicContacts: [BRepDrawingSilhouetteAlgebraicContact] = []
        var atlasStations: [BRepDrawingSilhouetteAtlasStation] = []
        var collapsedCurves: [BRepDrawingSilhouetteCollapsedCurve] = []
        var singularStations: [BRepDrawingSilhouetteSingularStation] = []
        var originalFaces: [BRepDrawingFaceSilhouette] = []
        var output: [BRepDrawingSilhouetteSpan] = []
        var exactTrimmedSpans: [BRepDrawingExactSilhouetteSpan] = []
        var retainedPartitions: [BRepDrawingSilhouetteTrimPartition] = []
        var coincident: [FaceID] = []
        var visited = Set<FaceID>()
        for bodyID in try orderedSourceIDs(model.bodies.keys, usage: &usage) {
            try usage.consumeWork()
            guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("Silhouette body is absent.") }
            for shellID in body.shellIDs {
                try usage.consumeWork()
                guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Silhouette shell is absent.") }
                for faceID in shell.faceIDs {
                    try usage.consumeWork()
                    try retainRecord(FaceID.self, usage: &usage)
                    guard visited.insert(faceID).inserted, let face = model.faces[faceID],
                          let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw failure(.missingReference, "Silhouette face ownership is absent or ambiguous.", tolerance)
                    }
                    let domain = try DefaultFaceParameterBoundsResolver(
                        maximumSubdivisionDepth: preparationSubdivisionDepth, consumeWork: preparationProofWork,
                        consumeStorage: preparationStorage, remainingSourceDepth: usage.maximumSourceDepth,
                        maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
                        .bounds(for: faceID, in: model, tolerance: tolerance)
                    let envelope = try producer.silhouette(of: surface, over: domain,
                        view: frame.normal, tolerance: tolerance, usage: &usage)
                    try retainRecord(BRepDrawingFaceSilhouette.self, usage: &usage)
                    originalFaces.append(BRepDrawingFaceSilhouette(bodyID: bodyID, faceID: faceID, original: envelope))
                    for contact in envelope.contacts {
                        try usage.consumeWork()
                        guard try membership.contains(contact.parameters, on: faceID) else { continue }
                        guard contacts.count < maximumProjectedSpans - exactTrimmedSpans.count - atlasStations.count - output.count - algebraicContacts.count - singularStations.count - collapsedCurves.count else {
                            throw failure(.resourceLimitExceeded, "Silhouette contact allowance exhausted.", tolerance)
                        }
                        func interval(_ range: ScalarInterval) -> OutwardScalarInterval {
                            OutwardScalarInterval(lower: range.lower, upper: range.upper)
                        }
                        let point = contact.spatialEnclosure
                        let x = interval(point.x) - .exact(frame.origin.x)
                        let y = interval(point.y) - .exact(frame.origin.y)
                        let z = interval(point.z) - .exact(frame.origin.z)
                        func project(_ axis: Vector3D) throws -> ScalarInterval {
                            let value = x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
                            guard value.isFinite else {
                                throw failure(.intersectionFailure, "Silhouette contact projection is nonfinite.", tolerance)
                            }
                            return try ScalarInterval(lower: value.lower, upper: value.upper)
                        }
                        try retainRecord(BRepDrawingSilhouetteContact.self, usage: &usage)
                        contacts.append(BRepDrawingSilhouetteContact(bodyID: bodyID, faceID: faceID,
                            source: contact, projectedEnclosure: try CoordinateEnclosure2D(
                                x: project(frame.horizontal), y: project(frame.vertical))))
                    }
                    if !envelope.coincidentDomains.isEmpty {
                        try retainRecord(FaceID.self, usage: &usage)
                        coincident.append(faceID)
                    }
                    var uses: [EdgeID: [Coedge]] = [:]
                    for loopID in face.loops {
                        try usage.consumeWork()
                        guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Silhouette loop is absent.") }
                        for use in loop.coedges {
                            try usage.consumeWork()
                            if uses[use.edgeID] == nil {
                                try retainRecord((EdgeID, [Coedge]).self, usage: &usage)
                            }
                            try retainRecord(Coedge.self, usage: &usage)
                            uses[use.edgeID, default: []].append(use)
                        }
                    }
                    var boundaries: [OriginalSurfaceSilhouetteBoundary] = []
                    for edgeID in try orderedSourceIDs(uses.keys, usage: &usage) {
                        let edgeUses = uses[edgeID] ?? []
                        if edgeUses.count == 2, edgeUses[0].orientation != edgeUses[1].orientation,
                           let first = edgeUses[0].surfaceParameterCurve,
                           let second = edgeUses[1].surfaceParameterCurve,
                           try PeriodicFaceSeamValidator().certifiesOppositeSeamCurves(first, second,
                               on: surface, tolerance: tolerance,
                               maximumSubdivisionDepth: preparationSubdivisionDepth, remainingSourceDepth: usage.maximumSourceDepth,
                               consumeWork: preparationProofWork, consumeStorage: preparationStorage,
                               maximumAlgebraicDepth: usage.maximumAlgebraicDepth) { continue }
                        for use in edgeUses {
                            guard boundaries.count < maximumBoundaryCurveCount,
                                  let pcurve = use.surfaceParameterCurve else {
                                throw failure(.missingReference, "Silhouette trim lacks an admitted original pcurve.", tolerance)
                            }
                            try retainRecord(OriginalSurfaceSilhouetteBoundary.self, usage: &usage)
                            boundaries.append(try OriginalSurfaceSilhouetteBoundary(curve: pcurve, on: surface,
                                maximumControlPointCount: maximumControlPointCount,
                                maximumBoundaryCurveCount: maximumBoundaryCurveCount,
                                tolerance: tolerance, usage: &usage))
                        }
                    }
                    for station in envelope.singularStations {
                        try usage.consumeWork()
                        guard envelope.curves.indices.contains(station.curveIndex) else {
                            throw failure(.topologyFailure, "Original singular silhouette station has no source curve.", tolerance)
                        }
                        let box = station.originalParameterEnclosure
                        var separated = true
                        for boundary in boundaries {
                            if try !excludes(boundary, box: box, usage: &usage) {
                                separated = false; break
                            }
                        }
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Exact rational cusp/trim incidence
                        // requires original boundary equality authority. The public drawing path
                        // refuses an inseparable box instead of rounding its source center.
                        guard separated else {
                            throw failure(.intersectionFailure, "Original rational silhouette station trim incidence is unresolved.", tolerance)
                        }
                        // Membership at this station classifies the complete boundary-free box;
                        // the original exact rational station and spatial enclosure are retained.
                        let classifierStation = SurfaceParameter(u: box.u.lower + box.u.width * 0.5,
                            v: box.v.lower + box.v.width * 0.5)
                        guard try membership.contains(classifierStation, on: faceID) else { continue }
                        guard singularStations.count < maximumProjectedSpans - exactTrimmedSpans.count - atlasStations.count - output.count - contacts.count - algebraicContacts.count - collapsedCurves.count else {
                            throw failure(.resourceLimitExceeded, "Silhouette singular station allowance exhausted.", tolerance)
                        }
                        try retainRecord(BRepDrawingSilhouetteSingularStation.self, usage: &usage)
                        singularStations.append(BRepDrawingSilhouetteSingularStation(bodyID: bodyID, faceID: faceID,
                            source: station, projectedEnclosure: try projectedContact(station.spatialEnclosure,
                                frame: frame, tolerance: tolerance)))
                    }
                    func admittedContact(_ original: SurfaceSilhouetteAlgebraicContact) throws -> SurfaceSilhouetteAlgebraicContact? {
                        var contact = original
                        for depth in 0...usage.maximumDepth {
                            try usage.consumeCell(depth: depth)
                            var separated = true
                            for boundary in boundaries {
                                if try !excludes(boundary, box: contact.parameterEnclosure, usage: &usage) {
                                    separated = false; break
                                }
                            }
                            if separated {
                                let box = contact.parameterEnclosure
                                // One station classifies the whole boundary-free box. It is
                                // never substituted for the original algebraic position.
                                let station = SurfaceParameter(u: box.u.lower + box.u.width * 0.5,
                                    v: box.v.lower + box.v.width * 0.5)
                                return try membership.contains(station, on: faceID) ? contact : nil
                            }
                            // A zero-width exact coordinate needs no refinement; the other
                            // coordinate can still separate the original contact from trim.
                            let uWidth = max(contact.parameterEnclosure.u.width * 0.5, Double.leastNonzeroMagnitude)
                            let vWidth = max(contact.parameterEnclosure.v.width * 0.5, Double.leastNonzeroMagnitude)
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Original algebraic station/trim
                            // coincidence still needs certified boundary incidence. This public
                            // producer refuses unresolved overlap instead of dropping a station.
                            guard depth < usage.maximumDepth else {
                                throw failure(.intersectionFailure, "Original algebraic silhouette trim contact remains unresolved.", tolerance)
                            }
                            contact = try contact.refined(maximumUWidth: uWidth, maximumVWidth: vWidth, usage: &usage)
                        }
                        throw failure(.intersectionFailure, "Original algebraic contact has no complete trim admission.", tolerance)
                    }
                    for originalContact in envelope.algebraicContacts {
                        try usage.consumeWork()
                        guard let contact = try admittedContact(originalContact) else { continue }
                        guard algebraicContacts.count < maximumProjectedSpans - exactTrimmedSpans.count - atlasStations.count - output.count - contacts.count - singularStations.count - collapsedCurves.count else {
                            throw failure(.resourceLimitExceeded, "Silhouette algebraic contact allowance exhausted.", tolerance)
                        }
                        try retainRecord(BRepDrawingSilhouetteAlgebraicContact.self, usage: &usage)
                        algebraicContacts.append(BRepDrawingSilhouetteAlgebraicContact(bodyID: bodyID,
                            faceID: faceID, source: contact,
                            projectedEnclosure: try projectedContact(contact.spatialEnclosure, frame: frame, tolerance: tolerance)))
                    }
                    for (atlasOrdinal, atlas) in envelope.originalPlaneAtlases.enumerated() {
                        try usage.consumeWork()
                        for curveIndex in atlas.curveIndices {
                            try usage.consumeWork()
                            guard envelope.curves.indices.contains(curveIndex) else {
                                throw failure(.topologyFailure, "Original plane atlas has no owning source curve.", tolerance)
                            }
                        }
                        for (stationOrdinal, station) in atlas.stations.enumerated() {
                            try usage.consumeWork()
                            guard station.incidentCurveIndices.count == station.incidentAtUpperEnd.count,
                                  station.regularGermCount >= 0, station.isolatedGermCount >= 0 else {
                                throw failure(.topologyFailure, "Original atlas station incidence is invalid.", tolerance)
                            }
                            for curveIndex in station.incidentCurveIndices {
                                try usage.consumeWork()
                                try usage.consumeWork(atlas.curveIndices.count)
                                guard envelope.curves.indices.contains(curveIndex), atlas.curveIndices.contains(curveIndex) else {
                                    throw failure(.topologyFailure, "Original atlas station has no incident owning curve.", tolerance)
                                }
                            }
                            guard let contact = try admittedContact(station.originalContact) else { continue }
                            guard atlasStations.count < maximumProjectedSpans - exactTrimmedSpans.count - output.count - contacts.count - algebraicContacts.count - singularStations.count - collapsedCurves.count else {
                                throw failure(.resourceLimitExceeded, "Silhouette atlas station allowance exhausted.", tolerance)
                            }
                            try retainRecord(BRepDrawingSilhouetteAtlasStation.self, usage: &usage)
                            atlasStations.append(BRepDrawingSilhouetteAtlasStation(bodyID: bodyID, faceID: faceID,
                                atlasOrdinal: atlasOrdinal, stationOrdinal: stationOrdinal, source: station,
                                admittedContact: contact, projectedEnclosure: try projectedContact(contact.spatialEnclosure,
                                    frame: frame, tolerance: tolerance)))
                        }
                    }
                    var componentByCurve: [Int: Int] = [:]
                    for (componentID, component) in envelope.components.enumerated() {
                        for curveID in component.curveIndices {
                            guard componentByCurve[curveID] == nil, envelope.curves.indices.contains(curveID) else {
                                throw failure(.topologyFailure, "Original silhouette component ownership is invalid.", tolerance)
                            }
                            try retainRecord((Int, Int).self, usage: &usage)
                            componentByCurve[curveID] = componentID
                        }
                    }
                    for (curveID, curve) in envelope.curves.enumerated() {
                        guard let componentID = componentByCurve[curveID] else {
                            throw failure(.topologyFailure, "Original silhouette curve has no connected component.", tolerance)
                        }
                        let whole = try curve.enclosure(over: curve.nativeDomain, usage: &usage)
                        var wholeSeparated = true
                        for boundary in boundaries {
                            if try !excludes(boundary, box: whole.parameters, usage: &usage) {
                                wholeSeparated = false; break
                            }
                        }
                        if !wholeSeparated {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): This production branch consumes
                            // complete exact graph/cusp/ramified trim partitions. Analytic and
                            // general implicit pcurve equations remain lower mandatory gaps;
                            // failure never falls back to rounded or sampled trim endpoints.
                            var cuts: [SurfaceSilhouetteTrimEndpoint] = []
                            var partitions: [SurfaceSilhouetteTrimPartition] = []
                            for (boundaryID, boundary) in boundaries.enumerated() {
                                let partition = try trimPartitions.partition(curve: curve, boundary: boundary, usage: &usage)
                                try retainRecord(SurfaceSilhouetteTrimPartition.self, usage: &usage)
                                partitions.append(partition)
                                try retainRecord(BRepDrawingSilhouetteTrimPartition.self, usage: &usage)
                                retainedPartitions.append(.init(bodyID: bodyID, faceID: faceID, curveOrdinal: curveID,
                                    boundaryOrdinal: boundaryID, original: partition))
                                for sector in partition.sectors {
                                    for endpointIndex in 0..<2 {
                                        let endpoint = endpointIndex == 0 ? sector.lower : sector.upper
                                        var index = 0
                                        while index < cuts.count, try cuts[index].compare(to: endpoint, usage: &usage) < 0 { index += 1 }
                                        if index < cuts.count, try cuts[index].compare(to: endpoint, usage: &usage) == 0 { continue }
                                        try retainRecord(SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
                                        cuts.insert(endpoint, at: index)
                                    }
                                }
                            }
                            guard cuts.count >= 2 else {
                                throw failure(.intersectionFailure, "Original trim partition has no complete traversal cover.", tolerance)
                            }
                            for index in 1..<cuts.count {
                                var lower = cuts[index - 1], upper = cuts[index]
                                var trimmed = try OriginalSurfaceSilhouetteTrimmedCurve(original: curve,
                                    lower: lower, upper: upper, usage: &usage)
                                var coincidentSector = false
                                for partition in partitions {
                                    for overlap in partition.overlaps {
                                        if try overlap.lower.compare(to: lower, usage: &usage) <= 0,
                                           try upper.compare(to: overlap.upper, usage: &usage) <= 0 { coincidentSector = true; break }
                                    }
                                    if coincidentSector { break }
                                }
                                var admitted = coincidentSector
                                if !coincidentSector {
                                    var width = ExactRationalCoefficient.one
                                    var separated = false
                                    for depth in 0...usage.maximumDepth {
                                        try usage.consumeCell(depth: depth)
                                        let interior = try trimmed.enclosure(overNormalized: .init(lower: 0.5, upper: 0.5),
                                            maximumParameterWidth: width, usage: &usage)
                                        separated = true
                                        for boundary in boundaries {
                                            if try !excludes(boundary, box: interior.parameters, usage: &usage) { separated = false; break }
                                        }
                                        if separated {
                                            let box = interior.parameters
                                            admitted = try membership.contains(SurfaceParameter(u: box.u.lower + box.u.width * 0.5,
                                                v: box.v.lower + box.v.width * 0.5), on: faceID)
                                            break
                                        }
                                        if depth < usage.maximumDepth {
                                            width = try width.divided(by: .originalDouble(2, usage: &usage), usage: &usage)
                                            trimmed = try trimmed.refined(maximumParameterWidth: width, usage: &usage)
                                            lower = trimmed.lower; upper = trimmed.upper
                                            cuts[index - 1] = lower; cuts[index] = upper
                                        }
                                    }
                                    guard separated else { throw failure(.intersectionFailure,
                                        "Exact original trim sector has no separated membership witness.", tolerance) }
                                }
                                if admitted {
                                    guard exactTrimmedSpans.count < maximumProjectedSpans - output.count - atlasStations.count
                                        - contacts.count - algebraicContacts.count - singularStations.count - collapsedCurves.count else {
                                        throw failure(.resourceLimitExceeded, "Exact silhouette trim span allowance exhausted.", tolerance)
                                    }
                                    let whole = try trimmed.enclosure(overNormalized: .init(lower: 0, upper: 1),
                                        maximumParameterWidth: .one, usage: &usage)
                                    guard whole.spatialDerivatives.count >= 2 else {
                                        throw failure(.intersectionFailure, "Exact trimmed silhouette has no original whole spatial jet.", tolerance)
                                    }
                                    let derivative = whole.spatialDerivatives[1]
                                    func zero(_ value: ScalarInterval) -> Bool { value.lower == 0 && value.upper == 0 }
                                    let constant = zero(derivative.x) && zero(derivative.y) && zero(derivative.z)
                                        ? whole.spatialDerivatives[0] : nil
                                    try retainRecord(BRepDrawingExactSilhouetteSpan.self, usage: &usage)
                                    exactTrimmedSpans.append(.init(bodyID: bodyID, faceID: faceID, componentOrdinal: componentID,
                                        curveOrdinal: curveID, curve: trimmed, isCoincidentWithTrim: coincidentSector,
                                        constantSpatialEnclosure: constant, frame: frame))
                                }
                            }
                            continue
                        }
                        try retainRecord(Cell.self, usage: &usage)
                        var pending = [Cell(range: curve.nativeDomain, depth: 0)]
                        while let cell = pending.popLast() {
                            try usage.consumeCell(depth: cell.depth)
                            let enclosure = try curve.enclosure(over: cell.range, usage: &usage)
                            var separated = true
                            for boundary in boundaries {
                                if try !excludes(boundary, box: enclosure.parameters, usage: &usage) {
                                    separated = false; break
                                }
                            }
                            if separated {
                                let uv = enclosure.parameters
                                let point = SurfaceParameter(u: uv.u.lower + uv.u.width * 0.5,
                                    v: uv.v.lower + uv.v.width * 0.5)
                                if try membership.contains(point, on: faceID) {
                                    guard output.count < maximumProjectedSpans - exactTrimmedSpans.count - atlasStations.count - contacts.count - algebraicContacts.count - singularStations.count - collapsedCurves.count else {
                                        throw failure(.resourceLimitExceeded, "Silhouette span allowance exhausted.", tolerance)
                                    }
                                    guard enclosure.spatialDerivatives.count >= 2 else {
                                        throw failure(.intersectionFailure, "Original silhouette spatial derivative proof is absent.", tolerance)
                                    }
                                    let derivative = enclosure.spatialDerivatives[1]
                                    func exactlyZero(_ value: ScalarInterval) -> Bool {
                                        value.lower == 0 && value.upper == 0
                                    }
                                    if exactlyZero(derivative.x) && exactlyZero(derivative.y) && exactlyZero(derivative.z) {
                                        let position = enclosure.spatialDerivatives[0]
                                        try retainRecord(BRepDrawingSilhouetteCollapsedCurve.self, usage: &usage)
                                        collapsedCurves.append(BRepDrawingSilhouetteCollapsedCurve(
                                            bodyID: bodyID, faceID: faceID, componentOrdinal: componentID,
                                            curveOrdinal: curveID, curve: curve, nativeRange: cell.range,
                                            spatialEnclosure: position, projectedEnclosure: try projectedContact(position,
                                                frame: frame, tolerance: tolerance)))
                                    } else {
                                        try retainRecord(BRepDrawingSilhouetteSpan.self, usage: &usage)
                                        output.append(BRepDrawingSilhouetteSpan(bodyID: bodyID, faceID: faceID,
                                            componentOrdinal: componentID, curveOrdinal: curveID,
                                            curve: curve, nativeRange: cell.range, frame: frame))
                                    }
                                }
                                continue
                            }
                            let midpoint = cell.range.lower + cell.range.width * 0.5
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Original boundary roots need
                            // complete discrete/contact event certification. Production clipping
                            // cannot accept an unresolved cell as inside or discard it as outside.
                            guard cell.depth < usage.maximumDepth, midpoint > cell.range.lower,
                                  midpoint < cell.range.upper else {
                                throw failure(.intersectionFailure, "Silhouette trim boundary event remains unresolved.", tolerance)
                            }
                            try retainRecords(2, of: Cell.self, usage: &usage)
                            pending.append(Cell(range: try ScalarInterval(lower: midpoint, upper: cell.range.upper), depth: cell.depth + 1))
                            pending.append(Cell(range: try ScalarInterval(lower: cell.range.lower, upper: midpoint), depth: cell.depth + 1))
                        }
                    }
                }
            }
        }
        guard visited == Set(model.faces.keys) else {
            throw failure(.missingReference, "Silhouette model has an unowned original face.", tolerance)
        }
        try retainRecord(BRepDrawingSilhouettes.self, usage: &usage)
        return BRepDrawingSilhouettes(sourceDocument: evaluated.document,
            configuration: evaluated.configuration, frame: frame, contacts: contacts, algebraicContacts: algebraicContacts,
            atlasStations: atlasStations,
            collapsedCurves: collapsedCurves, singularStations: singularStations, originalFaces: originalFaces,
            sourceSnapshot: sourceSnapshot, spans: output, exactTrimmedSpans: exactTrimmedSpans,
            trimPartitions: retainedPartitions, coincidentFaceIDs: coincident, placement: placement)
    }

    private struct ParameterMembership: Sendable {
        let source: any FacePointContainmentSession
        let tolerance: ModelingTolerance
        func contains(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool {
            guard let value = try source.containsParameter(parameter, on: faceID) else {
                throw KernelError(phase: .classification, code: .unsupportedCapability,
                    tolerance: tolerance, message: "Original silhouette clipping requires prepared UV membership.")
            }
            return value
        }
    }

    private func orderedSourceIDs<C: Collection>(_ source: C,
        usage: inout SurfaceSilhouetteUsage) throws -> [C.Element] where C.Element: Comparable {
        let bytes = source.count.multipliedReportingOverflow(by: MemoryLayout<C.Element>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original silhouette source-key preparation overflowed its storage count.")
        }
        try usage.preparationStorageCallback(bytes.partialValue)
        var result: [C.Element] = []; result.reserveCapacity(source.count)
        for value in source { try usage.consumeWork(); result.append(value) }
        let work = usage.preparationWorkCallback
        try result.sort { first, second in try work(); return first < second }
        return result
    }

    private func retainRecord<T>(_ type: T.Type, usage: inout SurfaceSilhouetteUsage) throws {
        try retainRecords(1, of: type, usage: &usage)
    }

    private func retainRecords<T>(_ count: Int, of type: T.Type,
        usage: inout SurfaceSilhouetteUsage) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Silhouette record storage count overflowed.")
        }
        try usage.preparationStorageCallback(bytes.partialValue)
    }

    private func projectedContact(_ point: CoordinateEnclosure3D, frame: OrthographicProjectionFrame,
                                  tolerance: ModelingTolerance) throws -> CoordinateEnclosure2D {
        func interval(_ value: ScalarInterval) -> OutwardScalarInterval {
            OutwardScalarInterval(lower: value.lower, upper: value.upper)
        }
        let x = interval(point.x) - .exact(frame.origin.x)
        let y = interval(point.y) - .exact(frame.origin.y)
        let z = interval(point.z) - .exact(frame.origin.z)
        func project(_ axis: Vector3D) throws -> ScalarInterval {
            let value = x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
            guard value.isFinite else {
                throw failure(.intersectionFailure, "Original algebraic contact projection is nonfinite.", tolerance)
            }
            return try ScalarInterval(lower: value.lower, upper: value.upper)
        }
        return try CoordinateEnclosure2D(x: project(frame.horizontal), y: project(frame.vertical))
    }

    private func excludes(_ boundary: OriginalSurfaceSilhouetteBoundary, box: SurfaceParameterBox,
                          usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        try retainRecord(Cell.self, usage: &usage)
        var pending = [Cell(range: try ScalarInterval(lower: 0, upper: 1), depth: 0)]
        while let cell = pending.popLast() {
            try usage.consumeCell(depth: cell.depth)
            let range = try boundary.enclosure(overFraction: cell.range, usage: &usage).position
            if range.x.upper < box.u.lower || range.x.lower > box.u.upper
                || range.y.upper < box.v.lower || range.y.lower > box.v.upper { continue }
            // A boundary enclosure inside the curve box cannot be interval-excluded;
            // refine the curve rather than exhausting boundary work at this scale.
            if range.x.lower >= box.u.lower && range.x.upper <= box.u.upper,
               range.y.lower >= box.v.lower && range.y.upper <= box.v.upper { return false }
            let middle = cell.range.lower + cell.range.width * 0.5
            if cell.depth == usage.maximumDepth || middle <= cell.range.lower || middle >= cell.range.upper { return false }
            try retainRecords(2, of: Cell.self, usage: &usage)
            pending.append(Cell(range: try ScalarInterval(lower: middle, upper: cell.range.upper), depth: cell.depth + 1))
            pending.append(Cell(range: try ScalarInterval(lower: cell.range.lower, upper: middle), depth: cell.depth + 1))
        }
        return true
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
