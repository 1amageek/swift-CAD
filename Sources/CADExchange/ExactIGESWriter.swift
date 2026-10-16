import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation

struct ExactIGESWriter: Sendable {
  let resourceLimits: ExchangeResourceLimits
  let tolerance: ModelingTolerance
  let surfaceOverrides: [Surface3D: BSplineSurface3D]
  let curveConversions: ExchangeCurveConversionPlan
  let processingBudget: ExchangeProcessingBudget
  let allowsReportedPlacementProjection: Bool
  let allowsReportedGroupProjection: Bool
  init(resourceLimits: ExchangeResourceLimits, tolerance: ModelingTolerance, surfaceOverrides: [Surface3D: BSplineSurface3D] = [:], curveConversions: ExchangeCurveConversionPlan = .init(), processingBudget: ExchangeProcessingBudget? = nil, allowsReportedPlacementProjection: Bool = false, allowsReportedGroupProjection: Bool = false) {
    self.resourceLimits = resourceLimits; self.tolerance = tolerance; self.surfaceOverrides = surfaceOverrides; self.curveConversions = curveConversions
    self.allowsReportedPlacementProjection = allowsReportedPlacementProjection; self.allowsReportedGroupProjection = allowsReportedGroupProjection
    self.processingBudget = processingBudget ?? ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
  }

  private func requireCertifiedBodySurfaceIncidence(_ brep: BRepModel) throws {
    guard !curveConversions.edges.isEmpty || !surfaceOverrides.isEmpty else { return }
    for (faceID, face) in brep.faces {
      try processingBudget.check(format: .iges)
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
            receipts.contains(where: { receipt in
              guard receipt.faceID == faceID, receipt.loopID == loopID,
                receipt.coedgeOrdinal == ordinal else { return false }
              guard receipt.hostedSurface == hostedSurface else { return false }
              return receipt.parameterCurve == pcurve
            }) else {
            throw IndependentShapeExchangeError.invalidAssociation("Converted Body boundary lacks its final emitted face/curve joint certificate.")
          }
        }
      }
    }
  }

  func writeIndependent(_ source:IndependentShapeSource,units:UnitSystem,to sink:any ByteSink) throws {
    var usage = try IndependentShapeExchangeOwner(limits:resourceLimits,format:.iges,processing:processingBudget,consumedEntities:0,consumedWork:0,consumedBytes:0)
    var execution = try usage.execution()
    try writeIndependent(source,units:units,to:sink,usage:usage, using: &execution)
  }
  func writeIndependent(_ source:IndependentShapeSource,units:UnitSystem,to sink:any ByteSink,
                        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws {
    var producer:any IndependentIGESGeometryWriting = try IndependentProducer(writer:self, using: execution)
    let data = try DefaultIndependentIGESGraphWriter(allowsReportedPlacementProjection: allowsReportedPlacementProjection, allowsReportedGroupProjection: allowsReportedGroupProjection).write(source,units:units,tolerance:tolerance,producer:&producer,usage:usage, using: &execution)
    try usage.check(); try data.withUnsafeBytes { try sink.write($0) }
  }
  private struct IndependentProducer: IndependentIGESGeometryWriting {
    let writer:ExactIGESWriter
    var table:EntityTable
    var curves:[IndependentShapeItemID:Int] = [:]
    var surfaces:[SurfaceID:Int] = [:]
    var originalFrames: [IndependentShapeFrameID: Int] = [:]
    var originalFrameNames: [IndependentShapeFrameID: String] = [:]
    init(writer: ExactIGESWriter, using execution: borrowing OriginalQueryExecution) throws {
      self.writer = writer; table = try .init(maximumEntities:writer.resourceLimits.maximumEntities,tolerance:writer.tolerance,maximumWork:writer.resourceLimits.maximumIterations,processingBudget:writer.processingBudget, originalBudget: execution.budget, limits: writer.resourceLimits)
    }
    mutating func curve(_ item:IndependentShapeItem,source:IndependentShapeSource,units:UnitSystem,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
      table.independentUsage = usage
      let selection = try item.resolvedCurve(in: source.geometry)
      var curve = selection.curve
      let trim = selection.trim
      let transformation: Int
      if case .curve(let curveID, _) = item.geometry, let association = source.curvePositionFrames[curveID] {
        // FIXME(INCOMPLETE_IMPLEMENTATION): A converted world-space curve does not retain its original directory-matrix source association.
        // Public conversion must certify an original local candidate or report that specific source loss before publication.
        guard writer.curveConversions.items[item.id] == nil else { throw IndependentShapeExchangeError.metadataLoss("Converted IGES curve requires original local directory-matrix transport.") }
        guard case .originalAffineWord(let image) = curve else { throw IndependentShapeExchangeError.invalidAssociation("Original IGES curve pose has no retained word image.") }
        var poseUsage = table.independentUsage!
        transformation = try originalPose(association, word: image.operationWord, unit: units.length, usage: poseUsage, using: &execution)
        table.independentUsage = poseUsage
        curve = image.source
      } else { transformation = 0 }
      if let cached = curves[item.id] { return cached }
      if let converted = writer.curveConversions.items[item.id] {
        let start: Double, end: Double
        if let trim { start = trim.startParameter; end = trim.endParameter }
        else if case .closed(let a, let b) = curve.parameterDomain { start = a; end = b }
        else { throw IndependentShapeExchangeError.invalidAssociation("Converted independent selection lost its finite original domain.") }
        let entity = try table.add(type: 126, form: 0, label: item.name,
          parameters: writer.bSplineCurveParameters(converted, startParameter: start, endParameter: end, unit: units.length), using: &execution)
        try execution.chargeSource(records: 1, work: 1)
        curves[item.id] = entity
        return entity
      }
      try GeometryStructuralComparisonWork.charge(curve:curve, using: &execution)
      let entity:Int
      if case .bSpline(let spline) = curve {
        guard let trim else { throw IndependentShapeExchangeError.invalidAssociation("An IGES126 selection needs its finite original trim.") }
        entity = try table.add(type:126,form:0,label:item.name,transformationPointer:transformation,parameters:writer.bSplineCurveParameters(spline,
            startParameter:trim.startParameter,endParameter:trim.endParameter,unit:units.length), using: &execution)
      } else if curve.exactLinearLocus != nil {
        // Type110 has the original endpoint-affine parameter law [0,1], not a free parameter remapping.
        guard let trim, trim.startParameter == 0, trim.endParameter == 1 else {
          throw IndependentShapeExchangeError.metadataLoss("IGES110 cannot retain this original line parameter chart/trim.")
        }
        let a = try curve.point(at:0,tolerance:writer.tolerance), b = try curve.point(at:1,tolerance:writer.tolerance)
        entity = try table.add(type:110,form:0,label:item.name,transformationPointer:transformation,parameters:writer.lineParameters(start:a,end:b,unit:units.length), using: &execution)
      } else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Independent IGES egress has not composed every original conic/procedural parameter producer.
        // Retain original chart, labels and shared law identities before these public curve families may count toward full X7.
        throw IndependentShapeExchangeError.unsupportedSemantics("Independent IGES curve family is not implemented.")
      }
      try execution.chargeSource(records:1,work:1); curves[item.id] = entity
      return entity
    }
    mutating func surface(_ item:IndependentShapeItem,source:IndependentShapeSource,units:UnitSystem,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
      table.independentUsage = usage
      guard case .surface(let id) = item.geometry, let originalSurface = source.geometry.surfaces[id] else { throw IndependentShapeExchangeError.invalidAssociation("Missing original IGES surface.") }
      if let cached = surfaces[id] { return cached }
      var surface = originalSurface
      let transformation: Int
      if let association = source.surfacePositionFrames[id] {
        // FIXME(INCOMPLETE_IMPLEMENTATION): A world-space surface candidate cannot silently discard the original directory transform.
        // Certify its local chart or explicitly report this source association loss before converted publication.
        guard writer.surfaceOverrides[originalSurface] == nil else { throw IndependentShapeExchangeError.metadataLoss("Converted IGES surface requires its original local matrix transport.") }
        guard case .procedural(.originalAffineWord(let image)) = originalSurface else { throw IndependentShapeExchangeError.invalidAssociation("Original IGES surface pose has no retained word image.") }
        var poseUsage = table.independentUsage!
        transformation = try originalPose(association, word: image.operationWord, unit: units.length, usage: poseUsage, using: &execution)
        table.independentUsage = poseUsage
        surface = image.source
      } else { transformation = 0 }
      try GeometryStructuralComparisonWork.charge(surface:surface, using: &execution)
      let entity:Int
      if let spline = writer.surfaceOverrides[surface] {
        entity = try table.add(type:128,form:0,label:item.name,transformationPointer:transformation,parameters:writer.bSplineSurfaceParameters(spline,unit:units.length), using: &execution)
      } else if case .bSpline(let spline) = surface {
        entity = try table.add(type:128,form:0,label:item.name,transformationPointer:transformation,parameters:writer.bSplineSurfaceParameters(spline,unit:units.length), using: &execution)
      } else if case .plane(let plane) = surface {
        let point = try table.add(type:116,form:0,label:"",parameters:writer.pointParameters(plane.origin,unit:units.length), using: &execution)
        let normal = try table.add(type:123,form:0,label:"",parameters:writer.directionParameters(plane.normal), using: &execution)
        let chart = try surface.differentialGeometry(u:0,v:0,tolerance:writer.tolerance)
        let reference = try table.add(type:123,form:0,label:"",parameters:writer.directionParameters(chart.tangentU), using: &execution)
        entity = try table.add(type:190,form:1,label:item.name,transformationPointer:transformation,parameters:"190,\(point),\(normal),\(reference);", using: &execution)
      } else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Analytic local IGES surfaces may already own an inner chart transform.
        // Emit an exact ordered composition with the directory pose before that nested case can succeed.
        guard transformation == 0 else { throw IndependentShapeExchangeError.unsupportedSemantics("Nested original IGES analytic directory pose composition is incomplete.") }
        entity = try originalSurfaceEntity(surface,label:item.name,units:units, using: &execution)
      }
      try execution.chargeSource(records:1,work:1); surfaces[id] = entity
      return entity
    }
    mutating func originalSurfaceEntity(_ surface:Surface3D,label:String,units:UnitSystem, using execution: inout OriginalQueryExecution) throws -> Int {
      try table.chargeGeometryWork(1, using: &execution)
      if let spline = writer.surfaceOverrides[surface] {
        return try table.add(type:128,form:0,label:label,parameters:writer.bSplineSurfaceParameters(spline,unit:units.length), using: &execution)
      }
      if case .bSpline(let spline) = surface {
        return try table.add(type:128,form:0,label:label,parameters:writer.bSplineSurfaceParameters(spline,unit:units.length), using: &execution)
      }
      if case .plane(let plane) = surface {
        let origin = try table.add(type:116,form:0,label:"",parameters:writer.pointParameters(plane.origin,unit:units.length), using: &execution)
        let normal = try table.add(type:123,form:0,label:"",parameters:writer.directionParameters(plane.normal), using: &execution)
        let chart = try surface.differentialGeometry(u:0,v:0,tolerance:writer.tolerance)
        let reference = try table.add(type:123,form:0,label:"",parameters:writer.directionParameters(chart.tangentU), using: &execution)
        return try table.add(type:190,form:1,label:label,parameters:"190,\(origin),\(normal),\(reference);", using: &execution)
      }
      if case .procedural(.offset(let offset)) = surface {
        let basis = try originalSurfaceEntity(offset.source,label:"",units:units, using: &execution)
        let indicator = try writer.offsetIndicator(for:offset.source,tolerance:writer.tolerance)
        return try table.add(type:140,form:0,label:label,parameters:["140",writer.number(indicator.x),writer.number(indicator.y),writer.number(indicator.z),writer.number(units.length.fromInternal(offset.distance)),String(basis)].joined(separator:",")+";", using: &execution)
      }
      guard case .procedural(.originalImage(let image)) = surface else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original IGES source chart transport currently requires its retained parameter-image owner for nonspline analytic values.
        // Public independent export must preserve the complete chart distinction before unwrapped native values can succeed under arbitrary output units.
        throw IndependentShapeExchangeError.unsupportedSemantics("Original IGES analytic chart requires its persistent parameter image.")
      }
      guard image.uGain == 1, image.uOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("IGES angular chart conflicts with the original parameter image.") }
      let original: AnalyticSurface3D
      if case .analytic(let value) = image.source { original = value }
      else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): General original-image basis egress requires the corresponding parameter-preserving standard producer.
        // Public independent IGES export must emit that original basis rather than flatten or sample its chart.
        throw IndependentShapeExchangeError.unsupportedSemantics("Original IGES image basis has no analytic family producer.")
      }
      let point:Point3D, axis:Vector3D, type:Int, measures:[String]
      switch original {
      case .cylinder(let origin,let normal,let radius):
        guard !image.swapAxes, image.vGain == units.length.toInternal(1), image.vOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("IGES cylinder axial chart differs from the retained original.") }
        point=origin; axis=normal; type=192; measures=[writer.number(units.length.fromInternal(radius))]
      case .cone(let apex,let normal,let angle):
        guard !image.swapAxes, image.vGain == units.length.toInternal(1)/cos(angle) else { throw IndependentShapeExchangeError.metadataLoss("IGES cone axial chart differs from the retained original.") }
        let radius=image.vOffset*sin(angle)
        guard radius >= 0 else { throw IndependentShapeExchangeError.metadataLoss("IGES cone reference radius is negative.") }
        point=apex+normal*(image.vOffset*cos(angle)); axis=normal; type=194
        measures=[writer.number(units.length.fromInternal(radius)),writer.number(angle)]
      case .sphere(let center,let radius):
        guard !image.swapAxes, image.vGain == 1, image.vOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("IGES sphere latitude chart differs from the retained original.") }
        point=center; axis = .unitZ; type=196; measures=[writer.number(units.length.fromInternal(radius))]
      case .torus(let center,let normal,let major,let minor):
        guard image.swapAxes, image.vGain == 1, image.vOffset == 0 else { throw IndependentShapeExchangeError.metadataLoss("IGES torus requires its original meridian-longitude chart order.") }
        point=center; axis=normal; type=198; measures=[writer.number(units.length.fromInternal(major)),writer.number(units.length.fromInternal(minor))]
      case .plane: throw IndependentShapeExchangeError.unsupportedSemantics("Original image plane requires its retained affine chart producer.")
      }
      let basis = try ExactAnalyticFrame.analyticBasis(for:axis,tolerance:writer.tolerance)
      let origin=try table.add(type:116,form:0,label:"",parameters:writer.pointParameters(point,unit:units.length), using: &execution)
      let normal=try table.add(type:123,form:0,label:"",parameters:writer.directionParameters(axis), using: &execution)
      let reference=try table.add(type:123,form:0,label:"",parameters:writer.directionParameters(basis.u), using: &execution)
      let f=image.transform
      let identity=f.basisX == .unitX && f.basisY == .unitY && f.basisZ == .unitZ && f.translation == .zero
      let transform = identity ? 0 : try addFrame(f,label:"",units:units, using: &execution)
      let parameters:[String]
      if type == 196 { parameters=[String(type),String(origin)]+measures+[String(normal),String(reference)] }
      else { parameters=[String(type),String(origin),String(normal)]+measures+[String(reference)] }
      return try table.add(type:type,form:1,label:label,transformationPointer:transform,parameters:parameters.joined(separator:",")+";", using: &execution)
    }
    mutating func originalPose(_ association: IndependentShapePositionFrame, word: OriginalAffineOperationWord, unit: LengthUnit,
        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
      try execution.chargeSource(work: 1)
      guard let pointer = originalFrames[association.frameID], let name = originalFrameNames[association.frameID] else { throw IndependentShapeExchangeError.invalidAssociation("Original IGES pose frame was not emitted.") }
      if association.originalIGESAdjustments.isEmpty { return pointer }
      guard writer.allowsReportedPlacementProjection else { throw IndependentShapeExchangeError.metadataLoss("Original IGES primitive-pose adjustment order/shared frame requires an admitted placement projection.") }
      let values = try word.prepared(usage: &execution).exactRationalCoefficients(usage: &execution)
      let gain = try OriginalIGESScalarSource.lengthGain(unit, using: &execution)
      try execution.chargeSource(storageBytes: 13 * MemoryLayout<String>.stride)
      var parameters = ["124"]; parameters.reserveCapacity(13)
      for index in values.indices {
        let value = index % 4 == 3 ? try values[index].divided(by: gain, usage: &execution) : values[index]
        parameters.append(try OriginalIGESDecimalWriting.literal(value, usage: usage, using: &execution))
      }
      table.independentUsage = usage

      return try table.add(type:124,form:word.orientationSign > 0 ? 0 : 1,label:name,parameters:parameters.joined(separator:",")+";", using: &execution)
    }
    mutating func frame(_ frame:IndependentShapeFrame,units:UnitSystem,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
      table.independentUsage = usage
      if let original = frame.originalIGES {
        guard original.lengthUnit == units.length else { throw IndependentShapeExchangeError.metadataLoss("Original IGES matrix unit differs from the actual global unit.") }
        var coefficients = original.coefficients
        if !original.adjustments.isEmpty {
          guard writer.allowsReportedPlacementProjection else { throw IndependentShapeExchangeError.metadataLoss("Original IGES matrix adjustment order requires an admitted placement projection.") }
          let word = try original.originalOperationWord(tolerance: writer.tolerance,
              maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, using: &execution)
          let values = try word.prepared(usage: &execution).exactRationalCoefficients(usage: &execution)
          let gain = try OriginalIGESScalarSource.lengthGain(units.length, using: &execution)
          try execution.chargeSource(storageBytes: 12 * MemoryLayout<String>.stride)
          coefficients = []
          for index in values.indices {
            let value = index % 4 == 3 ? try values[index].divided(by: gain, usage: &execution) : values[index]
            coefficients.append(try OriginalIGESDecimalWriting.literal(value, usage: usage, using: &execution))
          }
        }
                let entity = try table.add(type:124,form:original.form,label:frame.name,parameters:(["124"] + coefficients).joined(separator:",")+";", using: &execution)
        try table.independentUsage!.charge(entities: 2, work: 2,
            bytes: MemoryLayout<(IndependentShapeFrameID, Int)>.stride + MemoryLayout<(IndependentShapeFrameID, String)>.stride, using: &execution)
        originalFrames[frame.id] = entity; originalFrameNames[frame.id] = frame.name
        return entity
      }
      let entity = try addFrame(frame.placement,label:frame.name,units:units, using: &execution)
      try table.independentUsage!.charge(entities: 2, work: 2,
          bytes: MemoryLayout<(IndependentShapeFrameID, Int)>.stride + MemoryLayout<(IndependentShapeFrameID, String)>.stride, using: &execution)
      originalFrames[frame.id] = entity; originalFrameNames[frame.id] = frame.name
      return entity
    }
    mutating func addFrame(_ f:AffineTransform3D,label:String,units:UnitSystem, using execution: inout OriginalQueryExecution) throws -> Int {
      guard table.independentUsage != nil else {
        throw IndependentShapeExchangeError.invalidAssociation("Original IGES frame requires its operation allowance.")
      }
      _ = try OriginalOrthogonalAffineRepresentability.scale(of: f, requiresUnitScale: true, format: .iges, using: &execution)
      let sign = f.basisX.cross(f.basisY).dot(f.basisZ)
      let p = ["124",writer.number(f.basisX.x),writer.number(f.basisY.x),writer.number(f.basisZ.x),writer.number(units.length.fromInternal(f.translation.x)),
          writer.number(f.basisX.y),writer.number(f.basisY.y),writer.number(f.basisZ.y),writer.number(units.length.fromInternal(f.translation.y)),
          writer.number(f.basisX.z),writer.number(f.basisY.z),writer.number(f.basisZ.z),writer.number(units.length.fromInternal(f.translation.z))]
      return try table.add(type:124,form:sign > 0 ? 0 : 1,label:label,parameters:p.joined(separator:",")+";", using: &execution)
    }
    mutating func instancePlacement(_ instance:IndependentShapeInstance,definitionPointer:Int,units:UnitSystem,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
      table.independentUsage = usage
      let f = instance.placement
      guard table.independentUsage != nil else {
        throw IndependentShapeExchangeError.invalidAssociation("Original IGES instance requires its operation allowance.")
      }
      let scale = try OriginalOrthogonalAffineRepresentability.scale(of: f, requiresUnitScale: false,
          format: .iges, using: &execution)
      let matrix = try OriginalOrthogonalAffineRepresentability.normalizedFrame(f, scale: scale, using: &execution)
            let identity = matrix.basisX == .unitX && matrix.basisY == .unitY && matrix.basisZ == .unitZ
      let transform = identity && instance.placementName.isEmpty ? 0 : try addFrame(matrix,label:instance.placementName,units:units, using: &execution)
      let p = ["408",String(definitionPointer),writer.number(units.length.fromInternal(f.translation.x)),
          writer.number(units.length.fromInternal(f.translation.y)),writer.number(units.length.fromInternal(f.translation.z)),writer.number(scale)]
      return try table.add(type:408,form:0,label:instance.name,transformationPointer:transform,parameters:p.joined(separator:",")+";", using: &execution)
    }
    mutating func appendEntity(type:Int,form:Int,label:String,transformationPointer:Int,parameters:[String],usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
      table.independentUsage = usage
      return try table.add(type:type,form:form,label:label,transformationPointer:transformationPointer,parameters:parameters.joined(separator:",")+";", using: &execution)
    }
    mutating func appendGroupBackPointer(groupPointer:Int,memberPointer:Int,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws {
      table.independentUsage = usage
      try table.appendGroupBackPointer(groupPointer:groupPointer,memberPointer:memberPointer, using: &execution)
    }
    mutating func string(_ value:String,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> String {
      try execution.chargeSource(work:value.utf8.count+1)
      guard value.utf8.allSatisfy({ $0 < 128 }) else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent IGES text output has no original character-set property transport yet.
        // Preserve the actual string bytes through a legal IGES encoding before non-ASCII labels/names succeed.
        throw IndependentShapeExchangeError.metadataLoss("IGES text encoding cannot retain this original string.")
      }
      return "\(value.utf8.count)H\(value)"
    }
    mutating func finish(units:UnitSystem,usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data {
      table.independentUsage = usage
      try table.retainAssociationParameterTails( using: &execution)
      let header = try table.serializedFramingByteCount(unit:units.length, using: &execution)
      try execution.chargeSource(storageBytes:header)
      let output = try table.serialize(unit:units.length,maximumBytes:writer.resourceLimits.maximumBytes, using: &execution)
      try usage.check(); return output
    }
  }

  func write(
    brep: BRepModel,
    units: UnitSystem,
    to sink: any ByteSink
  ) throws {
    try requireCertifiedBodySurfaceIncidence(brep)
    var table = try EntityTable(
      maximumEntities: resourceLimits.maximumEntities,
      tolerance: tolerance,
      maximumWork: resourceLimits.maximumIterations, processingBudget: processingBudget
    , limits: resourceLimits)
    var execution = try table.execution()
    var curvePointers: [EdgeID: Int] = [:]
    var edgeSameSense: [EdgeID: Bool] = [:]
    var surfaceLiftEdges: Set<EdgeID> = []
    for edgeID in brep.edges.keys.sorted() {
      guard let edge = brep.edges[edgeID],
        let start = brep.vertices[edge.startVertexID]?.point,
        let end = brep.vertices[edge.endVertexID]?.point,
        let curve = brep.geometry.curves[edge.curveID]
      else {
        throw exchangeError(.missingReference, "IGES edge geometry is incomplete.")
      }
      if let converted = curveConversions.edges[edgeID] {
        guard let trim = curveConversions.selections[edgeID] else { throw exchangeError(.topologyFailure, "Converted edge lost its original directed selection.") }
        curvePointers[edgeID] = try table.add(type: 126, form: 0, label: "CERTCRV",
          parameters: bSplineCurveParameters(converted, startParameter: trim.startParameter,
            endParameter: trim.endParameter, unit: units.length), using: &execution)
        edgeSameSense[edgeID] = true
        continue
      }
      switch curve {
      case .line(let line):
        let signedSpan = (end - start).dot(line.direction)
        guard abs(signedSpan) > tolerance.distance else {
          throw exchangeError(
            .topologyFailure, "IGES edge curve direction is inconsistent with its vertices.")
        }
        edgeSameSense[edgeID] = signedSpan > 0.0
        curvePointers[edgeID] = try table.add(
          type: 110,
          form: 0,
          label: "CURVE",
          parameters: lineParameters(start: start, end: end, unit: units.length)
        , using: &execution)
      case .bSpline(let bSpline):
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure, "IGES B-spline edge requires an explicit trim interval.")
        }
        edgeSameSense[edgeID] = true
        curvePointers[edgeID] = try table.add(
          type: 126,
          form: 0,
          label: "NURBSCRV",
          parameters: bSplineCurveParameters(
            bSpline,
            startParameter: trim.startParameter,
            endParameter: trim.endParameter,
            unit: units.length
          )
        , using: &execution)
      case .circle(let circle):
        let trim = try requiredPeriodicTrim(edge, label: "circle")
        let sameSense = trim.endParameter > trim.startParameter
        edgeSameSense[edgeID] = sameSense
        let basis = try ExactAnalyticFrame.directBasis(for: circle.normal, tolerance: tolerance)
        curvePointers[edgeID] = try circularArcEntity(
          center: circle.center,
          normal: circle.normal,
          reference: basis.u,
          label: "CIRCARC",
          modelStart: sameSense ? start : end,
          modelEnd: sameSense ? end : start,
          unit: units.length,
          table: &table, using: &execution
        )
      case .analytic(let analytic):
        if case .planeTorus(let planeTorus) = analytic {
          guard let trim = edge.trim else {
            throw exchangeError(
              .topologyFailure,
              "IGES plane-torus intersection edges require an explicit trim."
            )
          }
          let transfer = try ExactPlaneTorusTransferBuilder().build(
            curve: planeTorus,
            trim: trim,
            tolerance: tolerance
          )
          guard case .closed(let lower, let upper) = transfer.curve.domain else {
            throw exchangeError(
              .topologyFailure,
              "IGES plane-torus transfer produced an unbounded derived curve."
            )
          }
          let modelCurve = try table.add(
            type: 126,
            form: 0,
            label: "INTMODEL",
            parameters: bSplineCurveParameters(
              transfer.curve,
              startParameter: lower,
              endParameter: upper,
              unit: units.length
            )
          , using: &execution)
          let planeSurface = try exactSurfaceEntity(
            planeTorus.planeSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          let torusSurface = try exactSurfaceEntity(
            planeTorus.torusSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          guard case .bSpline(let planePcurve) = transfer.planePcurve,
            case .bSpline(let torusPcurve) = transfer.torusPcurve
          else {
            throw exchangeError(
              .topologyFailure,
              "IGES plane-torus transfer requires verified rational p-curves."
            )
          }
          let planeParameterCurve = try parameterBSplineEntity(
            planePcurve,
            surface: planeTorus.planeSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          let torusParameterCurve = try parameterBSplineEntity(
            torusPcurve,
            surface: planeTorus.torusSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          let torusCurveOnSurface = try table.add(
            type: 142,
            form: 0,
            label: "INTTORUS",
            parameters: "142,1,\(torusSurface),\(torusParameterCurve),\(modelCurve),3;"
          , using: &execution)
          curvePointers[edgeID] = try table.add(
            type: 142,
            form: 0,
            label: "INTPLANE",
            parameters: "142,1,\(planeSurface),\(planeParameterCurve),\(torusCurveOnSurface),3;"
          , using: &execution)
          edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
        } else {
          let result = try analyticCurveEntity(
            analytic,
            edge: edge,
            start: start,
            end: end,
            unit: units.length,
            table: &table, using: &execution
          )
          edgeSameSense[edgeID] = result.sameSense
          curvePointers[edgeID] = result.pointer
        }
      case .implicit(let implicit):
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "IGES implicit intersection edges require an explicit trim."
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
            "IGES implicit intersection pcurve provenance disagrees with its model curve."
          )
        }
        let transfer = try ExactImplicitIntersectionTransferBuilder().build(
          source: source,
          trim: trim,
          tolerance: tolerance
        )
        guard case .closed(let lower, let upper) = transfer.curve.domain,
          case .bSpline(let firstPcurve) = transfer.firstPcurve,
          case .bSpline(let secondPcurve) = transfer.secondPcurve
        else {
          throw exchangeError(
            .topologyFailure,
            "IGES implicit intersection transfer requires finite verified rational splines."
          )
        }
        let modelCurve = try table.add(
          type: 126,
          form: 0,
          label: "INTMODEL",
          parameters: bSplineCurveParameters(
            transfer.curve,
            startParameter: lower,
            endParameter: upper,
            unit: units.length
          )
        , using: &execution)
        let firstSurface = try exactSurfaceEntity(
          source.firstSurface,
          unit: units.length,
          table: &table, using: &execution
        )
        let secondSurface = try exactSurfaceEntity(
          source.secondSurface,
          unit: units.length,
          table: &table, using: &execution
        )
        let firstParameterCurve = try parameterBSplineEntity(
          firstPcurve,
          surface: source.firstSurface,
          unit: units.length,
          table: &table, using: &execution
        )
        let secondParameterCurve = try parameterBSplineEntity(
          secondPcurve,
          surface: source.secondSurface,
          unit: units.length,
          table: &table, using: &execution
        )
        let secondCurveOnSurface = try table.add(
          type: 142,
          form: 0,
          label: "INTSECOND",
          parameters: "142,1,\(secondSurface),\(secondParameterCurve),\(modelCurve),3;"
        , using: &execution)
        curvePointers[edgeID] = try table.add(
          type: 142,
          form: 0,
          label: "INTFIRST",
          parameters: "142,1,\(firstSurface),\(firstParameterCurve),\(secondCurveOnSurface),3;"
        , using: &execution)
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
      case .surfaceLift(let lift):
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "IGES surface-lift edges require an explicit normalized trim."
          )
        }
        let transfer = try ExactSurfaceLiftTransferBuilder().build(
          lift: lift,
          trim: trim,
          tolerance: tolerance
        )
        guard case .closed(let lower, let upper) = transfer.curve.domain else {
          throw exchangeError(
            .topologyFailure,
            "IGES surface-lift transfer produced an unbounded derived curve."
          )
        }
        let modelCurve = try table.add(
          type: 126,
          form: 0,
          label: "LIFTMODEL",
          parameters: bSplineCurveParameters(
            transfer.curve,
            startParameter: lower,
            endParameter: upper,
            unit: units.length
          )
        , using: &execution)
        let sourceSurface = try exactSurfaceEntity(
          lift.surface,
          unit: units.length,
          table: &table, using: &execution
        )
        let sourceParameterCurve = try parameterCurveEntity(
          transfer.parameterCurve,
          surface: lift.surface,
          unit: units.length,
          table: &table, using: &execution
        )
        curvePointers[edgeID] = try table.add(
          type: 142,
          form: 0,
          label: "SURFLIFT",
          parameters: "142,1,\(sourceSurface),\(sourceParameterCurve),\(modelCurve),3;"
        , using: &execution)
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
        surfaceLiftEdges.insert(edgeID)
      case .certifiedIntersection, .rigidImage:
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "IGES certified transfer curves require an explicit normalized trim."
          )
        }
        let transfer = try ExactCertifiedCurveTransferBuilder().build(
          curve: curve,
          trim: trim,
          tolerance: tolerance
        )
        guard case .closed(let lower, let upper) = transfer.curve.domain else {
          throw exchangeError(
            .topologyFailure,
            "IGES certified transfer produced an unbounded rational curve."
          )
        }
        let modelCurve = try table.add(
          type: 126,
          form: 0,
          label: transfer.representsSurfaceLift ? "LIFTMODEL" : "CERTCURVE",
          parameters: bSplineCurveParameters(
            transfer.curve,
            startParameter: lower,
            endParameter: upper,
            unit: units.length
          )
        , using: &execution)
        let firstSurface = try exactSurfaceEntity(
          transfer.firstSurface,
          unit: units.length,
          table: &table, using: &execution
        )
        let firstParameterCurve = try parameterCurveEntity(
          transfer.firstSurfaceParameterCurve,
          surface: transfer.firstSurface,
          unit: units.length,
          table: &table, using: &execution
        )
        if transfer.representsSurfaceLift {
          curvePointers[edgeID] = try table.add(
            type: 142,
            form: 0,
            label: "SURFLIFT",
            parameters: "142,1,\(firstSurface),\(firstParameterCurve),\(modelCurve),3;"
          , using: &execution)
          surfaceLiftEdges.insert(edgeID)
        } else {
          let secondSurface = try exactSurfaceEntity(
            transfer.secondSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          let secondParameterCurve = try parameterCurveEntity(
            transfer.secondSurfaceParameterCurve,
            surface: transfer.secondSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          let secondCurveOnSurface = try table.add(
            type: 142,
            form: 0,
            label: "CERTSECO",
            parameters: "142,1,\(secondSurface),\(secondParameterCurve),\(modelCurve),3;"
          , using: &execution)
          curvePointers[edgeID] = try table.add(
            type: 142,
            form: 0,
            label: "CERTFIRS",
            parameters: "142,1,\(firstSurface),\(firstParameterCurve),\(secondCurveOnSurface),3;"
          , using: &execution)
        }
        edgeSameSense[edgeID] = trim.endParameter > trim.startParameter
      // FIXME(INCOMPLETE_IMPLEMENTATION): Body IGES parameter-image curves still require a certified original-parameter transport.
      // The public Body writer must preserve the foreign curve law and directed trim, rather than changing only endpoints or labels.
      // FIXME(INCOMPLETE_IMPLEMENTATION): Original flat word and endpoint-connector laws lack their bounded standard Body transport producer.
      // IGES publication must preserve the whole source law or publish an explicitly accepted certified conversion with its guarantee.
      case .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
        throw exchangeError(.unsupportedCapability, "IGES original word/endpoint connector Body transport requires its original producer.")
      case .parameterImage:
        throw exchangeError(.unsupportedCapability,"IGES original parameter-image Body curve transport is not implemented.")
      case .affineImage:
        if let line = curve.exactLinearLocus {
          let signedSpan = (end - start).dot(line.direction)
          guard abs(signedSpan) > tolerance.distance else {
            throw exchangeError(
              .singularGeometry,
              "IGES affine-image line geometry is inconsistent with its vertices."
            )
          }
          edgeSameSense[edgeID] = signedSpan > 0.0
          curvePointers[edgeID] = try table.add(
            type: 110,
            form: 0,
            label: "CURVE",
            parameters: lineParameters(start: start, end: end, unit: units.length)
          , using: &execution)
          continue
        }
        guard let trim = edge.trim else {
          throw exchangeError(
            .topologyFailure,
            "IGES affine-image curves require an explicit finite trim interval."
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
            tolerance: tolerance, using: &execution
          )
        else {
          throw exchangeError(
            .unsupportedCapability,
            "IGES has no exact rational representation for this affine-image curve."
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
            to: start,
            tolerance: tolerance.distance
          ),
          expectedEnd.isApproximatelyEqual(
            to: end,
            tolerance: tolerance.distance
          )
        else {
          throw exchangeError(
            .topologyFailure,
            "IGES affine-image rational transfer disagrees with its edge vertices."
          )
        }
        edgeSameSense[edgeID] = true
        curvePointers[edgeID] = try table.add(
          type: 126,
          form: 0,
          label: "NURBSCRV",
          parameters: bSplineCurveParameters(
            exactCurve,
            startParameter: trim.startParameter,
            endParameter: trim.endParameter,
            unit: units.length
          )
        , using: &execution)
      }
    }

    var surfacePointers: [SurfaceID: Int] = [:]
    for faceID in brep.faces.keys.sorted() {
      guard let face = brep.faces[faceID],
        let surface = brep.geometry.surfaces[face.surfaceID]
      else {
        throw exchangeError(.missingReference, "IGES face surface is missing.")
      }
      if surfacePointers[face.surfaceID] == nil {
        surfacePointers[face.surfaceID] = try exactSurfaceEntity(
          surface,
          unit: units.length,
          table: &table, using: &execution
        )
      }
    }

    let vertexIDs = brep.vertices.keys.sorted()
    var vertexIndices: [VertexID: Int] = [:]
    var vertexParameters = ["502", "\(vertexIDs.count)"]
    for (offset, vertexID) in vertexIDs.enumerated() {
      guard let vertex = brep.vertices[vertexID] else {
        throw exchangeError(.missingReference, "IGES vertex is missing.")
      }
      vertexIndices[vertexID] = offset + 1
      vertexParameters.append(contentsOf: coordinates(vertex.point, unit: units.length))
    }
    let vertexListPointer = try table.add(
      type: 502,
      form: 1,
      label: "VERTICES",
      parameters: vertexParameters.joined(separator: ",") + ";"
    , using: &execution)

    let edgeIDs = brep.edges.keys.sorted()
    var edgeIndices: [EdgeID: Int] = [:]
    var edgeParameters = ["504", "\(edgeIDs.count)"]
    for (offset, edgeID) in edgeIDs.enumerated() {
      guard let edge = brep.edges[edgeID],
        let curvePointer = curvePointers[edgeID],
        let startIndex = vertexIndices[edge.startVertexID],
        let endIndex = vertexIndices[edge.endVertexID]
      else {
        throw exchangeError(.missingReference, "IGES edge topology is incomplete.")
      }
      edgeIndices[edgeID] = offset + 1
      edgeParameters.append(contentsOf: [
        "\(curvePointer)",
        "\(vertexListPointer)",
        "\(startIndex)",
        "\(vertexListPointer)",
        "\(endIndex)",
      ])
    }
    let edgeListPointer = try table.add(
      type: 504,
      form: 1,
      label: "EDGES",
      parameters: edgeParameters.joined(separator: ",") + ";"
    , using: &execution)

    var loopPointers: [LoopID: Int] = [:]
    for faceID in brep.faces.keys.sorted() {
      guard let face = brep.faces[faceID],
        let surface = brep.geometry.surfaces[face.surfaceID]
      else {
        throw exchangeError(.missingReference, "IGES face surface is missing.")
      }
      let emittedSurface = surfaceOverrides[surface].map(Surface3D.bSpline) ?? surface
      for loopID in face.loops {
        guard let loop = brep.loops[loopID] else {
          throw exchangeError(.missingReference, "IGES loop is missing.")
        }
        var parameters = ["508", "\(loop.coedges.count)"]
        for coedge in loop.coedges {
          guard let parameterCurve = coedge.surfaceParameterCurve,
            let edge = brep.edges[coedge.edgeID],
            let edgeIndex = edgeIndices[coedge.edgeID],
            let sameSense = edgeSameSense[coedge.edgeID],
            let start = brep.vertices[edge.startVertexID]?.point,
            let end = brep.vertices[edge.endVertexID]?.point
          else {
            throw exchangeError(.topologyFailure, "IGES coedge topology or p-curve is incomplete.")
          }
          let modelStart = sameSense ? start : end
          let modelEnd = sameSense ? end : start
          let coedgeAgreesWithModelCurve = (coedge.orientation == .forward) == sameSense
          let directedCurve =
            coedgeAgreesWithModelCurve
            ? parameterCurve
            : try parameterCurve.reversed(tolerance: tolerance)
          let startUV = try directedCurve.startParameter(tolerance: tolerance)
          let endUV = try directedCurve.endParameter(tolerance: tolerance)
          let reconstructedStart = try emittedSurface.point(
            u: startUV.u,
            v: startUV.v,
            tolerance: tolerance
          )
          let reconstructedEnd = try emittedSurface.point(
            u: endUV.u,
            v: endUV.v,
            tolerance: tolerance
          )
          guard
            reconstructedStart.isApproximatelyEqual(
              to: modelStart,
              tolerance: tolerance.distance
            ),
            reconstructedEnd.isApproximatelyEqual(
              to: modelEnd,
              tolerance: tolerance.distance
            )
          else {
            throw exchangeError(
              .topologyFailure,
              "IGES p-curve endpoints disagree with the model-curve direction."
            )
          }
          if surfaceLiftEdges.contains(coedge.edgeID)
            || usesModelCurveOnly(
              directedCurve,
              on: emittedSurface
            )
          {
            parameters.append(contentsOf: [
              "0",
              "\(edgeListPointer)",
              "\(edgeIndex)",
              boolean(coedgeAgreesWithModelCurve),
              "0",
            ])
            continue
          }
          let pcurvePointer = try parameterCurveEntity(
            directedCurve,
            surface: emittedSurface,
            unit: units.length,
            table: &table, using: &execution
          )
          parameters.append(contentsOf: [
            "0",
            "\(edgeListPointer)",
            "\(edgeIndex)",
            boolean(coedgeAgreesWithModelCurve),
            "1",
            boolean(false),
            "\(pcurvePointer)",
          ])
        }
        loopPointers[loopID] = try table.add(
          type: 508,
          form: 1,
          label: "LOOP",
          parameters: parameters.joined(separator: ",") + ";"
        , using: &execution)
      }
    }

    var facePointers: [FaceID: Int] = [:]
    for faceID in brep.faces.keys.sorted() {
      guard let face = brep.faces[faceID],
        let surfacePointer = surfacePointers[face.surfaceID]
      else {
        throw exchangeError(.missingReference, "IGES face is incomplete.")
      }
      let orderedLoops = face.loops.sorted { lhs, rhs in
        (brep.loops[lhs]?.role == .outer ? 0 : 1) < (brep.loops[rhs]?.role == .outer ? 0 : 1)
      }
      guard orderedLoops.first.flatMap({ brep.loops[$0] })?.role == .outer else {
        throw exchangeError(.topologyFailure, "IGES face requires one outer loop.")
      }
      let pointers = try orderedLoops.map { loopID -> String in
        guard let pointer = loopPointers[loopID] else {
          throw exchangeError(.missingReference, "IGES face loop is missing.")
        }
        return "\(pointer)"
      }
      facePointers[faceID] = try table.add(
        type: 510,
        form: 1,
        label: "FACE",
        parameters: (["510", "\(surfacePointer)", "\(pointers.count)", boolean(true)] + pointers)
          .joined(separator: ",") + ";"
      , using: &execution)
    }

    let groupedSheetShellIDs = Set(
      brep.bodies.values.flatMap { body in
        body.kind == .sheet && body.shellIDs.count > 1 ? body.shellIDs : []
      })
    var shellPointers: [ShellID: Int] = [:]
    for shellID in brep.shells.keys.sorted() {
      guard let shell = brep.shells[shellID] else {
        throw exchangeError(.missingReference, "IGES shell is missing.")
      }
      var parameters = ["514", "\(shell.faceIDs.count)"]
      for faceID in shell.faceIDs {
        guard let face = brep.faces[faceID], let pointer = facePointers[faceID] else {
          throw exchangeError(.missingReference, "IGES shell face is missing.")
        }
        parameters.append("\(pointer)")
        parameters.append(boolean(face.orientation == .forward))
      }
      shellPointers[shellID] = try table.add(
        type: 514,
        form: 1,
        label: "SHELL",
        statusNumber: groupedSheetShellIDs.contains(shellID) ? 20_000 : 0,
        parameters: parameters.joined(separator: ",") + ";"
      , using: &execution)
    }

    for bodyID in brep.bodies.keys.sorted() {
      guard let body = brep.bodies[bodyID] else {
        throw exchangeError(.missingReference, "IGES body is missing.")
      }
      if body.kind == .sheet {
        if body.shellIDs.count > 1 {
          let pointers = try body.shellIDs.sorted().map { shellID -> String in
            guard let pointer = shellPointers[shellID] else {
              throw exchangeError(.missingReference, "IGES sheet body shell is missing.")
            }
            return "\(pointer)"
          }
          _ = try table.add(
            type: 402,
            form: 7,
            label: "SHEETBDY",
            statusNumber: 300,
            parameters: (["402", "\(pointers.count)"] + pointers)
              .joined(separator: ",") + ";"
          , using: &execution)
        }
        continue
      }
      let components = try brep.solidShellComponents(
        for: bodyID,
        tolerance: tolerance
      )
      for component in components {
        guard let outerPointer = shellPointers[component.outerShellID] else {
          throw exchangeError(.missingReference, "IGES solid outer shell is missing.")
        }
        var parameters = [
          "186",
          "\(outerPointer)",
          boolean(true),
          "\(component.voidShellIDs.count)",
        ]
        for voidShellID in component.voidShellIDs {
          guard let pointer = shellPointers[voidShellID] else {
            throw exchangeError(.missingReference, "IGES solid void shell is missing.")
          }
          parameters.append("\(pointer)")
          parameters.append(boolean(false))
        }
        _ = try table.add(
          type: 186,
          form: 0,
          label: "SOLID",
          parameters: parameters.joined(separator: ",") + ";"
        , using: &execution)
      }
    }

    let data = try table.serialize(unit: units.length, maximumBytes: resourceLimits.maximumBytes, using: &execution)
    try data.withUnsafeBytes { bytes in
      try sink.write(bytes)
    }
  }

  private func lineParameters(start: Point3D, end: Point3D, unit: LengthUnit) -> String {
    (["110"] + coordinates(start, unit: unit) + coordinates(end, unit: unit)).joined(separator: ",")
      + ";"
  }

  private func isLinear(_ curve: SurfaceParameterCurve) -> Bool {
    switch curve {
    case .affine, .constantU, .constantV:
      true
    case .polyline(let points):
      points.count == 2
    case .bSpline(let curve):
      curve.degree == 1 && curve.controlPointCount == 2
    case .originalBSplineContinuation, .originalAffineWord, .harmonic, .sphericalGreatCircle, .certifiedImplicit,
      .certifiedAnalyticImplicit, .certifiedAnalyticPair,
      .projectedAnalytic, .rigidImage, .originalImage:
      false
    case .periodicTranslation(let base, _, _):
      isLinear(base)
    case .offsetSurfaceImage(let image):
      isLinear(image.source)
    }
  }

  private func usesModelCurveOnly(
    _ curve: SurfaceParameterCurve,
    on surface: Surface3D
  ) -> Bool {
    switch curve {
    case .projectedAnalytic(let projected):
      guard case .analytic(.cone) = surface else { return false }
      return projected.surface == surface
    case .sphericalGreatCircle:
      guard case .analytic(.sphere) = surface else { return false }
      return true
    case .certifiedAnalyticPair(let certified):
      return certified.intersection.surface(for: certified.role) == surface
    case .certifiedImplicit(let certified):
      let source =
        certified.role == .first
        ? certified.intersection.firstSurface
        : certified.intersection.secondSurface
      return surface == source
    case .certifiedAnalyticImplicit(let certified):
      return certified.intersection.analyticSurface == surface
    case .originalImage(let image):
      return surface == .parameterImage(image.targetImage)
    // FIXME(INCOMPLETE_IMPLEMENTATION): Hosted original-word pcurve IGES support transport needs its actual original-law producer.
    // Body export must not omit the retained support operation word while publishing model geometry as faithful success.
    case .originalAffineWord:
      return false
    case .rigidImage(let image):
      return image.targetSurface == surface
    case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation:
      return false
    case .periodicTranslation(let base, _, _):
      return usesModelCurveOnly(base, on: surface)
    case .offsetSurfaceImage(let image):
      return usesModelCurveOnly(
        image.source,
        on: image.sourceSurface
      )
    }
  }

  private func line2DParameters(
    startU: Double,
    startV: Double,
    endU: Double,
    endV: Double
  ) -> String {
    [
      "110",
      number(startU),
      number(startV),
      "0",
      number(endU),
      number(endV),
      "0",
    ].joined(separator: ",") + ";"
  }

  private func parameterCurveEntity(
    _ curve: SurfaceParameterCurve,
    surface: Surface3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let start = try curve.startParameter(tolerance: tolerance)
    let end = try curve.endParameter(tolerance: tolerance)
    let encodedStart = try ExactSurfaceParameterCodec.encode(
      start,
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedEnd = try ExactSurfaceParameterCodec.encode(
      end,
      on: surface,
      unit: unit,
      convention: .iges
    )
    if isLinear(curve) {
      return try table.add(
        type: 110,
        form: 0,
        label: "PCURVE",
        parameters: line2DParameters(
          startU: encodedStart.u,
          startV: encodedStart.v,
          endU: encodedEnd.u,
          endV: encodedEnd.v
        )
      , using: &execution)
    }
    switch curve {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Exact hosted original-word pcurve publication needs a standard original-law carrier.
    // The Body writer must preserve the complete native directed chart and original support rather than publish a sampled substitute.
    case .originalAffineWord:
      throw exchangeError(.unsupportedCapability, "Hosted original-word pcurve requires faithful standard transport.")
    case .originalBSplineContinuation:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Public IGES p-curve extension still requires the original endpoint-span law producer in neutral representation.
      // Transfer must retain or certify the full directed continuation, rather than trimming the original spline inside its previous domain.
      throw exchangeError(.unsupportedCapability, "Original p-curve continuation requires a complete neutral curve-law transfer.")
    case .bSpline(let bSpline):
      return try parameterBSplineEntity(
        bSpline,
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    case .polyline(let points):
      return try parameterBSplineEntity(
        ExactPolylineBSplineBuilder(tolerance: tolerance).build(points: points),
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
      return try parameterHarmonicEntity(
        center: center,
        cosine: cosine,
        sine: sine,
        startParameter: startParameter,
        endParameter: endParameter,
        encodedStart: encodedStart,
        encodedEnd: encodedEnd,
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    case .projectedAnalytic(let projected):
      return try parameterBSplineEntity(
        try ExactProjectedAnalyticPcurveBSplineBuilder().build(
          projected,
          tolerance: tolerance, using: &execution
        ),
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    case .periodicTranslation:
      let translated = try curve.materializingPeriodicTranslation(using: &execution)
      if case .periodicTranslation = translated {
        throw exchangeError(
          .unsupportedCapability,
          "IGES cannot materialize this translated certificate-backed p-curve."
        )
      }
      return try parameterCurveEntity(
        translated,
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    case .offsetSurfaceImage(let image):
      try image.validate(on: surface, tolerance: tolerance)
      return try parameterCurveEntity(
        image.source,
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    case .affine, .constantU, .constantV:
      throw exchangeError(
        .topologyFailure,
        "IGES linear pcurve dispatch failed to recognize a linear curve."
      )
    case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
      .certifiedAnalyticPair:
      throw exchangeError(
        .unsupportedCapability,
        "IGES pcurve export requires an exact transferable line, polyline, ellipse, or rational B-spline."
      )
    case .originalImage(let image):
      try image.validate(on: surface, tolerance: tolerance)
      throw exchangeError(.topologyFailure,
        "IGES original-image p-curves must use their original model-curve surface association.")
    case .rigidImage:
      throw exchangeError(
        .topologyFailure,
        "IGES rigid-image p-curves must use their exact model-curve surface association."
      )
    }
  }

  private func parameterHarmonicEntity(
    center: Point2D,
    cosine: Point2D,
    sine: Point2D,
    startParameter: Double,
    endParameter: Double,
    encodedStart: SurfaceParameter,
    encodedEnd: SurfaceParameter,
    surface: Surface3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let encodedCenter = try ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x, v: center.y),
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedCosinePoint = try ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x + cosine.x, v: center.y + cosine.y),
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedSinePoint = try ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x + sine.x, v: center.y + sine.y),
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedCosine = Point2D(
      x: encodedCosinePoint.u - encodedCenter.u,
      y: encodedCosinePoint.v - encodedCenter.v
    )
    let encodedSine = Point2D(
      x: encodedSinePoint.u - encodedCenter.u,
      y: encodedSinePoint.v - encodedCenter.v
    )
    let signedOrientation =
      (encodedCosine.x * encodedSine.y - encodedCosine.y * encodedSine.x)
      * (endParameter - startParameter)
    if signedOrientation > 0.0 {
      return try parameterEllipseEntity(
        center: center,
        cosine: cosine,
        sine: sine,
        startParameter: startParameter,
        endParameter: endParameter,
        encodedStart: encodedStart,
        encodedEnd: encodedEnd,
        surface: surface,
        unit: unit,
        table: &table, using: &execution
      )
    }

    let curve = try ExactHarmonicArcBSplineBuilder(tolerance: tolerance).build(
      center: center,
      cosine: cosine,
      sine: sine,
      startParameter: startParameter,
      endParameter: endParameter
    )
    return try parameterBSplineEntity(
      curve,
      surface: surface,
      unit: unit,
      table: &table, using: &execution
    )
  }

  private func parameterEllipseEntity(
    center: Point2D,
    cosine: Point2D,
    sine: Point2D,
    startParameter: Double,
    endParameter: Double,
    encodedStart: SurfaceParameter,
    encodedEnd: SurfaceParameter,
    surface: Surface3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let encodedCenter = try ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x, v: center.y),
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedCosinePoint = try ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x + cosine.x, v: center.y + cosine.y),
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedSinePoint = try ExactSurfaceParameterCodec.encode(
      SurfaceParameter(u: center.x + sine.x, v: center.y + sine.y),
      on: surface,
      unit: unit,
      convention: .iges
    )
    let encodedCosine = Point2D(
      x: encodedCosinePoint.u - encodedCenter.u,
      y: encodedCosinePoint.v - encodedCenter.v
    )
    let encodedSine = Point2D(
      x: encodedSinePoint.u - encodedCenter.u,
      y: encodedSinePoint.v - encodedCenter.v
    )
    guard
      (encodedCosine.x * encodedSine.y - encodedCosine.y * encodedSine.x)
        * (endParameter - startParameter) > 0.0
    else {
      throw exchangeError(
        .unsupportedCapability,
        "IGES type 104 p-curves require counterclockwise model-curve parameterization."
      )
    }
    let ellipse = try STEPParameterEllipse(
      center: Point2D(x: encodedCenter.u, y: encodedCenter.v),
      cosine: encodedCosine,
      sine: encodedSine,
      tolerance: try ExactSurfaceParameterCodec.encodedTolerance(
        on: surface, unit: unit, tolerance: tolerance)
    )
    let x = ellipse.majorDirection
    let y = Point2D(x: -x.y, y: x.x)
    let inverseMajorSquared = 1.0 / (ellipse.majorRadius * ellipse.majorRadius)
    let inverseMinorSquared = 1.0 / (ellipse.minorRadius * ellipse.minorRadius)
    let a = x.x * x.x * inverseMajorSquared + y.x * y.x * inverseMinorSquared
    let b = 2.0 * (x.x * x.y * inverseMajorSquared + y.x * y.y * inverseMinorSquared)
    let c = x.y * x.y * inverseMajorSquared + y.y * y.y * inverseMinorSquared
    let d = -2.0 * a * ellipse.center.x - b * ellipse.center.y
    let e = -b * ellipse.center.x - 2.0 * c * ellipse.center.y
    let f =
      a * ellipse.center.x * ellipse.center.x
      + b * ellipse.center.x * ellipse.center.y
      + c * ellipse.center.y * ellipse.center.y
      - 1.0
    let parameters = [
      "104", number(a), number(b), number(c), number(d), number(e), number(f), "0",
      number(encodedStart.u), number(encodedStart.v),
      number(encodedEnd.u), number(encodedEnd.v),
    ]
    return try table.add(
      type: 104,
      form: 1,
      label: "PCONIC",
      parameters: parameters.joined(separator: ",") + ";"
    , using: &execution)
  }

  private func parameterBSplineEntity(
    _ curve: BSplineCurve2D,
    surface: Surface3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    try curve.validate(tolerance: tolerance, using: &execution)
    guard case .closed(let lower, let upper) = curve.domain else {
      throw exchangeError(.invalidInput, "IGES p-curve B-spline requires a finite domain.")
    }
    var values = [
      "126",
      "\(curve.controlPointCount - 1)",
      "\(curve.degree)",
      boolean(false),
      boolean(false),
      boolean(!curve.isRational),
      boolean(false),
    ]
    values.append(contentsOf: curve.knots.map(number))
    values.append(contentsOf: curve.weights.map(number))
    for point in curve.controlPoints {
      let encoded = try ExactSurfaceParameterCodec.encode(
        SurfaceParameter(u: point.x, v: point.y),
        on: surface,
        unit: unit,
        convention: .iges
      )
      values.append(contentsOf: [number(encoded.u), number(encoded.v), "0"])
    }
    values.append(contentsOf: [number(lower), number(upper), "0", "0", "1"])
    return try table.add(
      type: 126,
      form: 0,
      label: "PCNURBS",
      parameters: values.joined(separator: ",") + ";"
    , using: &execution)
  }

  private func circularArcParameters(
    modelStart: Point3D,
    modelEnd: Point3D,
    unit: LengthUnit
  ) -> String {
    [
      "100",
      "0",
      "0",
      "0",
      number(unit.fromInternal(modelStart.x)),
      number(unit.fromInternal(modelStart.y)),
      number(unit.fromInternal(modelEnd.x)),
      number(unit.fromInternal(modelEnd.y)),
    ].joined(separator: ",") + ";"
  }

  private func circularArcEntity(
    center: Point3D,
    normal: Vector3D,
    reference: Vector3D,
    label: String,
    modelStart: Point3D,
    modelEnd: Point3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let yAxis = try normal.cross(reference).normalized(
      tolerance: tolerance.distance
    )
    let transformation = try transformationEntity(
      origin: center,
      xAxis: reference,
      yAxis: yAxis,
      zAxis: normal,
      unit: unit,
      table: &table, using: &execution
    )
    let startOffset = modelStart - center
    let endOffset = modelEnd - center
    let localStart = Point3D(
      x: startOffset.dot(reference),
      y: startOffset.dot(yAxis),
      z: 0.0
    )
    let localEnd = Point3D(
      x: endOffset.dot(reference),
      y: endOffset.dot(yAxis),
      z: 0.0
    )
    return try table.add(
      type: 100,
      form: 0,
      label: label,
      transformationPointer: transformation,
      parameters: circularArcParameters(
        modelStart: localStart,
        modelEnd: localEnd,
        unit: unit
      )
    , using: &execution)
  }

  private func analyticCurveEntity(
    _ curve: AnalyticCurve3D,
    edge: Edge,
    start: Point3D,
    end: Point3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> (pointer: Int, sameSense: Bool) {
    switch curve {
    case .line(_, let direction):
      let signedSpan = (end - start).dot(direction)
      guard abs(signedSpan) > tolerance.distance else {
        throw exchangeError(
          .topologyFailure, "IGES analytic line is inconsistent with its vertices.")
      }
      return (
        try table.add(
          type: 110,
          form: 0,
          label: "ANALINE",
          parameters: lineParameters(
            start: signedSpan > 0.0 ? start : end,
            end: signedSpan > 0.0 ? end : start,
            unit: unit
          )
        , using: &execution),
        signedSpan > 0.0
      )
    case .circle(let center, let normal, _):
      let trim = try requiredPeriodicTrim(edge, label: "analytic circle")
      let sameSense = trim.endParameter > trim.startParameter
      let basis = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance)
      return (
        try circularArcEntity(
          center: center,
          normal: normal,
          reference: basis.u,
          label: "ANACIRCL",
          modelStart: sameSense ? start : end,
          modelEnd: sameSense ? end : start,
          unit: unit,
          table: &table, using: &execution
        ),
        sameSense
      )
    case .arc(let center, let normal, _, let startAngle, let endAngle):
      guard let trim = edge.trim,
        trim.startParameter >= startAngle - tolerance.angle,
        trim.startParameter <= endAngle + tolerance.angle,
        trim.endParameter >= startAngle - tolerance.angle,
        trim.endParameter <= endAngle + tolerance.angle,
        abs(trim.endParameter - trim.startParameter) > tolerance.angle,
        abs(trim.endParameter - trim.startParameter)
          < 2.0 * Double.pi - tolerance.angle
      else {
        throw exchangeError(
          .topologyFailure,
          "IGES analytic arc requires a finite sub-period trim inside its arc domain."
        )
      }
      let sameSense = trim.endParameter > trim.startParameter
      let basis = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance)
      return (
        try circularArcEntity(
          center: center,
          normal: normal,
          reference: basis.u,
          label: "ANAARC",
          modelStart: sameSense ? start : end,
          modelEnd: sameSense ? end : start,
          unit: unit,
          table: &table, using: &execution
        ),
        sameSense
      )
    case .ellipse(let center, let normal, let majorAxis, let majorRadius, let minorRadius):
      let trim = try requiredPeriodicTrim(edge, label: "analytic ellipse")
      let sameSense = trim.endParameter > trim.startParameter
      let minorAxis = try normal.cross(majorAxis).normalized(
        tolerance: tolerance.distance
      )
      let transformation = try transformationEntity(
        origin: center,
        xAxis: majorAxis,
        yAxis: minorAxis,
        zAxis: normal,
        unit: unit,
        table: &table, using: &execution
      )
      let modelStart = sameSense ? start : end
      let modelEnd = sameSense ? end : start
      let startOffset = modelStart - center
      let endOffset = modelEnd - center
      let localStart = Point2D(x: startOffset.dot(majorAxis), y: startOffset.dot(minorAxis))
      let localEnd = Point2D(x: endOffset.dot(majorAxis), y: endOffset.dot(minorAxis))
      let major = unit.fromInternal(majorRadius)
      let minor = unit.fromInternal(minorRadius)
      let parameters =
        [
          "104",
          number(minor * minor),
          "0",
          number(major * major),
          "0",
          "0",
          number(-major * major * minor * minor),
          "0",
          number(unit.fromInternal(localStart.x)),
          number(unit.fromInternal(localStart.y)),
          number(unit.fromInternal(localEnd.x)),
          number(unit.fromInternal(localEnd.y)),
        ].joined(separator: ",") + ";"
      return (
        try table.add(
          type: 104,
          form: 1,
          label: "ANAELIPS",
          transformationPointer: transformation,
          parameters: parameters
        , using: &execution),
        sameSense
      )
    case .hyperbola(let curve):
      guard let trim = edge.trim,
        trim.startParameter.isFinite,
        trim.endParameter.isFinite,
        abs(trim.endParameter - trim.startParameter) > tolerance.relative
      else {
        throw exchangeError(
          .topologyFailure,
          "IGES hyperbola edges require a finite nonzero trim."
        )
      }
      let sameSense = trim.endParameter > trim.startParameter
      let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
        tolerance: tolerance.distance
      )
      let transformation = try transformationEntity(
        origin: curve.center,
        xAxis: curve.transverseAxis,
        yAxis: conjugateAxis,
        zAxis: curve.normal,
        unit: unit,
        table: &table, using: &execution
      )
      let modelStart = sameSense ? start : end
      let modelEnd = sameSense ? end : start
      let startOffset = modelStart - curve.center
      let endOffset = modelEnd - curve.center
      let transverse = unit.fromInternal(curve.transverseRadius)
      let conjugate = unit.fromInternal(curve.conjugateRadius)
      let parameters =
        [
          "104",
          number(conjugate * conjugate),
          "0",
          number(-(transverse * transverse)),
          "0",
          "0",
          number(-(transverse * transverse * conjugate * conjugate)),
          "0",
          number(unit.fromInternal(startOffset.dot(curve.transverseAxis))),
          number(unit.fromInternal(startOffset.dot(conjugateAxis))),
          number(unit.fromInternal(endOffset.dot(curve.transverseAxis))),
          number(unit.fromInternal(endOffset.dot(conjugateAxis))),
        ].joined(separator: ",") + ";"
      return (
        try table.add(
          type: 104,
          form: 2,
          label: "ANAHYPER",
          transformationPointer: transformation,
          parameters: parameters
        , using: &execution),
        sameSense
      )
    case .parabola(let curve):
      guard let trim = edge.trim,
        trim.startParameter.isFinite,
        trim.endParameter.isFinite,
        abs(trim.endParameter - trim.startParameter) > tolerance.distance
      else {
        throw exchangeError(
          .topologyFailure,
          "IGES parabola edges require a finite nonzero trim."
        )
      }
      let sameSense = trim.endParameter > trim.startParameter
      let transverseAxis = try curve.normal.cross(curve.axis).normalized(
        tolerance: tolerance.distance
      )
      let transformation = try transformationEntity(
        origin: curve.vertex,
        xAxis: curve.axis,
        yAxis: transverseAxis,
        zAxis: curve.normal,
        unit: unit,
        table: &table, using: &execution
      )
      let modelStart = sameSense ? start : end
      let modelEnd = sameSense ? end : start
      let startOffset = modelStart - curve.vertex
      let endOffset = modelEnd - curve.vertex
      let parameters =
        [
          "104",
          "0",
          "0",
          "1",
          number(-4.0 * unit.fromInternal(curve.focalLength)),
          "0",
          "0",
          "0",
          number(unit.fromInternal(startOffset.dot(curve.axis))),
          number(unit.fromInternal(startOffset.dot(transverseAxis))),
          number(unit.fromInternal(endOffset.dot(curve.axis))),
          number(unit.fromInternal(endOffset.dot(transverseAxis))),
        ].joined(separator: ",") + ";"
      return (
        try table.add(
          type: 104,
          form: 3,
          label: "ANAPARAB",
          transformationPointer: transformation,
          parameters: parameters
        , using: &execution),
        sameSense
      )
    case .planeTorus:
      throw exchangeError(
        .unsupportedCapability,
        "IGES plane-torus intersection transfer requires an exact curve-on-surface entity writer."
      )
    }
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
        "IGES \(label) edge requires a finite trim shorter than one period."
      )
    }
    return trim
  }

  private func transformationEntity(
    origin: Point3D,
    xAxis: Vector3D,
    yAxis: Vector3D,
    zAxis: Vector3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let transformation = try IGESTransformation(
      xAxis: xAxis,
      yAxis: yAxis,
      zAxis: zAxis,
      translation: origin,
      tolerance: tolerance
    )
    let values = [
      "124",
      number(transformation.xAxis.x),
      number(transformation.yAxis.x),
      number(transformation.zAxis.x),
      number(unit.fromInternal(transformation.translation.x)),
      number(transformation.xAxis.y),
      number(transformation.yAxis.y),
      number(transformation.zAxis.y),
      number(unit.fromInternal(transformation.translation.y)),
      number(transformation.xAxis.z),
      number(transformation.yAxis.z),
      number(transformation.zAxis.z),
      number(unit.fromInternal(transformation.translation.z)),
    ]
    return try table.add(
      type: 124,
      form: 0,
      label: "XFORM",
      parameters: values.joined(separator: ",") + ";"
    , using: &execution)
  }

  private func bSplineCurveParameters(
    _ curve: BSplineCurve3D,
    startParameter: Double,
    endParameter: Double,
    unit: LengthUnit
  ) -> String {
    var values = [
      "126",
      "\(curve.controlPointCount - 1)",
      "\(curve.degree)",
      boolean(false),
      boolean(false),
      boolean(!curve.isRational),
      boolean(false),
    ]
    values.append(contentsOf: curve.knots.map(number))
    values.append(contentsOf: curve.weights.map(number))
    for point in curve.controlPoints {
      values.append(contentsOf: coordinates(point, unit: unit))
    }
    values.append(number(startParameter))
    values.append(number(endParameter))
    values.append(contentsOf: ["0", "0", "1"])
    return values.joined(separator: ",") + ";"
  }

  private func bSplineSurfaceParameters(
    _ surface: BSplineSurface3D,
    unit: LengthUnit
  ) -> String {
    var values = [
      "128",
      "\(surface.uControlPointCount - 1)",
      "\(surface.vControlPointCount - 1)",
      "\(surface.uDegree)",
      "\(surface.vDegree)",
      boolean(false),
      boolean(false),
      boolean(!surface.isRational),
      boolean(false),
      boolean(false),
    ]
    values.append(contentsOf: surface.uKnots.map(number))
    values.append(contentsOf: surface.vKnots.map(number))
    for row in surface.weights {
      values.append(contentsOf: row.map(number))
    }
    for row in surface.controlPoints {
      for point in row {
        values.append(contentsOf: coordinates(point, unit: unit))
      }
    }
    if case .closed(let uLower, let uUpper) = surface.uDomain,
      case .closed(let vLower, let vUpper) = surface.vDomain
    {
      values.append(contentsOf: [number(uLower), number(uUpper), number(vLower), number(vUpper)])
    }
    return values.joined(separator: ",") + ";"
  }

  private func exactSurfaceEntity(
    _ surface: Surface3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    if !surfaceOverrides.isEmpty {
      try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
      if let converted = surfaceOverrides[surface] {
        return try table.add(type: 128, form: 0, label: "SURFACE", parameters: bSplineSurfaceParameters(converted, unit: unit), using: &execution)
      }
    }
    switch surface {
    case .plane(let plane):
      let point = try table.add(
        type: 116,
        form: 0,
        label: "ORIGIN",
        parameters: pointParameters(plane.origin, unit: unit)
      , using: &execution)
      let normal = try table.add(
        type: 123,
        form: 0,
        label: "NORMAL",
        parameters: directionParameters(plane.normal)
      , using: &execution)
      let frame = try surface.differentialGeometry(
        u: 0.0,
        v: 0.0,
        tolerance: tolerance
      )
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(frame.tangentU)
      , using: &execution)
      return try table.add(
        type: 190,
        form: 1,
        label: "PLANE",
        parameters: "190,\(point),\(normal),\(reference);"
      , using: &execution)
    case .bSpline(let bSpline):
      return try table.add(
        type: 128,
        form: 0,
        label: "NURBSSRF",
        parameters: bSplineSurfaceParameters(bSpline, unit: unit)
      , using: &execution)
    case .cylinder(let cylinder):
      let point = try table.add(
        type: 116,
        form: 0,
        label: "ORIGIN",
        parameters: pointParameters(cylinder.origin, unit: unit)
      , using: &execution)
      let axis = try table.add(
        type: 123,
        form: 0,
        label: "AXIS",
        parameters: directionParameters(cylinder.axis)
      , using: &execution)
      let frame = try surface.differentialGeometry(
        u: 0.0,
        v: 0.0,
        tolerance: tolerance
      )
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(frame.normal)
      , using: &execution)
      return try table.add(
        type: 192,
        form: 1,
        label: "CYLINDER",
        parameters:
          "192,\(point),\(axis),\(number(unit.fromInternal(cylinder.radius))),\(reference);"
      , using: &execution)
    case .analytic(let analytic):
      return try analyticSurfaceEntity(analytic, unit: unit, table: &table, using: &execution)
    case .procedural(.originalImage):
      var producer = try IndependentProducer(writer:self, using: execution)
      producer.table = table
      // The original primitive producer emits its actual chart and spatial defining matrix.
      let entity = try producer.originalSurfaceEntity(surface,label:"",units:UnitSystem(length:unit,angle:.radian), using: &execution)
      table = producer.table
      return entity
    case .procedural(.offset(let offset)):
      if abs(offset.distance) <= tolerance.distance {
        return try exactSurfaceEntity(
          offset.source,
          unit: unit,
          table: &table, using: &execution
        )
      }
      let basis = try exactSurfaceEntity(
        offset.source,
        unit: unit,
        table: &table, using: &execution
      )
      let indicator = try offsetIndicator(
        for: offset.source,
        tolerance: tolerance
      )
      return try table.add(
        type: 140,
        form: 0,
        label: "OFFSETSRF",
        parameters: [
          "140",
          number(indicator.x),
          number(indicator.y),
          number(indicator.z),
          number(unit.fromInternal(offset.distance)),
          "\(basis)",
        ].joined(separator: ",") + ";"
      , using: &execution)
    case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalAffineWord), .procedural(.originalAngularTransport), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
      let representation = try ExactExchangeSurfaceRepresentationResolver()
        .resolve(surface, tolerance: tolerance)
      guard representation != surface else {
        throw exchangeError(
          .topologyFailure,
          "IGES procedural surface resolution made no progress."
        )
      }
      return try exactSurfaceEntity(
        representation,
        unit: unit,
        table: &table, using: &execution
      )
    }
  }

  private func offsetIndicator(
    for surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> Vector3D {
    let u: Double
    let v: Double
    if case .closed(let lower, let upper) = surface.uDomain,
      case .closed(let vLower, let vUpper) = surface.vDomain
    {
      u = lower + (upper - lower) * 0.5
      v = vLower + (vUpper - vLower) * 0.5
    } else {
      u = 0.0
      v = 0.0
    }
    return try surface.normal(u: u, v: v, tolerance: tolerance)
  }

  private func pointParameters(_ point: Point3D, unit: LengthUnit) -> String {
    (["116"] + coordinates(point, unit: unit) + ["0"]).joined(separator: ",") + ";"
  }

  private func directionParameters(_ vector: Vector3D) -> String {
    ["123", number(vector.x), number(vector.y), number(vector.z)].joined(separator: ",") + ";"
  }

  private func analyticSurfaceEntity(
    _ surface: AnalyticSurface3D,
    unit: LengthUnit,
    table: inout EntityTable, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let type: Int
    let label: String
    let parameters: String
    switch surface {
    case .plane(let origin, let normal):
      let basis = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance)
      let point = try table.add(
        type: 116,
        form: 0,
        label: "ORIGIN",
        parameters: pointParameters(origin, unit: unit)
      , using: &execution)
      let axis = try table.add(
        type: 123,
        form: 0,
        label: "NORMAL",
        parameters: directionParameters(normal)
      , using: &execution)
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(basis.u)
      , using: &execution)
      type = 190
      label = "ANAPLANE"
      parameters = "190,\(point),\(axis),\(reference);"
    case .cylinder(let origin, let axis, let radius):
      let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
      let point = try table.add(
        type: 116,
        form: 0,
        label: "ORIGIN",
        parameters: pointParameters(origin, unit: unit)
      , using: &execution)
      let axisPointer = try table.add(
        type: 123,
        form: 0,
        label: "AXIS",
        parameters: directionParameters(axis)
      , using: &execution)
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(basis.u)
      , using: &execution)
      type = 192
      label = "ANACYL"
      parameters = "192,\(point),\(axisPointer),\(number(unit.fromInternal(radius))),\(reference);"
    case .cone(let apex, let axis, let halfAngle):
      let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
      let point = try table.add(
        type: 116,
        form: 0,
        label: "APEX",
        parameters: pointParameters(apex, unit: unit)
      , using: &execution)
      let axisPointer = try table.add(
        type: 123,
        form: 0,
        label: "AXIS",
        parameters: directionParameters(axis)
      , using: &execution)
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(basis.u)
      , using: &execution)
      type = 194
      label = "ANACONE"
      parameters = "194,\(point),\(axisPointer),0,\(number(halfAngle)),\(reference);"
    case .sphere(let center, let radius):
      let axis = Vector3D.unitZ
      let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
      let point = try table.add(
        type: 116,
        form: 0,
        label: "CENTER",
        parameters: pointParameters(center, unit: unit)
      , using: &execution)
      let axisPointer = try table.add(
        type: 123,
        form: 0,
        label: "AXIS",
        parameters: directionParameters(axis)
      , using: &execution)
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(basis.u)
      , using: &execution)
      type = 196
      label = "ANASPHER"
      parameters = "196,\(point),\(number(unit.fromInternal(radius))),\(axisPointer),\(reference);"
    case .torus(let center, let axis, let majorRadius, let minorRadius):
      let basis = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance)
      let point = try table.add(
        type: 116,
        form: 0,
        label: "CENTER",
        parameters: pointParameters(center, unit: unit)
      , using: &execution)
      let axisPointer = try table.add(
        type: 123,
        form: 0,
        label: "AXIS",
        parameters: directionParameters(axis)
      , using: &execution)
      let reference = try table.add(
        type: 123,
        form: 0,
        label: "REFDIR",
        parameters: directionParameters(basis.u)
      , using: &execution)
      type = 198
      label = "ANATORUS"
      parameters =
        "198,\(point),\(axisPointer),\(number(unit.fromInternal(majorRadius))),\(number(unit.fromInternal(minorRadius))),\(reference);"
    }
    return try table.add(
      type: type,
      form: 1,
      label: label,
      parameters: parameters
    , using: &execution)
  }

  private func coordinates(_ point: Point3D, unit: LengthUnit) -> [String] {
    [
      number(unit.fromInternal(point.x)),
      number(unit.fromInternal(point.y)),
      number(unit.fromInternal(point.z)),
    ]
  }

  private func boolean(_ value: Bool) -> String {
    value ? "1" : "0"
  }

  private func number(_ value: Double) -> String {
    String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private func exchangeError(_ code: KernelErrorCode, _ message: String) -> KernelError {
    KernelError(phase: .exchange, code: code, tolerance: tolerance, message: message)
  }
}

extension ExactIGESWriter {
  fileprivate struct EntityTable: Sendable {
    struct Entity: Sendable {
      let type: Int
      let form: Int
      let label: String
      let transformationPointer: Int
      let statusNumber: Int
      let parameters: String
      var associationPointers: [Int] = []
      var associationCapacity = 0
    }

    let maximumEntities: Int
    let tolerance: ModelingTolerance
    var entities: [Entity] = []
    private var entityCapacity = 0
    var independentUsage:IndependentShapeExchangeOwner?

    var maximumWork: Int = 10_000_000
    let originalBudget: OriginalQueryBudget
    private let limits: ExchangeResourceLimits
    private let processingBudget: ExchangeProcessingBudget?
    init(maximumEntities: Int, tolerance: ModelingTolerance, maximumWork: Int = 10_000_000,
      processingBudget: ExchangeProcessingBudget? = nil, originalBudget: OriginalQueryBudget? = nil,
      limits: ExchangeResourceLimits = .standard) throws {
      self.maximumEntities = maximumEntities; self.tolerance = tolerance; self.maximumWork = maximumWork
      self.processingBudget = processingBudget; self.limits = limits
      self.originalBudget = try originalBudget ?? OriginalQueryBudget(workLimit: maximumWork,
        storageByteLimit: limits.maximumBytes, recordLimit: maximumEntities, cellVisitRecords: 1,
        checkpoint: { try processingBudget?.check(format: .iges) })
    }
    func execution() throws -> OriginalQueryExecution {
      try OriginalQueryExecution(budget: originalBudget,
        limits: .init(maximumValueDepth: limits.maximumAlgebraicDepth,
          maximumCoefficientDepth: limits.maximumAlgebraicDepth,
          remainingSourceDepth: limits.maximumNesting,
          maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
          maximumSpans: maximumEntities))
    }
    func chargeGeometryWork(_ work: Int, using execution: inout OriginalQueryExecution) throws {
      guard execution.budget === originalBudget else {
        throw IndependentShapeExchangeError.invalidAssociation("IGES geometry requires its original invocation.")
      }
      try execution.consumeWork(work)
    }
    mutating func add(
      type: Int,
      form: Int,
      label: String,
      transformationPointer: Int = 0,
      statusNumber: Int = 0,
      parameters: String, using execution: inout OriginalQueryExecution
    ) throws -> Int {
      try chargeGeometryWork(0, using: &execution)
      try processingBudget?.check(format: .iges)
      if independentUsage != nil {
        guard label.utf8.count <= 8, label.utf8.allSatisfy({ $0 < 128 }) else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Independent IGES long/encoded directory labels need actual standard name-property transport.
          // Retain the full original label instead of truncating it before this public egress family succeeds.
          throw IndependentShapeExchangeError.metadataLoss("IGES directory label exceeds the retained ASCII eight-byte field.")
        }
        try execution.chargeSource(work:parameters.utf8.count+label.utf8.count+1)
      }
      guard originalBudget.snapshot.records < maximumEntities else {
        throw KernelError(
          phase: .exchange,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "IGES output exceeds the configured entity limit."
        )
      }
      let wireRecords = 2 + (parameters.utf8.count + 63) / 64
      try execution.chargeSource(records: 1, storageBytes: wireRecords * 81)
      if entities.count == entityCapacity {
          let doubled = entityCapacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let next = max(1, doubled.partialValue)
          try execution.retainStorage(count: next, stride: MemoryLayout<Entity>.stride)
          entities.reserveCapacity(next)
          entityCapacity = next
        }
      entities.append(
        Entity(
          type: type,
          form: form,
          label: label,
          transformationPointer: transformationPointer,
          statusNumber: statusNumber,
          parameters: parameters
        ))
      return entities.count * 2 - 1
    }

    mutating func appendGroupBackPointer(groupPointer:Int,memberPointer:Int, using execution: inout OriginalQueryExecution) throws {
      try chargeGeometryWork(0, using: &execution)
      guard groupPointer > 0, memberPointer > 0, groupPointer % 2 == 1, memberPointer % 2 == 1,
            groupPointer / 2 < entities.count, memberPointer / 2 < entities.count,
            entities[groupPointer / 2].type == 402,
            [1,7,14,15].contains(entities[groupPointer / 2].form) else {
        throw IndependentShapeExchangeError.invalidAssociation("IGES inverse pointer requires actual emitted member and group entities.")
      }
      let index = memberPointer / 2
      let nextCount = entities[index].associationPointers.count.addingReportingOverflow(1)
      guard !nextCount.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("IGES inverse pointer count overflows.") }
      guard try !entities[index].associationPointers.contains(where: { pointer in
        try execution.consumeWork(1)
        return pointer == groupPointer
      }) else {
        throw IndependentShapeExchangeError.invalidAssociation("Duplicate emitted IGES inverse pointer.")
      }
      let size = nextCount.partialValue.multipliedReportingOverflow(by:MemoryLayout<Int>.stride)
      guard !size.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("IGES inverse pointer storage overflow.") }
      try execution.chargeSource(records: 1)
      var capacity = entities[index].associationCapacity
      if entities[index].associationPointers.count == capacity {
          let doubled = capacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let next = max(1, doubled.partialValue)
          try execution.retainStorage(count: next, stride: MemoryLayout<Int>.stride)
          entities[index].associationPointers.reserveCapacity(next)
          capacity = next
        }
      entities[index].associationCapacity = capacity
      entities[index].associationPointers.append(groupPointer)
    }

    mutating func retainAssociationParameterTails(using execution: inout OriginalQueryExecution) throws {
      try chargeGeometryWork(0, using: &execution)
      for index in entities.indices where !entities[index].associationPointers.isEmpty {
        let original = entities[index]
        let addition = original.associationPointers.count.multipliedReportingOverflow(by:21)
        let framing = original.parameters.utf8.count.addingReportingOverflow(24)
        let capacity = addition.partialValue.addingReportingOverflow(framing.partialValue)
        guard !addition.overflow, !framing.overflow, !capacity.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("IGES inverse parameter extent overflow.") }
        let rounded = capacity.partialValue.addingReportingOverflow(63)
        guard !rounded.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("IGES tail record extent overflow.") }
        let records = (rounded.partialValue/64).multipliedReportingOverflow(by:81)
        let bytes = records.partialValue.addingReportingOverflow(capacity.partialValue)
        guard !records.overflow, !bytes.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("IGES tail record storage overflow.") }
        try execution.retainStorage(bytes: capacity.partialValue)
        try execution.consumeWork(original.parameters.utf8.count)
        guard original.parameters.last == ";" else { throw IndependentShapeExchangeError.invalidAssociation("IGES base parameter delimiter is absent.") }
        var parameters = ""
        parameters.reserveCapacity(capacity.partialValue)
        parameters += original.parameters.dropLast()
        parameters += ",\(original.associationPointers.count)"
        for pointer in original.associationPointers {
          let token = String(pointer)
          try execution.consumeWork(token.utf8.count + 1)
          parameters += "," + token
        }
        parameters += ",0;"
        entities[index] = .init(type:original.type,form:original.form,label:original.label,
          transformationPointer:original.transformationPointer,statusNumber:original.statusNumber,parameters:parameters)
      }
    }

    func serializedFramingByteCount(unit:LengthUnit, using execution: inout OriginalQueryExecution) throws -> Int {
      try execution.consumeWork(1)

      let globalRecords = (try globalParameters(unit:unit, using: &execution).utf8.count+71)/72
      return (globalRecords+2)*81-1
    }

    func serialize(unit: LengthUnit, maximumBytes: Int, using execution: inout OriginalQueryExecution) throws -> Data {
      try chargeGeometryWork(0, using: &execution)
      if independentUsage == nil {
        try execution.retainSourceStorage(bytes: try serializedFramingByteCount(unit: unit, using: &execution))
      }
      let startRecords = try sectionRecords("SwiftCAD exact B-rep", section: "S", using: &execution)
      let globalRecords = try sectionRecords(try globalParameters(unit: unit, using: &execution), section: "G", using: &execution)
      var directoryRecords: [String] = []
      var parameterRecords: [String] = []
      var directoryCapacity = 0
      var parameterCapacity = 0
      var parameterSequence = 1
      for (offset, entity) in entities.enumerated() {
        try processingBudget?.check(format: .iges)
        let entityIndex = offset + 1
        let directoryPointer = entityIndex * 2 - 1
        let records = try parameterSectionRecords(
          entity.parameters,
          directoryPointer: directoryPointer,
          startSequence: parameterSequence
        , using: &execution)
        let directory = try directorySectionRecords(
            entity: entity,
            parameterPointer: parameterSequence,
            parameterLineCount: records.count,
            entityIndex: entityIndex, using: &execution)
        for record in directory {
          try execution.consumeWork(1)
          if directoryRecords.count == directoryCapacity {
          let doubled = directoryCapacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let next = max(1, doubled.partialValue)
          try execution.retainStorage(count: next, stride: MemoryLayout<String>.stride)
          directoryRecords.reserveCapacity(next)
          directoryCapacity = next
        }
          directoryRecords.append(record)
        }
        for record in records {
          try execution.consumeWork(1)
          if parameterRecords.count == parameterCapacity {
          let doubled = parameterCapacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let next = max(1, doubled.partialValue)
          try execution.retainStorage(count: next, stride: MemoryLayout<String>.stride)
          parameterRecords.reserveCapacity(next)
          parameterCapacity = next
        }
          parameterRecords.append(record)
        }
        parameterSequence += records.count
      }
      let terminate = try terminateRecord(
        startCount: startRecords.count,
        globalCount: globalRecords.count,
        directoryCount: directoryRecords.count,
        parameterCount: parameterRecords.count
      , using: &execution)
      var outputBytes = 0
      var outputRecords = 0
      try execution.retainStorage(count: 4, stride: MemoryLayout<[String]>.stride)
      for records in [startRecords, globalRecords, directoryRecords, parameterRecords] {
        for record in records {
          try execution.consumeWork(1)
          let bytes = outputBytes.addingReportingOverflow(record.utf8.count)
          let count = outputRecords.addingReportingOverflow(1)
          guard !bytes.overflow, !count.overflow else { throw ExactScalarFailure.countOverflow }
          outputBytes = bytes.partialValue; outputRecords = count.partialValue
        }
      }
      let tail = outputBytes.addingReportingOverflow(terminate.utf8.count)
      let framing = tail.partialValue.addingReportingOverflow(outputRecords)
      guard !tail.overflow, !framing.overflow else { throw ExactScalarFailure.countOverflow }
      outputBytes = framing.partialValue
      guard outputBytes <= maximumBytes else {
        throw KernelError(phase: .exchange, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "IGES output exceeds the configured byte limit.")
      }
      try execution.retainStorage(bytes: outputBytes)
      var text = ""
      text.reserveCapacity(outputBytes)
      try execution.retainStorage(count: 4, stride: MemoryLayout<[String]>.stride)
      for records in [startRecords, globalRecords, directoryRecords, parameterRecords] {
        for record in records {
          try execution.consumeWork(record.utf8.count + 1)
          text += record; text += "\n"
        }
      }
      text += terminate
      try execution.retainStorage(bytes: outputBytes)
      let data = Data(text.utf8)
      guard data.count <= maximumBytes else {
        throw KernelError(
          phase: .exchange,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "IGES output exceeds the configured byte limit."
        )
      }
      return data
    }

    private func globalParameters(unit: LengthUnit, using execution: inout OriginalQueryExecution) throws -> String {
      try execution.consumeWork(1)
      try execution.retainStorage(count: 26, stride: MemoryLayout<String>.stride)
      return [
        "1H,", "1H;", hollerith("SWFT"), hollerith("swiftcad-exact.igs"),
        hollerith("Swift-CAD"), hollerith("Swift-CAD"),
        "32", "38", "6", "308", "15", "1.0", "2", "\(unitFlag(unit))",
        hollerith(unitName(unit)), "1", "0.001", "15H20000101.000000", "1.0E-9", "0.0",
        "8HSwiftCAD", "9HSwift-CAD", "11", "0", "15H20000101.000000",
      ].joined(separator: ",") + ";"
    }

    private func directorySectionRecords(
      entity: Entity,
      parameterPointer: Int,
      parameterLineCount: Int,
      entityIndex: Int
    , using execution: inout OriginalQueryExecution) throws -> [String] {
      try execution.consumeWork(1)

      try execution.retainStorage(count: 18, stride: MemoryLayout<String>.stride)
      let first = [
        integer(entity.type), integer(parameterPointer), integer(0), integer(0), integer(0),
        integer(0), integer(entity.transformationPointer), integer(0), status(entity.statusNumber),
      ].joined()
      let second = [
        integer(entity.type), integer(0), integer(0), integer(parameterLineCount),
        integer(entity.form),
        integer(0), integer(0), text(entity.label), integer(entityIndex),
      ].joined()
      try execution.retainStorage(count: 2, stride: MemoryLayout<String>.stride)
      return [
        try record(first, section: "D", sequence: entityIndex * 2 - 1, using: &execution),
        try record(second, section: "D", sequence: entityIndex * 2, using: &execution),
      ]
    }

    private func parameterSectionRecords(
      _ data: String,
      directoryPointer: Int,
      startSequence: Int
    , using execution: inout OriginalQueryExecution) throws -> [String] {
      try execution.consumeWork(1)

      try execution.retainStorage(count: data.count, stride: MemoryLayout<Character>.stride)
      let characters = Array(data)
      var records: [String] = []
      var recordCapacity = 0
      var offset = 0
      var sequence = startSequence
      while offset < characters.count {
        try execution.consumeWork(1)
        if records.count == recordCapacity {
          let doubled = recordCapacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let next = max(1, doubled.partialValue)
          try execution.retainStorage(count: next, stride: MemoryLayout<String>.stride)
          records.reserveCapacity(next)
          recordCapacity = next
        }
        let end = min(offset + 64, characters.count)
        let chunk = String(characters[offset..<end])
        records.append(
          try record(
            chunk.padding(toLength: 64, withPad: " ", startingAt: 0) + integer(directoryPointer),
            section: "P",
            sequence: sequence
          , using: &execution))
        offset = end
        sequence += 1
      }
      return records
    }

    private func sectionRecords(_ content: String, section: Character, using execution: inout OriginalQueryExecution) throws -> [String] {
      try execution.consumeWork(1)

      try execution.retainStorage(count: content.count, stride: MemoryLayout<Character>.stride)
      let characters = Array(content)
      var records: [String] = []
      var recordCapacity = 0
      var offset = 0
      var sequence = 1
      repeat {
        try execution.consumeWork(1)
        if records.count == recordCapacity {
          let doubled = recordCapacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let next = max(1, doubled.partialValue)
          try execution.retainStorage(count: next, stride: MemoryLayout<String>.stride)
          records.reserveCapacity(next)
          recordCapacity = next
        }
        let end = min(offset + 72, characters.count)
        records.append(
          try record(String(characters[offset..<end]), section: section, sequence: sequence, using: &execution))
        offset = end
        sequence += 1
      } while offset < characters.count
      return records
    }

    private func terminateRecord(
      startCount: Int,
      globalCount: Int,
      directoryCount: Int,
      parameterCount: Int
    , using execution: inout OriginalQueryExecution) throws -> String {
      try execution.consumeWork(1)

      let content =
        "S\(integer(startCount).dropFirst())G\(integer(globalCount).dropFirst())D\(integer(directoryCount).dropFirst())P\(integer(parameterCount).dropFirst())"
      return try record(content, section: "T", sequence: 1, using: &execution)
    }

    private func record(_ content: String, section: Character, sequence: Int, using execution: inout OriginalQueryExecution) throws -> String {
      try execution.consumeWork(1)
      try execution.retainStorage(bytes: 80)
      return String(content.prefix(72)).padding(toLength: 72, withPad: " ", startingAt: 0)
        + String(section)
        + String(format: "%7d", locale: Locale(identifier: "en_US_POSIX"), sequence)
    }

    private func status(_ value: Int) -> String {
      String(format: "%08d", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func integer(_ value: Int) -> String {
      String(format: "%8d", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func text(_ value: String) -> String {
      String(value.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    private func hollerith(_ value: String) -> String {
      "\(value.count)H\(value)"
    }

    private func unitFlag(_ unit: LengthUnit) -> Int {
      switch unit {
      case .inch: 1
      case .millimeter: 2
      case .foot: 4
      case .meter: 6
      case .kilometer: 7
      case .micrometer: 9
      case .centimeter: 10
      }
    }

    private func unitName(_ unit: LengthUnit) -> String {
      switch unit {
      case .micrometer: "MICRON"
      case .meter: "M"
      case .millimeter: "MM"
      case .centimeter: "CM"
      case .kilometer: "KM"
      case .inch: "IN"
      case .foot: "FT"
      }
    }
  }
}
