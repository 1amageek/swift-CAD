import CADCore

/// One connected solid region represented by an outer shell and its owned void shells.
public struct SolidShellComponent: Equatable, Sendable {
    public let outerShellID: ShellID
    public let voidShellIDs: [ShellID]

    public init(outerShellID: ShellID, voidShellIDs: [ShellID] = []) {
        self.outerShellID = outerShellID
        self.voidShellIDs = voidShellIDs
    }

    public var shellIDs: [ShellID] {
        [outerShellID] + voidShellIDs
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case outerShellID
        case voidShellIDs
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.outerShellID, .voidShellIDs], in: decoder)
        outerShellID = try container.decode(ShellID.self, forKey: .outerShellID)
        voidShellIDs = try container.decode([ShellID].self, forKey: .voidShellIDs)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outerShellID, forKey: .outerShellID)
        try container.encode(voidShellIDs, forKey: .voidShellIDs)
    }
    #endif
}

public extension BRepModel {
    /// Returns the explicit material components owned by a solid body.
    func solidShellComponents(
        for bodyID: BodyID,
        tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> [SolidShellComponent] {
        try tolerance.validate()
        guard let body = bodies[bodyID] else {
            throw TopologyError.missingReference("Missing solid body \(bodyID).")
        }
        guard case .solid(let components) = body.topology else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Solid shell components require a solid body."
            )
        }
        guard components.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A measurable solid body requires at least one forward outer shell."
            )
        }
        for component in components {
            try Task.checkCancellation()
            try consumeWork?(0)
            guard let outerShell = shells[component.outerShellID] else {
                throw TopologyError.missingReference(
                    "Missing solid outer shell \(component.outerShellID)."
                )
            }
            guard outerShell.orientation == .forward else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A solid component outer shell must use forward orientation."
                )
            }
            for voidShellID in component.voidShellIDs {
                try Task.checkCancellation()
                try consumeWork?(0)
                guard let voidShell = shells[voidShellID] else {
                    throw TopologyError.missingReference(
                        "Missing solid void shell \(voidShellID)."
                    )
                }
                guard voidShell.orientation == .reversed else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A solid component void shell must use reversed orientation."
                    )
                }
            }
        }
        return components
    }
}

#if !hasFeature(Embedded)
extension SolidShellComponent: Codable {}
#endif
