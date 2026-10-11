import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicCoonsSelf

/// Complete public residual oracle for the original four-chart planar Coons product.
@main struct CoonsGraphSelfContactAcceptance {
    typealias Probe = CoonsGraphSelfContactProbe
    typealias Result = OriginalIssuedGraphSelfContacts<Probe.Source,Probe.Evidence,Probe.Cover,Probe.Evidence,Probe.Cover>
    static func query(_ raw: Probe.Raw, using a: inout PolylineLiftProof.Admission) throws -> Result {
        try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: raw,
            domainLimits: PolylineLiftProof.limits(),
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }
    static func main() throws {
        var preparation = try PolylineLiftProof.Admission(work: 80_000_000)
        let raw = try Probe.raw(using: &preparation)
        try Probe.oracle(raw, using: &preparation)
        var admission = try PolylineLiftProof.Admission(work: 80_000_000)
        let result = try query(raw, using: &admission)
        try PolylineLiftProof.require(result.raw.pairs.count == 16 && result.refinements.count == 16 && result.authoredDiagonals.count == 16)
        for ordinal in result.refinements.indices {
            let refined = result.refinements[ordinal], pullback = refined.pullback
            try PolylineLiftProof.require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0,1,2,3])
            let original = raw.pairs[ordinal].relation.projection.original.cells
            try PolylineLiftProof.require(pullback.source.cells.count == original.count)
            for index in original.indices { try PolylineLiftProof.require(pullback.source.cells[index] == original[index]) }
            try PolylineLiftProof.require(pullback.region.included.allSatisfy { !$0 })
            for sourceOrdinal in pullback.sourceCellOrdinals { try PolylineLiftProof.require(sourceOrdinal == -1) }
        }
        print("PASS S-COONS-PLANE-01 public complete empty residual; all16 raw/refined owners retained")
#if !hasFeature(Embedded)
        print("queryWork", admission.ledger.work, "queryBytes", admission.ledger.storageBytes, "checkpoints", admission.checkpoints)
#endif
    }
}
