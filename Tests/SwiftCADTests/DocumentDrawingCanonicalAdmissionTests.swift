import Testing
import Synchronization
import Foundation
import CADCore
import CADGeometry
import CADIR
import CADKernel
import SwiftCAD

@Suite("Document drawing canonical admission")
struct DocumentDrawingCanonicalAdmissionTests {
    private struct Source: Sendable {
        let document: CADDocument
        let evaluated: EvaluatedDocument
        let frame: OrthographicProjectionFrame
        let bodyID: BodyID
    }

    private func stage(_ name: String, curved: Bool) {
        let line = "DRAWING_STAGE curved=\(curved) main=\(Thread.isMainThread) \(name)\n"
        let data = Data(line.utf8)
        FileHandle.standardError.write(data)
        if let path = ProcessInfo.processInfo.environment["G01_DIAGNOSTIC_STAGE_LOG"] {
            do {
                let output = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                defer {
                    do { try output.close() }
                    catch { Issue.record("Drawing diagnostic stage log close failed: \(error)") }
                }
                _ = try output.seekToEnd()
                try output.write(contentsOf: data)
            } catch {
                Issue.record("Drawing diagnostic stage log append failed: \(error)")
            }
        }
    }

    @MainActor
    private func source(curved: Bool) throws -> Source {
        #expect(Thread.isMainThread)
        stage("source.builder.begin", curved: curved)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        stage("source.builder.end", curved: curved)
        stage("source.bSplineSurface.begin", curved: curved)
        if curved {
            // These stored binary controls give exactly z = (u - 1/2)^2.
            _ = try builder.bSplineSurface(BSplineSurface3D(
                uDegree: 2, vDegree: 1,
                uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [
                    [.init(x: 0, y: 0, z: 0.25), .init(x: 0.5, y: 0, z: -0.25), .init(x: 1, y: 0, z: 0.25)],
                    [.init(x: 0, y: 1, z: 0.25), .init(x: 0.5, y: 1, z: -0.25), .init(x: 1, y: 1, z: 0.25)]
                ]))
        } else {
            _ = try builder.bSplineSurface(.bilinearPatch(bottomLeft: .origin,
                bottomRight: .init(x: 1, y: 0, z: 0), topRight: .init(x: 1, y: 1, z: 0),
                topLeft: .init(x: 0, y: 1, z: 0)))
        }
        stage("source.bSplineSurface.end", curved: curved)
        stage("source.build.begin", curved: curved)
        let document = try builder.build(name: curved ? "Original quadratic arch" : "Original planar sheet")
        stage("source.build.end", curved: curved)
        stage("source.evaluateExact.begin", curved: curved)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        stage("source.evaluateExact.end", curved: curved)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        return Source(document: document, evaluated: evaluated,
            frame: try .init(origin: .origin, normal: curved ? .unitX : .unitZ,
                horizontalHint: curved ? .unitY : .unitX, tolerance: .standard), bodyID: bodyID)
    }

    private func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 16, maximumTransportDepth: 16, maximumSubdivisionDepth: 32,
            maximumSpans: 64))
    }

    @inline(never)
    private func query(_ source: Source, curved: Bool,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingProjectedContacts {
        let (placed, placement) = try projectAndPlace(source, curved: curved, using: &execution)
        let silhouettes: any DocumentDrawingSilhouetteProducing = DocumentDrawingSilhouetteProducer()
        let unplaced = try unplacedSilhouettes(silhouettes, source: source, curved: curved, using: &execution)
        let packet = try placedSilhouettes(silhouettes, placement: placement, source: source,
            curved: curved, using: &execution)
        try readSilhouettes(unplaced, packet: packet, curved: curved, using: &execution)
        let contacts: any DocumentDrawingProjectedContactPreparing = DocumentDrawingProjectedContactPreparer()
        let result = try prepareContacts(contacts, placed: placed, packet: packet, source: source,
            curved: curved, using: &execution)
        try readContacts(result, curved: curved, using: &execution)
        return result
    }

    @inline(never)
    private func projectAndPlace(_ source: Source, curved: Bool,
        using execution: inout OriginalQueryExecution) throws -> (BRepDrawingPlacedProjection, BRepDrawingPlacement) {
        stage("query.projectEdges.begin", curved: curved)
        let projection = try BRepDrawingProjector().projectEdges(in: source.evaluated,
            onto: source.frame, maximumProjectedUses: 4, using: &execution)
        stage("query.projectEdges.end", curved: curved)
        let placement = try BRepDrawingPlacement(identity: "original identity occurrence", bodyID: source.bodyID,
            transform: .init(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero))
        stage("query.place.begin", curved: curved)
        let placed = try DefaultBRepDrawingPlacer().place(projection, in: source.evaluated,
            placements: [placement], maximumPlacements: 1, maximumProjectedUses: 4, using: &execution)
        stage("query.place.end", curved: curved)
        #expect(placed.uses.count == 4)
        return (placed, placement)
    }

    @inline(never)
    private func unplacedSilhouettes(_ silhouettes: any DocumentDrawingSilhouetteProducing,
        source: Source, curved: Bool, using execution: inout OriginalQueryExecution) throws -> BRepDrawingSilhouettes {
        stage("query.unplacedSilhouettes.begin", curved: curved)
        let unplaced = try silhouettes.silhouettes(document: source.document, currentEvaluation: source.evaluated,
            onto: source.frame, maximumSourceFaces: 1, maximumProjectedSpans: 4,
            maximumControlPointCount: 6, maximumBoundaryCurveCount: 4, using: &execution)
        stage("query.unplacedSilhouettes.end", curved: curved)
        return unplaced
    }

    @inline(never)
    private func placedSilhouettes(_ silhouettes: any DocumentDrawingSilhouetteProducing,
        placement: BRepDrawingPlacement, source: Source, curved: Bool,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingSilhouettes {
        stage("query.placedSilhouettes.begin", curved: curved)
        let packet = try silhouettes.silhouettes(placement, document: source.document,
            currentEvaluation: source.evaluated, onto: source.frame, maximumSourceEntities: 64,
            maximumSourceFaces: 1, maximumProjectedSpans: 4, maximumControlPointCount: 6,
            maximumBoundaryCurveCount: 4, using: &execution)
        stage("query.placedSilhouettes.end", curved: curved)
        return packet
    }

    @inline(never)
    private func readSilhouettes(_ unplaced: BRepDrawingSilhouettes, packet: BRepDrawingSilhouettes,
        curved: Bool, using execution: inout OriginalQueryExecution) throws {
        stage("query.silhouetteReaders.begin", curved: curved)
        try check(unplaced, curved: curved, using: &execution)
        try check(packet, curved: curved, using: &execution)
        stage("query.silhouetteReaders.end", curved: curved)
    }

    @inline(never)
    private func prepareContacts(_ contacts: any DocumentDrawingProjectedContactPreparing,
        placed: BRepDrawingPlacedProjection, packet: BRepDrawingSilhouettes, source: Source, curved: Bool,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingProjectedContacts {
        stage("query.contacts.prepare.begin", curved: curved)
        let result = try contacts.prepare(placed, silhouettes: [packet], document: source.document,
            currentEvaluation: source.evaluated, maximumPartitions: 4, using: &execution)
        stage("query.contacts.prepare.end", curved: curved)
        return result
    }

    @inline(never)
    private func readContacts(_ result: BRepDrawingProjectedContacts, curved: Bool,
        using execution: inout OriginalQueryExecution) throws {
        stage("query.contactReaders.begin", curved: curved)
        #expect(result.projection.uses.count == 4)
        if curved {
            // The two end rails touch the projected V line at its original endpoints;
            // the other two rails are separated at z = 1/4.
            #expect(result.entries.count == 4)
            #expect(result.cells.count == 4)
            #expect(result.entries.reduce(0) { $0 + $1.partition.contacts.count } == 2)
            #expect(result.entries.allSatisfy { !$0.partition.hasWholeRangeProjectedOverlap })
            let precision = try ExactRationalCoefficient.originalDouble(1.0 / 1024, usage: &execution)
            var lowerEndpointCount = 0, upperEndpointCount = 0
            for entry in result.entries {
                for contact in entry.partition.contacts {
                    #expect(contact.edgeMultiplicity == 2)
                    #expect(!contact.coversWholeEdgeRange)
                    let edge = try #require(contact.edgeParameter)
                    let parameter = try edge.enclosure(maximumWidth: precision, using: &execution)
                    #expect(parameter.lower <= 0.5 && parameter.upper >= 0.5)
                    let uv = try contact.parameterEnclosure(maximumWidth: precision, using: &execution)
                    #expect(uv.u.lower <= 0.5 && uv.u.upper >= 0.5)
                    if uv.v.lower <= 0 && uv.v.upper < 0.25 { lowerEndpointCount += 1 }
                    if uv.v.lower > 0.75 && uv.v.upper >= 1 { upperEndpointCount += 1 }
                    guard case .zero = try contact.depthDifferenceSign(using: &execution) else {
                        Issue.record("Original endpoint contact changed its zero depth difference.")
                        continue
                    }
                }
            }
            #expect(lowerEndpointCount == 1 && upperEndpointCount == 1)
        } else {
            #expect(result.entries.isEmpty)
            #expect(result.cells.isEmpty)
        }
        stage("query.contactReaders.end", curved: curved)
    }

    @inline(never)
    private func check(_ packet: BRepDrawingSilhouettes, curved: Bool,
        using execution: inout OriginalQueryExecution) throws {
        #expect(packet.originalFaces.count == 1)
        #expect(packet.contacts.isEmpty)
        #expect(packet.algebraicContacts.isEmpty)
        #expect(packet.spans.isEmpty)
        if curved {
            #expect(packet.exactTrimmedSpans.count == 1)
            let span = try #require(packet.exactTrimmedSpans.first)
            #expect(!span.isSpatiallyCollapsed)
            #expect(!span.isCoincidentWithTrim)
            let whole = try span.curve.enclosure(overNormalized: .init(lower: 0, upper: 1),
                maximumParameterWidth: .one, using: &execution)
            #expect(whole.parameters.u.lower <= 0.5 && whole.parameters.u.upper >= 0.5)
            #expect(whole.parameters.v.lower <= 0 && whole.parameters.v.upper >= 1)
            let position = try #require(whole.spatialDerivatives.first)
            #expect(position.x.lower <= 0.5 && position.x.upper >= 0.5)
            #expect(position.y.lower <= 0 && position.y.upper >= 1)
            #expect(position.z.lower <= 0 && position.z.upper >= 0)
        } else {
            #expect(packet.exactTrimmedSpans.isEmpty)
            let face = try #require(packet.originalFaces.first)
            #expect(face.original.excludedDomains == [face.original.domain])
            #expect(face.original.coincidentDomains.isEmpty)
        }
    }

    private func expectResourceFailure(_ operation: () throws -> Void) {
        do { try operation(); Issue.record("Drawing publication exceeded its caller resource ceiling.") }
        catch {
            let published = OriginalQueryFailure.published(error, context: .unspecified, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
        }
    }

    @inline(never)
    private func retainedContactContribution(_ retained: BRepDrawingProjectedContacts,
        source: Source, budget: OriginalQueryBudget, workLimit: Int? = nil,
        storageByteLimit: Int? = nil) throws -> OriginalQueryBudgetSnapshot {
        var execution = try self.execution(budget)
        let handle = try execution.makeContributionHandle(workLimit: workLimit,
            storageByteLimit: storageByteLimit)
        try execution.withContributionScope(handle) { execution in
            let contacts: any DocumentDrawingProjectedContactPreparing = DocumentDrawingProjectedContactPreparer()
            let result = try prepareContacts(contacts, placed: retained.projection,
                packet: try #require(retained.silhouettes.first), source: source,
                curved: true, using: &execution)
            try readContacts(result, curved: true, using: &execution)
        }
        return handle.snapshot
    }

    private func assertWorkerThread() {
        #expect(!Thread.isMainThread)
    }

    @Test(.timeLimit(.minutes(2)))
    func planarWholeExclusionUsesTheRealDrawingWitnesses() async throws {
        stage("test.begin", curved: false)
        let source = try await self.source(curved: false)
        assertWorkerThread()
        var execution = try self.execution(OriginalQueryBudget())
        _ = try query(source, curved: false, using: &execution)
        #expect(execution.budget.snapshot.work > 0)
        #expect(execution.budget.snapshot.storageBytes > 0)
    }

    @Test(.timeLimit(.minutes(2)))
    func originalArchAndProjectedEndpointContactsShareExactResourceBoundaries() async throws {
        stage("test.begin", curved: true)
        let source = try await self.source(curved: true)
        assertWorkerThread()
        let budget = try OriginalQueryBudget()
        var baseline = try self.execution(budget)
        let result = try query(source, curved: true, using: &baseline)
        let measured = budget.snapshot
        #expect(measured.work > 0 && measured.storageBytes > 0)
        print("DRAWING_ARCH faces=\(result.silhouettes[0].originalFaces.count) spans=\(result.silhouettes[0].exactTrimmedSpans.count) uses=\(result.projection.uses.count) pairs=\(result.entries.count) contacts=\(result.entries.reduce(0) { $0 + $1.partition.contacts.count }) work=\(measured.work) bytes=\(measured.storageBytes)")
        // Fresh boundary dictionaries can change charged heap-sort comparisons.
        // Measure N on the retained consumer input and preserve its issuing owner.
        let consumer = try retainedContactContribution(result, source: source, budget: budget)
        let exact = try retainedContactContribution(result, source: source, budget: budget,
            workLimit: consumer.work, storageByteLimit: consumer.storageBytes)
        #expect(exact.work == consumer.work)
        #expect(exact.storageBytes == consumer.storageBytes)
        expectResourceFailure {
            _ = try retainedContactContribution(result, source: source, budget: budget,
                workLimit: consumer.work - 1)
        }
        expectResourceFailure {
            _ = try retainedContactContribution(result, source: source, budget: budget,
                storageByteLimit: consumer.storageBytes - 1)
        }
        #expect(budget.snapshot.work > measured.work && budget.snapshot.storageBytes > measured.storageBytes)
        var workShort = try self.execution(OriginalQueryBudget(workLimit: 0))
        expectResourceFailure { _ = try query(source, curved: true, using: &workShort) }
        var bytesShort = try self.execution(OriginalQueryBudget(storageByteLimit: 0))
        expectResourceFailure { _ = try query(source, curved: true, using: &bytesShort) }
    }

    @Test(.timeLimit(.minutes(2)))
    func drawingWitnessesPreserveTheCallerCancellationCause() async throws {
        stage("test.begin", curved: false)
        let source = try await self.source(curved: false)
        assertWorkerThread()
        let cancelled = Mutex(false)
        let budget = try OriginalQueryBudget(checkpoint: {
            if cancelled.withLock({ $0 }) { throw CancellationError() }
        })
        var execution = try self.execution(budget)
        let prepared = try query(source, curved: false, using: &execution)
        cancelled.withLock { $0 = true }
        let silhouettes: any DocumentDrawingSilhouetteProducing = DocumentDrawingSilhouetteProducer()
        let contacts: any DocumentDrawingProjectedContactPreparing = DocumentDrawingProjectedContactPreparer()
        do {
            _ = try silhouettes.silhouettes(document: source.document, currentEvaluation: source.evaluated,
                onto: source.frame, maximumSourceFaces: 1, maximumProjectedSpans: 4,
                maximumControlPointCount: 6, maximumBoundaryCurveCount: 4, using: &execution)
            Issue.record("Silhouette witness ignored caller cancellation.")
        } catch {
            #expect(OriginalQueryFailure.published(error, context: .unspecified, tolerance: .standard) is CancellationError)
        }
        let placement = try #require(prepared.projection.placements.first)
        do {
            _ = try silhouettes.silhouettes(placement, document: source.document,
                currentEvaluation: source.evaluated, onto: source.frame, maximumSourceEntities: 64,
                maximumSourceFaces: 1, maximumProjectedSpans: 4, maximumControlPointCount: 6,
                maximumBoundaryCurveCount: 4, using: &execution)
            Issue.record("Placed silhouette witness ignored caller cancellation.")
        } catch {
            #expect(OriginalQueryFailure.published(error, context: .unspecified, tolerance: .standard) is CancellationError)
        }
        do {
            _ = try contacts.prepare(prepared.projection, silhouettes: prepared.silhouettes,
                document: source.document, currentEvaluation: source.evaluated, maximumPartitions: 4, using: &execution)
            Issue.record("Projected-contact witness ignored caller cancellation.")
        } catch {
            #expect(OriginalQueryFailure.published(error, context: .unspecified, tolerance: .standard) is CancellationError)
        }
    }
}
