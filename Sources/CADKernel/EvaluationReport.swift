import CADCore
import CADIR

public struct EvaluationReport: Sendable {
    public var document: CADDocument
    public var evaluatedDocument: EvaluatedDocument?
    public var featureStates: [FeatureID: FeatureEvaluationState]
    public var failure: EvaluationFailure?

    public init(
        document: CADDocument,
        evaluatedDocument: EvaluatedDocument?,
        featureStates: [FeatureID: FeatureEvaluationState],
        failure: EvaluationFailure? = nil
    ) {
        self.document = document
        self.evaluatedDocument = evaluatedDocument
        self.featureStates = featureStates
        self.failure = failure
    }

    public var isComplete: Bool {
        guard let evaluatedDocument, failure == nil,
              document == evaluatedDocument.document,
              Set(featureStates.keys) == Set(document.designGraph.nodes.keys) else { return false }
        for (id, node) in document.designGraph.nodes {
            guard let state = featureStates[id] else { return false }
            switch (node.isSuppressed, state) {
            case (false, .evaluated), (true, .suppressed): continue
            default: return false
            }
        }
        return true
    }

    public func validate() throws {
        if let failure {
            try failure.validate()
        }
        let graphIDs = Set(document.designGraph.nodes.keys)
        guard Set(featureStates.keys) == graphIDs else {
            throw FeatureEvaluationError.invalidGraph("Evaluation states must cover exactly the source graph.")
        }
        for (id, state) in featureStates {
            try CurrentTaskCancellationChecker().checkCancellation()
            switch state {
            case .failed(let featureFailure):
                try featureFailure.validate()
                guard featureFailure.featureID == id,
                      Set(featureFailure.invalidatedFeatureIDs).isSubset(of: graphIDs) else {
                    throw FeatureEvaluationError.invalidGraph("Failed feature state has foreign provenance.")
                }
                for downstream in featureFailure.invalidatedFeatureIDs {
                    guard case .some(.blocked(let upstream)) = featureStates[downstream], upstream == id else {
                        throw FeatureEvaluationError.invalidGraph("Failed feature descendants must retain blocked provenance.")
                    }
                }
            case .blocked(let upstream):
                guard upstream != id, case .some(.failed(let failed)) = featureStates[upstream],
                      failed.invalidatedFeatureIDs.contains(id) else {
                    throw FeatureEvaluationError.invalidGraph("Blocked state must identify its failed upstream producer.")
                }
            case .evaluated:
                guard document.designGraph.nodes[id]?.isSuppressed == false else {
                    throw FeatureEvaluationError.invalidGraph("A suppressed feature cannot have an evaluated state.")
                }
            case .suppressed:
                guard document.designGraph.nodes[id]?.isSuppressed == true else {
                    throw FeatureEvaluationError.invalidGraph("An active feature cannot have a suppressed state.")
                }
            case .unevaluated: break
            }
        }
        switch (evaluatedDocument, failure) {
        case let (.some(evaluatedDocument), .none):
            try evaluatedDocument.validate()
            guard document == evaluatedDocument.document, isComplete else {
                throw FeatureEvaluationError.invalidGraph(
                    "A successful evaluation report must describe its complete evaluated document."
                )
            }
        case (.none, .some):
            guard isComplete == false else {
                throw FeatureEvaluationError.invalidGraph(
                    "A failed evaluation report cannot be complete."
                )
            }
        case (.some, .some), (.none, .none):
            throw FeatureEvaluationError.invalidGraph(
                "An evaluation report must contain exactly one evaluated document or failure."
            )
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case document
        case evaluatedDocument
        case featureStates
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.document, .evaluatedDocument, .featureStates, .failure],
            in: decoder
        )
        self.init(
            document: try container.decode(CADDocument.self, forKey: .document),
            evaluatedDocument: try container.decode(
                Optional<EvaluatedDocument>.self,
                forKey: .evaluatedDocument
            ),
            featureStates: try container.decode(
                [FeatureID: FeatureEvaluationState].self,
                forKey: .featureStates
            ),
            failure: try container.decode(
                Optional<EvaluationFailure>.self,
                forKey: .failure
            )
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(document, forKey: .document)
        try container.encode(evaluatedDocument, forKey: .evaluatedDocument)
        try container.encode(featureStates, forKey: .featureStates)
        try container.encode(failure, forKey: .failure)
    }
#endif
}

public struct EvaluationFailure: Sendable, Hashable {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public func validate() throws {
        guard !message.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Evaluation failure message must not be empty.")
        }
    }
}

#if !hasFeature(Embedded)
extension EvaluationReport: Codable {}
extension EvaluationFailure: Codable {}
#endif
