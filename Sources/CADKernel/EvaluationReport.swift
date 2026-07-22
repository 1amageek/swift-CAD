import CADCore
import CADIR

public struct EvaluationReport: Codable, Sendable {
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
        evaluatedDocument != nil && featureStates.values.allSatisfy { state in
            switch state {
            case .evaluated, .suppressed:
                true
            case .unevaluated, .blocked, .failed:
                false
            }
        }
    }

    public func validate() throws {
        if let failure {
            try failure.validate()
        }
        for state in featureStates.values {
            if case let .failed(featureFailure) = state {
                try featureFailure.validate()
            }
        }
        switch (evaluatedDocument, failure) {
        case let (.some(evaluatedDocument), .none):
            try evaluatedDocument.validate()
            let tolerance = evaluatedDocument.configuration.tolerance
            let reportFingerprint = try document.sourceFingerprint(tolerance: tolerance)
            let evaluatedFingerprint = try evaluatedDocument.document.sourceFingerprint(
                tolerance: tolerance
            )
            guard reportFingerprint == evaluatedFingerprint, isComplete else {
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
}

public struct EvaluationFailure: Codable, Sendable, Hashable {
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
