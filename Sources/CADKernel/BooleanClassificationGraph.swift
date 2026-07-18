import CADCore
import CADIR
import CADTopology

public struct BooleanClassificationGraph: Codable, Hashable, Sendable {
    public enum Side: String, Codable, Hashable, Sendable {
        case negative
        case positive
    }

    public struct Sample: Codable, Hashable, Sendable {
        public let facePair: BooleanFacePairCandidate
        public let componentID: BooleanFaceSplitComponentID
        public let sourceFaceID: FaceID
        public let oppositeBodyID: BodyID
        public let side: Side
        public let point: Point3D
        public let classification: SolidPointClassification

        public init(
            facePair: BooleanFacePairCandidate,
            componentID: BooleanFaceSplitComponentID,
            sourceFaceID: FaceID,
            oppositeBodyID: BodyID,
            side: Side,
            point: Point3D,
            classification: SolidPointClassification
        ) {
            self.facePair = facePair
            self.componentID = componentID
            self.sourceFaceID = sourceFaceID
            self.oppositeBodyID = oppositeBodyID
            self.side = side
            self.point = point
            self.classification = classification
        }
    }

    public let samples: [Sample]

    public init(samples: [Sample]) {
        self.samples = samples
    }

    public func validate(
        uvSplitGraph: BooleanUVSplitGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let splitsByPair = Dictionary(
            uniqueKeysWithValues: uvSplitGraph.splits.map { ($0.facePair, $0) }
        )
        guard Set(samples).count == samples.count else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean classification graph contains duplicate samples."
            )
        }
        for sample in samples {
            try sample.point.validate()
            try sample.componentID.validate(tolerance: tolerance)
            guard let split = splitsByPair[sample.facePair],
                  split.components.contains(where: { $0.id == sample.componentID }),
                  model.faces[sample.sourceFaceID] != nil,
                  model.bodies[sample.oppositeBodyID] != nil else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean classification sample references missing topology."
                )
            }
        }
    }
}
