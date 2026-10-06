import CADCore
import CADIR
import CADTopology

package struct SourceBRepFacePatchBuilder {
    package struct Result {
        package let patch: BRepSewingFacePatch
        package let stableKeys: [TopologyReference: BRepSewingStableKey]
    }

    package init() {}

    package func build(
        faceID: FaceID,
        stableID: String,
        from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> Result {
        let admission = CopyAdmission(tolerance: tolerance, work: consumeWork, storage: consumeStorage)
        try admission.step()
        try tolerance.validate()
        guard stableID.isEmpty == false,
              let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw missingReference(
                "Source face-patch extraction references missing face geometry.",
                tolerance: tolerance
            )
        }
        try admission.reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride)
        var stableKeys: [TopologyReference: BRepSewingStableKey] = [
            .face(faceID): .face(stableID),
        ]
        var sewingLoops: [BRepSewingLoop] = []
        try admission.reserve(count: face.loops.count, stride: MemoryLayout<BRepSewingLoop>.stride)
        sewingLoops.reserveCapacity(face.loops.count)
        for (loopIndex, loopID) in face.loops.enumerated() {
            try admission.step()
            guard let loop = model.loops[loopID] else {
                throw missingReference(
                    "Source face-patch extraction references a missing loop.",
                    tolerance: tolerance
                )
            }
            try admission.identity(base: stableID, suffixBytes: 6, ordinal: loopIndex)
            let loopStableID = "\(stableID):loop:\(loopIndex)"
            var sewingEdges: [BRepSewingEdge] = []
            try admission.reserve(count: loop.edges.count, stride: MemoryLayout<BRepSewingEdge>.stride)
            sewingEdges.reserveCapacity(loop.edges.count)
            for (useIndex, coedge) in loop.edges.enumerated() {
                try admission.step()
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      let storedStart = model.vertices[edge.startVertexID]?.point,
                      let storedEnd = model.vertices[edge.endVertexID]?.point,
                      let trim = edge.trim,
                      let pcurve = coedge.surfaceParameterCurve else {
                    throw missingReference(
                        "Exact source face-patch extraction requires edge geometry, vertices, and a face-local pcurve.",
                        tolerance: tolerance
                    )
                }
                try admission.identity(base: loopStableID, suffixBytes: 10, ordinal: useIndex)
                let edgeStableID = "\(loopStableID):edge-use:\(useIndex)"
                let oriented = orientedEdge(
                    edge: edge,
                    trim: trim,
                    storedStart: storedStart,
                    storedEnd: storedEnd,
                    orientation: coedge.orientation
                )
                // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded patch-copy callers
                // pay actual source traversal and output payload admission here.
                // Sewing ancestry canonicalization now forwards the same ledger.
                // Stable-key bucket metadata and complete modified-patch validation
                // still require their producer admission before whole ledger closure.
                try sewingEdges.append(BRepSewingEdge(
                    stableID: edgeStableID,
                    curve: curve,
                    startParameter: oriented.startParameter,
                    endParameter: oriented.endParameter,
                    startPoint: oriented.startPoint,
                    endPoint: oriented.endPoint,
                    surfaceParameterCurve: pcurve,
                    parentSubshapeIDs: sourceSubshapeIDs(
                        for: .edge(edge.id),
                        in: sourceSubshapes, admission: admission
                    ),
                    startVertexParentSubshapeIDs: sourceSubshapeIDs(
                        for: .vertex(oriented.startVertexID),
                        in: sourceSubshapes, admission: admission
                    ),
                    endVertexParentSubshapeIDs: sourceSubshapeIDs(
                        for: .vertex(oriented.endVertexID),
                        in: sourceSubshapes, admission: admission
                    ),
                    consumeWork: { _ in try admission.step() },
                    consumeStorage: admission.storage
                ))
                try admission.step()
                if stableKeys[.edge(edge.id)] == nil {
                    try admission.reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride)
                    stableKeys[.edge(edge.id)] = .edge(edgeStableID)
                }
                try admission.step()
                if stableKeys[.vertex(oriented.startVertexID)] == nil {
                    try admission.reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride)
                    stableKeys[.vertex(oriented.startVertexID)] = .startVertex(edge: edgeStableID)
                }
                try admission.step()
                if stableKeys[.vertex(oriented.endVertexID)] == nil {
                    try admission.reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride)
                    stableKeys[.vertex(oriented.endVertexID)] = .endVertex(edge: edgeStableID)
                }
            }
            sewingLoops.append(BRepSewingLoop(
                stableID: loopStableID,
                role: loop.role,
                edges: sewingEdges
            ))
        }
        return try Result(
            patch: BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: face.orientation,
                loops: sewingLoops,
                parentSubshapeIDs: sourceSubshapeIDs(
                    for: .face(faceID),
                    in: sourceSubshapes, admission: admission
                ),
                consumeWork: { _ in try admission.step() },
                consumeStorage: admission.storage
            ),
            stableKeys: stableKeys
        )
    }

    private func orientedEdge(
        edge: Edge,
        trim: CurveTrim,
        storedStart: Point3D,
        storedEnd: Point3D,
        orientation: Orientation
    ) -> OrientedEdge {
        switch orientation {
        case .forward:
            return OrientedEdge(
                startParameter: trim.startParameter,
                endParameter: trim.endParameter,
                startPoint: storedStart,
                endPoint: storedEnd,
                startVertexID: edge.startVertexID,
                endVertexID: edge.endVertexID
            )
        case .reversed:
            return OrientedEdge(
                startParameter: trim.endParameter,
                endParameter: trim.startParameter,
                startPoint: storedEnd,
                endPoint: storedStart,
                startVertexID: edge.endVertexID,
                endVertexID: edge.startVertexID
            )
        }
    }

    private func sourceSubshapeIDs(
        for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference],
        admission: CopyAdmission
    ) throws -> [SubshapeID] {
        var count = 0
        for (_, candidate) in sourceSubshapes {
            try admission.step()
            if candidate == reference {
                let next = count.addingReportingOverflow(1)
                guard !next.overflow else { throw admission.overflow() }
                count = next.partialValue
            }
        }
        try admission.reserve(count: count, stride: MemoryLayout<SubshapeID>.stride)
        var result: [SubshapeID] = []
        result.reserveCapacity(count)
        for (subshapeID, candidate) in sourceSubshapes {
            try admission.step()
            if candidate == reference { result.append(subshapeID) }
        }
        return result
    }

    private struct CopyAdmission: Sendable {
        let tolerance: ModelingTolerance
        let work: (@Sendable (Int) throws -> Void)?
        let storage: (@Sendable (Int) throws -> Void)?

        func step() throws {
            try Task.checkCancellation()
            try work?(0)
        }

        func reserve(count: Int, stride: Int) throws {
            try step()
            let bytes = count.multipliedReportingOverflow(by: stride)
            guard count >= 0, stride >= 0, !bytes.overflow else { throw overflow() }
            try storage?(bytes.partialValue)
        }

        func identity(base: String, suffixBytes: Int, ordinal: Int) throws {
            try step()
            var digits = 1, value = ordinal
            while value >= 10 { try step(); digits += 1; value /= 10 }
            let baseCount = base.utf8.count.addingReportingOverflow(suffixBytes)
            let total = baseCount.partialValue.addingReportingOverflow(digits)
            guard ordinal >= 0, !baseCount.overflow, !total.overflow else { throw overflow() }
            try reserve(count: total.partialValue, stride: MemoryLayout<UInt8>.stride)
        }

        func overflow() -> KernelError {
            KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original face-patch copy admission overflowed its payload count.")
        }
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }

    private struct OrientedEdge {
        let startParameter: Double
        let endParameter: Double
        let startPoint: Point3D
        let endPoint: Point3D
        let startVertexID: VertexID
        let endVertexID: VertexID
    }
}
