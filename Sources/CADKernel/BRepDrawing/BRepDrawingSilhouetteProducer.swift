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
                            using execution: inout OriginalQueryExecution) throws -> BRepDrawingSilhouettes {
        return try extract(evaluated.brep, in: evaluated, placement: nil, onto: frame,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This actual placed drawing path preserves
    // original word geometry and shared caller admission. Whole lower BRep/trim
    // equality and foreground-depth visibility still precede complete D1 publication.
    public func silhouettes(_ placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
        onto frame: OrthographicProjectionFrame, maximumSourceEntities: Int,
        maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingSilhouettes {
        guard case .some = evaluated.validatedSourceReceipt else {
            throw failure(.unsupportedCapability, "Placed silhouette requires an original producer-bound source.", evaluated.configuration.tolerance)
        }
        let tolerance = evaluated.configuration.tolerance
        let closure = try BRepDrawingBodyClosure().make(placement.bodyID, in: evaluated.brep,
            maximumEntities: maximumSourceEntities, tolerance: tolerance, using: &execution)
        let word: OriginalAffineOperationWord
        if let original = placement.operationWord {
            try original.validateOriginal(tolerance: tolerance, maximumDepth: execution.effectiveLimits.maximumValueDepth, usage: &execution)
            word = original
        } else {
            try execution.retainStorage(bytes: MemoryLayout<OriginalAffineOperation>.stride)
            word = try OriginalAffineOperationWord(factors: [.forward(placement.transform)], usage: &execution)
        }
        let image = try DefaultShapeOperator().transformed(validatedModel: closure, by: word,
            maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth), remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            using: &execution)
        return try extract(image, in: evaluated, placement: placement, onto: frame,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            using: &execution)
    }

    @inline(never)
    private func extract(_ model: BRepModel, in evaluated: EvaluatedDocument,
        placement: BRepDrawingPlacement?, onto frame: OrthographicProjectionFrame,
        maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingSilhouettes {
        let tolerance = evaluated.configuration.tolerance
        let preparationSubdivisionDepth = try validateExtractionSource(model, in: evaluated,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            tolerance: tolerance, using: &execution)
        return try extractValidatedSource(model, in: evaluated, placement: placement, onto: frame,
            maximumSourceFaces: maximumSourceFaces, maximumProjectedSpans: maximumProjectedSpans,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            tolerance: tolerance, preparationSubdivisionDepth: preparationSubdivisionDepth, using: &execution)
    }

    @inline(never)
    private func validateExtractionSource(_ model: BRepModel, in evaluated: EvaluatedDocument,
        maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Int {

        guard maximumSourceFaces > 0, maximumProjectedSpans > 0,
              maximumControlPointCount > 0, maximumBoundaryCurveCount > 0,
              model.faces.count <= maximumSourceFaces else {
            throw failure(.resourceLimitExceeded, "Silhouette source allowances are invalid or exhausted.", tolerance)
        }
        // Preserve the finite-face backend's existing intrinsic 48-level ceiling.
        // A stricter supplied geometric depth remains authoritative.
        let preparationSubdivisionDepth = min(48, execution.effectiveLimits.maximumSubdivisionDepth)
        try execution.consumeWork(1)
        guard case .some = evaluated.validatedSourceReceipt else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public/manual and Native-decoded
            // artifacts have no immutable producer source binding. Their complete
            // bounded semantic validator must precede all-domain D1 admission;
            // no legacy traversal or uncharged equality can fabricate that binding.
            throw failure(.unsupportedCapability,
                "Original silhouette preparation requires a producer-bound validated source.", tolerance)
        }
        _ = try ValidatedBRepModel(model, tolerance: tolerance,
            maximumSubdivisionDepth: preparationSubdivisionDepth, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
        return preparationSubdivisionDepth
    }

    @inline(never)
    private func extractValidatedSource(_ model: BRepModel, in evaluated: EvaluatedDocument,
        placement: BRepDrawingPlacement?, onto frame: OrthographicProjectionFrame,
        maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        tolerance: ModelingTolerance, preparationSubdivisionDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingSilhouettes {
        let faceIDs = try orderedSourceIDs(model.faces.keys, using: &execution)
        let preparedMembership = try containment.preparedContainmentSession(for: faceIDs,
            in: model, tolerance: tolerance, using: &execution)
        try retainRecord(ParameterMembership.self, using: &execution)
        let membership = ParameterMembership(source: preparedMembership, tolerance: tolerance)
        try retainRecord(BRepDrawingSourceSnapshot.self, using: &execution)
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
        for bodyID in try orderedSourceIDs(model.bodies.keys, using: &execution) {
            try execution.consumeWork(1)
            guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("Silhouette body is absent.") }
            for shellID in body.shellIDs {
                try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Silhouette shell is absent.") }
                for faceID in shell.faceIDs {
                    try execution.consumeWork(1)
                    guard try OriginalParameterQueryStorage.insert(faceID, in: &visited, using: &execution), let face = model.faces[faceID],
                          let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw failure(.missingReference, "Silhouette face ownership is absent or ambiguous.", tolerance)
                    }
                    let domain = try DefaultFaceParameterBoundsResolver(
                        maximumSubdivisionDepth: preparationSubdivisionDepth, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                        maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth)
                        .bounds(for: faceID, in: model, tolerance: tolerance, using: &execution)
                    let envelope = try producer.silhouette(of: surface, over: domain,
                        view: frame.normal, tolerance: tolerance, using: &execution)
                    try appendFaceEnvelope(envelope: envelope, bodyID: bodyID, faceID: faceID,
                        face: face, surface: surface, model: model, membership: membership, frame: frame,
                        maximumProjectedSpans: maximumProjectedSpans, maximumControlPointCount: maximumControlPointCount,
                        maximumBoundaryCurveCount: maximumBoundaryCurveCount, tolerance: tolerance,
                        preparationSubdivisionDepth: preparationSubdivisionDepth, originalFaces: &originalFaces,
                        contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations,
                        collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output,
                        exactTrimmedSpans: &exactTrimmedSpans, retainedPartitions: &retainedPartitions,
                        coincident: &coincident, using: &execution)
                }
            }
        }
        guard visited == (try OriginalParameterQueryStorage.set(model.faces.keys, using: &execution)) else {
            throw failure(.missingReference, "Silhouette model has an unowned original face.", tolerance)
        }
        try retainRecord(BRepDrawingSilhouettes.self, using: &execution)
        return BRepDrawingSilhouettes(sourceDocument: evaluated.document,
            configuration: evaluated.configuration, frame: frame, contacts: contacts, algebraicContacts: algebraicContacts,
            atlasStations: atlasStations,
            collapsedCurves: collapsedCurves, singularStations: singularStations, originalFaces: originalFaces,
            sourceSnapshot: sourceSnapshot, spans: output, exactTrimmedSpans: exactTrimmedSpans,
            trimPartitions: retainedPartitions, coincidentFaceIDs: coincident, placement: placement)
        }



    @inline(never)
    private func appendFaceEnvelope(envelope: SurfaceSilhouetteEnvelope, bodyID: BodyID, faceID: FaceID,
        face: Face, surface: Surface3D, model: BRepModel, membership: ParameterMembership,
        frame: OrthographicProjectionFrame, maximumProjectedSpans: Int, maximumControlPointCount: Int,
        maximumBoundaryCurveCount: Int, tolerance: ModelingTolerance, preparationSubdivisionDepth: Int,
        originalFaces: inout [BRepDrawingFaceSilhouette], contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan], exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        retainedPartitions: inout [BRepDrawingSilhouetteTrimPartition], coincident: inout [FaceID],
        using execution: inout OriginalQueryExecution) throws {
        try OriginalParameterQueryStorage.append(BRepDrawingFaceSilhouette(bodyID: bodyID, faceID: faceID, original: envelope), to: &originalFaces, using: &execution)
        if !envelope.contacts.isEmpty {
            try appendContacts(envelope: envelope, bodyID: bodyID, faceID: faceID,
                membership: membership, frame: frame, maximumProjectedSpans: maximumProjectedSpans,
                tolerance: tolerance, contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
        }
        if !envelope.coincidentDomains.isEmpty {
            try OriginalParameterQueryStorage.append(faceID, to: &coincident, using: &execution)
        }
        var boundaries: [OriginalSurfaceSilhouetteBoundary] = []
        try appendFaceBoundaries(face: face, surface: surface, model: model,
            maximumControlPointCount: maximumControlPointCount, maximumBoundaryCurveCount: maximumBoundaryCurveCount,
            tolerance: tolerance, preparationSubdivisionDepth: preparationSubdivisionDepth,
            boundaries: &boundaries, using: &execution)
        if !envelope.singularStations.isEmpty {
            try appendSingularStations(envelope: envelope, bodyID: bodyID, faceID: faceID,
                membership: membership, frame: frame, maximumProjectedSpans: maximumProjectedSpans,
                tolerance: tolerance, boundaries: boundaries, contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
        }
        if !envelope.algebraicContacts.isEmpty {
            try appendAlgebraicContacts(envelope: envelope, bodyID: bodyID, faceID: faceID,
                membership: membership, frame: frame, maximumProjectedSpans: maximumProjectedSpans,
                tolerance: tolerance, boundaries: boundaries, contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
        }
        if !envelope.originalPlaneAtlases.isEmpty {
            try appendAtlasStations(envelope: envelope, bodyID: bodyID, faceID: faceID,
                membership: membership, frame: frame, maximumProjectedSpans: maximumProjectedSpans,
                tolerance: tolerance, boundaries: boundaries, contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
        }
        var componentByCurve: [Int: Int] = [:]
        try bindFaceComponents(envelope: envelope, tolerance: tolerance,
            componentByCurve: &componentByCurve, using: &execution)
        try appendFaceCurves(envelope: envelope, bodyID: bodyID, faceID: faceID,
            boundaries: boundaries, componentByCurve: componentByCurve, membership: membership, frame: frame,
            maximumProjectedSpans: maximumProjectedSpans, tolerance: tolerance,
            retainedPartitions: &retainedPartitions, contacts: &contacts, algebraicContacts: &algebraicContacts,
            atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations,
            output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
    }

    @inline(never)
    private func appendFaceBoundaries(face: Face, surface: Surface3D, model: BRepModel,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int, tolerance: ModelingTolerance,
        preparationSubdivisionDepth: Int, boundaries: inout [OriginalSurfaceSilhouetteBoundary],
        using execution: inout OriginalQueryExecution) throws {
        var uses: [EdgeID: [Coedge]] = [:]
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Silhouette loop is absent.") }
            for use in loop.coedges {
                try execution.consumeWork(1)
                try BRepDrawingGroupedStorage.append(use, for: use.edgeID, in: &uses, using: &execution)
            }
        }
        for edgeID in try orderedSourceIDs(uses.keys, using: &execution) {
            let edgeUses = uses[edgeID] ?? []
            if edgeUses.count == 2, edgeUses[0].orientation != edgeUses[1].orientation,
               let first = edgeUses[0].surfaceParameterCurve,
               let second = edgeUses[1].surfaceParameterCurve,
               try PeriodicFaceSeamValidator().certifiesOppositeSeamCurves(first, second,
                   on: surface, tolerance: tolerance,
                   maximumSubdivisionDepth: preparationSubdivisionDepth, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                   maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution) { continue }
            for use in edgeUses {
                try execution.consumeWork(1)
                guard boundaries.count < maximumBoundaryCurveCount,
                      let pcurve = use.surfaceParameterCurve else {
                    throw failure(.missingReference, "Silhouette trim lacks an admitted original pcurve.", tolerance)
                }
                try OriginalParameterQueryStorage.append(try OriginalSurfaceSilhouetteBoundary(curve: pcurve, on: surface,
                    maximumControlPointCount: maximumControlPointCount,
                    maximumBoundaryCurveCount: maximumBoundaryCurveCount,
                    tolerance: tolerance, using: &execution), to: &boundaries, using: &execution)
            }
        }
    }

    @inline(never)
    private func bindFaceComponents(envelope: borrowing SurfaceSilhouetteEnvelope, tolerance: ModelingTolerance,
        componentByCurve: inout [Int: Int], using execution: inout OriginalQueryExecution) throws {
        for (componentID, component) in envelope.components.enumerated() {
                try execution.consumeWork(1)
            for curveID in component.curveIndices {
                try execution.consumeWork(1)
                guard componentByCurve[curveID] == nil, envelope.curves.indices.contains(curveID) else {
                    throw failure(.topologyFailure, "Original silhouette component ownership is invalid.", tolerance)
                }
                try OriginalParameterQueryStorage.set(componentID, for: curveID, in: &componentByCurve, using: &execution)
            }
        }
    }

    @inline(never)
    private func appendFaceCurves(envelope: borrowing SurfaceSilhouetteEnvelope, bodyID: BodyID, faceID: FaceID,
        boundaries: [OriginalSurfaceSilhouetteBoundary], componentByCurve: [Int: Int],
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        retainedPartitions: inout [BRepDrawingSilhouetteTrimPartition], contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan], exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution) throws {
        for curveID in envelope.curves.indices {
            try execution.consumeWork(1)
            guard let componentID = componentByCurve[curveID] else {
                throw failure(.topologyFailure, "Original silhouette curve has no connected component.", tolerance)
            }
            try appendCurve(curve: envelope.curves[curveID], curveID: curveID, componentID: componentID,
                bodyID: bodyID, faceID: faceID, boundaries: boundaries, membership: membership,
                frame: frame, maximumProjectedSpans: maximumProjectedSpans, tolerance: tolerance,
                retainedPartitions: &retainedPartitions,
                contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
        }
    }

    @inline(never)
    private func admittedContact(_ original: SurfaceSilhouetteAlgebraicContact,
        boundaries: [OriginalSurfaceSilhouetteBoundary], membership: ParameterMembership,
        faceID: FaceID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteAlgebraicContact? {
        var contact = original
        for depth in 0...execution.effectiveLimits.maximumSubdivisionDepth {
            try execution.visitDrawingCell(depth: depth)
            var separated = true
            for boundary in boundaries {
                if try !excludes(boundary, box: contact.parameterEnclosure, using: &execution) {
                    separated = false; break
                }
            }
            if separated {
                let box = contact.parameterEnclosure
                // One station classifies the whole boundary-free box. It is
                // never substituted for the original algebraic position.
                let station = SurfaceParameter(u: box.u.lower + box.u.width * 0.5,
                    v: box.v.lower + box.v.width * 0.5)
                return try membership.contains(station, on: faceID, using: &execution) ? contact : nil
            }
            // A zero-width exact coordinate needs no refinement; the other
            // coordinate can still separate the original contact from trim.
            let uWidth = max(contact.parameterEnclosure.u.width * 0.5, Double.leastNonzeroMagnitude)
            let vWidth = max(contact.parameterEnclosure.v.width * 0.5, Double.leastNonzeroMagnitude)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original algebraic station/trim
            // coincidence still needs certified boundary incidence. This public
            // producer refuses unresolved overlap instead of dropping a station.
            guard depth < execution.effectiveLimits.maximumSubdivisionDepth else {
                throw failure(.intersectionFailure, "Original algebraic silhouette trim contact remains unresolved.", tolerance)
            }
            contact = try contact.refined(maximumUWidth: uWidth, maximumVWidth: vWidth, using: &execution)
        }
        throw failure(.intersectionFailure, "Original algebraic contact has no complete trim admission.", tolerance)
    }

    @inline(never)
    private func appendExactTrimmedCurve(
        curve: borrowing OriginalSurfaceSilhouetteCurve, curveID: Int, componentID: Int,
        bodyID: BodyID, faceID: FaceID, boundaries: [OriginalSurfaceSilhouetteBoundary],
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        retainedPartitions: inout [BRepDrawingSilhouetteTrimPartition],
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This production branch consumes
        // complete exact graph/cusp/ramified trim partitions. Analytic and
        // general implicit pcurve equations remain lower mandatory gaps;
        // failure never falls back to rounded or sampled trim endpoints.
        var cuts: [SurfaceSilhouetteTrimEndpoint] = []
        var partitions: [SurfaceSilhouetteTrimPartition] = []
        try prepareExactPartitions(curve: curve, curveID: curveID, bodyID: bodyID,
            faceID: faceID, boundaries: boundaries, tolerance: tolerance,
            cuts: &cuts, partitions: &partitions, retainedPartitions: &retainedPartitions, using: &execution)
        try appendExactSectors(cuts: &cuts, partitions: partitions, curve: curve,
            curveID: curveID, componentID: componentID, bodyID: bodyID, faceID: faceID,
            boundaries: boundaries, membership: membership, frame: frame,
            maximumProjectedSpans: maximumProjectedSpans, tolerance: tolerance,
            contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations,
            collapsedCurves: &collapsedCurves, singularStations: &singularStations,
            output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
    }

    @inline(never)
    private func appendExactSectors(
        cuts: inout [SurfaceSilhouetteTrimEndpoint], partitions: [SurfaceSilhouetteTrimPartition],
        curve: borrowing OriginalSurfaceSilhouetteCurve, curveID: Int, componentID: Int,
        bodyID: BodyID, faceID: FaceID, boundaries: [OriginalSurfaceSilhouetteBoundary],
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        for index in 1..<cuts.count {
        try execution.consumeWork(1)
            var lower = cuts[index - 1], upper = cuts[index]
            // Retain an owned descriptor from the borrow, sharing the original source buffers.
            var trimmed = try OriginalSurfaceSilhouetteTrimmedCurve(original: copy curve,
                lower: lower, upper: upper, using: &execution)
            let coincidentSector = try exactSectorCoincides(partitions: partitions,
                lower: &lower, upper: &upper, using: &execution)
            let admitted = try admitExactSector(coincidentSector: coincidentSector, trimmed: &trimmed,
                lower: &lower, upper: &upper, cuts: &cuts, index: index, boundaries: boundaries,
                membership: membership, faceID: faceID, tolerance: tolerance, using: &execution)
            if admitted {
                try publishExactSector(trimmed: &trimmed, bodyID: bodyID, faceID: faceID,
                    componentID: componentID, curveID: curveID, coincidentSector: coincidentSector,
                    frame: frame, maximumProjectedSpans: maximumProjectedSpans, tolerance: tolerance,
                    contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
            }
        }
    }

    @inline(never)
    private func prepareExactPartitions(
        curve: borrowing OriginalSurfaceSilhouetteCurve, curveID: Int,
        bodyID: BodyID, faceID: FaceID, boundaries: [OriginalSurfaceSilhouetteBoundary],
        tolerance: ModelingTolerance, cuts: inout [SurfaceSilhouetteTrimEndpoint],
        partitions: inout [SurfaceSilhouetteTrimPartition],
        retainedPartitions: inout [BRepDrawingSilhouetteTrimPartition],
        using execution: inout OriginalQueryExecution
    ) throws {
        for (boundaryID, boundary) in boundaries.enumerated() {
            let partition = try trimPartitions.partition(curve: curve, boundary: boundary, using: &execution)
            try appendPartitionCuts(partition, curveID: curveID, bodyID: bodyID, faceID: faceID,
                boundaryID: boundaryID, cuts: &cuts, partitions: &partitions,
                retainedPartitions: &retainedPartitions, using: &execution)
        }
        guard cuts.count >= 2 else {
            throw failure(.intersectionFailure, "Original trim partition has no complete traversal cover.", tolerance)
        }
    }

    @inline(never)
    private func appendPartitionCuts(_ partition: SurfaceSilhouetteTrimPartition, curveID: Int,
        bodyID: BodyID, faceID: FaceID, boundaryID: Int,
        cuts: inout [SurfaceSilhouetteTrimEndpoint], partitions: inout [SurfaceSilhouetteTrimPartition],
        retainedPartitions: inout [BRepDrawingSilhouetteTrimPartition],
        using execution: inout OriginalQueryExecution) throws {
        try OriginalParameterQueryStorage.append(partition, to: &partitions, using: &execution)
        try OriginalParameterQueryStorage.append(.init(bodyID: bodyID, faceID: faceID, curveOrdinal: curveID,
            boundaryOrdinal: boundaryID, original: partition), to: &retainedPartitions, using: &execution)
        for sector in partition.sectors {
            try execution.consumeWork(1)
            for endpointIndex in 0..<2 {
                try execution.consumeWork(1)
                let endpoint = endpointIndex == 0 ? sector.lower : sector.upper
                var index = 0
                while index < cuts.count, try cuts[index].compare(to: endpoint, using: &execution) < 0 { index += 1 }
                if index < cuts.count, try cuts[index].compare(to: endpoint, using: &execution) == 0 { continue }
                let next = cuts.count.addingReportingOverflow(1)
                guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                try OriginalParameterQueryStorage.reserve(next.partialValue, in: &cuts, using: &execution)
                try execution.consumeWork(cuts.count - index)
                cuts.insert(endpoint, at: index)
            }
        }
    }

    @inline(never)
    private func exactSectorCoincides(
        partitions: [SurfaceSilhouetteTrimPartition],
        lower: inout SurfaceSilhouetteTrimEndpoint, upper: inout SurfaceSilhouetteTrimEndpoint,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
            var coincidentSector = false
            for partition in partitions {
        try execution.consumeWork(1)
                for overlap in partition.overlaps {
        try execution.consumeWork(1)
                    if try overlap.lower.compare(to: lower, using: &execution) <= 0,
                       try upper.compare(to: overlap.upper, using: &execution) <= 0 { coincidentSector = true; break }
                }
                if coincidentSector { break }
            }
            return coincidentSector
    }

    @inline(never)
    private func admitExactSector(
        coincidentSector: Bool, trimmed: inout OriginalSurfaceSilhouetteTrimmedCurve,
        lower: inout SurfaceSilhouetteTrimEndpoint, upper: inout SurfaceSilhouetteTrimEndpoint,
        cuts: inout [SurfaceSilhouetteTrimEndpoint], index: Int,
        boundaries: [OriginalSurfaceSilhouetteBoundary], membership: ParameterMembership,
        faceID: FaceID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        var admitted = coincidentSector
        if !coincidentSector {
            var width = ExactRationalCoefficient.one
            var separated = false
            for depth in 0...execution.effectiveLimits.maximumSubdivisionDepth {
                try execution.visitDrawingCell(depth: depth)
                let box = try exactSectorMembershipBox(trimmed: trimmed, width: width, boundaries: boundaries,
                    separated: &separated, using: &execution)
                if separated {
                    admitted = try membership.contains(SurfaceParameter(u: box.u.lower + box.u.width * 0.5,
                        v: box.v.lower + box.v.width * 0.5), on: faceID, using: &execution)
                    break
                }
                if depth < execution.effectiveLimits.maximumSubdivisionDepth {
                    try refineExactSector(width: &width, trimmed: &trimmed, lower: &lower, upper: &upper,
                        cuts: &cuts, index: index, using: &execution)
                }
            }
            guard separated else { throw failure(.intersectionFailure,
                "Exact original trim sector has no separated membership witness.", tolerance) }
        }
        return admitted
    }

    @inline(never)
    private func exactSectorMembershipBox(trimmed: borrowing OriginalSurfaceSilhouetteTrimmedCurve,
        width: ExactRationalCoefficient, boundaries: [OriginalSurfaceSilhouetteBoundary],
        separated: inout Bool, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        let interior = try trimmed.enclosure(overNormalized: .init(lower: 0.5, upper: 0.5),
            maximumParameterWidth: width, using: &execution)
        separated = true
        for boundary in boundaries {
            if try !excludes(boundary, box: interior.parameters, using: &execution) { separated = false; break }
        }
        return interior.parameters
    }

    @inline(never)
    private func refineExactSector(width: inout ExactRationalCoefficient,
        trimmed: inout OriginalSurfaceSilhouetteTrimmedCurve,
        lower: inout SurfaceSilhouetteTrimEndpoint, upper: inout SurfaceSilhouetteTrimEndpoint,
        cuts: inout [SurfaceSilhouetteTrimEndpoint], index: Int,
        using execution: inout OriginalQueryExecution) throws {
        width = try width.divided(by: .originalDouble(2, usage: &execution), usage: &execution)
        trimmed = try trimmed.refined(maximumParameterWidth: width, using: &execution)
        lower = trimmed.lower; upper = trimmed.upper
        cuts[index - 1] = lower; cuts[index] = upper
    }

    @inline(never)
    private func publishExactSector(
        trimmed: inout OriginalSurfaceSilhouetteTrimmedCurve,
        bodyID: BodyID, faceID: FaceID, componentID: Int, curveID: Int,
        coincidentSector: Bool, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {

        guard exactTrimmedSpans.count < maximumProjectedSpans - output.count - atlasStations.count
            - contacts.count - algebraicContacts.count - singularStations.count - collapsedCurves.count else {
            throw failure(.resourceLimitExceeded, "Exact silhouette trim span allowance exhausted.", tolerance)
        }
        let whole = try trimmed.enclosure(overNormalized: .init(lower: 0, upper: 1),
            maximumParameterWidth: .one, using: &execution)
        guard whole.spatialDerivatives.count >= 2 else {
            throw failure(.intersectionFailure, "Exact trimmed silhouette has no original whole spatial jet.", tolerance)
        }
        let derivative = whole.spatialDerivatives[1]
        func zero(_ value: ScalarInterval) -> Bool { value.lower == 0 && value.upper == 0 }
        let constant = zero(derivative.x) && zero(derivative.y) && zero(derivative.z)
            ? whole.spatialDerivatives[0] : nil
        try OriginalParameterQueryStorage.append(.init(bodyID: bodyID, faceID: faceID, componentOrdinal: componentID,
            curveOrdinal: curveID, curve: trimmed, isCoincidentWithTrim: coincidentSector,
            constantSpatialEnclosure: constant, frame: frame), to: &exactTrimmedSpans, using: &execution)
    }

    @inline(never)
    private func appendRegularCurve(
        curve: borrowing OriginalSurfaceSilhouetteCurve, curveID: Int, componentID: Int,
        bodyID: BodyID, faceID: FaceID, boundaries: [OriginalSurfaceSilhouetteBoundary],
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        try retainRecord(Cell.self, using: &execution)
        var pending = [Cell(range: curve.nativeDomain, depth: 0)]
        while let cell = pending.popLast() {
            try execution.visitDrawingCell(depth: cell.depth)
            let enclosure = try curve.enclosure(over: cell.range, using: &execution)
            var separated = true
            for boundary in boundaries {
                if try !excludes(boundary, box: enclosure.parameters, using: &execution) {
                    separated = false; break
                }
            }
            if separated {
                let uv = enclosure.parameters
                let point = SurfaceParameter(u: uv.u.lower + uv.u.width * 0.5,
                    v: uv.v.lower + uv.v.width * 0.5)
                if try membership.contains(point, on: faceID, using: &execution) {
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
                        // The published span owns its descriptor; the original buffers stay shared.
                        try OriginalParameterQueryStorage.append(BRepDrawingSilhouetteCollapsedCurve(
                            bodyID: bodyID, faceID: faceID, componentOrdinal: componentID,
                            curveOrdinal: curveID, curve: copy curve, nativeRange: cell.range,
                            spatialEnclosure: position, projectedEnclosure: try projectedContact(position,
                                frame: frame, tolerance: tolerance)), to: &collapsedCurves, using: &execution)
                    } else {
                        // The published span owns its descriptor; the original buffers stay shared.
                        try OriginalParameterQueryStorage.append(BRepDrawingSilhouetteSpan(bodyID: bodyID, faceID: faceID,
                            componentOrdinal: componentID, curveOrdinal: curveID,
                            curve: copy curve, nativeRange: cell.range, frame: frame), to: &output, using: &execution)
                    }
                }
                continue
            }
            let midpoint = cell.range.lower + cell.range.width * 0.5
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original boundary roots need
            // complete discrete/contact event certification. Production clipping
            // cannot accept an unresolved cell as inside or discard it as outside.
            guard cell.depth < execution.effectiveLimits.maximumSubdivisionDepth, midpoint > cell.range.lower,
                  midpoint < cell.range.upper else {
                throw failure(.intersectionFailure, "Silhouette trim boundary event remains unresolved.", tolerance)
            }

            try OriginalParameterQueryStorage.append(Cell(range: try ScalarInterval(lower: midpoint, upper: cell.range.upper), depth: cell.depth + 1), to: &pending, using: &execution)
            try OriginalParameterQueryStorage.append(Cell(range: try ScalarInterval(lower: cell.range.lower, upper: midpoint), depth: cell.depth + 1), to: &pending, using: &execution)
        }
    }

    @inline(never)
    private func appendCurve(
        curve: borrowing OriginalSurfaceSilhouetteCurve, curveID: Int, componentID: Int,
        bodyID: BodyID, faceID: FaceID, boundaries: [OriginalSurfaceSilhouetteBoundary],
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        retainedPartitions: inout [BRepDrawingSilhouetteTrimPartition],
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        let whole = try curve.enclosure(over: curve.nativeDomain, using: &execution)
        var wholeSeparated = true
        for boundary in boundaries {
            if try !excludes(boundary, box: whole.parameters, using: &execution) {
                wholeSeparated = false; break
            }
        }
        if !wholeSeparated {
            try appendExactTrimmedCurve(curve: curve, curveID: curveID, componentID: componentID,
                bodyID: bodyID, faceID: faceID, boundaries: boundaries,
                membership: membership, frame: frame, maximumProjectedSpans: maximumProjectedSpans,
                tolerance: tolerance, retainedPartitions: &retainedPartitions,
                contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
            return
        }
        try appendRegularCurve(curve: curve, curveID: curveID, componentID: componentID,
            bodyID: bodyID, faceID: faceID, boundaries: boundaries, membership: membership,
            frame: frame, maximumProjectedSpans: maximumProjectedSpans, tolerance: tolerance,
            contacts: &contacts, algebraicContacts: &algebraicContacts, atlasStations: &atlasStations, collapsedCurves: &collapsedCurves, singularStations: &singularStations, output: &output, exactTrimmedSpans: &exactTrimmedSpans, using: &execution)
    }

    @inline(never)
    private func appendContacts(
        envelope: borrowing SurfaceSilhouetteEnvelope, bodyID: BodyID, faceID: FaceID,
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        for contact in envelope.contacts {
            try execution.consumeWork(1)
            guard try membership.contains(contact.parameters, on: faceID, using: &execution) else { continue }
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
            try OriginalParameterQueryStorage.append(BRepDrawingSilhouetteContact(bodyID: bodyID, faceID: faceID,
                source: contact, projectedEnclosure: try CoordinateEnclosure2D(
                    x: project(frame.horizontal), y: project(frame.vertical))), to: &contacts, using: &execution)
        }
    }

    @inline(never)
    private func appendSingularStations(
        envelope: borrowing SurfaceSilhouetteEnvelope, bodyID: BodyID, faceID: FaceID,
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        boundaries: [OriginalSurfaceSilhouetteBoundary],
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        for station in envelope.singularStations {
            try execution.consumeWork(1)
            guard envelope.curves.indices.contains(station.curveIndex) else {
                throw failure(.topologyFailure, "Original singular silhouette station has no source curve.", tolerance)
            }
            let box = station.originalParameterEnclosure
            var separated = true
            for boundary in boundaries {
                if try !excludes(boundary, box: box, using: &execution) {
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
            guard try membership.contains(classifierStation, on: faceID, using: &execution) else { continue }
            guard singularStations.count < maximumProjectedSpans - exactTrimmedSpans.count - atlasStations.count - output.count - contacts.count - algebraicContacts.count - collapsedCurves.count else {
                throw failure(.resourceLimitExceeded, "Silhouette singular station allowance exhausted.", tolerance)
            }
            try OriginalParameterQueryStorage.append(BRepDrawingSilhouetteSingularStation(bodyID: bodyID, faceID: faceID,
                source: station, projectedEnclosure: try projectedContact(station.spatialEnclosure,
                    frame: frame, tolerance: tolerance)), to: &singularStations, using: &execution)
        }
    }

    @inline(never)
    private func appendAlgebraicContacts(
        envelope: borrowing SurfaceSilhouetteEnvelope, bodyID: BodyID, faceID: FaceID,
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        boundaries: [OriginalSurfaceSilhouetteBoundary],
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        for originalContact in envelope.algebraicContacts {
            try execution.consumeWork(1)
            guard let contact = try admittedContact(originalContact, boundaries: boundaries, membership: membership, faceID: faceID, tolerance: tolerance, using: &execution) else { continue }
            guard algebraicContacts.count < maximumProjectedSpans - exactTrimmedSpans.count - atlasStations.count - output.count - contacts.count - singularStations.count - collapsedCurves.count else {
                throw failure(.resourceLimitExceeded, "Silhouette algebraic contact allowance exhausted.", tolerance)
            }
            try OriginalParameterQueryStorage.append(BRepDrawingSilhouetteAlgebraicContact(bodyID: bodyID,
                faceID: faceID, source: contact,
                projectedEnclosure: try projectedContact(contact.spatialEnclosure, frame: frame, tolerance: tolerance)), to: &algebraicContacts, using: &execution)
        }
    }

    @inline(never)
    private func appendAtlasStations(
        envelope: borrowing SurfaceSilhouetteEnvelope, bodyID: BodyID, faceID: FaceID,
        membership: ParameterMembership, frame: OrthographicProjectionFrame,
        maximumProjectedSpans: Int, tolerance: ModelingTolerance,
        boundaries: [OriginalSurfaceSilhouetteBoundary],
        contacts: inout [BRepDrawingSilhouetteContact],
        algebraicContacts: inout [BRepDrawingSilhouetteAlgebraicContact],
        atlasStations: inout [BRepDrawingSilhouetteAtlasStation],
        collapsedCurves: inout [BRepDrawingSilhouetteCollapsedCurve],
        singularStations: inout [BRepDrawingSilhouetteSingularStation],
        output: inout [BRepDrawingSilhouetteSpan],
        exactTrimmedSpans: inout [BRepDrawingExactSilhouetteSpan],
        using execution: inout OriginalQueryExecution
    ) throws {
        for (atlasOrdinal, atlas) in envelope.originalPlaneAtlases.enumerated() {
            try execution.consumeWork(1)
            for curveIndex in atlas.curveIndices {
                try execution.consumeWork(1)
                guard envelope.curves.indices.contains(curveIndex) else {
                    throw failure(.topologyFailure, "Original plane atlas has no owning source curve.", tolerance)
                }
            }
            for (stationOrdinal, station) in atlas.stations.enumerated() {
                try execution.consumeWork(1)
                guard station.incidentCurveIndices.count == station.incidentAtUpperEnd.count,
                      station.regularGermCount >= 0, station.isolatedGermCount >= 0 else {
                    throw failure(.topologyFailure, "Original atlas station incidence is invalid.", tolerance)
                }
                for curveIndex in station.incidentCurveIndices {
                    try execution.consumeWork(1)
                    try execution.consumeWork(atlas.curveIndices.count)
                    guard envelope.curves.indices.contains(curveIndex), atlas.curveIndices.contains(curveIndex) else {
                        throw failure(.topologyFailure, "Original atlas station has no incident owning curve.", tolerance)
                    }
                }
                guard let contact = try admittedContact(station.originalContact, boundaries: boundaries, membership: membership, faceID: faceID, tolerance: tolerance, using: &execution) else { continue }
                guard atlasStations.count < maximumProjectedSpans - exactTrimmedSpans.count - output.count - contacts.count - algebraicContacts.count - singularStations.count - collapsedCurves.count else {
                    throw failure(.resourceLimitExceeded, "Silhouette atlas station allowance exhausted.", tolerance)
                }
                try OriginalParameterQueryStorage.append(BRepDrawingSilhouetteAtlasStation(bodyID: bodyID, faceID: faceID,
                    atlasOrdinal: atlasOrdinal, stationOrdinal: stationOrdinal, source: station,
                    admittedContact: contact, projectedEnclosure: try projectedContact(contact.spatialEnclosure,
                        frame: frame, tolerance: tolerance)), to: &atlasStations, using: &execution)
            }
        }
    }

    private struct ParameterMembership: Sendable {
        let source: any FacePointContainmentSession
        let tolerance: ModelingTolerance
        func contains(_ parameter: SurfaceParameter, on faceID: FaceID,
            using execution: inout OriginalQueryExecution) throws -> Bool {
            guard let value = try source.containsParameter(parameter, on: faceID, using: &execution) else {
                throw KernelError(phase: .classification, code: .unsupportedCapability,
                    tolerance: tolerance, message: "Original silhouette clipping requires prepared UV membership.")
            }
            return value
        }
    }

    private func orderedSourceIDs<C: Collection>(_ source: C,
        using execution: inout OriginalQueryExecution) throws -> [C.Element] where C.Element: Comparable {
        let bytes = source.count.multipliedReportingOverflow(by: MemoryLayout<C.Element>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original silhouette source-key preparation overflowed its storage count.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
        var result: [C.Element] = []; result.reserveCapacity(source.count)
        for value in source { try execution.consumeWork(1); result.append(value) }
        try OriginalParameterQueryStorage.sort(&result, using: &execution, less: <)
        return result
    }

    private func retainRecord<T>(_ type: T.Type, using execution: inout OriginalQueryExecution) throws {
        try retainRecords(1, of: type, using: &execution)
    }

    private func retainRecords<T>(_ count: Int, of type: T.Type,
        using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Silhouette record storage count overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
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
                          using execution: inout OriginalQueryExecution) throws -> Bool {
        try retainRecord(Cell.self, using: &execution)
        var pending = [Cell(range: try ScalarInterval(lower: 0, upper: 1), depth: 0)]
        while let cell = pending.popLast() {
            try execution.visitDrawingCell(depth: cell.depth)
            let range = try boundary.enclosure(overFraction: cell.range, using: &execution).position
            if range.x.upper < box.u.lower || range.x.lower > box.u.upper
                || range.y.upper < box.v.lower || range.y.lower > box.v.upper { continue }
            // A boundary enclosure inside the curve box cannot be interval-excluded;
            // refine the curve rather than exhausting boundary work at this scale.
            if range.x.lower >= box.u.lower && range.x.upper <= box.u.upper,
               range.y.lower >= box.v.lower && range.y.upper <= box.v.upper { return false }
            let middle = cell.range.lower + cell.range.width * 0.5
            if cell.depth == execution.effectiveLimits.maximumSubdivisionDepth || middle <= cell.range.lower || middle >= cell.range.upper { return false }

            try OriginalParameterQueryStorage.append(Cell(range: try ScalarInterval(lower: middle, upper: cell.range.upper), depth: cell.depth + 1), to: &pending, using: &execution)
            try OriginalParameterQueryStorage.append(Cell(range: try ScalarInterval(lower: cell.range.lower, upper: middle), depth: cell.depth + 1), to: &pending, using: &execution)
        }
        return true
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
