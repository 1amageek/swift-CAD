import CADCore
import CADIR

struct IncrementalEvaluationGraphState: Sendable {
    let documentIdentity: ValidatedCADDocumentIdentity
    let profileSourceFeatureIDs: Set<FeatureID>
    let curveSourceFeatureIDs: Set<FeatureID>
    let dependentsByFeatureID: [FeatureID: [FeatureID]]
    let orderIndexByFeatureID: [FeatureID: Int]

    init(_ document: ValidatedCADDocument) {
        documentIdentity = document.identity
        let graph = document.document.designGraph

        var profileSourceFeatureIDs = Set<FeatureID>()
        var curveSourceFeatureIDs = Set<FeatureID>()
        profileSourceFeatureIDs.reserveCapacity(graph.nodes.count)
        curveSourceFeatureIDs.reserveCapacity(graph.nodes.count)
        for node in graph.nodes.values where !node.isSuppressed {
            if node.outputs.contains(where: { $0.role == .curve }) {
                curveSourceFeatureIDs.insert(node.id)
            }
            for input in node.inputs {
                switch input.role {
                case .profile:
                    profileSourceFeatureIDs.insert(input.featureID)
                case .path, .guide:
                    curveSourceFeatureIDs.insert(input.featureID)
                case .curve, .target, .body, .sheet:
                    continue
                }
            }
        }
        self.profileSourceFeatureIDs = profileSourceFeatureIDs
        self.curveSourceFeatureIDs = curveSourceFeatureIDs

        var dependentsByFeatureID: [FeatureID: [FeatureID]] = [:]
        dependentsByFeatureID.reserveCapacity(graph.nodes.count)
        for dependency in graph.dependencies {
            dependentsByFeatureID[dependency.source, default: []].append(dependency.target)
        }
        self.dependentsByFeatureID = dependentsByFeatureID
        orderIndexByFeatureID = Dictionary(
            uniqueKeysWithValues: graph.order.enumerated().map { index, featureID in
                (featureID, index)
            }
        )
    }

    func graphStableChanges(
        for document: ValidatedCADDocument
    ) -> Set<FeatureID>? {
        if document.identity == documentIdentity {
            return []
        }
        guard let transition = document.transition,
              transition.sourceIdentity == documentIdentity else {
            return nil
        }
        return transition.changedFeatureIDs
    }

    func reidentified(
        as documentIdentity: ValidatedCADDocumentIdentity
    ) -> IncrementalEvaluationGraphState {
        IncrementalEvaluationGraphState(
            documentIdentity: documentIdentity,
            profileSourceFeatureIDs: profileSourceFeatureIDs,
            curveSourceFeatureIDs: curveSourceFeatureIDs,
            dependentsByFeatureID: dependentsByFeatureID,
            orderIndexByFeatureID: orderIndexByFeatureID
        )
    }

    func invalidationClosure(
        startingWith featureIDs: Set<FeatureID>
    ) -> Set<FeatureID> {
        guard !featureIDs.isEmpty else {
            return []
        }
        var invalidated = Set<FeatureID>()
        invalidated.reserveCapacity(featureIDs.count)
        var pending = Array(featureIDs)
        while let featureID = pending.popLast() {
            guard invalidated.insert(featureID).inserted else {
                continue
            }
            pending.append(contentsOf: dependentsByFeatureID[featureID, default: []])
        }
        return invalidated
    }

    func evaluationOrder(
        for featureIDs: Set<FeatureID>
    ) throws -> [FeatureID] {
        try ordered(featureIDs, ascending: true)
    }

    func rollbackOrder(
        for featureIDs: Set<FeatureID>
    ) throws -> [FeatureID] {
        try ordered(featureIDs, ascending: false)
    }

    private init(
        documentIdentity: ValidatedCADDocumentIdentity,
        profileSourceFeatureIDs: Set<FeatureID>,
        curveSourceFeatureIDs: Set<FeatureID>,
        dependentsByFeatureID: [FeatureID: [FeatureID]],
        orderIndexByFeatureID: [FeatureID: Int]
    ) {
        self.documentIdentity = documentIdentity
        self.profileSourceFeatureIDs = profileSourceFeatureIDs
        self.curveSourceFeatureIDs = curveSourceFeatureIDs
        self.dependentsByFeatureID = dependentsByFeatureID
        self.orderIndexByFeatureID = orderIndexByFeatureID
    }

    private func ordered(
        _ featureIDs: Set<FeatureID>,
        ascending: Bool
    ) throws -> [FeatureID] {
        try featureIDs.sorted { lhs, rhs in
            guard let lhsIndex = orderIndexByFeatureID[lhs],
                  let rhsIndex = orderIndexByFeatureID[rhs] else {
                throw IncrementalReplayError.stateMismatch(table: "featureOrder")
            }
            return ascending ? lhsIndex < rhsIndex : lhsIndex > rhsIndex
        }
    }
}
