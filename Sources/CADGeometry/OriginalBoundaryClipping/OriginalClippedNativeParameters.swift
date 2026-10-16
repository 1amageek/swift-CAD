import CADCore

/// Complete parameter clipping and original raw-cell correspondence; no image-stratum claim.
public final class OriginalClippedNativeParameters: Sendable {
    fileprivate final class Identity: Sendable {}
    public struct CellIdentifier: Equatable, Sendable {
        fileprivate let owner: Identity
        public let ordinal: Int
        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.owner === rhs.owner && lhs.ordinal == rhs.ordinal }
    }
    public enum RawCellIdentifier: Sendable {
        case curveSurface(OriginalNativeCurveSurfaceRelation.CellIdentifier)
        case surfaceSurface(OriginalNativeSurfaceSurfaceRelations.CellIdentifier)
    }
    public struct Cell: Sendable {
        public let identifier: CellIdentifier
        public let originalRawCell: RawCellIdentifier
        public let dimension: Int
        public let admissionDepth: Int
        public let coefficientAdmissionDepth: Int
        public let sample: [OriginalAlgebraicCoordinate]
        public let boundarySpans: [OriginalNativeBoundaryDomain.SpanReference]
    }
    public struct Component: Sendable {
        public let cellIdentifiers: [CellIdentifier]
        public let dimension: Int
    }
    public struct Attachment: Sendable {
        public let source: CellIdentifier
        public let target: CellIdentifier
        public let closureOrdinal: Int
        public let refinedTargetOrdinal: Int
        public let refinedTargetDimension: Int
    }
    public let attachments: [Attachment]
    public let boundary: OriginalNativeBoundaryDomain
    public let selection: OriginalNativeBoundaryDomain.Selection
    public let cells: [Cell]
    public let components: [Component]
    private let identity: Identity
    private let relation: OriginalRealRelation
    private let baseline: OriginalBoundaryAdmission

    init<A: ExactScalarAdmission & ~Copyable>(boundary: OriginalNativeBoundaryDomain, selection: OriginalNativeBoundaryDomain.Selection,
        relation: OriginalRealRelation, source: OriginalBoundarySourceCover, rawNodes: [Int],
        compiler: OriginalBoundaryBooleanCompiler, baseline: OriginalBoundaryAdmission,
        usage: inout A) throws {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(2, of: UInt.self, usage: &usage)
        let identity = Identity()
        try RationalAlgebraStorage.retain(relation.cells.count, of: Cell.self, usage: &usage)
        var cells: [Cell] = []; cells.reserveCapacity(relation.cells.count)
        for (ordinal, cell) in relation.cells.enumerated() {
            try intersectionAlgebraStep(&usage)
            let values = try compiler.values(signs: cell.sourceSigns, usage: &usage)
            var rawOwner: Int?
            for index in rawNodes.indices {
                try intersectionAlgebraStep(&usage)
                if values[rawNodes[index]] {
                    guard rawOwner == nil else { throw rationalAlgebraFailure("A refined boundary cell has multiple original raw owners.") }
                    rawOwner = index
                }
            }
            guard let rawOwner else { throw rationalAlgebraFailure("A refined boundary cell omitted its original raw owner.") }
            let raw: RawCellIdentifier
            switch source.identifiers[rawOwner] {
            case .curveSurface(let identifier): raw = .curveSurface(identifier)
            case .surfaceSurface(let identifier): raw = .surfaceSurface(identifier)
            }
            var spans: [OriginalNativeBoundaryDomain.SpanReference] = []
            for index in compiler.boundaryNodes.indices {
                try intersectionAlgebraStep(&usage)
                if values[compiler.boundaryNodes[index]] {
                    try RationalAlgebraStorage.retain(1, of: OriginalNativeBoundaryDomain.SpanReference.self, usage: &usage)
                    spans.append(compiler.references[index])
                }
            }
            try RationalAlgebraStorage.retain(cell.sample.count, of: OriginalAlgebraicCoordinate.self, usage: &usage)
            var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(cell.sample.count)
            for value in cell.sample {
                try intersectionAlgebraStep(&usage)
                sample.append(.init(original: value.original,
                    inheritedDepth: try rationalAlgebraCount(baseline.parameterDepth, value.inheritedDepth),
                    inheritedCoefficientDepth: try rationalAlgebraCount(baseline.coefficientDepth, value.inheritedCoefficientDepth)))
            }
            cells.append(.init(identifier: .init(owner: identity, ordinal: ordinal), originalRawCell: raw,
                dimension: cell.dimension, admissionDepth: try rationalAlgebraCount(baseline.parameterDepth, cell.admissionDepth),
                coefficientAdmissionDepth: try rationalAlgebraCount(baseline.coefficientDepth, cell.coefficientAdmissionDepth),
                sample: sample, boundarySpans: spans))
        }
        try RationalAlgebraStorage.retain(relation.components.count, of: Component.self, usage: &usage)
        var components: [Component] = []; components.reserveCapacity(relation.components.count)
        func matchingCell(_ predicate: (OriginalRealRelation.Cell) -> Bool) throws -> Int? {
            for (index, cell) in relation.cells.enumerated() {
                try intersectionAlgebraStep(&usage)
                if predicate(cell) { return index }
            }
            return nil
        }
        for component in relation.components {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(component.cellIdentifiers.count, of: CellIdentifier.self, usage: &usage)
            var identifiers: [CellIdentifier] = []; identifiers.reserveCapacity(component.cellIdentifiers.count)
            for original in component.cellIdentifiers {
                try intersectionAlgebraStep(&usage)
                guard let ordinal = try matchingCell({ $0.identifier == original }) else {
                    throw rationalAlgebraFailure("Boundary component lost its complete selected cell owner.")
                }
                identifiers.append(.init(owner: identity, ordinal: ordinal))
            }
            components.append(.init(cellIdentifiers: identifiers, dimension: component.dimension))
        }
        try RationalAlgebraStorage.retain(relation.incidence.attachments.count, of: Attachment.self, usage: &usage)
        var attachments: [Attachment] = []; attachments.reserveCapacity(relation.incidence.attachments.count)
        for link in relation.incidence.attachments {
            try intersectionAlgebraStep(&usage)
            guard let from = try matchingCell({ $0.identifier.ordinal == link.sourceCellIndex }),
                let to = try matchingCell({ $0.identifier.ordinal == link.targetCellIndex }) else {
                throw rationalAlgebraFailure("Boundary incidence lost its complete selected cell owners.")
            }
            let dimension = relation.incidence.closures[link.closureIndex].freePartition.cells[link.refinedTargetCellIndex].dimension
            attachments.append(.init(source: .init(owner: identity, ordinal: from), target: .init(owner: identity, ordinal: to),
                closureOrdinal: link.closureIndex, refinedTargetOrdinal: link.refinedTargetCellIndex,
                refinedTargetDimension: dimension))
        }
        let bytes = 2 * MemoryLayout<UInt>.stride + MemoryLayout<OriginalNativeBoundaryDomain>.stride
            + MemoryLayout<OriginalNativeBoundaryDomain.Selection>.stride + MemoryLayout<[Cell]>.stride
            + MemoryLayout<[Component]>.stride + MemoryLayout<[Attachment]>.stride + MemoryLayout<Identity>.stride
            + MemoryLayout<OriginalRealRelation>.stride + MemoryLayout<OriginalBoundaryAdmission>.stride
        try RationalAlgebraStorage.retainBytes(bytes, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.boundary = boundary; self.selection = selection; self.relation = relation; self.baseline = baseline
        self.identity = identity; self.cells = cells; self.components = components; self.attachments = attachments
    }
    public func contains(rationalParameters: [ExactRationalCoefficient], inCell identifier: CellIdentifier? = nil,
        maximumDepth: Int, maximumCoefficientDepth: Int, using original: inout OriginalQueryExecution) throws -> Bool {
        try intersectionAlgebraStep(&original)
        if let identifier {
            guard identifier.owner === identity, relation.cells.indices.contains(identifier.ordinal) else {
                throw GeometryConversionError.invalidInput("Boundary membership has a foreign parameter cell owner.")
            }
        }
        let value = try baseline.withScope(maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &original) { admission in
            try relation.contains(rationalPoint: rationalParameters,
                inCell: identifier.map { relation.cells[$0.ordinal].identifier },
                maximumDepth: maximumDepth - baseline.parameterDepth,
                maximumCoefficientDepth: maximumCoefficientDepth - baseline.coefficientDepth, usage: &admission)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return value
    }
}
