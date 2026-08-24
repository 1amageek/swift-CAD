public struct PolySplineMeshAnalysisResult: Codable, Sendable, Hashable {
    public enum PatchCandidateKind: String, Codable, Sendable, Hashable {
        case singleQuad
        case quadPatchGraph
    }

    public struct Diagnostic: Codable, Sendable, Hashable {
        public enum Severity: String, Codable, Sendable, Hashable {
            case info
            case warning
            case error
        }

        public enum Code: String, Codable, Sendable, Hashable {
            case invalidMesh
            @available(*, deprecated, message: "Rounded corner reconstruction is supported; this case is retained for decoding older analysis results.")
            case unsupportedRoundedCorners
            case unsupportedPatchNetwork
            case nonManifoldEdges
            case inconsistentBoundaryWinding
            case degenerateBoundary
            case singleQuadPatchSupported
            case patchGraphIdentified
            case patchGraphPartitioned
            case patchAdjacencyIdentified
            @available(*, deprecated, message: "Exact reconstruction failures use unsupportedPatchNetwork; this case is retained for decoding older analysis results.")
            case patchTangentPlaneDiscontinuity
            @available(*, deprecated, message: "Exact reconstruction failures use unsupportedPatchNetwork; this case is retained for decoding older analysis results.")
            case patchCurvatureContinuityUnresolved
            @available(*, deprecated, message: "Use bicubicPatchNetworkSupported; this case is retained for decoding older analysis results.")
            case planarPatchNetworkSupported
            case bicubicPatchNetworkSupported
            case incompletePatchPartition
            @available(*, deprecated, message: "Partitioning uses deterministic polynomial-time matching; this case is retained for decoding older analysis results.")
            case oversizedPatchPartitionSearch
            case mergePatchesHasNoEffect
        }

        public var severity: Severity
        public var code: Code
        public var message: String
        public var vertexIndices: [Int]
        public var triangleIndices: [Int]

        public init(
            severity: Severity,
            code: Code,
            message: String,
            vertexIndices: [Int] = [],
            triangleIndices: [Int] = []
        ) {
            self.severity = severity
            self.code = code
            self.message = message
            self.vertexIndices = vertexIndices
            self.triangleIndices = triangleIndices
        }
    }

    public var vertexCount: Int
    public var usedVertexCount: Int
    public var triangleCount: Int
    public var indexedElementCount: Int
    public var boundaryEdgeCount: Int
    public var internalEdgeCount: Int
    public var nonManifoldEdgeCount: Int
    public var connectedComponentCount: Int
    public var supportedPatchCount: Int
    public var candidatePatchCount: Int
    public var candidateKind: PatchCandidateKind?
    public var patchGraph: PolySplinePatchGraph?
    public var isSupported: Bool
    public var diagnostics: [Diagnostic]

    public init(
        vertexCount: Int = 0,
        usedVertexCount: Int = 0,
        triangleCount: Int = 0,
        indexedElementCount: Int = 0,
        boundaryEdgeCount: Int = 0,
        internalEdgeCount: Int = 0,
        nonManifoldEdgeCount: Int = 0,
        connectedComponentCount: Int = 0,
        supportedPatchCount: Int = 0,
        candidatePatchCount: Int = 0,
        candidateKind: PatchCandidateKind? = nil,
        patchGraph: PolySplinePatchGraph? = nil,
        isSupported: Bool = false,
        diagnostics: [Diagnostic] = []
    ) {
        self.vertexCount = vertexCount
        self.usedVertexCount = usedVertexCount
        self.triangleCount = triangleCount
        self.indexedElementCount = indexedElementCount
        self.boundaryEdgeCount = boundaryEdgeCount
        self.internalEdgeCount = internalEdgeCount
        self.nonManifoldEdgeCount = nonManifoldEdgeCount
        self.connectedComponentCount = connectedComponentCount
        self.supportedPatchCount = supportedPatchCount
        self.candidatePatchCount = candidatePatchCount
        self.candidateKind = candidateKind
        self.patchGraph = patchGraph
        self.isSupported = isSupported
        self.diagnostics = diagnostics
    }

    public var errors: [Diagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    public var failureMessage: String? {
        let messages = errors.map(\.message)
        guard !messages.isEmpty else {
            return nil
        }
        return messages.joined(separator: " ")
    }
}
