import CADCore
import CADIR
import CADTopology

/// Complete exact topology input for one body sewing operation.
public struct BRepSewingRequest: Sendable {
    public let featureID: FeatureID
    public let bodyKind: BodyKind
    public let shells: [BRepSewingShell]
    public let bodyParentSubshapeIDs: [SubshapeID]
    public let topologyNamespace: BRepSewingTopologyNamespace

    public init(
        featureID: FeatureID,
        bodyKind: BodyKind,
        shells: [BRepSewingShell],
        bodyParentSubshapeIDs: [SubshapeID] = [],
        topologyNamespace: BRepSewingTopologyNamespace = .feature
    ) {
        self.featureID = featureID
        self.bodyKind = bodyKind
        self.shells = shells
        self.bodyParentSubshapeIDs = Array(Set(bodyParentSubshapeIDs)).sorted()
        self.topologyNamespace = topologyNamespace
    }

    public func namespaced(
        as topologyNamespace: BRepSewingTopologyNamespace
    ) -> BRepSewingRequest {
        BRepSewingRequest(
            featureID: featureID,
            bodyKind: bodyKind,
            shells: shells,
            bodyParentSubshapeIDs: bodyParentSubshapeIDs,
            topologyNamespace: topologyNamespace
        )
    }

    public func validate(tolerance: ModelingTolerance) throws {
        guard shells.isEmpty == false,
              Set(shells.map(\.stableID)).count == shells.count,
              bodyParentSubshapeIDs.allSatisfy(\.isValid) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-rep sewing requires uniquely identified shells."
            )
        }
        for shell in shells {
            do {
                try shell.validate(tolerance: tolerance)
            } catch let error as KernelError {
                throw KernelError(
                    phase: error.phase,
                    code: error.code,
                    residual: error.residual,
                    tolerance: tolerance,
                    message: "B-rep sewing request contains invalid shell \(shell.stableID). \(error.message)"
                )
            } catch {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "B-rep sewing request contains invalid shell \(shell.stableID). \(error)"
                )
            }
        }
        let stableIDs = shells.flatMap { shell in
            [shell.stableID] + shell.patches.flatMap { patch in
                [patch.stableID] + patch.loops.flatMap { loop in
                    [loop.stableID] + loop.edges.map(\.stableID)
                }
            }
        }
        guard Set(stableIDs).count == stableIDs.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-rep sewing stable identities must be unique across the request."
            )
        }
    }
}
