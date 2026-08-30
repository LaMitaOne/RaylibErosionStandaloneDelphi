unit ModelEngine;

{==============================================================================*
 *  ModelEngine - actor layer combining r3d rendering with Kraft physics        *
 *                                                                              *
 *  Core idea: every visible/gameplay object is a TModelActor that owns         *
 *    - a Kraft rigid body + shape (physics), and                              *
 *    - an optional r3d model (rendering).                                     *
 *                                                                              *
 *  TModelEngine owns the actor list and the physics world. Each frame:         *
 *    Update(DeltaTime) -> step physics, then let every living actor sync       *
 *    its transform from its body and run its own logic.                        *
 *    Render()          -> draws all visible, alive actors (call this between   *
 *                         R3D_Begin and R3D_End).                              *
 *                                                                              *
 *  Kraft's low-level contact callbacks are translated here into per-actor      *
 *  events (OnCollision / OnCollisionEnter / OnCollisionExit), and each         *
 *  actor's UserData points back at itself, so physics rays and contacts        *
 *  can always be traced back to the owning actor.                              *
 *                                                                              *
 *  Class hierarchy:                                                            *
 *    TModelActor            physics body + optional static model               *
 *      TStaticModelActor    convenience: krbtSTATIC                            *
 *      TDynamicModelActor   convenience: krbtDYNAMIC                           *
 *        TAnimatedModelActor  plays skeletal animations (r3d player)           *
 *          TActionActor     character base with update hooks; the game         *
 *                           derives TPlayerActor / TZombieActor from it        *
 *      TSimpleActionActor   directly velocity-controlled mover (boxes, balls)  *
 *                                                                              *
 *  NOTE: for mesh collision shapes (kstMesh) the model must be loaded with     *
 *  R3D_IMPORT_RETAIN_MESH_DATA - this unit does that automatically.            *
 *==============================================================================}

{$POINTERMATH ON}

interface

uses
  Raylib, rlgl, Classes, SysUtils, Contnrs, Kraft, KraftConvert, RayMath, Math,
  r3ddelphi;   // rename to 'r3d' if you use the released single-unit binding

type
  TModelActor = class;

  // Collision event: fires continuously while two actors touch
  TCollisionEvent = procedure(Sender: TModelActor; Other: TModelActor; const ContactPoint: TVector3; const Normal: TVector3) of object;

  // Collision begin/end events: fire exactly once per contact pair
  TCollisionStateEvent = procedure(Sender: TModelActor; Other: TModelActor) of object;

  { TModelEngine }
  TModelEngine = class
  private
    FActorList: TObjectList;
    FPhysics: TKraft;
    function GetCount: integer;
    function GetModelActor(const Index: integer): TModelActor;
    // Internal Kraft contact callbacks, mapped to per-actor events
    procedure OnContactBegin(const ContactPair: PKraftContactPair);
    procedure OnContactEnd(const ContactPair: PKraftContactPair);
    procedure OnContactStay(const ContactPair: PKraftContactPair);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ModelActor: TModelActor);
    procedure Remove(const ModelActor: TModelActor);
    procedure Update(DeltaTime: single);
    procedure Render;
    procedure Clear;
    property Items[const Index: integer]: TModelActor read GetModelActor; default;
    property Count: integer read GetCount;
    property Physics: TKraft read FPhysics;
  end;

  { TModelActor }
  TModelActor = class
  protected
    // Protected fields - accessible to descendants
    FBody: TKraftRigidBody;
    FShape: TKraftShape;
    FMeshShape: TKraftShapeMesh;
    FModel: TR3D_Model;
    FModelLoaded: boolean;
    FEngine: TModelEngine;
    FCapsuleRadius: Single;
    FCapsuleHeight: Single;
  private
    FCamLayer: TR3D_Layer;
    FIsDead: boolean;
    FName: string;
    FVisible: boolean;
    FPosition: TVector3;
    FScale: TVector3;
    FRotation: TVector3;
    FQuaternion: TQuaternion;
    FModelOffset: TVector3;
    FModelTransform: TMatrix;
    FTint: TColor;
    FMass: single;
    FDensity: single;
    // Collision events
    FOnCollision: TCollisionEvent;
    FOnCollisionEnter: TCollisionStateEvent;
    FOnCollisionExit: TCollisionStateEvent;
    // Actors we currently touch
    FContacts: TList;
    // Helpers
    function GetFriction: single;
    function GetRestitution: single;
    procedure SetEngine(AValue: TModelEngine);
    function GetTransformMatrix: PMatrix;
    procedure SetFriction(AValue: single);
    procedure SetRestitution(AValue: single);
    procedure UpdatePhysicsRotation;
    procedure UpdateMassProperties;
    procedure CreateMeshShape(ASize: TVector3);
    procedure LoadR3DModel(const APath: string; CreateCollider: boolean = False);
    procedure UnloadR3DModel;
    procedure UpdateModelTransform;

    // Internal collision bookkeeping
    procedure InternalAddContact(Other: TModelActor);
    procedure InternalRemoveContact(Other: TModelActor);
    procedure InternalProcessContact(Other: TModelActor; const ContactPoint: TVector3; const Normal: TVector3);
  public
    constructor Create(AModelPath: string; AParent: TModelEngine; AShapeType: TKraftShapeType;
      ASize: TVector3; ARigidBodyType: TKraftRigidBodyType = krbtDYNAMIC);
    destructor Destroy; override;
    function Vec3ToKraft(const V: TVector3): TKraftVector3;
    function KraftToVec3(const V: TKraftVector3): TVector3;
    procedure Update(DeltaTime: single); virtual;
    procedure UpdateRotationFromPhysics;
    procedure Draw; virtual;
    procedure Dead; virtual;
    procedure SetPosition(APosition: TVector3);
    procedure SetRotation(ARotation: TVector3); overload;
    procedure SetRotation(AQuaternion: TQuaternion); overload;
    procedure SetModelOffset(AOffset: TVector3);
    procedure SetMass(AMass: single);
    procedure SetDensity(ADensity: single);
    procedure ApplyForce(AForce: TVector3);
    procedure ApplyImpulse(AImpulse: TVector3);
    procedure ApplyTorque(ATorque: TVector3);
    procedure ApplyAngularImpulse(AImpulse: TVector3);
    procedure SetOrientationRadians(AXRotation, AYRotation, AZRotation: single);
    procedure AddOrientationRadians(AXRotation, AYRotation, AZRotation: single);
    procedure SetOrientationDegrees(AXRotation, AYRotation, AZRotation: single);
    procedure AddOrientationDegrees(AXRotation, AYRotation, AZRotation: single);
    function GetPosition: TVector3;
    function GetRotation: TVector3;
    function GetQuaternion: TQuaternion;
    function GetMass: single;
    function GetDensity: single;
    // Test whether this actor currently touches another one
    function IsCollidingWith(Other: TModelActor): boolean;
    // Properties
    property Engine: TModelEngine read FEngine write SetEngine;
    property Position: TVector3 read FPosition write SetPosition;
    property Rotation: TVector3 read GetRotation write SetRotation;
    property Quaternion: TQuaternion read GetQuaternion write SetRotation;
    property Scale: TVector3 read FScale write FScale;
    property Model: TR3D_Model read FModel;
    property ModelLoaded: boolean read FModelLoaded;
    property ModelTransform: TMatrix read FModelTransform;
    property Tint: TColor read FTint write FTint;
    property Visible: boolean read FVisible write FVisible;
    property IsDead: boolean read FIsDead;
    property Name: string read FName write FName;
    property Mass: single read GetMass write SetMass;
    property Density: single read GetDensity write SetDensity;
    property Restitution: single read GetRestitution write SetRestitution;
    property Friction: single read GetFriction write SetFriction;
    property ModelOffset: TVector3 read FModelOffset write SetModelOffset;
    property CapsuleRadius: Single read FCapsuleRadius;
    property CapsuleHeight: Single read FCapsuleHeight;
    // Physics access for descendants
    property Body: TKraftRigidBody read FBody;
    property Shape: TKraftShape read FShape;
    // Collision events
    property OnCollision: TCollisionEvent read FOnCollision write FOnCollision;
    property OnCollisionEnter: TCollisionStateEvent read FOnCollisionEnter write FOnCollisionEnter;
    property OnCollisionExit: TCollisionStateEvent read FOnCollisionExit write FOnCollisionExit;
    property CamLayer: TR3D_Layer read FCamLayer write FCamLayer;
  end;

  { Convenience constructors that fix the rigid body type }
  TStaticModelActor = class(TModelActor)
  public
    constructor Create(AModelPath: string; AParent: TModelEngine; AShapeType: TKraftShapeType;
      ASize: TVector3);
  end;

  TDynamicModelActor = class(TModelActor)
  public
    constructor Create(AModelPath: string; AParent: TModelEngine; AShapeType: TKraftShapeType;
      ASize: TVector3);
  end;

  { TAnimatedModelActor - actor with skeletal animation support }
  TAnimatedModelActor = class(TDynamicModelActor)
  private
    FAnimationLib: TR3D_AnimationLib;
    FAnimationPlayer: TR3D_AnimationPlayer;
    FAnimationsLoaded: boolean;
    FAnimationSpeed: single;
    FCurrentAnimation: string;
    FDefaultAnimation: string;
    FAnimIndex: integer;
    FLoopAnimation: boolean;
    FPaused: boolean;
  protected
    procedure LoadAnimations(const APath: string);
    procedure UnloadAnimations;
    procedure UpdateAnimation(DeltaTime: single); virtual;
    procedure DrawAnimated; virtual;
  public
    constructor Create(AModelPath: string; AParent: TModelEngine; ASize: TVector3;
      AShapeType: TKraftShapeType = kstCapsule);
    destructor Destroy; override;
    procedure Update(DeltaTime: single); override;
    procedure Draw; override;

    // Animation control
    procedure PlayAnimation(const AName: string; ALoop: boolean = True; ASpeed: single = 1.0);
    procedure PlayAnimationByIndex(AIndex: integer; ALoop: boolean = True; ASpeed: single = 1.0);
    procedure PlayDefaultAnimation;
    procedure StopAnimation;
    procedure PauseAnimation;
    procedure ResumeAnimation;
    procedure SetAnimationSpeed(ASpeed: single);
    procedure SetAnimationLoop(ALoop: boolean);
    function GetAnimationCount: integer;
    function GetAnimationName(AIndex: integer): string;
    function GetCurrentAnimationIndex: integer;
    function FindAnimationIndex(const AName: string): integer;

    property AnimationSpeed: single read FAnimationSpeed write SetAnimationSpeed;
    property CurrentAnimation: string read FCurrentAnimation;
    property DefaultAnimation: string read FDefaultAnimation write FDefaultAnimation;
    property AnimationsLoaded: boolean read FAnimationsLoaded;
    property AnimationPlayer: TR3D_AnimationPlayer read FAnimationPlayer;
    property AnimationLib: TR3D_AnimationLib read FAnimationLib;
    property Paused: boolean read FPaused;
  end;

  { TSimpleActionActor - simple velocity-controlled mover (box, ball, ...) }
  TSimpleActionActor = class(TDynamicModelActor)
  protected
    FOnGround: boolean;
    FIsJumping: boolean;
    FCurrentYaw: single;
    FCurrentPitch: single;
    FTargetYaw: single;
    FGroundContactCount: integer;
    FGroundNormal: TVector3;
    FWalkSpeed: single;
    FJumpForce: single;
    FGravityScale: single;
    FMoveDirection: TVector3;
  public
    constructor Create(AModelPath: string; AParent: TModelEngine; ASize: TVector3;
      AWalkSpeed: single = 2.0; AJumpForce: single = 4.0);
    destructor Destroy; override;
    procedure Update(DeltaTime: single); override;
    procedure Jump;
    procedure SetYaw(AYaw: single);
    procedure SetPitch(APitch: single);
    procedure SetMoveDirection(const ADirection: TVector3);
    procedure SetJumpKeyPressed(AJump: boolean);
    procedure SetOnGround(AOnGround: boolean);
    procedure SetGroundContactCount(ACount: integer);
    procedure SetIsJumping(AJumping: boolean);

    property OnGround: boolean read FOnGround;
    property CurrentYaw: single read FCurrentYaw write FCurrentYaw;
    property WalkSpeed: single read FWalkSpeed write FWalkSpeed;
    property JumpForce: single read FJumpForce write FJumpForce;
    property GravityScale: single read FGravityScale write FGravityScale;
    property MoveDirection: TVector3 read FMoveDirection write SetMoveDirection;
    property GroundNormal: TVector3 read FGroundNormal;
  end;

  { TActionActor - base class for game characters (player, NPCs, enemies).
    Provides the update skeleton and template methods that descendants
    override to inject their own logic:
      DoBeforeUpdate  - input/AI, runs before physics sync
      GetMoveDirection - desired movement direction (world space)
      IsJumpKeyPressed - jump intent
      DoAfterUpdate   - animation, post-physics work
    Movement itself is force-based: a spring accelerates the body towards
    the target speed, which keeps it stable against collisions. }
  TActionActor = class(TAnimatedModelActor)
  protected
    FOnGround: boolean;
    FIsJumping: boolean;
    FCurrentYaw: single;
    FCurrentPitch: single;
    FTargetYaw: single;
    FGroundContactCount: integer;
    FGroundNormal: TVector3;
    FWalkSpeed: single;
    FJumpForce: single;
    FGravityScale: single;

    // Virtual template methods, overridden by descendants
    procedure DoBeforeUpdate(DeltaTime: single); virtual;
    procedure DoAfterUpdate(DeltaTime: single); virtual;
    procedure DoOnGroundChanged(NewOnGround: boolean); virtual;
    function GetMoveDirection(DeltaTime: single): TVector3; virtual;
    function IsJumpKeyPressed: boolean; virtual;
  private
    FLastPosition: TVector3;
    FMoveDirection: TVector3;
  public
    constructor Create(AModelPath: string; AParent: TModelEngine; ASize: TVector3;
      AWalkSpeed: single = 2.0; AJumpForce: single = 4.0);
    destructor Destroy; override;
    procedure Update(DeltaTime: single); override;
    procedure Jump;
    procedure SetYaw(AYaw: single);
    procedure SetPitch(APitch: single);
    function GetForwardDirection: TVector3;
    function GetRightDirection: TVector3;
    procedure SetOnGround(AOnGround: boolean);
    procedure SetGroundContactCount(ACount: integer);
    procedure SetIsJumping(AJumping: boolean);

    property OnGround: boolean read FOnGround;
    property CurrentYaw: single read FCurrentYaw write FCurrentYaw;
    property CurrentPitch: single read FCurrentPitch write FCurrentPitch;
    property WalkSpeed: single read FWalkSpeed write FWalkSpeed;
    property JumpForce: single read FJumpForce write FJumpForce;
    property GravityScale: single read FGravityScale write FGravityScale;
    property GroundContactCount: integer read FGroundContactCount;
    property GroundNormal: TVector3 read FGroundNormal;
    property MoveDirection: TVector3 read FMoveDirection;
  end;

implementation

const Vector3Up: TVector3 = (x: 0.0; y: 1.0; z: 0.0);

{ TModelEngine }

function TModelEngine.GetCount: integer;
begin
  Result := FActorList.Count;
end;

function TModelEngine.GetModelActor(const Index: integer): TModelActor;
begin
  if (Index >= 0) and (Index < FActorList.Count) then
    Result := TModelActor(FActorList.Items[Index])
  else
    Result := nil;
end;

procedure TModelEngine.OnContactBegin(const ContactPair: PKraftContactPair);
var
  ActorA, ActorB: TModelActor;
  ContactPoint, Normal: TVector3;
  WorldNormal: TKraftVector3;
begin
  if not Assigned(ContactPair) then Exit;

  // Shapes carry the owning actor in UserData
  ActorA := TModelActor(ContactPair^.Shapes[0].UserData);
  ActorB := TModelActor(ContactPair^.Shapes[1].UserData);

  if not (Assigned(ActorA) and Assigned(ActorB)) then Exit;

  // Register the contact on both sides (used by IsCollidingWith)
  ActorA.InternalAddContact(ActorB);
  ActorB.InternalAddContact(ActorA);

  // Contact normal and point, transformed to world space
  WorldNormal := Vector3TermMatrixMulBasis(ContactPair^.Manifold.LocalNormal,
    ActorA.Body.WorldTransform);
  Normal := KraftVector3ToRaylibVector3(WorldNormal);

  if ContactPair^.Manifold.CountContacts > 0 then
  begin
    ContactPoint := KraftVector3ToRaylibVector3(ContactPair^.Manifold.Contacts[0].LocalPoints[1]);
  end
  else
  begin
    ContactPoint := ActorB.GetPosition;
  end;

  // Fire the enter event exactly once per contact pair
  if Assigned(ActorA.FOnCollisionEnter) then
    ActorA.FOnCollisionEnter(ActorA, ActorB);
  if Assigned(ActorB.FOnCollisionEnter) then
    ActorB.FOnCollisionEnter(ActorB, ActorA);

  // Fire the continuous collision event. The manifold normal is defined
  // from A's point of view, so B receives it negated.
  if Assigned(ActorA.FOnCollision) then
    ActorA.FOnCollision(ActorA, ActorB, ContactPoint, Normal);
  if Assigned(ActorB.FOnCollision) then
    ActorB.FOnCollision(ActorB, ActorA, ContactPoint, Vector3Negate(Normal));
end;

procedure TModelEngine.OnContactEnd(const ContactPair: PKraftContactPair);
var
  ActorA, ActorB: TModelActor;
begin
  if not Assigned(ContactPair) then Exit;

  ActorA := TModelActor(ContactPair^.Shapes[0].UserData);
  ActorB := TModelActor(ContactPair^.Shapes[1].UserData);

  if not (Assigned(ActorA) and Assigned(ActorB)) then Exit;

  // Unregister the contact on both sides
  ActorA.InternalRemoveContact(ActorB);
  ActorB.InternalRemoveContact(ActorA);

  // Fire the exit event exactly once per contact pair
  if Assigned(ActorA.FOnCollisionExit) then
    ActorA.FOnCollisionExit(ActorA, ActorB);
  if Assigned(ActorB.FOnCollisionExit) then
    ActorB.FOnCollisionExit(ActorB, ActorA);
end;

procedure TModelEngine.OnContactStay(const ContactPair: PKraftContactPair);
var
  ActorA, ActorB: TModelActor;
  ContactPoint, Normal: TVector3;
  WorldNormal: TKraftVector3;
begin
  if not Assigned(ContactPair) then Exit;

  ActorA := TModelActor(ContactPair^.Shapes[0].UserData);
  ActorB := TModelActor(ContactPair^.Shapes[1].UserData);

  if not (Assigned(ActorA) and Assigned(ActorB)) then Exit;

  // Contact normal and point, transformed to world space
  WorldNormal := Vector3TermMatrixMulBasis(ContactPair^.Manifold.LocalNormal,
    ActorA.Body.WorldTransform);
  Normal := KraftVector3ToRaylibVector3(WorldNormal);

  if ContactPair^.Manifold.CountContacts > 0 then
  begin
    ContactPoint := KraftVector3ToRaylibVector3(ContactPair^.Manifold.Contacts[0].LocalPoints[1]);
  end
  else
  begin
    ContactPoint := ActorB.GetPosition;
  end;

  // Fire the continuous collision event while the pair stays in contact
  if Assigned(ActorA.FOnCollision) then
    ActorA.FOnCollision(ActorA, ActorB, ContactPoint, Normal);
  if Assigned(ActorB.FOnCollision) then
    ActorB.FOnCollision(ActorB, ActorA, ContactPoint, Vector3Negate(Normal));
end;

constructor TModelEngine.Create;
begin
  FActorList := TObjectList.Create(True);
  FPhysics := TKraft.Create(-1);

  // Solver tuning: 60 Hz steps, iteration counts chosen for a good
  // stability/performance balance for character-driven games
  FPhysics.SetFrequency(60);
  FPhysics.VelocityIterations := 8;
  FPhysics.PositionIterations := 3;
  FPhysics.SpeculativeIterations := 8;
  FPhysics.TimeOfImpactIterations := 0;
  FPhysics.Gravity.y := -9.81;   // Earth gravity
  FPhysics.LinearSlop := 0.02;
  FPhysics.PenetrationSlop := 0.02;
  FPhysics.ContactBaumgarte := 0.5;

  // Hook the per-actor event mapping into Kraft's contact manager
  FPhysics.ContactManager.OnContactBegin := OnContactBegin;
  FPhysics.ContactManager.OnContactEnd := OnContactEnd;
  FPhysics.ContactManager.OnContactStay := OnContactStay;
end;

destructor TModelEngine.Destroy;
begin
  Clear;            // frees all actors ( TObjectList owns them)
  FPhysics.Free;
  FActorList.Free;
  inherited Destroy;
end;

procedure TModelEngine.Add(const ModelActor: TModelActor);
begin
  if not Assigned(ModelActor) then Exit;
  FActorList.Add(ModelActor);
end;

procedure TModelEngine.Remove(const ModelActor: TModelActor);
begin
  if not Assigned(ModelActor) then Exit;
  FActorList.Remove(ModelActor);
  ModelActor.FEngine := nil;
end;

procedure TModelEngine.Update(DeltaTime: single);
var
  i: integer;
  Actor: TModelActor;
begin
  // 1) Step the physics world
  FPhysics.Step(DeltaTime);

  // 2) Let every living actor sync its transform from its body
  //    and run its own logic (AI, animation, input, ...)
  for i := 0 to FActorList.Count - 1 do
  begin
    Actor := TModelActor(FActorList.Items[i]);
    if Assigned(Actor) and not Actor.IsDead then
    begin
      Actor.Update(DeltaTime);
    end;
  end;
end;

procedure TModelEngine.Render;
var
  i: integer;
  Actor: TModelActor;
begin
  // Draw all visible, alive actors. Call between R3D_Begin and R3D_End.
  for i := 0 to FActorList.Count - 1 do
  begin
    Actor := TModelActor(FActorList.Items[i]);
    if Assigned(Actor) and Actor.Visible and not Actor.IsDead then
      Actor.Draw;
  end;
end;

procedure TModelEngine.Clear;
begin
  FActorList.Clear;
end;

{ TModelActor }

function TModelActor.Vec3ToKraft(const V: TVector3): TKraftVector3;
begin
  Result.x := V.x;
  Result.y := V.y;
  Result.z := V.z;
end;

function TModelActor.KraftToVec3(const V: TKraftVector3): TVector3;
begin
  Result.x := V.x;
  Result.y := V.y;
  Result.z := V.z;
end;

procedure TModelActor.SetEngine(AValue: TModelEngine);
begin
  if FEngine = AValue then Exit;
  if FEngine <> nil then
    FEngine.Remove(Self);
  FEngine := AValue;
end;

function TModelActor.GetRestitution: single;
begin
  if Assigned(FShape) then Result := FShape.Restitution;
end;

function TModelActor.GetFriction: single;
begin
  if Assigned(FShape) then Result := FShape.Friction;
end;

function TModelActor.GetTransformMatrix: PMatrix;
begin
  // NOTE: must never return a pointer to a local temporary, so the
  // no-body case returns nil instead of a dangling stack pointer.
  if Assigned(FBody) then
    Result := @FBody.WorldTransform
  else
    Result := nil;
end;

procedure TModelActor.SetFriction(AValue: single);
begin
  if Assigned(FShape) then FShape.Friction := AValue;
end;

procedure TModelActor.SetRestitution(AValue: single);
begin
  if Assigned(FShape) then FShape.Restitution := AValue;
end;

procedure TModelActor.UpdateRotationFromPhysics;
begin
  if Assigned(FBody) then
  begin
    // Extract the orientation from the body's world transform
    FQuaternion := KraftMatrix4x4ToQuaternion(FBody.WorldTransform);
    FRotation := QuaternionToEuler(FQuaternion);
    FRotation := Vector3Scale(FRotation, RAD2DEG);
  end;
end;

procedure TModelActor.UpdatePhysicsRotation;
var
  KraftPos: TKraftVector3;
  KraftMatrix: TKraftMatrix4x4;
  RotationMatrix: TMatrix;
begin
  if Assigned(FBody) then
  begin
    // Push our quaternion and position back into the body's transform
    // (Kraft stores the translation in row 3 of its 4x4 matrix)
    RotationMatrix := QuaternionToMatrix(FQuaternion);
    KraftMatrix := RaylibMatrixToKraftMatrix(RotationMatrix);
    KraftPos := Vec3ToKraft(FPosition);
    KraftMatrix[3, 0] := KraftPos.x;
    KraftMatrix[3, 1] := KraftPos.y;
    KraftMatrix[3, 2] := KraftPos.z;
    FBody.SetWorldTransformation(KraftMatrix);
  end;
end;

procedure TModelActor.UpdateMassProperties;
begin
  if Assigned(FBody) and Assigned(FShape) then
  begin
    // Re-apply density, then let Kraft recompute mass/inertia
    FShape.Density := FDensity;
    FBody.Finish;
  end;
end;

procedure TModelActor.UpdateModelTransform;
var
  ModelPos: TVector3;
  Quat: TQuaternion;
  RotMat: TMatrix;
begin
  // Compose: scale * translate(model position incl. offset) * rotate.
  // The offset is rotated with the body, so it stays attached to the
  // model's local frame (used to align meshes to their collider).
  ModelPos := GetPosition;
  Quat := GetQuaternion;
  RotMat := QuaternionToMatrix(Quat);

  if (FModelOffset.x <> 0) or (FModelOffset.y <> 0) or (FModelOffset.z <> 0) then
  begin
    ModelPos := Vector3Add(ModelPos, Vector3Transform(FModelOffset, RotMat));
  end;

  FModelTransform := MatrixTranslate(ModelPos.x, ModelPos.y, ModelPos.z);
  FModelTransform := MatrixMultiply(RotMat, FModelTransform);
  FModelTransform := MatrixMultiply(MatrixScale(FScale.x, FScale.y, FScale.z), FModelTransform);
end;

procedure TModelActor.LoadR3DModel(const APath: string; CreateCollider: boolean);
begin
  if FModelLoaded then
    UnloadR3DModel;

  if FileExists(APath) then
  begin
    if CreateCollider then
      // RETAIN_MESH_DATA keeps a CPU-side copy of the vertices - required
      // later by CreateMeshShape to build the Kraft triangle collider
      FModel := R3D_LoadModelEx(PAnsiChar(AnsiString(APath)), R3D_IMPORT_RETAIN_MESH_DATA)
    else
      FModel := R3D_LoadModel(PAnsiChar(AnsiString(APath)));

    FModelLoaded := FModel.meshCount > 0;

    UpdateModelTransform;
  end
  else
  begin
    // Missing file: continue with an empty (zeroed) model rather than
    // crashing - descendants decide how to handle "no mesh"
    FModelLoaded := False;
    FillChar(FModel, SizeOf(TR3D_Model), 0);
  end;
end;

procedure TModelActor.UnloadR3DModel;
begin
  if FModelLoaded then
  begin
    R3D_UnloadModel(FModel, True);
    FModelLoaded := False;
    FillChar(FModel, SizeOf(TR3D_Model), 0);
  end;
end;

procedure TModelActor.CreateMeshShape(ASize: TVector3);
var
  mesh: TKraftMesh;
  i, j: integer;
  r3dMeshData: PR3D_MeshData;
  verts: PR3D_Vertex;
  indices: PUInt32;
  v1, v2, v3: TVector3;
  n1, n2, n3: TVector3;
begin
  if not Assigned(FEngine) or not FModelLoaded then Exit;

  mesh := TKraftMesh.Create(FEngine.Physics);

  // Build a triangle collider from the retained CPU mesh data.
  // Requires the model to have been loaded with R3D_IMPORT_RETAIN_MESH_DATA.
  for i := 0 to FModel.meshCount - 1 do
  begin
    r3dMeshData := @FModel.meshData[i];

    if not Assigned(r3dMeshData) or (r3dMeshData^.vertexCount = 0) then
      Continue;

    verts := r3dMeshData^.vertices;
    indices := r3dMeshData^.indices;

    if (r3dMeshData^.indexCount > 0) and Assigned(indices) then
    begin
      // Indexed mesh: three indices per triangle
      for j := 0 to (r3dMeshData^.indexCount div 3) - 1 do
      begin
        v1 := Vector3Create(
          verts[indices[j * 3 + 0]].position.x,
          verts[indices[j * 3 + 0]].position.y,
          verts[indices[j * 3 + 0]].position.z
        );
        v2 := Vector3Create(
          verts[indices[j * 3 + 1]].position.x,
          verts[indices[j * 3 + 1]].position.y,
          verts[indices[j * 3 + 1]].position.z
        );
        v3 := Vector3Create(
          verts[indices[j * 3 + 2]].position.x,
          verts[indices[j * 3 + 2]].position.y,
          verts[indices[j * 3 + 2]].position.z
        );

        // Normals are stored as SNORM8 (-127..127): scale back to [-1..1]
        n1 := Vector3Create(
          verts[indices[j * 3 + 0]].normal[0] / 127.0,
          verts[indices[j * 3 + 0]].normal[1] / 127.0,
          verts[indices[j * 3 + 0]].normal[2] / 127.0
        );
        n2 := Vector3Create(
          verts[indices[j * 3 + 1]].normal[0] / 127.0,
          verts[indices[j * 3 + 1]].normal[1] / 127.0,
          verts[indices[j * 3 + 1]].normal[2] / 127.0
        );
        n3 := Vector3Create(
          verts[indices[j * 3 + 2]].normal[0] / 127.0,
          verts[indices[j * 3 + 2]].normal[1] / 127.0,
          verts[indices[j * 3 + 2]].normal[2] / 127.0
        );

        n1 := Vector3Normalize(n1);
        n2 := Vector3Normalize(n2);
        n3 := Vector3Normalize(n3);

        mesh.AddTriangle(
          mesh.AddVertex(Vec3ToKraft(v1)),
          mesh.AddVertex(Vec3ToKraft(v2)),
          mesh.AddVertex(Vec3ToKraft(v3)),
          mesh.AddNormal(Vec3ToKraft(n1)),
          mesh.AddNormal(Vec3ToKraft(n2)),
          mesh.AddNormal(Vec3ToKraft(n3))
        );
      end;
    end
    else
    begin
      // No index buffer: vertices are raw triangle soup
      for j := 0 to (r3dMeshData^.vertexCount div 3) - 1 do
      begin
        v1 := Vector3Create(
          verts[j * 3 + 0].position.x,
          verts[j * 3 + 0].position.y,
          verts[j * 3 + 0].position.z
        );
        v2 := Vector3Create(
          verts[j * 3 + 1].position.x,
          verts[j * 3 + 1].position.y,
          verts[j * 3 + 1].position.z
        );
        v3 := Vector3Create(
          verts[j * 3 + 2].position.x,
          verts[j * 3 + 2].position.y,
          verts[j * 3 + 2].position.z
        );

        n1 := Vector3Create(
          verts[j * 3 + 0].normal[0] / 127.0,
          verts[j * 3 + 0].normal[1] / 127.0,
          verts[j * 3 + 0].normal[2] / 127.0
        );
        n2 := Vector3Create(
          verts[j * 3 + 1].normal[0] / 127.0,
          verts[j * 3 + 1].normal[1] / 127.0,
          verts[j * 3 + 1].normal[2] / 127.0
        );
        n3 := Vector3Create(
          verts[j * 3 + 2].normal[0] / 127.0,
          verts[j * 3 + 2].normal[1] / 127.0,
          verts[j * 3 + 2].normal[2] / 127.0
        );

        n1 := Vector3Normalize(n1);
        n2 := Vector3Normalize(n2);
        n3 := Vector3Normalize(n3);

        mesh.AddTriangle(
          mesh.AddVertex(Vec3ToKraft(v1)),
          mesh.AddVertex(Vec3ToKraft(v2)),
          mesh.AddVertex(Vec3ToKraft(v3)),
          mesh.AddNormal(Vec3ToKraft(n1)),
          mesh.AddNormal(Vec3ToKraft(n2)),
          mesh.AddNormal(Vec3ToKraft(n3))
        );
      end;
    end;
  end;

  // Scale the collider to the actor's size, then finalize
  mesh.Scale(Vec3ToKraft(ASize));
  mesh.DoubleSided := True;
  mesh.Finish;

  FMeshShape := TKraftShapeMesh.Create(FEngine.Physics, FBody, mesh);
  FMeshShape.Restitution := 0.4;
  FMeshShape.Density := FDensity;
  FMeshShape.Friction := 0.3;
  FMeshShape.Finish;
  FShape := FMeshShape;
end;

constructor TModelActor.Create(AModelPath: string; AParent: TModelEngine; AShapeType: TKraftShapeType;
  ASize: TVector3; ARigidBodyType: TKraftRigidBodyType);
var
  FKrSize: TKraftVector3;
  PlaneNormal: TKraftVector3;
  KraftMatrix: TKraftMatrix4x4;
begin
  FEngine := AParent;
  FIsDead := False;
  FModelLoaded := False;
  FillChar(FModel, SizeOf(TR3D_Model), 0);
  FModelTransform := MatrixIdentity();
  FPosition := Vector3Create(0, 0, 0);
  FScale := Vector3Create(1, 1, 1);
  FRotation := Vector3Create(0, 0, 0);
  FQuaternion := QuaternionIdentity;
  FModelOffset := Vector3Zero;
  FTint := WHITE;
  FVisible := True;
  FMass := 1.0;
  FDensity := 1.0;
  FMeshShape := nil;
  FContacts := TList.Create;
  FOnCollision := nil;
  FOnCollisionEnter := nil;
  FOnCollisionExit := nil;
  FCapsuleRadius  := ASize.x;
  FCapsuleHeight := ASize.y;

  if AModelPath <> '' then
    LoadR3DModel(AModelPath, True);

  if Assigned(FEngine) then
  begin
    FBody := TKraftRigidBody.Create(FEngine.Physics);
    FBody.SetRigidBodyType(ARigidBodyType);
    FKrSize := Vec3ToKraft(ASize);

    // UserData lets collision callbacks and physics rays find the
    // owning actor (used by occlusion checks, zombie vision, ...)
    FBody.UserData := Self;

    case AShapeType of
      kstBox: begin
        FShape := TKraftShapeBox.Create(FEngine.Physics, FBody, FKrSize);
      end;
      kstSphere:
        FShape := TKraftShapeSphere.Create(FEngine.Physics, FBody, ASize.x);
      kstCapsule:
        FShape := TKraftShapeCapsule.Create(FEngine.Physics, FBody, ASize.x, ASize.y);
      kstPlane:
      begin
        // Infinite static ground-style plane, normal pointing up
        PlaneNormal := Vec3ToKraft(Vector3Create(0.0, 1.0, 0.0));
        FShape := TKraftShapePlane.Create(FEngine.Physics, FBody, Plane(PlaneNormal, 0.0));
        FBody.SetRigidBodyType(krbtStatic);
      end;
      kstMesh:
      begin
        // Triangle-mesh colliders are expensive - force static body
        FBody.SetRigidBodyType(krbtStatic);
        CreateMeshShape(ASize);
      end;
      else
        FShape := TKraftShapeBox.Create(FEngine.Physics, FBody, FKrSize);
    end;

    // Set UserData on the shape as well (contact pairs reference shapes)
    FShape.UserData := Self;

    if AShapeType <> kstMesh then
    begin
      FShape.Restitution := 0.4;
      FShape.Density := FDensity;
      FShape.Friction := 0.3;
    end;

    FBody.Finish;
    KraftMatrix := Matrix4x4Translate(FPosition.x, FPosition.y, FPosition.z);
    FBody.SetWorldTransformation(KraftMatrix);
    FBody.CollisionGroups := [0];
  end;

  if Assigned(FEngine) then
    FEngine.Add(Self);
end;

destructor TModelActor.Destroy;
begin
  if Assigned(FEngine) then
    FEngine.Remove(Self);

  UnloadR3DModel;

  // Mesh actors: FShape and FMeshShape are the same object, free it once
  if Assigned(FMeshShape) then
    FMeshShape.Free;

  // Otherwise free the regular shape
  if Assigned(FShape) and (FShape <> FMeshShape) then
    FShape.Free;

  if Assigned(FBody) then
    FBody.Free;

  if Assigned(FContacts) then
    FContacts.Free;

  inherited Destroy;
end;

procedure TModelActor.Update(DeltaTime: single);
begin
  if Assigned(FBody) then
  begin
    // Pull the authoritative transform from the physics body
    FPosition := GetPosition;
    UpdateRotationFromPhysics;
    UpdateModelTransform;
  end;
end;

procedure TModelActor.Draw;
begin
  if not FVisible or FIsDead or not FModelLoaded then Exit;
  R3D_DrawModelPro(FModel, FModelTransform);
end;

procedure TModelActor.Dead;
begin
  // Marked only - the engine skips update/draw for dead actors
  FIsDead := True;
end;

procedure TModelActor.SetPosition(APosition: TVector3);
begin
  FPosition := APosition;
  if Assigned(FBody) then
  begin
    // Teleport the body; the actor follows on the next Update
    FBody.SetWorldPosition(Vec3ToKraft(APosition));
  end;
  UpdateModelTransform;
end;

procedure TModelActor.SetRotation(ARotation: TVector3);
begin
  FRotation := ARotation;
  FQuaternion := QuaternionFromEuler(ARotation.x * DEG2RAD,
                                     ARotation.y * DEG2RAD,
                                     ARotation.z * DEG2RAD);
  UpdatePhysicsRotation;
  UpdateModelTransform;
end;

procedure TModelActor.SetRotation(AQuaternion: TQuaternion);
begin
  FQuaternion := AQuaternion;
  FRotation := QuaternionToEuler(AQuaternion);
  FRotation := Vector3Scale(FRotation, RAD2DEG);
  UpdatePhysicsRotation;
  UpdateModelTransform;
end;

procedure TModelActor.SetModelOffset(AOffset: TVector3);
begin
  FModelOffset := AOffset;
  UpdateModelTransform;
end;

procedure TModelActor.SetMass(AMass: single);
begin
  if AMass > 0 then
  begin
    FMass := AMass;
    if Assigned(FShape) then
    begin
      // Derive a density that produces the requested mass for this volume
      FDensity := FMass / (FScale.x * FScale.y * FScale.z);
      UpdateMassProperties;
    end;
  end;
end;

procedure TModelActor.SetDensity(ADensity: single);
begin
  if ADensity > 0 then
  begin
    FDensity := ADensity;
    if Assigned(FShape) then
    begin
      FShape.Density := FDensity;
      if Assigned(FBody) then
      begin
        FBody.Finish;
        FMass := FBody.Mass;
      end;
    end;
  end;
end;

procedure TModelActor.ApplyForce(AForce: TVector3);
begin
  if Assigned(FBody) then
  begin
    // kfmForce: continuous force, accumulated and applied during the step
    FBody.SetWorldForce(Vec3ToKraft(AForce), kfmForce);
  end;
end;

procedure TModelActor.ApplyImpulse(AImpulse: TVector3);
begin
  if Assigned(FBody) then
  begin
    // kfmImpulse: instant velocity change (mass-independent force spike)
    FBody.SetWorldForce(Vec3ToKraft(AImpulse), kfmImpulse);
  end;
end;

procedure TModelActor.ApplyTorque(ATorque: TVector3);
begin
  if Assigned(FBody) then
  begin
    FBody.SetWorldTorque(Vec3ToKraft(ATorque), kfmForce);
  end;
end;

procedure TModelActor.ApplyAngularImpulse(AImpulse: TVector3);
begin
  if Assigned(FBody) then
  begin
    FBody.SetWorldTorque(Vec3ToKraft(AImpulse), kfmImpulse);
  end;
end;

procedure TModelActor.SetOrientationRadians(AXRotation, AYRotation, AZRotation: single);
begin
  if Assigned(FBody) then
    FBody.SetOrientation(AXRotation, AYRotation, AZRotation);
end;

procedure TModelActor.AddOrientationRadians(AXRotation, AYRotation, AZRotation: single);
begin
  if Assigned(FBody) then
    FBody.AddOrientation(AXRotation, AYRotation, AZRotation);
end;

procedure TModelActor.SetOrientationDegrees(AXRotation, AYRotation, AZRotation: single);
begin
  if Assigned(FBody) then
    FBody.SetOrientation(
      AXRotation * DEG2RAD,
      AYRotation * DEG2RAD,
      AZRotation * DEG2RAD);
end;

procedure TModelActor.AddOrientationDegrees(AXRotation, AYRotation, AZRotation: single);
begin
  if Assigned(FBody) then
    FBody.AddOrientation(
      AXRotation * DEG2RAD,
      AYRotation * DEG2RAD,
      AZRotation * DEG2RAD);
end;

function TModelActor.GetPosition: TVector3;
var
  Transform: TKraftMatrix4x4;
begin
  if Assigned(FBody) then
  begin
    // Kraft stores the translation in row 3 of its row-major 4x4
    Transform := FBody.WorldTransform;
    Result := Vector3Create(Transform[3, 0], Transform[3, 1], Transform[3, 2]);
  end
  else
    Result := FPosition;
end;

function TModelActor.GetRotation: TVector3;
begin
  Result := FRotation;
end;

function TModelActor.GetQuaternion: TQuaternion;
begin
  Result := FQuaternion;
end;

function TModelActor.GetMass: single;
begin
  if Assigned(FBody) then
    Result := FBody.Mass
  else
    Result := FMass;
end;

function TModelActor.GetDensity: single;
begin
  Result := FDensity;
end;

function TModelActor.IsCollidingWith(Other: TModelActor): boolean;
begin
  Result := FContacts.IndexOf(Other) >= 0;
end;

procedure TModelActor.InternalAddContact(Other: TModelActor);
begin
  if FContacts.IndexOf(Other) < 0 then
    FContacts.Add(Other);
end;

procedure TModelActor.InternalRemoveContact(Other: TModelActor);
begin
  FContacts.Remove(Other);
end;

procedure TModelActor.InternalProcessContact(Other: TModelActor; const ContactPoint: TVector3; const Normal: TVector3);
begin
  // Called on every contact frame
  if Assigned(FOnCollision) then
    FOnCollision(Self, Other, ContactPoint, Normal);
end;

{ TStaticModelActor }

constructor TStaticModelActor.Create(AModelPath: string; AParent: TModelEngine;
  AShapeType: TKraftShapeType; ASize: TVector3);
begin
  inherited Create(AModelPath, AParent, AShapeType, ASize, krbtSTATIC);
end;

{ TDynamicModelActor }

constructor TDynamicModelActor.Create(AModelPath: string; AParent: TModelEngine;
  AShapeType: TKraftShapeType; ASize: TVector3);
begin
  inherited Create(AModelPath, AParent, AShapeType, ASize, krbtDYNAMIC);
end;

{ TAnimatedModelActor }

constructor TAnimatedModelActor.Create(AModelPath: string; AParent: TModelEngine; ASize: TVector3;
  AShapeType: TKraftShapeType);
begin
  inherited Create(AModelPath, AParent, AShapeType, ASize);

  FAnimationLib := Default(TR3D_AnimationLib);
  FAnimationPlayer := Default(TR3D_AnimationPlayer);
  FAnimationsLoaded := False;
  FAnimationSpeed := 1.0;
  FCurrentAnimation := '';
  FDefaultAnimation := '';
  FAnimIndex := -1;
  FLoopAnimation := True;
  FPaused := False;

  if AModelPath <> '' then
    LoadAnimations(AModelPath);
end;

destructor TAnimatedModelActor.Destroy;
begin
  UnloadAnimations;
  inherited Destroy;
end;

procedure TAnimatedModelActor.LoadAnimations(const APath: string);
begin
  if FAnimationsLoaded then
    UnloadAnimations;

  if FileExists(APath) then
  begin
    // Load the animation library and bind a player to the model's
    // skeleton (the model must already be loaded with a skeleton)
    FAnimationLib := R3D_LoadAnimationLib(PAnsiChar(AnsiString(APath)));
    if FAnimationLib.count > 0 then
    begin
      FAnimationPlayer := R3D_LoadAnimationPlayer(FModel.skeleton, FAnimationLib);
      FAnimationsLoaded := True;

      // If animations exist, make the first one current and start it
      // looping as the default
      if FAnimationLib.count > 0 then
      begin
        FAnimIndex := 0;
        FCurrentAnimation := string(FAnimationLib.animations[0].name);
        R3D_SetAnimationLoop(@FAnimationPlayer, 0, True);
        R3D_PlayAnimation(@FAnimationPlayer, 0);
      end;
    end;
  end;
end;

procedure TAnimatedModelActor.UnloadAnimations;
begin
  if FAnimationsLoaded then
  begin
    R3D_UnloadAnimationPlayer(FAnimationPlayer);
    R3D_UnloadAnimationLib(FAnimationLib);
    FAnimationsLoaded := False;
    FAnimIndex := -1;
    FCurrentAnimation := '';
  end;
end;

procedure TAnimatedModelActor.UpdateAnimation(DeltaTime: single);
begin
  if FAnimationsLoaded and (FAnimIndex >= 0) and not FPaused then
  begin
    R3D_UpdateAnimationPlayer(@FAnimationPlayer, DeltaTime * FAnimationSpeed);
  end;
end;

procedure TAnimatedModelActor.DrawAnimated;
begin
  if not FVisible or FIsDead or not FModelLoaded then Exit;

  // Animated draw while a player is bound, plain draw otherwise
  if FAnimationsLoaded then
    R3D_DrawAnimatedModelPro(FModel, FAnimationPlayer, FModelTransform)
  else
    R3D_DrawModelPro(FModel, FModelTransform);
end;

procedure TAnimatedModelActor.Update(DeltaTime: single);
begin
  inherited Update(DeltaTime);
  UpdateAnimation(DeltaTime);
end;

procedure TAnimatedModelActor.Draw;
begin
  DrawAnimated;
end;

procedure TAnimatedModelActor.PlayAnimation(const AName: string; ALoop: boolean; ASpeed: single);
var
  i: integer;
begin
  if not FAnimationsLoaded then Exit;

  for i := 0 to FAnimationLib.count - 1 do
  begin
    if string(FAnimationLib.animations[i].name) = AName then
    begin
      FAnimIndex := i;
      FCurrentAnimation := AName;
      FAnimationSpeed := ASpeed;
      FLoopAnimation := ALoop;
      FPaused := False;

      R3D_SetAnimationLoop(@FAnimationPlayer, i, ALoop);
      R3D_PlayAnimation(@FAnimationPlayer, i);
      Break;
    end;
  end;
end;

procedure TAnimatedModelActor.PlayAnimationByIndex(AIndex: integer; ALoop: boolean; ASpeed: single);
begin
  if not FAnimationsLoaded or (AIndex < 0) or (AIndex >= FAnimationLib.count) then Exit;

  FAnimIndex := AIndex;
  FCurrentAnimation := string(FAnimationLib.animations[AIndex].name);
  FAnimationSpeed := ASpeed;
  FLoopAnimation := ALoop;
  FPaused := False;

  R3D_SetAnimationLoop(@FAnimationPlayer, AIndex, ALoop);
  R3D_PlayAnimation(@FAnimationPlayer, AIndex);
end;

procedure TAnimatedModelActor.PlayDefaultAnimation;
begin
  if FDefaultAnimation <> '' then
    PlayAnimation(FDefaultAnimation);
end;

procedure TAnimatedModelActor.StopAnimation;
begin
  if FAnimationsLoaded then
  begin
    R3D_StopAnimation(@FAnimationPlayer);
    FPaused := True;
  end;
end;

procedure TAnimatedModelActor.PauseAnimation;
begin
  FPaused := True;
end;

procedure TAnimatedModelActor.ResumeAnimation;
begin
  FPaused := False;
end;

procedure TAnimatedModelActor.SetAnimationSpeed(ASpeed: single);
begin
  FAnimationSpeed := ASpeed;
end;

procedure TAnimatedModelActor.SetAnimationLoop(ALoop: boolean);
begin
  FLoopAnimation := ALoop;
  if FAnimationsLoaded and (FAnimIndex >= 0) then
    R3D_SetAnimationLoop(@FAnimationPlayer, FAnimIndex, ALoop);
end;

function TAnimatedModelActor.GetAnimationCount: integer;
begin
  if FAnimationsLoaded then
    Result := FAnimationLib.count
  else
    Result := 0;
end;

function TAnimatedModelActor.GetAnimationName(AIndex: integer): string;
begin
  Result := '';
  if FAnimationsLoaded and (AIndex >= 0) and (AIndex < FAnimationLib.count) then
    Result := string(FAnimationLib.animations[AIndex].name);
end;

function TAnimatedModelActor.GetCurrentAnimationIndex: integer;
begin
  Result := FAnimIndex;
end;

function TAnimatedModelActor.FindAnimationIndex(const AName: string): integer;
var
  i: integer;
begin
  Result := -1;
  if not FAnimationsLoaded then Exit;

  for i := 0 to FAnimationLib.count - 1 do
  begin
    if string(FAnimationLib.animations[i].name) = AName then
    begin
      Result := i;
      Break;
    end;
  end;
end;

{ TSimpleActionActor }

constructor TSimpleActionActor.Create(AModelPath: string; AParent: TModelEngine; ASize: TVector3;
  AWalkSpeed: single; AJumpForce: single);
begin
  inherited Create(AModelPath, AParent, kstBox, ASize);

  FOnGround := False;
  FIsJumping := False;
  FCurrentYaw := 0.0;
  FCurrentPitch := 0.0;
  FTargetYaw := 0.0;
  FGroundContactCount := 0;
  FGroundNormal := Vector3Up;
  FWalkSpeed := AWalkSpeed;
  FJumpForce := AJumpForce;
  FGravityScale := 1.0;
  FMoveDirection := Vector3Zero;

  if Assigned(Shape) then
  begin
    Shape.Friction := 0.5;
    Shape.Restitution := 0.1;
    Shape.Density := 10.0;
  end;

  if Assigned(Body) then
  begin
    // Lock pitch/roll: this actor only yaws
    Body.Flags := Body.Flags + [krbfLockRotationAxisX, krbfLockRotationAxisZ];
    Body.LinearVelocityDamp := 0.5;
    Body.AngularVelocityDamp := 0.5;
    SetRotation(QuaternionIdentity);
  end;
end;

destructor TSimpleActionActor.Destroy;
begin
  inherited Destroy;
end;

procedure TSimpleActionActor.Update(DeltaTime: single);
var
  MoveDir: TVector3;
  Vel: TKraftVector3;
  Quat: TQuaternion;
  KraftMat: TKraftMatrix3x3;
  AngleDiff: single;
begin
  inherited Update(DeltaTime);

  // Turn towards the movement direction
  if Vector3Length(FMoveDirection) > 0 then
  begin
    MoveDir := Vector3Normalize(FMoveDirection);
    FTargetYaw := ArcTan2(MoveDir.x, MoveDir.z);
  end;

  if FTargetYaw <> FCurrentYaw then
  begin
    // Shortest-arc angle difference, then smooth approach
    AngleDiff := FTargetYaw - FCurrentYaw;
    while AngleDiff > PI do AngleDiff := AngleDiff - 2 * PI;
    while AngleDiff < -PI do AngleDiff := AngleDiff + 2 * PI;

    FCurrentYaw := FCurrentYaw + AngleDiff * Min(1.0, 4.0 * DeltaTime);

    Quat := QuaternionFromEuler(0, FCurrentYaw, 0);
    KraftMat := QuaternionToKraftMatrix3x3(Quat);
    Body.SetOrientation(KraftMat);
    SetRotation(Quat);
  end;

  // Movement: horizontal velocity is set directly (kinematic-style)
  MoveDir := FMoveDirection;
  if Vector3Length(MoveDir) > 0 then
    MoveDir := Vector3Normalize(MoveDir);

  Vel := Body.LinearVelocity;
  Vel.x := MoveDir.x * FWalkSpeed;
  Vel.z := MoveDir.z * FWalkSpeed;

  if FGravityScale <> 1.0 then
    Vel.y := Vel.y * FGravityScale;

  Body.LinearVelocity := Vel;

  // Jump
  if FIsJumping and FOnGround then
    Jump;
end;

procedure TSimpleActionActor.Jump;
var
  Vel: TKraftVector3;
begin
  if FOnGround then
  begin
    Vel := Body.LinearVelocity;
    Vel.y := FJumpForce;
    Body.LinearVelocity := Vel;
    FIsJumping := True;
    FOnGround := False;
  end;
end;

procedure TSimpleActionActor.SetYaw(AYaw: single);
begin
  FCurrentYaw := AYaw;
  FTargetYaw := AYaw;
  SetRotation(QuaternionFromEuler(0, FCurrentYaw, 0));
end;

procedure TSimpleActionActor.SetPitch(APitch: single);
begin
  FCurrentPitch := APitch;
end;

procedure TSimpleActionActor.SetMoveDirection(const ADirection: TVector3);
begin
  FMoveDirection := ADirection;
end;

procedure TSimpleActionActor.SetJumpKeyPressed(AJump: boolean);
begin
  FIsJumping := AJump;
end;

procedure TSimpleActionActor.SetOnGround(AOnGround: boolean);
begin
  FOnGround := AOnGround;
end;

procedure TSimpleActionActor.SetGroundContactCount(ACount: integer);
begin
  FGroundContactCount := ACount;
end;

procedure TSimpleActionActor.SetIsJumping(AJumping: boolean);
begin
  FIsJumping := AJumping;
end;

{ TActionActor }

constructor TActionActor.Create(AModelPath: string; AParent: TModelEngine; ASize: TVector3;
  AWalkSpeed: single; AJumpForce: single);
begin
  inherited Create(AModelPath, AParent, ASize, kstCapsule);

  FOnGround := False;
  FIsJumping := False;
  FCurrentYaw := 0.0;
  FCurrentPitch := 0.0;
  FTargetYaw := 0.0;
  FGroundContactCount := 0;
  FGroundNormal := Vector3Up;
  FWalkSpeed := AWalkSpeed;
  FJumpForce := AJumpForce;
  FGravityScale := 1.0;
  FLastPosition := Vector3Zero;
  FMoveDirection := Vector3Zero;

  if Assigned(Shape) then
  begin
    Shape.Friction := 0.8;       // higher friction so characters grip the floor
    Shape.Restitution := 0.1;
    Shape.Density := 10.0;
  end;

  if Assigned(Body) then
  begin
    Body.LinearVelocityDamp := 0.5;   // almost no linear damping
    Body.GravityScale := 1.0;         // full gravity

    // Rotation is not locked here: the yaw is applied manually each
    // frame, and a strong angular damping keeps the body from spinning
    Body.AngularVelocityDamp := 10.0;
    Body.GravityScale := 1.0;
    SetRotation(QuaternionIdentity);
  end;
end;

destructor TActionActor.Destroy;
begin
  inherited Destroy;
end;

procedure TActionActor.Update(DeltaTime: single);
var
  MoveDir: TVector3;
  Vel: TKraftVector3;
  Quat: TQuaternion;
  KraftMat: TKraftMatrix3x3;
  AngleDiff: single;
  Force: TVector3;
  CurrentSpeed: single;
  TargetSpeed: single;
begin
  // Hook for input/AI - runs before everything else
  DoBeforeUpdate(DeltaTime);

  // Base update: sync transform from the physics body
  inherited Update(DeltaTime);

  // Smoothly rotate towards the target yaw
  if FTargetYaw <> FCurrentYaw then
  begin
    // Shortest-arc angle difference, then smooth approach
    AngleDiff := FTargetYaw - FCurrentYaw;
    while AngleDiff > PI do AngleDiff := AngleDiff - 2 * PI;
    while AngleDiff < -PI do AngleDiff := AngleDiff + 2 * PI;

    FCurrentYaw := FCurrentYaw + AngleDiff * Min(1.0, 8.0 * DeltaTime);

    Quat := QuaternionFromEuler(0, FCurrentYaw, 0);
    KraftMat := QuaternionToKraftMatrix3x3(Quat);
    Body.SetOrientation(KraftMat);
    SetRotation(Quat);
  end;

  // Movement: force-based instead of directly setting velocity - this
  // keeps collision response intact while accelerating towards the
  // target speed
  MoveDir := GetMoveDirection(DeltaTime);
  FMoveDirection := MoveDir;

  if Assigned(Body) then
  begin
    Vel := Body.LinearVelocity;
    CurrentSpeed := Sqrt(Vel.x*Vel.x + Vel.z*Vel.z);

    if (Vector3Length(MoveDir) > 0) then
    begin
      MoveDir := Vector3Normalize(MoveDir);
      TargetSpeed := FWalkSpeed;

      if CurrentSpeed < TargetSpeed then
      begin
        Force := Vector3Scale(MoveDir, (TargetSpeed - CurrentSpeed) * 8.0);
        ApplyForce(Force);
      end;
    end
    else
    begin
      // Quick stop: counter-force while moving, hard zero below threshold
      if CurrentSpeed > 0.05 then
      begin
        Force := Vector3Scale(Vector3Create(-Vel.x, 0, -Vel.z), 3.0);
        ApplyForce(Force);
      end
      else if CurrentSpeed > 0 then
      begin
        Vel.x := 0;
        Vel.z := 0;
        Body.LinearVelocity := Vel;
      end;
    end;
  end;

  FLastPosition := GetPosition;

  // Jump - uses an impulse instead of directly setting the velocity
  if IsJumpKeyPressed then
    Jump;

  // Hook for animation and post-physics work
  DoAfterUpdate(DeltaTime);
end;

procedure TActionActor.DoBeforeUpdate(DeltaTime: single);
begin
  // Empty by default; override in descendants
end;

procedure TActionActor.DoAfterUpdate(DeltaTime: single);
begin
  // Empty by default; override in descendants
end;

procedure TActionActor.DoOnGroundChanged(NewOnGround: boolean);
begin
  // Empty by default; override in descendants
end;

function TActionActor.GetMoveDirection(DeltaTime: single): TVector3;
begin
  Result := Vector3Zero;
end;

function TActionActor.IsJumpKeyPressed: boolean;
begin
  Result := False;
end;

procedure TActionActor.Jump;
begin
  if FOnGround and not FIsJumping then
  begin
    // Impulse-based jump: works with the solver instead of against it
    ApplyImpulse(Vector3Create(0, FJumpForce, 0));
    FIsJumping := True;
    FOnGround := False;
  end;
end;

procedure TActionActor.SetYaw(AYaw: single);
begin
  FCurrentYaw := AYaw;
  FTargetYaw := AYaw;
  SetRotation(QuaternionFromEuler(0, FCurrentYaw, 0));
end;

procedure TActionActor.SetPitch(APitch: single);
begin
  FCurrentPitch := APitch;
end;

function TActionActor.GetForwardDirection: TVector3;
var
  Quat: TQuaternion;
begin
  // Forward on the XZ plane, derived from the current yaw
  Quat := QuaternionFromEuler(0, FCurrentYaw, 0);
  Result := Vector3RotateByQuaternion(Vector3Create(0, 0, 1), Quat);
  Result.y := 0;
  if Vector3Length(Result) > 0 then
    Result := Vector3Normalize(Result)
  else
    Result := Vector3Create(0, 0, 1);
end;

function TActionActor.GetRightDirection: TVector3;
var
  ForwardDir: TVector3;
begin
  ForwardDir := GetForwardDirection;
  Result := Vector3CrossProduct(ForwardDir, Vector3Up);
  Result.y := 0;
  if Vector3Length(Result) > 0 then
    Result := Vector3Normalize(Result)
  else
    Result := Vector3Create(1, 0, 0);
end;

procedure TActionActor.SetOnGround(AOnGround: boolean);
begin
  FOnGround := AOnGround;
end;

procedure TActionActor.SetGroundContactCount(ACount: integer);
begin
  FGroundContactCount := ACount;
end;

procedure TActionActor.SetIsJumping(AJumping: boolean);
begin
  FIsJumping := AJumping;
end;

end.
