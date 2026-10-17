import CADCore
import CADGeometry
import CADIR
import CADTopology
import HashTreeCollections
import Synchronization
@testable import CADKernel

/// Actual cache-content encoding checks shared by all selected targets.
enum BRepCacheSourceAdmissionChecks {
    private struct Failure: Error { let message: String }
    private enum Stop: Error { case cancelled }
    private struct Encoded {
        let bytes: [UInt8]
        let work: Int
        let storage: Int
    }
    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == stop { throw Stop.cancelled }
        }
    }

    // These are the existing ordinary cache-content encoding allowances.
    private static var limits: PortableSourceEncodingLimits {
        .init(maximumBytes: Int.max, maximumWork: Int.max, maximumDepth: Int.max)
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }
    private static func input() throws -> BRepModel {
        let cube = VolumeMomentLoopAdmissionChecks.cube()
        try require(cube.model.bodies.count == 1 && cube.model.shells.count == 1
            && cube.model.faces.count == 6 && cube.model.loops.count == 6
            && cube.model.edges.count == 12 && cube.model.vertices.count == 8,
            "The complete authored cube changed.")
        // Preparation is an explicit genuine public operation, separate from encoding.
        try cube.model.validate(tolerance: .standard)
        return cube.model
    }
    private static func original(_ error: any Error) -> any Error {
        VolumeMomentLoopAdmissionChecks.original(error)
    }
    private static func axis(_ error: any Error) -> OriginalQueryResourceAxis? {
        if let failure = error as? OriginalQueryFailure { return failure.context.resource?.axis }
        if case .admissionRejected(let cause)? = error as? ExactScalarFailure { return axis(cause) }
        return nil
    }
    private static func encode(_ source: BRepCacheContentSource,
        budget: OriginalQueryBudget, prefixWork: Int = 0, prefixBytes: Int = 0) throws -> Encoded {
        var admission = try VolumeMomentLoopAdmissionChecks.execution(budget)
        if prefixWork != 0 { try admission.consumeWork(prefixWork) }
        if prefixBytes != 0 { try admission.retainStorage(count: prefixBytes, stride: MemoryLayout<UInt8>.stride) }
        var encoder = try PortableSourceEncoder(limits: limits)
        try encoder.value(source, using: &admission)
        try require(budget.snapshot.work == admission.localWork
            && budget.snapshot.storageBytes == admission.localStorageBytes,
            "The codec lost its original cumulative caller.")
        try require(admission.localWork == encoder.consumedWork + prefixWork,
            "A child writer reset or duplicated the admitted work.")
        return Encoded(bytes: encoder.bytes, work: admission.localWork, storage: admission.localStorageBytes)
    }
    private static func ordinary(_ source: BRepCacheContentSource) throws -> [UInt8] {
        var encoder = try PortableSourceEncoder(limits: limits)
        try encoder.value(source)
        return encoder.bytes
    }

    /// Reauthors only identifiers and references; every original geometric value is retained.
    private static func reidentified(_ source: BRepModel) -> BRepModel {
        func id<Tag>(_ old: TaggedID<Tag>) -> TaggedID<Tag> {
            .init(.init(high: old.rawValue.high ^ 0x8000_0000_0000_0000, low: old.rawValue.low))
        }
        var result = BRepModel()
        for (key, value) in source.geometry.curves { result.geometry.curves[id(key)] = value }
        for (key, value) in source.geometry.surfaces { result.geometry.surfaces[id(key)] = value }
        for vertex in source.vertices.values {
            result.vertices[id(vertex.id)] = Vertex(id: id(vertex.id), point: vertex.point,
                originalPoint: vertex.originalPoint)
        }
        for edge in source.edges.values {
            result.edges[id(edge.id)] = Edge(id: id(edge.id), curveID: id(edge.curveID),
                startVertexID: id(edge.startVertexID), endVertexID: id(edge.endVertexID), trim: edge.trim)
        }
        for loop in source.loops.values {
            let coedges = loop.coedges.map { Coedge(edgeID: id($0.edgeID), orientation: $0.orientation,
                surfaceParameterCurve: $0.surfaceParameterCurve) }
            result.loops[id(loop.id)] = Loop(id: id(loop.id), role: loop.role, coedges: coedges)
        }
        for face in source.faces.values {
            result.faces[id(face.id)] = Face(id: id(face.id), surfaceID: id(face.surfaceID),
                loops: face.loops.map { id($0) }, orientation: face.orientation)
        }
        for shell in source.shells.values {
            result.shells[id(shell.id)] = Shell(id: id(shell.id), faceIDs: shell.faceIDs.map { id($0) },
                orientation: shell.orientation)
        }
        for body in source.bodies.values {
            let topology: BodyTopology
            switch body.topology {
            case .solid(let components):
                topology = .solid(components: components.map {
                    .init(outerShellID: id($0.outerShellID), voidShellIDs: $0.voidShellIDs.map { id($0) })
                })
            case .sheet(let shells): topology = .sheet(shellIDs: shells.map { id($0) })
            }
            result.bodies[id(body.id)] = Body(id: id(body.id), topology: topology,
                name: body.name, material: body.material)
        }
        return result
    }

    static func canonicalOriginalContentIgnoresRegeneratedTopologyIDs() throws {
        let model = try input()
        let source = BRepCacheContentSource(model: model)
        let expected = try ordinary(source)
        let admitted = try encode(source, budget: OriginalQueryBudget())
        try require(!expected.isEmpty && admitted.bytes == expected,
            "The admitted complete original content changed its canonical bytes.")
        let remapped = reidentified(model)
        try remapped.validate(tolerance: .standard)
        try require(model.bodies.keys.first != remapped.bodies.keys.first
            && model.geometry.curves.keys.first != remapped.geometry.curves.keys.first,
            "The control did not regenerate original topology identifiers.")
        try require(try encode(BRepCacheContentSource(model: remapped), budget: OriginalQueryBudget()).bytes == expected,
            "Canonical content retained regenerated topology identifiers.")
        var changed = model
        let bodyID = VolumeMomentLoopAdmissionChecks.cube().bodyID
        guard var body = changed.bodies[bodyID] else { throw Failure(message: "The authored body is absent.") }
        body.name = "Different original body content"
        changed.bodies[bodyID] = body
        try require(try encode(BRepCacheContentSource(model: changed), budget: OriginalQueryBudget()).bytes != expected,
            "Different original body content was erased together with identifiers.")
    }

    static func exactCumulativeWorkAndStorageBoundaries() throws {
        // Repeated requests retain this exact immutable model and canonical input order.
        let source = BRepCacheContentSource(model: try input())
        let measured = try encode(source, budget: OriginalQueryBudget())
        try require(measured.work > 1 && measured.storage > measured.bytes.count,
            "Nested child arrays and canonical keys escaped admission.")
        let exact = try encode(source, budget: OriginalQueryBudget(workLimit: measured.work,
            storageByteLimit: measured.storage))
        try require(exact.bytes == measured.bytes && exact.work == measured.work
            && exact.storage == measured.storage, "Exact retained-input allowances changed the result.")
        for storage in [false, true] {
            for zero in [false, true] {
                let budget = try OriginalQueryBudget(workLimit: storage ? measured.work : (zero ? 0 : measured.work - 1),
                    storageByteLimit: storage ? (zero ? 0 : measured.storage - 1) : measured.storage)
                do {
                    _ = try encode(source, budget: budget)
                    throw Failure(message: "A zero or N-1 caller allowance published cache content.")
                } catch {
                    try require(axis(error) == (storage ? .storageBytes : .work),
                        "The codec changed the original independent resource refusal.")
                }
            }
        }
        let prefixed = try encode(source, budget: OriginalQueryBudget(workLimit: measured.work + 13,
            storageByteLimit: measured.storage + 17), prefixWork: 13, prefixBytes: 17)
        try require(prefixed.bytes == measured.bytes && prefixed.work == measured.work + 13
            && prefixed.storage == measured.storage + 17,
            "Nested cache content encoding reset a paid caller prefix.")
    }

    static func nestedFailuresRetainTheirOriginalTypedCause() throws {
        let model = try input()
        var missing = model
        missing.geometry.curves.removeAll(where: { _ in true })
        let missingBudget = try OriginalQueryBudget()
        do {
            _ = try encode(BRepCacheContentSource(model: missing), budget: missingBudget)
            throw Failure(message: "Missing original edge geometry encoded successfully.")
        } catch {
            guard case .missingReference(let message)? = original(error) as? TopologyError else { throw error }
            try require(message == "Cache content original edge geometry is absent." && missingBudget.snapshot.work > 0,
                "The nested coedge failure changed its original cause or bypassed its caller.")
        }
        var nonfinite = model
        let vertexID = VertexID(PortableIdentity128(high: 1, low: 1))
        guard var vertex = nonfinite.vertices[vertexID] else { throw Failure(message: "The original cube vertex is absent.") }
        vertex.point.x = .infinity
        nonfinite.vertices[vertexID] = vertex
        do {
            _ = try encode(BRepCacheContentSource(model: nonfinite), budget: OriginalQueryBudget())
            throw Failure(message: "A nested nonfinite original source encoded successfully.")
        } catch PortableSourceEncodingError.nonfiniteScalar {}
        var caller = try VolumeMomentLoopAdmissionChecks.execution(OriginalQueryBudget())
        var encoder = try PortableSourceEncoder(limits: .init(maximumBytes: Int.max,
            maximumWork: Int.max, maximumDepth: 1))
        do {
            try encoder.value(BRepCacheContentSource(model: model), using: &caller)
            throw Failure(message: "The nested source encoding depth was waived.")
        } catch PortableSourceEncodingError.resourceLimitExceeded(let reason) {
            try require(reason == "Source encoding depth." && caller.localWork > 0,
                "The original nested encoding guard or caller was replaced.")
        }
    }

    static func cancellationAndRetainedSourceLifetime() throws {
        let source = BRepCacheContentSource(model: try input())
        let observation = Checkpoints()
        let expected = try encode(source, budget: OriginalQueryBudget(checkpoint: { try observation.check() }))
        let last = observation.count
        try require(last > 3, "The complete nonempty source did not reach interior checkpoints.")
        // Same retained input and same traversal; the last checkpoint belongs to encoder.value publication.
        for ordinal in [1, last / 2, last] {
            let control = Checkpoints(stop: ordinal)
            let budget = try OriginalQueryBudget(checkpoint: { try control.check() })
            do {
                _ = try encode(source, budget: budget)
                throw Failure(message: "A cancelled cache source published complete content.")
            } catch {
                try require(original(error) as? Stop == .cancelled && control.count == ordinal,
                    "The original entry, interior or terminal cancellation was replaced.")
            }
            if ordinal == 1 {
                try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                    "Entry cancellation admitted source work or storage.")
            }
        }
        func detachedBytes() throws -> [UInt8] {
            var authored = VolumeMomentLoopAdmissionChecks.cube().model
            let retained = BRepCacheContentSource(model: authored)
            authored.geometry.curves.removeAll(where: { _ in true })
            authored.loops.removeAll(where: { _ in true })
            try require(authored.geometry.curves.isEmpty && authored.loops.isEmpty,
                "The COW control did not remove authored buffers.")
            return try encode(retained, budget: OriginalQueryBudget()).bytes
        }
        try require(try detachedBytes() == expected.bytes,
            "Returned bytes or retained source changed after authored mutation and owner release.")
    }
}
