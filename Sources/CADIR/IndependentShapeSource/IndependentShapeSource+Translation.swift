import CADCore
import CADGeometry

public extension IndependentShapeSource {
    func translated(by displacement: Vector3D, tolerance: ModelingTolerance,
                    limits: IndependentShapeSourceLimits = .standard, bodySourceGraph: DesignGraph? = nil) throws -> IndependentShapeSource {
        try displacement.validate()
        var execution = try IndependentShapeSourceExecutionOwner.execution(limits: limits)
        _ = try DefaultIndependentShapeSourceValidator().validate(self, tolerance: tolerance, limits: limits, bodySourceGraph: bodySourceGraph, using: &execution)
        let transform = RigidTransform3D.translated(by: displacement)
        var shiftedGeometry = geometry
        for (id, curve) in geometry.curves {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 1, using: &execution)
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
            shiftedGeometry.curves[id] = try translatedCurve(curve, by: transform,
                tolerance: tolerance, remainingDepth: limits.maximumDepth, using: &execution)
        }
        for (id, surface) in geometry.surfaces {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 1, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
            shiftedGeometry.surfaces[id] = try translatedSurface(surface, by: transform,
                tolerance: tolerance, remainingDepth: limits.maximumDepth, using: &execution)
        }
        var originalMatrices: [IndependentShapeFrameID: OriginalIGESMatrixSource] = [:]
        for frame in frames {
            try IndependentShapeSourceExecutionOwner.charge(work: 1, using: &execution)
            if let original = frame.originalIGES { try IndependentShapeSourceExecutionOwner.charge(records: 1, using: &execution); originalMatrices[frame.id] = original }
        }
        var shiftedDefinitions: [IndependentShapeDefinition] = []
        for definition in definitions {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 1, using: &execution)
            let original = try definition.originalIGES?.adjusted(by: displacement, using: &execution)
            shiftedDefinitions.append(.init(id: definition.id, representationID: definition.representationID,
                originFrameID: definition.originFrameID, originalIGES: original))
        }
        var shiftedFrames: [IndependentShapeFrame] = []
        for frame in frames {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 12, using: &execution)
            let original = frame.placement
            let witness = try frame.originalSTEPPlacement?.adjusted(by: displacement, conjugates: false, using: &execution)
            let shifted: AffineTransform3D
            if frame.originalIGES != nil {
                shifted = original
            } else if let witness {
                shifted = try witness.derivedAffineTransform(tolerance: tolerance,
                    maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumDepth, using: &execution)
            } else {
                shifted = try AffineTransform3D(basisX: original.basisX, basisY: original.basisY,
                    basisZ: original.basisZ, translation: original.translation + displacement)
            }
            shiftedFrames.append(IndependentShapeFrame(id: frame.id, name: frame.name, placement: shifted,
                originalSTEPPlacement: witness, originalIGES: frame.originalIGES))
        }
        var originPresence: [IndependentShapeDefinitionID: Bool] = [:]
        for definition in definitions { try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 1, using: &execution); originPresence[definition.id] = definition.originFrameID != nil }
        var shiftedInstances: [IndependentShapeInstance] = []
        for instance in instances {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 32, using: &execution)
            guard let hasOrigin = originPresence[instance.target] else { throw IndependentShapeSourceError.missingReference("Translated instance definition.") }
            let original = instance.placement
            let translation = hasOrigin ? original.translation + displacement
                : original.translation + displacement - original.applying(to: displacement)
            let witness = try instance.originalSTEPPlacement?.adjusted(by: displacement, conjugates: !hasOrigin, using: &execution)
            let igesWitness = try instance.originalIGES?.adjusted(by: displacement, conjugates: true, using: &execution)
            let shifted: AffineTransform3D
            if let igesWitness {
                let matrix = igesWitness.matrixFrameID.flatMap { originalMatrices[$0] }
                shifted = try igesWitness.derivedAffineTransform(matrix: matrix, tolerance: tolerance,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth, using: &execution)
            } else if let witness {
                shifted = try witness.derivedAffineTransform(tolerance: tolerance,
                    maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumDepth, using: &execution)
            } else {
                shifted = try AffineTransform3D(basisX: original.basisX, basisY: original.basisY,
                    basisZ: original.basisZ, translation: translation)
            }
            shiftedInstances.append(IndependentShapeInstance(id: instance.id, name: instance.name,
                placementName: instance.placementName, target: instance.target, placement: shifted,
                originalSTEPPlacement: witness, originalIGES: igesWitness))
        }
        var shiftedCurvePositions = curvePositionFrames
        for (id, association) in curvePositionFrames where originalMatrices[association.frameID] != nil {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 1, using: &execution)
            let count = association.originalIGESAdjustments.count.addingReportingOverflow(1)
            guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES pose adjustment count overflows.") }
            try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &execution)
            shiftedCurvePositions[id] = .init(frameID: association.frameID, parameterLengthUnit: association.parameterLengthUnit,
                originalIGESAdjustments: association.originalIGESAdjustments + [.init(displacement: displacement, conjugates: false)])
        }
        var shiftedSurfacePositions = surfacePositionFrames
        for (id, association) in surfacePositionFrames where originalMatrices[association.frameID] != nil {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 1, using: &execution)
            let count = association.originalIGESAdjustments.count.addingReportingOverflow(1)
            guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES surface pose adjustment count overflows.") }
            try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &execution)
            shiftedSurfacePositions[id] = .init(frameID: association.frameID, parameterLengthUnit: association.parameterLengthUnit,
                originalIGESAdjustments: association.originalIGESAdjustments + [.init(displacement: displacement, conjugates: false)])
        }
        var shiftedItems: [IndependentShapeItem] = []
        for item in items {
            try IndependentShapeSourceExecutionOwner.charge(records: 1, work: 16, using: &execution)
            shiftedItems.append(IndependentShapeItem(id: item.id, name: item.name, geometry: item.geometry,
                trimmingSource: item.trimmingSource?.translated(by: displacement),
                traversalSource: try item.traversalSource.map { original in
                    try GeometryStructuralComparisonWork.charge(curve: original, using: &execution)
                    return try translatedCurve(original, by: transform, tolerance: tolerance,
                        remainingDepth: limits.maximumDepth, using: &execution)
                }))
        }
        var shiftedLinearSources: [CurveID: OriginalSTEPLineSource] = [:]
        for (id, source) in curveLinearSources {
            try IndependentShapeSourceExecutionOwner.charge(records: source.adjustments.count + 2, work: source.adjustments.count + 1, using: &execution)
            shiftedLinearSources[id] = try source.translated(by: displacement)
        }
        let result = IndependentShapeSource(geometry: shiftedGeometry, items: shiftedItems, geometricSets: geometricSets,
            contexts: contexts, ambientContexts: ambientContexts, representations: representations, frames: shiftedFrames, definitions: shiftedDefinitions,
            curveNames: curveNames, surfaceNames: surfaceNames, curvePositionFrames: shiftedCurvePositions,
            surfacePositionFrames: shiftedSurfacePositions, surfaceAngularMeasures: surfaceAngularMeasures, curveLinearSources: shiftedLinearSources, curveSplineSources: curveSplineSources, surfaceSplineSources: surfaceSplineSources, groups: groups, originalSTEPGroups: originalSTEPGroups, instances: shiftedInstances, productAssociations: productAssociations, ambientOriginalAngularSource: ambientOriginalAngularSource, ambientOriginalLengthSource: ambientOriginalLengthSource, roots: roots)
        _ = try DefaultIndependentShapeSourceValidator().validate(result, tolerance: tolerance, limits: limits, bodySourceGraph: bodySourceGraph, using: &execution)
        return result
    }
}

private func translatedCurve(_ source: Curve3D, by transform: RigidTransform3D,
    tolerance: ModelingTolerance, remainingDepth: Int, using execution: inout OriginalQueryExecution) throws -> Curve3D {
    guard remainingDepth > 0 else {
        throw IndependentShapeSourceError.resourceLimitExceeded("Translated curve source depth.")
    }
    try IndependentShapeSourceExecutionOwner.charge(work: 1, using: &execution)
    switch source {
    case .originalAffineWord(let image):
        let action = try AffineTransform3D(basisX: transform.basisX, basisY: transform.basisY,
            basisZ: transform.basisZ, translation: transform.translation)
        let word = try image.operationWord.appending(.forward(action), tolerance: tolerance, usage: &execution)
        return .originalAffineWord(try OriginalAffineWordCurve3D(source: image.source,
            operationWord: word, tolerance: tolerance, remainingSourceDepth: remainingDepth,
            maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: min(execution.limits.maximumValueDepth, execution.limits.maximumCoefficientDepth), usage: &execution))
    case .parameterImage(let image):
        let shifted = try translatedCurve(image.source, by: transform, tolerance: tolerance,
            remainingDepth: remainingDepth - 1, using: &execution)
        return .parameterImage(ParameterImageCurve3D(validatedSource: shifted,
            parameterGain: image.parameterGain, offset: image.offset))
    default:
        return try transform.applying(to: source, tolerance: tolerance)
    }
}

private func translatedSurface(_ source: Surface3D, by transform: RigidTransform3D,
    tolerance: ModelingTolerance, remainingDepth: Int, using execution: inout OriginalQueryExecution) throws -> Surface3D {
    guard remainingDepth > 0 else {
        throw IndependentShapeSourceError.resourceLimitExceeded("Translated surface source depth.")
    }
    try IndependentShapeSourceExecutionOwner.charge(work: 1, using: &execution)
    if case .procedural(.originalImage(let image)) = source,
       image.transform.basisX == .unitX, image.transform.basisY == .unitY,
       image.transform.basisZ == .unitZ, image.transform.translation == .zero {
        let shifted = try translatedSurface(image.source, by: transform, tolerance: tolerance,
            remainingDepth: remainingDepth - 1, using: &execution)
        return .parameterImage(image.replacingSourceKeepingChart(with: shifted))
    }
    if case .procedural(.originalAffineWord(let image)) = source {
        let action = try AffineTransform3D(basisX: transform.basisX, basisY: transform.basisY,
            basisZ: transform.basisZ, translation: transform.translation)
        let word = try image.operationWord.appending(.forward(action), tolerance: tolerance, usage: &execution)
        return .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: image.source,
            operationWord: word, tolerance: tolerance, remainingSourceDepth: remainingDepth,
            maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: min(execution.limits.maximumValueDepth, execution.limits.maximumCoefficientDepth), usage: &execution)))
    }
    return try transform.applying(to: source, tolerance: tolerance)
}
