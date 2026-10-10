import HashTreeCollections
import CADCore
import CADGeometry

public struct DefaultBRepDistanceQuery: BRepDistanceQuerying {
    private struct Domain {
        let support: BRepDistanceSelection
        let curve: Curve3D?
        let surface: Surface3D?
        let point: Point3D?
        let intervals: [ScalarInterval]
        let trimPredicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)]
        var boundaryBoxes: [SurfaceParameterCurveEnclosure] = []
        var preparedSurface: PreparedSurfaceDifferentialEncloser? = nil
        var preparedCurve: PreparedCurveDifferentialEncloser? = nil
        var depth: Int = 0
    }
    private struct Cell {
        let first: Domain
        let second: Domain
        let depth: Int
        let lower: Double
    }
    public init() {}

    public func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, accuracy: Double, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult {
        try distance(from: first, to: second, in: model,
            options: BRepDistanceOptions(absoluteAccuracy: accuracy), tolerance: tolerance)
    }

    public func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult {
        let budget = BRepDistanceProofBudget(tolerance: tolerance,
            maximumWork: options.maximumWork, maximumDepth: options.maximumSubdivisionDepth,
            maximumCumulativeStorageBytes: options.maximumCumulativeStorageBytes,
            maximumSourceDepth: options.maximumSourceDepth, maximumAlgebraicDepth: options.maximumAlgebraicDepth)
        return try distance(from: first, to: second, in: model, options: options,
            tolerance: tolerance, budget: budget)
    }

    public func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        validatedModel: ValidatedBRepModel, options: BRepDistanceOptions) throws -> BRepDistanceQueryResult {
        let budget = BRepDistanceProofBudget(tolerance: validatedModel.tolerance,
            maximumWork: options.maximumWork, maximumDepth: options.maximumSubdivisionDepth,
            maximumCumulativeStorageBytes: options.maximumCumulativeStorageBytes,
            maximumSourceDepth: options.maximumSourceDepth, maximumAlgebraicDepth: options.maximumAlgebraicDepth)
        return try distance(from: first, to: second, validatedModel: validatedModel,
            options: options, budget: budget)
    }

    package func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        validatedModel: ValidatedBRepModel, options: BRepDistanceOptions,
        budget: BRepDistanceProofBudget) throws -> BRepDistanceQueryResult {
        guard validatedModel.validationLevel != .modeling else {
            throw failure("Original distance preparation requires an exact model receipt.", validatedModel.tolerance)
        }
        return try evaluate(from: first, to: second, in: validatedModel.model, options: options,
            tolerance: validatedModel.tolerance, budget: budget, validatedModel: validatedModel)
    }

    package func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance,
        budget: BRepDistanceProofBudget) throws -> BRepDistanceQueryResult {
        try options.validate()
        guard budget.isBound(to: options, tolerance: tolerance) else {
            throw failure("The distance allowance belongs to another original request.", tolerance)
        }
        let validated = try ValidatedBRepModel(model, tolerance: tolerance,
            validationLevel: .exact, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge() },
            consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
        return try evaluate(from: first, to: second, in: validated.model, options: options,
            tolerance: validated.tolerance, budget: budget, validatedModel: validated)
    }

    private func evaluate(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance,
        budget: BRepDistanceProofBudget, validatedModel: ValidatedBRepModel?) throws -> BRepDistanceQueryResult {
        try tolerance.validate(); try options.validate()
        guard options.absoluteAccuracy.isFinite, options.absoluteAccuracy > 0,
            options.relativeAccuracy.isFinite, options.relativeAccuracy >= 0,
            (1...262_144).contains(options.maximumWork),
            (0...32).contains(options.maximumSubdivisionDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Distance accuracy and caller proof ceilings are invalid.")
        }
        guard budget.isBound(to: options, tolerance: tolerance) else {
            throw failure("The distance allowance belongs to another original request.", tolerance)
        }
        func attained(lower: Double, upper: Double) -> Bool {
            guard lower.isFinite, upper.isFinite, lower <= upper else { return false }
            let width = (OutwardScalarInterval.exact(upper) - .exact(lower)).upper
            let relative = (OutwardScalarInterval.exact(options.relativeAccuracy)
                * .exact(max(0,lower))).lower
            return width.isFinite && width <= max(options.absoluteAccuracy,relative)
        }
        let accuracy = options.absoluteAccuracy
        let firstDomains = try domains(first, model: model, tolerance: tolerance,budget: budget, validatedModel: validatedModel)
        let secondDomains = try domains(second, model: model, tolerance: tolerance,budget: budget, validatedModel: validatedModel)
        var cells: [Cell] = []
        var witnesses: [BRepDistanceWitness] = []
        var upper = Double.infinity

        for a in firstDomains { for b in secondDomains {
            try budget.charge()
            let cell = try makeCell(a, b, depth: 0, tolerance: tolerance, budget: budget)
            try push(cell, into: &cells, budget: budget)
            try retainWitnesses(a, b, accuracy: accuracy, upper: &upper, witnesses: &witnesses, tolerance: tolerance, budget: budget)
        } }
        guard !cells.isEmpty else { throw failure("Distance selection has no exact support domains.", tolerance) }
        var globalLower = 0.0
        while !cells.isEmpty {
            try budget.charge()
            guard let cell = try popMinimum(from: &cells, budget: budget) else { break }
            globalLower = cell.lower
            if attained(lower: globalLower,upper: upper) { try push(cell, into: &cells, budget: budget); break }
            if cell.lower > upper { continue }
            guard cell.depth < options.maximumSubdivisionDepth else { throw failure("Minimum-distance depth exhausted before a certified distance width was achieved.", tolerance) }
            let aBox = try positionBounds(cell.first, tolerance: tolerance, budget: budget)
            let bBox = try positionBounds(cell.second, tolerance: tolerance, budget: budget)
            let splitFirst = diameter(aBox) >= diameter(bBox) && !cell.first.intervals.isEmpty || cell.second.intervals.isEmpty
            let source = splitFirst ? cell.first : cell.second
            guard let axis = source.intervals.indices.max(by: { source.intervals[$0].width < source.intervals[$1].width }) else {
                throw failure("A point-only distance pair failed finite arithmetic admission.", tolerance)
            }
            let interval = source.intervals[axis], middle = interval.midpoint
            guard middle > interval.lower, middle < interval.upper else { throw failure("Minimum-distance parameter resolution exhausted.", tolerance) }
            try DistanceQueryStorage.charge(2,of: ScalarInterval.self,budget: budget)
            for range in [try ScalarInterval(lower: interval.lower, upper: middle), try ScalarInterval(lower: middle, upper: interval.upper)] {
                try budget.charge()
                try DistanceQueryStorage.charge(source.intervals.capacity,of: ScalarInterval.self,budget: budget)
                var intervals = source.intervals; intervals[axis] = range
                let child = Domain(support: source.support, curve: source.curve, surface: source.surface,
                    point: source.point, intervals: intervals, trimPredicates: source.trimPredicates, boundaryBoxes: source.boundaryBoxes, preparedSurface: source.preparedSurface, preparedCurve: source.preparedCurve, depth: cell.depth + 1)
                let a = splitFirst ? child : cell.first, b = splitFirst ? cell.second : child
                let next = try makeCell(a, b, depth: cell.depth + 1, tolerance: tolerance, budget: budget)
                try retainWitnesses(a, b, accuracy: accuracy, upper: &upper, witnesses: &witnesses, tolerance: tolerance, budget: budget)
                if next.lower <= upper { try push(next, into: &cells, budget: budget) }
            }
        }
        guard upper.isFinite, !witnesses.isEmpty, attained(lower: globalLower,upper: upper) else {
            throw failure("No trim-admitted closest witness was certified within the requested accuracy.", tolerance)
        }
        var retainedWitnesses: [BRepDistanceWitness] = []
        for witness in witnesses {
            try budget.charge()
            guard witness.distance <= upper+accuracy else { continue }
            try DistanceQueryStorage.reserveForAppend(&retainedWitnesses,budget: budget)
            retainedWitnesses.append(witness)
        }
        var regions: [BRepDistanceMinimumRegion] = []
        for cell in cells {
            try budget.charge()
            guard cell.lower <= upper+accuracy else { continue }
            try DistanceQueryStorage.reserveForAppend(&regions,budget: budget)
            regions.append(BRepDistanceMinimumRegion(firstSupport: cell.first.support,
                secondSupport: cell.second.support, firstParameterRanges: cell.first.intervals,
                secondParameterRanges: cell.second.intervals, lowerDistanceBound: cell.lower))
        }
        return BRepDistanceQueryResult(lowerBound: max(0,globalLower),upperBound: upper,
            witnesses: retainedWitnesses, minimumRegions: regions,
            requestedOptions: options, consumedWork: budget.consumedWork)
    }

    private func push(_ cell: Cell, into cells: inout [Cell], budget: BRepDistanceProofBudget) throws {
        try DistanceQueryStorage.reserveForAppend(&cells,budget: budget)
        cells.append(cell)
        var child = cells.count - 1
        while child > 0 {
            try budget.charge()
            let parent = (child - 1) / 2
            guard cells[child].lower < cells[parent].lower else { break }
            cells.swapAt(child, parent)
            child = parent
        }
    }

    private func popMinimum(from cells: inout [Cell], budget: BRepDistanceProofBudget) throws -> Cell? {
        guard let first = cells.first else { return nil }
        let last = cells.removeLast()
        guard !cells.isEmpty else { return first }
        cells[0] = last
        var parent = 0
        while parent < cells.count / 2 {
            try budget.charge()
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
        budget: BRepDistanceProofBudget, validatedModel: ValidatedBRepModel?) throws -> [Domain] {
        try budget.charge()
        switch selection {
        case .point(let point):
            try DistanceQueryStorage.charge(1,of: Domain.self,budget: budget)
            try point.validate()
            return [Domain(support: selection, curve: nil, surface: nil, point: point, intervals: [], trimPredicates: [])]
        case .curve(let curve, let start, let end):
            try DistanceQueryStorage.charge(1,of: Domain.self,budget: budget)
            try DistanceQueryStorage.charge(1,of: ScalarInterval.self,budget: budget)
            try curve.validate(tolerance: tolerance, remainingSourceDepth: budget.maximumSourceDepth,
                maximumSubdivisionDepth: budget.maximumDepth,
                consumeWork: { try budget.charge(depth: $0) },
                consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            return [Domain(support: selection, curve: curve, surface: nil, point: nil,
                intervals: [try ScalarInterval(lower: min(start, end), upper: max(start, end))], trimPredicates: [],
                preparedCurve: try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                    remainingSourceDepth: budget.maximumSourceDepth, maximumSubdivisionDepth: budget.maximumDepth,
                    consumeWork: { try budget.charge() },
                    consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth))]
        case .surfaceStation(let surface, let parameter):
            try DistanceQueryStorage.charge(1, of: Domain.self, budget: budget)
            try DistanceQueryStorage.charge(2, of: ScalarInterval.self, budget: budget)
            try surface.validate(tolerance: tolerance, remainingSourceDepth: budget.maximumSourceDepth,
                maximumSubdivisionDepth: budget.maximumDepth,
                consumeWork: { try budget.charge(depth: $0) },
                consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            try parameter.validate()
            guard try surface.uDomain.contains(parameter.u, tolerance: tolerance),
                try surface.vDomain.contains(parameter.v, tolerance: tolerance) else {
                throw failure("Original surface station is outside its authored support domain.", tolerance)
            }
            return [Domain(support: selection, curve: nil, surface: surface, point: nil,
                intervals: [try ScalarInterval(lower: parameter.u, upper: parameter.u),
                    try ScalarInterval(lower: parameter.v, upper: parameter.v)], trimPredicates: [],
                preparedSurface: try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                    remainingSourceDepth: budget.maximumSourceDepth, maximumSubdivisionDepth: budget.maximumDepth,
                    consumeWork: { try budget.charge() }, consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth))]
        case .vertex(let id):
            try DistanceQueryStorage.charge(1,of: Domain.self,budget: budget)
            guard let point = model.vertices[id]?.point else { throw TopologyError.missingReference("Missing distance vertex.") }
            return [Domain(support: selection, curve: nil, surface: nil, point: point, intervals: [], trimPredicates: [])]
        case .edge(let id):
            try DistanceQueryStorage.charge(1,of: Domain.self,budget: budget)
            try DistanceQueryStorage.charge(1,of: ScalarInterval.self,budget: budget)
            guard let edge = model.edges[id], let curve = model.geometry.curves[edge.curveID] else { throw TopologyError.missingReference("Missing distance edge curve.") }
            let start: Double, end: Double
            if let trim = edge.trim { start = trim.startParameter; end = trim.endParameter }
            else {
                guard let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { throw TopologyError.invalidEdge(id) }
                start = try curve.parameterProjection(of: a, tolerance: tolerance).parameter
                end = try curve.parameterProjection(of: b, tolerance: tolerance).parameter
            }
            return [Domain(support: selection, curve: curve, surface: nil, point: nil,
                intervals: [try ScalarInterval(lower: min(start, end), upper: max(start, end))], trimPredicates: [],
                preparedCurve: try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                    remainingSourceDepth: budget.maximumSourceDepth, maximumSubdivisionDepth: budget.maximumDepth,
                    consumeWork: { try budget.charge() },
                    consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth))]
        case .faceRegion(let id, let requested):
            let original = try domains(.face(id), model: model, tolerance: tolerance, budget: budget, validatedModel: validatedModel)
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
            try DistanceQueryStorage.charge(1,of: Domain.self,budget: budget)
            try DistanceQueryStorage.charge(2,of: ScalarInterval.self,budget: budget)
            return [Domain(support: selection, curve: nil, surface: face.surface, point: nil,
                intervals: [try ScalarInterval(lower: lowerU, upper: upperU),
                    try ScalarInterval(lower: lowerV, upper: upperV)],
                trimPredicates: face.trimPredicates, boundaryBoxes: face.boundaryBoxes,
                preparedSurface: face.preparedSurface)]
        case .face(let id):
            guard let face = model.faces[id], let surface = model.geometry.surfaces[face.surfaceID] else { throw TopologyError.missingReference("Missing distance face support.") }
            let box = try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: budget.maximumDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission, remainingSourceDepth: budget.maximumSourceDepth,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth).bounds(for: id, in: model, tolerance: tolerance)
            var predicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)] = []
            var boundaries: [Domain] = []
            var boundaryBoxes: [SurfaceParameterCurveEnclosure] = []
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing distance face loop.") }
                for use in loop.coedges {
                    try budget.charge()
                    guard let curve = use.surfaceParameterCurve else { throw failure("A distance face requires every original trim pcurve.", tolerance) }
                    let originalDomains = try domains(.edge(use.edgeID), model: model, tolerance: tolerance,
                        budget: budget, validatedModel: validatedModel)
                    for domain in originalDomains {
                        try budget.charge(); try DistanceQueryStorage.reserveForAppend(&boundaries, budget: budget)
                        boundaries.append(domain)
                    }
                    let originalBoxes = try CertifiedSurfaceParameterCurveEncloser(
                        maximumSubdivisionDepth: budget.maximumDepth,
                        consumeWork: { try budget.charge(depth: $0) },
                        consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth,
                        remainingSourceDepth: budget.maximumSourceDepth)
                        .enclosures(for: curve, on: surface, maximumWidth: 0.25, tolerance: tolerance)
                    for box in originalBoxes {
                        try budget.charge(); try DistanceQueryStorage.reserveForAppend(&boundaryBoxes, budget: budget)
                        boundaryBoxes.append(box)
                    }
                }
                try DistanceQueryStorage.reserveForAppend(&predicates, budget: budget)
                if let validatedModel {
                    predicates.append((loop.role, try CertifiedSurfaceParameterLoopPredicate(
                        loopID: loopID, validatedModel: validatedModel,
                        maximumSubdivisionDepth: budget.maximumDepth, maximumAlgebraicDepth: budget.maximumAlgebraicDepth,
                        remainingSourceDepth: budget.maximumSourceDepth,
                        consumeWork: { try budget.charge(depth: $0) })))
                } else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Raw-model distance compatibility
                    // prepares endpoint/chart authority without a bounded original receipt.
                    // Complete manual-input accounting requires bounded model admission.
                    try DistanceQueryStorage.charge(loop.coedges.count, of: SurfaceParameterCurve.self, budget: budget)
                    let curves = try loop.coedges.map { use -> SurfaceParameterCurve in
                        try budget.charge()
                        guard let curve = use.surfaceParameterCurve else { throw failure("Missing original trim pcurve.", tolerance) }
                        return curve
                    }
                    predicates.append((loop.role, try CertifiedSurfaceParameterLoopPredicate(curves: curves, tolerance: tolerance)))
                }
            }
            try DistanceQueryStorage.charge(1,of: Domain.self,budget: budget)
            try DistanceQueryStorage.charge(2,of: ScalarInterval.self,budget: budget)
            try DistanceQueryStorage.charge(boundaries.count+1,of: Domain.self,budget: budget)
            return [Domain(support: selection, curve: nil, surface: surface, point: nil, intervals: [box.u, box.v], trimPredicates: predicates, boundaryBoxes: boundaryBoxes, preparedSurface: try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                remainingSourceDepth: budget.maximumSourceDepth, maximumSubdivisionDepth: budget.maximumDepth,
                    consumeWork: { try budget.charge() },
                    consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth))] + boundaries
        case .body(let id):
            guard let body = model.bodies[id] else { throw TopologyError.missingReference("Missing distance body.") }
            var result: [Domain] = []
            for shellID in body.shellIDs {
                try budget.charge()
                guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Missing distance body shell.") }
                for faceID in shell.faceIDs {
                    try budget.charge()
                    let originalDomains = try domains(.face(faceID), model: model, tolerance: tolerance,
                        budget: budget, validatedModel: validatedModel)
                    for domain in originalDomains {
                        try budget.charge(); try DistanceQueryStorage.reserveForAppend(&result, budget: budget)
                        result.append(domain)
                    }
                }
            }
            return result
        }
    }

    private func positionBounds(_ domain: Domain, tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> CoordinateEnclosure3D {
        if let point = domain.point { return CoordinateEnclosure3D(x: try ScalarInterval(lower: point.x, upper: point.x), y: try ScalarInterval(lower: point.y, upper: point.y), z: try ScalarInterval(lower: point.z, upper: point.z)) }
        let native: IntervalVector3DBounds
        let remainingDepth = budget.maximumDepth - domain.depth
        if domain.curve != nil {
            guard let prepared = domain.preparedCurve else { throw failure("A curve domain has no prepared original position source.", tolerance) }
            native = try prepared.positionBounds(over: domain.intervals[0], tolerance: tolerance,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: remainingDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: domain.depth) },
                consumeStorage: budget.storageAdmission)
        } else {
            guard let prepared = domain.preparedSurface else { throw failure("A surface domain has no prepared original position source.", tolerance) }
            native = try prepared.positionBounds(over: SurfaceParameterBox(u: domain.intervals[0], v: domain.intervals[1]),
                tolerance: tolerance, maximumSpanCount: 262_144, maximumSubdivisionDepth: remainingDepth,
                remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge(depth: domain.depth) },
                consumeStorage: budget.storageAdmission)
        }
        return CoordinateEnclosure3D(x: try ScalarInterval(lower: native.x.lower, upper: native.x.upper),
            y: try ScalarInterval(lower: native.y.lower, upper: native.y.upper),
            z: try ScalarInterval(lower: native.z.lower, upper: native.z.upper))
    }

    private func witnessClassification(_ point: Point2D,
        predicate: CertifiedSurfaceParameterLoopPredicate, depth: Int,
        tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> PlanarPointClassification {
        let visit: @Sendable (Int) throws -> Void = { try budget.charge(depth: depth + $0) }
        if let strict = try predicate.classifyStrictlyOriginal(point, tolerance: tolerance,
            consumeWork: visit, consumeStorage: budget.storageAdmission,
            maximumSubdivisionDepth: budget.maximumDepth - depth) { return strict }
        return try predicate.classify(point, tolerance: tolerance, consumeWork: visit,
            consumeStorage: budget.storageAdmission, maximumSubdivisionDepth: budget.maximumDepth - depth)
    }

    private func samples(_ domain: Domain, tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> [(Point3D, [Double])] {
        if let point = domain.point {
            try DistanceQueryStorage.charge(1,of: (Point3D,[Double]).self,budget: budget)
            return [(point, [])]
        }
        func station(_ parameters: [Double]) throws -> Point3D {
            let original = try witnessPositionBounds(domain, parameters: parameters,
                point: .origin, tolerance: tolerance, budget: budget)
            let point = Point3D(x: original.x.midpoint, y: original.y.midpoint, z: original.z.midpoint)
            try point.validate()
            return point
        }
        if domain.curve != nil {
            try DistanceQueryStorage.charge(3,of: Double.self,budget: budget)
            try DistanceQueryStorage.charge(3,of: (Point3D,[Double]).self,budget: budget)
            return try [domain.intervals[0].lower, domain.intervals[0].midpoint, domain.intervals[0].upper].map {
                try budget.charge()
                try DistanceQueryStorage.charge(2,of: Double.self,budget: budget)
                return (try station([$0]), [$0])
            }
        }
        guard domain.surface != nil else { throw failure("Distance sampling has no exact support.", tolerance) }
        var result: [(Point3D, [Double])] = []
        try DistanceQueryStorage.charge(3,of: Double.self,budget: budget)
        for u in [domain.intervals[0].lower, domain.intervals[0].midpoint, domain.intervals[0].upper] {
            try DistanceQueryStorage.charge(3,of: Double.self,budget: budget)
            for v in [domain.intervals[1].lower, domain.intervals[1].midpoint, domain.intervals[1].upper] {
                try budget.charge()
                var admitted = true
                for (role, predicate) in domain.trimPredicates {
                    let classification = try witnessClassification(Point2D(x: u, y: v), predicate: predicate,
                        depth: domain.depth, tolerance: tolerance, budget: budget)
                    if role == .outer && classification != .inside || role == .inner && classification != .outside { admitted = false; break }
                }
                if admitted {
                    try DistanceQueryStorage.reserveForAppend(&result,budget: budget)
                    try DistanceQueryStorage.charge(4,of: Double.self,budget: budget)
                    result.append((try station([u, v]), [u, v]))
                }
            }
        }
        return result
    }

    private func retainWitnesses(_ a: Domain, _ b: Domain, accuracy: Double, upper: inout Double,
        witnesses: inout [BRepDistanceWitness], tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws {
        try budget.charge()
        var first = try samples(a, tolerance: tolerance, budget: budget), second = try samples(b, tolerance: tolerance, budget: budget)
        if !upper.isFinite, let refined = try refinedWitness(a, b, tolerance: tolerance, budget: budget) {
            try DistanceQueryStorage.reserveForAppend(&first,budget: budget)
            try DistanceQueryStorage.reserveForAppend(&second,budget: budget)
            first.append(refined.0); second.append(refined.1)
        }
        try DistanceQueryStorage.charge(first.count,of: CoordinateEnclosure3D.self,budget: budget)
        try DistanceQueryStorage.charge(second.count,of: CoordinateEnclosure3D.self,budget: budget)
        let firstBoxes = try first.map { try witnessPositionBounds(a, parameters: $0.1,
            point: $0.0, tolerance: tolerance, budget: budget) }
        let secondBoxes = try second.map { try witnessPositionBounds(b, parameters: $0.1,
            point: $0.0, tolerance: tolerance, budget: budget) }
        for (firstIndex, x) in first.enumerated() { for (secondIndex, y) in second.enumerated() {
            try budget.charge()
            let value = upperDistance(firstBoxes[firstIndex], secondBoxes[secondIndex])
            guard value.isFinite else { throw failure("Minimum-distance witness arithmetic is nonfinite.", tolerance) }
            if value < upper {
                upper = value
                try witnesses.removeAll { witness in
                    try budget.charge()
                    return witness.distance > upper+accuracy
                }
            }
            let repeated: Bool
            if value <= upper + accuracy {
                repeated = try witnesses.contains(where: { witness in
                    try originalSupportComparison(witness.firstSupport,a.support,budget: budget)
                        && originalSupportComparison(witness.secondSupport,b.support,budget: budget)
                        && (witness.firstPoint - x.0).length <= accuracy
                        && (witness.secondPoint - y.0).length <= accuracy
                })
            } else { repeated = true }
            if !repeated {
                guard witnesses.count < 262_144 else { throw failure("Minimum-distance witness allowance exhausted.", tolerance) }
                try DistanceQueryStorage.reserveForAppend(&witnesses,budget: budget)
                witnesses.append(.init(firstSupport: a.support, secondSupport: b.support,
                    firstPoint: x.0, secondPoint: y.0, firstParameters: x.1, secondParameters: y.1))
            }
        } }
    }
    private func originalSupportComparison(_ first: BRepDistanceSelection,
        _ second: BRepDistanceSelection,budget: BRepDistanceProofBudget) throws -> Bool {
        try budget.charge()
        if case .curve(let curve,_,_) = first {
            try GeometryStructuralComparisonWork.charge(curve: curve,
                using: { count in for _ in 0..<count { try budget.charge() } })
        }
        if case .curve(let curve,_,_) = second {
            try GeometryStructuralComparisonWork.charge(curve: curve,
                using: { count in for _ in 0..<count { try budget.charge() } })
        }
        if case .surfaceStation(let surface, _) = first {
            try GeometryStructuralComparisonWork.charge(surface: surface,
                using: { count in for _ in 0..<count { try budget.charge() } })
        }
        if case .surfaceStation(let surface, _) = second {
            try GeometryStructuralComparisonWork.charge(surface: surface,
                using: { count in for _ in 0..<count { try budget.charge() } })
        }
        return first == second
    }

    private func refinedWitness(_ first: Domain, _ second: Domain, tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws
        -> ((Point3D,[Double]),(Point3D,[Double]))? {
        try DistanceQueryStorage.charge(first.intervals.count+second.intervals.count,of: Double.self,budget: budget)
        var a = first.intervals.map({ $0.midpoint }), b = second.intervals.map({ $0.midpoint })
        func evaluated(_ domain: Domain, _ parameters: [Double]) throws
            -> (point: Point3D, bounds: CoordinateEnclosure3D) {
            if let point = domain.point {
                return (point, try witnessPositionBounds(domain, parameters: parameters,
                    point: point, tolerance: tolerance, budget: budget))
            }
            let original = try witnessPositionBounds(domain, parameters: parameters,
                point: .origin, tolerance: tolerance, budget: budget)
            let point = Point3D(x: original.x.midpoint, y: original.y.midpoint, z: original.z.midpoint)
            try point.validate()
            return (point, original)
        }
        func admitted(_ domain: Domain,_ parameters:[Double]) throws -> Bool {
            guard domain.surface != nil else{return true}
            for (role,predicate) in domain.trimPredicates {
                let classification = try witnessClassification(Point2D(x: parameters[0], y: parameters[1]),
                    predicate: predicate, depth: domain.depth, tolerance: tolerance, budget: budget)
                if role == .outer && classification != .inside || role == .inner && classification != .outside{return false}
            }
            return true
        }
        try budget.charge()
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
                        try budget.charge()
                        var parameters = side == 0 ? a : b
                        let previous = parameters[axis]
                        try DistanceQueryStorage.charge(parameters.capacity,of: Double.self,budget: budget)
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
        tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> CoordinateEnclosure3D {
        try budget.charge()
        if domain.point != nil {
            return CoordinateEnclosure3D(x: try ScalarInterval(lower: point.x, upper: point.x),
                y: try ScalarInterval(lower: point.y, upper: point.y),
                z: try ScalarInterval(lower: point.z, upper: point.z))
        }
        try DistanceQueryStorage.charge(parameters.count,of: ScalarInterval.self,budget: budget)
        let ranges = try parameters.map { try ScalarInterval(lower: $0, upper: $0) }
        let station = Domain(support: domain.support, curve: domain.curve, surface: domain.surface,
            point: nil, intervals: ranges, trimPredicates: [], preparedSurface: domain.preparedSurface,
            preparedCurve: domain.preparedCurve, depth: domain.depth)
        return try positionBounds(station, tolerance: tolerance, budget: budget)
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

    private func makeCell(_ a: Domain, _ b: Domain, depth: Int, tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> Cell {
        if try trimCellIsEmpty(a, tolerance: tolerance, budget: budget) || trimCellIsEmpty(b, tolerance: tolerance, budget: budget) {
            return Cell(first: a, second: b, depth: depth, lower: .infinity)
        }
        let x = try positionBounds(a, tolerance: tolerance, budget: budget), y = try positionBounds(b, tolerance: tolerance, budget: budget)
        func gap(_ a: ScalarInterval, _ b: ScalarInterval) -> Double { max(0, max((a.lower - b.upper).nextDown, (b.lower - a.upper).nextDown)) }
        let dx = gap(x.x, y.x), dy = gap(x.y, y.y), dz = gap(x.z, y.z)
        let lower = normBounds(dx,dy,dz).lower
        return Cell(first: a, second: b, depth: depth, lower: lower)
    }
    private func trimCellIsEmpty(_ domain: Domain, tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> Bool {
        guard domain.surface != nil, !domain.trimPredicates.isEmpty else { return false }
        let u = domain.intervals[0], v = domain.intervals[1]
        // A complete boundary enclosure disjoint from this connected box permits
        // one winding classification to classify every point in the box.
        guard !domain.boundaryBoxes.contains(where: { $0.u.intersects(u) && $0.v.intersects(v) }) else { return false }
        for (role, predicate) in domain.trimPredicates {
            let classification = try predicate.classify(Point2D(x: u.midpoint, y: v.midpoint), tolerance: tolerance, consumeWork: { try budget.charge(depth: domain.depth + $0) },
                consumeStorage: budget.storageAdmission, maximumSubdivisionDepth: budget.maximumDepth - domain.depth)
            if role == .outer && classification == .outside || role == .inner && classification == .inside { return true }
        }
        return false
    }
    private func diameter(_ box: CoordinateEnclosure3D) -> Double { max(box.x.width, max(box.y.width, box.z.width)) }
    private func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
