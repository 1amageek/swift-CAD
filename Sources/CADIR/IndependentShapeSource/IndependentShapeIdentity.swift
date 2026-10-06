import CADCore

/// Distinct source identity domains for selections, memberships and placements.
public enum IndependentShapeIdentity {
    public enum ItemTag {}
    public enum GroupTag {}
    public enum STEPGroupTag {}
    public enum InstanceTag {}
    public enum SetTag {}
    public enum ContextTag {}
    public enum RepresentationTag {}
    public enum DefinitionTag {}
    public enum FrameTag {}
    public enum AngularUnitTag {}
    public enum AngularMeasureTag {}
    public enum AngularDimensionsTag {}
}
public typealias IndependentShapeItemID = TaggedID<IndependentShapeIdentity.ItemTag>
public typealias IndependentShapeGroupID = TaggedID<IndependentShapeIdentity.GroupTag>
public typealias IndependentShapeSTEPGroupID = TaggedID<IndependentShapeIdentity.STEPGroupTag>
public typealias IndependentShapeInstanceID = TaggedID<IndependentShapeIdentity.InstanceTag>

public typealias IndependentShapeSetID = TaggedID<IndependentShapeIdentity.SetTag>
public typealias IndependentShapeContextID = TaggedID<IndependentShapeIdentity.ContextTag>
public typealias IndependentShapeRepresentationID = TaggedID<IndependentShapeIdentity.RepresentationTag>
public typealias IndependentShapeDefinitionID = TaggedID<IndependentShapeIdentity.DefinitionTag>

public typealias IndependentShapeFrameID = TaggedID<IndependentShapeIdentity.FrameTag>

public typealias IndependentShapeAngularUnitID = TaggedID<IndependentShapeIdentity.AngularUnitTag>
public typealias IndependentShapeAngularMeasureID = TaggedID<IndependentShapeIdentity.AngularMeasureTag>
public typealias IndependentShapeAngularDimensionsID = TaggedID<IndependentShapeIdentity.AngularDimensionsTag>
