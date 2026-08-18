import CADCore
import CADIR
import CADTopology

/// Complete exact topology input for one body sewing operation.
public struct BRepSewingRequest: Sendable {
    public let featureID: FeatureID
    public let bodyTopology: BRepSewingBodyTopology
    public let shells: [BRepSewingShell]
    public let bodyParentSubshapeIDs: [SubshapeID]
    public let topologyNamespace: BRepSewingTopologyNamespace

    public var bodyKind: BodyKind {
        bodyTopology.bodyKind
    }

    public init(
        featureID: FeatureID,
        bodyTopology: BRepSewingBodyTopology,
        shells: [BRepSewingShell],
        bodyParentSubshapeIDs: [SubshapeID] = [],
        topologyNamespace: BRepSewingTopologyNamespace = .feature
    ) {
        self.featureID = featureID
        self.bodyTopology = bodyTopology
        self.shells = shells
        self.bodyParentSubshapeIDs = Array(Set(bodyParentSubshapeIDs)).sorted()
        self.topologyNamespace = topologyNamespace
    }

    public init(
        featureID: FeatureID,
        bodyKind: BodyKind,
        shells: [BRepSewingShell],
        bodyParentSubshapeIDs: [SubshapeID] = [],
        topologyNamespace: BRepSewingTopologyNamespace = .feature
    ) {
        self.featureID = featureID
        self.bodyTopology = Self.inferredBodyTopology(
            bodyKind: bodyKind,
            shells: shells
        )
        self.shells = shells
        self.bodyParentSubshapeIDs = Array(Set(bodyParentSubshapeIDs)).sorted()
        self.topologyNamespace = topologyNamespace
    }

    public func namespaced(
        as topologyNamespace: BRepSewingTopologyNamespace
    ) -> BRepSewingRequest {
        BRepSewingRequest(
            featureID: featureID,
            bodyTopology: bodyTopology,
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
        try bodyTopology.validate(shells: shells, tolerance: tolerance)
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

    private static func inferredBodyTopology(
        bodyKind: BodyKind,
        shells: [BRepSewingShell]
    ) -> BRepSewingBodyTopology {
        switch bodyKind {
        case .sheet:
            return .sheet(shellStableIDs: shells.map(\.stableID))
        case .solid:
            let outerShellStableIDs = shells.compactMap {
                $0.orientation == .forward ? $0.stableID : nil
            }
            let voidShellStableIDs = shells.compactMap {
                $0.orientation == .reversed ? $0.stableID : nil
            }
            if outerShellStableIDs.count == 1 {
                return .solid(components: [BRepSewingSolidComponent(
                    outerShellStableID: outerShellStableIDs[0],
                    voidShellStableIDs: voidShellStableIDs
                )])
            }
            return .solid(components: outerShellStableIDs.map {
                BRepSewingSolidComponent(outerShellStableID: $0)
            })
        }
    }
}
