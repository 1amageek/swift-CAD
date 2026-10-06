import CADCore
import CADGeometry
import CADTopology

public struct DefaultIndependentShapeSourceValidator: IndependentShapeSourceValidating {
    public init() {}

    public func validate(_ source: IndependentShapeSource, tolerance: ModelingTolerance,
                         limits: IndependentShapeSourceLimits = .standard, bodySourceGraph: DesignGraph? = nil) throws -> IndependentShapeSourceValidation {
        try validate(source, tolerance: tolerance, limits: limits, bodySourceGraph: bodySourceGraph, check: {})
    }

    public func validate(_ source: IndependentShapeSource, tolerance: ModelingTolerance,
                         limits: IndependentShapeSourceLimits, bodySourceGraph: DesignGraph? = nil, check: @escaping () throws -> Void) throws -> IndependentShapeSourceValidation {
        try limits.validate()
        try tolerance.validate()
        var budget = Budget(limits: limits, check: check)
        // Admit all record storage and scan work before creating a duplicate/index set.
        for count in [source.geometry.curves.count, source.geometry.surfaces.count,
                      source.items.count, source.geometricSets.count, source.contexts.count, source.ambientContexts.count, source.representations.count,
                      source.frames.count, source.definitions.count, source.curveNames.count, source.surfaceNames.count,
                      source.curvePositionFrames.count, source.surfacePositionFrames.count, source.surfaceAngularMeasures.count, source.curveLinearSources.count,
                      source.curveSplineSources.count, source.surfaceSplineSources.count,
                      source.groups.count, source.originalSTEPGroups.count, source.instances.count, source.productAssociations.count, source.roots.count] {
            try budget.records(count)
        }
        for group in source.groups { try budget.records(group.members.count); try budget.records(group.backPointerMembers.count) }
        for set in source.geometricSets { try budget.records(set.members.count) }
        for representation in source.representations { try budget.records(representation.members.count) }
        var hasBodySelection = false
        if bodySourceGraph != nil, source.items.isEmpty, source.frames.isEmpty {
            for reference in source.roots {
                try budget.work(1)
                if case .body = reference { hasBodySelection = true }
            }
            for representation in source.representations {
                for reference in representation.members {
                    try budget.work(1)
                    if case .body = reference { hasBodySelection = true }
                }
            }
            for group in source.groups {
                for reference in group.members {
                    try budget.work(1)
                    if case .body = reference { hasBodySelection = true }
                }
            }
        }
        let hasGeometricSelection = !source.items.isEmpty || !source.frames.isEmpty || hasBodySelection
        guard hasGeometricSelection && !source.roots.isEmpty || !source.originalSTEPGroups.isEmpty else {
            throw IndependentShapeSourceError.invalidSource("Independent source requires real rooted geometry or actual original GROUP declarations.")
        }
        for curve in source.geometry.curves.values {
            try GeometryStructuralComparisonWork.charge(curve: curve) { try budget.work($0) }
            try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: limits.maximumDepth,
                maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
                consumeWork: { _ in try budget.work(1) }, consumeStorage: { try budget.geometryStorage($0) }, maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        }
        for surface in source.geometry.surfaces.values {
            try GeometryStructuralComparisonWork.charge(surface: surface) { try budget.work($0) }
            try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: limits.maximumDepth,
                maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
                consumeWork: { _ in try budget.work(1) }, consumeStorage: { try budget.geometryStorage($0) }, maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        }
        var items: [IndependentShapeItemID: IndependentShapeItem] = [:]
        var sets: [IndependentShapeSetID: IndependentShapeGeometricSet] = [:]
        var contexts: [IndependentShapeContextID: IndependentShapeContext] = [:]
        var representations: [IndependentShapeRepresentationID: IndependentShapeRepresentation] = [:]
        var stepElements: [PortableIdentity128: (kind: String, value: OriginalSTEPPlacementElement)] = [:]
        var frames: [IndependentShapeFrameID: IndependentShapeFrame] = [:]
        var frameContexts: [IndependentShapeFrameID: Set<IndependentShapeContextID>] = [:]
        var definitions: [IndependentShapeDefinitionID: IndependentShapeDefinition] = [:]
        var igesDefinitions: [IndependentShapeRepresentationID: IndependentShapeDefinition] = [:]
        var igesForwardFrames = Set<IndependentShapeFrameID>()
        var groups: [IndependentShapeGroupID: IndependentShapeGroup] = [:]
        var stepGroupOwners: [IndependentShapeSTEPGroupID: IndependentShapeSTEPGroup] = [:]
        var instances: [IndependentShapeInstanceID: IndependentShapeInstance] = [:]
        var curves = Set<CurveID>(), surfaces = Set<SurfaceID>()
        var lengthRegistry = LengthRegistry()
        var angularUnits: [IndependentShapeAngularUnitID: IndependentShapeAngularSource] = [:]
        var angularDimensions: [IndependentShapeAngularDimensionsID: [Double]] = [:]
        var angularMeasures: [IndependentShapeAngularMeasureID: IndependentShapeAngularConversion] = [:]
        var angularDepth = 0
        var angularAssociatedItems = Set<IndependentShapeItemID>()
        var previousItem: IndependentShapeItemID?
        for item in source.items {
            try budget.work(1)
            if let previousItem, !(previousItem < item.id) { throw invalid("Item IDs must be unique and canonically sorted.") }
            previousItem = item.id
            try budget.text(item.name)
            switch item.geometry {
            case .curve(let id, let trim):
                guard let basis = source.geometry.curves[id] else { throw missing("Item curve \(id).") }
                let curve = try item.resolvedCurve(in: source.geometry).curve
                if let traversal = item.traversalSource {
                    try GeometryStructuralComparisonWork.charge(curve: traversal) { try budget.work($0) }
                    try traversal.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: limits.maximumDepth,
                        maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth, consumeWork: { _ in try budget.work(1) },
                        consumeStorage: { try budget.geometryStorage($0) }, maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
                    guard trim != nil, item.trimmingSource != nil else {
                        throw invalid("Directed chart lacks its original selectors and finite selection.")
                    }
                    if IndependentShapeAngularCurveSelection.physicalArcTransport(in: traversal) != nil {
                        guard trim?.startParameter == 0, trim?.endParameter == 1 else {
                            throw invalid("Original physical arc must retain its complete normalized traversal.")
                        }
                    }
                    if case .parameterImage(let chart) = traversal,
                       case .difference(let difference) = chart.parameterGain {
                        guard trim?.startParameter == 0, trim?.endParameter == 1,
                              chart.offset == difference.originalLower else {
                            throw invalid("Directed periodic chart has conflicting original labels.")
                        }
                        let rebound = try OriginalPeriodicCurveTraversal.normalized(source: chart.source,
                            originalStart: difference.originalLower, originalEnd: difference.originalUpper,
                            translation: difference.periodicTranslation, remainingSourceDepth: limits.maximumDepth,
                            maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth, tolerance: tolerance, usage: &budget)
                        guard rebound == chart else { throw invalid("Directed chart's retained periodic authority belongs to another original curve.") }
                    }

                }
                if let trim {
                    try budget.work(3)
                    guard trim.startParameter.isFinite, trim.endParameter.isFinite,
                          trim.startParameter != trim.endParameter,
                          (trim.endParameter - trim.startParameter).isFinite else { throw invalid("Curve trim must be a finite nonzero directed interval.") }
                    if case .closed(let lower, let upper) = curve.parameterDomain {
                        guard min(trim.startParameter, trim.endParameter) >= lower,
                              max(trim.startParameter, trim.endParameter) <= upper else { throw invalid("Curve trim exceeds the original closed domain.") }
                    }
                }
                if let selectors = item.trimmingSource {
                    guard let trim else { throw invalid("Original trimming selectors lack their selected traversal.") }
                    let increasing: Bool
                    if case .parameterImage(let chart)? = item.traversalSource {
                        increasing = try chart.parameterGain.exactCoefficient(usage: &budget).isPositive
                    } else if let transport = IndependentShapeAngularCurveSelection.physicalArcTransport(in: curve) {
                        increasing = try transport.orientationSign(usage: &budget) > 0
                    } else { increasing = trim.endParameter > trim.startParameter }
                    guard selectors.agreesWithBasis == increasing else { throw invalid("Original trimming selectors conflict with resolved traversal.") }
                    for (values, endpoint) in [(selectors.first, trim.startParameter), (selectors.second, trim.endParameter)] {
                        guard values.count == 1 || values.count == 2 else { throw invalid("Original trim must retain one or two selectors.") }
                        try budget.records(values.count); try budget.work(values.count * 16)
                        try GeometryStructuralComparisonWork.charge(curve: curve) { try budget.work($0) }
                        let expected = try curve.point(at: endpoint, tolerance: tolerance)
                        var hasParameter = false, hasPoint = false
                        for value in values {
                            switch value {
                            case .parameter(let parameter):
                                guard !hasParameter, parameter.isFinite else { throw invalid("Repeated or nonfinite original trim parameter.") }
                                hasParameter = true
                                // Exact physical endpoint coefficients are checked against the descriptor below.
                                if IndependentShapeAngularCurveSelection.physicalArcTransport(in: curve) != nil { continue }
                                let selectorCurve: Curve3D
                                if case .parameterImage(let chart)? = item.traversalSource,
                                   case .difference = chart.parameterGain { selectorCurve = chart.source }
                                else { selectorCurve = item.traversalSource ?? basis }
                                let actual = try selectorCurve.point(at: parameter, tolerance: tolerance)
                                guard (expected - actual).length <= tolerance.distance else { throw invalid("Original trim parameter disagrees with resolved source endpoint.") }
                            case .point(let point):
                                guard !hasPoint, point.isFinite, (expected - point).length <= tolerance.distance else { throw invalid("Original Cartesian trim disagrees with resolved source endpoint.") }
                                hasPoint = true
                            }
                        }
                    }
                }
                curves.insert(id)
            case .surface(let id):
                guard item.trimmingSource == nil, item.traversalSource == nil else { throw invalid("A surface item cannot own curve trimming selectors.") }
                guard source.geometry.surfaces[id] != nil else { throw missing("Item surface \(id).") }
                surfaces.insert(id)
            }
            items[item.id] = item
        }
        guard curves.count == source.geometry.curves.count, surfaces.count == source.geometry.surfaces.count else {
            throw invalid("Every original geometry law must have a real item selection.")
        }
        for (id, name) in source.curveNames {
            try budget.work(1)
            guard source.geometry.curves[id] != nil else { throw missing("Named original curve \(id).") }
            try budget.text(name)
        }
        for (id, name) in source.surfaceNames {
            try budget.work(1)
            guard source.geometry.surfaces[id] != nil else { throw missing("Named original surface \(id).") }
            try budget.text(name)
        }
        try canonicalIDs(source.geometricSets.lazy.map(\.id), budget: &budget)
        for set in source.geometricSets {
            try budget.text(set.name)
            guard !set.members.isEmpty else { throw invalid("A geometric set must have real selections.") }
            try canonicalIDs(set.members, budget: &budget)
            for itemID in set.members {
                try budget.work(1)
                guard let item = items[itemID] else { throw missing("Geometric set item \(itemID).") }
                if set.family == .curves, case .surface = item.geometry { throw invalid("Original geometric curve set contains a surface.") }
            }
            sets[set.id] = set
        }
        try canonicalIDs(source.contexts.lazy.map(\.id), budget: &budget)
        for context in source.contexts {
            try budget.text(context.identifier); try budget.text(context.type)
            try budget.work(2); try context.units.validate()
            contexts[context.id] = context
        }
        let angularContextCount = try budget.sum(source.contexts.count, source.ambientContexts.count)
        for index in 0...angularContextCount {
            try budget.work(1)
            let originalAngularSource: IndependentShapeAngularSource?
            if index < source.contexts.count { originalAngularSource = source.contexts[index].originalAngularSource }
            else if index < angularContextCount { originalAngularSource = source.ambientContexts[index - source.contexts.count].originalAngularSource }
            else { originalAngularSource = source.ambientOriginalAngularSource }
            if var angular = originalAngularSource {
                var active = Set<IndependentShapeAngularUnitID>(), depth = 0
                while true {
                    try budget.records(1); try budget.work(2)
                    depth += 1
                    guard depth <= limits.maximumDepth, active.insert(angular.id).inserted else { throw invalid("Original angular source depth/cycle.") }
                    angularDepth = max(angularDepth, depth)
                    if let previous = angularUnits[angular.id] {
                        let same: Bool
                        switch (previous.law, angular.law) {
                        case (.radian(let a), .radian(let b)): same = a == b
                        case (.conversion(let a), .conversion(let b)):
                            try budget.work(a.name.utf8.count + b.name.utf8.count + a.dimensions.count + b.dimensions.count)
                            same = a.name.utf8.elementsEqual(b.name.utf8) && a.factor == b.factor && a.interpretation == b.interpretation
                                && a.dimensionsID == b.dimensionsID && a.dimensions == b.dimensions && a.measureID == b.measureID
                                && a.measureKind == b.measureKind && a.base.id == b.base.id
                        default: same = false
                        }
                        guard same else { throw invalid("One original angular unit identity has conflicting laws.") }
                    } else { angularUnits[angular.id] = angular }
                    switch angular.law {
                    case .radian: break
                    case .conversion(let conversion):
                        try budget.records(2 + conversion.dimensions.count); try budget.text(conversion.name)
                        guard conversion.factor.isFinite, conversion.factor > 0, conversion.dimensions.count == 7,
                              conversion.dimensions.allSatisfy({ $0.isFinite && $0 == 0 }),
                              (conversion.interpretation == .canonicalDegree) == (conversion.factor == AngleUnit.degree.toInternal(1)) else {
                            throw invalid("Original angular conversion factor, interpretation or dimensions are inconsistent.")
                        }
                        if let previous = angularDimensions[conversion.dimensionsID], previous != conversion.dimensions { throw invalid("Shared angular dimensions conflict.") }
                        angularDimensions[conversion.dimensionsID] = conversion.dimensions
                        if let previous = angularMeasures[conversion.measureID], previous.factor != conversion.factor
                            || previous.interpretation != conversion.interpretation || previous.measureKind != conversion.measureKind
                            || previous.base.id != conversion.base.id { throw invalid("Shared original angular measure conflicts.") }
                        angularMeasures[conversion.measureID] = conversion
                        angular = conversion.base
                        continue
                    }
                    break
                }
            }
        }
        try canonicalIDs(source.ambientContexts.lazy.map(\.id), budget: &budget)
        var ambientIDs = Set<IndependentShapeContextID>()
        var ambientUnit: UnitSystem?
        var ambientLaw: IndependentShapeAngularSource? = source.ambientOriginalAngularSource
        var ambientAuthoritySelected = false
        for context in source.ambientContexts {
            try budget.text(context.identifier); try budget.text(context.type)
            try budget.records(1); try budget.work(4); try context.units.validate()
            guard contexts[context.id] == nil, ambientIDs.insert(context.id).inserted else {
                throw invalid("Ambient and representation context identities must have distinct actual ownership.")
            }
            if let previous = ambientUnit, previous.length != context.units.length { throw invalid("Actual ambient context length units conflict.") }
            ambientUnit = context.units
            guard let original = context.originalAngularSource else { throw invalid("Actual ambient context requires its original angular descriptor.") }
            if original.id == source.ambientOriginalAngularSource?.id { ambientAuthoritySelected = true }
            if let previous = ambientLaw {
                guard try previous.isCoordinateLawEquivalent(to: original, maximumSourceDepth: budget.limits.maximumDepth, usage: &budget) else {
                    throw invalid("Actual ambient angular context laws conflict.")
                }
            } else { ambientLaw = original }
        }
        if !source.ambientContexts.isEmpty, !ambientAuthoritySelected {
            throw invalid("Actual ambient contexts must own their selected original coordinate authority.")
        }
        let lengthContextCount = try budget.sum(source.contexts.count, source.ambientContexts.count)
        for index in 0...lengthContextCount {
            let original: OriginalSTEPLengthSource?
            if index < source.contexts.count { original = source.contexts[index].originalLengthSource }
            else if index < lengthContextCount { original = source.ambientContexts[index - source.contexts.count].originalLengthSource }
            else { original = source.ambientOriginalLengthSource }
            try lengthRegistry.validate(original, budget: &budget)
        }
        var selectedAmbientLength = source.ambientContexts.isEmpty
        var ambientLengthGain: ExactRationalCoefficient?
        for context in source.ambientContexts {
            let gain: ExactRationalCoefficient
            if let original = context.originalLengthSource {
                if original.id == source.ambientOriginalLengthSource?.id { selectedAmbientLength = true }
                gain = try original.exactGain(maximumDepth: limits.maximumDepth, usage: &budget)
            } else {
                if source.ambientOriginalLengthSource == nil { selectedAmbientLength = true }
                gain = try ExactRationalCoefficient.originalDouble(context.units.length.toInternal(1), usage: &budget)
            }
            if let previous = ambientLengthGain, previous != gain { throw invalid("Actual ambient length coordinate laws conflict.") }
            ambientLengthGain = gain
        }
        if !selectedAmbientLength { throw invalid("Actual ambient contexts must own their selected original length authority.") }
        try canonicalIDs(source.frames.lazy.map(\.id), budget: &budget)
        for frame in source.frames {
            try budget.text(frame.name)
            try budget.work(512); try frame.placement.validate()
            try validatePlacement(frame.placement, budget: &budget)
            try lengthRegistry.validate(frame.originalSTEPPlacement?.originalLengthSource, budget: &budget)
            try validateOriginalPlacement(frame.originalSTEPPlacement, derived: frame.placement,
                tolerance: tolerance, elements: &stepElements, budget: &budget)
            if let original = frame.originalIGES {
                guard frame.originalSTEPPlacement == nil else { throw invalid("A frame cannot own both STEP and IGES placement laws.") }
                try budget.records(1)
                for token in original.coefficients { try budget.text(token) }
                let expected = try original.derivedAffineTransform(tolerance: tolerance,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth, usage: &budget)
                guard expected == frame.placement else { throw invalid("Original IGES frame numeric view contradicts its retained law.") }
            }
            frames[frame.id] = frame
        }
        for (id, association) in source.curvePositionFrames {
            try budget.work(64)
            guard let curve = source.geometry.curves[id], let frame = frames[association.frameID] else {
                throw missing("Original curve position association.")
            }
            try validatePosition(curve: curve, association: association, originalFrame: frame, frame: frame.placement, tolerance: tolerance, budget: &budget)
        }
        for (id, association) in source.surfacePositionFrames {
            try budget.work(32)
            guard let surface = source.geometry.surfaces[id], let frame = frames[association.frameID] else {
                throw missing("Original surface position association.")
            }
            try validatePosition(surface: surface, association: association, originalFrame: frame, frame: frame.placement, tolerance: tolerance, budget: &budget)
        }
        var originalVectors: [PortableIdentity128: OriginalSTEPLineSource] = [:]
        for (id, linear) in source.curveLinearSources {
            try budget.records(3); try budget.text(linear.vectorName)
            try lengthRegistry.validate(linear.originalLengthSource, budget: &budget)
            guard stepElements[linear.vectorID] == nil else { throw invalid("Original VECTOR identity conflicts with a point/direction record.") }
            for (kind, element) in [("point", linear.location), ("direction", linear.direction)] {
                guard originalVectors[element.id] == nil else { throw invalid("Original point/direction identity conflicts with a VECTOR record.") }
                try budget.text(element.name)
                if let old = stepElements[element.id] {
                    guard old.kind == kind, old.value == element else { throw invalid("Shared original LINE/placement element conflicts.") }
                } else { stepElements[element.id] = (kind, element) }
            }
            if let old = originalVectors[linear.vectorID] {
                guard old.direction == linear.direction, old.magnitude == linear.magnitude,
                      old.vectorName.utf8.elementsEqual(linear.vectorName.utf8) else {
                    throw invalid("Shared original VECTOR has conflicting source values.")
                }
            } else { originalVectors[linear.vectorID] = linear }
            guard source.curvePositionFrames[id] == nil, let original = source.geometry.curves[id],
                  case .originalAffineWord(let image) = original, case .line(let local) = image.source,
                  local.origin == .origin, local.direction == .unitX else { throw invalid("Original LINE carrier is not bound to its retained original word curve.") }
            let expected = try linear.originalOperationWord(tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
            guard try image.operationWord.isEquivalent(to: expected, tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget) else {
                throw invalid("Original LINE word disagrees with its source VECTOR law.")
            }
        }
        for (id, metadata) in source.curveSplineSources {
            guard source.curveLinearSources[id] == nil, source.curvePositionFrames[id] == nil,
                  let curve = source.geometry.curves[id], case .originalAffineWord(let image) = curve,
                  case .bSpline(let spline) = image.source,
                  metadata.controlPoints.count == spline.controlPoints.count else {
                throw invalid("Original spline curve metadata is not bound to its raw control law.")
            }
            try budget.records(metadata.controlPoints.count)
            for index in metadata.controlPoints.indices {
                let original = metadata.controlPoints[index], point = spline.controlPoints[index]
                guard original.coordinates == Vector3D(x: point.x, y: point.y, z: point.z),
                      originalVectors[original.id] == nil else { throw invalid("Original spline curve control coordinate or identity conflicts.") }
                try budget.text(original.name)
                if let previous = stepElements[original.id] {
                    guard previous.kind == "point", previous.value == original else { throw invalid("Shared original spline point records conflict.") }
                } else { stepElements[original.id] = ("point", original) }
                if !metadata.isRational, spline.weights[index] != 1 { throw invalid("Nonrational original curve has nonunit weights.") }
            }
        }
        for (id, metadata) in source.surfaceSplineSources {
            guard source.surfacePositionFrames[id] == nil,
                  let surface = source.geometry.surfaces[id], case .procedural(.originalAffineWord(let image)) = surface,
                  case .bSpline(let spline) = image.source,
                  metadata.controlPointRows.count == spline.vControlPointCount else {
                throw invalid("Original spline surface metadata is not bound to its raw control law.")
            }
            try budget.records(metadata.controlPointRows.count)
            for v in metadata.controlPointRows.indices {
                let row = metadata.controlPointRows[v]
                guard row.count == spline.uControlPointCount else { throw invalid("Original spline control metadata is nonrectangular.") }
                try budget.records(row.count)
                for u in row.indices {
                    let original = row[u], point = spline.controlPoints[v][u]
                    guard original.coordinates == Vector3D(x: point.x, y: point.y, z: point.z),
                          originalVectors[original.id] == nil else { throw invalid("Original spline surface control coordinate or identity conflicts.") }
                    try budget.text(original.name)
                    if let previous = stepElements[original.id] {
                        guard previous.kind == "point", previous.value == original else { throw invalid("Shared original spline surface point records conflict.") }
                    } else { stepElements[original.id] = ("point", original) }
                    if !metadata.isRational, spline.weights[v][u] != 1 { throw invalid("Nonrational original surface has nonunit weights.") }
                }
            }
        }
        try canonicalIDs(source.representations.lazy.map(\.id), budget: &budget)
        for representation in source.representations {
            try budget.text(representation.name)
            guard let context = contexts[representation.contextID] else { throw missing("Representation context \(representation.contextID).") }
            guard !representation.members.isEmpty else { throw invalid("A representation must have real members.") }
            try canonical(representation.members, budget: &budget)
            for member in representation.members {
                try budget.work(1)
                switch member {
                case .item(let id):
                    guard let item = items[id] else { throw missing("Original representation item.") }
                    try budget.records(1); angularAssociatedItems.insert(item.id)
                    try validateAngularBinding(item: item, source: source, originalAngularSource: context.originalAngularSource, tolerance: tolerance, budget: &budget)
                    try validateLengthBinding(item: item, source: source, frames: frames,
                        originalLengthSource: context.originalLengthSource, units: context.units, budget: &budget)
                case .geometricSet(let id):
                    guard let set = sets[id] else { throw missing("Original representation geometric set.") }
                    for id in set.members {
                        try budget.work(1)
                        guard let item = items[id] else { throw missing("Original geometric-set item.") }
                        try budget.records(1); angularAssociatedItems.insert(item.id)
                    try validateAngularBinding(item: item, source: source, originalAngularSource: context.originalAngularSource, tolerance: tolerance, budget: &budget)
                    try validateLengthBinding(item: item, source: source, frames: frames,
                        originalLengthSource: context.originalLengthSource, units: context.units, budget: &budget)
                    }
                case .body:
                    guard representation.family == .shape || representation.family == .representation else {
                        throw invalid("Original Body membership conflicts with the bounded independent representation family.")
                    }
                case .instance, .group: break
                case .frame(let id):
                    guard frames[id] != nil else { throw missing("Representation frame \(id).") }
                    try budget.work(1)
                    frameContexts[id, default: []].insert(representation.contextID)
                case .representation: throw invalid("Representation membership must be a real item, geometric set, frame, group or instance.")
                }
            }
            representations[representation.id] = representation
        }
        for item in source.items {
            try budget.work(1)
            if !angularAssociatedItems.contains(item.id) {
                try validateAngularBinding(item: item, source: source,
                    originalAngularSource: source.ambientOriginalAngularSource, tolerance: tolerance, budget: &budget)
            }
        }
        for item in source.items {
            try budget.work(1)
            if !angularAssociatedItems.contains(item.id) {
                // An absent foreign source retains the native unit convention only when no raw frame declares another law.
                try budget.work(source.frames.count)
                let lineUnit: LengthUnit?
                if case .curve(let id, _) = item.geometry { lineUnit = source.curveLinearSources[id]?.lengthUnit } else { lineUnit = nil }
                let nativeUnits = lineUnit ?? source.frames.first(where: { frame in
                    switch item.geometry {
                    case .curve(let id, _): return source.curvePositionFrames[id]?.frameID == frame.id
                    case .surface(let id): return source.surfacePositionFrames[id]?.frameID == frame.id
                    }
                })?.originalSTEPPlacement?.lengthUnit ?? .meter
                try validateLengthBinding(item: item, source: source, frames: frames,
                    originalLengthSource: source.ambientOriginalLengthSource, units: UnitSystem(length: nativeUnits), budget: &budget)
            }
        }
        for (id, measure) in source.surfaceAngularMeasures {
            try budget.work(2)
            guard let surface = source.geometry.surfaces[id] else { throw missing("Original angular surface measure owner.") }
            guard case .coneSemiAngle(let original) = measure, original.isFinite, original > 0,
                  case .procedural(.originalImage(let image)) = surface,
                  case .analytic(.cone(_, _, let halfAngle)) = image.source,
                  try image.uParameterGain.applied(to: original, usage: &budget) == halfAngle else {
                throw invalid("Original cone semi-angle does not produce its native analytic angle.")
            }
        }
        var previousAssociation: IndependentShapeProductAssociation?
        for association in source.productAssociations {
            try budget.work(2)
            if let previousAssociation, !(previousAssociation < association) { throw invalid("Product associations must be unique and canonically sorted.") }
            guard representations[association.representationID] != nil else { throw missing("Product-associated original representation.") }
            previousAssociation = association
        }
        try canonicalIDs(source.definitions.lazy.map(\.id), budget: &budget)
        for definition in source.definitions {
            try budget.work(2)
            guard let representation = representations[definition.representationID] else { throw missing("Definition representation \(definition.representationID).") }
            if let original = definition.originalIGES {
                try budget.records(1); try budget.work(2); try budget.text(original.directoryLabel)
                guard definition.originFrameID == nil, igesDefinitions[definition.representationID] == nil else {
                    throw invalid("Original IGES template requires a unique forward definition without an inverse STEP origin.")
                }
                if let frameID = original.definingFrameID {
                    guard let frame = frames[frameID], frame.originalSTEPPlacement == nil else { throw missing("Original IGES definition forward frame.") }
                    try budget.records(1); igesForwardFrames.insert(frameID)
                }
                let matrix = original.definingFrameID.flatMap { frames[$0]?.originalIGES }
                _ = try original.originalOperationWord(frame: matrix, tolerance: tolerance,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth, usage: &budget)
                igesDefinitions[definition.representationID] = definition
            }
            if let originID = definition.originFrameID {
                guard frames[originID] != nil else { throw missing("Definition origin frame \(originID).") }
                guard frameContexts[originID]?.contains(representation.contextID) == true else {
                    throw invalid("Mapping origin must have actual representation membership in the mapped context.")
                }
            }
            definitions[definition.id] = definition
        }
        for definition in source.definitions {
            try budget.work(1)
            if let originID = definition.originFrameID, igesForwardFrames.contains(originID) {
                throw invalid("One original frame cannot own both forward IGES definition and inverse STEP origin semantics.")
            }
        }
        var previousSTEPOwner: IndependentShapeSTEPGroupID?
        for owner in source.originalSTEPGroups {
            try budget.work(1)
            if let previousSTEPOwner, !(previousSTEPOwner < owner.id) { throw invalid("Original STEP GROUP owner IDs must be unique and canonical.") }
            previousSTEPOwner = owner.id
            try budget.text(owner.name)
            if let description = owner.description { try budget.text(description) }
            stepGroupOwners[owner.id] = owner
        }
        var previousGroup: IndependentShapeGroupID?
        for group in source.groups {
            try budget.work(1)
            if let previousGroup, !(previousGroup < group.id) { throw invalid("Group IDs must be unique and canonically sorted.") }
            previousGroup = group.id
            try budget.text(group.name)
            if let description = group.description { try budget.text(description) }
            guard !group.members.isEmpty else { throw invalid("A group must have real members.") }
            if let ownerID = group.originalSTEPGroupID {
                guard group.family == .unordered, group.backPointerMembers.isEmpty else {
                    throw invalid("Original STEP assignment cannot carry ordered or inverse-pointer group obligations.")
                }
                if let previous = stepGroupOwners[ownerID] {
                    try budget.work(try budget.sum(previous.name.utf8.count, group.name.utf8.count))
                    guard previous.name.utf8.elementsEqual(group.name.utf8) else {
                        throw invalid("Shared original STEP GROUP has inconsistent name.")
                    }
                    switch (previous.description, group.description) {
                    case (nil, nil): break
                    case (.some(let a), .some(let b)):
                        try budget.work(try budget.sum(a.utf8.count, b.utf8.count))
                        guard a.utf8.elementsEqual(b.utf8) else { throw invalid("Shared original STEP GROUP has inconsistent description.") }
                    default: throw invalid("Shared original STEP GROUP has inconsistent nullable description.")
                    }
                } else { throw missing("Original STEP GROUP owner \(ownerID).") }
            }
            if !group.family.isOrdered { try canonical(group.members, budget: &budget) }
            try canonical(group.backPointerMembers, budget: &budget)
            // Compare original membership without allocating a detached inverse graph.
            for inverse in group.backPointerMembers {
                var found = false
                for member in group.members { try budget.work(1); if member == inverse { found = true; break } }
                guard found else { throw invalid("Group inverse pointer selects a nonmember.") }
            }
            if group.family.requiresBackPointers {
                for member in group.members {
                    var found = false
                    for inverse in group.backPointerMembers { try budget.work(1); if member == inverse { found = true; break } }
                    guard found else { throw invalid("Required group inverse membership is absent.") }
                }
            }
            groups[group.id] = group
        }
        var previousInstance: IndependentShapeInstanceID?
        for instance in source.instances {
            try budget.work(1)
            if let previousInstance, !(previousInstance < instance.id) { throw invalid("Instance IDs must be unique and canonically sorted.") }
            previousInstance = instance.id
            try budget.text(instance.name); try budget.text(instance.placementName)
            // Fixed original 3x3 interval determinant work and scratch are admitted before arithmetic.
            try budget.work(512)
            try instance.placement.validate()
            try validatePlacement(instance.placement, budget: &budget)
            try lengthRegistry.validate(instance.originalSTEPPlacement?.originalLengthSource, budget: &budget)
            try validateOriginalPlacement(instance.originalSTEPPlacement, derived: instance.placement,
                tolerance: tolerance, elements: &stepElements, budget: &budget)
            if let original = instance.originalIGES {
                guard instance.originalSTEPPlacement == nil else { throw invalid("An instance cannot own both STEP and IGES placement laws.") }
                try budget.records(1); try budget.text(original.scale)
                for token in original.translation { try budget.text(token) }
                let matrix = original.matrixFrameID.flatMap { frames[$0]?.originalIGES }
                let expected = try original.derivedAffineTransform(matrix: matrix, tolerance: tolerance,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth, usage: &budget)
                guard expected == instance.placement else { throw invalid("Original IGES instance numeric view contradicts its retained law.") }
            }
            guard definitions[instance.target] != nil else { throw missing("Instance definition \(instance.target).") }
            instances[instance.id] = instance
        }
        for id in originalVectors.keys {
            try budget.work(1)
            guard stepElements[id] == nil else { throw invalid("Original VECTOR identity conflicts with a later point/direction record.") }
        }
        for representation in source.representations where representation.family == .geometricallyBoundedWireframe || representation.family == .geometricallyBoundedSurface {
            var hasGeometry = false, hasSurface = false
            for member in representation.members {
                try budget.work(1)
                switch member {
                case .frame: break
                case .geometricSet(let id):
                    guard let set = sets[id] else { throw missing("Original bounded geometric set.") }
                    guard representation.family != .geometricallyBoundedWireframe || set.family == .curves else {
                        throw invalid("Original bounded wireframe requires its curve-set family.")
                    }
                    hasGeometry = true
                    for selection in set.members {
                        try budget.work(1)
                        guard let item = items[selection] else { throw missing("Original bounded selection.") }
                        if case .surface = item.geometry { hasSurface = true }
                    }
                case .instance(let id):
                    guard let instance = instances[id], let definition = definitions[instance.target],
                          let target = representations[definition.representationID], target.family == representation.family else {
                        throw invalid("Original bounded map selects a different representation family.")
                    }
                    hasGeometry = true
                    if representation.family == .geometricallyBoundedSurface {
                        var childHasSet = false
                        for child in target.members { try budget.work(1); if case .geometricSet = child { childHasSet = true } }
                        guard childHasSet else { throw invalid("Original bounded surface map lacks its direct geometric set.") }
                    }
                default: throw invalid("Original bounded representation contains a non-profile member.")
                }
            }
            guard hasGeometry else { throw invalid("Original bounded representation has no geometric set or mapped geometry.") }
            if representation.family == .geometricallyBoundedSurface, !hasSurface {
                throw invalid("Original bounded surface representation lacks its direct surface selection.")
            }
        }
        try canonical(source.roots, budget: &budget)
        enum Pending { case enter(IndependentShapeReference); case leave(IndependentShapeReference) }
        var pending: [Pending] = []
        for root in source.roots.reversed() { try budget.work(1); pending.append(.enter(root)) }
        var active = Set<IndependentShapeReference>()
        var heights: [IndependentShapeReference: Int] = [:]
        var observedDepth = max(angularDepth, source.originalSTEPGroups.isEmpty ? 0 : 1)
        var usedDefinitions = Set<IndependentShapeDefinitionID>()
        var usedContexts = Set<IndependentShapeContextID>()
        var usedBodies = Set<SubshapeID>()
        while let next = pending.popLast() {
            try budget.work(1)
            switch next {
            case .enter(let reference):
                if heights[reference] != nil { continue }
                guard active.insert(reference).inserted else { throw IndependentShapeSourceError.cycle(reference) }
                try budget.work(1)
                pending.append(.leave(reference))
                switch reference {
                case .body(let selector):
                    try IndependentShapeBodySourceAuthority.validate(selector, in: bodySourceGraph) { records, work in
                        try budget.records(records); try budget.work(work)
                    }
                    usedBodies.insert(selector)
                case .frame(let id): guard frames[id] != nil else { throw missing("Frame \(id).") }
                case .item(let id):
                    guard let item = items[id] else { throw missing("Item \(id).") }
                    if let position = positionFrame(item, source: source) {
                        try budget.work(1); pending.append(.enter(.frame(position)))
                    }
                case .geometricSet(let id):
                    guard let set = sets[id] else { throw missing("Geometric set \(id).") }
                    for child in set.members.reversed() { try budget.work(1); pending.append(.enter(.item(child))) }
                case .representation(let id):
                    guard let representation = representations[id] else { throw missing("Representation \(id).") }
                    try budget.work(1); usedContexts.insert(representation.contextID)
                    if let definition = igesDefinitions[id] {
                        try budget.work(1); usedDefinitions.insert(definition.id)
                        if let frameID = definition.originalIGES?.definingFrameID { pending.append(.enter(.frame(frameID))) }
                    }
                    for child in representation.members.reversed() { try budget.work(1); pending.append(.enter(child)) }
                case .group(let id):
                    guard let group = groups[id] else { throw missing("Group \(id).") }
                    for child in group.members.reversed() { try budget.work(1); pending.append(.enter(child)) }
                case .instance(let id):
                    guard let instance = instances[id] else { throw missing("Instance \(id).") }
                    guard let definition = definitions[instance.target] else { throw missing("Instance definition \(instance.target).") }
                    try budget.work(2); usedDefinitions.insert(definition.id)
                    if let frameID = instance.originalIGES?.matrixFrameID { try budget.work(1); pending.append(.enter(.frame(frameID))) }
                    pending.append(.enter(.representation(definition.representationID)))
                }
            case .leave(let reference):
                var height = 1
                switch reference {
                case .body, .frame: break
                case .item(let id):
                    guard let item = items[id] else { throw missing("Item \(id).") }
                    if let position = positionFrame(item, source: source) {
                        try budget.work(1)
                        guard let childHeight = heights[.frame(position)], childHeight < Int.max else {
                            throw invalid("Incomplete original position traversal.")
                        }
                        height = childHeight + 1
                    }
                case .geometricSet(let id):
                    guard let set = sets[id] else { throw missing("Geometric set \(id).") }
                    for child in set.members {
                        try budget.work(1)
                        guard let childHeight = heights[.item(child)], childHeight < Int.max else { throw invalid("Incomplete geometric set child traversal.") }
                        height = max(height, childHeight + 1)
                    }
                case .representation(let id):
                    guard let representation = representations[id] else { throw missing("Representation \(id).") }
                    for child in representation.members {
                        try budget.work(1)
                        guard let childHeight = heights[child], childHeight < Int.max else { throw invalid("Incomplete representation child traversal.") }
                        height = max(height, childHeight + 1)
                    }
                    if let definition = igesDefinitions[id] {
                        try budget.work(1)
                        height = max(height, 3)
                        if let frameID = definition.originalIGES?.definingFrameID {
                            guard let childHeight = heights[.frame(frameID)], childHeight < Int.max - 2 else {
                                throw invalid("Incomplete original IGES forward-frame traversal.")
                            }
                            height = max(height, childHeight + 2)
                        }
                    }
                case .group(let id):
                    guard let group = groups[id] else { throw missing("Group \(id).") }
                    for child in group.members {
                        try budget.work(1)
                        guard let childHeight = heights[child], childHeight < Int.max else { throw invalid("Incomplete group child traversal.") }
                        height = max(height, childHeight + 1)
                    }
                case .instance(let id):
                    guard let instance = instances[id], let definition = definitions[instance.target],
                          let childHeight = heights[.representation(definition.representationID)], childHeight < Int.max - 1 else { throw invalid("Incomplete instance child traversal.") }
                    // A real representation-map definition contributes its own source depth.
                    height = childHeight + 2
                    if let frameID = instance.originalIGES?.matrixFrameID {
                        guard let frameHeight = heights[.frame(frameID)], frameHeight < Int.max - 1 else { throw invalid("Incomplete IGES instance matrix traversal.") }
                        height = max(height, frameHeight + 2)
                    }
                }
                guard height <= limits.maximumDepth else { throw IndependentShapeSourceError.resourceLimitExceeded("Independent source DAG exceeds the caller depth ceiling.") }
                observedDepth = max(observedDepth, height)
                active.remove(reference); heights[reference] = height
            }
        }
        let expected = try budget.sum(frames.count, try budget.sum(items.count, try budget.sum(sets.count,
            try budget.sum(representations.count, try budget.sum(groups.count, instances.count)))))
        guard heights.count == (try budget.sum(expected, usedBodies.count)), usedDefinitions.count == definitions.count, usedContexts.count == contexts.count else {
            throw invalid("Every independent source owner must be reachable from an explicit root.")
        }
        return .init(consumedRecords: budget.recordCount, consumedTextBytes: budget.textCount,
                     consumedWork: budget.workCount, maximumObservedDepth: observedDepth)
    }

    private func positionFrame(_ item: IndependentShapeItem, source: IndependentShapeSource) -> IndependentShapeFrameID? {
        switch item.geometry {
        case .curve(let id, _): return source.curvePositionFrames[id]?.frameID
        case .surface(let id): return source.surfacePositionFrames[id]?.frameID
        }
    }

    private func validatePosition(curve: Curve3D, association: IndependentShapePositionFrame, originalFrame: IndependentShapeFrame, frame: AffineTransform3D, tolerance: ModelingTolerance, budget: inout Budget) throws {
        var curve = curve
        var depth = 0
        while case .parameterImage(let image) = curve {
            depth += 1; try budget.visitSourceCell(depth: depth)
            curve = image.source
        }
        if case .originalAffineWord(let image) = curve, let original = originalFrame.originalIGES {
            guard association.parameterLengthUnit == nil else { throw invalid("IGES directory pose has no independent length parameter-unit override.") }
            var expected = try original.originalOperationWord(tolerance: tolerance,
                maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
            for adjustment in association.originalIGESAdjustments {
                expected = try adjustment.applying(to: expected, tolerance: tolerance,
                    maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
            }
            guard try image.operationWord.isEquivalent(to: expected, tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget) else { throw invalid("Original IGES curve pose word is inconsistent.") }
            return
        }
        guard association.originalIGESAdjustments.isEmpty else { throw invalid("IGES pose adjustments require the actual original IGES matrix frame.") }
        if case .originalAffineWord(let image) = curve {
            guard let original = originalFrame.originalSTEPPlacement else { throw invalid("Original normalized curve position source is absent.") }
            let law = try original.originalNormalizedAffineSource(usage: &budget, maximumSourceDepth: budget.limits.maximumDepth, localCoordinatesInModelUnits: true)
            let expected = try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
            guard try image.operationWord.isEquivalent(to: expected, tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget) else { throw invalid("Original curve position word disagrees with its actual frame source.") }
            let matches: Bool
            switch image.source {
            case .circle(let circle): matches = association.parameterLengthUnit == nil && circle.center == .origin && circle.normal == .unitZ
            case .analytic(.ellipse(let center, let normal, let axis, _, _)):
                matches = association.parameterLengthUnit == nil && center == .origin && normal == .unitZ && axis == .unitX
            case .analytic(.hyperbola(let source)):
                matches = association.parameterLengthUnit == nil && source.center == .origin && source.normal == .unitZ && source.transverseAxis == .unitX
            case .analytic(.parabola(let source)):
                matches = association.parameterLengthUnit == original.lengthUnit && source.vertex == .origin && source.normal == .unitZ && source.axis == .unitX
            default: matches = false
            }
            guard matches else { throw invalid("Original curve position has a foreign local primitive law.") }
            return
        }
        try frame.basisX.validateUnitLength(tolerance: tolerance)
        try frame.basisY.validateUnitLength(tolerance: tolerance)
        try frame.basisZ.validateUnitLength(tolerance: tolerance)
        let origin = Point3D(x: frame.translation.x, y: frame.translation.y, z: frame.translation.z)
        guard frame.basisY == frame.basisZ.cross(frame.basisX) else {
            throw invalid("Original position requires its exact right-handed stored axes.")
        }
        let matches: Bool
        switch curve {
        case .affineImage(let image):
            switch image.source {
            case .circle(let circle):
                matches = association.parameterLengthUnit == nil && circle.center == .origin && circle.normal == .unitZ && image.transform == frame
            case .analytic(.parabola(let parabola)):
                guard let unit = association.parameterLengthUnit else { throw invalid("Original parabola parameter length unit is absent.") }
                let gain = unit.toInternal(1)
                matches = parabola.vertex == .origin && parabola.normal == .unitZ && parabola.axis == .unitX &&
                    image.transform.translation == frame.translation && image.transform.basisX == frame.basisX * gain &&
                    image.transform.basisY == frame.basisY * gain && image.transform.basisZ == frame.basisZ * gain
            default: matches = false
            }
        case .analytic(.ellipse(let center, let normal, let axis, _, _)):
            matches = association.parameterLengthUnit == nil && center == origin && normal == frame.basisZ && axis == frame.basisX
        case .analytic(.hyperbola(let hyperbola)):
            matches = association.parameterLengthUnit == nil && hyperbola.center == origin && hyperbola.normal == frame.basisZ && hyperbola.transverseAxis == frame.basisX
        case .analytic(.parabola(let parabola)):
            matches = association.parameterLengthUnit == .meter && parabola.vertex == origin && parabola.normal == frame.basisZ && parabola.axis == frame.basisX
        default: matches = false
        }
        guard matches else { throw invalid("Original curve position association disagrees with its stored parameter law.") }
    }

    private func validateLengthBinding(item: IndependentShapeItem, source: IndependentShapeSource,
        frames: [IndependentShapeFrameID: IndependentShapeFrame], originalLengthSource: OriginalSTEPLengthSource?,
        units: UnitSystem, budget: inout Budget) throws {
        if case .curve(let id, _) = item.geometry, let linear = source.curveLinearSources[id] {
            let contextGain = try originalLengthSource?.exactGain(maximumDepth: budget.limits.maximumDepth, usage: &budget)
                ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &budget)
            let lineGain = try linear.originalLengthSource?.exactGain(maximumDepth: budget.limits.maximumDepth, usage: &budget)
                ?? ExactRationalCoefficient.originalDouble(linear.lengthUnit.toInternal(1), usage: &budget)
            guard try contextGain.subtracting(lineGain, usage: &budget).isZero else {
                throw invalid("Original LINE and its actual context length laws disagree.")
            }
            return
        }
        let association: IndependentShapePositionFrame?
        switch item.geometry {
        case .curve(let id, _): association = source.curvePositionFrames[id]
        case .surface(let id): association = source.surfacePositionFrames[id]
        }
        guard let association, let frame = frames[association.frameID], let original = frame.originalSTEPPlacement else { return }
        let contextGain = try originalLengthSource?.exactGain(maximumDepth: budget.limits.maximumDepth, usage: &budget)
            ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &budget)
        let frameGain = try original.originalLengthSource?.exactGain(maximumDepth: budget.limits.maximumDepth, usage: &budget)
            ?? ExactRationalCoefficient.originalDouble(original.lengthUnit.toInternal(1), usage: &budget)
        guard try contextGain.subtracting(frameGain, usage: &budget).isZero else {
            throw invalid("Original positioned item and its actual context have conflicting exact length laws.")
        }
    }

    private func validateAngularBinding(item: IndependentShapeItem, source: IndependentShapeSource,
        originalAngularSource: IndependentShapeAngularSource?, tolerance: ModelingTolerance, budget: inout Budget) throws {
        if case .curve(let id, _) = item.geometry, let traversal = item.traversalSource,
           let basis = source.geometry.curves[id] {
            let selected: Curve3D
            if case .parameterImage(let chart) = traversal, case .difference = chart.parameterGain { selected = chart.source }
            else { selected = traversal }
            if selected != basis {
                guard let original = originalAngularSource else { throw invalid("Foreign selected angular chart lacks its original descriptor.") }
                let law = try original.originalCoordinateLaw(maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
                let expected: Curve3D
                if IndependentShapeAngularCurveSelection.physicalArcTransport(in: selected) != nil {
                    guard case .physicalRadians(let gain) = law, let selectors = item.trimmingSource else {
                        throw invalid("Physical arc has no actual physical-radian descriptor and selectors.")
                    }
                    func scalar(_ values: [IndependentShapeTrimmingSource.Selector]) throws -> Double {
                        for value in values { if case .parameter(let parameter) = value { return parameter } }
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Cartesian-only physical-angle inverse phase has no retained exact selector producer.
                        // Native source validation must bind the original directed phase before this selection can succeed.
                        throw invalid("Physical arc requires its retained original scalar selector authority.")
                    }
                    expected = try IndependentShapeAngularCurveSelection.physicalArc(basis: basis, gain: gain,
                        first: scalar(selectors.first), last: scalar(selectors.second), increasing: selectors.agreesWithBasis,
                        tolerance: tolerance, maximumSourceDepth: budget.limits.maximumDepth,
                        maximumSubdivisionDepth: budget.limits.maximumCurveSubdivisionDepth,
                        maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
                } else {
                    expected = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
                        tolerance: tolerance, maximumSourceDepth: budget.limits.maximumDepth,
                        maximumSubdivisionDepth: budget.limits.maximumCurveSubdivisionDepth,
                        maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
                }
                try GeometryStructuralComparisonWork.charge(curve: expected) { try budget.work($0) }
                guard selected == expected else { throw invalid("Selected angular chart is not bound to its actual original basis and descriptor.") }
            }
        }
        guard let original = originalAngularSource else { return }
        switch item.geometry {
        case .curve(let id, _):
            guard let curve = source.geometry.curves[id] else { throw missing("Original angular curve binding.") }
            if case .parameterImage(let image) = curve {
                let gain = try original.originalParameterGain(maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
                guard try image.parameterGain.isEquivalent(to: gain, usage: &budget) else {
                    throw invalid("Original curve angular descriptor disagrees with its retained image gain.")
                }
            }
        case .surface(let id):
            guard let surface = source.geometry.surfaces[id] else { throw missing("Original angular surface binding.") }
            if case .procedural(.originalAffineWord(let positioned)) = surface,
               let intrinsic = IndependentShapeAngularSurfaceSelection.removingTransport(from: positioned.source) {
                let law = try original.originalCoordinateLaw(maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
                guard case .physicalRadians(let gain) = law else { throw invalid("Physical surface transport has a canonical-label angular descriptor.") }
                let expected = try IndependentShapeAngularSurfaceSelection.physical(local: intrinsic, gain: gain,
                    tolerance: tolerance, usage: &budget)
                try GeometryStructuralComparisonWork.charge(surface: expected) { try budget.work($0) }
                guard expected == positioned.source else { throw invalid("Original physical surface transport disagrees with its actual angular descriptor.") }
                return
            }
            if case .procedural(.originalImage(let chart)) = surface,
               case .procedural(.originalAffineWord(let positioned)) = chart.source {
                let local = try IndependentShapeOriginalSurfacePrimitive.read(positioned.source)
                let gain = try original.originalParameterGain(maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
                guard !chart.swapAxes, try chart.uParameterGain.isEquivalent(to: gain, usage: &budget) else {
                    throw invalid("Original positioned surface longitude conflicts with its descriptor.")
                }
                switch local {
                case .sphere, .torus:
                    guard try chart.vParameterGain.isEquivalent(to: gain, usage: &budget) else {
                        throw invalid("Original positioned surface latitude conflicts with its descriptor.")
                    }
                case .cylinder:
                    guard try chart.vParameterGain.isEquivalent(to: .binary(1), usage: &budget) else {
                        throw invalid("Original cylinder axial parameter is not its raw model coordinate.")
                    }
                case .plane: throw invalid("Original plane must retain its nonangular local chart.")
                }
                return
            }
            if case .procedural(.originalImage(let image)) = surface,
               case .analytic(let analytic) = image.source {
                switch analytic {
                case .plane: break
                case .cylinder, .cone, .sphere, .torus:
                    let gain = try original.originalParameterGain(maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
                    guard !image.swapAxes, try image.uParameterGain.isEquivalent(to: gain, usage: &budget) else {
                        throw invalid("Original surface angular descriptor disagrees with its retained longitude gain.")
                    }
                    if case .sphere = analytic {
                        guard try image.vParameterGain.isEquivalent(to: gain, usage: &budget) else {
                            throw invalid("Original sphere latitude descriptor disagrees with its retained gain.")
                        }
                    }
                    if case .torus = analytic {
                        guard try image.vParameterGain.isEquivalent(to: gain, usage: &budget) else {
                            throw invalid("Original torus meridian descriptor disagrees with its retained gain.")
                        }
                    }
                }
            }
        }
    }

    private func validatePosition(surface: Surface3D, association: IndependentShapePositionFrame,
        originalFrame: IndependentShapeFrame, frame: AffineTransform3D, tolerance: ModelingTolerance, budget: inout Budget) throws {
        var positioned = surface
        if case .procedural(.originalImage(let chart)) = positioned,
           case .procedural(.originalAffineWord) = chart.source {
            guard !chart.swapAxes, chart.uOffset == 0, chart.vOffset == 0,
                  chart.transform.basisX == .unitX, chart.transform.basisY == .unitY,
                  chart.transform.basisZ == .unitZ, chart.transform.translation == .zero else {
                throw invalid("Original positioned surface has a foreign outer chart transform.")
            }
            positioned = chart.source
        }
        if case .procedural(.originalAffineWord(let image)) = positioned, let original = originalFrame.originalIGES {
            guard association.parameterLengthUnit == nil else { throw invalid("IGES surface pose has no length parameter-unit override.") }
            var expected = try original.originalOperationWord(tolerance: tolerance,
                maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
            for adjustment in association.originalIGESAdjustments {
                expected = try adjustment.applying(to: expected, tolerance: tolerance,
                    maximumAlgebraicDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
            }
            guard try image.operationWord.isEquivalent(to: expected, tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget) else { throw invalid("Original IGES surface pose word is inconsistent.") }
            return
        }
        guard association.originalIGESAdjustments.isEmpty else { throw invalid("IGES surface pose adjustments require the original IGES matrix frame.") }
        if case .procedural(.originalAffineWord(let image)) = positioned {
            guard association.parameterLengthUnit == nil, let original = originalFrame.originalSTEPPlacement else {
                throw invalid("Original positioned surface has no retained frame source.")
            }
            let law = try original.originalNormalizedAffineSource(usage: &budget, maximumSourceDepth: budget.limits.maximumDepth, localCoordinatesInModelUnits: true)
            let expected = try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget)
            guard try image.operationWord.isEquivalent(to: expected, tolerance: tolerance,
                maximumDepth: budget.limits.maximumAlgebraicDepth, usage: &budget) else {
                throw invalid("Original surface word disagrees with its source frame.")
            }
            _ = try IndependentShapeOriginalSurfacePrimitive.read(image.source)
            return
        }
        try budget.work(64)
        guard association.parameterLengthUnit == nil,
              frame.basisY == frame.basisZ.cross(frame.basisX) else {
            throw invalid("Original surface position requires its defining right-handed coordinate frame.")
        }
        let origin = Point3D(x: frame.translation.x, y: frame.translation.y, z: frame.translation.z)
        if case .plane(let plane) = surface {
            guard plane.origin == origin, plane.normal == frame.basisZ, plane.uDirection == frame.basisX else {
                throw invalid("Original plane position association disagrees with its stored chart.")
            }
            return
        }
        guard case .procedural(.originalImage(let image)) = surface,
              case .analytic(let analytic) = image.source else {
            throw invalid("Original surface position needs its retained defining analytic image.")
        }
        let definingOrigin: Point3D, axis: Vector3D, station: Double
        switch analytic {
        case .cylinder(let point, let direction, _): definingOrigin = point; axis = direction; station = 0
        case .cone(let apex, let direction, let angle):
            definingOrigin = apex + direction * (image.vOffset * cos(angle)); axis = direction; station = 1
        case .sphere(let center, _): definingOrigin = center; axis = .unitZ; station = 0
        case .torus(let center, let direction, _, _): definingOrigin = center; axis = direction; station = 0
        case .plane: throw invalid("Original affine plane defining frame requires its own chart association.")
        }
        let derivatives = try image.source.differentialGeometry(u: 0, v: station, tolerance: tolerance)
        let reference = try derivatives.tangentU.cross(axis).normalized(tolerance: tolerance.distance)
        let actualOrigin = image.transform.applying(to: definingOrigin)
        let actualAxis = image.transform.applying(to: axis)
        let actualReference = image.transform.applying(to: reference)
        guard (actualOrigin - origin).length <= tolerance.distance,
              (actualAxis - frame.basisZ).length <= tolerance.angle,
              (actualReference - frame.basisX).length <= tolerance.angle else {
            throw invalid("Original analytic surface defining frame disagrees with its retained source position.")
        }
    }

    private func canonical(_ values: [IndependentShapeReference], budget: inout Budget) throws {
        var previous: IndependentShapeReference?
        for value in values {
            try budget.work(1)
            if let previous, !(previous < value) { throw invalid("Set references must be unique and canonically sorted.") }
            previous = value
        }
    }

    private func canonicalIDs<S: Sequence>(_ ids: S, budget: inout Budget) throws where S.Element: Comparable {
        var previous: S.Element?
        for id in ids {
            try budget.work(1)
            if let previous, !(previous < id) { throw invalid("Source owner IDs/members must be unique and canonically sorted.") }
            previous = id
        }
    }

    private func validatePlacement(_ f: AffineTransform3D, budget: inout Budget) throws {
        try budget.visitExactCell(depth: 0)
        let ax = try ExactRationalCoefficient.originalDouble(f.basisX.x, usage: &budget)
        let ay = try ExactRationalCoefficient.originalDouble(f.basisX.y, usage: &budget)
        let az = try ExactRationalCoefficient.originalDouble(f.basisX.z, usage: &budget)
        let bx = try ExactRationalCoefficient.originalDouble(f.basisY.x, usage: &budget)
        let by = try ExactRationalCoefficient.originalDouble(f.basisY.y, usage: &budget)
        let bz = try ExactRationalCoefficient.originalDouble(f.basisY.z, usage: &budget)
        let cx = try ExactRationalCoefficient.originalDouble(f.basisZ.x, usage: &budget)
        let cy = try ExactRationalCoefficient.originalDouble(f.basisZ.y, usage: &budget)
        let cz = try ExactRationalCoefficient.originalDouble(f.basisZ.z, usage: &budget)
        let yz = try by.multiplied(by: cz, usage: &budget).subtracting(bz.multiplied(by: cy, usage: &budget), usage: &budget)
        let xz = try bx.multiplied(by: cz, usage: &budget).subtracting(bz.multiplied(by: cx, usage: &budget), usage: &budget)
        let xy = try bx.multiplied(by: cy, usage: &budget).subtracting(by.multiplied(by: cx, usage: &budget), usage: &budget)
        let determinant = try ax.multiplied(by: yz, usage: &budget)
            .subtracting(ay.multiplied(by: xz, usage: &budget), usage: &budget)
            .adding(az.multiplied(by: xy, usage: &budget), usage: &budget)
        guard !determinant.isZero else { throw invalid("Original affine placement is exactly singular.") }
    }

    private func validateOriginalPlacement(_ source: OriginalSTEPPlacementSource?, derived: AffineTransform3D,
        tolerance: ModelingTolerance, elements: inout [PortableIdentity128: (kind: String, value: OriginalSTEPPlacementElement)],
        budget: inout Budget) throws {
        guard let source else { return }
        func retain(_ value: OriginalSTEPPlacementElement?, kind: String,
                    elements: inout [PortableIdentity128: (kind: String, value: OriginalSTEPPlacementElement)],
                    budget: inout Budget) throws {
            guard let value else { return }
            try budget.records(1); try budget.text(value.name)
            if let previous = elements[value.id] {
                guard previous.kind == kind, previous.value == value else {
                    throw invalid("Shared original STEP placement element has conflicting source values.")
                }
            } else { elements[value.id] = (kind, value) }
        }
        switch source {
        case .axis2(let value):
            try retain(value.location, kind: "point", elements: &elements, budget: &budget)
            try retain(value.axis, kind: "direction", elements: &elements, budget: &budget)
            try retain(value.referenceDirection, kind: "direction", elements: &elements, budget: &budget)
        case .cartesian(let value):
            try retain(value.location, kind: "point", elements: &elements, budget: &budget)
            try retain(value.axis1, kind: "direction", elements: &elements, budget: &budget)
            try retain(value.axis2, kind: "direction", elements: &elements, budget: &budget)
            try retain(value.axis3, kind: "direction", elements: &elements, budget: &budget)
        }
        try budget.records(source.adjustments.count)
        let candidate = try source.derivedAffineTransform(tolerance: tolerance, maximumDepth: budget.limits.maximumAlgebraicDepth, maximumSourceDepth: budget.limits.maximumDepth, usage: &budget)
        guard candidate == derived else { throw invalid("Derived placement differs from its original STEP source law.") }
    }

    private func invalid(_ detail: String) -> IndependentShapeSourceError { .invalidSource(detail) }
    private func missing(_ detail: String) -> IndependentShapeSourceError { .missingReference(detail) }

    private struct LengthRegistry {
        var units: [PortableIdentity128: OriginalSTEPLengthSource] = [:]
        var dimensions: [PortableIdentity128: [String]] = [:]
        var measures: [PortableIdentity128: OriginalSTEPLengthConversion] = [:]
        mutating func validate(_ original: OriginalSTEPLengthSource?, budget: inout Budget) throws {
            guard var source = original else { return }
            _ = try source.exactGain(maximumDepth: budget.limits.maximumDepth, usage: &budget)
            var depth = 0
            var active = Set<PortableIdentity128>()
            while true {
                try budget.records(1); try budget.work(1)
                guard depth <= budget.limits.maximumDepth, active.insert(source.id).inserted else {
                    throw IndependentShapeSourceError.invalidSource("Original length source depth or identity cycle.")
                }
                if let previous = units[source.id] {
                    let same: Bool
                    switch (previous.law, source.law) {
                    case (.metre(let a), .metre(let b)): same = a == b
                    case (.conversion(let a), .conversion(let b)):
                        try budget.work(a.name.utf8.count + b.name.utf8.count + a.factorLiteral.utf8.count + b.factorLiteral.utf8.count)
                        same = a.name.utf8.elementsEqual(b.name.utf8) && a.dimensionsID == b.dimensionsID
                            && a.dimensions == b.dimensions && a.measureID == b.measureID && a.measureKind == b.measureKind
                            && a.factorLiteral.utf8.elementsEqual(b.factorLiteral.utf8) && a.base.id == b.base.id
                    default: same = false
                    }
                    guard same else { throw IndependentShapeSourceError.invalidSource("Original length unit identity has conflicting records.") }
                } else { units[source.id] = source }
                switch source.law {
                case .metre: return
                case .conversion(let conversion):
                    try budget.records(2 + conversion.dimensions.count)
                    try budget.text(conversion.name); try budget.text(conversion.factorLiteral)
                    for literal in conversion.dimensions { try budget.text(literal) }
                    if let previous = dimensions[conversion.dimensionsID], previous != conversion.dimensions {
                        throw IndependentShapeSourceError.invalidSource("Original length dimensions identity has conflicting literals.")
                    }
                    dimensions[conversion.dimensionsID] = conversion.dimensions
                    if let previous = measures[conversion.measureID] {
                        guard previous.measureKind == conversion.measureKind,
                            previous.factorLiteral.utf8.elementsEqual(conversion.factorLiteral.utf8), previous.base.id == conversion.base.id else {
                            throw IndependentShapeSourceError.invalidSource("Original length measure identity has conflicting source values.")
                        }
                    } else { measures[conversion.measureID] = conversion }
                    source = conversion.base; depth += 1
                }
            }
        }
    }
    private struct Budget: RationalAlgebraAdmitting {
        let limits: IndependentShapeSourceLimits
        let check: () throws -> Void
        var recordCount = 0, textCount = 0, workCount = 0
        mutating func records(_ count: Int) throws {
            try checkpoint()
            let total = try sum(recordCount, count)
            guard total <= limits.maximumRecords else { throw IndependentShapeSourceError.resourceLimitExceeded("Independent source record ceiling.") }
            try work(count); recordCount = total
        }
        mutating func text(_ value: String) throws {
            try checkpoint()
            let count = value.utf8.count
            let total = try sum(textCount, count)
            guard total <= limits.maximumTextBytes else { throw IndependentShapeSourceError.resourceLimitExceeded("Independent source UTF8 ceiling.") }
            try work(count); textCount = total
        }
        mutating func work(_ count: Int) throws {
            try checkpoint()
            let total = try sum(workCount, count)
            guard total <= limits.maximumWork else { throw IndependentShapeSourceError.resourceLimitExceeded("Independent source cumulative work ceiling.") }
            workCount = total
        }
        mutating func visitSourceCell(depth: Int) throws {
            guard depth >= 0, depth <= limits.maximumDepth else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Original source nesting ceiling.")
            }
            try records(1)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= limits.maximumAlgebraicDepth else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Original source exact depth ceiling.")
            }
            try records(1)
        }
        mutating func consumeExactWork(_ count: Int) throws { try work(count) }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow, bytes.partialValue <= limits.maximumTextBytes - textCount else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Original exact source storage exceeds the caller byte ceiling.")
            }
            try records(count)
            textCount += bytes.partialValue
        }
        mutating func geometryStorage(_ bytes: Int) throws {
            guard bytes >= 0, bytes <= limits.maximumTextBytes - textCount else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Original geometry source storage exceeds the caller byte ceiling.")
            }
            let stride = MemoryLayout<UInt32>.stride
            try records(bytes / stride + (bytes % stride == 0 ? 0 : 1))
            textCount += bytes
        }
        func checkpoint() throws { try CurrentTaskCancellationChecker().checkCancellation(); try check() }
        func sum(_ a: Int, _ b: Int) throws -> Int {
            let result = a.addingReportingOverflow(b)
            guard a >= 0, b >= 0, !result.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Independent source count overflow.") }
            return result.partialValue
        }
    }
}
