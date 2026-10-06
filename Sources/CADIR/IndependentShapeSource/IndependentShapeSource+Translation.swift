import CADCore
import CADGeometry

public extension IndependentShapeSource {
    func translated(by displacement: Vector3D, tolerance: ModelingTolerance,
                    limits: IndependentShapeSourceLimits = .standard, bodySourceGraph: DesignGraph? = nil) throws -> IndependentShapeSource {
        try displacement.validate()
        var budget = try IndependentShapeSourceBudget(limits: limits)
        let admitted = try DefaultIndependentShapeSourceValidator().validate(self, tolerance: tolerance, limits: limits, bodySourceGraph: bodySourceGraph)
        try budget.charge(records: admitted.consumedRecords, work: admitted.consumedWork, textBytes: admitted.consumedTextBytes)
        let transform = RigidTransform3D.translated(by: displacement)
        var shiftedGeometry = geometry
        for (id, curve) in geometry.curves {
            try budget.charge(records: 1, work: 1)
            try GeometryStructuralComparisonWork.charge(curve: curve) { try budget.charge(work: $0) }
            shiftedGeometry.curves[id] = try translatedCurve(curve, by: transform,
                tolerance: tolerance, remainingDepth: limits.maximumDepth, budget: &budget)
        }
        for (id, surface) in geometry.surfaces {
            try budget.charge(records: 1, work: 1)
            try GeometryStructuralComparisonWork.charge(surface: surface) { try budget.charge(work: $0) }
            shiftedGeometry.surfaces[id] = try translatedSurface(surface, by: transform,
                tolerance: tolerance, remainingDepth: limits.maximumDepth, budget: &budget)
        }
        var originalMatrices: [IndependentShapeFrameID: OriginalIGESMatrixSource] = [:]
        for frame in frames {
            try budget.charge(work: 1)
            if let original = frame.originalIGES { try budget.charge(records: 1); originalMatrices[frame.id] = original }
        }
        var shiftedDefinitions: [IndependentShapeDefinition] = []
        for definition in definitions {
            try budget.charge(records: 1, work: 1)
            let original = try definition.originalIGES?.adjusted(by: displacement, usage: &budget)
            shiftedDefinitions.append(.init(id: definition.id, representationID: definition.representationID,
                originFrameID: definition.originFrameID, originalIGES: original))
        }
        var shiftedFrames: [IndependentShapeFrame] = []
        for frame in frames {
            try budget.charge(records: 1, work: 12)
            let original = frame.placement
            let witness = try frame.originalSTEPPlacement?.adjusted(by: displacement, conjugates: false) {
                try budget.charge(records: $0, work: $0)
            }
            let shifted: AffineTransform3D
            if frame.originalIGES != nil {
                shifted = original
            } else if let witness {
                shifted = try witness.derivedAffineTransform(tolerance: tolerance,
                    maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumDepth, usage: &budget)
            } else {
                shifted = try AffineTransform3D(basisX: original.basisX, basisY: original.basisY,
                    basisZ: original.basisZ, translation: original.translation + displacement)
            }
            shiftedFrames.append(IndependentShapeFrame(id: frame.id, name: frame.name, placement: shifted,
                originalSTEPPlacement: witness, originalIGES: frame.originalIGES))
        }
        var originPresence: [IndependentShapeDefinitionID: Bool] = [:]
        for definition in definitions { try budget.charge(records: 1, work: 1); originPresence[definition.id] = definition.originFrameID != nil }
        var shiftedInstances: [IndependentShapeInstance] = []
        for instance in instances {
            try budget.charge(records: 1, work: 32)
            guard let hasOrigin = originPresence[instance.target] else { throw IndependentShapeSourceError.missingReference("Translated instance definition.") }
            let original = instance.placement
            let translation = hasOrigin ? original.translation + displacement
                : original.translation + displacement - original.applying(to: displacement)
            let witness = try instance.originalSTEPPlacement?.adjusted(by: displacement, conjugates: !hasOrigin) {
                try budget.charge(records: $0, work: $0)
            }
            let igesWitness = try instance.originalIGES?.adjusted(by: displacement, conjugates: true, usage: &budget)
            let shifted: AffineTransform3D
            if let igesWitness {
                let matrix = igesWitness.matrixFrameID.flatMap { originalMatrices[$0] }
                shifted = try igesWitness.derivedAffineTransform(matrix: matrix, tolerance: tolerance,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth, usage: &budget)
            } else if let witness {
                shifted = try witness.derivedAffineTransform(tolerance: tolerance,
                    maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumDepth, usage: &budget)
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
            try budget.charge(records: 1, work: 1)
            let count = association.originalIGESAdjustments.count.addingReportingOverflow(1)
            guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES pose adjustment count overflows.") }
            try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &budget)
            shiftedCurvePositions[id] = .init(frameID: association.frameID, parameterLengthUnit: association.parameterLengthUnit,
                originalIGESAdjustments: association.originalIGESAdjustments + [.init(displacement: displacement, conjugates: false)])
        }
        var shiftedSurfacePositions = surfacePositionFrames
        for (id, association) in surfacePositionFrames where originalMatrices[association.frameID] != nil {
            try budget.charge(records: 1, work: 1)
            let count = association.originalIGESAdjustments.count.addingReportingOverflow(1)
            guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES surface pose adjustment count overflows.") }
            try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &budget)
            shiftedSurfacePositions[id] = .init(frameID: association.frameID, parameterLengthUnit: association.parameterLengthUnit,
                originalIGESAdjustments: association.originalIGESAdjustments + [.init(displacement: displacement, conjugates: false)])
        }
        var shiftedItems: [IndependentShapeItem] = []
        for item in items {
            try budget.charge(records: 1, work: 16)
            shiftedItems.append(IndependentShapeItem(id: item.id, name: item.name, geometry: item.geometry,
                trimmingSource: item.trimmingSource?.translated(by: displacement),
                traversalSource: try item.traversalSource.map { original in
                    try GeometryStructuralComparisonWork.charge(curve: original) { try budget.charge(work: $0) }
                    return try translatedCurve(original, by: transform, tolerance: tolerance,
                        remainingDepth: limits.maximumDepth, budget: &budget)
                }))
        }
        var shiftedLinearSources: [CurveID: OriginalSTEPLineSource] = [:]
        for (id, source) in curveLinearSources {
            try budget.charge(records: source.adjustments.count + 2, work: source.adjustments.count + 1)
            shiftedLinearSources[id] = try source.translated(by: displacement)
        }
        let result = IndependentShapeSource(geometry: shiftedGeometry, items: shiftedItems, geometricSets: geometricSets,
            contexts: contexts, ambientContexts: ambientContexts, representations: representations, frames: shiftedFrames, definitions: shiftedDefinitions,
            curveNames: curveNames, surfaceNames: surfaceNames, curvePositionFrames: shiftedCurvePositions,
            surfacePositionFrames: shiftedSurfacePositions, surfaceAngularMeasures: surfaceAngularMeasures, curveLinearSources: shiftedLinearSources, curveSplineSources: curveSplineSources, surfaceSplineSources: surfaceSplineSources, groups: groups, originalSTEPGroups: originalSTEPGroups, instances: shiftedInstances, productAssociations: productAssociations, ambientOriginalAngularSource: ambientOriginalAngularSource, ambientOriginalLengthSource: ambientOriginalLengthSource, roots: roots)
        _ = try DefaultIndependentShapeSourceValidator().validate(result, tolerance: tolerance, limits: budget.remaining, bodySourceGraph: bodySourceGraph)
        return result
    }
}

private func translatedCurve(_ source: Curve3D, by transform: RigidTransform3D,
    tolerance: ModelingTolerance, remainingDepth: Int, budget: inout IndependentShapeSourceBudget) throws -> Curve3D {
    guard remainingDepth > 0 else {
        throw IndependentShapeSourceError.resourceLimitExceeded("Translated curve source depth.")
    }
    try budget.charge(work: 1)
    switch source {
    case .originalAffineWord(let image):
        let action = try AffineTransform3D(basisX: transform.basisX, basisY: transform.basisY,
            basisZ: transform.basisZ, translation: transform.translation)
        let word = try image.operationWord.appending(.forward(action), tolerance: tolerance, usage: &budget)
        return .originalAffineWord(try OriginalAffineWordCurve3D(source: image.source,
            operationWord: word, tolerance: tolerance, remainingSourceDepth: remainingDepth,
            maximumSubdivisionDepth: budget.limits.maximumCurveSubdivisionDepth,
            maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget))
    case .parameterImage(let image):
        let shifted = try translatedCurve(image.source, by: transform, tolerance: tolerance,
            remainingDepth: remainingDepth - 1, budget: &budget)
        return .parameterImage(ParameterImageCurve3D(validatedSource: shifted,
            parameterGain: image.parameterGain, offset: image.offset))
    default:
        return try transform.applying(to: source, tolerance: tolerance)
    }
}

private func translatedSurface(_ source: Surface3D, by transform: RigidTransform3D,
    tolerance: ModelingTolerance, remainingDepth: Int, budget: inout IndependentShapeSourceBudget) throws -> Surface3D {
    guard remainingDepth > 0 else {
        throw IndependentShapeSourceError.resourceLimitExceeded("Translated surface source depth.")
    }
    try budget.charge(work: 1)
    if case .procedural(.originalImage(let image)) = source,
       image.transform.basisX == .unitX, image.transform.basisY == .unitY,
       image.transform.basisZ == .unitZ, image.transform.translation == .zero {
        let shifted = try translatedSurface(image.source, by: transform, tolerance: tolerance,
            remainingDepth: remainingDepth - 1, budget: &budget)
        return .parameterImage(image.replacingSourceKeepingChart(with: shifted))
    }
    if case .procedural(.originalAffineWord(let image)) = source {
        let action = try AffineTransform3D(basisX: transform.basisX, basisY: transform.basisY,
            basisZ: transform.basisZ, translation: transform.translation)
        let word = try image.operationWord.appending(.forward(action), tolerance: tolerance, usage: &budget)
        return .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: image.source,
            operationWord: word, tolerance: tolerance, remainingSourceDepth: remainingDepth,
            maximumSubdivisionDepth: budget.limits.maximumCurveSubdivisionDepth,
            maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)))
    }
    return try transform.applying(to: source, tolerance: tolerance)
}
