import CADCore

/// Complete source-bound native relation. Samples never stand for whole cells.
public final class OriginalNativeCurveSurfaceRelation: Sendable {
    fileprivate final class Identity: Sendable {}
    public struct CellIdentifier: Equatable, Sendable {
        fileprivate let owner: Identity
        public let ordinal: Int
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.owner === rhs.owner && lhs.ordinal == rhs.ordinal
        }
    }
    public struct Cell: Sendable {
        public let identifier: CellIdentifier
        public let parameterDimension: Int
        public let curveParameterDimension: Int
        public let imageDimension: Int
        public let surfaceParameterFiberDimension: Int
        public let imageFiberDimension: Int
        public let originalJacobianRank: Int
        public let sample: [OriginalAlgebraicCoordinate]
    }
    public struct Attachment: Sendable {
        public let source: CellIdentifier
        public let target: CellIdentifier
        public let closureOrdinal: Int
        public let refinedTargetCellOrdinal: Int
    }
    public struct Projection: Sendable {
        public let lower: OriginalAlgebraicCoordinate
        public let upper: OriginalAlgebraicCoordinate
        public let includesLower: Bool
        public let includesUpper: Bool
        /// Exact original t-prefix cells in cylindrical order.
        public let prefixCellOrdinals: [Int]
    }
    public struct Component: Sendable {
        public let cellIdentifiers: [CellIdentifier]
        public let attachmentOrdinals: [Int]
        public let parameterDimension: Int
        public let imageDimension: Int
        public let curveParameterProjections: [Projection]
    }
    public let curve: BSplineCurve3D
    public let surface: BSplineSurface3D
    public let certificationTolerance: ModelingTolerance
    public let nativeDomains: [OriginalRationalParameterDomain]
    public let requestedDomains: [OriginalRationalParameterDomain]
    public let effectiveDomains: [OriginalRationalParameterDomain]?
    public let cells: [Cell]
    public let attachments: [Attachment]
    public let components: [Component]
    public var hasPositiveDimensionalSolutions: Bool { cells.contains { $0.parameterDimension > 0 } }
    private let identity: Identity
    package let chart: NativeCurveSurfacePointChart

    package init<B: RationalAlgebraAdmitting>(chart: NativeCurveSurfacePointChart,
        curve: BSplineCurve3D, surface: BSplineSurface3D, tolerance: ModelingTolerance,
        maximumCandidateCount: Int, maximumDepth: Int, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        let metadataBytes = 3 * MemoryLayout<UInt>.stride
            + MemoryLayout<BSplineCurve3D>.stride + MemoryLayout<BSplineSurface3D>.stride
            + MemoryLayout<ModelingTolerance>.stride + MemoryLayout<NativeCurveSurfacePointChart>.stride
            + 2 * MemoryLayout<[OriginalRationalParameterDomain]>.stride
            + MemoryLayout<[OriginalRationalParameterDomain]?>.stride
            + MemoryLayout<[Cell]>.stride + MemoryLayout<[Attachment]>.stride + MemoryLayout<[Component]>.stride
        try RationalAlgebraStorage.retainBytes(metadataBytes, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: UInt.self, usage: &usage)
        let owner = Identity()
        identity = owner; self.chart = chart; self.curve = curve; self.surface = surface
        certificationTolerance = tolerance; nativeDomains = chart.decomposition.nativeDomains
        requestedDomains = chart.decomposition.requestedDomains
        effectiveDomains = chart.decomposition.effectiveDomains
        guard case .parameterCells(let strata, let incidence, let connected) = chart.decomposition.coverage else {
            cells = []; attachments = []; components = []; return
        }
        let partition = strata.partition
        guard partition.solutionCells.count <= maximumCandidateCount,
            connected.components.count <= maximumCandidateCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Native relation selected cell or component count exceeds the cumulative result ceiling.")
        }
        let derivativeWeight = try chart.curve.homogeneous[3].differentiated(alongU: true, usage: &usage)
        var constantImage = true
        for axis in 0..<3 {
            let numerator = try chart.curve.homogeneous[axis].differentiated(alongU: true, usage: &usage)
                .multiplied(by: chart.curve.homogeneous[3], usage: &usage)
                .subtracting(chart.curve.homogeneous[axis].multiplied(by: derivativeWeight, usage: &usage), usage: &usage)
            if !numerator.isZero { constantImage = false }
        }
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Cell.self, usage: &usage)
        var published: [Cell] = []; published.reserveCapacity(partition.solutionCells.count)
        for stratum in strata.strata {
            try intersectionAlgebraStep(&usage)
            let index = stratum.cellIndex, original = partition.cells[index]
            let prefix = try Self.prefix(index, in: partition, usage: &usage)
            let tDimension = partition.cells[prefix].dimension
            let imageDimension = constantImage ? 0 : tDimension
            try RationalAlgebraStorage.retain(3, of: OriginalAlgebraicCoordinate.self, usage: &usage)
            var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(3)
            for coordinate in original.coordinates {
                try intersectionAlgebraStep(&usage)
                sample.append(.init(original: coordinate, inheritedDepth: original.admissionDepth,
                    inheritedCoefficientDepth: original.coefficientAdmissionDepth))
            }
            published.append(.init(identifier: .init(owner: owner, ordinal: index),
                parameterDimension: original.dimension, curveParameterDimension: tDimension,
                imageDimension: imageDimension, surfaceParameterFiberDimension: original.dimension - tDimension,
                imageFiberDimension: original.dimension - imageDimension,
                originalJacobianRank: stratum.originalJacobianRank, sample: sample))
        }
        try RationalAlgebraStorage.retain(incidence.attachments.count, of: Attachment.self, usage: &usage)
        var links: [Attachment] = []; links.reserveCapacity(incidence.attachments.count)
        for link in incidence.attachments {
            try intersectionAlgebraStep(&usage)
            links.append(.init(source: .init(owner: owner, ordinal: link.sourceCellIndex),
                target: .init(owner: owner, ordinal: link.targetCellIndex), closureOrdinal: link.closureIndex,
                refinedTargetCellOrdinal: link.refinedTargetCellIndex))
        }
        try RationalAlgebraStorage.retain(connected.components.count, of: Component.self, usage: &usage)
        var groups: [Component] = []; groups.reserveCapacity(connected.components.count)
        for component in connected.components {
            var dimension = 0, imageDimension = 0
            try RationalAlgebraStorage.retain(component.cellIndexes.count, of: CellIdentifier.self, usage: &usage)
            var handles: [CellIdentifier] = []; handles.reserveCapacity(component.cellIndexes.count)
            for index in component.cellIndexes {
                try intersectionAlgebraStep(&usage)
                dimension = max(dimension, partition.cells[index].dimension)
                let prefix = try Self.prefix(index, in: partition, usage: &usage)
                imageDimension = max(imageDimension, constantImage ? 0 : partition.cells[prefix].dimension)
                handles.append(.init(owner: owner, ordinal: index))
            }
            let projections = try Self.projections(component.cellIndexes, in: partition,
                maximumDepth: maximumDepth, usage: &usage)
            groups.append(.init(cellIdentifiers: handles, attachmentOrdinals: component.attachmentIndexes,
                parameterDimension: dimension, imageDimension: imageDimension, curveParameterProjections: projections))
        }
        cells = published; attachments = links; components = groups
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    public func owns(_ identifier: CellIdentifier) -> Bool {
        identifier.owner === identity && cells.contains { $0.identifier.ordinal == identifier.ordinal }
    }

    /// Exact membership in the original requested relation or one whole original cell.
    public func contains(rationalParameters: [ExactRationalCoefficient], inCell identifier: CellIdentifier? = nil,
        maximumDepth: Int, usage: OriginalRelationUsage) throws -> Bool {
        var admission = usage
        try intersectionAlgebraStep(&admission)
        try admission.consumeExactWork(cells.count)
        guard rationalParameters.count == 3, maximumDepth >= 0,
            identifier.map({ owns($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Native relation membership requires its owner and all t/u/v coordinates.")
        }
        guard case .parameterCells(let strata, _, _) = chart.decomposition.coverage else { return false }
        let context = try OriginalSingularFieldContext(usage: &admission)
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &admission)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(3)
        for parameter in rationalParameters {
            values.append(try .constant(parameter, in: context, maximumDepth: maximumDepth, usage: &admission))
        }
        for index in strata.partition.solutionCells where identifier == nil || index == identifier?.ordinal {
            let cell = strata.partition.cells[index]
            guard cell.admissionDepth <= maximumDepth else {
                throw rationalAlgebraFailure("Native membership cannot reset original cell depth.")
            }
            let condition = try OriginalIntersectionCellCondition(partition: strata.partition,
                cellIndex: index, usage: &admission)
            if try condition.contains(context: context, coordinates: values,
                maximumDepth: maximumDepth - cell.admissionDepth, usage: &admission) { return true }
        }
        return false
    }

    private static func prefix<B: RationalAlgebraAdmitting>(_ index: Int,
        in partition: OriginalRationalIntersectionCells, usage: inout B) throws -> Int {
        var current = index
        while true {
            try intersectionAlgebraStep(&usage)
            let stack = partition.stacks[partition.cells[current].stackIndex]
            if stack.axis == 0 { return current }
            guard let parent = stack.parentCell else { throw rationalAlgebraFailure("Native relation lost its t-prefix.") }
            current = parent
        }
    }

    private static func projections<B: RationalAlgebraAdmitting>(_ indexes: [Int],
        in partition: OriginalRationalIntersectionCells, maximumDepth: Int, usage: inout B) throws -> [Projection] {
        guard let first = indexes.first else { return [] }
        let prefix = try Self.prefix(first, in: partition, usage: &usage)
        let stack = partition.stacks[partition.cells[prefix].stackIndex]
        try RationalAlgebraStorage.retain(stack.children.count, of: Bool.self, usage: &usage)
        var selected = Array(repeating: false, count: stack.children.count)
        for index in indexes {
            let p = try Self.prefix(index, in: partition, usage: &usage)
            for (ordinal, child) in stack.children.enumerated() {
                try intersectionAlgebraStep(&usage)
                if child == p { selected[ordinal] = true; break }
            }
        }
        func endpoint(_ index: Int, lower: Bool) throws -> (OriginalAlgebraicCoordinate, Bool) {
            let cell = partition.cells[index]
            let value: OriginalSingularFieldElement, included: Bool
            switch cell.kind {
            case .section:
                value = cell.coordinates[0]; included = true
            case .sector(let a, let b):
                guard let ordinal = lower ? a : b else {
                    throw rationalAlgebraFailure("Finite native projection has an unbounded original end.")
                }
                value = try stack.roots[ordinal].value(maximumDepth: maximumDepth, usage: &usage); included = false
            }
            return (.init(original: value, inheritedDepth: cell.admissionDepth,
                inheritedCoefficientDepth: cell.coefficientAdmissionDepth), included)
        }
        try RationalAlgebraStorage.retain(stack.children.count, of: Projection.self, usage: &usage)
        var result: [Projection] = []; result.reserveCapacity(stack.children.count)
        var start = 0
        while start < selected.count {
            try intersectionAlgebraStep(&usage)
            guard selected[start] else { start += 1; continue }
            var end = start
            while end + 1 < selected.count && selected[end + 1] { try intersectionAlgebraStep(&usage); end += 1 }
            let low = try endpoint(stack.children[start], lower: true)
            let high = try endpoint(stack.children[end], lower: false)
            try RationalAlgebraStorage.retain(end - start + 1, of: Int.self, usage: &usage)
            let prefixes = Array(stack.children[start...end])
            result.append(.init(lower: low.0, upper: high.0, includesLower: low.1,
                includesUpper: high.1, prefixCellOrdinals: prefixes))
            start = end + 1
        }
        return result
    }
}
