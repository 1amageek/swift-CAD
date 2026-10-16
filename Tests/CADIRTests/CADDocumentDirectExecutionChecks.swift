import CADCore
import CADGeometry
import CADIR
import Synchronization

enum CADDocumentDirectExecutionChecks {
    struct Failure: Error { let message: String }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws {
            let count = state.withLock { value in value += 1; return value }
            if count == stop { throw CancellationError() }
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }

    private static func original(_ error: any Error) -> any Error {
        if let value = error as? OriginalQueryFailure { return original(value.originalError) }
        if let value = error as? ExactScalarFailure {
            if case .admissionRejected(let cause) = value { return original(cause) }
            if case .cancelled = value { return CancellationError() }
        }
        return error
    }

    private static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: 256,
            maximumTransportDepth: 256, maximumSubdivisionDepth: 32))
    }

    static func document() -> CADDocument {
        let documentID = DocumentID()
        let length = Parameter(name: "width", expression: .constant(.length(1, unit: .meter)), kind: .length)
        let derived = Parameter(name: "derivedWidth",
            expression: .add(.reference(length.id), .constant(.length(0, unit: .meter))), kind: .length)
        let parameters = ParameterTable(parameters: [length.id: length, derived.id: derived])
        let featureID = FeatureID()
        let feature = FeatureNode(id: featureID, operation: .primitive(.init(definition: .box(.init(
            width: .reference(derived.id), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let product = AssemblyProduct(identifier: "part", name: "retained source")
        let formation = AssemblyProductFormation(productID: product.id)
        let definition = AssemblyDefinition(formationID: formation.id, features: [featureID])
        let assembly = DocumentAssembly(products: [product], formations: [formation],
            definitions: [definition], roots: [AssemblyOccurrence(definitionID: definition.id)])
        let target = ProductAttributeTarget(kind: .part, definitionID: definition.id)
        let attributes = ProductAttributes(assignments: [.init(target: target,
            value: .density(.init(kilogramsPerCubicMeter: 1000)))],
            layers: [.init(name: "source layer", members: [target])])
        let owner = DocumentObjectReference(documentID: documentID)
        let foundation = DocumentFoundation(attributes: [
            .init(name: "source values", owner: owner, value: .reals([1, 2, 3, 4])),
            .init(name: "source feature", owner: owner,
                value: .reference(.init(documentID: documentID, target: .feature(featureID))))
        ])
        let reference = StableSubshapeReference(subshapeID: .init(featureID: featureID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin))
        let dimension = SelectionDimension(kind: .distance, first: .subshape(reference),
            second: .subshape(reference), target: .reference(derived.id))
        return CADDocument(id: documentID, units: .meters, parameters: parameters,
            designGraph: .init(nodes: [featureID: feature], order: [featureID]),
            selectionDimensions: [dimension], documentFoundation: foundation, assembly: assembly,
            productAttributes: attributes,
            metadata: .init(name: "complete validation caller", createdAtReferenceDate: 0, updatedAtReferenceDate: 0))
    }

    static func validNonemptyDocumentPreservesOriginalValidation() throws {
        let source = document()
        try require(source.assembly?.roots.count == 1 && source.productAttributes.assignments.count == 1,
            "The control must exercise real nonempty assembly and product validation.")
        try source.validate(tolerance: .standard)
        var caller = try execution(OriginalQueryBudget())
        let result = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
        try require(result == nil && caller.activeContributionCount == 0,
            "Complete source validation changed its original optional result or leaked a contribution scope.")
    }

    static func zeroCallerWorkRefusesWholeDocumentPublication() throws {
        let source = document()
        let budget = try OriginalQueryBudget(workLimit: 0)
        var caller = try execution(budget)
        do {
            _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
            throw Failure(message: "Complete document validation escaped its zero-work caller through ordinary child roots.")
        } catch {
            guard let scalar = original(error) as? ExactScalarFailure,
                case .resourceLimit(.work) = scalar else { throw error }
        }
        try require(budget.snapshot.work == 0 && caller.activeContributionCount == 0,
            "Rejected document work was committed or its child scope escaped.")
    }

    static func zeroCallerStorageRefusesWholeDocumentPublication() throws {
        let source = document()
        let budget = try OriginalQueryBudget(storageByteLimit: 0)
        var caller = try execution(budget)
        do {
            _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
            throw Failure(message: "Complete document validation allocated scratch storage outside its caller.")
        } catch {
            guard let scalar = original(error) as? ExactScalarFailure,
                case .resourceLimit(.storage) = scalar else { throw error }
        }
        try require(budget.snapshot.storageBytes == 0 && caller.activeContributionCount == 0,
            "Rejected typed document storage was committed or its child scope escaped.")
    }

    static func measuredInteriorCallerCancellationRefusesPublication() throws {
        let source = document()
        let baseline = Checkpoints()
        var uninterrupted = try execution(OriginalQueryBudget(checkpoint: { try baseline.check() }))
        _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &uninterrupted)
        let stop = max(3, baseline.count / 2)
        let interrupted = Checkpoints(stop: stop)
        var caller = try execution(OriginalQueryBudget(checkpoint: { try interrupted.check() }))
        do {
            _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
            throw Failure(message: "Document children never reached the interior caller cancellation checkpoint.")
        } catch {
            guard original(error) is CancellationError else { throw error }
        }
        try require(interrupted.count == stop && caller.activeContributionCount == 0,
            "Document cancellation changed its actual checkpoint or leaked an invocation scope.")
    }
    private static func queryFailure(_ error: any Error) -> OriginalQueryFailure? {
        if let value = error as? OriginalQueryFailure { return value }
        if let value = error as? ExactScalarFailure,
            case .admissionRejected(let cause) = value { return queryFailure(cause) }
        return nil
    }

    static func measuredExactWorkAndStorageCeilings() throws {
        let source = document()
        let baselineBudget = try OriginalQueryBudget(allocationPolicy: .bytes)
        var baseline = try execution(baselineBudget)
        _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &baseline)
        let needed = baselineBudget.snapshot
        try require(needed.work > 0 && needed.storageBytes > 0, "The measured validation must own real work and typed scratch storage.")
        let exactBudget = try OriginalQueryBudget(workLimit: needed.work, storageByteLimit: needed.storageBytes, allocationPolicy: .bytes)
        var exact = try execution(exactBudget)
        _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &exact)
        try require(exactBudget.snapshot.work == needed.work && exactBudget.snapshot.storageBytes == needed.storageBytes,
            "An exact measured document allowance changed the admitted operation sequence.")
        for axis in [OriginalQueryResourceAxis.work, .storageBytes] {
            let limit = axis == .work ? needed.work - 1 : needed.storageBytes - 1
            let budget = try OriginalQueryBudget(workLimit: axis == .work ? limit : needed.work,
                storageByteLimit: axis == .storageBytes ? limit : needed.storageBytes, allocationPolicy: .bytes)
            var caller = try execution(budget)
            var published = false
            do {
                _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
                published = true
                throw Failure(message: "Document validation published with one less than its measured allowance.")
            } catch {
                guard let failure = queryFailure(error), let resource = failure.context.resource,
                    resource.axis == axis, resource.limit == .known(limit),
                    case .known(let used) = resource.used, case .known(let requested) = resource.requested,
                    used <= limit, requested > limit - used else { throw error }
            }
            try require(!published && caller.activeContributionCount == 0,
                "A rejected exact document request published or leaked its child scope.")
            let rejected = budget.snapshot
            try require((axis == .work ? rejected.work : rejected.storageBytes) <= limit,
                "A refused document debit mutated its rejected counter.")
        }
    }

    static func independentSourceAncestryAndNumericAxes() throws {
        let source = document()
        var baseline = try execution(OriginalQueryBudget())
        _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &baseline)
        let sourceDepth = baseline.sourceDepth
        let valueDepth = baseline.valueDepth, coefficientDepth = baseline.coefficientDepth
        let geometricDepth = baseline.geometricDepth, transportDepth = baseline.transportDepth
        try require(sourceDepth > 0, "Authored expression and owner ancestry was never admitted.")
        let limits = try OriginalQueryExecutionLimits(maximumValueDepth: valueDepth, maximumCoefficientDepth: coefficientDepth,
            remainingSourceDepth: sourceDepth, maximumTransportDepth: transportDepth, maximumSubdivisionDepth: geometricDepth)
        var exact = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: limits)
        _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &exact)
        try require(exact.sourceDepth == sourceDepth && exact.valueDepth == valueDepth && exact.coefficientDepth == coefficientDepth &&
            exact.geometricDepth == geometricDepth && exact.transportDepth == transportDepth,
            "Document validation merged independent ancestry, numeric, transport or subdivision axes.")
        var shallow = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(
            maximumValueDepth: valueDepth, maximumCoefficientDepth: coefficientDepth,
            remainingSourceDepth: sourceDepth - 1, maximumTransportDepth: transportDepth,
            maximumSubdivisionDepth: geometricDepth))
        do {
            _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &shallow)
            throw Failure(message: "Document validation escaped its actual source ancestry ceiling.")
        } catch {
            guard let failure = queryFailure(error), let resource = failure.context.resource,
                resource.axis == .sourceDepth, resource.limit == .known(sourceDepth - 1) else { throw error }
        }
        try require(shallow.activeContributionCount == 0, "Source ancestry rejection leaked a local scope.")
    }

    static func selectedContributionAndScopeRestoration() throws {
        let source = document()
        var baseline = try execution(OriginalQueryBudget(allocationPolicy: .bytes))
        let baselineHandle = try baseline.makeContributionHandle(allocationPolicy: .bytes)
        try baseline.withContributionScope(baselineHandle) { caller in
            _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
            try require(caller.activeContributionCount == 1, "A child validation discarded its enclosing contribution.")
        }
        let needed = baselineHandle.snapshot.work
        try require(needed > 0 && baseline.activeContributionCount == 0,
            "The selected document contribution did not own its actual work or restore its parent.")
        for limit in [needed, needed - 1] {
            var caller = try execution(OriginalQueryBudget(allocationPolicy: .bytes))
            let handle = try caller.makeContributionHandle(workLimit: limit, allocationPolicy: .bytes)
            var published = false
            do {
                try caller.withContributionScope(handle) { caller in
                    _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
                }
                published = true
                try require(limit == needed, "A selected one-less document contribution was ignored.")
            } catch {
                guard limit == needed - 1, let failure = queryFailure(error), let resource = failure.context.resource,
                    resource.axis == .work, resource.limit == .known(limit) else { throw error }
            }
            try require(published == (limit == needed) && handle.snapshot.work <= limit && caller.activeContributionCount == 0,
                "Selected document work was charged outside its owner, overcommitted, or leaked its scope.")
        }
    }

    static func originalInvalidOrderAndCopyLifetime() throws {
        let source = document()
        let retained = source
        var invalid = source
        let parameter = Parameter(name: "mismatched", expression: .constant(.scalar(1)), kind: .scalar)
        let wrongKey = ParameterID()
        invalid.parameters = ParameterTable(parameters: [wrongKey: parameter])
        invalid.designGraph.order.append(invalid.designGraph.order[0])
        let foreign = DocumentObjectReference(documentID: DocumentID())
        invalid.documentFoundation = DocumentFoundation(attributes: [.init(name: "foreign", owner: foreign, value: .boolean(true))])
        if var assembly = invalid.assembly { assembly.roots = []; invalid.assembly = assembly }
        var caller = try execution(OriginalQueryBudget())
        do {
            _ = try invalid.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
            throw Failure(message: "Invalid parameter identities were accepted.")
        } catch {
            guard let failure = original(error) as? ParameterError,
                failure == .tableKeyMismatch(key: wrongKey, parameterID: parameter.id) else { throw error }
        }
        invalid.parameters = source.parameters
        var graphCaller = try execution(OriginalQueryBudget())
        do {
            _ = try invalid.validate(tolerance: .standard, independentShapeLimits: .standard, using: &graphCaller)
            throw Failure(message: "Duplicate graph order was accepted.")
        } catch {
            guard let failure = original(error) as? FeatureEvaluationError,
                failure == .invalidGraph("Feature order contains duplicate IDs.") else { throw error }
        }
        invalid.designGraph = source.designGraph
        var foundationCaller = try execution(OriginalQueryBudget())
        do {
            _ = try invalid.validate(tolerance: .standard, independentShapeLimits: .standard, using: &foundationCaller)
            throw Failure(message: "Foreign foundation ownership was accepted.")
        } catch {
            guard let failure = original(error) as? DocumentFoundationError,
                failure == .foreignOwner(foreign) else { throw error }
        }
        try require(source == retained && source.assembly?.roots.count == 1,
            "Failed document validation mutated its retained authored source through a COW copy.")
        var retainedCaller = try execution(OriginalQueryBudget())
        _ = try retained.validate(tolerance: .standard, independentShapeLimits: .standard, using: &retainedCaller)
    }

    static func terminalCallerCancellationRefusesPublication() throws {
        let source = document()
        let baseline = Checkpoints()
        var complete = try execution(OriginalQueryBudget(checkpoint: { try baseline.check() }))
        _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &complete)
        let stop = baseline.count
        let terminal = Checkpoints(stop: stop)
        var caller = try execution(OriginalQueryBudget(checkpoint: { try terminal.check() }))
        var published = false
        do {
            _ = try source.validate(tolerance: .standard, independentShapeLimits: .standard, using: &caller)
            published = true
            throw Failure(message: "The terminal document checkpoint published after cancellation.")
        } catch {
            guard original(error) is CancellationError else { throw error }
        }
        try require(!published && terminal.count == stop && caller.activeContributionCount == 0,
            "Terminal document cancellation did not stop at its measured final caller checkpoint.")
    }

    static func structuralHashAndFixedScratchUseCallerAdmission() throws {
        try faceRoleHashWork()
        try surfaceDomainScratch()
        try meshNormalScratch()
        try assemblySourceCountScratch()
    }

    private static func faceRoleHashWork() throws {
        let featureID = FeatureID()
        let shortRole = "f"
        let longRole = String(repeating: "f", count: 257)
        func feature(_ role: String) -> FaceRebuildFeature {
            FaceRebuildFeature(target: .init(featureID: featureID), faces: [
                StableSubshapeReference(subshapeID: .init(featureID: featureID, role: role, ordinal: 0),
                    geometrySignature: .untrimmedPlane(origin: .origin))
            ], method: .nominal)
        }
        let shortBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var shortCaller = try execution(shortBudget)
        try feature(shortRole).validate(using: &shortCaller)
        let longBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var longCaller = try execution(longBudget)
        try feature(longRole).validate(using: &longCaller)
        try require(longBudget.snapshot.work - shortBudget.snapshot.work == longRole.utf8.count - shortRole.utf8.count,
            "Face rebuild Set hashing escaped the caller's variable role work.")
        try require(longBudget.snapshot.storageBytes == shortBudget.snapshot.storageBytes,
            "Changing only a stored face role changed fixed validation scratch storage.")
    }

    private static func surfaceDomainScratch() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 0, y: 1, z: 0)],
                [.init(x: 1, y: 0, z: 0), .init(x: 1, y: 1, z: 0)]])
        let sourceBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var sourceCaller = try execution(sourceBudget)
        try surface.validate(tolerance: .standard, using: &sourceCaller)
        let domainBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var domainCaller = try execution(domainBudget)
        try SurfaceParameterDomain2D(uLowerBound: 0, uUpperBound: 1, vLowerBound: 0, vUpperBound: 1)
            .validate(containedIn: surface, tolerance: .standard, using: &domainCaller)
        try require(domainBudget.snapshot.storageBytes - sourceBudget.snapshot.storageBytes == 4 * MemoryLayout<Double>.stride,
            "Surface domain bounds did not admit their actual four-Double scratch array.")
    }

    private static func meshNormalScratch() throws {
        let positions: [Point3D] = [.origin, .init(x: 1, y: 0, z: 0), .init(x: 0, y: 1, z: 0)]
        let plain = Mesh(positions: positions, indices: [0, 1, 2])
        let withNormals = Mesh(positions: positions, normals: [.unitZ, .unitZ, .unitZ], indices: [0, 1, 2])
        let plainBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var plainCaller = try execution(plainBudget)
        try plain.validate(tolerance: .standard, using: &plainCaller)
        let normalBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var normalCaller = try execution(normalBudget)
        try withNormals.validate(tolerance: .standard, using: &normalCaller)
        try require(normalBudget.snapshot.storageBytes - plainBudget.snapshot.storageBytes == 3 * MemoryLayout<Int>.stride,
            "Mesh normal winding checks did not admit their actual three-Int scratch array.")
    }

    private static func assemblySourceCountScratch() throws {
        let source = document()
        guard let assembly = source.assembly else { throw Failure(message: "The assembly scratch control requires a real assembly.") }
        var empty = assembly
        empty.roots = []
        var limits = AssemblyResourceLimits.standard
        limits.maximumRecords = 1
        let emptyBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var emptyCaller = try execution(emptyBudget)
        do {
            _ = try DocumentAssemblyValidator().expand(empty, in: source.designGraph,
                tolerance: .standard, limits: limits, using: &emptyCaller)
            throw Failure(message: "Empty assembly roots lost their original first rejection.")
        } catch {
            guard let failure = original(error) as? AssemblyError,
                failure == .invalidSource("Assembly requires at least one root occurrence.") else { throw error }
        }
        let sourceBudget = try OriginalQueryBudget(allocationPolicy: .none)
        var sourceCaller = try execution(sourceBudget)
        do {
            _ = try DocumentAssemblyValidator().expand(assembly, in: source.designGraph,
                tolerance: .standard, limits: limits, using: &sourceCaller)
            throw Failure(message: "Assembly source records escaped their original local ceiling.")
        } catch {
            guard let failure = original(error) as? AssemblyError,
                failure == .resourceLimitExceeded("source records") else { throw error }
        }
        try require(sourceBudget.snapshot.storageBytes - emptyBudget.snapshot.storageBytes == 4 * MemoryLayout<Int>.stride,
            "Assembly source counts did not admit their actual four-Int scratch array.")
        try require(emptyCaller.activeContributionCount == 0 && sourceCaller.activeContributionCount == 0,
            "An original assembly rejection leaked its allocation scope.")
    }

}
