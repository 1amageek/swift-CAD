import CADCore

/// The explicit ownership topology of a B-rep body.
///
/// A solid stores connected material components and each component owns its
/// void shells. A sheet stores independent open shells. No semantic meaning is
/// assigned to the order of a flattened shell list.
public enum BodyTopology: Equatable, Sendable {
    case solid(components: [SolidShellComponent])
    case sheet(shellIDs: [ShellID])

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case components
        case shellIDs
    }
    #endif

    #if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case solid
        case sheet
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .solid:
            try container.validateOnlyExpectedKeys([.kind, .components], in: decoder)
            self = .solid(
                components: try container.decode(
                    [SolidShellComponent].self,
                    forKey: .components
                )
            )
        case .sheet:
            try container.validateOnlyExpectedKeys([.kind, .shellIDs], in: decoder)
            self = .sheet(
                shellIDs: try container.decode([ShellID].self, forKey: .shellIDs)
            )
        }
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let components):
            try container.encode(Kind.solid, forKey: .kind)
            try container.encode(components, forKey: .components)
        case .sheet(let shellIDs):
            try container.encode(Kind.sheet, forKey: .kind)
            try container.encode(shellIDs, forKey: .shellIDs)
        }
    }
    #endif

    public var kind: BodyKind {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .sheet
        }
    }

    public var shellIDs: [ShellID] {
        switch self {
        case .solid(let components):
            components.flatMap({ $0.shellIDs })
        case .sheet(let shellIDs):
            shellIDs
        }
    }

    public var solidComponents: [SolidShellComponent]? {
        guard case .solid(let components) = self else {
            return nil
        }
        return components
    }

    public var sheetShellIDs: [ShellID]? {
        guard case .sheet(let shellIDs) = self else {
            return nil
        }
        return shellIDs
    }
}

#if !hasFeature(Embedded)
extension BodyTopology: Codable {}
#endif
