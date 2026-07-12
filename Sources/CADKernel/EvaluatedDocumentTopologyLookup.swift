import CADCore
import CADIR

public extension EvaluatedDocument {
    func persistentNames(for subshapeID: SubshapeID) -> [PersistentName] {
        generatedNames.keys
            .filter { name in
                guard let featureID = name.components.compactMap({ component -> FeatureID? in
                    if case let .feature(value) = component { return value }
                    return nil
                }).first else {
                    return false
                }
                return featureID == subshapeID.featureID && lineageRole(for: name) == subshapeID.role
            }
            .sorted(by: canonicalName(_:_:))
    }

    func persistentName(for subshapeID: SubshapeID) -> PersistentName? {
        guard lineage[subshapeID] != nil else { return nil }
        let candidates = persistentNames(for: subshapeID)
        guard subshapeID.ordinal < candidates.count else { return nil }
        return candidates[subshapeID.ordinal]
    }

    func subshapeID(for name: PersistentName) -> SubshapeID? {
        guard let featureID = name.components.compactMap({ component -> FeatureID? in
            if case let .feature(value) = component { return value }
            return nil
        }).first else {
            return nil
        }
        let role = lineageRole(for: name)
        let seed = SubshapeID(featureID: featureID, role: role, ordinal: 0)
        guard let ordinal = persistentNames(for: seed).firstIndex(of: name) else {
            return nil
        }
        let subshapeID = SubshapeID(featureID: featureID, role: role, ordinal: ordinal)
        return lineage[subshapeID] == nil ? nil : subshapeID
    }
}

private func lineageRole(for name: PersistentName) -> String {
    var subshapeRole: String?
    for component in name.components.reversed() {
        switch component {
        case let .generated(value):
            return value
        case let .subshape(value):
            subshapeRole = subshapeRole ?? value
        case .feature, .index:
            continue
        }
    }
    return subshapeRole ?? "generated"
}

private func canonicalName(_ lhs: PersistentName, _ rhs: PersistentName) -> Bool {
    func key(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case let .feature(featureID): return "feature:\(featureID)"
            case let .generated(value): return "generated:\(value)"
            case let .subshape(value): return "subshape:\(value)"
            case let .index(value): return "index:\(value)"
            }
        }.joined(separator: "/")
    }
    return key(lhs) < key(rhs)
}
