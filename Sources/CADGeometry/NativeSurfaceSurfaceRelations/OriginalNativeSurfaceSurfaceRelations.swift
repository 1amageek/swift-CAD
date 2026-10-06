import CADCore

/// Immutable complete original UV relation, independent of a numerical curve representation.
public final class OriginalNativeSurfaceSurfaceRelations: Sendable {
    public struct CellIdentifier: Equatable, Sendable {
        fileprivate let owner: OriginalNativeSurfaceSurfaceRelations
        public let ordinal: Int
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.owner === rhs.owner && lhs.ordinal == rhs.ordinal
        }
    }
    public struct ComponentIdentifier: Equatable, Sendable {
        fileprivate let owner: OriginalNativeSurfaceSurfaceRelations
        public let ordinal: Int
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.owner === rhs.owner && lhs.ordinal == rhs.ordinal
        }
    }
    public struct Cell: Sendable {
        public let identifier: CellIdentifier
        public let parameterDimension: Int
        public let originalJacobianRank: Int
        /// Every original tuple sample is a witness, never a completeness approximation.
        public let parameterSample: [OriginalAlgebraicCoordinate]
        public let imageStrata: [ImageStratum]
    }
    public struct ImageStratum: Sendable {
        public let ordinal: Int
        public let parameterDimension: Int
        public let imageDimension: Int
        public let fiberDimension: Int
        /// Original order is XYZ,u1,v1,u2,v2 on the retained rational graph.
        public let sample: [OriginalAlgebraicCoordinate]
    }
    public struct Component: Sendable {
        public let identifier: ComponentIdentifier
        public let cellOrdinals: [Int]
        public let parameterDimension: Int
        public let imageDimension: Int
        public let attachmentOrdinals: [Int]
    }
    public struct Attachment: Sendable {
        public let source: CellIdentifier
        public let target: CellIdentifier
        public let closureOrdinal: Int
        public let refinedTargetOrdinal: Int
        public let refinedTargetDimension: Int
    }

    public let firstSurface: BSplineSurface3D
    public let secondSurface: BSplineSurface3D
    public let certificationTolerance: ModelingTolerance
    public var nativeDomains: [OriginalRationalParameterDomain] { decomposition.nativeDomains }
    public var requestedDomains: [OriginalRationalParameterDomain] { decomposition.requestedDomains }
    public var effectiveDomains: [OriginalRationalParameterDomain]? { decomposition.effectiveDomains }
    public var hasPositiveDimensionalParameters: Bool { dimensions.contains { $0 > 0 } }
    package let decomposition: OriginalRationalIntersectionDecomposition
    package let graph: OriginalRationalIntersectionCells?
    package let graphIdeal: ExactIntersectionIdeal?
    private let inheritedParameterDepth: Int
    private let parentRelation: OriginalNativeSurfaceSurfaceRelations?
    private let conditions: [OriginalIntersectionCellCondition]
    private let indices: [Int]
    private let dimensions: [Int]
    private let ranks: [Int]
    private let samples: [[OriginalAlgebraicCoordinate]]
    private let images: [[ImageStratum]]
    private let componentCells: [[Int]]
    private let componentAttachments: [[Int]]
    private let retainedAttachments: [OriginalRationalIntersectionIncidence.Attachment]
    private let attachmentDimensions: [Int]

    package init<B: RationalAlgebraAdmitting>(first: BSplineSurface3D, second: BSplineSurface3D,
        tolerance: ModelingTolerance, decomposition: OriginalRationalIntersectionDecomposition,
        graph: OriginalRationalIntersectionCells?, graphIdeal: ExactIntersectionIdeal? = nil, conditions: [OriginalIntersectionCellCondition],
        images: [[ImageStratum]], inheritedParameterDepth: Int = 0,
        parentRelation: OriginalNativeSurfaceSurfaceRelations? = nil, usage: inout B) throws {
        guard decomposition.system.variableCount == 4,
            decomposition.system.firstSurfaceSource.source == first,
            decomposition.system.secondSurfaceSource?.source == second else {
            throw rationalAlgebraFailure("Native SSI receipt requires both unchanged original source laws.")
        }
        self.firstSurface = first; self.secondSurface = second; certificationTolerance = tolerance
        self.inheritedParameterDepth = inheritedParameterDepth; self.parentRelation = parentRelation
        self.decomposition = decomposition; self.graph = graph; self.graphIdeal = graphIdeal; self.conditions = conditions; self.images = images
        var indices: [Int] = [], dimensions: [Int] = [], ranks: [Int] = []
        var samples: [[OriginalAlgebraicCoordinate]] = [], componentCells: [[Int]] = []
        var componentAttachments: [[Int]] = [], attachments: [OriginalRationalIntersectionIncidence.Attachment] = []
        var attachmentDimensions: [Int] = []
        if case .parameterCells(let strata, let incidence, let components) = decomposition.coverage {
            let count = strata.partition.solutionCells.count
            guard conditions.count == count, images.count == count, (graph == nil) == (graphIdeal == nil) else {
                throw rationalAlgebraFailure("Native SSI relation publication omitted an original selected cell.")
            }
            try RationalAlgebraStorage.retain(try rationalAlgebraCount(count, 3, multiply: true), of: Int.self, usage: &usage)
            try RationalAlgebraStorage.retain(count, of: [OriginalAlgebraicCoordinate].self, usage: &usage)
            indices.reserveCapacity(count); dimensions.reserveCapacity(count); ranks.reserveCapacity(count); samples.reserveCapacity(count)
            for ordinal in 0..<count {
                try intersectionAlgebraStep(&usage)
                let index = strata.partition.solutionCells[ordinal], cell = strata.partition.cells[index]
                guard conditions[ordinal].cellIndex == index, !images[ordinal].isEmpty,
                    strata.strata[ordinal].cellIndex == index else {
                    throw rationalAlgebraFailure("Native SSI image strata lost their original cell binding.")
                }
                indices.append(index); dimensions.append(cell.dimension); ranks.append(strata.strata[ordinal].originalJacobianRank)
                try RationalAlgebraStorage.retain(4, of: OriginalAlgebraicCoordinate.self, usage: &usage)
                var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(4)
                for value in cell.coordinates {
                    sample.append(.init(original: value, inheritedDepth: try rationalAlgebraCount(inheritedParameterDepth, cell.admissionDepth),
                        inheritedCoefficientDepth: cell.coefficientAdmissionDepth))
                }
                samples.append(sample)
            }
            try RationalAlgebraStorage.retain(try rationalAlgebraCount(components.components.count, 2, multiply: true), of: [Int].self, usage: &usage)
            componentCells.reserveCapacity(components.components.count); componentAttachments.reserveCapacity(components.components.count)
            for component in components.components {
                try RationalAlgebraStorage.retain(component.cellIndexes.count, of: Int.self, usage: &usage)
                var ordinals: [Int] = []; ordinals.reserveCapacity(component.cellIndexes.count)
                for index in component.cellIndexes {
                    try usage.consumeExactWork(count)
                    guard let ordinal = indices.firstIndex(of: index) else {
                        throw rationalAlgebraFailure("Native SSI component contains a foreign original cell.")
                    }
                    ordinals.append(ordinal)
                }
                componentCells.append(ordinals); componentAttachments.append(component.attachmentIndexes)
            }
            attachments = incidence.attachments
            try RationalAlgebraStorage.retain(attachments.count, of: Int.self, usage: &usage)
            attachmentDimensions.reserveCapacity(attachments.count)
            for attachment in attachments {
                try intersectionAlgebraStep(&usage)
                attachmentDimensions.append(incidence.closures[attachment.closureIndex]
                    .freePartition.cells[attachment.refinedTargetCellIndex].dimension)
            }
        } else {
            guard conditions.isEmpty, images.isEmpty, graph == nil, graphIdeal == nil else {
                throw rationalAlgebraFailure("Excluded original products cannot publish graph cells.")
            }
        }
        self.indices = indices; self.dimensions = dimensions; self.ranks = ranks; self.samples = samples
        self.componentCells = componentCells; self.componentAttachments = componentAttachments
        retainedAttachments = attachments; self.attachmentDimensions = attachmentDimensions
    }

    public var cellCount: Int { indices.count }
    public var componentCount: Int { componentCells.count }
    public var attachmentCount: Int { retainedAttachments.count }

    public func cell(at ordinal: Int) throws -> Cell {
        guard indices.indices.contains(ordinal) else { throw invalid("Native SSI cell is outside its owning receipt.") }
        return .init(identifier: .init(owner: self, ordinal: ordinal), parameterDimension: dimensions[ordinal],
            originalJacobianRank: ranks[ordinal], parameterSample: samples[ordinal], imageStrata: images[ordinal])
    }

    public func component(at ordinal: Int) throws -> Component {
        guard componentCells.indices.contains(ordinal) else { throw invalid("Native SSI component is outside its owning receipt.") }
        var dimension = 0, imageDimension = 0
        for index in componentCells[ordinal] {
            dimension = max(dimension, dimensions[index])
            for image in images[index] { imageDimension = max(imageDimension, image.imageDimension) }
        }
        return .init(identifier: .init(owner: self, ordinal: ordinal), cellOrdinals: componentCells[ordinal],
            parameterDimension: dimension, imageDimension: imageDimension, attachmentOrdinals: componentAttachments[ordinal])
    }

    public func attachment(at ordinal: Int) throws -> Attachment {
        guard retainedAttachments.indices.contains(ordinal) else { throw invalid("Native SSI attachment is outside its owning receipt.") }
        let proof = retainedAttachments[ordinal]
        guard let source = indices.firstIndex(of: proof.sourceCellIndex), let target = indices.firstIndex(of: proof.targetCellIndex) else {
            throw invalid("Native SSI attachment lost its retained original cell.")
        }
        return .init(source: .init(owner: self, ordinal: source), target: .init(owner: self, ordinal: target),
            closureOrdinal: proof.closureIndex, refinedTargetOrdinal: proof.refinedTargetCellIndex,
            refinedTargetDimension: attachmentDimensions[ordinal])
    }

    public func contains<B: RationalAlgebraAdmitting>(parameters: [ExactRationalCoefficient],
        inCell identifier: CellIdentifier? = nil, inComponent component: ComponentIdentifier? = nil,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> Bool {
        try intersectionAlgebraStep(&usage)
        guard parameters.count == 4, (0...32).contains(maximumAlgebraicDepth) else {
            throw invalid("Native SSI membership requires four original coordinates and a valid depth.")
        }
        if let identifier { guard identifier.owner === self else { throw invalid("Native SSI membership has a foreign cell owner.") } }
        if let component { guard component.owner === self else { throw invalid("Native SSI membership has a foreign component owner.") } }
        for ordinal in indices.indices where (identifier == nil || identifier?.ordinal == ordinal) &&
            (component == nil || componentCells[component!.ordinal].contains(ordinal)) {
            let depth = try sourceDepth(at: ordinal, maximumDepth: maximumAlgebraicDepth)
            let context = try OriginalSingularFieldContext(usage: &usage)
            try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldElement.self, usage: &usage)
            var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(4)
            for coordinate in parameters {
                values.append(try .constant(coordinate, in: context, maximumDepth: depth, usage: &usage))
            }
            if try conditions[ordinal].contains(context: context, coordinates: values, maximumDepth: depth, usage: &usage) {
                try CurrentTaskCancellationChecker().checkCancellation(); return true
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation(); return false
    }

    /// Membership in one retained image/fiber stratum checks the whole exact graph condition.
    public func contains<B: RationalAlgebraAdmitting>(position: [ExactRationalCoefficient],
        parameters: [ExactRationalCoefficient], inCell identifier: CellIdentifier,
        imageStratumOrdinal: Int, maximumAlgebraicDepth: Int, usage: inout B) throws -> Bool {
        try intersectionAlgebraStep(&usage)
        guard identifier.owner === self, indices.indices.contains(identifier.ordinal), position.count == 3,
            parameters.count == 4, (0...32).contains(maximumAlgebraicDepth) else {
            throw invalid("SSI graph membership requires its owning cell, original XYZ and both UV coordinates.")
        }
        let ordinal = identifier.ordinal
        try usage.consumeExactWork(images[ordinal].count)
        guard images[ordinal].contains(where: { $0.ordinal == imageStratumOrdinal }) else {
            throw invalid("SSI graph membership has a foreign image stratum.")
        }
        let sourceAvailableDepth = try sourceDepth(at: ordinal, maximumDepth: maximumAlgebraicDepth)
        if let graph {
            let cell = graph.cells[imageStratumOrdinal]
            let retained = try rationalAlgebraCount(inheritedParameterDepth, cell.admissionDepth)
            guard retained <= maximumAlgebraicDepth else { throw invalid("SSI graph membership cannot reset retained image depth.") }
            let depth = min(sourceAvailableDepth, maximumAlgebraicDepth - retained)
            let condition = try OriginalIntersectionCellCondition(partition: graph, cellIndex: imageStratumOrdinal, usage: &usage)
            let context = try OriginalSingularFieldContext(usage: &usage)
            try RationalAlgebraStorage.retain(7, of: OriginalSingularFieldElement.self, usage: &usage)
            var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(7)
            for coordinate in position { values.append(try .constant(coordinate,in: context,maximumDepth: depth,usage: &usage)) }
            for coordinate in parameters { values.append(try .constant(coordinate,in: context,maximumDepth: depth,usage: &usage)) }
            let result = try condition.contains(context: context,coordinates: values,maximumDepth: depth,usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return result
        }
        guard try contains(parameters: parameters,inCell: identifier,maximumAlgebraicDepth: maximumAlgebraicDepth,usage: &usage) else { return false }
        let source = decomposition.system.firstSurfaceSource
        let weight = try source.homogeneous[3].evaluated(atU: parameters[0],v: parameters[1],usage: &usage)
        for axis in 0..<3 {
            let coordinate = try source.homogeneous[axis].evaluated(atU: parameters[0],v: parameters[1],usage: &usage)
                .divided(by: weight,usage: &usage)
            if coordinate != position[axis] { try CurrentTaskCancellationChecker().checkCancellation(); return false }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return true
    }

    /// The exact rational station retains every opposite UV preimage and exceptional fiber.
    public func fiber<B: RationalAlgebraAdmitting>(surface: Int, u: ExactRationalCoefficient,
        v: ExactRationalCoefficient, maximumAlgebraicDepth: Int, usage: inout B) throws -> OriginalNativeSurfaceSurfaceRelations {
        try intersectionAlgebraStep(&usage)
        guard (0...1).contains(surface), (0...32).contains(maximumAlgebraicDepth) else {
            throw invalid("Native SSI fiber requires its original surface role and a valid depth.")
        }
        for ordinal in indices.indices { _ = try sourceDepth(at: ordinal, maximumDepth: maximumAlgebraicDepth) }
        try RationalAlgebraStorage.retain(4, of: OriginalRationalParameterDomain.self, usage: &usage)
        var requested = decomposition.requestedDomains
        requested[surface * 2] = try .init(lower: u, upper: u, usage: &usage)
        requested[surface * 2 + 1] = try .init(lower: v, upper: v, usage: &usage)
        // Intersect with the original requested domain before adding the exact station.
        for axis in 0..<4 {
            if let domain = try requested[axis].intersecting(decomposition.requestedDomains[axis], usage: &usage) {
                requested[axis] = domain
            } else {
                throw invalid("Native SSI fiber station is outside the original requested domain.")
            }
        }
        let retainedDepth = try retainedParameterDepth(usage: &usage)
        guard retainedDepth <= maximumAlgebraicDepth else { throw invalid("Native SSI fiber cannot reset retained image depth.") }
        var admission = OriginalSourceScalarAdmission(base: usage, maximumDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: 0, originalParameterDepth: 0, originalCoefficientDepth: 0,
            inheritedParameterDepth: retainedDepth, inheritedCoefficientDepth: 0,
            parameterDepth: retainedDepth, coefficientDepth: 0)
        defer { usage = admission.base }
        let availableDepth = maximumAlgebraicDepth - retainedDepth
        let resolved = try OriginalRationalIntersectionDecomposition.prepare(system: decomposition.system,
            requestedDomains: requested, pruneExcludedPrefixes: true, normalizeDenominatorFactors: true,
            reducePureEvenPowerZeroSets: true, preferIsolatedCells: true,
            maximumDepth: availableDepth, usage: &admission)
        return try NativeSurfaceSurfaceRelationPublisher.publish(first: firstSurface, second: secondSurface,
            tolerance: certificationTolerance, decomposition: resolved, maximumDepth: availableDepth,
            inheritedParameterDepth: retainedDepth, parentRelation: self, usage: &admission)
    }

    package func retainedParameterDepth<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Int {
        var depth = inheritedParameterDepth
        if case .parameterCells(let strata, _, _) = decomposition.coverage {
            for index in strata.partition.solutionCells {
                depth = max(depth, try rationalAlgebraCount(inheritedParameterDepth,
                    strata.partition.cells[index].admissionDepth))
            }
        }
        if let graph {
            for index in graph.solutionCells {
                depth = max(depth, try rationalAlgebraCount(inheritedParameterDepth, graph.cells[index].admissionDepth))
            }
        }
        try usage.consumeExactWork(try rationalAlgebraCount(indices.count, graph?.solutionCells.count ?? 0))
        return depth
    }

    private func sourceDepth(at ordinal: Int, maximumDepth: Int) throws -> Int {
        guard case .parameterCells(let strata, _, _) = decomposition.coverage else {
            throw invalid("An excluded receipt has no source cell.")
        }
        let cell = strata.partition.cells[indices[ordinal]]
        let depth = try rationalAlgebraCount(inheritedParameterDepth, cell.admissionDepth)
        guard depth <= maximumDepth else { throw invalid("Native SSI query cannot reset retained source depth.") }
        return maximumDepth - depth
    }
    private func invalid(_ message: String) -> GeometryConversionError { .invalidInput(message) }
}
