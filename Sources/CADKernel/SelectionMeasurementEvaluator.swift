#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct SelectionMeasurementEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let edgeQueryEvaluator: EdgeQueryEvaluator
    private let curveQueryEvaluator: CurveQueryEvaluator
    private let surfaceQueryEvaluator: SurfaceQueryEvaluator

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        self.edgeQueryEvaluator = EdgeQueryEvaluator(tolerance: tolerance)
        self.curveQueryEvaluator = CurveQueryEvaluator(tolerance: tolerance)
        self.surfaceQueryEvaluator = SurfaceQueryEvaluator(tolerance: tolerance)
    }

    public func point(
        for selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        try selection.validate()
        switch selection {
        case let .subshape(reference):
            return try topologyPoint(
                for: try document.topologyReference(for: reference),
                stableReference: reference,
                selection: selection,
                in: document
            )
        case let .edge(reference):
            return try edgePoint(for: reference, selection: selection, in: document)
        case let .curve(reference):
            return try curvePoint(for: reference, selection: selection, in: document)
        case let .sketchPoint(reference):
            return try sketchPoint(for: reference, selection: selection, in: document)
        case let .surface(reference):
            return try surfacePoint(for: reference, selection: selection, in: document)
        }
    }

    public func distance(
        from first: SelectionReference,
        to second: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionDistanceMeasurement {
        try distance(from: first, to: second, in: document,
            options: BRepDistanceOptions(absoluteAccuracy: tolerance.distance))
    }

    public func distance(
        from first: SelectionReference, to second: SelectionReference,
        in document: EvaluatedDocument, options: BRepDistanceOptions,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> SelectionDistanceMeasurement {
        let overview = try distanceOverview(from: first, to: second, in: document,
            options: options, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let result = overview.minimum
        guard let witness = result.witnesses.first else {
            throw KernelError(phase: .geometry, code: .emptyResult, tolerance: tolerance,
                message: "A certified minimum-distance query produced no closest pair.")
        }
        return try SelectionDistanceMeasurement(
            first: SelectionMeasurementPoint(selection: first, point: witness.firstPoint),
            second: SelectionMeasurementPoint(selection: second, point: witness.secondPoint),
            modelLengthUnit: overview.modelLengthUnit,
            minimumBounds: ScalarInterval(lower: result.lowerBound, upper: result.upperBound),
            requestedOptions: result.requestedOptions, consumedWork: result.consumedWork
        )
    }

    public func closestPairs(
        from first: SelectionReference, to second: SelectionReference,
        in document: EvaluatedDocument, accuracy: Double? = nil
    ) throws -> BRepDistanceQueryResult {
        try distanceOverview(from: first, to: second, in: document, accuracy: accuracy).minimum
    }

    public func distanceOverview(from first: SelectionReference,to second: SelectionReference,
        in document: EvaluatedDocument,accuracy:Double?=nil)throws->SelectionDistanceOverview{
        try distanceOverview(from: first, to: second, in: document,
            options: BRepDistanceOptions(absoluteAccuracy: accuracy ?? tolerance.distance))
    }

    public func closestPairs(from first: SelectionReference, to second: SelectionReference,
        in document: EvaluatedDocument, options: BRepDistanceOptions) throws -> BRepDistanceQueryResult {
        try distanceOverview(from: first, to: second, in: document, options: options).minimum
    }

    public func distanceOverview(from first: SelectionReference, to second: SelectionReference,
        in document: EvaluatedDocument, options: BRepDistanceOptions,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil) throws -> SelectionDistanceOverview {
        try options.validate()
        try tolerance.validate()
        let proofBudget = BRepDistanceProofBudget(tolerance: tolerance, maximumWork: options.maximumWork,
            maximumDepth: options.maximumSubdivisionDepth,
            maximumCumulativeStorageBytes: options.maximumCumulativeStorageBytes,
            maximumSourceDepth: options.maximumSourceDepth, maximumAlgebraicDepth: options.maximumAlgebraicDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        try proofBudget.charge()
        let a=try distanceSelection(first,in:document,budget:proofBudget)
        try proofBudget.charge()
        let b=try distanceSelection(second,in:document,budget:proofBudget)
        let certificate: ValidatedBRepModel
        if let original = document.validatedBRep {
            guard original.tolerance == tolerance, original.validationLevel != .modeling else {
                throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                    message: "Distance preparation requires its configured original exact model receipt.")
            }
            certificate = original
        } else {
            certificate = try ValidatedBRepModel(document.brep, tolerance: tolerance,
                validationLevel: .exact, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                remainingSourceDepth: proofBudget.maximumSourceDepth, consumeWork: { try proofBudget.charge() },
                consumeStorage: proofBudget.storageAdmission, maximumAlgebraicDepth: proofBudget.maximumAlgebraicDepth)
        }
        let boundary = try DefaultBRepDistanceQuery().distance(from: a, to: b,
            validatedModel: certificate, options: options, budget: proofBudget)
        func currentBoundary() -> BRepDistanceQueryResult {
            BRepDistanceQueryResult(lowerBound: boundary.lowerBound, upperBound: boundary.upperBound,
                witnesses: boundary.witnesses, minimumRegions: boundary.minimumRegions,
                requestedOptions: options, consumedWork: proofBudget.consumedWork)
        }
        guard case .body(let firstBody)=a,case .body(let secondBody)=b,
            document.brep.bodies[firstBody]?.kind == .solid,document.brep.bodies[secondBody]?.kind == .solid else{
            return SelectionDistanceOverview(modelLengthUnit: document.document.units.length, minimum:currentBoundary(),boundarySeparation:currentBoundary(),
                relationship: boundary.upperBound == 0 ? .boundaryContact:
                    boundary.lowerBound > 0 ? .separated:.indeterminate)
        }
        let classifier=DefaultBRepSolidPointClassifier()
        let classifications = try PreparedSolidClassificationPair(firstBodyID: firstBody,
            secondBodyID: secondBody, validatedModel: certificate, classifier: classifier,
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            remainingSourceDepth: proofBudget.maximumSourceDepth, maximumAlgebraicDepth: proofBudget.maximumAlgebraicDepth,
            consumeWork: { try proofBudget.charge(depth: $0) },
            consumeStorage: proofBudget.storageAdmission)
        let firstSession = classifications.firstClassification
        let secondSession = classifications.secondClassification
        if firstBody == secondBody {
            guard let contact = try finiteBodyContact(classifications: classifications, budget: proofBudget),
                let point = contact.interiorPoint else {
                throw KernelError(phase: .classification, code: .classificationFailure, tolerance: tolerance,
                    message: "Identical original solids have no admitted common interior witness.")
            }
            let witness = BRepDistanceWitness(firstSupport: a, secondSupport: b,
                firstPoint: point, secondPoint: point, firstParameters: [], secondParameters: [])
            try DistanceQueryStorage.charge(1, of: BRepDistanceWitness.self, budget: proofBudget)
            return SelectionDistanceOverview(modelLengthUnit: document.document.units.length,
                minimum: BRepDistanceQueryResult(lowerBound: 0, upperBound: 0, witnesses: [witness],
                    requestedOptions: options, consumedWork: proofBudget.consumedWork),
                boundarySeparation: currentBoundary(), relationship: contact.relationship)
        }
        func classify(_ point: Point3D, in body: BodyID) throws -> SolidPointClassification {
            try proofBudget.charge()
            if body == firstBody { return try firstSession.classify(point) }
            guard body == secondBody else { throw TopologyError.missingReference("Foreign body in original distance classification.") }
            return try secondSession.classify(point)
        }
        func points(_ id: BodyID) throws -> [Point3D] {
            guard let body = document.brep.bodies[id] else {
                throw TopologyError.missingReference("Missing relationship body.")
            }
            let allowance = (tolerance.distance / 16).nextDown
            guard allowance > 0 else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                    message: "Original boundary localization cannot represent its distance allocation.")
            }
            var result: [Point3D] = []
            func admit(_ position: IntervalVector3DBounds) throws {
                try proofBudget.charge()
                let point = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
                let x = (position.x - .exact(point.x)).absoluteUpperBound
                let y = (position.y - .exact(point.y)).absoluteUpperBound
                let z = (position.z - .exact(point.z)).absoluteUpperBound
                let error = OriginalDistanceMagnitude.bounds(x,y,z).upper
                guard error.isFinite, error <= allowance else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, residual: error,
                        tolerance: tolerance,
                        message: "Original boundary station cannot attain the relationship localization allocation.")
                }
                try point.validate()
                try DistanceQueryStorage.reserveForAppend(&result, budget: proofBudget)
                result.append(point)
            }
            var edgeIDs: [EdgeID] = []
            for shellID in body.shellIDs {
                try proofBudget.charge()
                guard let shell = document.brep.shells[shellID] else {
                    throw TopologyError.missingReference("Missing original relationship shell.")
                }
                for faceID in shell.faceIDs {
                    try proofBudget.charge()
                    guard let face = document.brep.faces[faceID] else {
                        throw TopologyError.missingReference("Missing original relationship face.")
                    }
                    if face.loops.isEmpty {
                        guard let surface = document.brep.geometry.surfaces[face.surfaceID] else {
                            throw TopologyError.missingReference("Missing original loop-free relationship support.")
                        }
                        let extent = try FaceParameterExtentResolver(maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                            consumeWork: { try proofBudget.charge(depth: $0) }, consumeStorage: proofBudget.storageAdmission,
                            remainingSourceDepth: proofBudget.maximumSourceDepth,
                            maximumAlgebraicDepth: proofBudget.maximumAlgebraicDepth)
                            .bounds(for: faceID, in: document.brep, tolerance: tolerance)
                        let station = SurfaceParameterBox(u: try .init(lower: extent.u.midpoint, upper: extent.u.midpoint),
                            v: try .init(lower: extent.v.midpoint, upper: extent.v.midpoint))
                        let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                            remainingSourceDepth: proofBudget.maximumSourceDepth,
                            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                            consumeWork: { try proofBudget.charge() }, consumeStorage: proofBudget.storageAdmission,
                            maximumAlgebraicDepth: proofBudget.maximumAlgebraicDepth)
                        try admit(prepared.positionBounds(over: station, tolerance: tolerance,
                            maximumSpanCount: 262_144, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                            remainingSourceDepth: proofBudget.maximumSourceDepth,
                            consumeWork: { try proofBudget.charge() }, consumeStorage: proofBudget.storageAdmission))
                    }
                    for loopID in face.loops {
                        try proofBudget.charge()
                        guard let loop = document.brep.loops[loopID] else {
                            throw TopologyError.missingReference("Missing original relationship loop.")
                        }
                        for use in loop.coedges {
                            try proofBudget.charge()
                            try DistanceQueryStorage.reserveForAppend(&edgeIDs, budget: proofBudget)
                            edgeIDs.append(use.edgeID)
                        }
                    }
                }
            }
            try DistanceQueryStorage.orderAndDeduplicate(&edgeIDs, budget: proofBudget)
            for edgeID in edgeIDs {
                try proofBudget.charge()
                guard let edge = document.brep.edges[edgeID],
                    let curve = document.brep.geometry.curves[edge.curveID] else {
                    throw TopologyError.missingReference("Missing original relationship edge curve.")
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original raw-ID edge preparation
                // supplies authored/native endpoints under this retained model and
                // query ledger. General untrimmed nonrepresentable endpoint laws
                // still need their producer before the whole relationship domain
                // can be certified; no legacy numeric projection is replayed here.
                let original = try edgeQueryEvaluator.originalGeometry(of: edgeID, in: document,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    remainingSourceDepth: proofBudget.maximumSourceDepth,
                    consumeWork: { try proofBudget.charge(depth: $0) }, consumeStorage: proofBudget.storageAdmission,
                    maximumAlgebraicDepth: proofBudget.maximumAlgebraicDepth)
                guard original.curveID == edge.curveID else {
                    throw TopologyError.missingReference("Original relationship edge preparation changed its source identity.")
                }
                let parameters = (first: original.startParameter, last: original.endParameter)
                let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                    remainingSourceDepth: proofBudget.maximumSourceDepth, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    consumeWork: { try proofBudget.charge() },
                    consumeStorage: proofBudget.storageAdmission, maximumAlgebraicDepth: proofBudget.maximumAlgebraicDepth)
                for endpoint in 0..<2 {
                    let parameter = endpoint == 0 ? parameters.first : parameters.last
                    try proofBudget.charge()
                    let position = try prepared.positionBounds(over: ScalarInterval(lower: parameter, upper: parameter),
                        tolerance: tolerance, maximumSpanCount: 262_144,
                        maximumSubdivisionDepth: options.maximumSubdivisionDepth, remainingSourceDepth: proofBudget.maximumSourceDepth,
                        consumeWork: { try proofBudget.charge() },
                        consumeStorage: proofBudget.storageAdmission)
                    try admit(position)
                }
            }
            return result
        }
        let firstPoints=try points(firstBody),secondPoints=try points(secondBody)
        func classificationSummary(_ points: [Point3D], in body: BodyID)
            throws -> (anyInside: Bool, allInside: Bool) {
            var anyInside = false, allInside = !points.isEmpty
            for point in points {
                let inside = try classify(point, in: body) == .inside
                anyInside = anyInside || inside; allInside = allInside && inside
            }
            return (anyInside, allInside)
        }
        let firstClasses = try classificationSummary(firstPoints, in: secondBody)
        let secondClasses = try classificationSummary(secondPoints, in: firstBody)
        if firstClasses.anyInside || secondClasses.anyInside {
            // FIXME(INCOMPLETE_IMPLEMENTATION): This original common-interior
            // producer supplies actual both-inside witnesses under the same query
            // ledger. Classifier lower allocation and combined search/source-depth
            // admission remain required for whole-query resource completion.
            guard let point = try OriginalTransverseMaterialOverlap().interiorWitness(
                in: classifications, maximumSubdivisionDepth: proofBudget.maximumDepth,
                consumeWork: { try proofBudget.charge(depth: $0) },
                consumeStorage: proofBudget.storageAdmission) else {
                throw KernelError(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Original containment evidence has no proved common interior witness within the request limits.")
            }
            let firstContained = firstClasses.allInside && !secondClasses.anyInside
                && boundary.lowerBound>tolerance.distance
            let secondContained = secondClasses.allInside && !firstClasses.anyInside
                && boundary.lowerBound>tolerance.distance
            let relationship:SelectionDistanceRelationship = firstContained ? .firstContainedInSecond:
                secondContained ? .secondContainedInFirst:boundary.lowerBound>tolerance.distance ? .mixedComponents:.intersecting
            let witness=BRepDistanceWitness(firstSupport:a,secondSupport:b,firstPoint:point,secondPoint:point,
                firstParameters:[],secondParameters:[])
            try DistanceQueryStorage.charge(1, of: BRepDistanceWitness.self, budget: proofBudget)
            return SelectionDistanceOverview(modelLengthUnit: document.document.units.length, minimum:BRepDistanceQueryResult(lowerBound:0,upperBound:0,witnesses:[witness],
                    requestedOptions: options, consumedWork: proofBudget.consumedWork),
                boundarySeparation:currentBoundary(),relationship:relationship)
        }
        if boundary.lowerBound <= tolerance.distance {
            let contact = try finiteBodyContact(classifications: classifications, budget: proofBudget)
            if let contact {
                // The original supports retain their actual floating-point locations.
                // A trim-intersection certificate establishes a zero lower bound,
                // while the published closest pair still supplies its actual upper bound.
                let minimum: BRepDistanceQueryResult
                if let point = contact.interiorPoint {
                    let witness = BRepDistanceWitness(firstSupport: a, secondSupport: b,
                        firstPoint: point, secondPoint: point, firstParameters: [], secondParameters: [])
                    try DistanceQueryStorage.charge(1, of: BRepDistanceWitness.self, budget: proofBudget)
                    minimum = BRepDistanceQueryResult(lowerBound: 0, upperBound: 0, witnesses: [witness],
                        requestedOptions: options, consumedWork: proofBudget.consumedWork)
                } else { minimum = currentBoundary() }
                return SelectionDistanceOverview(modelLengthUnit: document.document.units.length, minimum: minimum,
                    boundarySeparation: currentBoundary(), relationship: contact.relationship)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Complete finite intersection graphs
            // exclude contact, but close disjoint boundaries still require continued
            // extrema refinement below the caller accuracy to prove strict separation.
            // Production path: body distanceOverview; an inconclusive lower bound
            // must not publish separated material or a manufactured zero distance.
            throw KernelError(phase: .classification, code: .classificationFailure,
                tolerance: tolerance,
                message: "Finite boundaries have no contact, but the minimum enclosure cannot yet prove strict separation.")
        }
        return SelectionDistanceOverview(modelLengthUnit: document.document.units.length, minimum:currentBoundary(),boundarySeparation:currentBoundary(),relationship:.separated)
    }

    private func finiteBodyContact(classifications: PreparedSolidClassificationPair,
        budget: BRepDistanceProofBudget
    ) throws -> (relationship: SelectionDistanceRelationship, interiorPoint: Point3D?)? {
        let validatedModel = classifications.validatedModel
        let firstBody = classifications.firstBodyID, secondBody = classifications.secondBodyID
        let firstSession = classifications.firstClassification, secondSession = classifications.secondClassification
        let model = validatedModel.model
        if firstBody == secondBody {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Actual common-interior search
            // replaces rounded boundary-coordinate witnesses. Classifier lower
            // BYTES and combined source/search depth still prevent a whole-query
            // resource-completion claim on the production distance path.
            guard let point = try OriginalTransverseMaterialOverlap().interiorWitness(
                in: classifications, maximumSubdivisionDepth: budget.maximumDepth,
                consumeWork: { try budget.charge(depth: $0) },
                consumeStorage: budget.storageAdmission) else {
                throw KernelError(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Identical solids have no proved common interior witness within the request limits.")
            }
            return (.intersecting, point)
        }
        func faces(_ id: BodyID) throws -> [FaceID] {
            guard let body = model.bodies[id] else {
                throw TopologyError.missingReference("Missing original contact body.")
            }
            var result: [FaceID] = []
            for shellID in body.shellIDs {
                try budget.charge()
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing original contact shell.")
                }
                for faceID in shell.faceIDs {
                    try budget.charge()
                    try DistanceQueryStorage.reserveForAppend(&result, budget: budget)
                    result.append(faceID)
                }
            }
            try DistanceQueryStorage.orderAndDeduplicate(&result, budget: budget)
            return result
        }
        let firstFaces = try faces(firstBody), secondFaces = try faces(secondBody)
        guard firstFaces.count <= 262144,
            secondFaces.count <= 262144 / max(1, firstFaces.count) else {
            throw KernelError(phase: .classification, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Complete body-contact face pairs exceed the existing work ceiling.")
        }
        var pairs: [BooleanFacePairCandidate] = []
        for first in firstFaces {
            for second in secondFaces where first != second {
                try budget.charge()
                try DistanceQueryStorage.reserveForAppend(&pairs, budget: budget)
                pairs.append(BooleanFacePairCandidate(targetFaceID: first, toolFaceID: second))
            }
        }
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        // FIXME(INCOMPLETE_IMPLEMENTATION): Public body distance reaches these
        // source-bound graph producer under the same query work/byte owner. UV split,
        // overlap and remaining SSI/trim temporary allocations still need their
        // bounded lower ports before complete invocation admission can be claimed.
        let prepared = try pipeline.prepareIntersectionGraph(facePairs: pairs,
            classifications: classifications, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
            consumeWork: { try budget.charge(depth: $0) },
            consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
        if let originalInterior = try OriginalTransverseMaterialOverlap().interiorWitness(in: prepared,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: budget.maximumDepth,
            remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge(depth: $0) },
            consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth) {
            return (.intersecting, originalInterior)
        }
        let graph = prepared.intersectionGraph
        try budget.charge()
        let splits = try pipeline.uvSplitGraph(intersectionGraph: graph, model: model, tolerance: tolerance)
        let overlap = CoincidentFaceOverlapTester(facePointContainment: DefaultFacePointContainmentTester())
        var foundContact = false
        for split in splits.splits {
            for component in split.components {
                try budget.charge()
                let point: Point3D?
                switch component.geometry {
                case .transverseSegment(let start, _): point = start.point
                case .closedCurve(let curve): point = curve.samples.first?.uvPoint.point
                case .trimmedCurve(let chain): point = chain.start.point
                case .tangent(let tangent): point = tangent.point
                case .coincident:
                    point = try overlap.overlapWitness(split.facePair.targetFaceID,
                        split.facePair.toolFaceID, in: model, tolerance: tolerance)
                }
                guard let point else { continue }
                foundContact = true
                // Candidates only locate witnesses; original solid classifiers
                // establish membership. No absent candidate proves disjoint interiors.
                let distance = tolerance.distance * 8
                for x in -1...1 {
                    for y in -1...1 {
                        for z in -1...1 where x != 0 || y != 0 || z != 0 {
                            try budget.charge()
                            try budget.charge()
                            let candidate = point + Vector3D(x: Double(x)*distance,
                                y: Double(y)*distance, z: Double(z)*distance)
                            if try firstSession.classify(candidate) == .inside,
                                try secondSession.classify(candidate) == .inside {
                                return (.intersecting, candidate)
                            }
                        }
                    }
                }
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Production body distanceOverview reaches
        // this contact route. Finite offset candidates can miss a narrow common interior;
        // complete original material-side certificates must distinguish touching from
        // overlap before boundary-only contact can be published.
        if foundContact {
            throw KernelError(phase: .classification, code: .classificationFailure,
                tolerance: tolerance, message: "Original contact exists, but finite candidates do not prove boundary-only material contact.")
        }
        return nil
    }

    private func distanceSelection(_ selection: SelectionReference,
        in document: EvaluatedDocument, budget: BRepDistanceProofBudget) throws -> BRepDistanceSelection {
        try selection.validate()
        let stable: StableSubshapeReference?
        switch selection {
        case .subshape(let reference): stable = reference
        case .edge(.whole(let reference)): stable = reference.subshape
        case .surface(.whole(let reference)): stable = reference.subshape
        case .edge(.parameter(let reference)):
            let source = try edgeQueryEvaluator.resolveOriginalGeometry(reference.edge, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            guard try source.contains(parameter: reference.parameter, tolerance: tolerance) else {
                throw GeometryError.invalidDistance(reference.parameter)
            }
            return .curve(source.curve, from: reference.parameter, to: reference.parameter)
        case .curve(.parameter(let reference)):
            let source = try curveQueryEvaluator.resolveOriginalGeometry(reference.curve, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            guard try source.parameterDomain.contains(reference.parameter, tolerance: tolerance) else {
                throw GeometryError.invalidDistance(reference.parameter)
            }
            return .curve(source.curve, from: reference.parameter, to: reference.parameter)
        case .curve(.knot(let reference)):
            let source = try curveQueryEvaluator.resolveOriginalGeometry(reference.curve, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            let knot = try curveQueryEvaluator.knotOriginal(reference, source: source,
                remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge(depth: $0) })
            guard try source.parameterDomain.contains(knot, tolerance: tolerance) else {
                throw GeometryError.invalidDistance(knot)
            }
            return .curve(source.curve, from: knot, to: knot)
        case .curve(.span(let reference)):
            let source = try curveQueryEvaluator.resolveOriginalGeometry(reference.curve, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            let span = try curveQueryEvaluator.spanOriginal(reference, source: source,
                remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge(depth: $0) })
            return .curve(source.curve, from: span.lowerParameter, to: span.upperParameter)
        case .surface(.parameter(let reference)):
            let source = try surfaceQueryEvaluator.resolveOriginalGeometry(reference.surface, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            return .surfaceStation(source.surface, SurfaceParameter(u: reference.u, v: reference.v))
        case .surface(.knot(let reference)):
            let source = try surfaceQueryEvaluator.resolveOriginalGeometry(reference.surface, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            let knot = try surfaceQueryEvaluator.knotOriginal(reference, source: source,
                remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge(depth: $0) })
            let original = try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: budget.maximumDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                remainingSourceDepth: budget.maximumSourceDepth, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
                .bounds(for: source.faceID,
                in: document.brep, tolerance: tolerance)
            let axis = try ScalarInterval(lower: knot, upper: knot)
            let region: SurfaceParameterBox
            switch reference.direction {
            case .u: region = SurfaceParameterBox(u: axis, v: original.v)
            case .v: region = SurfaceParameterBox(u: original.u, v: axis)
            }
            return .faceRegion(source.faceID, region)
        case .surface(.span(let reference)):
            let source = try surfaceQueryEvaluator.resolveOriginalGeometry(reference.surface, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            let span = try surfaceQueryEvaluator.spanOriginal(reference, source: source,
                remainingSourceDepth: budget.maximumSourceDepth, consumeWork: { try budget.charge(depth: $0) })
            let original = try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: budget.maximumDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                remainingSourceDepth: budget.maximumSourceDepth, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
                .bounds(for: source.faceID,
                in: document.brep, tolerance: tolerance)
            let axis = try ScalarInterval(lower: span.lowerParameter, upper: span.upperParameter)
            let region: SurfaceParameterBox
            switch reference.direction {
            case .u: region = SurfaceParameterBox(u: axis, v: original.v)
            case .v: region = SurfaceParameterBox(u: original.u, v: axis)
            }
            return .faceRegion(source.faceID, region)
        case .surface(.trim(let reference)):
            let trim = try surfaceQueryEvaluator.trimOriginal(reference, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            return .curve(trim.liftedCurve, from: 0, to: 1)
        case .surface(.trimSpan(let reference)):
            let trim = try surfaceQueryEvaluator.trimOriginal(reference.trim, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            let span = try surfaceQueryEvaluator.trimSpanOriginal(reference, source: trim,
                consumeWork: { try budget.charge(depth: $0) })
            let source = try OriginalTrimSpanParameterResolver.curve(trim.liftedCurve,
                from: span.lowerParameter, to: span.upperParameter, in: span.nativeDomain,
                tolerance: tolerance, budget: budget)
            return .curve(source, from: 0, to: 1)
        case .surface(.trimKnot(let reference)):
            let trim = try surfaceQueryEvaluator.trimOriginal(reference.trim, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            guard case .bSpline(let curve) = trim.parameterCurve,
                curve.knots.indices.contains(reference.knotIndex) else {
                throw FeatureEvaluationError.missingInput("Original trim knot could not be resolved.")
            }
            try budget.charge()
            let knot = curve.knots[reference.knotIndex]
            let station = try OriginalTrimSpanParameterResolver.fraction(at: knot,
                in: curve.domain, tolerance: tolerance, budget: budget)
            return .curve(trim.liftedCurve, from: station, to: station)
        case .curve(.whole(let reference)):
            let source = try curveQueryEvaluator.resolveOriginalGeometry(reference, in: document,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
            return .curve(source.curve, from: source.startParameter, to: source.endParameter)
        default: stable = nil
        }
        if let stable {
            switch try document.originalTopologyReference(for: stable, tolerance: tolerance,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumSourceDepth,
                consumeWork: { try budget.charge(depth: $0) }, consumeStorage: budget.storageAdmission,
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth) {
            case .body(let id): return .body(id)
            case .face(let id): return .face(id)
            case .edge(let id): return .edge(id)
            case .vertex(let id): return .vertex(id)
            }
        }
        return .point(try point(for: selection, in: document).point)
    }

    public func angle(
        between first: SelectionReference,
        and second: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionAngleMeasurement {
        let a = try originalAngleDirection(for: first, in: document)
        let b = try originalAngleDirection(for: second, in: document)
        return try SelectionAngleMeasurement(first: a.point, second: b.point,
            firstDirectionBounds: a.bounds, secondDirectionBounds: b.bounds, tolerance: tolerance)
    }

    public func angle(between first: SelectionReference, and second: SelectionReference,
        in document: EvaluatedDocument, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil) throws -> SelectionAngleMeasurement {
        let resolver = OriginalBoundedSelectionAngleResolver(tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let a = try resolver.resolve(first, in: document)
        let b = try resolver.resolve(second, in: document)
        return try SelectionAngleMeasurement(first: a.point, second: b.point,
            firstDirectionBounds: a.bounds, secondDirectionBounds: b.bounds, tolerance: tolerance,
            consumeWork: { try consumeWork(0) })
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Original selection angle now consumes
    // certified direction boxes, but public station-resolution/projection
    // preparations still have opaque legacy accounting. Complete query work
    // publication requires their bounded original callback adapters as well.
    private func originalAngleDirection(for selection: SelectionReference, in document: EvaluatedDocument)
        throws -> (point: SelectionMeasurementPoint, bounds: CoordinateEnclosure3D) {
        try selection.validate(); try Task.checkCancellation()
        switch selection {
        case .subshape(let stable):
            let resolved: SelectionReference
            switch try document.topologyReference(for: stable) {
            case .edge: resolved = .edge(.whole(EdgeReference(subshape: stable)))
            case .face: resolved = .surface(.whole(SurfaceReference(subshape: stable)))
            case .body, .vertex: throw angleDirectionFailure()
            }
            var result = try originalAngleDirection(for: resolved, in: document)
            result.point.selection = selection
            return result
        case .edge(let reference):
            let frame: EdgeQueryFrame
            switch reference {
            case .whole(let edge): frame = try edgeQueryEvaluator.midpoint(of: edge, in: document)
            case .parameter(let parameter): frame = try edgeQueryEvaluator.frame(at: parameter, in: document)
            }
            let resolved = try edgeQueryEvaluator.resolve(frame.reference.edge, in: document)
            let range = try ScalarInterval(lower: frame.reference.parameter, upper: frame.reference.parameter)
            let derivative = try originalAngleCurveDerivative(resolved.curve, over: range)
            let bounds = try OriginalSelectionAngleBounds.scaled(derivative,
                sign: resolved.endParameter < resolved.startParameter ? -1 : 1)
            return (SelectionMeasurementPoint(selection: selection, point: frame.point,
                tangent: try OriginalSelectionAngleBounds.representative(bounds, tolerance: tolerance)), bounds)
        case .curve(let reference):
            let query: CurveQueryPoint
            switch reference {
            case .whole(let curve): query = try curveQueryEvaluator.midpoint(of: curve, in: document)
            case .parameter(let parameter): query = try curveQueryEvaluator.point(at: parameter, in: document)
            case .span(let span):
                let domain = try curveQueryEvaluator.span(span, in: document)
                query = try curveQueryEvaluator.point(at: .init(curve: span.curve,
                    parameter: (domain.lowerParameter+domain.upperParameter)*0.5), in: document)
            case .knot(let knot):
                query = try curveQueryEvaluator.point(at: .init(curve: knot.curve,
                    parameter: curveQueryEvaluator.knot(knot, in: document)), in: document)
            case .center, .controlPoint: throw angleDirectionFailure()
            }
            let original = try curveQueryEvaluator.resolve(query.reference.curve, in: document)
            let bounds: CoordinateEnclosure3D
            if let exact = original.exactCurve {
                bounds = try originalAngleCurveDerivative(exact,
                    over: ScalarInterval(lower: query.reference.parameter, upper: query.reference.parameter))
            } else {
                bounds = try originalPolylineAngleDirection(original.points, fraction: query.reference.parameter)
            }
            return (SelectionMeasurementPoint(selection: selection, point: query.point,
                tangent: try OriginalSelectionAngleBounds.representative(bounds, tolerance: tolerance)), bounds)
        case .surface(let reference):
            let parameterReference: SurfaceParameterReference
            switch reference {
            case .whole(let surface): parameterReference = try representativeFrame(for: surface, in: document).reference
            case .parameter(let parameter):
                try parameter.validate()
                parameterReference = parameter
            case .span(let span):
                let representative = try representativeFrame(for: span.surface, in: document)
                let domain = try surfaceQueryEvaluator.span(span, in: document)
                let middle = (domain.lowerParameter+domain.upperParameter)*0.5
                parameterReference = .init(surface: span.surface,
                    u: span.direction == .u ? middle : representative.reference.u,
                    v: span.direction == .v ? middle : representative.reference.v)
            case .knot(let knot):
                let representative = try representativeFrame(for: knot.surface, in: document)
                let parameter = try surfaceQueryEvaluator.knot(knot, in: document)
                parameterReference = .init(surface: knot.surface,
                    u: knot.direction == .u ? parameter : representative.reference.u,
                    v: knot.direction == .v ? parameter : representative.reference.v)
            case .trim(let trim): return try originalTrimAngleDirection(trim, station: nil, selection: selection, in: document)
            case .trimSpan(let span):
                let result = try surfaceQueryEvaluator.trimCurve(span.trim, in: document)
                guard case .bSpline(let curve) = result.parameterCurve else { throw angleDirectionFailure() }
                return try originalTrimAngleDirection(span.trim,
                    station: trimSpanParameter(span.spanIndex, on: curve), selection: selection, in: document)
            case .trimKnot(let knot):
                let result = try surfaceQueryEvaluator.trimCurve(knot.trim, in: document)
                guard case .bSpline(let curve) = result.parameterCurve, curve.knots.indices.contains(knot.knotIndex) else {
                    throw angleDirectionFailure()
                }
                return try originalTrimAngleDirection(knot.trim,
                    station: curve.knots[knot.knotIndex], selection: selection, in: document)
            case .controlPoint: throw angleDirectionFailure()
            }
            let resolved = try surfaceQueryEvaluator.resolve(parameterReference.surface, in: document)
            let box = SurfaceParameterBox(u: try .init(lower: parameterReference.u, upper: parameterReference.u),
                v: try .init(lower: parameterReference.v, upper: parameterReference.v))
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: resolved.surface,
                tolerance: tolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: 32,
                consumeWork: { try Task.checkCancellation() }, maximumAlgebraicDepth: 32)
            var support = resolved.surface
            var nativeStation = box
            var chartImages: [OriginalImageSurface3D] = []
            var sourceDepth = 0
            while true {
                try Task.checkCancellation()
                switch support {
                case .procedural(.originalImage(let image)):
                    guard sourceDepth < 16 else { throw angleDirectionFailure() }
                    sourceDepth += 1
                    nativeStation = try image.sourceParameterBounds(over: nativeStation, tolerance: tolerance,
                        consumeWork: { try Task.checkCancellation() })
                    chartImages.append(image); support = image.source
                case .procedural(.originalAffineWord(let image)):
                    guard sourceDepth < 16 else { throw angleDirectionFailure() }
                    sourceDepth += 1; support = image.source
                default: break
                }
                if case .procedural(.originalImage) = support { continue }
                if case .procedural(.originalAffineWord) = support { continue }
                break
            }
            var coneNappe: OriginalAnalyticPoleNormal.ConeNappe?
            if case .analytic(.cone) = support, nativeStation.v.lower == 0, nativeStation.v.upper == 0 {
                var extent = try FaceParameterExtentResolver(maximumSubdivisionDepth: 32,
                    consumeWork: { _ in try Task.checkCancellation() }).bounds(
                        for: resolved.faceID, in: document.brep, tolerance: tolerance)
                for image in chartImages {
                    extent = try image.sourceParameterBounds(over: extent, tolerance: tolerance,
                        consumeWork: { try Task.checkCancellation() })
                }
                if extent.v.lower >= 0, extent.v.upper > 0 { coneNappe = .positive }
                else if extent.v.upper <= 0, extent.v.lower < 0 { coneNappe = .negative }
                else { throw angleDirectionFailure() }
            }
            var usage = OriginalSourceProofAdmission(consumeWork: { _ in try Task.checkCancellation() })
            let field = try prepared.unitNormalBounds(over: box, tolerance: tolerance,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: 32, remainingSourceDepth: 16,
                coneNappe: coneNappe, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage)
            let bounds = CoordinateEnclosure3D(x: try .init(lower: field.x.lower, upper: field.x.upper),
                y: try .init(lower: field.y.lower, upper: field.y.upper),
                z: try .init(lower: field.z.lower, upper: field.z.upper))
            let position = try prepared.positionBounds(over: box, tolerance: tolerance,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: 32, remainingSourceDepth: 16,
                consumeWork: { try Task.checkCancellation() })
            let point = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
            try point.validate()
            return (SelectionMeasurementPoint(selection: selection, point: point,
                normal: try OriginalSelectionAngleBounds.representative(bounds, tolerance: tolerance)), bounds)
        case .sketchPoint: throw angleDirectionFailure()
        }
    }

    private func originalAngleCurveDerivative(_ curve: Curve3D, over range: ScalarInterval) throws -> CoordinateEnclosure3D {
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, consumeWork: { try Task.checkCancellation() }, maximumAlgebraicDepth: 32)
        let original = try prepared.closedNativeJets(over: range, tolerance: tolerance,
            maximumSpanCount: 1_048_576, maximumSubdivisionDepth: 32, remainingSourceDepth: 16,
            consumeWork: { try Task.checkCancellation() })
        var x: OutwardScalarInterval?, y: OutwardScalarInterval?, z: OutwardScalarInterval?
        for owner in original.spans {
            try Task.checkCancellation()
            x = x.map { $0.union(owner.jet.x.derivativeU) } ?? owner.jet.x.derivativeU
            y = y.map { $0.union(owner.jet.y.derivativeU) } ?? owner.jet.y.derivativeU
            z = z.map { $0.union(owner.jet.z.derivativeU) } ?? owner.jet.z.derivativeU
        }
        guard let x, let y, let z else { throw angleDirectionFailure() }
        return .init(x: try .init(lower: x.lower, upper: x.upper), y: try .init(lower: y.lower, upper: y.upper),
            z: try .init(lower: z.lower, upper: z.upper))
    }

    private func originalTrimAngleDirection(_ trim: SurfaceTrimReference, station: Double?,
        selection: SelectionReference, in document: EvaluatedDocument)
        throws -> (point: SelectionMeasurementPoint, bounds: CoordinateEnclosure3D) {
        let result = try surfaceQueryEvaluator.trimCurve(trim, in: document)
        let surface = try surfaceQueryEvaluator.resolve(trim.surface, in: document).surface
        let fraction: ScalarInterval
        if let station {
            guard case .bSpline(let curve) = result.parameterCurve,
                case .closed(let lower, let upper) = try curve.domain, lower <= station, station <= upper else {
                throw angleDirectionFailure()
            }
            if station == lower { fraction = try .init(lower: 0, upper: 0) }
            else if station == upper { fraction = try .init(lower: 1, upper: 1) }
            else {
                guard let value = (OutwardScalarInterval.exact(station) - .exact(lower))
                    .divided(by: .exact(upper) - .exact(lower)) else { throw angleDirectionFailure() }
                fraction = try .init(lower: value.lower, upper: value.upper)
            }
        } else { fraction = try .init(lower: 0.5, upper: 0.5) }
        let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: result.parameterCurve)
        let bounds = try originalAngleCurveDerivative(.surfaceLift(lift), over: fraction)
        let point = try lift.point(atNormalizedFraction: fraction.midpoint, tolerance: tolerance)
        return (SelectionMeasurementPoint(selection: selection, point: point,
            tangent: try OriginalSelectionAngleBounds.representative(bounds, tolerance: tolerance)), bounds)
    }

    private func originalPolylineAngleDirection(_ points: [Point3D], fraction: Double) throws -> CoordinateEnclosure3D {
        guard points.count >= 2 else { throw angleDirectionFailure() }
        var length = 0.0
        for index in 0..<(points.count-1) {
            try Task.checkCancellation(); length += (points[index+1]-points[index]).length
        }
        guard length.isFinite, length > tolerance.distance else { throw angleDirectionFailure() }
        let target = length*fraction
        var traversed = 0.0
        for index in 0..<(points.count-1) {
            try Task.checkCancellation()
            let segmentLength = (points[index+1]-points[index]).length
            guard segmentLength > tolerance.distance else { continue }
            if target <= traversed+segmentLength || index == points.count-2 {
                return try OriginalSelectionAngleBounds.difference(points[index+1], points[index])
            }
            traversed += segmentLength
        }
        throw angleDirectionFailure()
    }

    private func angleDirectionFailure() -> KernelError {
        .init(phase: .validation, code: .invalidInput, tolerance: tolerance,
            message: "Selection angle measurement requires an original nonzero tangent or normal direction at the selected station.")
    }

    private func topologyPoint(
        for reference: TopologyReference,
        stableReference: StableSubshapeReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        switch reference {
        case let .body(bodyID):
            let bounds = try BRepBodyBoundingBoxBuilder().bounds(
                for: bodyID,
                in: document.brep,
                tolerance: tolerance
            )
            return SelectionMeasurementPoint(selection: selection, point: bounds.center)
        case .face:
            return try surfacePoint(
                for: .whole(SurfaceReference(subshape: stableReference)),
                selection: selection,
                in: document
            )
        case .edge:
            return try edgePoint(
                for: .whole(EdgeReference(subshape: stableReference)),
                selection: selection,
                in: document
            )
        case let .vertex(vertexID):
            guard let vertex = document.brep.vertices[vertexID] else {
                throw FeatureEvaluationError.missingInput("Selection vertex could not be resolved.")
            }
            return SelectionMeasurementPoint(selection: selection, point: vertex.point)
        }
    }

    private func edgePoint(
        for reference: EdgeSubobjectReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let frame: EdgeQueryFrame
        switch reference {
        case let .whole(edge):
            frame = try edgeQueryEvaluator.midpoint(of: edge, in: document)
        case let .parameter(parameter):
            frame = try edgeQueryEvaluator.frame(at: parameter, in: document)
        }
        return SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            tangent: frame.tangent,
            curvature: frame.curvature
        )
    }

    private func curvePoint(
        for reference: CurveSubobjectReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        switch reference {
        case let .whole(curve):
            return try measurementPoint(
                from: curveQueryEvaluator.midpoint(of: curve, in: document),
                selection: selection
            )
        case let .parameter(parameter):
            return try measurementPoint(
                from: curveQueryEvaluator.point(at: parameter, in: document),
                selection: selection
            )
        case let .center(center):
            return SelectionMeasurementPoint(
                selection: selection,
                point: try curveQueryEvaluator.center(center, in: document)
            )
        case let .span(span):
            let spanResult = try curveQueryEvaluator.span(span, in: document)
            let parameter = (spanResult.lowerParameter + spanResult.upperParameter) * 0.5
            return try measurementPoint(
                from: curveQueryEvaluator.point(
                    at: CurveParameterReference(curve: span.curve, parameter: parameter),
                    in: document
                ),
                selection: selection
            )
        case let .controlPoint(controlPoint):
            return SelectionMeasurementPoint(
                selection: selection,
                point: try curveQueryEvaluator.controlPoint(controlPoint, in: document)
            )
        case let .knot(knot):
            let parameter = try curveQueryEvaluator.knot(knot, in: document)
            return try measurementPoint(
                from: curveQueryEvaluator.point(
                    at: CurveParameterReference(curve: knot.curve, parameter: parameter),
                    in: document
                ),
                selection: selection
            )
        }
    }

    private func sketchPoint(
        for reference: SketchPointSelectionReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        guard let feature = document.document.designGraph.nodes[reference.featureID],
              case let .sketch(sketch) = feature.operation else {
            throw FeatureEvaluationError.missingInput("Sketch point selection feature could not be resolved.")
        }
        guard let entity = sketch.entities[reference.entityID] else {
            throw FeatureEvaluationError.missingInput("Sketch point selection entity could not be resolved.")
        }
        guard case let .point(point) = entity else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sketch point selection reference must target a sketch point entity."
            )
        }
        let resolvedPoint = try resolveSketchPoint(point, parameters: document.parameters)
        return SelectionMeasurementPoint(
            selection: selection,
            point: try mapTo3D(resolvedPoint, on: sketch.plane)
        )
    }

    private func surfacePoint(
        for reference: SurfaceSubobjectReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        switch reference {
        case let .whole(surface):
            return try measurementPoint(
                from: representativeFrame(for: surface, in: document),
                selection: selection
            )
        case let .parameter(parameter):
            return try measurementPoint(
                from: surfaceQueryEvaluator.frame(at: parameter, in: document),
                selection: selection
            )
        case let .span(span):
            return try surfaceSpanPoint(for: span, selection: selection, in: document)
        case let .controlPoint(controlPoint):
            return SelectionMeasurementPoint(
                selection: selection,
                point: try surfaceQueryEvaluator.controlPoint(controlPoint, in: document)
            )
        case let .knot(knot):
            return try surfaceKnotPoint(for: knot, selection: selection, in: document)
        case let .trim(trim):
            return try surfaceTrimPoint(for: trim, selection: selection, in: document)
        case let .trimSpan(span):
            return try surfaceTrimSpanPoint(for: span, selection: selection, in: document)
        case let .trimKnot(knot):
            return try surfaceTrimKnotPoint(for: knot, selection: selection, in: document)
        }
    }

    private func surfaceSpanPoint(
        for span: SurfaceSpanReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let representative = try representativeFrame(for: span.surface, in: document)
        let spanResult = try surfaceQueryEvaluator.span(span, in: document)
        let spanParameter = (spanResult.lowerParameter + spanResult.upperParameter) * 0.5
        let parameter: SurfaceParameterReference
        switch span.direction {
        case .u:
            parameter = SurfaceParameterReference(
                surface: span.surface,
                u: spanParameter,
                v: representative.reference.v
            )
        case .v:
            parameter = SurfaceParameterReference(
                surface: span.surface,
                u: representative.reference.u,
                v: spanParameter
            )
        }
        return try measurementPoint(
            from: surfaceQueryEvaluator.frame(at: parameter, in: document),
            selection: selection
        )
    }

    private func surfaceKnotPoint(
        for knot: SurfaceKnotReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let representative = try representativeFrame(for: knot.surface, in: document)
        let knotParameter = try surfaceQueryEvaluator.knot(knot, in: document)
        let parameter: SurfaceParameterReference
        switch knot.direction {
        case .u:
            parameter = SurfaceParameterReference(
                surface: knot.surface,
                u: knotParameter,
                v: representative.reference.v
            )
        case .v:
            parameter = SurfaceParameterReference(
                surface: knot.surface,
                u: representative.reference.u,
                v: knotParameter
            )
        }
        return try measurementPoint(
            from: surfaceQueryEvaluator.frame(at: parameter, in: document),
            selection: selection
        )
    }

    private func surfaceTrimPoint(
        for trim: SurfaceTrimReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let result = try surfaceQueryEvaluator.trimCurve(trim, in: document)
        let parameter = try result.parameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
        let frame = try surfaceFrame(for: parameter, on: trim.surface, in: document)
        let tangent = try trimTangent(from: result.parameterCurve, on: trim.surface, in: document)
        return SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            tangent: tangent,
            normal: frame.normal,
            curvature: frame.meanCurvature
        )
    }

    private func surfaceTrimSpanPoint(
        for span: SurfaceTrimSpanReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let result = try surfaceQueryEvaluator.trimCurve(span.trim, in: document)
        guard case let .bSpline(curve) = result.parameterCurve else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface trim p-curve span selection requires a B-spline parameter curve."
            )
        }
        let curveParameter = try trimSpanParameter(span.spanIndex, on: curve)
        return try surfaceTrimParameterPoint(
            curveParameter: curveParameter,
            curve: curve,
            trim: span.trim,
            selection: selection,
            in: document
        )
    }

    private func surfaceTrimKnotPoint(
        for knot: SurfaceTrimKnotReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let result = try surfaceQueryEvaluator.trimCurve(knot.trim, in: document)
        guard case let .bSpline(curve) = result.parameterCurve else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface trim p-curve knot selection requires a B-spline parameter curve."
            )
        }
        guard curve.knots.indices.contains(knot.knotIndex) else {
            throw FeatureEvaluationError.missingInput("Surface trim p-curve knot index could not be resolved.")
        }
        let curveParameter = curve.knots[knot.knotIndex]
        guard try curve.domain.contains(curveParameter, tolerance: tolerance) else {
            throw FeatureEvaluationError.missingInput("Surface trim p-curve knot is outside the curve domain.")
        }
        return try surfaceTrimParameterPoint(
            curveParameter: curveParameter,
            curve: curve,
            trim: knot.trim,
            selection: selection,
            in: document
        )
    }

    private func surfaceTrimParameterPoint(
        curveParameter: Double,
        curve: BSplineCurve2D,
        trim: SurfaceTrimReference,
        selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        let point = try curve.point(at: curveParameter, tolerance: tolerance)
        let parameter = SurfaceParameter(u: point.x, v: point.y)
        let frame = try surfaceFrame(for: parameter, on: trim.surface, in: document)
        let tangent = try surfaceTrimTangent(from: curve, at: curveParameter, using: frame)
        return SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            tangent: tangent,
            normal: frame.normal,
            curvature: frame.meanCurvature
        )
    }

    private func trimSpanParameter(_ spanIndex: Int, on curve: BSplineCurve2D) throws -> Double {
        try trimSpanBounds(spanIndex, on: curve).midpoint
    }

    private func trimSpanBounds(_ spanIndex: Int, on curve: BSplineCurve2D) throws -> ScalarInterval {
        try curve.validate(tolerance: tolerance)
        let lowerIndex = curve.degree
        let upperIndex = curve.knots.count - curve.degree - 1
        guard lowerIndex < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Surface trim pcurve has no queryable knot spans.")
        }
        var ordinal = 0
        for index in lowerIndex..<upperIndex {
            let lower = curve.knots[index], upper = curve.knots[index + 1]
            guard upper - lower > tolerance.distance else { continue }
            if ordinal == spanIndex { return try ScalarInterval(lower: lower, upper: upper) }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Surface trim pcurve span index could not be resolved.")
    }

    private func surfaceFrame(
        for parameter: SurfaceParameter,
        on surface: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceQueryFrame {
        try surfaceQueryEvaluator.frame(
            at: SurfaceParameterReference(surface: surface, u: parameter.u, v: parameter.v),
            in: document
        )
    }

    private func surfaceTrimTangent(
        from curve: BSplineCurve2D,
        at curveParameter: Double,
        using frame: SurfaceQueryFrame
    ) throws -> Vector3D? {
        let geometry = try curve.differentialGeometry(at: curveParameter, tolerance: tolerance)
        let tangent = (frame.tangentU * geometry.firstDerivative.x)
            + (frame.tangentV * geometry.firstDerivative.y)
        try tangent.validate()
        let length = tangent.length
        guard length.isFinite else {
            throw GeometryError.invalidVectorLength(length)
        }
        guard length > tolerance.distance else {
            return nil
        }
        return tangent / length
    }

    private func representativeFrame(
        for reference: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceQueryFrame {
        let resolved = try surfaceQueryEvaluator.resolve(reference, in: document)
        if let centroid = centroidOfFace(resolved.faceID, in: document) {
            return try surfaceQueryEvaluator.closestPoint(
                to: centroid,
                on: reference,
                in: document
            ).frame
        }
        let parameter = try midpointParameter(on: resolved.surface, reference: reference)
        return try surfaceQueryEvaluator.frame(at: parameter, in: document)
    }

    private func centroidOfFace(_ faceID: FaceID, in document: EvaluatedDocument) -> Point3D? {
        guard let face = document.brep.faces[faceID] else {
            return nil
        }
        var points: [Point3D] = []
        for loopID in face.loops {
            guard let loop = document.brep.loops[loopID] else {
                continue
            }
            for orientedEdge in loop.edges {
                guard let edge = document.brep.edges[orientedEdge.edgeID] else {
                    continue
                }
                let vertexID = startVertexID(for: orientedEdge, edge: edge)
                guard let vertex = document.brep.vertices[vertexID] else {
                    continue
                }
                points.append(vertex.point)
            }
        }
        guard points.isEmpty == false else {
            return nil
        }
        let scale = 1.0 / Double(points.count)
        let sum = points.reduce((x: 0.0, y: 0.0, z: 0.0)) { partial, point in
            (
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        return Point3D(x: sum.x * scale, y: sum.y * scale, z: sum.z * scale)
    }

    private func midpointParameter(
        on surface: Surface3D,
        reference: SurfaceReference
    ) throws -> SurfaceParameterReference {
        SurfaceParameterReference(
            surface: reference,
            u: try midpoint(of: surface.uDomain),
            v: try midpoint(of: surface.vDomain)
        )
    }

    private func midpoint(of domain: ParameterDomain) throws -> Double {
        switch domain {
        case .unbounded:
            return 0.0
        case let .closed(lower, upper):
            return (lower + upper) * 0.5
        case let .periodic(period):
            return period * 0.5
        }
    }

    private func trimTangent(
        from parameterCurve: SurfaceParameterCurve,
        on surface: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> Vector3D {
        let lowerFraction = 0.5 - 1.0e-5
        let upperFraction = 0.5 + 1.0e-5
        let lower = try parameterCurve.parameter(atNormalizedFraction: lowerFraction, tolerance: tolerance)
        let upper = try parameterCurve.parameter(atNormalizedFraction: upperFraction, tolerance: tolerance)
        let lowerFrame = try surfaceQueryEvaluator.frame(
            at: SurfaceParameterReference(surface: surface, u: lower.u, v: lower.v),
            in: document
        )
        let upperFrame = try surfaceQueryEvaluator.frame(
            at: SurfaceParameterReference(surface: surface, u: upper.u, v: upper.v),
            in: document
        )
        return try (upperFrame.point - lowerFrame.point).normalized(tolerance: tolerance.distance)
    }

    private func measurementPoint(
        from point: CurveQueryPoint,
        selection: SelectionReference
    ) throws -> SelectionMeasurementPoint {
        SelectionMeasurementPoint(
            selection: selection,
            point: point.point,
            tangent: point.tangent,
            curvature: point.curvature
        )
    }

    private func supportsProjectionDistancePoint(
        _ selection: SelectionReference,
        in document: EvaluatedDocument
    ) throws -> Bool {
        switch selection {
        case let .subshape(stableReference):
            let topologyReference = try document.topologyReference(for: stableReference)
            if case .vertex = topologyReference { return true }
            return false
        case .sketchPoint:
            return true
        case let .edge(edge):
            if case .parameter = edge {
                return true
            }
            return false
        case let .curve(curve):
            switch curve {
            case .parameter, .center, .controlPoint, .knot:
                return true
            case .whole, .span:
                return false
            }
        case let .surface(surface):
            switch surface {
            case .parameter, .controlPoint, .trimSpan, .trimKnot:
                return true
            case .whole, .span, .knot, .trim:
                return false
            }
        }
    }

    private func measurementPoint(
        from frame: SurfaceQueryFrame,
        selection: SelectionReference
    ) throws -> SelectionMeasurementPoint {
        SelectionMeasurementPoint(
            selection: selection,
            point: frame.point,
            normal: frame.normal,
            curvature: frame.meanCurvature
        )
    }

    private func resolveSketchPoint(
        _ point: SketchPoint,
        parameters: ResolvedParameterTable
    ) throws -> Point2D {
        let resolver = ParameterResolver()
        let x = try resolver.evaluate(point.x, parameters: parameters, variables: [:])
        let y = try resolver.evaluate(point.y, parameters: parameters, variables: [:])
        guard x.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "selection.sketchPoint.x",
                expected: .length,
                actual: x.kind
            )
        }
        guard y.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "selection.sketchPoint.y",
                expected: .length,
                actual: y.kind
            )
        }
        guard x.value.isFinite else {
            throw GeometryError.invalidCoordinate(x.value)
        }
        guard y.value.isFinite else {
            throw GeometryError.invalidCoordinate(y.value)
        }
        return Point2D(x: x.value, y: y.value)
    }

    private func mapTo3D(_ point: Point2D, on plane: SketchPlane) throws -> Point3D {
        switch plane {
        case .xy:
            return Point3D(x: point.x, y: point.y, z: 0.0)
        case .yz:
            return Point3D(x: 0.0, y: point.x, z: point.y)
        case .zx:
            return Point3D(x: point.y, y: 0.0, z: point.x)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return plane.origin + (u * point.x) + (v * point.y)
        }
    }

    private func startVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }
}
