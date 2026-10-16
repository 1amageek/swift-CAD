import CADCore
import CADGeometry

/// A topological body with explicit solid-component or sheet-shell ownership.
public struct Body: Equatable, Sendable {
    public var id: BodyID
    public var topology: BodyTopology
    public var name: String?
    public var material: MaterialID?

    public init(
        id: BodyID = BodyID(),
        topology: BodyTopology,
        name: String? = nil,
        material: MaterialID? = nil
    ) {
        self.id = id
        self.topology = topology
        self.name = name
        self.material = material
    }

    public init(
        id: BodyID = BodyID(),
        solidComponents: [SolidShellComponent],
        name: String? = nil,
        material: MaterialID? = nil
    ) {
        self.init(
            id: id,
            topology: .solid(components: solidComponents),
            name: name,
            material: material
        )
    }

    public init(
        id: BodyID = BodyID(),
        sheetShellIDs: [ShellID],
        name: String? = nil,
        material: MaterialID? = nil
    ) {
        self.init(
            id: id,
            topology: .sheet(shellIDs: sheetShellIDs),
            name: name,
            material: material
        )
    }

    public var kind: BodyKind {
        topology.kind
    }

    public var shellIDs: [ShellID] {
        topology.shellIDs
    }

    package func originalShellIDs(using execution: inout OriginalQueryExecution) throws -> [ShellID] {
        switch topology {
        case .sheet(let ids):
            for _ in ids { try execution.consumeWork(1) }
            return ids
        case .solid(let components):
            var result: [ShellID] = []
            for component in components {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(component.outerShellID, to: &result, using: &execution)
                for id in component.voidShellIDs {
                    try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(id, to: &result, using: &execution)
                }
            }
            return result
        }
    }

    public var solidComponents: [SolidShellComponent]? {
        topology.solidComponents
    }

    public var sheetShellIDs: [ShellID]? {
        topology.sheetShellIDs
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case id
        case topology
        case name
        case material
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .topology, .name, .material], in: decoder)
        id = try container.decode(BodyID.self, forKey: .id)
        topology = try container.decode(BodyTopology.self, forKey: .topology)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(topology, forKey: .topology)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(material, forKey: .material)
    }
    #endif
}

#if !hasFeature(Embedded)
extension Body: Codable {}
#endif
