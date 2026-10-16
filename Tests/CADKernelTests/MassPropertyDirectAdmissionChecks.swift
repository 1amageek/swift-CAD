import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADModeling
import CADKernel
import HashTreeCollections
import Synchronization

enum MassPropertyDirectAdmissionChecks {
    private typealias Shared = VolumeMomentLoopAdmissionChecks
    private enum Failure: Error { case unexpectedAttributes, missingRefusal }
    static let center = Point3D(x: 0.5, y: 0.5, z: 0.5)

    private struct ExplicitDensityAttributes: ProductAttributeResolving {
        func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits) throws -> ResolvedProductAttributes {
            throw Failure.unexpectedAttributes
        }
        func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits,
            using execution: inout OriginalQueryExecution) throws -> ResolvedProductAttributes {
            throw Failure.unexpectedAttributes
        }
        func sourceReference(for subshapeID: SubshapeID, in evaluated: EvaluatedDocument) throws -> StableSubshapeReference {
            throw Failure.unexpectedAttributes
        }
    }

    /// A narrow authored-density consumer control, not a default-resolver implementation.
    private struct AuthoredDensityAttributes: ProductAttributeResolving {
        let expected: OriginalQueryBudget
        func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits) throws -> ResolvedProductAttributes {
            throw Failure.unexpectedAttributes
        }
        func sourceReference(for subshapeID: SubshapeID, in evaluated: EvaluatedDocument) throws -> StableSubshapeReference {
            throw Failure.unexpectedAttributes
        }
        func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits,
            using execution: inout OriginalQueryExecution) throws -> ResolvedProductAttributes {
            try Shared.require(execution.budget === expected, "Authored density lost the Mass caller's execution owner.")
            let initialWork = execution.localWork
            var budget = try ProductAttributeBudget(limits: limits, using: &execution)
            let invocation = budget
            return try invocation.withExecution(using: &execution) { execution in
                let assignments = evaluated.document.productAttributes.assignments
                guard assignments.count == 1, assignments.count <= limits.maximumRecords else {
                    throw ProductAttributeError.unsupportedSemantics("The consumer control requires one authored density assignment.")
                }
                var values: [ResolvedProductTarget: ResolvedProductProperties] = [:]
                var geometry: [ProductAttributeTarget: TopologyReference] = [:]
                for assignment in assignments {
                    try budget.charge(work: 1, targets: 1, using: &execution)
                    try assignment.target.validate(using: &execution)
                    guard assignment.target.kind == .body, assignment.target.definitionID == nil,
                        assignment.target.path == nil, assignment.overrides == nil,
                        let reference = assignment.target.geometry,
                        case .body(let bodyID)? = evaluated.subshapes[reference.subshapeID],
                        evaluated.brep.bodies[bodyID] != nil,
                        case .density(let density) = assignment.value else {
                        throw ProductAttributeError.unsupportedSemantics("The consumer control requires a live global body density without overrides.")
                    }
                    try density.validate()
                    let chain = try OriginalParameterQueryStorage.values(count: 1, using: &execution) { _ in [assignment.id] }
                    let property = ResolvedProductProperty(value: assignment.value, assignmentChain: chain)
                    var properties: [ProductAttributeValue.Property: ResolvedProductProperty] = [:]
                    try OriginalParameterQueryStorage.set(property, for: .density, in: &properties, using: &execution)
                    try OriginalParameterQueryStorage.set(ResolvedProductProperties(properties: properties, layers: []),
                        for: ResolvedProductTarget(topology: .body(bodyID)), in: &values, using: &execution)
                    try OriginalParameterQueryStorage.set(.body(bodyID), for: assignment.target, in: &geometry, using: &execution)
                }
                return ResolvedProductAttributes(documentID: evaluated.document.id, values: values,
                    localGeometry: geometry, consumedWork: execution.localWork - initialWork)
            }
        }
    }

    private final class MomentCalls: Sendable {
        struct State: Sendable {
            var raw = 0; var receipt = 0; var ordinary = 0; var sameOwner = true
            var completed = false
        }
        private let state = Mutex(State())
        let expected: OriginalQueryBudget?
        init(expected: OriginalQueryBudget? = nil) { self.expected = expected }
        var snapshot: State { state.withLock { $0 } }
        func complete() { state.withLock { $0.completed = true } }
        func visit(receipt: Bool, budget: OriginalQueryBudget?) {
            state.withLock {
                if let budget {
                    if receipt { $0.receipt += 1 } else { $0.raw += 1 }
                    if let expected { $0.sameOwner = $0.sameOwner && budget === expected }
                } else { $0.ordinary += 1 }
            }
        }
    }

    private struct CountedMoments: BRepVolumeMomentMeasuring {
        let calls: MomentCalls
        func moments(of bodyID: BodyID, in model: BRepModel, options: BRepVolumeMomentOptions,
            tolerance: ModelingTolerance) throws -> BRepVolumeMoments {
            calls.visit(receipt: false, budget: nil)
            return try DefaultBRepVolumeMomentMeasurer().moments(of: bodyID, in: model,
                options: options, tolerance: tolerance)
        }
        func moments(of bodyID: BodyID, in model: ValidatedBRepModel,
            options: BRepVolumeMomentOptions) throws -> BRepVolumeMoments {
            calls.visit(receipt: true, budget: nil)
            return try DefaultBRepVolumeMomentMeasurer().moments(of: bodyID, in: model, options: options)
        }
        func moments(of bodyID: BodyID, in model: BRepModel, options: BRepVolumeMomentOptions,
            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
            calls.visit(receipt: false, budget: execution.budget)
            let result = try DefaultBRepVolumeMomentMeasurer().moments(of: bodyID, in: model,
                options: options, tolerance: tolerance, using: &execution)
            try Shared.checkMoments(result)
            calls.complete()
            return result
        }
        func moments(of bodyID: BodyID, in model: ValidatedBRepModel, options: BRepVolumeMomentOptions,
            using execution: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
            calls.visit(receipt: true, budget: execution.budget)
            return try DefaultBRepVolumeMomentMeasurer().moments(of: bodyID, in: model,
                options: options, using: &execution)
        }
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        let stop: Int
        init(stop: Int) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws(ExactScalarFailure) {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == stop { throw .cancelled }
        }
    }

    static func document(_ model: BRepModel) -> EvaluatedDocument {
        EvaluatedDocument(document: CADDocument(units: .init(length: .meter, angle: .radian),
            metadata: .init(createdAtReferenceDate: 0, updatedAtReferenceDate: 0)),
            parameters: ResolvedParameterTable(), brep: model, meshes: [:], caches: DocumentCaches(),
            configuration: .init(tolerance: Shared.tolerance, tessellationOptions: .standard))
    }

    private static func provider(_ calls: MomentCalls) -> any MassPropertyMeasuring {
        MassPropertyEvaluator(tolerance: Shared.tolerance,
            momentMeasurer: CountedMoments(calls: calls), attributes: ExplicitDensityAttributes())
    }

    private static func contains(_ interval: ScalarInterval, _ value: Double) throws {
        try Shared.require(interval.contains(value), "A mass field excluded its independent analytic value.")
    }

    private static func brackets(_ interval: ScalarInterval, _ lower: Double, _ upper: Double) throws {
        try Shared.require(interval.lower <= lower && interval.upper >= upper,
            "A mass field excluded the adjacent dyadics bounding its independent rational value.")
    }

    private static func third(_ interval: ScalarInterval, numerator: Int = 1) throws {
        let lower: Double, upper: Double
        switch numerator {
        case 1: lower = 0x1.5555555555555p-2; upper = 0x1.5555555555556p-2
        case 2: lower = 0x1.5555555555555p-1; upper = 0x1.5555555555556p-1
        case 4: lower = 0x1.5555555555555p+0; upper = 0x1.5555555555556p+0
        case 5: lower = 0x1.aaaaaaaaaaaaap+0; upper = 0x1.aaaaaaaaaaaabp+0
        case 7: lower = 0x1.2aaaaaaaaaaaap+1; upper = 0x1.2aaaaaaaaaaabp+1
        case 14: lower = 0x1.2aaaaaaaaaaaap+2; upper = 0x1.2aaaaaaaaaaabp+2
        case 16: lower = 0x1.5555555555555p+2; upper = 0x1.5555555555556p+2
        case 20: lower = 0x1.aaaaaaaaaaaaap+2; upper = 0x1.aaaaaaaaaaaabp+2
        default: throw Shared.Failure(message: "The independent rational oracle has no requested numerator.")
        }
        try Shared.require(interval.lower <= lower && interval.upper >= upper,
            "A mass field excluded its exact rational-third oracle: numerator=\(numerator), lower=\(interval.lower), upper=\(interval.upper).")
    }

    private static func coherent(_ value: MassPropertyMeasurement, unit: LengthUnit = .meter) throws {
        try value.validate()
        try Shared.require(value.requestedIntegrationAccuracy == Shared.options && value.modelLengthUnit == unit
            && value.units.mass == "kg" && value.units.length == "m"
            && value.units.firstMoment == "kg*m" && value.units.inertia == "kg*m^2",
            "Mass publication changed its requested accuracy or canonical SI units.")
        let fields = [value.mass] + value.firstMoments + value.centroidBounds
            + value.secondMoments.flatMap { $0 } + value.inertiaAtReference.flatMap { $0 }
            + value.principalMoments + value.principalAxisResidualBounds
        for field in fields {
            try Shared.require(field.lower.isFinite && field.upper.isFinite
                && (field.upper - field.lower).nextUp <= Shared.options.absoluteAccuracy,
                "A mass field lost its finite requested-width control on the selected small cube.")
        }
        try Shared.require(value.principalFrameOrthogonalityError.isFinite
            && value.principalFrameOrthogonalityError <= Shared.options.absoluteAccuracy,
            "The selected cube's principal frame lost its orthogonality control.")
        for residual in value.principalAxisResidualBounds {
            try Shared.require(residual.lower == 0 && residual.upper <= Shared.options.absoluteAccuracy,
                "The selected cube's principal frame lost its tensor residual bound.")
        }
    }

    static func checkUnitCube(_ value: MassPropertyMeasurement, atOrigin: Bool = false) throws {
        try coherent(value)
        try contains(value.mass, 2)
        try Shared.require(value.inertiaReference == (atOrigin ? .origin : center), "Mass lost its requested reference.")
        for i in 0..<3 {
            try contains(value.firstMoments[i], 1)
            try contains(value.centroidBounds[i], 0.5)
            try third(value.secondMoments[i][i], numerator: 2)
            try third(value.inertiaAtReference[i][i], numerator: atOrigin ? 4 : 1)
            if !atOrigin { try third(value.principalMoments[i]) }
            for j in 0..<3 where i != j {
                try contains(value.secondMoments[i][j], 0.5)
                try contains(value.inertiaAtReference[i][j], atOrigin ? -0.5 : 0)
            }
        }
    }

    static func actualPublicEntriesPreserveMassTensorAndCallerAttribution() throws {
        let input = Shared.cube(), evaluated = document(input.model), calls = MomentCalls()
        let evaluator = provider(calls)
        let components = [MassPropertyComponent(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 2)]
        try checkUnitCube(evaluator.measure(components, in: evaluated, options: Shared.options, reference: center))
        try checkUnitCube(evaluator.measure(components, in: evaluated, options: Shared.options,
            modelLengthUnit: .meter, reference: .origin), atOrigin: true)
        for explicitUnit in [false, true] {
            let budget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork)
            let directCalls = MomentCalls(expected: budget), direct = provider(directCalls)
            var execution = try Shared.execution(budget)
            try execution.consumeWork(13)
            let value = try explicitUnit
                ? direct.measure(components, in: evaluated, options: Shared.options, modelLengthUnit: .meter,
                    reference: center, using: &execution)
                : direct.measure(components, in: evaluated, options: Shared.options, reference: center, using: &execution)
            try checkUnitCube(value)
            try Shared.require(value.consumedWork == execution.localWork - 13 && budget.snapshot.work == execution.localWork
                && execution.activeContributionCount == 0 && budget.snapshot.storageBytes > 0,
                "Mass result validation/publication escaped its cumulative caller work owner.")
            let observed = directCalls.snapshot
            try Shared.require(observed.raw == 1 && observed.receipt == 0 && observed.ordinary == 0 && observed.sameOwner,
                "Mass bypassed the direct raw producer or substituted its caller execution.")
            print("MASS_DIRECT work=\(value.consumedWork) cumulative=\(budget.snapshot.work) bytes=\(budget.snapshot.storageBytes)")
        }
        try Shared.require(calls.snapshot.raw == 2 && calls.snapshot.ordinary == 0,
            "Ordinary mass entries did not delegate into the direct raw producer.")
    }

    static func authoredDensityAssignmentFeedsTheDirectMassConsumer() throws {
        let input = Shared.cube()
        let featureID = FeatureID(PortableIdentity128(high: 20, low: 1))
        let subshapeID = SubshapeID(featureID: featureID, role: "body", ordinal: 0)
        let preparationBudget = try OriginalQueryBudget()
        var preparation = try Shared.execution(preparationBudget)
        let signature = try SubshapeGeometrySignatureBuilder(model: input.model, tolerance: Shared.tolerance)
            .signature(for: .body(input.bodyID), using: &preparation)
        print("MASS_DENSITY_SOURCE_PREPARATION work=\(preparationBudget.snapshot.work) bytes=\(preparationBudget.snapshot.storageBytes)")
        let reference = StableSubshapeReference(subshapeID: subshapeID, geometrySignature: signature)
        let length = CADExpression.constant(.length(1, unit: .meter))
        let feature = FeatureNode(id: featureID,
            operation: .primitive(.init(definition: .box(.init(width: length, depth: length, height: length)))),
            outputs: [.init(role: .body)])
        let assignment = ProductAttributeAssignment(id: ProductAttributeID(PortableIdentity128(high: 21, low: 1)),
            target: .init(kind: .body, geometry: reference), value: .density(.init(kilogramsPerCubicMeter: 2)))
        let source = CADDocument(units: .meters, designGraph: .init(nodes: [featureID: feature], order: [featureID]),
            productAttributes: .init(assignments: [assignment]),
            metadata: .init(createdAtReferenceDate: 0, updatedAtReferenceDate: 0))
        let evaluated = EvaluatedDocument(document: source, parameters: .init(), brep: input.model,
            meshes: [:], caches: .init(), subshapes: .init([subshapeID: .body(input.bodyID)]),
            configuration: .init(tolerance: Shared.tolerance, tessellationOptions: .standard))
        let budget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork)
        var execution = try Shared.execution(budget)
        try execution.consumeWork(13)
        let calls = MomentCalls(expected: budget)
        let evaluator: any MassPropertyMeasuring = MassPropertyEvaluator(tolerance: Shared.tolerance,
            momentMeasurer: CountedMoments(calls: calls), attributes: AuthoredDensityAttributes(expected: budget))
        let result = try evaluator.measure([.init(bodyID: input.bodyID)], in: evaluated, options: Shared.options,
            reference: center, using: &execution)
        try checkUnitCube(result)
        try Shared.require(result.consumedWork == execution.localWork - 13 && execution.localWork == budget.snapshot.work
            && execution.activeContributionCount == 0 && calls.snapshot.raw == 1 && calls.snapshot.sameOwner,
            "The authored density consumer lost its same-owner result attribution or actual moment producer.")
    }

    static func repeatedOccurrencesAndOriginalPlacementsPreserveComposition() throws {
        let input = Shared.cube(), evaluated = document(input.model), calls = MomentCalls()
        let evaluator = provider(calls)
        var execution = try Shared.execution(OriginalQueryBudget())
        let repeated = try evaluator.measure([
            .init(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 1),
            .init(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 1,
                placement: .translated(by: .init(x: 2, y: 0, z: 0)))], in: evaluated, options: Shared.options,
            reference: .init(x: 1.5, y: 0.5, z: 0.5), using: &execution)
        try coherent(repeated)
        try Shared.require(calls.snapshot.raw == 1, "Two occurrences recomputed the same original body moments.")
        try contains(repeated.mass, 2)
        for i in 0..<3 {
            try contains(repeated.firstMoments[i], i == 0 ? 3 : 1)
            try contains(repeated.centroidBounds[i], i == 0 ? 1.5 : 0.5)
            try third(repeated.secondMoments[i][i], numerator: i == 0 ? 20 : 2)
            try third(repeated.inertiaAtReference[i][i], numerator: i == 0 ? 1 : 7)
            try third(repeated.principalMoments[i], numerator: i == 0 ? 1 : 7)
            for j in 0..<3 where i != j {
                try contains(repeated.secondMoments[i][j], i == 0 || j == 0 ? 1.5 : 0.5)
                try contains(repeated.inertiaAtReference[i][j], 0)
            }
        }
        let rigid = try RigidTransform3D(basisX: .unitY, basisY: -Vector3D.unitX, basisZ: .unitZ,
            translation: .init(x: 2, y: 0, z: 0), tolerance: Shared.tolerance)
        var rotatedExecution = try Shared.execution(OriginalQueryBudget())
        let rotated = try evaluator.measure([.init(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 2,
            placement: rigid)], in: evaluated, options: Shared.options, reference: .init(x: 1.5, y: 0.5, z: 0.5), using: &rotatedExecution)
        try coherent(rotated); try contains(rotated.mass, 2)
        for i in 0..<3 {
            try contains(rotated.firstMoments[i], i == 0 ? 3 : 1)
            try contains(rotated.centroidBounds[i], i == 0 ? 1.5 : 0.5)
            try third(rotated.secondMoments[i][i], numerator: i == 0 ? 14 : 2)
            try third(rotated.inertiaAtReference[i][i]); try third(rotated.principalMoments[i])
            for j in 0..<3 where i != j {
                try contains(rotated.secondMoments[i][j], i == 0 || j == 0 ? 1.5 : 0.5)
                try contains(rotated.inertiaAtReference[i][j], 0)
            }
        }
        let affine = try AffineTransform3D(basisX: .init(x: 2, y: 0, z: 0), basisY: .unitY,
            basisZ: .unitZ, translation: .zero)
        var stretchedExecution = try Shared.execution(OriginalQueryBudget())
        let stretched = try evaluator.measure([.init(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 2,
            affinePlacement: affine)], in: evaluated, options: Shared.options, reference: .init(x: 1, y: 0.5, z: 0.5), using: &stretchedExecution)
        try coherent(stretched); try contains(stretched.mass, 4)
        for i in 0..<3 {
            try contains(stretched.firstMoments[i], i == 0 ? 4 : 2)
            try contains(stretched.centroidBounds[i], i == 0 ? 1 : 0.5)
            try third(stretched.secondMoments[i][i], numerator: i == 0 ? 16 : 4)
            try third(stretched.inertiaAtReference[i][i], numerator: i == 0 ? 2 : 5)
            try third(stretched.principalMoments[i], numerator: i == 0 ? 2 : 5)
            for j in 0..<3 where i != j {
                try contains(stretched.secondMoments[i][j], i == 0 || j == 0 ? 2 : 1)
                try contains(stretched.inertiaAtReference[i][j], 0)
            }
        }
        var scaledExecution = try Shared.execution(OriginalQueryBudget())
        let scaled = try evaluator.measure([.init(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 2)],
            in: evaluated, options: Shared.options, modelLengthUnit: .millimeter,
            reference: .init(x: 0.0005, y: 0.0005, z: 0.0005), using: &scaledExecution)
        try coherent(scaled, unit: .millimeter)
        // Adjacent dyadics around exact SI fractions 2/10^9, 1/10^12, 1/2000,
        // 2/(3*10^15), 1/(2*10^15) and 1/(3*10^15), independent of the producer.
        try brackets(scaled.mass, 0x1.12e0be826d694p-29, 0x1.12e0be826d695p-29)
        for i in 0..<3 {
            try brackets(scaled.firstMoments[i], 0x1.19799812dea11p-40, 0x1.19799812dea12p-40)
            try brackets(scaled.centroidBounds[i], 0x1.0624dd2f1a9fbp-11, 0x1.0624dd2f1a9fcp-11)
            try brackets(scaled.secondMoments[i][i], 0x1.804ea293472c7p-51, 0x1.804ea293472c8p-51)
            try brackets(scaled.inertiaAtReference[i][i], 0x1.804ea293472c7p-52, 0x1.804ea293472c8p-52)
            try brackets(scaled.principalMoments[i], 0x1.804ea293472c7p-52, 0x1.804ea293472c8p-52)
            for j in 0..<3 where i != j {
                try brackets(scaled.secondMoments[i][j], 0x1.203af9ee75615p-51, 0x1.203af9ee75616p-51)
                try contains(scaled.inertiaAtReference[i][j], 0)
            }
        }
        try Shared.require(calls.snapshot.raw == 4 && calls.snapshot.ordinary == 0,
            "Mass occurrence reuse escaped its per-request producer cache.")
    }

    static func callerResourcesAndCancellationRefusePublication() throws {
        let input = Shared.cube(), evaluated = document(input.model)
        let components = [MassPropertyComponent(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 2)]
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? 100_000 : Shared.options.maximumWork,
                storageByteLimit: resource == .storage ? 0 : nil)
            var execution = try Shared.execution(budget)
            do {
                _ = try provider(MomentCalls(expected: budget)).measure(components, in: evaluated,
                    options: Shared.options, reference: center, using: &execution)
                throw Failure.missingRefusal
            } catch {
                guard let scalar = Shared.original(error) as? ExactScalarFailure,
                    case .resourceLimit(let actual) = scalar, actual == resource else { throw error }
            }
            try Shared.require(execution.activeContributionCount == 0 && execution.localWork == budget.snapshot.work,
                "Refused mass publication leaked its request or reset its original work.")
            if resource == .storage { try Shared.require(budget.snapshot.storageBytes == 0, "Mass committed a rejected allocation.") }
            else { try Shared.require(budget.snapshot.work > 0 && budget.snapshot.work <= 100_000, "Mass exceeded its caller work limit.") }
        }
        for limit in [13, Shared.options.maximumWork] {
            let budget = try OriginalQueryBudget(allocationPolicy: .uint32WordWork)
            var execution = try Shared.execution(budget)
            try execution.consumeWork(13)
            let calls = MomentCalls(expected: budget)
            let options = BRepVolumeMomentOptions(absoluteAccuracy: Shared.options.absoluteAccuracy,
                relativeAccuracy: Shared.options.relativeAccuracy, maximumWork: limit,
                maximumSubdivisionDepth: Shared.options.maximumSubdivisionDepth)
            do {
                _ = try provider(calls).measure(components, in: evaluated, options: options,
                    reference: center, using: &execution)
                throw Failure.missingRefusal
            } catch {
                guard let scalar = Shared.original(error) as? ExactScalarFailure,
                    case .resourceLimit(.work) = scalar else { throw error }
            }
            try Shared.require(execution.localWork == budget.snapshot.work
                && budget.snapshot.work >= 13 && budget.snapshot.work - 13 <= limit
                && execution.activeContributionCount == 0 && calls.snapshot.sameOwner,
                "Allocation metadata bypassed the caller's cumulative Mass work ceiling.")
            if limit == 13 {
                try Shared.require(calls.snapshot.raw == 0 && calls.snapshot.ordinary == 0,
                    "A metadata-rejected Mass setup reached the real producer.")
            }
        }
        for stop in [1, 1_000] {
            let checkpoints = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork,
                checkpoint: { try checkpoints.check() })
            var execution = try Shared.execution(budget)
            do {
                _ = try provider(MomentCalls(expected: budget)).measure(components, in: evaluated,
                    options: Shared.options, reference: center, using: &execution)
                throw Failure.missingRefusal
            } catch {
                guard let scalar = Shared.original(error) as? ExactScalarFailure,
                    case .cancelled = scalar else { throw error }
            }
            try Shared.require(checkpoints.count == stop && execution.activeContributionCount == 0,
                "Mass cancellation lost the actual caller checkpoint or contribution lifetime.")
            if stop == 1 { try Shared.require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0, "Entry cancellation consumed mass resources.") }
            else { try Shared.require(budget.snapshot.work > 0, "In-progress mass cancellation refunded admitted work.") }
        }
        let completed = MomentCalls()
        let terminalBudget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork, checkpoint: {
            if completed.snapshot.completed { throw ExactScalarFailure.cancelled }
        })
        var terminal = try Shared.execution(terminalBudget)
        do {
            _ = try provider(completed).measure(components, in: evaluated, options: Shared.options,
                reference: center, using: &terminal)
            throw Failure.missingRefusal
        } catch {
            guard let scalar = Shared.original(error) as? ExactScalarFailure,
                case .cancelled = scalar else { throw error }
        }
        try Shared.require(completed.snapshot.raw == 1 && completed.snapshot.completed
            && terminalBudget.snapshot.work > 0 && terminal.activeContributionCount == 0,
            "Cancellation after the real lower producer returned did not abort Mass publication.")
    }

    static func evaluatedSourceAndPublishedResultRetainTheirOwners() throws {
        func retained() throws -> MassPropertyMeasurement {
            var authored = Shared.cube()
            let evaluated = document(authored.model)
            authored.model.vertices[VertexID(PortableIdentity128(high: 1, low: 1))] = Vertex(
                id: VertexID(PortableIdentity128(high: 1, low: 1)), point: .init(x: 99, y: 0, z: 0))
            authored.model.loops.removeAll(where: { _ in true })
            try Shared.require(evaluated.brep.vertices[VertexID(PortableIdentity128(high: 1, low: 1))]?.point == .origin
                && evaluated.brep.loops.count == 6, "Authored COW mutation changed the evaluated source.")
            var execution = try Shared.execution(OriginalQueryBudget(workLimit: Shared.options.maximumWork))
            return try provider(MomentCalls()).measure([.init(bodyID: authored.bodyID, densityKilogramsPerCubicMeter: 2)],
                in: evaluated, options: Shared.options, reference: center, using: &execution)
        }
        let result = try retained()
        try checkUnitCube(result)
    }
}
