import CADCore
import CADIR
import CADTopology

/// Consumes validated Shape roots and CADIR's existing material/output authority.
public struct DefaultBooleanDimensionResolver: BooleanDimensionResolving {
    private let shapeOperator: any ShapeOperating

    public init(shapeOperator: any ShapeOperating = DefaultShapeOperator()) {
        self.shapeOperator = shapeOperator
    }

    public func resolve(feature: BooleanFeature, targets: [any ShapeRepresenting],
                        tools: [any ShapeRepresenting], tolerance: ModelingTolerance) throws -> BooleanDimensionContract {
        try tolerance.validate()
        try feature.validate()
        guard targets.count == feature.targets.count, tools.count == feature.tools.count else {
            throw failure(.invalidInput, "Boolean shape operands must match the declared target and tool counts.", tolerance)
        }
        func dimensions(_ operands: [any ShapeRepresenting]) throws -> [BooleanTopologicalDimension] {
            try operands.map { operand in
                try Task.checkCancellation()
                // extract owns the single provider acquisition and selected-closure
                // validity. All semantic decisions below use only its returned value.
                let shape = try shapeOperator.extract(operand, tolerance: tolerance)
                return try supportedDimension(of: shape.root, tolerance: tolerance)
            }
        }
        let targetDimensions = try dimensions(targets)
        let toolDimensions = try dimensions(tools)
        guard let target = targetDimensions.first, targetDimensions.allSatisfy({ $0 == target }) else {
            throw failure(.invalidInput, "Boolean targets must have the same admitted root dimension.", tolerance)
        }
        if feature.operation != .region, tools.count > 1 {
            guard toolDimensions.allSatisfy({ $0 == .volume }),
                  feature.toolMaterial == .default || feature.toolMaterial == .inside else {
                throw failure(.invalidInput, "Multiple Boolean tools must be solids taken as their volumes.", tolerance)
            }
        }
        let targetPorts = targetDimensions.map { $0 == .volume ? FeaturePort.body : .sheet }
        let outputPort = try feature.resultPort(targetPorts: targetPorts)
        let sliceToolRegions: BooleanDimensionLossPolicy.SliceToolRegions
        if feature.operation != .slice { sliceToolRegions = .notApplicable }
        else if feature.targetMaterial == .default, feature.toolMaterial == .default,
                (targetDimensions + toolDimensions).allSatisfy({ $0 == .volume }) {
            sliceToolRegions = .includedForDefaultSolidInputs
        } else { sliceToolRegions = .notGeneratedInCurrentEnvelope }
        return BooleanDimensionContract(targetDimensions: targetDimensions, toolDimensions: toolDimensions,
            outputPort: outputPort, lossPolicy: .init(keepTools: feature.keepTools, sliceToolRegions: sliceToolRegions))
    }

    private func supportedDimension(of root: ShapeReference,
                                    tolerance: ModelingTolerance) throws -> BooleanTopologicalDimension {
        switch root {
        case .solid: return .volume
        case .face, .shell: return .surface
        // FIXME(INCOMPLETE_IMPLEMENTATION): standalone point Boolean construction is absent.
        // Public dimension preflight rejects this valid T1 root; admit it only after
        // exact point results and operation-specific loss behavior are implemented and verified.
        case .vertex:
            throw failure(.unsupportedCapability, "Standalone vertex Boolean geometry is not implemented by the body pipeline.", tolerance)
        // FIXME(INCOMPLETE_IMPLEMENTATION): standalone edge/wire Boolean construction is absent.
        // Public dimension preflight rejects these valid T1 roots; admit them only after
        // exact curve results and operation-specific loss behavior are implemented and verified.
        case .edge, .wire:
            throw failure(.unsupportedCapability, "Standalone edge and wire Boolean geometry is not implemented by the body pipeline.", tolerance)
        // FIXME(INCOMPLETE_IMPLEMENTATION): the body pipeline does not preserve complex interfaces.
        // Public dimension preflight rejects valid solid complexes; admit them only after
        // interface-preserving Boolean construction and lineage are implemented and verified.
        case .solidComplex:
            throw failure(.unsupportedCapability, "Solid-complex Boolean geometry has no admitted interface-preserving route.", tolerance)
        case .compound(let roots):
            var pending = roots
            var hasSurface = false
            while let selected = pending.popLast() {
                try Task.checkCancellation()
                switch selected {
                case .face, .shell: hasSurface = true
                case .compound(let children): pending.append(contentsOf: children)
                default:
                    throw failure(.unsupportedCapability, "Boolean aggregate operands must contain only sheet face or shell roots.", tolerance)
                }
            }
            guard hasSurface else { throw failure(.invalidInput, "An empty compound is not a Boolean operand.", tolerance) }
            return .surface
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .validation, code: code, tolerance: tolerance, message: message)
    }
}
