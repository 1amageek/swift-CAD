import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation

struct ExactSTEPWriter: Sendable {
  let resourceLimits: ExchangeResourceLimits
  let tolerance: ModelingTolerance
  let allowsGroupSemanticLoss: Bool
  let surfaceOverrides: [Surface3D: BSplineSurface3D]
  let curveConversions: ExchangeCurveConversionPlan
  let processingBudget: ExchangeProcessingBudget
  init(resourceLimits: ExchangeResourceLimits, tolerance: ModelingTolerance, surfaceOverrides: [Surface3D: BSplineSurface3D] = [:], curveConversions: ExchangeCurveConversionPlan = .init(), processingBudget: ExchangeProcessingBudget? = nil, allowsGroupSemanticLoss: Bool = false) {
    self.allowsGroupSemanticLoss = allowsGroupSemanticLoss
    self.resourceLimits = resourceLimits; self.tolerance = tolerance; self.surfaceOverrides = surfaceOverrides; self.curveConversions = curveConversions
    self.processingBudget = processingBudget ?? ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
  }

  private func requireCertifiedBodySurfaceIncidence(_ brep: BRepModel) throws {
    guard !curveConversions.edges.isEmpty || !surfaceOverrides.isEmpty else { return }
    for (faceID, face) in brep.faces {
      try processingBudget.check(format: .step)
      guard let original = brep.geometry.surfaces[face.surfaceID] else {
        throw IndependentShapeExchangeError.invalidAssociation("Body face surface is absent.")
      }
      let convertedSurface = surfaceOverrides[original]
      let hostedSurface = convertedSurface.map(Surface3D.bSpline) ?? original
      for loopID in face.loops {
        guard let loop = brep.loops[loopID] else { throw IndependentShapeExchangeError.invalidAssociation("Converted Body loop is absent.") }
        for (ordinal, coedge) in loop.coedges.enumerated() {
          let convertedEdge = curveConversions.edges[coedge.edgeID]
          guard convertedSurface != nil || convertedEdge != nil else { continue }
          guard convertedEdge != nil, let pcurve = coedge.surfaceParameterCurve,
            let receipts = curveConversions.hostedBoundaries[coedge.edgeID],
            receipts.contains(where: {
              $0.faceID == faceID && $0.loopID == loopID && $0.coedgeOrdinal == ordinal
                && $0.hostedSurface == hostedSurface && $0.parameterCurve == pcurve
            }) else {
            throw IndependentShapeExchangeError.invalidAssociation("Converted Body boundary lacks its final emitted face/curve joint certificate.")
          }
        }
      }
    }
  }

  func writeIndependent(_ source: IndependentShapeSource, units: UnitSystem, to sink: any ByteSink) throws {
    var usage = try IndependentShapeExchangeUsage(limits:resourceLimits,format:.step,processing:processingBudget,consumedEntities:0,consumedWork:0,consumedBytes:0)
    try writeIndependent(source,units:units,to:sink,usage:&usage)
  }

  func writeIndependent(_ source:IndependentShapeSource,units:UnitSystem,to sink:any ByteSink,
                        usage:inout IndependentShapeExchangeUsage) throws {
    var producer: any IndependentSTEPGeometryWriting = IndependentProducer(writer:self)
    let data = try DefaultIndependentSTEPGraphWriter(allowingGroupSemanticLoss: allowsGroupSemanticLoss).write(source,standaloneUnits:units,tolerance:tolerance,producer:&producer,usage:&usage)
    try usage.check()
    try data.withUnsafeBytes { try sink.write($0) }
  }

  /// Appends the real independent graph to this invocation's existing bounded table.
  func appendIndependent(_ source: IndependentShapeSource, units: UnitSystem,
      table: inout EntityTable, productDefinitions: [AssemblyDefinitionID: Int] = [:],
      bodyBindings: [SubshapeID: IndependentSTEPBodyBinding] = [:], bodySourceGraph: DesignGraph? = nil, usage: inout IndependentShapeExchangeUsage) throws {
    var producer = IndependentProducer(writer: self, table: table)
    try DefaultIndependentSTEPGraphWriter(allowingGroupSemanticLoss: allowsGroupSemanticLoss).append(source, standaloneUnits: units,
      tolerance: tolerance, productDefinitions: productDefinitions, bodyBindings: bodyBindings, bodySourceGraph: bodySourceGraph, producer: &producer, usage: &usage)
    table = producer.table
    table.independentUsage = usage
  }

  private struct IndependentProducer: IndependentSTEPGeometryWriting {
    let writer: ExactSTEPWriter
    var table: EntityTable
    var curves: [CurveID:(entity:Int,unit:UnitSystem,gain:OriginalParameterGain?)] = [:]
    var surfaces: [SurfaceID:(entity:Int,unit:UnitSystem,law:IndependentShapeAngularSource.CoordinateLaw?)] = [:]
    var lengthUnits: [PortableIdentity128: Int] = [:]
    var lengthDimensions: [PortableIdentity128: Int] = [:]
    var lengthMeasures: [PortableIdentity128: Int] = [:]
    var angularUnits: [IndependentShapeAngularUnitID: Int] = [:]
    var angularDimensions: [IndependentShapeAngularDimensionsID: Int] = [:]
    var angularMeasures: [IndependentShapeAngularMeasureID: Int] = [:]
    init(writer:ExactSTEPWriter) {
      self.writer = writer
      table = EntityTable(maximumEntities:writer.resourceLimits.maximumEntities,tolerance:writer.tolerance,
          maximumBytes:writer.resourceLimits.maximumBytes,maximumStringWork:writer.resourceLimits.maximumIterations,maximumSourceDepth:writer.resourceLimits.maximumNesting,maximumAlgebraicDepth:writer.resourceLimits.maximumAlgebraicDepth,processingBudget:writer.processingBudget)
    }
    init(writer: ExactSTEPWriter, table: EntityTable) {
      self.writer = writer
      self.table = table
    }
    mutating func context(_ context:IndependentShapeContext,usage:inout IndependentShapeExchangeUsage) throws -> Int {
      try unitContext(identifier:context.identifier,type:context.type,units:context.units,originalAngularSource:context.originalAngularSource,originalLengthSource:context.originalLengthSource,usage:&usage)
    }
    mutating func standaloneUnits(_ units:UnitSystem,originalAngularSource:IndependentShapeAngularSource?,originalLengthSource:OriginalSTEPLengthSource?,usage:inout IndependentShapeExchangeUsage) throws -> Int {
      try unitContext(identifier:"",type:"",units:units,originalAngularSource:originalAngularSource,originalLengthSource:originalLengthSource,usage:&usage)
    }
    private mutating func unitContext(identifier:String,type:String,units:UnitSystem,originalAngularSource:IndependentShapeAngularSource?,originalLengthSource:OriginalSTEPLengthSource?,usage:inout IndependentShapeExchangeUsage) throws -> Int {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      let length: Int
      if let originalLengthSource { length = try originalLengthUnitEntity(originalLengthSource, depth: 0) }
      else { length = try writer.lengthUnitEntity(units.length,table:&table) }
      let angle: Int
      if let originalAngularSource {
        angle = try originalAngularUnitEntity(originalAngularSource, depth: 1)
      } else if units.angle == .degree {
        let radian = try table.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
        let dimensions = try table.add("DIMENSIONAL_EXPONENTS(0.,0.,0.,0.,0.,0.,0.)")
        let conversion = try table.add("PLANE_ANGLE_MEASURE_WITH_UNIT(PLANE_ANGLE_MEASURE(\(writer.number(AngleUnit.degree.toInternal(1)))),#\(radian))")
        angle = try table.add("(CONVERSION_BASED_UNIT('degree',#\(conversion)) NAMED_UNIT(#\(dimensions)) PLANE_ANGLE_UNIT())")
      } else { angle = try table.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))") }
      return try table.add("(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(length),#\(angle))) REPRESENTATION_CONTEXT(\(try table.quotedString(identifier)),\(try table.quotedString(type))))")
    }
    private mutating func originalLengthUnitEntity(_ source: OriginalSTEPLengthSource, depth: Int) throws -> Int {
      guard depth <= table.maximumSourceDepth else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original length unit output depth.") }
      try table.consumeExactWork(1)
      if let existing = lengthUnits[source.id] { return existing }
      let entity: Int
      switch source.law {
      case .metre(let prefix):
        let token = prefix.map { "." + $0.rawValue + "." } ?? "$"
        entity = try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(\(token),.METRE.))")
      case .conversion(let conversion):
        let base = try originalLengthUnitEntity(conversion.base, depth: depth + 1)
        let dimensions: Int
        if let existing = lengthDimensions[conversion.dimensionsID] { dimensions = existing }
        else {
          try table.consumeExactWork(conversion.dimensions.count)
          dimensions = try table.add("DIMENSIONAL_EXPONENTS(" + conversion.dimensions.joined(separator: ",") + ")")
          try table.visitSourceCell(depth: depth); lengthDimensions[conversion.dimensionsID] = dimensions
        }
        let measure: Int
        if let existing = lengthMeasures[conversion.measureID] { measure = existing }
        else {
          let value = "LENGTH_MEASURE(\(conversion.factorLiteral)),#\(base)"
          switch conversion.measureKind {
          case .measureWithUnit: measure = try table.add("MEASURE_WITH_UNIT(\(value))")
          case .lengthMeasureWithUnit: measure = try table.add("LENGTH_MEASURE_WITH_UNIT(\(value))")
          case .complexLengthMeasureWithUnit: measure = try table.add("(LENGTH_MEASURE_WITH_UNIT() MEASURE_WITH_UNIT(\(value)))")
          }
          try table.visitSourceCell(depth: depth); lengthMeasures[conversion.measureID] = measure
        }
        entity = try table.add("(CONVERSION_BASED_UNIT(\(try table.quotedString(conversion.name)),#\(measure)) LENGTH_UNIT() NAMED_UNIT(#\(dimensions)))")
      }
      try table.visitSourceCell(depth: depth); lengthUnits[source.id] = entity
      return entity
    }
    private mutating func originalAngularUnitEntity(_ source: IndependentShapeAngularSource, depth: Int) throws -> Int {
      try table.independentUsage!.charge(work: 1)
      guard depth <= table.independentUsage!.limits.maximumNesting else {
        throw IndependentShapeExchangeError.resourceLimitExceeded("Original angular unit chain exceeds the output depth allowance.")
      }
      if let entity = angularUnits[source.id] { return entity }
      let entity: Int
      switch source.law {
      case .radian(let prefix):
        let value = prefix.map { "." + $0.rawValue + "." } ?? "$"
        entity = try table.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT(\(value),.RADIAN.))")
      case .conversion(let conversion):
        let base = try originalAngularUnitEntity(conversion.base, depth: depth + 1)
        let dimensions: Int
        if let existing = angularDimensions[conversion.dimensionsID] { dimensions = existing }
        else {
          try table.independentUsage!.charge(work: conversion.dimensions.count)
          dimensions = try table.add("DIMENSIONAL_EXPONENTS(" + conversion.dimensions.map { writer.number($0) }.joined(separator: ",") + ")")
          try table.independentUsage!.charge(entities: 1); angularDimensions[conversion.dimensionsID] = dimensions
        }
        let measure: Int
        if let existing = angularMeasures[conversion.measureID] { measure = existing }
        else {
          let value = "PLANE_ANGLE_MEASURE(\(writer.number(conversion.factor))),#\(base)"
          switch conversion.measureKind {
          case .measureWithUnit: measure = try table.add("MEASURE_WITH_UNIT(\(value))")
          case .planeAngleMeasureWithUnit: measure = try table.add("PLANE_ANGLE_MEASURE_WITH_UNIT(\(value))")
          case .complexPlaneAngleMeasureWithUnit:
            measure = try table.add("(MEASURE_WITH_UNIT(\(value)) PLANE_ANGLE_MEASURE_WITH_UNIT())")
          }
          try table.independentUsage!.charge(entities: 1); angularMeasures[conversion.measureID] = measure
        }
        entity = try table.add("(CONVERSION_BASED_UNIT(\(try table.quotedString(conversion.name)),#\(measure)) NAMED_UNIT(#\(dimensions)) PLANE_ANGLE_UNIT())")
      }
      try table.independentUsage!.charge(entities: 1); angularUnits[source.id] = entity
      return entity
    }
    mutating func curve(_ item:IndependentShapeItem,source:IndependentShapeSource,units:UnitSystem,originalAngularSource:IndependentShapeAngularSource?,originalLengthSource:OriginalSTEPLengthSource?,positionEntityID:Int?,
                        usage:inout IndependentShapeExchangeUsage) throws -> Int {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      guard case .curve(let id,let trim) = item.geometry, let curve = source.geometry.curves[id], let name = source.curveNames[id] else {
        throw IndependentShapeExchangeError.invalidAssociation("Missing original STEP curve or label.")
      }
      if let converted = writer.curveConversions.items[item.id] {
        let selected = try item.resolvedCurve(in: source.geometry)
        let lower: Double, upper: Double
        if let trim = selected.trim { lower = trim.startParameter; upper = trim.endParameter }
        else if case .closed(let a, let b) = selected.curve.domain { lower = a; upper = b }
        else { throw IndependentShapeExchangeError.invalidAssociation("Converted independent selection lost its finite original domain.") }
        let basis = try writer.bSplineCurveEntity(converted, name: name, units: units.length, table: &table)
        let label = try table.quotedString(item.name)
        return try table.add("TRIMMED_CURVE(\(label),#\(basis),(PARAMETER_VALUE(\(writer.number(lower)))),(PARAMETER_VALUE(\(writer.number(upper)))),\(upper > lower ? ".T." : ".F."),.PARAMETER.)")
      }
      let angularGain: OriginalParameterGain?
      if case .parameterImage = curve {
        angularGain = try IndependentSTEPAngularLaw.gain(source: originalAngularSource, units: units, usage: &table.independentUsage!)
      } else { angularGain = nil }
      let requiresPosition:Bool
      var positionedCurve = curve
      var positionDepth = 0
      while case .parameterImage(let image) = positionedCurve {
        positionDepth += 1; try table.independentUsage!.visitSourceCell(depth: positionDepth)
        positionedCurve = image.source
      }
      switch positionedCurve {
      case .circle: requiresPosition = true
      case .analytic(let analytic):
        switch analytic { case .circle, .ellipse, .hyperbola, .parabola: requiresPosition = true; default: requiresPosition = false }
      case .originalAffineWord(let image):
        switch image.source { case .circle, .analytic(.ellipse), .analytic(.hyperbola), .analytic(.parabola): requiresPosition = true; default: requiresPosition = false }
      case .affineImage(let image):
        switch image.source { case .circle, .analytic(.parabola): requiresPosition = true; default: requiresPosition = false }
      default: requiresPosition = false
      }
      let originalSpline: BSplineCurve3D?
      if case .originalAffineWord(let image) = positionedCurve, case .bSpline(let spline) = image.source {
        let expected = try IndependentSTEPLengthLaw.coordinateWord(source: originalLengthSource, units: units,
          tolerance: writer.tolerance, usage: &table.independentUsage!)
        guard image.operationWord.factors == expected.factors,
          try image.operationWord.isEquivalent(to: expected, tolerance: writer.tolerance,
          maximumDepth: table.independentUsage!.limits.maximumAlgebraicDepth, usage: &table.independentUsage!) else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): A general spline spatial word needs legal original operation transport or certified materialization.
          // The unit-only raw-control producer must not publish translated/general source under an unrelated output context.
          throw IndependentShapeExchangeError.metadataLoss("Original spline word is not the emitted context's coordinate law.")
        }
        originalSpline = spline
      } else { originalSpline = nil }
      if requiresPosition, source.curveLinearSources[id] == nil, case .originalAffineWord(let image) = positionedCurve {
        try table.independentUsage!.charge(work: source.frames.count)
        guard let association = source.curvePositionFrames[id],
              let frame = source.frames.first(where: { $0.id == association.frameID }),
              let original = frame.originalSTEPPlacement else {
          throw IndependentShapeExchangeError.invalidAssociation("Original normalized conic has no retained position source.")
        }
        let gain = try originalLengthSource?.exactGain(maximumDepth: table.independentUsage!.limits.maximumNesting, usage: &table.independentUsage!)
          ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &table.independentUsage!)
        let frameGain = try original.originalLengthSource?.exactGain(maximumDepth: table.independentUsage!.limits.maximumNesting, usage: &table.independentUsage!)
          ?? ExactRationalCoefficient.originalDouble(original.lengthUnit.toInternal(1), usage: &table.independentUsage!)
        guard try gain.subtracting(frameGain, usage: &table.independentUsage!).canonicalSign == 0 else {
          throw IndependentShapeExchangeError.invalidAssociation("Original conic position and context length laws disagree.")
        }
        let law = try original.originalNormalizedAffineSource(usage: &table.independentUsage!, maximumSourceDepth: table.independentUsage!.limits.maximumNesting, localCoordinatesInModelUnits: true)
        let expected = try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: writer.tolerance,
          maximumDepth: table.independentUsage!.limits.maximumAlgebraicDepth, usage: &table.independentUsage!)
        guard try image.operationWord.isEquivalent(to: expected, tolerance: writer.tolerance,
          maximumDepth: table.independentUsage!.limits.maximumAlgebraicDepth, usage: &table.independentUsage!) else {
          throw IndependentShapeExchangeError.invalidAssociation("Original conic word is not bound to its emitted position.")
        }
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP export cannot encode absence of an original position-entity association for a mandatory positioned primitive.
      // Prove an explicit loss policy or equivalent standard absence carrier before Native-only conics without that source identity can succeed.
      guard !requiresPosition || positionEntityID != nil else {
        throw IndependentShapeExchangeError.metadataLoss("Original primitive position association is absent.")
      }
      let basis:Int
      if let value = curves[id] {
        guard value.unit.length == units.length else { throw IndependentShapeExchangeError.unsupportedSemantics("Shared STEP basis has conflicting owned length units.") }
        if let angularGain, let previous = value.gain {
          guard try angularGain.isEquivalent(to: previous, usage: &table.independentUsage!) else {
            throw IndependentShapeExchangeError.unsupportedSemantics("Shared STEP basis has conflicting original angular coordinate laws.")
          }
        }
        basis = value.entity
      }
      else {
        try GeometryStructuralComparisonWork.charge(curve:curve) { try table.independentUsage!.charge(work:$0) }
        if let association = source.curvePositionFrames[id], let parameterUnit = association.parameterLengthUnit,
           parameterUnit != units.length {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP export retains the original length-parameter parabola chart only in its declared unit context.
          // Prove the original parameter and trim remapping before changing that context; do not reinterpret source parameter numbers.
          throw IndependentShapeExchangeError.metadataLoss("Original parabola parameter unit differs from the output context.")
        }
        if let originalSpline {
          guard let metadata = source.curveSplineSources[id] else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Native absence of original spline attributes needs a legal source absence carrier.
            // Original raw-control publication must retain that distinction before inventing mandatory standard assertions.
            throw IndependentShapeExchangeError.metadataLoss("Original spline descriptive source is absent.")
          }
          basis = try writer.bSplineCurveEntity(originalSpline, name: name, units: .meter, originalSource: metadata, table: &table)
        } else if let linear = source.curveLinearSources[id] {
          let outputGain = try originalLengthSource?.exactGain(maximumDepth: table.independentUsage!.limits.maximumNesting, usage: &table.independentUsage!)
            ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &table.independentUsage!)
          let sourceGain = try linear.originalLengthSource?.exactGain(maximumDepth: table.independentUsage!.limits.maximumNesting, usage: &table.independentUsage!)
            ?? ExactRationalCoefficient.originalDouble(linear.lengthUnit.toInternal(1), usage: &table.independentUsage!)
          guard try outputGain.subtracting(sourceGain, usage: &table.independentUsage!).isZero else {
            throw IndependentShapeExchangeError.invalidAssociation("Original LINE and its emitted context gains conflict.")
          }
          basis = try writer.originalSTEPLineEntity(linear, curve: curve, name: name, table: &table)
        } else {
          basis = try writer.independentCurveEntity(curve,name:name,units:units.length,angleUnit:units.angle,originalAngularGain:angularGain,positionEntityID:positionEntityID,table:&table)
        }
        try table.independentUsage!.charge(entities:1,work:1); curves[id] = (basis,units,angularGain)
      }
      if let trim {
        let first: String, second: String, agrees: Bool, preference: String
        if let original = item.trimmingSource {
          first = try trimmingSelectors(original.first, units: units.length)
          second = try trimmingSelectors(original.second, units: units.length)
          agrees = original.agreesWithBasis; preference = original.preference.rawValue.uppercased()
        } else {
          first = "(PARAMETER_VALUE(\(writer.number(trim.startParameter))))"
          second = "(PARAMETER_VALUE(\(writer.number(trim.endParameter))))"
          agrees = trim.endParameter > trim.startParameter; preference = "PARAMETER"
        }
        return try table.add("TRIMMED_CURVE(\(try table.quotedString(item.name)),#\(basis),\(first),\(second),\(agrees ? ".T." : ".F."),.\(preference).)")
      }
      guard item.name.utf8.elementsEqual(name.utf8) else { throw IndependentShapeExchangeError.metadataLoss("Unwrapped STEP curve cannot retain distinct selection and basis labels.") }
      return basis
    }
    private mutating func trimmingSelectors(_ selectors: [IndependentShapeTrimmingSource.Selector], units: LengthUnit) throws -> String {
      var tokens: [String] = []
      for selector in selectors {
        try table.independentUsage!.charge(work: 1)
        switch selector {
        case .parameter(let parameter): tokens.append("PARAMETER_VALUE(\(writer.number(parameter)))")
        case .point(let point): tokens.append("#\(try writer.cartesianPoint(point, units: units, table: &table))")
        }
      }
      return "(" + tokens.joined(separator: ",") + ")"
    }
    mutating func surface(_ item:IndependentShapeItem,source:IndependentShapeSource,units:UnitSystem,originalAngularSource:IndependentShapeAngularSource?,originalLengthSource:OriginalSTEPLengthSource?,positionEntityID:Int?,
                          usage:inout IndependentShapeExchangeUsage) throws -> Int {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      guard case .surface(let id) = item.geometry, let surface = source.geometry.surfaces[id], let name = source.surfaceNames[id] else {
        throw IndependentShapeExchangeError.invalidAssociation("Missing original STEP surface or label.")
      }
      guard item.name.utf8.elementsEqual(name.utf8) else { throw IndependentShapeExchangeError.metadataLoss("STEP surface cannot retain distinct selection and basis labels.") }
      let angularLaw: IndependentShapeAngularSource.CoordinateLaw?
      if try IndependentSTEPAngularLaw.usesAngularCoordinates(surface: surface, usage: &table.independentUsage!) {
        angularLaw = try IndependentSTEPAngularLaw.coordinateLaw(source: originalAngularSource, units: units, usage: &table.independentUsage!)
      } else { angularLaw = nil }
      let angularGain: OriginalParameterGain?
      if case .some(.canonicalGain(let gain)) = angularLaw { angularGain = gain } else { angularGain = nil }
      if let value = surfaces[id] {
        guard value.unit.length == units.length else { throw IndependentShapeExchangeError.unsupportedSemantics("Shared STEP surface has conflicting owned length units.") }
        if let angularLaw, let previous = value.law {
          guard try IndependentSTEPAngularLaw.equivalent(angularLaw, previous, usage: &table.independentUsage!) else {
            throw IndependentShapeExchangeError.unsupportedSemantics("Shared STEP surface has conflicting original angular coordinate laws.")
          }
        }
        return value.entity
      }
      try GeometryStructuralComparisonWork.charge(surface:surface) { try table.independentUsage!.charge(work:$0) }
      var positionedSurface = surface
      var originalChart: OriginalImageSurface3D?
      if case .procedural(.originalImage(let chart)) = surface,
         case .procedural(.originalAffineWord) = chart.source {
        originalChart = chart; positionedSurface = chart.source
      }
      let originalEntity: Int?
      if case .procedural(.originalAffineWord(let image)) = positionedSurface, case .bSpline(let spline) = image.source {
        guard originalChart == nil else { throw IndependentShapeExchangeError.metadataLoss("Spline has an additional foreign UV chart.") }
        let expected = try IndependentSTEPLengthLaw.coordinateWord(source: originalLengthSource, units: units,
          tolerance: writer.tolerance, usage: &table.independentUsage!)
        guard image.operationWord.factors == expected.factors,
          try image.operationWord.isEquivalent(to: expected, tolerance: writer.tolerance,
          maximumDepth: table.independentUsage!.limits.maximumAlgebraicDepth, usage: &table.independentUsage!) else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): General original spline support words need legal operation transport or certified materialization.
          // A raw-control surface writer may succeed only after exact emitted-context binding is proved.
          throw IndependentShapeExchangeError.metadataLoss("Original spline support word differs from the emitted coordinate law.")
        }
        guard let metadata = source.surfaceSplineSources[id] else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Native absence of original spline support assertions needs legal source absence transport.
          // This raw-control publication path must preserve the source distinction before emitting authored standard attributes.
          throw IndependentShapeExchangeError.metadataLoss("Original spline support descriptive source is absent.")
        }
        originalEntity = try writer.bSplineSurfaceEntity(spline, name: name, units: .meter, originalSource: metadata, table: &table)
      } else if case .procedural(.originalAffineWord(let image)) = positionedSurface {
        try table.independentUsage!.charge(work: source.frames.count)
        guard let association = source.surfacePositionFrames[id],
              let frame = source.frames.first(where: { $0.id == association.frameID }),
              let original = frame.originalSTEPPlacement, let placement = positionEntityID else {
          throw IndependentShapeExchangeError.invalidAssociation("Original surface has no retained emitted position source.")
        }
        let gain = try originalLengthSource?.exactGain(maximumDepth: table.independentUsage!.limits.maximumNesting, usage: &table.independentUsage!)
          ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &table.independentUsage!)
        let frameGain = try original.originalLengthSource?.exactGain(maximumDepth: table.independentUsage!.limits.maximumNesting, usage: &table.independentUsage!)
          ?? ExactRationalCoefficient.originalDouble(original.lengthUnit.toInternal(1), usage: &table.independentUsage!)
        guard try gain.subtracting(frameGain, usage: &table.independentUsage!).canonicalSign == 0 else {
          throw IndependentShapeExchangeError.invalidAssociation("Original surface context and position length laws disagree.")
        }
        let law = try original.originalNormalizedAffineSource(usage: &table.independentUsage!, maximumSourceDepth: table.independentUsage!.limits.maximumNesting, localCoordinatesInModelUnits: true)
        let expected = try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: writer.tolerance,
          maximumDepth: table.independentUsage!.limits.maximumAlgebraicDepth, usage: &table.independentUsage!)
        guard try image.operationWord.isEquivalent(to: expected, tolerance: writer.tolerance,
          maximumDepth: table.independentUsage!.limits.maximumAlgebraicDepth, usage: &table.independentUsage!) else {
          throw IndependentShapeExchangeError.invalidAssociation("Original surface word is not bound to its emitted position.")
        }
        let local = try IndependentShapeOriginalSurfacePrimitive.read(image.source)
        switch local {
        case .plane:
          guard originalChart == nil else { throw IndependentShapeExchangeError.invalidAssociation("Original plane has a foreign angular chart.") }
        default:
          if case .some(.physicalRadians(let gain)) = angularLaw {
            guard originalChart == nil,
                  let intrinsic = IndependentShapeAngularSurfaceSelection.removingTransport(from: image.source) else {
              throw IndependentShapeExchangeError.invalidAssociation("Original physical surface has no retained local angular transport.")
            }
            let expectedLocal = try IndependentShapeAngularSurfaceSelection.physical(local: intrinsic, gain: gain,
              tolerance: writer.tolerance, usage: &table.independentUsage!)
            try GeometryStructuralComparisonWork.charge(surface: expectedLocal) { try table.independentUsage!.charge(work: $0) }
            guard image.source == expectedLocal else {
              throw IndependentShapeExchangeError.invalidAssociation("Original physical surface angular transport conflicts with its emitted descriptor.")
            }
          } else {
          guard let chart = originalChart, let angularGain, !chart.swapAxes,
                chart.uOffset == 0, chart.vOffset == 0,
                chart.transform.basisX == .unitX, chart.transform.basisY == .unitY,
                chart.transform.basisZ == .unitZ, chart.transform.translation == .zero,
                try chart.uParameterGain.isEquivalent(to: angularGain, usage: &table.independentUsage!) else {
            throw IndependentShapeExchangeError.invalidAssociation("Original surface chart conflicts with its emitted angular law.")
          }
          let vertical: OriginalParameterGain
          switch local { case .cylinder: vertical = .binary(1); default: vertical = angularGain }
          guard try chart.vParameterGain.isEquivalent(to: vertical, usage: &table.independentUsage!) else {
            throw IndependentShapeExchangeError.invalidAssociation("Original surface vertical chart conflicts with its source primitive.")
          }
          }
        }
        let label = try table.quotedString(name)
        switch local {
        case .plane: originalEntity = try table.add("PLANE(\(label),#\(placement))")
        case .cylinder(let radius): originalEntity = try table.add("CYLINDRICAL_SURFACE(\(label),#\(placement),\(writer.number(radius)))")
        case .sphere(let radius): originalEntity = try table.add("SPHERICAL_SURFACE(\(label),#\(placement),\(writer.number(radius)))")
        case .torus(let major, let minor): originalEntity = try table.add("TOROIDAL_SURFACE(\(label),#\(placement),\(writer.number(major)),\(writer.number(minor)))")
        }
      } else { originalEntity = nil }
      let entity:Int
      if let originalEntity { entity = originalEntity }
      else if case .bSpline(let spline) = surface {
        entity = try writer.bSplineSurfaceEntity(spline,name:name,units:units.length,table:&table)
      } else if case .plane(let plane) = surface {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Independent public STEP plane export has no faithful carrier for absent original AXIS2 identity.
        // Preserve that source distinction or obtain an explicit loss policy before manufacturing a positioned source can succeed.
        guard positionEntityID != nil else { throw IndependentShapeExchangeError.metadataLoss("Original primitive position association is absent.") }
        let jet = try surface.differentialGeometry(u:0,v:0,tolerance:writer.tolerance)
        let placement = try positionEntityID ?? writer.axisPlacementEntity(origin:plane.origin,axis:plane.normal,reference:jet.tangentU,
            units:units.length,table:&table)
        entity = try table.add("PLANE(\(try table.quotedString(name)),#\(placement))")
      } else {
        entity = try writer.independentAnalyticSurfaceEntity(surface, name: name, units: units,
            positionEntityID: positionEntityID, originalAngularGain: angularGain,
            originalAngularMeasure: source.surfaceAngularMeasures[id], table: &table)
      }
      try table.independentUsage!.charge(entities:1,work:1); surfaces[id] = (entity,units,angularLaw)
      return entity
    }
    mutating func mappingOrigin(_ frame:AffineTransform3D,originalSource:OriginalSTEPPlacementSource?,name:String,units:UnitSystem,
                               usage:inout IndependentShapeExchangeUsage) throws -> Int {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      if let originalSource {
        return try writer.originalSTEPPlacementEntity(originalSource, derived: frame, name: name, units: units.length, table: &table)
      }
      try Self.orthogonal(frame,unitScale:true,table:&table)
      guard frame.basisZ.cross(frame.basisX).dot(frame.basisY) >= 1-writer.tolerance.angle else {
        throw IndependentShapeExchangeError.metadataLoss("STEP AXIS2 origin cannot retain a reflected original frame.")
      }
      let origin = Point3D(x:frame.translation.x,y:frame.translation.y,z:frame.translation.z)
      let p = try writer.cartesianPoint(origin,units:units.length,table:&table)
      let z = try writer.directionEntity(frame.basisZ,table:&table), x = try writer.directionEntity(frame.basisX,table:&table)
      return try table.add("AXIS2_PLACEMENT_3D(\(try table.quotedString(name)),#\(p),#\(z),#\(x))")
    }
    mutating func mappingTarget(_ frame:AffineTransform3D,originalSource:OriginalSTEPPlacementSource?,name:String,units:UnitSystem,
                               usage:inout IndependentShapeExchangeUsage) throws -> Int {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      if let originalSource {
        return try writer.originalSTEPPlacementEntity(originalSource, derived: frame, name: name, units: units.length, table: &table)
      }
      let scale = try Self.orthogonal(frame,unitScale:false,table:&table)
      let p = try writer.cartesianPoint(Point3D(x:frame.translation.x,y:frame.translation.y,z:frame.translation.z),units:units.length,table:&table)
      let x = try writer.directionEntity(frame.basisX,table:&table), y = try writer.directionEntity(frame.basisY,table:&table)
      let z = try writer.directionEntity(frame.basisZ,table:&table)
      return try table.add("CARTESIAN_TRANSFORMATION_OPERATOR_3D(\(try table.quotedString(name)),*,*,#\(x),#\(y),#\(p),\(writer.number(scale)),#\(z))")
    }
    static func orthogonal(_ frame: AffineTransform3D, unitScale: Bool,
                           table: inout EntityTable) throws -> Double {
      try OriginalOrthogonalAffineRepresentability.scale(of: frame, requiresUnitScale: unitScale, usage: &table)
    }
    mutating func quotedString(_ value:String,usage:inout IndependentShapeExchangeUsage) throws -> String {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      return try table.quotedString(value)
    }
    mutating func appendEntity(_ expression:String,usage:inout IndependentShapeExchangeUsage) throws -> Int {
      table.independentUsage = usage; defer { usage = table.independentUsage! }
      return try table.add(expression)
    }
    mutating func finish(usage:inout IndependentShapeExchangeUsage) throws -> Data {
      table.independentUsage = usage
      // Charge the actual shared envelope header and materialization before serialization.
      let header = ExactSTEPWriter.envelopePrefix.utf8.count + ExactSTEPWriter.envelopeSuffix.utf8.count
      try usage.charge(work:table.serializedByteCount+header,bytes:header)
      let sink = DataByteSink()
      try writer.publish(table:table,to:sink,framingIsPaid:true)
      try usage.check()
      return sink.bytes
    }
  }

  private func independentAnalyticSurfaceEntity(_ surface: Surface3D, name: String, units: UnitSystem,
      positionEntityID: Int?, originalAngularGain: OriginalParameterGain? = nil,
      originalAngularMeasure: IndependentShapeSurfaceAngularMeasure? = nil, table: inout EntityTable) throws -> Int {
    if !surfaceOverrides.isEmpty {
      try GeometryStructuralComparisonWork.charge(surface: surface) { try table.chargeGeometryWork($0) }
      if let converted = surfaceOverrides[surface] { return try bSplineSurfaceEntity(converted, name: name, units: units.length, table: &table) }
    }
    let quoted = try table.quotedString(name)
    func angle(_ value: Double, table: inout EntityTable) throws -> String {
      if let originalAngularGain {
        guard var ledger = table.independentUsage else { throw IndependentShapeExchangeError.invalidAssociation("Original angular scalar publication lacks its parent ledger.") }
        defer { table.independentUsage = ledger }
        if case .coneSemiAngle(let source) = originalAngularMeasure {
          guard try originalAngularGain.applied(to: source, usage: &ledger) == value else {
            throw IndependentShapeExchangeError.metadataLoss("Original cone angular measure disagrees with its native analytic law.")
          }
          return number(source)
        }
        return number(try originalAngularGain.inverseApplied(to: value, usage: &ledger))
      }
      return number(units.angle == .degree ? value * 180 / Double.pi : value)
    }
    let origin: Point3D, axis: Vector3D, reference: Vector3D, family: String, measures: String
    switch surface {
    case .procedural(.originalImage(let image)):
      let angular = originalAngularGain ?? (units.angle == .degree ? .ratio(numerator: Double.pi, denominator: 180) : .binary(1))
      let length = units.length.toInternal(1)
      guard !image.swapAxes, try gainsEquivalent(image.uParameterGain, angular, table: &table), image.uOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("Surface angular source chart conflicts with output units.") }
      _ = try IndependentProducer.orthogonal(image.transform, unitScale: true, table: &table)
      guard image.transform.basisX.cross(image.transform.basisY).dot(image.transform.basisZ) > 0 else { throw IndependentShapeExchangeError.metadataLoss("Reflected surface requires a retained standard affine carrier.") }
      guard case .analytic(let original) = image.source else { throw IndependentShapeExchangeError.unsupportedSemantics("Original image surface requires its actual standard basis producer.") }
      let originalOrigin: Point3D, originalAxis: Vector3D, originalReference: Vector3D, type: String, encoded: String
      switch original {
      case .cylinder(let point, let normal, let radius):
        guard image.vGain == length, image.vOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("Original axial cylinder chart conflicts with output units.") }
        originalOrigin = point; originalAxis = normal; originalReference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        type = "CYLINDRICAL_SURFACE"; encoded = number(units.length.fromInternal(radius))
      case .cone(let apex, let normal, let halfAngle):
        guard image.vGain == length / cos(halfAngle) else { throw IndependentShapeExchangeError.metadataLoss("Original axial cone chart conflicts with output units.") }
        originalOrigin = apex + normal * (image.vOffset * cos(halfAngle)); originalAxis = normal
        originalReference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        let radius = image.vOffset * sin(halfAngle)
        guard radius >= 0 else { throw IndependentShapeExchangeError.metadataLoss("Original cone reference radius is negative.") }
        type = "CONICAL_SURFACE"; encoded = number(units.length.fromInternal(radius)) + "," + (try angle(halfAngle, table: &table))
      case .sphere(let center, let radius):
        guard try gainsEquivalent(image.vParameterGain, angular, table: &table), image.vOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("Original sphere latitude chart conflicts with output units.") }
        originalOrigin = center; originalAxis = .unitZ; originalReference = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance).u
        type = "SPHERICAL_SURFACE"; encoded = number(units.length.fromInternal(radius))
      case .torus(let center, let normal, let majorRadius, let minorRadius):
        guard try gainsEquivalent(image.vParameterGain, angular, table: &table), image.vOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("Original torus chart conflicts with output units.") }
        originalOrigin = center; originalAxis = normal; originalReference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        type = "TOROIDAL_SURFACE"; encoded = number(units.length.fromInternal(majorRadius)) + "," + number(units.length.fromInternal(minorRadius))
      case .plane: throw IndependentShapeExchangeError.unsupportedSemantics("Original image plane requires a spatial affine chart producer.")
      }
      let position = try positionEntityID ?? axisPlacementEntity(origin: image.transform.applying(to: originalOrigin),
        axis: image.transform.applying(to: originalAxis), reference: image.transform.applying(to: originalReference), units: units.length, table: &table)
      return try table.add("\(type)(\(quoted),#\(position),\(encoded))")
    case .cylinder(let cylinder):
      origin = cylinder.origin; axis = cylinder.axis
      reference = try ExactAnalyticFrame.directBasis(for: axis, tolerance: tolerance).u
      family = "CYLINDRICAL_SURFACE"; measures = number(units.length.fromInternal(cylinder.radius))
    case .analytic(let analytic):
      switch analytic {
      case .plane(let point, let normal):
        origin = point; axis = normal; reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        family = "PLANE"; measures = ""
      case .cylinder(let point, let normal, let radius):
        origin = point; axis = normal; reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        family = "CYLINDRICAL_SURFACE"; measures = number(units.length.fromInternal(radius))
      case .cone(let apex, let normal, let halfAngle):
        origin = apex; axis = normal; reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        family = "CONICAL_SURFACE"; measures = "0.," + (try angle(halfAngle, table: &table))
      case .sphere(let center, let radius):
        origin = center; axis = .unitZ; reference = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance).u
        family = "SPHERICAL_SURFACE"; measures = number(units.length.fromInternal(radius))
      case .torus(let center, let normal, let majorRadius, let minorRadius):
        origin = center; axis = normal; reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
        family = "TOROIDAL_SURFACE"; measures = number(units.length.fromInternal(majorRadius)) + "," + number(units.length.fromInternal(minorRadius))
      }
    case .procedural(.offset(let offset)):
      let basis = try independentAnalyticSurfaceEntity(offset.source, name: "", units: units, positionEntityID: nil, originalAngularGain: originalAngularGain, table: &table)
      return try table.add("OFFSET_SURFACE(\(quoted),#\(basis),\(number(units.length.fromInternal(offset.distance))),.U.)")
    case .plane(let plane):
      origin = plane.origin; axis = plane.normal
      reference = try surface.differentialGeometry(u: 0, v: 0, tolerance: tolerance).tangentU
      family = "PLANE"; measures = ""
    case .bSpline(let spline): return try bSplineSurfaceEntity(spline, name: name, units: units.length, table: &table)
    default:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Independent procedural surface egress needs the explicit certified conversion policy.
      // Exact STEP export reaches this branch; actual bounded conversion and its published guarantee are required before success.
      throw IndependentShapeExchangeError.unsupportedSemantics("Independent procedural surface needs a certified exchange conversion.")
    }
    let position = try positionEntityID ?? axisPlacementEntity(origin: origin, axis: axis, reference: reference, units: units.length, table: &table)
    return try table.add("\(family)(\(quoted),#\(position)\(measures.isEmpty ? "" : "," + measures))")
  }

  private func gainsEquivalent(_ lhs: OriginalParameterGain, _ rhs: OriginalParameterGain,
      table: inout EntityTable) throws -> Bool {
    return try lhs.isEquivalent(to: rhs, usage: &table)
  }

  private func independentCurveEntity(_ curve:Curve3D,name:String,units:LengthUnit,angleUnit:AngleUnit = .radian,originalAngularGain:OriginalParameterGain? = nil,positionEntityID:Int? = nil,table:inout EntityTable) throws -> Int {
    switch curve {
    case .parameterImage(let image):
      let gain = originalAngularGain ?? (angleUnit == .degree ? .ratio(numerator: Double.pi, denominator: 180) : .binary(1))
      guard try gainsEquivalent(image.parameterGain, gain, table: &table), image.offset == 0 else { throw IndependentShapeExchangeError.metadataLoss("Original angular chart conflicts with the output unit context.") }
      return try independentCurveEntity(image.source, name: name, units: units, angleUnit: .radian, positionEntityID: positionEntityID, table: &table)
    case .originalAffineWord(let image):
      guard let placement = positionEntityID else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Generic original operation-word curves need a legal original frame/context carrier.
        // Independent positioned conics consume their retained frame; arbitrary native words require explicit loss or certified conversion.
        throw IndependentShapeExchangeError.metadataLoss("Original operation-word curve lacks its standard position carrier.")
      }
      let label = try table.quotedString(name)
      switch image.source {
      case .circle(let circle):
        guard circle.center == .origin, circle.normal == .unitZ else { throw IndependentShapeExchangeError.invalidAssociation("Foreign local circle law.") }
        return try table.add("CIRCLE(\(label),#\(placement),\(number(circle.radius)))")
      case .analytic(.ellipse(let center, let normal, let axis, let major, let minor)):
        guard center == .origin, normal == .unitZ, axis == .unitX else { throw IndependentShapeExchangeError.invalidAssociation("Foreign local ellipse law.") }
        return try table.add("ELLIPSE(\(label),#\(placement),\(number(major)),\(number(minor)))")
      case .analytic(.hyperbola(let local)):
        guard local.center == .origin, local.normal == .unitZ, local.transverseAxis == .unitX else { throw IndependentShapeExchangeError.invalidAssociation("Foreign local hyperbola law.") }
        return try table.add("HYPERBOLA(\(label),#\(placement),\(number(local.transverseRadius)),\(number(local.conjugateRadius)))")
      case .analytic(.parabola(let local)):
        guard local.vertex == .origin, local.normal == .unitZ, local.axis == .unitX else { throw IndependentShapeExchangeError.invalidAssociation("Foreign local parabola law.") }
        return try table.add("PARABOLA(\(label),#\(placement),\(number(local.focalLength)))")
      default:
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original word-image standard emission for other primitive families is still being composed.
        // Keep the original source law and native parameters before this production writer can accept another family.
        throw IndependentShapeExchangeError.unsupportedSemantics("Original word curve has no standard primitive emission yet.")
      }
    case .line(let line):
      let origin = try cartesianPoint(line.origin,units:units,table:&table), direction = try directionEntity(line.direction,table:&table)
      let vector = try table.add("VECTOR('',#\(direction),\(number(units.fromInternal(1))))")
      return try table.add("LINE(\(try table.quotedString(name)),#\(origin),#\(vector))")
    case .affineImage(let image):
      if case .line(let line) = image.source {
        let p = image.transform.applying(to:line.origin), d = image.transform.applying(to:line.direction), magnitude = d.length
        guard magnitude > 0, magnitude.isFinite else { throw IndependentShapeExchangeError.invalidAssociation("Singular original affine line.") }
        let origin = try cartesianPoint(p,units:units,table:&table), direction = try directionEntity(d/magnitude,table:&table)
        let vector = try table.add("VECTOR('',#\(direction),\(number(units.fromInternal(magnitude))))")
        return try table.add("LINE(\(try table.quotedString(name)),#\(origin),#\(vector))")
      }
      if case .circle(let circle) = image.source {
        let scale = positionEntityID == nil ? try IndependentProducer.orthogonal(image.transform,unitScale:false,table:&table) : 1
        let basis = try ExactAnalyticFrame.directBasis(for:circle.normal,tolerance:tolerance)
        let originalU = image.transform.applying(to:basis.u)/scale
        let originalV = image.transform.applying(to:basis.v)/scale
        let placement = try positionEntityID ?? axisPlacementEntity(origin:image.transform.applying(to:circle.center),
            axis:originalU.cross(originalV),reference:originalU,units:units,table:&table)
        return try table.add("CIRCLE(\(try table.quotedString(name)),#\(placement),\(number(units.fromInternal(circle.radius*scale))))")
      }
      if case .analytic(.parabola(let parabola)) = image.source {
        let scale = units.toInternal(1)
        if positionEntityID == nil {
          let originalScale = try IndependentProducer.orthogonal(image.transform,unitScale:false,table:&table)
          guard originalScale == scale else { throw IndependentShapeExchangeError.metadataLoss("STEP parabola parameter unit cannot retain this affine source chart.") }
        }
        guard image.transform.basisZ.cross(image.transform.basisX).dot(image.transform.basisY) > 0 else {
          throw IndependentShapeExchangeError.metadataLoss("STEP parabola parameter unit cannot retain this affine source chart.")
        }
        let placement = try positionEntityID ?? axisPlacementEntity(origin:image.transform.applying(to:parabola.vertex),
            axis:image.transform.applying(to:parabola.normal)/scale,reference:image.transform.applying(to:parabola.axis)/scale,units:units,table:&table)
        return try table.add("PARABOLA(\(try table.quotedString(name)),#\(placement),\(number(parabola.focalLength)))")
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Independent STEP export has no original coefficient producer for every affine-image curve family.
      // Preserve the exact native parameter law, including nonorthogonal conic images, before this public path succeeds.
      throw IndependentShapeExchangeError.unsupportedSemantics("Independent STEP affine curve family is not implemented.")
    case .bSpline(let spline): return try bSplineCurveEntity(spline,name:name,units:units,table:&table)
    case .circle(let circle):
      let basis = try ExactAnalyticFrame.directBasis(for:circle.normal,tolerance:tolerance)
      let placement = try positionEntityID ?? axisPlacementEntity(origin:circle.center,axis:circle.normal,reference:basis.u,units:units,table:&table)
      return try table.add("CIRCLE(\(try table.quotedString(name)),#\(placement),\(number(units.fromInternal(circle.radius))))")
    case .analytic(let analytic):
      switch analytic {
      case .line(let origin,let direction):
        return try independentCurveEntity(.line(Line3D(origin:origin,direction:direction)),name:name,units:units,table:&table)
      case .circle(let center,let normal,let radius):
        let basis = try ExactAnalyticFrame.analyticBasis(for:normal,tolerance:tolerance)
        let placement = try positionEntityID ?? axisPlacementEntity(origin:center,axis:normal,reference:basis.u,units:units,table:&table)
        return try table.add("CIRCLE(\(try table.quotedString(name)),#\(placement),\(number(units.fromInternal(radius))))")
      case .ellipse(let center,let normal,let majorAxis,let majorRadius,let minorRadius):
        let placement = try positionEntityID ?? axisPlacementEntity(origin:center,axis:normal,reference:majorAxis,units:units,table:&table)
        return try table.add("ELLIPSE(\(try table.quotedString(name)),#\(placement),\(number(units.fromInternal(majorRadius))),\(number(units.fromInternal(minorRadius))))")
      case .hyperbola(let hyperbola):
        let placement = try positionEntityID ?? axisPlacementEntity(origin:hyperbola.center,axis:hyperbola.normal,reference:hyperbola.transverseAxis,units:units,table:&table)
        return try table.add("HYPERBOLA(\(try table.quotedString(name)),#\(placement),\(number(units.fromInternal(hyperbola.transverseRadius))),\(number(units.fromInternal(hyperbola.conjugateRadius))))")
      case .parabola(let parabola):
        guard units == .meter else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP export does not yet transport a native parabola's length parameter across differing model units.
          // Preserve its original same-number parameter law before non-meter native parabola authoring succeeds.
          throw IndependentShapeExchangeError.unsupportedSemantics("Native parabola chart requires a proved parameter-unit transport.")
        }
        let placement = try positionEntityID ?? axisPlacementEntity(origin:parabola.vertex,axis:parabola.normal,reference:parabola.axis,units:units,table:&table)
        return try table.add("PARABOLA(\(try table.quotedString(name)),#\(placement),\(number(parabola.focalLength)))")
      case .arc, .planeTorus:
        // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP export has not proved the bounded arc/certified-intersection source domain transport.
        // Retain the original source domain and associations before these original families succeed.
        throw IndependentShapeExchangeError.unsupportedSemantics("Independent STEP bounded analytic curve family is not implemented.")
      }
    default:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Independent STEP public egress has not yet composed every original analytic/procedural curve producer.
      // Implement standard original-law authoring and independent two-generation proofs before full X7 curve availability.
      throw IndependentShapeExchangeError.unsupportedSemantics("Independent STEP curve family is not implemented.")
    }
  }

  func write(
    brep: BRepModel,
    units: UnitSystem,
    to sink: any ByteSink
  ) throws {
    let processing = processingBudget
    var table = EntityTable(maximumEntities: resourceLimits.maximumEntities, tolerance: tolerance, maximumBytes: resourceLimits.maximumBytes,
        maximumStringWork: resourceLimits.maximumIterations, maximumSourceDepth: resourceLimits.maximumNesting, maximumAlgebraicDepth: resourceLimits.maximumAlgebraicDepth, processingBudget: processing)
    _ = try appendDefinition(brep: brep, units: units, identifier: "SWIFTCAD", name: "",
        additionalItems: [], table: &table)
    try publish(table: table, to: sink)
  }

  func appendProduct(_ product: AssemblyProduct, table: inout EntityTable) throws -> Int {
    let application = try table.add("APPLICATION_CONTEXT('managed model based 3d engineering')")
    let context = try table.add("PRODUCT_CONTEXT('',#\(application),'mechanical')")
    let text = try product.description.map { try table.quotedString($0) } ?? "$"
    return try table.add("PRODUCT(\(try table.quotedString(product.identifier)),\(try table.quotedString(product.name)),\(text),(#\(context)))")
  }

  func appendFormation(_ formation: AssemblyProductFormation, product: Int, table: inout EntityTable) throws -> Int {
    let identifier = try table.quotedString(formation.versionIdentifier)
    let text = try formation.description.map { try table.quotedString($0) } ?? "$"
    if let specified = formation.specifiedSource {
      return try table.add("PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE(\(identifier),\(text),#\(product),.\(specified.rawValue.uppercased()).)")
    }
    return try table.add("PRODUCT_DEFINITION_FORMATION(\(identifier),\(text),#\(product))")
  }

  func appendDefinition(brep: BRepModel, units: UnitSystem, identifier: String, name: String,
                        productDescription: String? = "", definitionDescription: String? = "",
                        additionalItems: [Int], retainedFormation: Int? = nil, definitionIdentifier: String = "design", wholePartCarrier: Bool = false, bodyNames: [BodyID: String] = [:], faceNames: [FaceID: String] = [:],
                        table: inout EntityTable) throws -> WrittenDefinition {
    try requireCertifiedBodySurfaceIncidence(brep)
    guard brep.bodies.values.allSatisfy({ $0.material == nil }) else {
      throw ProductAttributeError.unsupportedSemantics("Legacy PBR Body.material references need an explicit physical/presentation conversion before STEP export.")
    }
    let applicationContext = try table.add(
      "APPLICATION_CONTEXT('managed model based 3d engineering')")
    let formation: Int
    if let retainedFormation {
      formation = retainedFormation
    } else {
      let productContext = try table.add("PRODUCT_CONTEXT('',#\(applicationContext),'mechanical')")
      let productIdentifier = try table.quotedString(identifier), productName = try table.quotedString(name)
      let productText = try productDescription.map { try table.quotedString($0) } ?? "$"
      let product = try table.add("PRODUCT(\(productIdentifier),\(productName),\(productText),(#\(productContext)))")
      formation = try table.add("PRODUCT_DEFINITION_FORMATION('','',#\(product))")
    }
    let definitionText = try definitionDescription.map { try table.quotedString($0) } ?? "$"
    let definitionContext = try table.add(
      "PRODUCT_DEFINITION_CONTEXT('part definition',#\(applicationContext),'design')")
    let definition = try table.add(
      "PRODUCT_DEFINITION(\(try table.quotedString(definitionIdentifier)),\(definitionText),#\(formation),#\(definitionContext))")
    let definitionShape = try table.add("PRODUCT_DEFINITION_SHAPE('','',#\(definition))")
    let geometryContext = try appendGeometryContext(units: units, table: &table)
    let geometry = try appendGeometry(brep: brep, units: units, geometryContext: geometryContext,
        bodyNames: bodyNames, faceNames: faceNames, table: &table)
    return try appendGeometryRepresentation(geometry, definition: definition, definitionShape: definitionShape,
        additionalItems: additionalItems, wholePartCarrier: wholePartCarrier, units: units, table: &table)
  }

  /// Emits topology without manufacturing any product or definition owner.
  func appendGeometry(brep: BRepModel, units: UnitSystem,
                      geometryContext: WrittenGeometryContext,
                      bodyNames: [BodyID: String], faceNames: [FaceID: String],
                      table: inout EntityTable) throws -> WrittenGeometry {
    guard brep.bodies.values.allSatisfy({ $0.material == nil }) else {
      throw ProductAttributeError.unsupportedSemantics("Legacy PBR Body.material references need an explicit physical/presentation conversion before STEP export.")
    }
    let representationType: String
    if brep.bodies.isEmpty { representationType = "SHAPE_REPRESENTATION" }
    else if brep.bodies.values.allSatisfy({ $0.kind == .solid }) { representationType = "ADVANCED_BREP_SHAPE_REPRESENTATION" }
    else if brep.bodies.values.allSatisfy({ $0.kind != .solid }) { representationType = "MANIFOLD_SURFACE_SHAPE_REPRESENTATION" }
    else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Public exact STEP and assembly exports cannot yet express mixed sheet/solid representation groups.
      // A proved standard mixed-family association and attribute carrier must retain every item owner before this path can succeed.
      throw ProductAttributeError.unsupportedSemantics("Mixed sheet and solid STEP geometry requires a proved representation family.")
    }
    guard geometryContext.units == units else { throw AssemblyError.invalidSource("Geometry context has conflicting owned units.") }
    let context = geometryContext.context
    var vertexEntities: [VertexID: Int] = [:]
    for vertexID in brep.vertices.keys.sorted() {
      guard let vertex = brep.vertices[vertexID] else {
        throw exchangeError(.missingReference, "STEP vertex table is incomplete.")
      }
      let point = try cartesianPoint(vertex.point, units: units.length, table: &table)
      vertexEntities[vertexID] = try table.add("VERTEX_POINT('',#\(point))")
    }
    let parameterContext = try table.add(
      "(GEOMETRIC_REPRESENTATION_CONTEXT(2) PARAMETRIC_REPRESENTATION_CONTEXT() REPRESENTATION_CONTEXT('2D SPACE',''))"
    )
    var surfaceEntities: [SurfaceID: Int] = [:]
    var surfaceEntityByGeometry: [Surface3D: Int] = [:]
    for faceID in brep.faces.keys.sorted() {
      guard let face = brep.faces[faceID],
        let surface = brep.geometry.surfaces[face.surfaceID]
      else {
        throw exchangeError(.missingReference, "STEP face surface is missing.")
      }
      if surfaceEntities[face.surfaceID] == nil {
        let entity = try exactSurfaceEntity(
          surface,
          units: units.length,
          table: &table
        )
        surfaceEntities[face.surfaceID] = entity
        surfaceEntityByGeometry[surface] = entity
      }
    }
    var curveEntities: [EdgeID: Int] = [:]
    var edgeSameSense: [EdgeID: Bool] = [:]
    var exactIntersectionAssociations: [EdgeID: [SurfaceCurveAssociation]] = [:]
    for edgeID in brep.edges.keys.sorted() {
      guard let edge = brep.edges[edgeID],
        let startPoint = brep.vertices[edge.startVertexID]?.point,
        let endPoint = brep.vertices[edge.endVertexID]?.point,
        let curve = brep.geometry.curves[edge.curveID]
      else {
        throw exchangeError(.missingReference, "STEP edge geometry is incomplete.")
      }
      if let converted = curveConversions.edges[edgeID] {
        guard let trim = curveConversions.selections[edgeID] else { throw exchangeError(.topologyFailure, "Converted edge lost its original directed selection.") }
        let basis = try bSplineCurveEntity(converted, units: units.length, table: &table)
        curveEntities[edgeID] = try table.add("TRIMMED_CURVE('SWIFTCAD_CERTIFIED_TRIM',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(trim.endParameter > trim.startParameter ? ".T." : ".F."),.PARAMETER.)")
        edgeSameSense[edgeID] = true
        continue
      }
      switch curve {
      case .line(let line):
        let origin = try cartesianPoint(line.origin, units: units.length, table: &table)
        let direction = try directionEntity(line.direction, table: &table)
        let vector = try table.add("VECTOR('',#\(direction),\(number(units.length.fromInternal(1))))")
        curveEntities[edgeID] = try table.add("LINE('',#\(origin),#\(vector))")
        let directionResidual = (endPoint - startPoint).dot(line.direction)
        guard abs(directionResidual) > tolerance.distance else {
          throw exchangeError(
            .topologyFailure, "STEP line direction is perpendicular to its edge span.")
        }
        edgeSameSense[edgeID] = directionResidual > 0.0
      case .bSpline(let bSpline):
        guard let trim = edge.trim,
          case .closed(let lower, let upper) = bSpline.domain
        else {
          throw exchangeError(
            .topologyFailure,
            "STEP B-spline edges require a finite explicit trim interval."
          )
        }
        guard trim.startParameter >= lower - tolerance.distance,
          trim.startParameter <= upper + tolerance.distance,
          trim.endParameter >= lower - tolerance.distance,
          trim.endParameter <= upper + tolerance.distance,
          abs(trim.endParameter - trim.startParameter) > tolerance.distance
        else {
          throw exchangeError(
            .topologyFailure,
            "STEP B-spline edge trim is outside its finite knot domain."
          )
        }
        let basis = try bSplineCurveEntity(
          bSpline,
          units: units.length,
          table: &table
        )
        let followsBasis = trim.endParameter > trim.startParameter
        curveEntities[edgeID] = try table.add(
          "TRIMMED_CURVE('SWIFTCAD_BSPLINE_TRIM',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(followsBasis ? ".T." : ".F."),.PARAMETER.)"
        )
        edgeSameSense[edgeID] = true
      case .circle(let circle):
        let trim = try requiredPeriodicTrim(edge, label: "circle")
        curveEntities[edgeID] = try circleEntity(
          circle,
          units: units.length,
          table: &table
        )
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
      case .analytic(let analytic):
        if case .planeTorus(let planeTorus) = analytic {
          guard let trim = edge.trim else {
            throw exchangeError(
              .topologyFailure,
              "STEP plane-torus intersection edges require an explicit trim."
            )
          }
          let transfer = try ExactPlaneTorusTransferBuilder().build(
            curve: planeTorus,
            trim: trim,
            tolerance: tolerance
          )
          curveEntities[edgeID] = try bSplineCurveEntity(
            transfer.curve,
            units: units.length,
            table: &table
          )
          edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
          let exactSurfaces = [planeTorus.planeSurface, planeTorus.torusSurface]
          exactIntersectionAssociations[edgeID] = try exactSurfaces.map { surface in
            let entity: Int
            if let existing = surfaceEntityByGeometry[surface] {
              entity = existing
            } else {
              entity = try exactSurfaceEntity(
                surface,
                units: units.length,
                table: &table
              )
              surfaceEntityByGeometry[surface] = entity
            }
            return SurfaceCurveAssociation(entity: entity, isPcurve: false)
          }
        } else {
          let result = try analyticCurveEntity(
            analytic,
            edge: edge,
            startPoint: startPoint,
            endPoint: endPoint,
            units: units.length,
            table: &table
          )
          curveEntities[edgeID] = result.entity
          edgeSameSense[edgeID] = result.sameSense
        }
      case .implicit(let implicit):
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "STEP implicit intersection edges require an explicit trim."
          )
        }
        let source = try ExactImplicitIntersectionTransferSource.resolve(
          edgeID: edgeID,
          in: brep,
          tolerance: tolerance
        )
        guard source.curve == implicit else {
          throw exchangeError(
            .topologyFailure,
            "STEP implicit edge curve disagrees with its certified pcurve provenance."
          )
        }
        let transfer = try ExactImplicitIntersectionTransferBuilder().build(
          source: source,
          trim: trim,
          tolerance: tolerance
        )
        curveEntities[edgeID] = try bSplineCurveEntity(
          transfer.curve,
          units: units.length,
          table: &table
        )
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
        exactIntersectionAssociations[edgeID] = try [
          source.firstSurface,
          source.secondSurface,
        ].map { surface in
          let entity: Int
          if let existing = surfaceEntityByGeometry[surface] {
            entity = existing
          } else {
            entity = try exactSurfaceEntity(
              surface,
              units: units.length,
              table: &table
            )
            surfaceEntityByGeometry[surface] = entity
          }
          return SurfaceCurveAssociation(entity: entity, isPcurve: false)
        }
      case .surfaceLift(let lift):
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "STEP surface-lift edges require an explicit normalized trim."
          )
        }
        let transfer = try ExactSurfaceLiftTransferBuilder().build(
          lift: lift,
          trim: trim,
          tolerance: tolerance
        )
        curveEntities[edgeID] = try bSplineCurveEntity(
          transfer.curve,
          name: "SWIFTCAD_SURFACE_LIFT",
          units: units.length,
          table: &table
        )
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
      case .certifiedIntersection, .rigidImage:
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "STEP certified transfer curves require an explicit normalized trim."
          )
        }
        let transfer = try ExactCertifiedCurveTransferBuilder().build(
          curve: curve,
          trim: trim,
          tolerance: tolerance
        )
        curveEntities[edgeID] = try bSplineCurveEntity(
          transfer.curve,
          name: transfer.representsSurfaceLift
            ? "SWIFTCAD_SURFACE_LIFT"
            : "SWIFTCAD_CERTIFIED_CURVE",
          units: units.length,
          table: &table
        )
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
        if transfer.representsSurfaceLift {
          continue
        }
        var associations: [SurfaceCurveAssociation] = []
        for support in [transfer.firstSurface, transfer.secondSurface] {
          let entity: Int
          if let existing = surfaceEntityByGeometry[support] {
            entity = existing
          } else {
            entity = try exactSurfaceEntity(
              support,
              units: units.length,
              table: &table
            )
            surfaceEntityByGeometry[support] = entity
          }
          let association = SurfaceCurveAssociation(
            entity: entity,
            isPcurve: false
          )
          if associations.contains(association) == false {
            associations.append(association)
          }
        }
        exactIntersectionAssociations[edgeID] = associations
      // FIXME(INCOMPLETE_IMPLEMENTATION): Body word images and exact endpoint connectors need original-law standard transport or a caller-certified conversion producer.
      // The public STEP Body writer must preserve the complete directed law; construction splines or rounded word columns cannot serve as exact source.
      case .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
        throw exchangeError(.unsupportedCapability, "STEP original word/endpoint connector Body transport requires its original producer.")
      case .parameterImage:
        guard let trim = edge.trim else { throw exchangeError(.topologyFailure, "STEP original parameter image requires its real finite edge trim.") }
        try trim.validate(on:curve,edgeID:edgeID,tolerance:tolerance)
        let basis = try independentCurveEntity(curve,name:"",units:units.length,angleUnit:units.angle,positionEntityID:nil,table:&table)
        let forward = trim.endParameter > trim.startParameter
        curveEntities[edgeID] = try table.add("TRIMMED_CURVE('',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(forward ? ".T." : ".F."),.PARAMETER.)")
        edgeSameSense[edgeID] = true
      case .affineImage(let image):
        if let line = curve.exactLinearLocus {
          let origin = try cartesianPoint(
            line.origin,
            units: units.length,
            table: &table
          )
          let direction = try directionEntity(line.direction, table: &table)
          guard case .line(let original) = image.source else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact Body STEP output has no native parameter proof for every affine linear-locus source.
            // Preserve the complete original parameter law for non-LINE sources before this public branch succeeds.
            throw exchangeError(.unsupportedCapability, "STEP affine linear locus lacks an original LINE parameter owner.")
          }
          let magnitude = image.transform.applying(to:original.direction).length
          let vector = try table.add("VECTOR('',#\(direction),\(number(units.length.fromInternal(magnitude))))")
          curveEntities[edgeID] = try table.add("LINE('',#\(origin),#\(vector))")
          let directionResidual = (endPoint - startPoint).dot(line.direction)
          guard abs(directionResidual) > tolerance.distance else {
            throw exchangeError(
              .singularGeometry,
              "STEP affine-image line geometry is inconsistent with its vertices."
            )
          }
          edgeSameSense[edgeID] = directionResidual > 0.0
          continue
        }
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "STEP affine-image curves require an explicit finite trim interval."
          )
        }
        try trim.validate(
          on: curve,
          edgeID: edgeID,
          tolerance: tolerance
        )
        let interval = try ScalarInterval(
          lower: min(trim.startParameter, trim.endParameter),
          upper: max(trim.startParameter, trim.endParameter)
        )
        guard
          let exactCurve = try AnalyticCurveBSplineBuilder().boundedCurve(
            curve: curve,
            interval: interval,
            maximumSpanCount: 4_096,
            tolerance: tolerance
          )
        else {
          throw exchangeError(
            .unsupportedCapability,
            "STEP has no exact rational representation for this affine-image curve."
          )
        }
        let expectedStart = try exactCurve.point(
          at: trim.startParameter,
          tolerance: tolerance
        )
        let expectedEnd = try exactCurve.point(
          at: trim.endParameter,
          tolerance: tolerance
        )
        guard
          expectedStart.isApproximatelyEqual(
            to: startPoint,
            tolerance: tolerance.distance
          ),
          expectedEnd.isApproximatelyEqual(
            to: endPoint,
            tolerance: tolerance.distance
          )
        else {
          throw exchangeError(
            .topologyFailure,
            "STEP affine-image rational transfer disagrees with its edge vertices."
          )
        }
        let basis = try bSplineCurveEntity(
          exactCurve,
          units: units.length,
          table: &table
        )
        let followsBasis = trim.endParameter > trim.startParameter
        curveEntities[edgeID] = try table.add(
          "TRIMMED_CURVE('SWIFTCAD_BSPLINE_TRIM',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(followsBasis ? ".T." : ".F."),.PARAMETER.)"
        )
        edgeSameSense[edgeID] = true
      }
    }
    var edgeAssociations = exactIntersectionAssociations
    for faceID in brep.faces.keys.sorted() {
      guard let face = brep.faces[faceID],
        let surface = brep.geometry.surfaces[face.surfaceID],
        let surfaceEntity = surfaceEntities[face.surfaceID]
      else {
        throw exchangeError(.missingReference, "STEP face surface is missing.")
      }
      let emittedSurface = surfaceOverrides[surface].map(Surface3D.bSpline) ?? surface
      for loopID in face.loops {
        guard let loop = brep.loops[loopID] else {
          throw exchangeError(.missingReference, "STEP face loop is missing.")
        }
        for coedge in loop.coedges {
          guard let parameterCurve = coedge.surfaceParameterCurve,
            let edge = brep.edges[coedge.edgeID],
            let sameSense = edgeSameSense[coedge.edgeID],
            let start = brep.vertices[edge.startVertexID]?.point,
            let end = brep.vertices[edge.endVertexID]?.point
          else {
            throw exchangeError(.topologyFailure, "STEP exact coedge p-curve is incomplete.")
          }
          let association = try pcurveEntity(
            parameterCurve: parameterCurve,
            parameterCurveFollowsModel: (coedge.orientation == .forward) == sameSense,
            modelStart: sameSense ? start : end,
            modelEnd: sameSense ? end : start,
            surface: emittedSurface,
            surfaceEntity: surfaceEntity,
            units: units.length,
            parameterContext: parameterContext,
            table: &table
          )
          if edgeAssociations[coedge.edgeID, default: []].contains(association) == false {
            edgeAssociations[coedge.edgeID, default: []].append(association)
          }
          guard edgeAssociations[coedge.edgeID, default: []].count <= 2 else {
            throw exchangeError(
              .unsupportedCapability,
              "STEP SURFACE_CURVE supports at most two exact face-surface associations."
            )
          }
        }
      }
    }
    var edgeEntities: [EdgeID: Int] = [:]
    for edgeID in brep.edges.keys.sorted() {
      guard let edge = brep.edges[edgeID],
        let startVertex = vertexEntities[edge.startVertexID],
        let endVertex = vertexEntities[edge.endVertexID],
        let curve = curveEntities[edgeID],
        let associations = edgeAssociations[edgeID],
        !associations.isEmpty,
        let sameSense = edgeSameSense[edgeID]
      else {
        throw exchangeError(.missingReference, "STEP edge geometry or p-curve is missing.")
      }
      let masterRepresentation =
        associations.allSatisfy(\.isPcurve)
        ? ".PCURVE_S1."
        : ".CURVE_3D."
      let surfaceCurve = try table.add(
        "SURFACE_CURVE('',#\(curve),(\(associations.map { "#\($0.entity)" }.joined(separator: ","))),\(masterRepresentation))"
      )
      edgeEntities[edgeID] = try table.add(
        "EDGE_CURVE('',#\(startVertex),#\(endVertex),#\(surfaceCurve),\(sameSense ? ".T." : ".F."))"
      )
    }
    var faceEntities: [FaceID: Int] = [:]
    for faceID in brep.faces.keys.sorted() {
      guard let face = brep.faces[faceID],
        let surface = surfaceEntities[face.surfaceID]
      else {
        throw exchangeError(
          .unsupportedCapability,
          "STEP face surface has no exported exact entity."
        )
      }
      var bounds: [Int] = []
      for loopID in face.loops {
        guard let loop = brep.loops[loopID] else {
          throw exchangeError(.missingReference, "STEP face loop is missing.")
        }
        let orientedEdges = try loop.coedges.map { coedge -> Int in
          guard let edge = edgeEntities[coedge.edgeID] else {
            throw exchangeError(.missingReference, "STEP loop edge is missing.")
          }
          let orientation = coedge.orientation == .forward ? ".T." : ".F."
          return try table.add("ORIENTED_EDGE('',*,*,#\(edge),\(orientation))")
        }
        let loopEntity = try table.add(
          "EDGE_LOOP('',(\(orientedEdges.map { "#\($0)" }.joined(separator: ","))))"
        )
        let boundType = loop.role == .outer ? "FACE_OUTER_BOUND" : "FACE_BOUND"
        bounds.append(try table.add("\(boundType)('',#\(loopEntity),.T.)"))
      }
      let orientation = face.orientation == .forward ? ".T." : ".F."
      faceEntities[faceID] = try table.add(
        "ADVANCED_FACE(\(try table.quotedString(faceNames[faceID] ?? "")),(\(bounds.map { "#\($0)" }.joined(separator: ","))),#\(surface),\(orientation))"
      )
    }
    var representationItems: [Int] = []
    var bodyEntities: [BodyID: [Int]] = [:]
    for bodyID in brep.bodies.keys.sorted() {
      guard let body = brep.bodies[bodyID] else {
        throw exchangeError(.missingReference, "STEP body is missing.")
      }
      let firstItem = representationItems.count
      var shellEntities: [Int] = []
      for shellID in body.shellIDs {
        guard let shell = brep.shells[shellID] else {
          throw exchangeError(.missingReference, "STEP shell is missing.")
        }
        let faces = try shell.faceIDs.map { faceID -> String in
          guard let entity = faceEntities[faceID] else {
            throw exchangeError(.missingReference, "STEP shell face is missing.")
          }
          return "#\(entity)"
        }
        let shellType = body.kind == .solid ? "CLOSED_SHELL" : "OPEN_SHELL"
        let shellEntity = try table.add("\(shellType)('',(\(faces.joined(separator: ","))))")
        shellEntities.append(shellEntity)
      }
      if body.kind == .solid {
        let shellEntityByID = Dictionary(uniqueKeysWithValues: zip(body.shellIDs, shellEntities))
        let components = try brep.solidShellComponents(
          for: bodyID,
          tolerance: tolerance
        )
        for component in components {
          guard let outerEntity = shellEntityByID[component.outerShellID] else {
            throw exchangeError(.missingReference, "STEP solid outer shell is missing.")
          }
          if component.voidShellIDs.isEmpty {
            representationItems.append(
              try table.add(
                "MANIFOLD_SOLID_BREP(\(try table.quotedString(bodyNames[bodyID] ?? body.name ?? "")),#\(outerEntity))"
              ))
            continue
          }
          let orientedVoids: [Int] = try component.voidShellIDs.map { shellID in
            guard let shellEntity = shellEntityByID[shellID] else {
              throw exchangeError(.missingReference, "STEP solid void shell is missing.")
            }
            return try table.add(
              "ORIENTED_CLOSED_SHELL('',*,#\(shellEntity),.F.)"
            )
          }
          representationItems.append(
            try table.add(
              "BREP_WITH_VOIDS(\(try table.quotedString(bodyNames[bodyID] ?? body.name ?? "")),#\(outerEntity),(\(orientedVoids.map { "#\($0)" }.joined(separator: ","))))"
            ))
        }
      } else {
        representationItems.append(
          try table.add(
            "SHELL_BASED_SURFACE_MODEL(\(try table.quotedString(bodyNames[bodyID] ?? body.name ?? "")),(\(shellEntities.map { "#\($0)" }.joined(separator: ","))))"
          ))
      }
      bodyEntities[bodyID] = Array(representationItems[firstItem...])
    }
    return WrittenGeometry(items: representationItems, context: context, origin: geometryContext.origin,
        representationType: representationType, bodies: bodyEntities, faces: faceEntities)
  }

  func appendGeometryContext(units: UnitSystem, table: inout EntityTable) throws -> WrittenGeometryContext {
    let context = try appendRepresentationContext(units: units, table: &table)
    let origin = try assemblyAxis(.translated(by: .zero), units: units.length, table: &table)
    return WrittenGeometryContext(units: units, context: context, origin: origin)
  }

  private func appendRepresentationContext(units: UnitSystem, table: inout EntityTable) throws -> Int {
    let lengthUnit = try lengthUnitEntity(units.length, table: &table)
    let angleUnit = try table.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
    let solidAngleUnit = try table.add("(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT())")
    let uncertainty = number(units.length.fromInternal(tolerance.distance))
    let context = try table.add(
      "(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#\(try table.add("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(uncertainty)),#\(lengthUnit),'distance_accuracy_value','confusion accuracy')")))) GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(lengthUnit),#\(angleUnit),#\(solidAngleUnit))) REPRESENTATION_CONTEXT('',''))"
    )
    return context
  }

  func appendModularDefinition(geometries: [WrittenGeometry], retainedFormation: Int,
                               identifier: String, description: String?, placementItems: [Int] = [], wholePartCarrier: Bool,
                               units: UnitSystem, processing: ExchangeProcessingBudget, table: inout EntityTable) throws -> WrittenDefinition {
    if !wholePartCarrier { try validatePlacementItems(placementItems, table: table) }
    guard let first = geometries.first else { throw AssemblyError.invalidSource("Missing modular STEP geometry.") }
    var items: [Int] = [], bodies: [BodyID: [Int]] = [:], faces: [FaceID: Int] = [:]
    for geometry in geometries {
      try processing.check(format: .step)
      guard geometry.context == first.context, geometry.origin == first.origin else {
        throw AssemblyError.invalidSource("Modular geometry requires one owned representation context.")
      }
      guard geometry.representationType == first.representationType else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP assembly export admits homogeneous modular groups only.
        // Standard mixed-family composition and scope-preserving carriers must be proved before combining sheet and solid feature owners.
        throw ProductAttributeError.unsupportedSemantics("Mixed sheet and solid STEP geometry requires a proved representation family.")
      }
      items.append(contentsOf: geometry.items)
      for (body, entities) in geometry.bodies {
        try processing.check(format: .step)
        guard bodies.updateValue(entities, forKey: body) == nil else { throw AssemblyError.invalidSource("Competing modular body ownership.") }
      }
      for (face, entity) in geometry.faces {
        try processing.check(format: .step)
        guard faces.updateValue(entity, forKey: face) == nil else { throw AssemblyError.invalidSource("Competing modular face ownership.") }
      }
    }
    let application = try table.add("APPLICATION_CONTEXT('managed model based 3d engineering')")
    let context = try table.add("PRODUCT_DEFINITION_CONTEXT('part definition',#\(application),'design')")
    let text = try description.map { try table.quotedString($0) } ?? "$"
    let definition = try table.add("PRODUCT_DEFINITION(\(try table.quotedString(identifier)),\(text),#\(retainedFormation),#\(context))")
    let shape = try table.add("PRODUCT_DEFINITION_SHAPE('','',#\(definition))")
    let combined = WrittenGeometry(items: items, context: first.context, origin: first.origin,
        representationType: first.representationType, bodies: bodies, faces: faces)
    return try appendGeometryRepresentation(combined, definition: definition, definitionShape: shape,
        additionalItems: placementItems, wholePartCarrier: wholePartCarrier, units: units, table: &table)
  }

  private func appendGeometryRepresentation(_ geometry: WrittenGeometry, definition: Int, definitionShape: Int,
                                           additionalItems: [Int], wholePartCarrier: Bool,
                                           units: UnitSystem, table: inout EntityTable) throws -> WrittenDefinition {
    var representationItems = geometry.items
    representationItems.append(geometry.origin)
    if wholePartCarrier {
      try validatePlacementItems(additionalItems, table: table)
    } else {
      representationItems.append(contentsOf: additionalItems)
    }
    let outerContext = try appendRepresentationContext(units: units, table: &table)
    let localContext = wholePartCarrier ? geometry.context : outerContext
    let geometryRepresentation = try table.add(
      "\(geometry.representationType)('',(\(representationItems.map { "#\($0)" }.joined(separator: ","))),#\(localContext))"
    )
    let representation: Int
    let carrier: Int?
    if wholePartCarrier {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP part appearance export still requires real local exact geometry.
      // Prove a source-preserving standard carrier for empty subassemblies before their whole-part appearance can succeed.
      guard !geometry.bodies.isEmpty else {
        throw ProductAttributeError.unsupportedSemantics("Whole-part appearance requires exact local geometry.")
      }
      let map = try table.add("REPRESENTATION_MAP(#\(geometry.origin),#\(geometryRepresentation))")
      let point = try cartesianPoint(.origin, units: units.length, table: &table)
      let x = try directionEntity(.unitX, table: &table), y = try directionEntity(.unitY, table: &table), z = try directionEntity(.unitZ, table: &table)
      let transform = try table.add("CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#\(x),#\(y),#\(point),1.,#\(z))")
      let item = try table.add("MAPPED_ITEM('',#\(map),#\(transform))")
      let outerItems = [item, geometry.origin] + additionalItems
      representation = try table.add("\(geometry.representationType)('',(\(outerItems.map { "#\($0)" }.joined(separator: ","))),#\(outerContext))")
      carrier = item
    } else { representation = geometryRepresentation; carrier = nil }
    _ = try table.add("SHAPE_DEFINITION_REPRESENTATION(#\(definitionShape),#\(representation))")
    return WrittenDefinition(definition: definition, definitionShape: definitionShape, representation: representation,
        context: geometry.context, origin: geometry.origin, geometryRepresentation: geometryRepresentation, carrier: carrier,
        representationType: geometry.representationType, bodies: geometry.bodies, faces: geometry.faces)
  }

  func appendSharedDefinition(geometry: WrittenDefinition, retainedFormation: Int,
                             identifier: String, description: String?, placementItems: [Int] = [], wholePartCarrier: Bool,
                             units: UnitSystem, table: inout EntityTable) throws -> WrittenDefinition {
    try validatePlacementItems(placementItems, table: table)
    let application = try table.add("APPLICATION_CONTEXT('managed model based 3d engineering')")
    let context = try table.add("PRODUCT_DEFINITION_CONTEXT('part definition',#\(application),'design')")
    let text = try description.map { try table.quotedString($0) } ?? "$"
    let definition = try table.add("PRODUCT_DEFINITION(\(try table.quotedString(identifier)),\(text),#\(retainedFormation),#\(context))")
    let shape = try table.add("PRODUCT_DEFINITION_SHAPE('','',#\(definition))")
    let outerContext = try appendRepresentationContext(units: units, table: &table)
    let representation: Int
    let carrier: Int?
    let geometryRepresentation: Int
    if wholePartCarrier {
      guard geometry.carrier != nil else {
        throw AssemblyError.invalidSource("Shared carrier geometry must have an unassociated inner representation.")
      }
      let map = try table.add("REPRESENTATION_MAP(#\(geometry.origin),#\(geometry.geometryRepresentation))")
      let point = try cartesianPoint(.origin, units: units.length, table: &table)
      let x = try directionEntity(.unitX, table: &table), y = try directionEntity(.unitY, table: &table), z = try directionEntity(.unitZ, table: &table)
      let transform = try table.add("CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#\(x),#\(y),#\(point),1.,#\(z))")
      let item = try table.add("MAPPED_ITEM('',#\(map),#\(transform))")
      let outerItems = [item, geometry.origin] + placementItems
      representation = try table.add("\(geometry.representationType)('',(\(outerItems.map { "#\($0)" }.joined(separator: ","))),#\(outerContext))")
      geometryRepresentation = geometry.geometryRepresentation
      carrier = item
    } else {
      guard geometry.carrier == nil else { throw AssemblyError.invalidSource("Shared carrier group cannot flatten a definition scope.") }
      var representationItems: [Int] = []
      for body in geometry.bodies.keys.sorted() {
        try Task.checkCancellation()
        guard let items = geometry.bodies[body] else { throw AssemblyError.invalidSource("Missing shared geometry body items.") }
        representationItems.append(contentsOf: items)
      }
      representationItems.append(geometry.origin)
      representationItems.append(contentsOf: placementItems)
      representation = try table.add("\(geometry.representationType)('',(\(representationItems.map { "#\($0)" }.joined(separator: ","))),#\(outerContext))")
      geometryRepresentation = representation
      carrier = nil
    }
    _ = try table.add("SHAPE_DEFINITION_REPRESENTATION(#\(shape),#\(representation))")
    return WrittenDefinition(definition: definition, definitionShape: shape, representation: representation,
        context: geometry.context, origin: geometry.origin, geometryRepresentation: geometryRepresentation,
        carrier: carrier, representationType: geometry.representationType, bodies: geometry.bodies, faces: geometry.faces)
  }

  private func validatePlacementItems(_ items: [Int], table: EntityTable) throws {
    guard items.count <= table.maximumEntities else {
      throw exchangeError(.resourceLimitExceeded, "STEP placement support exceeds the configured entity limit.")
    }
    for item in items {
      try Task.checkCancellation()
      guard item > 0, item <= table.entities.count,
            (table.entities[item - 1].hasPrefix("AXIS2_PLACEMENT_3D(")
             || table.entities[item - 1].hasPrefix("CARTESIAN_TRANSFORMATION_OPERATOR_3D(")) else {
        throw ProductAttributeError.unsupportedSemantics("STEP placement support requires an actual 3D placement or Cartesian operator entity.")
      }
    }
  }

  private static let envelopePrefix = """
      ISO-10303-21;
      HEADER;
      FILE_DESCRIPTION(('SwiftCAD exact B-rep'),'2;1');
      FILE_NAME('swiftcad.step','2000-01-01T00:00:00',(''),(''),'swift-CAD','','');
      FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
      ENDSEC;
      DATA;

      """
  private static let envelopeSuffix = """

      ENDSEC;
      END-ISO-10303-21;
      """
  func publish(table: EntityTable, to sink: any ByteSink, framingIsPaid: Bool = false) throws {
    let framing = Self.envelopePrefix.utf8.count + Self.envelopeSuffix.utf8.count
    guard framing <= resourceLimits.maximumBytes,
          table.serializedByteCount <= resourceLimits.maximumBytes-framing else {
      throw exchangeError(.resourceLimitExceeded,"STEP output exceeds the configured byte limit.")
    }
    var usage = table.independentUsage
    if !framingIsPaid { try usage?.charge(work: table.serializedByteCount + framing, bytes: framing) }
    try usage?.check(); try table.processingBudget?.check(format: .step)
    let text = Self.envelopePrefix + table.serialized() + Self.envelopeSuffix
    try Task.checkCancellation()
    let data = Data(text.utf8)
    guard data.count <= resourceLimits.maximumBytes else {
      throw exchangeError(.resourceLimitExceeded, "STEP output exceeds the configured byte limit.")
    }
    try usage?.check(); try table.processingBudget?.check(format: .step)
    try data.withUnsafeBytes { bytes in
      try sink.write(bytes)
    }
  }

  struct WrittenGeometryContext {
    let units: UnitSystem
    let context: Int
    let origin: Int
  }

  struct WrittenGeometry {
    let items: [Int]
    let context: Int
    let origin: Int
    let representationType: String
    let bodies: [BodyID: [Int]]
    let faces: [FaceID: Int]
  }

  struct WrittenDefinition {
    let definition: Int
    let definitionShape: Int
    let representation: Int
    /// Canonical shared item context for attribute views, distinct from the outer placement context.
    let context: Int
    let origin: Int
    let geometryRepresentation: Int
    let carrier: Int?
    let representationType: String
    let bodies: [BodyID: [Int]]
    let faces: [FaceID: Int]
  }

  func assemblyAxis(_ frame: RigidTransform3D, units: LengthUnit, table: inout EntityTable) throws -> Int {
    try frame.validate(tolerance: tolerance)
    guard !frame.reversesOrientation else { throw AssemblyError.invalidPlacement }
    let point = try cartesianPoint(Point3D.origin + frame.translation, units: units, table: &table)
    let z = try directionEntity(frame.basisZ, table: &table)
    let x = try directionEntity(frame.basisX, table: &table)
    return try table.add("AXIS2_PLACEMENT_3D('',#\(point),#\(z),#\(x))")
  }

  private func originalSTEPElement(_ value: OriginalSTEPPlacementElement?, type: String, table: inout EntityTable) throws -> String {
    guard let value else { return "$" }
    try table.consumeExactWork(1)
    if let existing = table.originalPlacementElements[value.id] {
      guard existing.type == type, existing.source == value else {
        throw IndependentShapeExchangeError.invalidAssociation("Shared original placement element has conflicting source values.")
      }
      return "#" + String(existing.entity)
    }
    let point = value.coordinates
    let entity = try table.add("\(type)(\(table.quotedString(value.name)),(\(number(point.x)),\(number(point.y)),\(number(point.z))))")
    try table.visitExactCell(depth: 0)
    table.originalPlacementElements[value.id] = (type, value, entity)
    return "#" + String(entity)
  }

  private func originalSTEPLineEntity(_ source: OriginalSTEPLineSource, curve: Curve3D, name: String,
      table: inout EntityTable) throws -> Int {
    guard case .originalAffineWord(let image) = curve, case .line(let local) = image.source,
          local.origin == .origin, local.direction == .unitX else {
      throw IndependentShapeExchangeError.invalidAssociation("Original LINE is not bound to its retained word curve.")
    }
    let expected = try source.originalOperationWord(tolerance: tolerance,
      maximumDepth: table.maximumAlgebraicDepth, maximumSourceDepth: table.maximumSourceDepth, usage: &table)
    guard try image.operationWord.isEquivalent(to: expected, tolerance: tolerance,
      maximumDepth: table.maximumAlgebraicDepth, usage: &table) else {
      throw IndependentShapeExchangeError.invalidAssociation("Original LINE curve disagrees with its original VECTOR law.")
    }
    guard source.adjustments.isEmpty else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Translated original LINE source needs a legal original world-operation carrier in standard STEP.
      // Native retains raw records and ordered adjustments; do not round a transformed location into another original source record.
      throw ExchangePreservationError.unacceptedLoss(.init(losses: [.init(domain: .placement,
        reason: .unrepresentableSource, description: "Original LINE world adjustments require a standard source carrier.")]))
    }
    let location = try originalSTEPElement(source.location, type: "CARTESIAN_POINT", table: &table)
    let direction = try originalSTEPElement(source.direction, type: "DIRECTION", table: &table)
    let vector: Int
    if let old = table.originalLineVectors[source.vectorID] {
      guard old.source.direction == source.direction, old.source.magnitude == source.magnitude,
            old.source.vectorName.utf8.elementsEqual(source.vectorName.utf8) else {
        throw IndependentShapeExchangeError.invalidAssociation("Shared original VECTOR conflicts.")
      }
      vector = old.entity
    } else {
      vector = try table.add("VECTOR(\(table.quotedString(source.vectorName)),\(direction),\(number(source.magnitude)))")
      try table.visitExactCell(depth: 0); table.originalLineVectors[source.vectorID] = (source, vector)
    }
    return try table.add("LINE(\(table.quotedString(name)),\(location),#\(vector))")
  }

  func originalSTEPPlacementEntity(_ source: OriginalSTEPPlacementSource, derived: AffineTransform3D,
      name: String, units: LengthUnit, table: inout EntityTable) throws -> Int {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Adjusted original standard frames retain their
    // world operation sequence, but the neutral legal chain carrier is not authored.
    // This public STEP producer must retain that complete sequence before success.
    guard source.adjustments.isEmpty else {
      throw ExchangePreservationError.unacceptedLoss(.init(losses: [.init(domain: .placement,
          reason: .unrepresentableSource, description: "STEP source adjustments require their legal original operation-chain carrier.")]))
    }
    guard source.lengthUnit == units else {
      throw IndependentShapeExchangeError.metadataLoss("Original STEP placement model unit differs from its output context.")
    }
    let candidate = try source.derivedAffineTransform(tolerance: tolerance, maximumDepth: table.maximumAlgebraicDepth, maximumSourceDepth: table.maximumSourceDepth, usage: &table)
    guard candidate == derived else { throw IndependentShapeExchangeError.invalidAssociation("Original STEP placement witness differs from its derived frame.") }
    let quotedName = try table.quotedString(name)
    switch source {
    case .axis2(let value):
      let location = try originalSTEPElement(value.location, type: "CARTESIAN_POINT", table: &table)
      let axis = try originalSTEPElement(value.axis, type: "DIRECTION", table: &table)
      let reference = try originalSTEPElement(value.referenceDirection, type: "DIRECTION", table: &table)
      return try table.add("AXIS2_PLACEMENT_3D(\(quotedName),\(location),\(axis),\(reference))")
    case .cartesian(let value):
      let location = try originalSTEPElement(value.location, type: "CARTESIAN_POINT", table: &table)
      let x = try originalSTEPElement(value.axis1, type: "DIRECTION", table: &table)
      let y = try originalSTEPElement(value.axis2, type: "DIRECTION", table: &table)
      let z = try originalSTEPElement(value.axis3, type: "DIRECTION", table: &table)
      let scale = value.scale.map { number($0) } ?? "$"
      return try table.add("CARTESIAN_TRANSFORMATION_OPERATOR_3D(\(quotedName),*,*,\(x),\(y),\(location),\(scale),\(z))")
    }
  }

  func assemblyPlacementItem(_ placement: AssemblyPlacement, units: LengthUnit,
                             table: inout EntityTable) throws -> Int {
    switch placement {
    case .rigid(let frame): return try assemblyAxis(frame, units: units, table: &table)
    case .step(let source):
      let derived = try source.derivedAffineTransform(tolerance: tolerance, maximumDepth: table.maximumAlgebraicDepth, maximumSourceDepth: table.maximumSourceDepth, usage: &table)
      return try originalSTEPPlacementEntity(source, derived: derived, name: "", units: units, table: &table)
    case .affine(let frame):
      let scale = try IndependentProducer.orthogonal(frame, unitScale: false, table: &table)
      let point = try cartesianPoint(Point3D.origin + frame.translation, units: units, table: &table)
      let x = try directionEntity(frame.basisX, table: &table)
      let y = try directionEntity(frame.basisY, table: &table)
      let z = try directionEntity(frame.basisZ, table: &table)
      return try table.add("CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#\(x),#\(y),#\(point),\(number(scale)),#\(z))")
    // FIXME(INCOMPLETE_IMPLEMENTATION): The public assembly writer retains original
    // two-frame IDT words in its caller; an arbitrary word needs a legal standard
    // chain carrier before it can be published without flattening its source law.
    case .word:
      throw IndependentShapeExchangeError.metadataLoss("STEP placement items cannot flatten an original operation word.")
    }
  }

  func writeIndependentGeometry(_ model: IndependentSTEPGeometry, to sink: any ByteSink) throws {
    try resourceLimits.validate(); try tolerance.validate(); try model.units.validate()
    let budget = processingBudget
    try budget.check(format: .step)
    guard !model.curves.isEmpty || !model.surfaces.isEmpty else {
      throw exchangeError(.invalidInput, "Standalone STEP geometry cannot be empty.")
    }
    guard model.units.angle == .radian else {
      throw exchangeError(.unsupportedCapability, "Standalone STEP geometry requires a radian angular context.")
    }
    var table = EntityTable(maximumEntities: resourceLimits.maximumEntities, tolerance: tolerance,
      maximumBytes: resourceLimits.maximumBytes, maximumStringWork: resourceLimits.maximumIterations, maximumSourceDepth: resourceLimits.maximumNesting, maximumAlgebraicDepth: resourceLimits.maximumAlgebraicDepth, processingBudget: budget)
    let length = try lengthUnitEntity(model.units.length, table: &table)
    let angle = try table.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
    let context = try table.add("(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(length),#\(angle))) REPRESENTATION_CONTEXT('',''))")
    var curveSets: [Int] = [], surfaceSets: [Int] = []
    for item in model.curves {
      try budget.check(format: .step)
      try item.curve.validate(tolerance: tolerance)
      let name = try table.quotedString(item.name)
      let basis: Int
      var lengthParameters = false
      switch item.curve {
      case .line(let line):
        guard item.trim != nil else {
          throw exchangeError(.invalidInput, "An independent STEP line requires a finite directed trim.")
        }
        basis = try independentLineEntity(origin: line.origin, direction: line.direction, units: model.units.length, table: &table)
        lengthParameters = true
      case .analytic(.line(let origin, let direction)):
        guard item.trim != nil else {
          throw exchangeError(.invalidInput, "An independent STEP line requires a finite directed trim.")
        }
        basis = try independentLineEntity(origin: origin, direction: direction, name: "SWIFTCAD_ANALYTIC", units: model.units.length, table: &table)
        lengthParameters = true
      case .circle(let circle): basis = try circleEntity(circle, units: model.units.length, table: &table)
      case .bSpline(let curve): basis = try bSplineCurveEntity(curve, units: model.units.length, table: &table)
      case .analytic(let analytic):
        switch analytic {
        case .circle, .ellipse, .arc: basis = try independentAnalyticCurveEntity(analytic, units: model.units.length, table: &table)
        default:
          // FIXME(INCOMPLETE_IMPLEMENTATION): The independent public STEP path
          // does not yet transfer original hyperbola and parabola parameter laws.
          // Full X7 must preserve their exact bases and directed trims before admission.
          throw exchangeError(.unsupportedCapability, "Standalone STEP curve transfer currently supports lines, circles, ellipses, arcs and rational B-splines.")
        }
      default:
        // FIXME(INCOMPLETE_IMPLEMENTATION): The public independent STEP route
        // has no original implicit/lift/image chart transfer. Full X7 requires
        // these laws and their directed trims before extending this admission.
        throw exchangeError(.unsupportedCapability, "Standalone STEP curve transfer requires an exact supported primitive.")
      }
      let entity: Int
      if let trim = item.trim {
        guard trim.startParameter.isFinite, trim.endParameter.isFinite,
          trim.startParameter != trim.endParameter,
          try item.curve.parameterDomain.containsSpan(from: trim.startParameter, to: trim.endParameter, tolerance: tolerance) else {
          throw exchangeError(.invalidInput, "An independent curve trim must be finite, nonempty and contained in its source.")
        }
        let start = lengthParameters ? model.units.length.fromInternal(trim.startParameter) : trim.startParameter
        let end = lengthParameters ? model.units.length.fromInternal(trim.endParameter) : trim.endParameter
        guard start.isFinite, end.isFinite, start != end else {
          throw exchangeError(.resourceLimitExceeded, "Standalone STEP trim unit conversion lost its finite directed interval.")
        }
        entity = try table.add("TRIMMED_CURVE('',#\(basis),(PARAMETER_VALUE(\(number(start)))),(PARAMETER_VALUE(\(number(end)))),\(end > start ? ".T." : ".F."),.PARAMETER.)")
      } else { entity = basis }
      curveSets.append(try table.add("GEOMETRIC_CURVE_SET(\(name),(#\(entity)))"))
    }
    for item in model.surfaces {
      try budget.check(format: .step)
      switch item.surface {
      case .plane, .cylinder, .analytic, .bSpline: break
      case .procedural:
        // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone STEP currently transfers
        // original analytic and spline surfaces. The public independent path
        // must retain procedural chart laws with bounded source traversal
        // before admitting them as part of full X7.
        throw exchangeError(.unsupportedCapability, "Standalone STEP surface transfer requires an original analytic or rational B-spline surface.")
      }
      try item.surface.validate(tolerance: tolerance)
      let name = try table.quotedString(item.name)
      let entity = try exactSurfaceEntity(item.surface, units: model.units.length, table: &table)
      surfaceSets.append(try table.add("GEOMETRIC_SET(\(name),(#\(entity)))"))
    }
    if !curveSets.isEmpty {
      _ = try table.add("GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION('',(\(references(curveSets))),#\(context))")
    }
    if !surfaceSets.isEmpty {
      _ = try table.add("SHAPE_REPRESENTATION('SWIFTCAD_INDEPENDENT_SURFACES',(\(references(surfaceSets))),#\(context))")
    }
    let text = """
      ISO-10303-21;
      HEADER;
      FILE_DESCRIPTION(('SwiftCAD independent exact geometry'),'2;1');
      FILE_NAME('swiftcad.step','2000-01-01T00:00:00',(''),(''),'swift-CAD','','');
      FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
      ENDSEC;
      DATA;
      \(table.serialized())
      ENDSEC;
      END-ISO-10303-21;
      """
    try budget.check(format: .step)
    guard text.utf8.count <= resourceLimits.maximumBytes else {
      throw exchangeError(.resourceLimitExceeded, "Standalone STEP output exceeds its byte budget.")
    }
    // Validate complete output before the only mutation of the caller's sink.
    let facade = STEPExchange(tolerance: tolerance, resourceLimits: resourceLimits)
    try facade.validateIndependentSTEPOutput(text, budget: budget)
    let data = Data(text.utf8)
    try budget.check(format: .step)
    try data.withUnsafeBytes { try sink.write($0) }
  }

  private func independentLineEntity(origin: Point3D, direction: Vector3D, name: String = "",
                                     units: LengthUnit, table: inout EntityTable) throws -> Int {
    let point = try cartesianPoint(origin, units: units, table: &table)
    let direction = try directionEntity(direction, table: &table)
    let vector = try table.add("VECTOR('',#\(direction),1.)")
    return try table.add("LINE('\(name)',#\(point),#\(vector))")
  }

  private func independentAnalyticCurveEntity(_ curve: AnalyticCurve3D,
                                              units: LengthUnit, table: inout EntityTable) throws -> Int {
    switch curve {
    case .circle(let center, let normal, let radius):
      return try analyticCircleEntity(center: center, normal: normal, radius: radius,
        name: "SWIFTCAD_ANALYTIC", units: units, table: &table)
    case .ellipse(let center, let normal, let majorAxis, let majorRadius, let minorRadius):
      let placement = try axisPlacementEntity(origin: center, axis: normal, reference: majorAxis, units: units, table: &table)
      return try table.add("ELLIPSE('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(majorRadius))),\(number(units.fromInternal(minorRadius))))")
    case .arc(let center, let normal, let radius, let start, let end):
      let basis = try analyticCircleEntity(center: center, normal: normal, radius: radius,
        name: "SWIFTCAD_ARC_BASIS", units: units, table: &table)
      return try table.add("TRIMMED_CURVE('SWIFTCAD_ARC',#\(basis),(PARAMETER_VALUE(\(number(start)))),(PARAMETER_VALUE(\(number(end)))),.T.,.PARAMETER.)")
    default:
      throw exchangeError(.unsupportedCapability, "Standalone analytic STEP transfer requires a circle, ellipse or arc.")
    }
  }

  private func pcurveEntity(
    parameterCurve: SurfaceParameterCurve,
    parameterCurveFollowsModel: Bool,
    modelStart: Point3D,
    modelEnd: Point3D,
    surface: Surface3D,
    surfaceEntity: Int,
    units: LengthUnit,
    parameterContext: Int,
    table: inout EntityTable
  ) throws -> SurfaceCurveAssociation {
    let directedCurve =
      parameterCurveFollowsModel
      ? parameterCurve
      : try parameterCurve.reversed(tolerance: tolerance)
    let origin = try directedCurve.startParameter(tolerance: tolerance)
    let directionPoint = try directedCurve.endParameter(tolerance: tolerance)
    let surfaceStart = try surface.point(
      u: origin.u,
      v: origin.v,
      tolerance: tolerance
    )
    let surfaceEnd = try surface.point(
      u: directionPoint.u,
      v: directionPoint.v,
      tolerance: tolerance
    )
    guard
      surfaceStart.isApproximatelyEqual(
        to: modelStart,
        tolerance: tolerance.distance
      ),
      surfaceEnd.isApproximatelyEqual(
        to: modelEnd,
        tolerance: tolerance.distance
      )
    else {
      throw exchangeError(
        .topologyFailure,
        "STEP p-curve endpoints disagree with the model-curve direction."
      )
    }

    if try usesModelCurveOnly(directedCurve, on: surface) {
      return SurfaceCurveAssociation(entity: surfaceEntity, isPcurve: false)
    }

    let curveEntity = try parameterCurveEntity(
      directedCurve,
      surface: surface,
      units: units,
      table: &table
    )
    let representation = try table.add(
      "DEFINITIONAL_REPRESENTATION('',(#\(curveEntity)),#\(parameterContext))"
    )
    return SurfaceCurveAssociation(
      entity: try table.add("PCURVE('',#\(surfaceEntity),#\(representation))"),
      isPcurve: true
    )
  }

  private func parameterCurveEntity(
    _ curve: SurfaceParameterCurve,
    surface: Surface3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let origin = try curve.startParameter(tolerance: tolerance)
    let directionPoint = try curve.endParameter(tolerance: tolerance)
    switch curve {
    case .affine, .constantU, .constantV:
      return try parameterBSplineEntity(
        ExactPolylineBSplineBuilder(tolerance: tolerance).build(points: [
          origin,
          directionPoint,
        ]),
        surface: surface,
        units: units,
        table: &table
      )
    case .polyline(let points) where points.count == 2:
      return try parameterBSplineEntity(
        ExactPolylineBSplineBuilder(tolerance: tolerance).build(points: points),
        surface: surface,
        units: units,
        table: &table
      )
    case .polyline(let points):
      return try parameterBSplineEntity(
        ExactPolylineBSplineBuilder(tolerance: tolerance).build(points: points),
        surface: surface,
        units: units,
        table: &table
      )
    // FIXME(INCOMPLETE_IMPLEMENTATION): Exact hosted original-word pcurve publication needs a standard original-law carrier.
    // The Body writer must preserve the complete native directed chart and original support rather than publish a sampled substitute.
    case .originalAffineWord:
      throw exchangeError(.unsupportedCapability, "Hosted original-word pcurve requires faithful standard transport.")
    case .originalBSplineContinuation:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP p-curve extension still requires the original endpoint-span law producer in neutral representation.
      // Transfer must retain or certify the full directed continuation, rather than trimming the original spline inside its previous domain.
      throw exchangeError(.unsupportedCapability, "Original p-curve continuation requires a complete neutral curve-law transfer.")
    case .bSpline(let curve):
      return try parameterBSplineEntity(
        curve,
        surface: surface,
        units: units,
        table: &table
      )
    case .harmonic(let center, let cosine, let sine, _, _):
      return try parameterEllipseEntity(
        center: center,
        cosine: cosine,
        sine: sine,
        surface: surface,
        units: units,
        table: &table
      )
    case .projectedAnalytic(let projected):
      return try parameterBSplineEntity(
        try ExactProjectedAnalyticPcurveBSplineBuilder().build(
          projected,
          tolerance: tolerance
        ),
        surface: surface,
        units: units,
        table: &table
      )
    case .periodicTranslation(let base, let uShift, let vShift):
      let translated = SurfaceParameterCurve.periodicTranslation(
        base: base,
        uShift: uShift,
        vShift: vShift
      ).materializingPeriodicTranslation()
      if case .periodicTranslation = translated {
        throw exchangeError(
          .unsupportedCapability,
          "STEP cannot materialize this translated certificate-backed p-curve."
        )
      }
      return try parameterCurveEntity(
        translated,
        surface: surface,
        units: units,
        table: &table
      )
    case .offsetSurfaceImage(let image):
      try image.validate(on: surface, tolerance: tolerance)
      return try parameterCurveEntity(
        image.source,
        surface: surface,
        units: units,
        table: &table
      )
    case .originalImage(let image):
      try image.validate(on: surface, tolerance: tolerance)
      throw exchangeError(.topologyFailure,
        "STEP original-image p-curves must use their original model-curve surface association.")
    case .rigidImage:
      throw exchangeError(
        .topologyFailure,
        "STEP rigid-image p-curves must use their exact model-curve surface association."
      )
    case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
      .certifiedAnalyticPair:
      throw exchangeError(
        .unsupportedCapability,
        "STEP p-curve export requires an exact transferable line, polyline, ellipse, or rational B-spline."
      )
    }
  }

  private func usesModelCurveOnly(
    _ curve: SurfaceParameterCurve,
    on surface: Surface3D
  ) throws -> Bool {
    switch curve {
    case .projectedAnalytic(let projected):
      guard case .analytic(.cone) = surface else { return false }
      guard projected.surface == surface else {
        throw exchangeError(
          .topologyFailure,
          "STEP projected analytic p-curve support disagrees with its face surface."
        )
      }
      return true
    case .sphericalGreatCircle:
      guard case .analytic(.sphere) = surface else { return false }
      return true
    case .certifiedAnalyticPair(let certified):
      guard certified.intersection.surface(for: certified.role) == surface else {
        throw exchangeError(
          .topologyFailure,
          "STEP certified analytic-pair p-curve support disagrees with its face surface."
        )
      }
      return true
    case .certifiedImplicit(let certified):
      return surface
        == (certified.role == .first
          ? certified.intersection.firstSurface
          : certified.intersection.secondSurface)
    case .certifiedAnalyticImplicit(let certified):
      return surface == certified.intersection.analyticSurface
    case .originalImage(let image):
      try image.validate(on: surface, tolerance: tolerance)
      return true
    // FIXME(INCOMPLETE_IMPLEMENTATION): Hosted exact affine-word pcurves need a faithful standard support/parameter transport producer.
    // The STEP Body path must retain original word and native UV traversal rather than treating them as an empty association.
    case .originalAffineWord:
      throw exchangeError(.unsupportedCapability, "STEP hosted original-word pcurve transport requires its original producer.")
    case .rigidImage(let image):
      guard image.targetSurface == surface else {
        throw exchangeError(
          .topologyFailure,
          "STEP rigid-image p-curve support disagrees with its face surface."
        )
      }
      return true
    case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation:
      return false
    case .periodicTranslation(let base, _, _):
      return try usesModelCurveOnly(base, on: surface)
    case .offsetSurfaceImage(let image):
      try image.validate(on: surface, tolerance: tolerance)
      return try usesModelCurveOnly(
        image.source,
        on: image.sourceSurface
      )
    }
  }

  private func parameterEllipseEntity(
    center: Point2D,
    cosine: Point2D,
    sine: Point2D,
    surface: Surface3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let encodedCenter = ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x, v: center.y),
      on: surface,
      unit: units
    )
    let encodedCosinePoint = ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x + cosine.x, v: center.y + cosine.y),
      on: surface,
      unit: units
    )
    let encodedSinePoint = ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x + sine.x, v: center.y + sine.y),
      on: surface,
      unit: units
    )
    let ellipse = try STEPParameterEllipse(
      center: Point2D(x: encodedCenter.u, y: encodedCenter.v),
      cosine: Point2D(
        x: encodedCosinePoint.u - encodedCenter.u,
        y: encodedCosinePoint.v - encodedCenter.v
      ),
      sine: Point2D(
        x: encodedSinePoint.u - encodedCenter.u,
        y: encodedSinePoint.v - encodedCenter.v
      ),
      tolerance: ExactSurfaceParameterCodec.encodedTolerance(
        on: surface, unit: units, tolerance: tolerance)
    )
    let point = try table.add(
      "CARTESIAN_POINT('',(\(number(ellipse.center.x)),\(number(ellipse.center.y))))"
    )
    let direction = try table.add(
      "DIRECTION('',(\(number(ellipse.majorDirection.x)),\(number(ellipse.majorDirection.y))))"
    )
    let placement = try table.add("AXIS2_PLACEMENT_2D('',#\(point),#\(direction))")
    return try table.add(
      "ELLIPSE('SWIFTCAD_PCURVE',#\(placement),\(number(ellipse.majorRadius)),\(number(ellipse.minorRadius)))"
    )
  }

  private func parameterBSplineEntity(
    _ curve: BSplineCurve2D,
    surface: Surface3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    try curve.validate(tolerance: tolerance)
    var points: [Int] = []
    for point in curve.controlPoints {
      let encoded = ExactSurfaceParameterCodec.encode(
        SurfaceParameter(u: point.x, v: point.y),
        on: surface,
        unit: units
      )
      points.append(
        try table.add(
          "CARTESIAN_POINT('',(\(number(encoded.u)),\(number(encoded.v))))"
        ))
    }
    let knotData = compressedKnots(curve.knots)
    let entity =
      "(BOUNDED_CURVE() "
      + "B_SPLINE_CURVE(\(curve.degree),(\(references(points))),.UNSPECIFIED.,.F.,.F.) "
      + "B_SPLINE_CURVE_WITH_KNOTS((\(integers(knotData.multiplicities))),(\(numbers(knotData.values))),.UNSPECIFIED.) "
      + "CURVE() GEOMETRIC_REPRESENTATION_ITEM() "
      + "RATIONAL_B_SPLINE_CURVE((\(numbers(curve.weights)))) REPRESENTATION_ITEM('SWIFTCAD_PCURVE'))"
    return try table.add(entity)
  }

  private func cartesianPoint(
    _ point: Point3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    try table.add(
      "CARTESIAN_POINT('',(\(number(units.fromInternal(point.x))),\(number(units.fromInternal(point.y))),\(number(units.fromInternal(point.z)))))"
    )
  }

  private func directionEntity(
    _ vector: Vector3D,
    table: inout EntityTable
  ) throws -> Int {
    try table.add("DIRECTION('',(\(number(vector.x)),\(number(vector.y)),\(number(vector.z))))")
  }

  private func exactSurfaceEntity(
    _ surface: Surface3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    if !surfaceOverrides.isEmpty {
      try GeometryStructuralComparisonWork.charge(surface: surface) { try table.chargeGeometryWork($0) }
      if let converted = surfaceOverrides[surface] { return try bSplineSurfaceEntity(converted, units: units, table: &table) }
    }
    switch surface {
    case .plane(let plane):
      return try planeEntity(plane, units: units, table: &table)
    case .bSpline(let bSpline):
      return try bSplineSurfaceEntity(bSpline, units: units, table: &table)
    case .cylinder(let cylinder):
      return try cylinderEntity(cylinder, units: units, table: &table)
    case .analytic(let analytic):
      return try analyticSurfaceEntity(analytic, units: units, table: &table)
    case .procedural(.originalImage):
      return try independentAnalyticSurfaceEntity(surface,name:"",units:UnitSystem(length:units,angle:.radian),positionEntityID:nil,table:&table)
    case .procedural(.offset(let offset)):
      let basis = try exactSurfaceEntity(
        offset.source,
        units: units,
        table: &table
      )
      return try table.add(
        "OFFSET_SURFACE('SWIFTCAD_OFFSET',#\(basis),\(number(units.fromInternal(offset.distance))),.U.)"
      )
    case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalAffineWord), .procedural(.originalAngularTransport), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
      let representation = try ExactExchangeSurfaceRepresentationResolver()
        .resolve(surface, tolerance: tolerance)
      guard representation != surface else {
        throw exchangeError(
          .topologyFailure,
          "STEP procedural surface resolution made no progress."
        )
      }
      return try exactSurfaceEntity(
        representation,
        units: units,
        table: &table
      )
    }
  }

  private func planeEntity(
    _ plane: Plane3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let origin = try cartesianPoint(plane.origin, units: units, table: &table)
    let normal = try directionEntity(plane.normal, table: &table)
    let surface = Surface3D.plane(plane)
    let frame = try surface.differentialGeometry(
      u: 0.0,
      v: 0.0,
      tolerance: tolerance
    )
    let reference = try directionEntity(frame.tangentU, table: &table)
    let placement = try table.add("AXIS2_PLACEMENT_3D('',#\(origin),#\(normal),#\(reference))")
    return try table.add("PLANE('',#\(placement))")
  }

  private func cylinderEntity(
    _ cylinder: Cylinder3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let reference = try ExactAnalyticFrame.directBasis(for: cylinder.axis, tolerance: tolerance).u
    let placement = try axisPlacementEntity(
      origin: cylinder.origin,
      axis: cylinder.axis,
      reference: reference,
      units: units,
      table: &table
    )
    return try table.add(
      "CYLINDRICAL_SURFACE('',#\(placement),\(number(units.fromInternal(cylinder.radius))))"
    )
  }

  private func analyticSurfaceEntity(
    _ surface: AnalyticSurface3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let name = "'SWIFTCAD_ANALYTIC'"
    switch surface {
    case .plane(let origin, let normal):
      let reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
      let placement = try axisPlacementEntity(
        origin: origin,
        axis: normal,
        reference: reference,
        units: units,
        table: &table
      )
      return try table.add("PLANE(\(name),#\(placement))")
    case .cylinder(let origin, let axis, let radius):
      let reference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
      let placement = try axisPlacementEntity(
        origin: origin,
        axis: axis,
        reference: reference,
        units: units,
        table: &table
      )
      return try table.add(
        "CYLINDRICAL_SURFACE(\(name),#\(placement),\(number(units.fromInternal(radius))))"
      )
    case .cone(let apex, let axis, let halfAngle):
      let reference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
      let placement = try axisPlacementEntity(
        origin: apex,
        axis: axis,
        reference: reference,
        units: units,
        table: &table
      )
      return try table.add(
        "CONICAL_SURFACE(\(name),#\(placement),0.,\(number(halfAngle)))"
      )
    case .sphere(let center, let radius):
      let frame = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance)
      let placement = try axisPlacementEntity(
        origin: center,
        axis: .unitZ,
        reference: frame.u,
        units: units,
        table: &table
      )
      return try table.add(
        "SPHERICAL_SURFACE(\(name),#\(placement),\(number(units.fromInternal(radius))))"
      )
    case .torus(let center, let axis, let majorRadius, let minorRadius):
      let reference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
      let placement = try axisPlacementEntity(
        origin: center,
        axis: axis,
        reference: reference,
        units: units,
        table: &table
      )
      return try table.add(
        "TOROIDAL_SURFACE(\(name),#\(placement),\(number(units.fromInternal(majorRadius))),\(number(units.fromInternal(minorRadius))))"
      )
    }
  }

  private func circleEntity(
    _ circle: Circle3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let reference = try ExactAnalyticFrame.directBasis(for: circle.normal, tolerance: tolerance).u
    let placement = try axisPlacementEntity(
      origin: circle.center,
      axis: circle.normal,
      reference: reference,
      units: units,
      table: &table
    )
    return try table.add(
      "CIRCLE('',#\(placement),\(number(units.fromInternal(circle.radius))))"
    )
  }

  private func analyticCurveEntity(
    _ curve: AnalyticCurve3D,
    edge: Edge,
    startPoint: Point3D,
    endPoint: Point3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> (entity: Int, sameSense: Bool) {
    switch curve {
    case .line(let origin, let direction):
      let point = try cartesianPoint(origin, units: units, table: &table)
      let directionEntity = try self.directionEntity(direction, table: &table)
      let vector = try table.add("VECTOR('',#\(directionEntity),1.)")
      let signedSpan = (endPoint - startPoint).dot(direction)
      guard abs(signedSpan) > tolerance.distance else {
        throw exchangeError(
          .topologyFailure, "STEP analytic line direction is inconsistent with its edge.")
      }
      return (
        try table.add("LINE('SWIFTCAD_ANALYTIC',#\(point),#\(vector))"),
        signedSpan > 0.0
      )
    case .circle(let center, let normal, let radius):
      let trim = try requiredPeriodicTrim(edge, label: "analytic circle")
      let entity = try analyticCircleEntity(
        center: center,
        normal: normal,
        radius: radius,
        name: "SWIFTCAD_ANALYTIC",
        units: units,
        table: &table
      )
      return (entity, trim.endParameter > trim.startParameter)
    case .arc(let center, let normal, let radius, _, _):
      guard let trim = edge.trim else {
        throw exchangeError(
          .topologyFailure,
          "STEP analytic arc requires a finite explicit trim interval."
        )
      }
      let basis = try analyticCircleEntity(
        center: center,
        normal: normal,
        radius: radius,
        name: "SWIFTCAD_ARC_BASIS",
        units: units,
        table: &table
      )
      let sameSense = trim.endParameter > trim.startParameter
      let entity = try table.add(
        "TRIMMED_CURVE('SWIFTCAD_ARC',#\(basis),(PARAMETER_VALUE(\(number(trim.startParameter)))),(PARAMETER_VALUE(\(number(trim.endParameter)))),\(sameSense ? ".T." : ".F."),.PARAMETER.)"
      )
      return (entity, true)
    case .ellipse(let center, let normal, let majorAxis, let majorRadius, let minorRadius):
      let trim = try requiredPeriodicTrim(edge, label: "analytic ellipse")
      let placement = try axisPlacementEntity(
        origin: center,
        axis: normal,
        reference: majorAxis,
        units: units,
        table: &table
      )
      let entity = try table.add(
        "ELLIPSE('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(majorRadius))),\(number(units.fromInternal(minorRadius))))"
      )
      return (entity, trim.endParameter > trim.startParameter)
    case .hyperbola(let curve):
      guard let trim = edge.trim,
        trim.startParameter.isFinite,
        trim.endParameter.isFinite,
        abs(trim.endParameter - trim.startParameter) > tolerance.relative
      else {
        throw exchangeError(
          .topologyFailure,
          "STEP hyperbola edges require a finite nonzero trim."
        )
      }
      let placement = try axisPlacementEntity(
        origin: curve.center,
        axis: curve.normal,
        reference: curve.transverseAxis,
        units: units,
        table: &table
      )
      let entity = try table.add(
        "HYPERBOLA('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(curve.transverseRadius))),\(number(units.fromInternal(curve.conjugateRadius))))"
      )
      return (entity, trim.endParameter > trim.startParameter)
    case .parabola(let curve):
      guard let trim = edge.trim,
        trim.startParameter.isFinite,
        trim.endParameter.isFinite,
        abs(trim.endParameter - trim.startParameter) > tolerance.distance
      else {
        throw exchangeError(
          .topologyFailure,
          "STEP parabola edges require a finite nonzero trim."
        )
      }
      let placement = try axisPlacementEntity(
        origin: curve.vertex,
        axis: curve.normal,
        reference: curve.axis,
        units: units,
        table: &table
      )
      let entity = try table.add(
        "PARABOLA('SWIFTCAD_ANALYTIC',#\(placement),\(number(units.fromInternal(curve.focalLength))))"
      )
      return (entity, trim.endParameter > trim.startParameter)
    case .planeTorus:
      throw exchangeError(
        .unsupportedCapability,
        "STEP certified plane-torus transfer requires an exact surface-curve association writer."
      )
    }
  }

  private func analyticCircleEntity(
    center: Point3D,
    normal: Vector3D,
    radius: Double,
    name: String,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let reference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
    let placement = try axisPlacementEntity(
      origin: center,
      axis: normal,
      reference: reference,
      units: units,
      table: &table
    )
    return try table.add(
      "CIRCLE('\(name)',#\(placement),\(number(units.fromInternal(radius))))"
    )
  }

  private func requiredPeriodicTrim(_ edge: Edge, label: String) throws -> CurveTrim {
    guard let trim = edge.trim,
      trim.startParameter.isFinite,
      trim.endParameter.isFinite,
      abs(trim.endParameter - trim.startParameter) > tolerance.angle,
      abs(trim.endParameter - trim.startParameter)
        < 2.0 * Double.pi - tolerance.angle
    else {
      throw exchangeError(
        .topologyFailure,
        "STEP \(label) edge requires a finite trim shorter than one period."
      )
    }
    return trim
  }

  private func axisPlacementEntity(
    origin: Point3D,
    axis: Vector3D,
    reference: Vector3D,
    units: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    let point = try cartesianPoint(origin, units: units, table: &table)
    let axisEntity = try directionEntity(axis, table: &table)
    let referenceEntity = try directionEntity(reference, table: &table)
    return try table.add(
      "AXIS2_PLACEMENT_3D('',#\(point),#\(axisEntity),#\(referenceEntity))"
    )
  }

  private func bSplineCurveEntity(
    _ curve: BSplineCurve3D,
    name: String = "",
    units: LengthUnit,
    originalSource: OriginalSTEPSplineCurveSource? = nil,
    table: inout EntityTable
  ) throws -> Int {
    try admitSplineArray(curve.controlPoints.count, of: Int.self, table: &table)
    if let originalSource, originalSource.controlPoints.count != curve.controlPoints.count {
      throw IndependentShapeExchangeError.invalidAssociation("Original spline control count differs from its geometry law.")
    }
    var points: [Int] = []
    points.reserveCapacity(curve.controlPoints.count)
    for index in curve.controlPoints.indices {
      let point = curve.controlPoints[index]
      if let originalSource {
        let original = originalSource.controlPoints[index]
        guard original.coordinates == Vector3D(x: point.x, y: point.y, z: point.z),
              originalSource.isRational || curve.weights[index] == 1 else {
          throw IndependentShapeExchangeError.invalidAssociation("Original spline control or rational assertion conflicts.")
        }
        let reference = try originalSTEPElement(original, type: "CARTESIAN_POINT", table: &table)
        guard let entity = Int(reference.dropFirst()) else { throw IndependentShapeExchangeError.invalidAssociation("Original spline point publication is not an entity reference.") }
        points.append(entity)
      } else { points.append(try cartesianPoint(point, units: units, table: &table)) }
    }
    try admitSplineArray(curve.knots.count, of: Double.self, table: &table)
    try admitSplineArray(curve.knots.count, of: Int.self, table: &table)
    let knotData = compressedKnots(curve.knots)
    let form = originalSource?.curveForm.stepToken ?? ".UNSPECIFIED."
    let closed = originalSource?.closed.stepToken ?? ".F.", intersects = originalSource?.selfIntersect.stepToken ?? ".F."
    let knotSpecification = originalSource?.knotSpecification.stepToken ?? ".UNSPECIFIED."
    let rational = originalSource?.isRational ?? true
    let rationalComponent = rational ? "RATIONAL_B_SPLINE_CURVE((\(numbers(curve.weights)))) " : ""
    let entity =
      "(BOUNDED_CURVE() "
      + "B_SPLINE_CURVE(\(curve.degree),(\(references(points))),\(form),\(closed),\(intersects)) "
      + "B_SPLINE_CURVE_WITH_KNOTS((\(integers(knotData.multiplicities))),(\(numbers(knotData.values))),\(knotSpecification)) "
      + "CURVE() GEOMETRIC_REPRESENTATION_ITEM() "
      + rationalComponent + "REPRESENTATION_ITEM(\(try table.quotedString(name))))"
    return try table.add(entity)
  }

  private func bSplineSurfaceEntity(
    _ surface: BSplineSurface3D,
    name: String = "",
    units: LengthUnit,
    originalSource: OriginalSTEPSplineSurfaceSource? = nil,
    table: inout EntityTable
  ) throws -> Int {
    if let originalSource, originalSource.controlPointRows.count != surface.vControlPointCount {
      throw IndependentShapeExchangeError.invalidAssociation("Original spline support control rows disagree.")
    }
    try admitSplineArray(surface.uControlPointCount, of: [Int].self, table: &table)
    var pointRows: [[Int]] = []
    pointRows.reserveCapacity(surface.uControlPointCount)
    // STEP stores [u][v]; the original native surface stores [v][u].
    for u in 0..<surface.uControlPointCount {
      try admitSplineArray(surface.vControlPointCount, of: Int.self, table: &table)
      var pointRow: [Int] = []
      pointRow.reserveCapacity(surface.vControlPointCount)
      for v in 0..<surface.vControlPointCount {
        let point = surface.controlPoints[v][u]
        if let originalSource {
          guard originalSource.controlPointRows[v].count == surface.uControlPointCount else {
            throw IndependentShapeExchangeError.invalidAssociation("Original spline support controls are nonrectangular.")
          }
          let original = originalSource.controlPointRows[v][u]
          guard original.coordinates == Vector3D(x: point.x, y: point.y, z: point.z),
                originalSource.isRational || surface.weights[v][u] == 1 else {
            throw IndependentShapeExchangeError.invalidAssociation("Original spline support control or rational assertion conflicts.")
          }
          let reference = try originalSTEPElement(original, type: "CARTESIAN_POINT", table: &table)
          guard let entity = Int(reference.dropFirst()) else { throw IndependentShapeExchangeError.invalidAssociation("Original spline support point is not an entity reference.") }
          pointRow.append(entity)
        } else { pointRow.append(try cartesianPoint(point, units: units, table: &table)) }
      }
      pointRows.append(pointRow)
    }
    for count in [surface.uKnots.count, surface.vKnots.count] {
      try admitSplineArray(count, of: Double.self, table: &table)
      try admitSplineArray(count, of: Int.self, table: &table)
    }
    let uKnots = compressedKnots(surface.uKnots)
    let vKnots = compressedKnots(surface.vKnots)
    let controlNet = pointRows.map { "(\(references($0)))" }.joined(separator: ",")
    try admitSplineArray(surface.uControlPointCount, of: String.self, table: &table)
    var weightRows: [String] = []
    for u in 0..<surface.uControlPointCount {
      try admitSplineArray(surface.vControlPointCount, of: Double.self, table: &table)
      var row: [Double] = []
      for v in 0..<surface.vControlPointCount { row.append(surface.weights[v][u]) }
      weightRows.append("(\(numbers(row)))")
    }
    let weightNet = weightRows.joined(separator: ",")
    let form = originalSource?.surfaceForm.stepToken ?? ".UNSPECIFIED."
    let uClosed = originalSource?.uClosed.stepToken ?? ".F.", vClosed = originalSource?.vClosed.stepToken ?? ".F."
    let intersects = originalSource?.selfIntersect.stepToken ?? ".F."
    let knotSpecification = originalSource?.knotSpecification.stepToken ?? ".UNSPECIFIED."
    let rationalComponent = (originalSource?.isRational ?? true) ? "RATIONAL_B_SPLINE_SURFACE((\(weightNet))) " : ""
    let entity =
      "(BOUNDED_SURFACE() "
      + "B_SPLINE_SURFACE(\(surface.uDegree),\(surface.vDegree),(\(controlNet)),\(form),\(uClosed),\(vClosed),\(intersects)) "
      + "B_SPLINE_SURFACE_WITH_KNOTS((\(integers(uKnots.multiplicities))),(\(integers(vKnots.multiplicities))),(\(numbers(uKnots.values))),(\(numbers(vKnots.values))),\(knotSpecification)) "
      + "GEOMETRIC_REPRESENTATION_ITEM() "
      + rationalComponent + "REPRESENTATION_ITEM(\(try table.quotedString(name))) SURFACE())"
    return try table.add(entity)
  }

  private func admitSplineArray<Value>(_ count: Int, of type: Value.Type, table: inout EntityTable) throws {
    let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Value>.stride)
    guard count >= 0, !bytes.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Spline publication retained storage overflow.") }
    let stride = MemoryLayout<UInt32>.stride
    try table.retainExactStorage(bytes.partialValue / stride + (bytes.partialValue % stride == 0 ? 0 : 1))
    try table.chargeGeometryWork(count)
  }

  private func compressedKnots(_ knots: [Double]) -> (values: [Double], multiplicities: [Int]) {
    var values: [Double] = []
    var multiplicities: [Int] = []
    for knot in knots {
      if let last = values.last, last == knot {
        multiplicities[multiplicities.count - 1] += 1
      } else {
        values.append(knot)
        multiplicities.append(1)
      }
    }
    return (values, multiplicities)
  }

  private func references(_ values: [Int]) -> String {
    values.map { "#\($0)" }.joined(separator: ",")
  }

  private func integers(_ values: [Int]) -> String {
    values.map(String.init).joined(separator: ",")
  }

  private func numbers(_ values: [Double]) -> String {
    values.map(number).joined(separator: ",")
  }

  private func lengthUnitEntity(
    _ unit: LengthUnit,
    table: inout EntityTable
  ) throws -> Int {
    switch unit {
    case .micrometer:
      return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MICRO.,.METRE.))")
    case .meter:
      return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
    case .millimeter:
      return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))")
    case .centimeter:
      return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.CENTI.,.METRE.))")
    case .kilometer:
      return try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.METRE.))")
    case .inch, .foot:
      let dimensions = try table.add("DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.)")
      let metre = try table.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
      let measure = try table.add(
        "LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(number(unit.metersPerUnit))),#\(metre))"
      )
      let name = unit == .inch ? "INCH" : "FOOT"
      return try table.add(
        "(CONVERSION_BASED_UNIT('\(name)',#\(measure)) LENGTH_UNIT() NAMED_UNIT(#\(dimensions)))"
      )
    }
  }

  private func number(_ value: Double) -> String {
    String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private func exchangeError(_ code: KernelErrorCode, _ message: String) -> KernelError {
    KernelError(phase: .exchange, code: code, tolerance: tolerance, message: message)
  }

  private struct SurfaceCurveAssociation: Hashable {
    let entity: Int
    let isPcurve: Bool
  }

  struct EntityTable: Sendable, RationalAlgebraAdmitting {
    let maximumEntities: Int
    let tolerance: ModelingTolerance
    let processingBudget: ExchangeProcessingBudget?
    var entities: [String] = []
    var maximumBytes: Int = 64 * 1024 * 1024
    private var byteCount: Int = 0
    private var stringWork = 0
    private var stringBytes = 0
    private var exactCells = 0
    private var exactStorageBytes = 0
    let maximumStringWork: Int
    let maximumSourceDepth: Int
    let maximumAlgebraicDepth: Int
    var originalLineVectors: [PortableIdentity128: (source: OriginalSTEPLineSource, entity: Int)] = [:]
    var originalPlacementElements: [PortableIdentity128: (type: String, source: OriginalSTEPPlacementElement, entity: Int)] = [:]
    var independentUsage: IndependentShapeExchangeUsage?
    var serializedByteCount: Int { byteCount }

    init(maximumEntities: Int, tolerance: ModelingTolerance, maximumBytes: Int = 64 * 1024 * 1024, maximumStringWork: Int = 10_000_000, maximumSourceDepth: Int = ExchangeResourceLimits.standard.maximumNesting, maximumAlgebraicDepth: Int = ExchangeResourceLimits.standard.maximumAlgebraicDepth, processingBudget: ExchangeProcessingBudget? = nil) {
      self.maximumEntities = maximumEntities
      self.tolerance = tolerance
      self.maximumBytes = maximumBytes
      self.maximumStringWork = maximumStringWork
      self.maximumSourceDepth = maximumSourceDepth; self.maximumAlgebraicDepth = maximumAlgebraicDepth
      self.processingBudget = processingBudget
    }

    mutating func visitSourceCell(depth: Int) throws {
      let ceiling = independentUsage?.limits.maximumNesting ?? maximumSourceDepth
      guard depth >= 0, depth <= ceiling else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original STEP source nesting allowance.") }
      try visitExactCell(depth: 0)
    }
    mutating func visitExactCell(depth: Int) throws {
      try processingBudget?.check(format: .step)
      try Task.checkCancellation()
      let maximumDepth = independentUsage?.limits.maximumAlgebraicDepth ?? maximumAlgebraicDepth
      guard depth >= 0, depth <= maximumDepth, exactCells < maximumEntities - entities.count else {
        throw IndependentShapeExchangeError.resourceLimitExceeded("Original STEP algebra cell/depth allowance.")
      }
      exactCells += 1
      if independentUsage != nil { try independentUsage!.visitExactCell(depth: depth) }
      else { try chargeGeometryWork(1) }
    }
    mutating func consumeExactWork(_ count: Int) throws {
      try processingBudget?.check(format: .step)
      try Task.checkCancellation()
      try chargeGeometryWork(count)
    }
    mutating func retainExactStorage(_ count: Int) throws {
      let size = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
      guard count >= 0, !size.overflow, size.partialValue <= maximumBytes - byteCount - exactStorageBytes else {
        throw IndependentShapeExchangeError.resourceLimitExceeded("Original STEP rational storage allowance.")
      }
      try independentUsage?.retainExactStorage(count)
      exactStorageBytes += size.partialValue
    }
    mutating func chargeGeometryWork(_ work: Int) throws {
      guard work >= 0, work <= maximumStringWork - stringWork else { throw IndependentShapeExchangeError.resourceLimitExceeded("Converted STEP geometry lookup work.") }
      stringWork += work; try independentUsage?.charge(work: work)
    }
    mutating func quotedString(_ value: String) throws -> String {
      let result = try STEPStringCodec().encode(value, limits: STEPStringLimits(
        maximumInputBytes: maximumBytes,
        maximumOutputBytes: min(min(maximumBytes - byteCount - exactStorageBytes, maximumBytes - stringBytes),
            independentUsage.map { $0.limits.maximumBytes-$0.consumedBytes } ?? maximumBytes),
        maximumWork: min(maximumStringWork - stringWork,
            independentUsage.map { $0.limits.maximumIterations-$0.consumedWork } ?? maximumStringWork)))
      stringWork += result.consumedWork; stringBytes += result.outputBytes
      try independentUsage?.charge(work:result.consumedWork)
      return result.value
    }

    mutating func add(_ entity: String) throws -> Int {
      if let processingBudget { try processingBudget.check(format: .step) }
      try Task.checkCancellation()
      guard entities.count < maximumEntities - exactCells else {
        throw KernelError(
          phase: .exchange,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "STEP output exceeds the configured entity limit."
        )
      }
      let bytes = entity.utf8.count
      // Reserve the entity marker, decimal identifier, separator, terminator, and line break.
      let framing = String(entities.count + 1).utf8.count + 3 + (entities.isEmpty ? 0 : 1)
      guard framing <= maximumBytes - byteCount - exactStorageBytes, bytes <= maximumBytes - byteCount - exactStorageBytes - framing else {
        throw KernelError(phase: .exchange, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "STEP entity table exceeds the configured byte limit.")
      }
      try chargeGeometryWork(bytes + framing)
      byteCount += bytes + framing
      try independentUsage?.charge(entities:1,bytes:bytes+framing)
      entities.append(entity)
      return entities.count
    }

    func serialized() -> String {
      entities.enumerated().map { index, entity in
        "#\(index + 1)=\(entity);"
      }.joined(separator: "\n")
    }
  }
}
