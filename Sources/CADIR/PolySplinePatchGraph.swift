public struct PolySplinePatchGraph: Codable, Sendable, Hashable {
    public struct VertexPair: Codable, Sendable, Hashable {
        public var firstVertexIndex: Int
        public var secondVertexIndex: Int

        public init(
            firstVertexIndex: Int,
            secondVertexIndex: Int
        ) {
            self.firstVertexIndex = min(firstVertexIndex, secondVertexIndex)
            self.secondVertexIndex = max(firstVertexIndex, secondVertexIndex)
        }
    }

    public struct QuadCandidate: Codable, Sendable, Hashable {
        public var id: Int
        public var triangleIndices: [Int]
        public var boundaryVertexIndices: [Int]
        public var boundaryEdges: [VertexPair]
        public var splitEdge: VertexPair

        public init(
            id: Int,
            triangleIndices: [Int],
            boundaryVertexIndices: [Int],
            boundaryEdges: [VertexPair],
            splitEdge: VertexPair
        ) {
            self.id = id
            self.triangleIndices = triangleIndices
            self.boundaryVertexIndices = boundaryVertexIndices
            self.boundaryEdges = boundaryEdges
            self.splitEdge = splitEdge
        }
    }

    public struct Relationship: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable, Hashable {
            case sharesBoundaryEdge
            case competesForTriangle
        }

        public var firstCandidateID: Int
        public var secondCandidateID: Int
        public var kind: Kind
        public var vertexIndices: [Int]
        public var triangleIndices: [Int]

        public init(
            firstCandidateID: Int,
            secondCandidateID: Int,
            kind: Kind,
            vertexIndices: [Int] = [],
            triangleIndices: [Int] = []
        ) {
            self.firstCandidateID = min(firstCandidateID, secondCandidateID)
            self.secondCandidateID = max(firstCandidateID, secondCandidateID)
            self.kind = kind
            self.vertexIndices = vertexIndices.sorted()
            self.triangleIndices = triangleIndices.sorted()
        }
    }

    public struct SelectedAdjacency: Codable, Sendable, Hashable {
        public enum ContinuityLevel: String, Codable, Sendable, Hashable {
            case positional
            case tangentPlane
        }

        public var firstCandidateID: Int
        public var secondCandidateID: Int
        public var sharedEdge: VertexPair
        public var sharedVertexIndices: [Int]
        public var continuityLevel: ContinuityLevel
        public var normalAngleRadians: Double
        public var requiresCurvatureContinuitySolve: Bool

        public init(
            firstCandidateID: Int,
            secondCandidateID: Int,
            sharedEdge: VertexPair,
            sharedVertexIndices: [Int],
            continuityLevel: ContinuityLevel,
            normalAngleRadians: Double,
            requiresCurvatureContinuitySolve: Bool
        ) {
            self.firstCandidateID = min(firstCandidateID, secondCandidateID)
            self.secondCandidateID = max(firstCandidateID, secondCandidateID)
            self.sharedEdge = sharedEdge
            self.sharedVertexIndices = sharedVertexIndices.sorted()
            self.continuityLevel = continuityLevel
            self.normalAngleRadians = normalAngleRadians
            self.requiresCurvatureContinuitySolve = requiresCurvatureContinuitySolve
        }
    }

    public struct Partition: Codable, Sendable, Hashable {
        public var selectedCandidateIDs: [Int]
        public var rejectedCandidateIDs: [Int]
        public var coveredTriangleIndices: [Int]
        public var uncoveredTriangleIndices: [Int]

        public init(
            selectedCandidateIDs: [Int],
            rejectedCandidateIDs: [Int],
            coveredTriangleIndices: [Int],
            uncoveredTriangleIndices: [Int]
        ) {
            self.selectedCandidateIDs = selectedCandidateIDs.sorted()
            self.rejectedCandidateIDs = rejectedCandidateIDs.sorted()
            self.coveredTriangleIndices = coveredTriangleIndices.sorted()
            self.uncoveredTriangleIndices = uncoveredTriangleIndices.sorted()
        }

        public var isComplete: Bool {
            !selectedCandidateIDs.isEmpty && uncoveredTriangleIndices.isEmpty
        }
    }

    public var triangleCount: Int
    public var candidates: [QuadCandidate]
    public var relationships: [Relationship]
    public var selectedAdjacencies: [SelectedAdjacency]
    public var unpairedTriangleIndices: [Int]
    public var ambiguousTriangleIndices: [Int]
    public var partition: Partition?

    public init(
        triangleCount: Int,
        candidates: [QuadCandidate] = [],
        relationships: [Relationship] = [],
        selectedAdjacencies: [SelectedAdjacency] = [],
        unpairedTriangleIndices: [Int] = [],
        ambiguousTriangleIndices: [Int] = [],
        partition: Partition? = nil
    ) {
        self.triangleCount = triangleCount
        self.candidates = candidates
        self.relationships = relationships
        self.selectedAdjacencies = selectedAdjacencies
        self.unpairedTriangleIndices = unpairedTriangleIndices
        self.ambiguousTriangleIndices = ambiguousTriangleIndices
        self.partition = partition
    }
}
