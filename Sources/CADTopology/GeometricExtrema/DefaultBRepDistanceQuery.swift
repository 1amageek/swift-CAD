import HashTreeCollections
import CADCore
import CADGeometry

public struct DefaultBRepDistanceQuery: BRepDistanceQuerying {
    private final class Domain: Sendable {
        private struct Payload {
            let support: BRepDistanceSelection
            let curve: Curve3D?
            let surface: Surface3D?
            let point: Point3D?
            let intervals: [ScalarInterval]
            let trimPredicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)]
            let boundaryBoxes: [SurfaceParameterCurveEnclosure]
            let preparedSurface: PreparedSurfaceDifferentialEncloser?
            let preparedCurve: PreparedCurveDifferentialEncloser?
            let depth: Int
        }
        let support: BRepDistanceSelection
        let curve: Curve3D?
        let surface: Surface3D?
        let point: Point3D?
        let intervals: [ScalarInterval]
        let trimPredicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)]
        let boundaryBoxes: [SurfaceParameterCurveEnclosure]
        let preparedSurface: PreparedSurfaceDifferentialEncloser?
        let preparedCurve: PreparedCurveDifferentialEncloser?
        let depth: Int

        private init(support: BRepDistanceSelection, curve: Curve3D?, surface: Surface3D?,
            point: Point3D?, intervals: [ScalarInterval],
            trimPredicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)],
            boundaryBoxes: [SurfaceParameterCurveEnclosure],
            preparedSurface: PreparedSurfaceDifferentialEncloser?,
            preparedCurve: PreparedCurveDifferentialEncloser?, depth: Int) {
            self.support = support; self.curve = curve; self.surface = surface; self.point = point
            self.intervals = intervals; self.trimPredicates = trimPredicates
            self.boundaryBoxes = boundaryBoxes; self.preparedSurface = preparedSurface
            self.preparedCurve = preparedCurve; self.depth = depth
        }

        static func make(support: BRepDistanceSelection, curve: Curve3D?, surface: Surface3D?,
            point: Point3D?, intervals: [ScalarInterval],
            trimPredicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)],
            boundaryBoxes: [SurfaceParameterCurveEnclosure] = [],
            preparedSurface: PreparedSurfaceDifferentialEncloser? = nil,
            preparedCurve: PreparedCurveDifferentialEncloser? = nil, depth: Int = 0,
            using execution: inout OriginalQueryExecution) throws -> Domain {
            // Swift 6.4 heap headers have two pointer-sized words on every selected target.
            let header = MemoryLayout<UnsafeRawPointer>.stride.multipliedReportingOverflow(by: 2)
            let alignment = MemoryLayout<Payload>.alignment
            let padding = (alignment - header.partialValue % alignment) % alignment
            let alignedHeader = header.partialValue.addingReportingOverflow(padding)
            let bytes = alignedHeader.partialValue.addingReportingOverflow(MemoryLayout<Payload>.stride)
            guard !header.overflow, !alignedHeader.overflow, !bytes.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: nil, message: "Original distance domain allocation byte count overflowed.")
            }
            try DistanceQueryStorage.charge(bytes.partialValue, of: UInt8.self, using: &execution)
            return Domain(support: support, curve: curve, surface: surface, point: point,
                intervals: intervals, trimPredicates: trimPredicates, boundaryBoxes: boundaryBoxes,
                preparedSurface: preparedSurface, preparedCurve: preparedCurve, depth: depth)
        }
    }
    private struct Cell {
        let first: Domain
        let second: Domain
        let depth: Int
        let lower: Double
    }
    public init() {}

    package static func originalExecution(options: BRepDistanceOptions) throws -> OriginalQueryExecution {
        try options.validate()
        return OriginalQueryExecution(
            budget: try OriginalQueryBudget(workLimit: options.maximumWork,
                storageByteLimit: options.maximumCumulativeStorageBytes),
            limits: try .init(maximumValueDepth: options.maximumAlgebraicDepth,
                maximumCoefficientDepth: options.maximumAlgebraicDepth,
                remainingSourceDepth: options.maximumSourceDepth,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth))
    }


    public func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, accuracy: Double, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult {
        try distance(from: first, to: second, in: model,
            options: BRepDistanceOptions(absoluteAccuracy: accuracy), tolerance: tolerance)
    }

    public func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult {
        var execution = try Self.originalExecution(options: options)
        return try distance(from: first, to: second, in: model, options: options,
            tolerance: tolerance, using: &execution)
    }

    public func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        validatedModel: ValidatedBRepModel, options: BRepDistanceOptions) throws -> BRepDistanceQueryResult {
        var execution = try Self.originalExecution(options: options)
        return try distance(from: first, to: second, validatedModel: validatedModel,
            options: options, using: &execution)
    }

    package func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        validatedModel: ValidatedBRepModel, options: BRepDistanceOptions,
        using execution: inout OriginalQueryExecution) throws -> BRepDistanceQueryResult {
        try options.validate()
        let request = try execution.makeContributionHandle(workLimit: options.maximumWork,
            storageByteLimit: options.maximumCumulativeStorageBytes,
            allocationPolicy: execution.effectiveAllocationPolicy, executionLimits: try .init(maximumValueDepth: options.maximumAlgebraicDepth,
                maximumCoefficientDepth: options.maximumAlgebraicDepth,
                remainingSourceDepth: options.maximumSourceDepth,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth))
        return try execution.withContributionScope(request) { execution in
        guard validatedModel.validationLevel != .modeling else {
            throw failure("Original distance preparation requires an exact model receipt.", validatedModel.tolerance)
        }
        return try evaluate(from: first, to: second, in: validatedModel.model, options: options,
            tolerance: validatedModel.tolerance, using: &execution, validatedModel: validatedModel)
        }
    }

    package func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BRepDistanceQueryResult {
        try options.validate()
        let request = try execution.makeContributionHandle(workLimit: options.maximumWork,
            storageByteLimit: options.maximumCumulativeStorageBytes,
            allocationPolicy: execution.effectiveAllocationPolicy, executionLimits: try .init(maximumValueDepth: options.maximumAlgebraicDepth,
                maximumCoefficientDepth: options.maximumAlgebraicDepth,
                remainingSourceDepth: options.maximumSourceDepth,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth))
        return try execution.withContributionScope(request) { execution in
        try options.validate()
        let validated = try ValidatedBRepModel(model, tolerance: tolerance,
            validationLevel: .exact, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
        return try evaluate(from: first, to: second, in: validated.model, options: options,
            tolerance: validated.tolerance, using: &execution, validatedModel: validated)
        }
    }

    private func evaluate(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution, validatedModel: ValidatedBRepModel) throws -> BRepDistanceQueryResult {
        try tolerance.validate(); try options.validate()
        guard options.absoluteAccuracy.isFinite, options.absoluteAccuracy > 0,
            options.relativeAccuracy.isFinite, options.relativeAccuracy >= 0,
            (1...262_144).contains(options.maximumWork),
            (0...32).contains(options.maximumSubdivisionDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Distance accuracy and caller proof ceilings are invalid.")
        }
        func attained(lower: Double, upper: Double) -> Bool {
            guard lower.isFinite, upper.isFinite, lower <= upper else { return false }
            let width = (OutwardScalarInterval.exact(upper) - .exact(lower)).upper
            let relative = (OutwardScalarInterval.exact(options.relativeAccuracy)
                * .exact(max(0,lower))).lower
            return width.isFinite && width <= max(options.absoluteAccuracy,relative)
        }
        let accuracy = options.absoluteAccuracy
        let firstDomains = try domains(first, model: model, tolerance: tolerance,using: &execution, validatedModel: validatedModel)
        let secondDomains = try domains(second, model: model, tolerance: tolerance,using: &execution, validatedModel: validatedModel)
        var cells: [Cell] = []
        var witnesses: [BRepDistanceWitness] = []
        var upper = Double.infinity

        for a in firstDomains { for b in secondDomains {
            try execution.consumeWork(1)
            let cell = try makeCell(a, b, depth: 0, tolerance: tolerance, using: &execution)
            try push(cell, into: &cells, using: &execution)
            try retainWitnesses(a, b, accuracy: accuracy, upper: &upper, witnesses: &witnesses, tolerance: tolerance, using: &execution)
        } }
        guard !cells.isEmpty else { throw failure("Distance selection has no exact support domains.", tolerance) }
        var globalLower = 0.0
        while !cells.isEmpty {
            try execution.consumeWork(1)
            guard let cell = try popMinimum(from: &cells, using: &execution) else { break }
            globalLower = cell.lower
            if attained(lower: globalLower,upper: upper) { try push(cell, into: &cells, using: &execution); break }
            if cell.lower > upper { continue }
            guard cell.depth < options.maximumSubdivisionDepth else { throw failure("Minimum-distance depth exhausted before a certified distance width was achieved.", tolerance) }
            let aBox = try positionBounds(cell.first, tolerance: tolerance, using: &execution)
            let bBox = try positionBounds(cell.second, tolerance: tolerance, using: &execution)
            let splitFirst = diameter(aBox) >= diameter(bBox) && !cell.first.intervals.isEmpty || cell.second.intervals.isEmpty
            let source = splitFirst ? cell.first : cell.second
            guard let axis = source.intervals.indices.max(by: { source.intervals[$0].width < source.intervals[$1].width }) else {
                throw failure("A point-only distance pair failed finite arithmetic admission.", tolerance)
            }
            let interval = source.intervals[axis], middle = interval.midpoint
            guard middle > interval.lower, middle < interval.upper else { throw failure("Minimum-distance parameter resolution exhausted.", tolerance) }
            try DistanceQueryStorage.charge(2,of: ScalarInterval.self,using: &execution)
            for range in [try ScalarInterval(lower: interval.lower, upper: middle), try ScalarInterval(lower: middle, upper: interval.upper)] {
                try execution.consumeWork(1)
                try DistanceQueryStorage.charge(source.intervals.capacity,of: ScalarInterval.self,using: &execution)
                var intervals = source.intervals; intervals[axis] = range
                let child = try Domain.make(support: source.support, curve: source.curve, surface: source.surface,
                    point: source.point, intervals: intervals, trimPredicates: source.trimPredicates, boundaryBoxes: source.boundaryBoxes, preparedSurface: source.preparedSurface, preparedCurve: source.preparedCurve, depth: cell.depth + 1, using: &execution)
                let a = splitFirst ? child : cell.first, b = splitFirst ? cell.second : child
                let next = try makeCell(a, b, depth: cell.depth + 1, tolerance: tolerance, using: &execution)
                try retainWitnesses(a, b, accuracy: accuracy, upper: &upper, witnesses: &witnesses, tolerance: tolerance, using: &execution)
                if next.lower <= upper { try push(next, into: &cells, using: &execution) }
            }
        }
        guard upper.isFinite, !witnesses.isEmpty, attained(lower: globalLower,upper: upper) else {
            throw failure("No trim-admitted closest witness was certified within the requested accuracy.", tolerance)
        }
        var retainedWitnesses: [BRepDistanceWitness] = []
        for witness in witnesses {
            try execution.consumeWork(1)
            guard witness.distance <= upper+accuracy else { continue }
            try DistanceQueryStorage.reserveForAppend(&retainedWitnesses,using: &execution)
            retainedWitnesses.append(witness)
        }
        var regions: [BRepDistanceMinimumRegion] = []
        for cell in cells {
            try execution.consumeWork(1)
            guard cell.lower <= upper+accuracy else { continue }
            try DistanceQueryStorage.reserveForAppend(&regions,using: &execution)
            regions.append(BRepDistanceMinimumRegion(firstSupport: cell.first.support,
                secondSupport: cell.second.support, firstParameterRanges: cell.first.intervals,
                secondParameterRanges: cell.second.intervals, lowerDistanceBound: cell.lower))
        }
        return BRepDistanceQueryResult(lowerBound: max(0,globalLower),upperBound: upper,
            witnesses: retainedWitnesses, minimumRegions: regions,
            requestedOptions: options, consumedWork: execution.activeContributionHandle?.snapshot.work ?? execution.localWork)
    }

    private func push(_ cell: Cell, into cells: inout [Cell], using execution: inout OriginalQueryExecution) throws {
        try DistanceQueryStorage.reserveForAppend(&cells,using: &execution)
        cells.append(cell)
        var child = cells.count - 1
        while child > 0 {
            try execution.consumeWork(1)
            let parent = (child - 1) / 2
            guard cells[child].lower < cells[parent].lower else { break }
            cells.swapAt(child, parent)
            child = parent
        }
    }

    private func popMinimum(from cells: inout [Cell], using execution: inout OriginalQueryExecution) throws -> Cell? {
        guard let first = cells.first else { return nil }
        let last = cells.removeLast()
        guard !cells.isEmpty else { return first }
        cells[0] = last
        var parent = 0
        while parent < cells.count / 2 {
            try execution.consumeWork(1)
            let left = parent * 2 + 1, right = left + 1
            guard left < cells.count else { break }
            let child = right < cells.count && cells[right].lower < cells[left].lower ? right : left
            guard cells[child].lower < cells[parent].lower else { break }
            cells.swapAt(parent, child)
            parent = child
        }
        return first
    }

    private func domains(_ selection: BRepDistanceSelection, model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution, validatedModel: ValidatedBRepModel) throws -> [Domain] {
        try execution.consumeWork(1)
        switch selection {
        case .point(let point):
            try DistanceQueryStorage.charge(1,of: Domain.self,using: &execution)
            try point.validate()
            return [try Domain.make(support: selection, curve: nil, surface: nil, point: point, intervals: [], trimPredicates: [], using: &execution)]
        case .curve(let curve, let start, let end):
            try DistanceQueryStorage.charge(1,of: Domain.self,using: &execution)
            try DistanceQueryStorage.charge(1,of: ScalarInterval.self,using: &execution)
            try curve.validate(tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
            return [try Domain.make(support: selection, curve: curve, surface: nil, point: nil,
                intervals: [try ScalarInterval(lower: min(start, end), upper: max(start, end))], trimPredicates: [],
                preparedCurve: try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution), using: &execution)]
        case .surfaceStation(let surface, let parameter):
            try DistanceQueryStorage.charge(1, of: Domain.self, using: &execution)
            try DistanceQueryStorage.charge(2, of: ScalarInterval.self, using: &execution)
            try surface.validate(tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
            try parameter.validate()
            guard try surface.uDomain.contains(parameter.u, tolerance: tolerance),
                try surface.vDomain.contains(parameter.v, tolerance: tolerance) else {
                throw failure("Original surface station is outside its authored support domain.", tolerance)
            }
            return [try Domain.make(support: selection, curve: nil, surface: surface, point: nil,
                intervals: [try ScalarInterval(lower: parameter.u, upper: parameter.u),
                    try ScalarInterval(lower: parameter.v, upper: parameter.v)], trimPredicates: [],
                preparedSurface: try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution), using: &execution)]
        case .vertex(let id):
            try DistanceQueryStorage.charge(1,of: Domain.self,using: &execution)
            guard let point = model.vertices[id]?.point else { throw TopologyError.missingReference("Missing distance vertex.") }
            return [try Domain.make(support: selection, curve: nil, surface: nil, point: point, intervals: [], trimPredicates: [], using: &execution)]
        case .edge(let id):
            try DistanceQueryStorage.charge(1,of: Domain.self,using: &execution)
            try DistanceQueryStorage.charge(1,of: ScalarInterval.self,using: &execution)
            guard let edge = model.edges[id], let curve = model.geometry.curves[edge.curveID] else { throw TopologyError.missingReference("Missing distance edge curve.") }
            let start: Double, end: Double
            if let trim = edge.trim { start = trim.startParameter; end = trim.endParameter }
            else {
                guard let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { throw TopologyError.invalidEdge(id) }
                start = try curve.parameterProjection(of: a, tolerance: tolerance, using: &execution).parameter
                end = try curve.parameterProjection(of: b, tolerance: tolerance, using: &execution).parameter
            }
            return [try Domain.make(support: selection, curve: curve, surface: nil, point: nil,
                intervals: [try ScalarInterval(lower: min(start, end), upper: max(start, end))], trimPredicates: [],
                preparedCurve: try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution), using: &execution)]
        case .faceRegion(let id, let requested):
            let original = try domains(.face(id), model: model, tolerance: tolerance, using: &execution, validatedModel: validatedModel)
            guard let face = original.first(where: { $0.surface != nil }) else {
                throw failure("A restricted face distance has no original surface domain.", tolerance)
            }
            let lowerU = max(face.intervals[0].lower, requested.u.lower)
            let upperU = min(face.intervals[0].upper, requested.u.upper)
            let lowerV = max(face.intervals[1].lower, requested.v.lower)
            let upperV = min(face.intervals[1].upper, requested.v.upper)
            guard lowerU <= upperU, lowerV <= upperV else {
                throw failure("The original face parameter region is empty.", tolerance)
            }
            try DistanceQueryStorage.charge(1,of: Domain.self,using: &execution)
            try DistanceQueryStorage.charge(2,of: ScalarInterval.self,using: &execution)
            return [try Domain.make(support: selection, curve: nil, surface: face.surface, point: nil,
                intervals: [try ScalarInterval(lower: lowerU, upper: upperU),
                    try ScalarInterval(lower: lowerV, upper: upperV)],
                trimPredicates: face.trimPredicates, boundaryBoxes: face.boundaryBoxes,
                preparedSurface: face.preparedSurface, using: &execution)]
        case .face(let id):
            guard let face = model.faces[id], let surface = model.geometry.surfaces[face.surfaceID] else { throw TopologyError.missingReference("Missing distance face support.") }
            let box = try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth).bounds(for: id, in: model, tolerance: tolerance, using: &execution)
            var predicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)] = []
            var boundaries: [Domain] = []
            var boundaryBoxes: [SurfaceParameterCurveEnclosure] = []
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing distance face loop.") }
                for use in loop.coedges {
                    try execution.consumeWork(1)
                    guard let curve = use.surfaceParameterCurve else { throw failure("A distance face requires every original trim pcurve.", tolerance) }
                    let originalDomains = try domains(.edge(use.edgeID), model: model, tolerance: tolerance,
                        using: &execution, validatedModel: validatedModel)
                    for domain in originalDomains {
                        try execution.consumeWork(1); try DistanceQueryStorage.reserveForAppend(&boundaries, using: &execution)
                        boundaries.append(domain)
                    }
                    let originalBoxes = try CertifiedSurfaceParameterCurveEncloser(
                        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth,
                        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth)
                        .enclosures(for: curve, on: surface, maximumWidth: 0.25, tolerance: tolerance, using: &execution)
                    for box in originalBoxes {
                        try execution.consumeWork(1); try DistanceQueryStorage.reserveForAppend(&boundaryBoxes, using: &execution)
                        boundaryBoxes.append(box)
                    }
                }
                try DistanceQueryStorage.reserveForAppend(&predicates, using: &execution)
                    predicates.append((loop.role, try CertifiedSurfaceParameterLoopPredicate(
                        loopID: loopID, validatedModel: validatedModel,
                        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth,
                        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)))
            }
            try DistanceQueryStorage.charge(1,of: Domain.self,using: &execution)
            try DistanceQueryStorage.charge(2,of: ScalarInterval.self,using: &execution)
            try DistanceQueryStorage.charge(boundaries.count+1,of: Domain.self,using: &execution)
            return [try Domain.make(support: selection, curve: nil, surface: surface, point: nil, intervals: [box.u, box.v], trimPredicates: predicates, boundaryBoxes: boundaryBoxes, preparedSurface: try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution), using: &execution)] + boundaries
        case .body(let id):
            guard let body = model.bodies[id] else { throw TopologyError.missingReference("Missing distance body.") }
            var result: [Domain] = []
            for shellID in body.shellIDs {
                try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Missing distance body shell.") }
                for faceID in shell.faceIDs {
                    try execution.consumeWork(1)
                    let originalDomains = try domains(.face(faceID), model: model, tolerance: tolerance,
                        using: &execution, validatedModel: validatedModel)
                    for domain in originalDomains {
                        try execution.consumeWork(1); try DistanceQueryStorage.reserveForAppend(&result, using: &execution)
                        result.append(domain)
                    }
                }
            }
            return result
        }
    }

    private func positionBounds(_ domain: Domain, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        return try execution.withGeometricDepthOffset(domain.depth) { execution in
        if let point = domain.point { return CoordinateEnclosure3D(x: try ScalarInterval(lower: point.x, upper: point.x), y: try ScalarInterval(lower: point.y, upper: point.y), z: try ScalarInterval(lower: point.z, upper: point.z)) }
        let native: IntervalVector3DBounds
        try execution.admitGeometricDepth(0)
        let remainingDepth = execution.effectiveLimits.maximumSubdivisionDepth - domain.depth
        if domain.curve != nil {
            guard let prepared = domain.preparedCurve else { throw failure("A curve domain has no prepared original position source.", tolerance) }
            native = try prepared.positionBounds(over: domain.intervals[0], tolerance: tolerance,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: remainingDepth, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
        } else {
            guard let prepared = domain.preparedSurface else { throw failure("A surface domain has no prepared original position source.", tolerance) }
            native = try prepared.positionBounds(over: SurfaceParameterBox(u: domain.intervals[0], v: domain.intervals[1]),
                tolerance: tolerance, maximumSpanCount: 262_144, maximumSubdivisionDepth: remainingDepth,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
        }
        return CoordinateEnclosure3D(x: try ScalarInterval(lower: native.x.lower, upper: native.x.upper),
            y: try ScalarInterval(lower: native.y.lower, upper: native.y.upper),
            z: try ScalarInterval(lower: native.z.lower, upper: native.z.upper))
        }
    }

    private func witnessClassification(_ point: Point2D,
        predicate: CertifiedSurfaceParameterLoopPredicate, depth: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> PlanarPointClassification {
        return try execution.withGeometricDepthOffset(depth) { execution in
        try execution.admitGeometricDepth(0)
        if let strict = try predicate.classifyStrictlyOriginal(point, tolerance: tolerance,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth - depth, using: &execution) { return strict }
        return try predicate.classify(point, tolerance: tolerance, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth - depth, using: &execution)
        }
    }

    private func samples(_ domain: Domain, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [(Point3D, [Double])] {
        if let point = domain.point {
            try DistanceQueryStorage.charge(1,of: (Point3D,[Double]).self,using: &execution)
            return [(point, [])]
        }
        func station(_ parameters: [Double]) throws -> Point3D {
            let original = try witnessPositionBounds(domain, parameters: parameters,
                point: .origin, tolerance: tolerance, using: &execution)
            let point = Point3D(x: original.x.midpoint, y: original.y.midpoint, z: original.z.midpoint)
            try point.validate()
            return point
        }
        if domain.curve != nil {
            try DistanceQueryStorage.charge(3,of: Double.self,using: &execution)
            try DistanceQueryStorage.charge(3,of: (Point3D,[Double]).self,using: &execution)
            return try [domain.intervals[0].lower, domain.intervals[0].midpoint, domain.intervals[0].upper].map {
                try execution.consumeWork(1)
                try DistanceQueryStorage.charge(2,of: Double.self,using: &execution)
                return (try station([$0]), [$0])
            }
        }
        guard domain.surface != nil else { throw failure("Distance sampling has no exact support.", tolerance) }
        var result: [(Point3D, [Double])] = []
        try DistanceQueryStorage.charge(3,of: Double.self,using: &execution)
        for u in [domain.intervals[0].lower, domain.intervals[0].midpoint, domain.intervals[0].upper] {
            try DistanceQueryStorage.charge(3,of: Double.self,using: &execution)
            for v in [domain.intervals[1].lower, domain.intervals[1].midpoint, domain.intervals[1].upper] {
                try execution.consumeWork(1)
                var admitted = true
                for (role, predicate) in domain.trimPredicates {
                    let classification = try witnessClassification(Point2D(x: u, y: v), predicate: predicate,
                        depth: domain.depth, tolerance: tolerance, using: &execution)
                    if role == .outer && classification != .inside || role == .inner && classification != .outside { admitted = false; break }
                }
                if admitted {
                    try DistanceQueryStorage.reserveForAppend(&result,using: &execution)
                    try DistanceQueryStorage.charge(4,of: Double.self,using: &execution)
                    result.append((try station([u, v]), [u, v]))
                }
            }
        }
        return result
    }

    private func retainWitnesses(_ a: Domain, _ b: Domain, accuracy: Double, upper: inout Double,
        witnesses: inout [BRepDistanceWitness], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        var first = try samples(a, tolerance: tolerance, using: &execution), second = try samples(b, tolerance: tolerance, using: &execution)
        if !upper.isFinite, let refined = try refinedWitness(a, b, tolerance: tolerance, using: &execution) {
            try DistanceQueryStorage.reserveForAppend(&first,using: &execution)
            try DistanceQueryStorage.reserveForAppend(&second,using: &execution)
            first.append(refined.0); second.append(refined.1)
        }
        try DistanceQueryStorage.charge(first.count,of: CoordinateEnclosure3D.self,using: &execution)
        try DistanceQueryStorage.charge(second.count,of: CoordinateEnclosure3D.self,using: &execution)
        let firstBoxes = try first.map { try witnessPositionBounds(a, parameters: $0.1,
            point: $0.0, tolerance: tolerance, using: &execution) }
        let secondBoxes = try second.map { try witnessPositionBounds(b, parameters: $0.1,
            point: $0.0, tolerance: tolerance, using: &execution) }
        for (firstIndex, x) in first.enumerated() { for (secondIndex, y) in second.enumerated() {
            try execution.consumeWork(1)
            let value = upperDistance(firstBoxes[firstIndex], secondBoxes[secondIndex])
            guard value.isFinite else { throw failure("Minimum-distance witness arithmetic is nonfinite.", tolerance) }
            if value < upper {
                upper = value
                try witnesses.removeAll { witness in
                    try execution.consumeWork(1)
                    return witness.distance > upper+accuracy
                }
            }
            let repeated: Bool
            if value <= upper + accuracy {
                repeated = try witnesses.contains(where: { witness in
                    try originalSupportComparison(witness.firstSupport,a.support,using: &execution)
                        && originalSupportComparison(witness.secondSupport,b.support,using: &execution)
                        && (witness.firstPoint - x.0).length <= accuracy
                        && (witness.secondPoint - y.0).length <= accuracy
                })
            } else { repeated = true }
            if !repeated {
                guard witnesses.count < 262_144 else { throw failure("Minimum-distance witness allowance exhausted.", tolerance) }
                try DistanceQueryStorage.reserveForAppend(&witnesses,using: &execution)
                witnesses.append(.init(firstSupport: a.support, secondSupport: b.support,
                    firstPoint: x.0, secondPoint: y.0, firstParameters: x.1, secondParameters: y.1))
            }
        } }
    }
    private func originalSupportComparison(_ first: BRepDistanceSelection,
        _ second: BRepDistanceSelection,using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        if case .curve(let curve,_,_) = first {
            try GeometryStructuralComparisonWork.charge(curve: curve,
                using: &execution)
        }
        if case .curve(let curve,_,_) = second {
            try GeometryStructuralComparisonWork.charge(curve: curve,
                using: &execution)
        }
        if case .surfaceStation(let surface, _) = first {
            try GeometryStructuralComparisonWork.charge(surface: surface,
                using: &execution)
        }
        if case .surfaceStation(let surface, _) = second {
            try GeometryStructuralComparisonWork.charge(surface: surface,
                using: &execution)
        }
        return first == second
    }

    private func refinedWitness(_ first: Domain, _ second: Domain, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
        -> ((Point3D,[Double]),(Point3D,[Double]))? {
        try DistanceQueryStorage.charge(first.intervals.count+second.intervals.count,of: Double.self,using: &execution)
        var a = first.intervals.map({ $0.midpoint }), b = second.intervals.map({ $0.midpoint })
        func evaluated(_ domain: Domain, _ parameters: [Double]) throws
            -> (point: Point3D, bounds: CoordinateEnclosure3D) {
            if let point = domain.point {
                return (point, try witnessPositionBounds(domain, parameters: parameters,
                    point: point, tolerance: tolerance, using: &execution))
            }
            let original = try witnessPositionBounds(domain, parameters: parameters,
                point: .origin, tolerance: tolerance, using: &execution)
            let point = Point3D(x: original.x.midpoint, y: original.y.midpoint, z: original.z.midpoint)
            try point.validate()
            return (point, original)
        }
        func admitted(_ domain: Domain,_ parameters:[Double]) throws -> Bool {
            guard domain.surface != nil else{return true}
            for (role,predicate) in domain.trimPredicates {
                let classification = try witnessClassification(Point2D(x: parameters[0], y: parameters[1]),
                    predicate: predicate, depth: domain.depth, tolerance: tolerance, using: &execution)
                if role == .outer && classification != .inside || role == .inner && classification != .outside{return false}
            }
            return true
        }
        try execution.consumeWork(1)
        var x = try evaluated(first,a), y = try evaluated(second,b)
        var scale = 0.5
        var currentUpper = upperDistance(x.bounds,y.bounds)
        for _ in 0..<32 {
            try CurrentTaskCancellationChecker().checkCancellation()
            var improved = false
            for side in 0..<2 {
                let domain = side == 0 ? first : second
                for axis in domain.intervals.indices {
                    let interval = domain.intervals[axis]
                    let step = interval.width * scale
                    guard step.isFinite, step > 0 else { continue }
                    for signIndex in 0..<2 {
                        let sign = signIndex == 0 ? -1.0 : 1.0
                        try execution.consumeWork(1)
                        var parameters = side == 0 ? a : b
                        let previous = parameters[axis]
                        try DistanceQueryStorage.charge(parameters.capacity,of: Double.self,using: &execution)
                        parameters[axis] = min(interval.upper,max(interval.lower,previous+sign*step))
                        guard parameters[axis] != previous, try admitted(domain,parameters) else { continue }
                        let candidate = try evaluated(domain,parameters)
                        let candidateUpper = side == 0
                            ? upperDistance(candidate.bounds,y.bounds)
                            : upperDistance(x.bounds,candidate.bounds)
                        if candidateUpper.isFinite, candidateUpper < currentUpper {
                            if side == 0 { a = parameters; x = candidate }
                            else { b = parameters; y = candidate }
                            currentUpper = candidateUpper; improved = true
                        }
                    }
                }
            }
            if !improved { scale *= 0.5 }
            if scale == 0 { break }
        }
        guard try admitted(first,a), try admitted(second,b) else{return nil}
        // Local iteration supplies upper witnesses only; the complete cell-pair
        // interval cover remains the authority for global optimality.
        return ((x.point,a),(y.point,b))
    }
    private func witnessPositionBounds(_ domain: Domain, parameters: [Double], point: Point3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        if domain.point != nil {
            return CoordinateEnclosure3D(x: try ScalarInterval(lower: point.x, upper: point.x),
                y: try ScalarInterval(lower: point.y, upper: point.y),
                z: try ScalarInterval(lower: point.z, upper: point.z))
        }
        try DistanceQueryStorage.charge(parameters.count,of: ScalarInterval.self,using: &execution)
        let ranges = try parameters.map { try ScalarInterval(lower: $0, upper: $0) }
        let station = try Domain.make(support: domain.support, curve: domain.curve, surface: domain.surface,
            point: nil, intervals: ranges, trimPredicates: [], preparedSurface: domain.preparedSurface,
            preparedCurve: domain.preparedCurve, depth: domain.depth, using: &execution)
        return try positionBounds(station, tolerance: tolerance, using: &execution)
    }

    private func upperDistance(_ first: CoordinateEnclosure3D, _ second: CoordinateEnclosure3D) -> Double {
        func magnitude(_ a: ScalarInterval, _ b: ScalarInterval) -> Double {
            if a.lower == a.upper, a.lower == b.lower, b.lower == b.upper { return 0 }
            return max(abs((a.lower-b.upper).nextDown), abs((a.upper-b.lower).nextUp))
        }
        let x = magnitude(first.x, second.x), y = magnitude(first.y, second.y), z = magnitude(first.z, second.z)
        return normBounds(x,y,z).upper
    }

    private func normBounds(_ x: Double, _ y: Double, _ z: Double)
        -> (lower: Double, upper: Double) {
        OriginalDistanceMagnitude.bounds(x,y,z)
    }

    private func makeCell(_ a: Domain, _ b: Domain, depth: Int, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Cell {
        try execution.admitGeometricDepth(depth)
        if try trimCellIsEmpty(a, tolerance: tolerance, using: &execution) || trimCellIsEmpty(b, tolerance: tolerance, using: &execution) {
            return Cell(first: a, second: b, depth: depth, lower: .infinity)
        }
        let x = try positionBounds(a, tolerance: tolerance, using: &execution), y = try positionBounds(b, tolerance: tolerance, using: &execution)
        func gap(_ a: ScalarInterval, _ b: ScalarInterval) -> Double { max(0, max((a.lower - b.upper).nextDown, (b.lower - a.upper).nextDown)) }
        let dx = gap(x.x, y.x), dy = gap(x.y, y.y), dz = gap(x.z, y.z)
        let lower = normBounds(dx,dy,dz).lower
        return Cell(first: a, second: b, depth: depth, lower: lower)
    }
    private func trimCellIsEmpty(_ domain: Domain, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard domain.surface != nil, !domain.trimPredicates.isEmpty else { return false }
        let u = domain.intervals[0], v = domain.intervals[1]
        // A complete boundary enclosure disjoint from this connected box permits
        // one winding classification to classify every point in the box.
        guard !domain.boundaryBoxes.contains(where: { $0.u.intersects(u) && $0.v.intersects(v) }) else { return false }
        for (role, predicate) in domain.trimPredicates {
            let classification = try execution.withGeometricDepthOffset(domain.depth) { execution in
                try predicate.classify(Point2D(x: u.midpoint, y: v.midpoint), tolerance: tolerance, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth - domain.depth, using: &execution)
            }
            if role == .outer && classification == .outside || role == .inner && classification == .inside { return true }
        }
        return false
    }
    private func diameter(_ box: CoordinateEnclosure3D) -> Double { max(box.x.width, max(box.y.width, box.z.width)) }
    private func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
