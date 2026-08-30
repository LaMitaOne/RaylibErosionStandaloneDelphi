unit RaylibErosionViewer;


{*******************************************************************************
 *  TRaylibErosionViewer
 *  A high-performance, threaded VCL/FMX component utilizing Raylib for
 *  off-screen rendering. Fully encapsulates the Terrain Erosion island demo.
 *
 *  Original C++ Project:
 *  https://github.com/Delvix000/RaylibErosionStandalone
 *  Ported to Delphi with major architectural improvements.
 *
 *  Key Features of this Delphi Port:
 *  - Threaded Architecture: Separates the entire Raylib Game Loop and Logic
 *    from the UI Thread (similar to Skia4Delphi's threaded renderer).
 *    Increased performance by ~20+ FPS compared to VCL TTimer approaches.
 *  - Encapsulation: The entire Engine (Erosion Math, RLights, Shaders) is
 *    packed into a single, drop-in TWinControl component.
 *
 *  Author: Lara Miriam Tamy Reschke / LamitaOne
 *
 *  Acknowledgements:
 *  - Delvix000 for the original C++ implementation and shaders.
 *******************************************************************************}

{$POINTERMATH ON}
{$Q-} // wraparound integer arithmetic in the hash helpers is intended
{$R-}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math, System.SyncObjs,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics,
  Raylib, RayMath, rlgl;

const
  MAX_LIGHTS = 1;
  MAP_RESOLUTION = 512;
  CLIP_SHADERS_COUNT = 1;
  TREE_TEXTURE_COUNT = 19;
  TREE_COUNT = 4096;

  { Raylib 5.x compatibility aliases }
  UNIFORM_FLOAT       = SHADER_UNIFORM_FLOAT;
  UNIFORM_VEC2        = SHADER_UNIFORM_VEC2;
  UNIFORM_VEC3        = SHADER_UNIFORM_VEC3;
  UNIFORM_VEC4        = SHADER_UNIFORM_VEC4;
  UNIFORM_INT         = SHADER_UNIFORM_INT;
  UNIFORM_IVEC2       = SHADER_UNIFORM_IVEC2;
  UNIFORM_IVEC3       = SHADER_UNIFORM_IVEC3;
  UNIFORM_IVEC4       = SHADER_UNIFORM_IVEC4;
  UNIFORM_SAMPLER2D   = SHADER_UNIFORM_SAMPLER2D;

  LOC_VERTEX_POSITION = SHADER_LOC_VERTEX_POSITION;
  LOC_MATRIX_MODEL    = SHADER_LOC_MATRIX_MODEL;
  LOC_MATRIX_VIEW     = SHADER_LOC_MATRIX_VIEW;
  LOC_MATRIX_PROJECTION = SHADER_LOC_MATRIX_PROJECTION;
  LOC_VECTOR_VIEW     = SHADER_LOC_VECTOR_VIEW;
  LOC_MAP_ALBEDO      = SHADER_LOC_MAP_ALBEDO;
  LOC_MAP_ROUGHNESS   = SHADER_LOC_MAP_ROUGHNESS;
  LOC_MAP_NORMAL      = SHADER_LOC_MAP_NORMAL;
  LOC_MAP_CUBEMAP     = SHADER_LOC_MAP_CUBEMAP;
  LOC_MAP_IRRADIANCE  = SHADER_LOC_MAP_IRRADIANCE;

  FILTER_POINT        = TEXTURE_FILTER_POINT;
  FILTER_BILINEAR     = TEXTURE_FILTER_BILINEAR;
  FILTER_TRILINEAR    = TEXTURE_FILTER_TRILINEAR;

  WRAP_REPEAT         = TEXTURE_WRAP_REPEAT;
  WRAP_CLAMP          = TEXTURE_WRAP_CLAMP;
  WRAP_MIRROR_REPEAT  = TEXTURE_WRAP_MIRROR_REPEAT;
  WRAP_MIRROR_CLAMP   = TEXTURE_WRAP_MIRROR_CLAMP;

  MAP_ROUGHNESS      = 3;
  MAP_CUBEMAP        = 7;
  MAP_IRRADIANCE     = 8;
  CUBEMAP_LAYOUT_PANORAMA = 3;

  DISPLAY_RESOLUTIONS: array[0..4, 0..1] of integer = (
    (320, 180), (640, 360), (1280, 720), (1600, 900), (1920, 1080));

type
  TLightType = (LIGHT_DIRECTIONAL, LIGHT_POINT);
  TGradientType = (gtSquare, gtCircle, gtDiamond, gtStar);

  THeightAndGradient = record
    height: single;
    gradientX: single;
    gradientY: single;
  end;

  TColorRec = record
    r, g, b, a: Byte;
  end;

  TAmbientColor = record
    r, g, b, a: single;
  end;

  TTreeBillboard = record
    texture: TTexture2D;
    position: TVector3;
    scale: single;
    color: TColor;
  end;

  TLight = record
    LType: integer;
    position: TVector3;
    target: TVector3;
    color: TColor;
    enabled: boolean;
    enabledLoc: TArray<integer>;
    typeLoc: TArray<integer>;
    posLoc: TArray<integer>;
    targetLoc: TArray<integer>;
    colorLoc: TArray<integer>;
    shaders: TArray<TShader>;
  end;

  { Internal Erosion Simulator Class }
  TErosionMaker = class
  private
    FBrushOffX: array of TArray<integer>;
    FBrushOffY: array of TArray<integer>;
    FBrushWeights: array of TArray<single>;
    FCurrentErosionRadius: integer;
    FCurrentMapSize: integer;
    FCurrentSeed: integer;

    procedure Initialize(mapSize: integer; resetSeed: boolean);
    function CalculateHeightAndGradient(const mapData: TArray<single>; mapSize: integer; posX, posY: single): THeightAndGradient;
    procedure InitializeBrushIndices(mapSize, radius: integer);
    function RemapValue(value: single): single;
  public
    erosionRadius: integer;
    inertia: single;
    sedimentCapacityFactor: single;
    minSedimentCapacity: single;
    erodeSpeed: single;
    depositSpeed: single;
    evaporateSpeed: single;
    gravity: single;
    maxDropletLifetime: integer;
    initialWaterVolume: single;
    initialSpeed: single;

    constructor Create;
    procedure Erode(var mapData: TArray<single>; mapSize: integer; dropletAmount: integer = 1; resetSeed: boolean = False);
    procedure Gradient(var mapData: TArray<single>; mapSize: integer; normalizedOffset: single; gradientType: TGradientType);
    function GetNormal(const mapData: TArray<single>; mapSize, x, y: integer): TVector3;
    procedure Remap(var mapData: TArray<single>; mapSize: integer);
  end;

  { Main Threaded Component }
  TRaylibErosionViewer = class(TWinControl)
  private
    { Threading & Sync }
    FThread: TThread;
    FLock: TCriticalSection;
    FTargetFPS: Integer;
    FThreadActive: Boolean;
    FPaused: Boolean;
    FActive: Boolean;

    { Raylib State }
    FRaylibWnd: HWND;
    FInitialized: Boolean;
    FTxtBuf: AnsiString;

    { FBOs / Post-Processing }
    FPostProcessShader: TShader;
    FApplicationBuffer: TRenderTexture2D;
    FReflectionBuffer: TRenderTexture2D;
    FRefractionBuffer: TRenderTexture2D;
    FBoSize: single;
    FUseApplicationBuffer: boolean;
    FLockTo60FPS: boolean;

    { Day/Night }
    FDayTime: single;
    FDaySpeed: single;
    FDayRunning: boolean;
    FAmbc: array[0..3] of single;
    FAmbientColors: TArray<TAmbientColor>;
    FLightRadius: single;

    { Erosion / Heightmap }
    FErosion: TErosionMaker;
    FMap: TArray<single>;
    FInitialMap: TArray<single>;
    FPixels: TArray<TColor>;
    FHeightmapTexture: TTexture2D;
    FTotalDroplets: integer;
    FDropletsSinceTreeRegen: integer;

    { Terrain, Water, Clouds, Sky, Trees, Lights }
    FTerrainModel: TModel;
    FTerrainShader: TShader;
    FTerrainGradient: TTexture2D;
    FRockNormalMap: TTexture2D;
    FTerrainDaytimeLoc: integer;
    FTerrainAmbientLoc: integer;

    FOceanModel: TModel;
    FOceanShader: TShader;
    FOceanFloorModel: TModel;
    FWhiteTexture: TTexture2D;
    FDUDVTex: TTexture2D;
    FWaterMoveFactor: single;
    FWaterMoveFactorLoc: integer;

    FCloudModel: TModel;
    FCloudShader: TShader;
    FCloudTexture: TTexture2D;
    FCloudMoveFactor: single;
    FCloudMoveFactorLoc: integer;
    FCloudDaytimeLoc: integer;

    FSkybox: TModel;
    FSkyboxShader: TShader;
    FSkyboxDaytimeLoc: integer;
    FSkyboxDayrotationLoc: integer;
    FSkyboxMoveFactor: single;
    FSkyboxMoveFactorLoc: integer;

    FTreeTextures: array[0..TREE_TEXTURE_COUNT - 1] of TTexture2D;
    FTrees: TArray<TTreeBillboard>;
    FTreeShader: TShader;
    FTreeMaterial: TMaterial;
    FTreeMoveFactor: single;
    FTreeMoveFactorLoc: integer;
    FTreeAmbientLoc: integer;

    FLights: array[0..MAX_LIGHTS - 1] of TLight;

    { Window & Camera state }
    FWindowWidthBeforeFullscreen: integer;
    FWindowHeightBeforeFullscreen: integer;
    FWindowSizeChanged: boolean;
    FFullscreen: boolean;
    FCurrentDisplayResolutionIndex: integer;
    FPrevKeys: array[0..255] of boolean;
    FNoiseSeed: integer;
    FCamera: TCamera3D;
    FCamYaw, FCamPitch, FCamDist: single;
    FDragging: boolean;
    FLastMouse: TPoint;
    FCursorHidden: boolean;
    FRDragging: boolean;

    { Clip Shaders }
    clipShaders: array[0..CLIP_SHADERS_COUNT - 1] of TShader;
    clipShaderHeightLocs: array[0..CLIP_SHADERS_COUNT - 1] of integer;
    clipShaderTypeLocs: array[0..CLIP_SHADERS_COUNT - 1] of integer;
    ClipShadersCount: integer;

    { Internal Methods }
    function Txt(const AText: string): PAnsiChar;
    function KeyDown(vk: integer): boolean;
    function KeyPressed(vk: integer): boolean;
    procedure LoadAmbientColors;
    procedure GenerateInitialHeightmap;
    procedure NormalizeMap;
    function CreateTextureFromPixels: TTexture2D;
    procedure InitTerrain;
    procedure InitOcean;
    procedure InitClouds;
    procedure InitSkybox;
    procedure InitTrees;
    procedure InitLight;
    function GenTextureCubemap(panorama: TTexture2D): TTexture2D;
    procedure BindSamplerUniforms(shader: TShader; count: integer);
    procedure UpdateHeightmapPixels;
    procedure UpdateHeightmapTexture;
    procedure GenerateTrees(generateNew: boolean);
    procedure RebuildBuffers;
    procedure ResetIsland(gradientType: TGradientType);
    procedure ToggleFullscreenVCL;
    procedure HandleCameraInput;
    procedure UpdateGame;
    procedure HandleGameplayInput;
    procedure RenderGame;
    procedure Render3DScene(const camera: TCamera3D; const models: array of TModel; const trees: array of TTreeBillboard; clipPlane: integer);
    procedure DrawGUI;

    { Setters }
    procedure SetActive(const Value: Boolean);
    procedure SetTargetFPS(const Value: Integer);
    procedure StartThread;
    procedure StopThread;
    procedure ThreadSafeInvalidate;
  protected
    procedure Resize; override;
    procedure CreateWindowHandle(const Params: TCreateParams); override;
    procedure DestroyWindowHandle; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Align;
    property Anchors;
    property Visible;
    property Active: Boolean read FActive write SetActive default False;
    property TargetFPS: Integer read FTargetFPS write SetTargetFPS default 60;
  end;

  { Utility Functions }
function CreateLight(alType: integer; position, target: TVector3; color: TColor; const shaders: array of TShader): TLight;
procedure UpdateLightValues(const light: TLight);
function AddClipShader(var Viewer: TRaylibErosionViewer; shader: TShader): integer;

implementation

{ ------------------------- Utility Functions ------------------------------- }

function LerpF(a, b, t: single): single; inline;
begin
  Result := a + (b - a) * t;
end;

function Clamp01(v: single): single; inline;
begin
  if v < 0 then Result := 0
  else if v > 1 then Result := 1
  else Result := v;
end;

function MinF(a, b: single): single; inline;
begin
  if a < b then Result := a else Result := b;
end;

function MaxF(a, b: single): single; inline;
begin
  if a > b then Result := a else Result := b;
end;

function RandomRangeF(aMin, aMax: single): single; inline;
begin
  Result := aMin + Random * (aMax - aMin);
end;

{ ------------------------- RLights Implementation -------------------------- }

function CreateLight(alType: integer; position, target: TVector3; color: TColor; const shaders: array of TShader): TLight;
var
  i: integer;
  enabledName, typeName, posName, targetName, colorName: AnsiString;
  LightsCount: integer;
begin
  Result := Default(TLight);
  LightsCount := 0; // Static count managed internally or externally

  if LightsCount < MAX_LIGHTS then
  begin
    Result.enabled := True;
    Result.LType := alType;
    Result.position := position;
    Result.target := target;
    Result.color := color;

    enabledName := AnsiString(Format('lights[%d].enabled', [LightsCount]));
    typeName := AnsiString(Format('lights[%d].type', [LightsCount]));
    posName := AnsiString(Format('lights[%d].position', [LightsCount]));
    targetName := AnsiString(Format('lights[%d].target', [LightsCount]));
    colorName := AnsiString(Format('lights[%d].color', [LightsCount]));

    SetLength(Result.enabledLoc, Length(shaders));
    SetLength(Result.typeLoc, Length(shaders));
    SetLength(Result.posLoc, Length(shaders));
    SetLength(Result.targetLoc, Length(shaders));
    SetLength(Result.colorLoc, Length(shaders));
    SetLength(Result.shaders, Length(shaders));

    for i := 0 to High(shaders) do
    begin
      Result.enabledLoc[i] := GetShaderLocation(shaders[i], PAnsiChar(enabledName));
      Result.typeLoc[i] := GetShaderLocation(shaders[i], PAnsiChar(typeName));
      Result.posLoc[i] := GetShaderLocation(shaders[i], PAnsiChar(posName));
      Result.targetLoc[i] := GetShaderLocation(shaders[i], PAnsiChar(targetName));
      Result.colorLoc[i] := GetShaderLocation(shaders[i], PAnsiChar(colorName));
      Result.shaders[i] := shaders[i];
    end;
  end;
end;

procedure UpdateLightValues(const light: TLight);
var
  i: integer;
  enabled, ltype: integer;
  position, target: array[0..2] of single;
  color: array[0..3] of single;
begin
  for i := 0 to High(light.shaders) do
  begin
    enabled := Ord(light.enabled);
    ltype := light.LType;
    SetShaderValue(light.shaders[i], light.enabledLoc[i], @enabled, SHADER_UNIFORM_INT);
    SetShaderValue(light.shaders[i], light.typeLoc[i], @ltype, SHADER_UNIFORM_INT);

    position[0] := light.position.x;
    position[1] := light.position.y;
    position[2] := light.position.z;
    SetShaderValue(light.shaders[i], light.posLoc[i], @position, SHADER_UNIFORM_VEC3);

    target[0] := light.target.x;
    target[1] := light.target.y;
    target[2] := light.target.z;
    SetShaderValue(light.shaders[i], light.targetLoc[i], @target, SHADER_UNIFORM_VEC3);

    color[0] := light.color.r / 255.0;
    color[1] := light.color.g / 255.0;
    color[2] := light.color.b / 255.0;
    color[3] := light.color.a / 255.0;
    SetShaderValue(light.shaders[i], light.colorLoc[i], @color, SHADER_UNIFORM_VEC4);
  end;
end;

function AddClipShader(var Viewer: TRaylibErosionViewer; shader: TShader): integer;
begin
  Viewer.clipShaders[Viewer.ClipShadersCount] := shader;
  Viewer.clipShaderHeightLocs[Viewer.ClipShadersCount] := GetShaderLocation(shader, 'cullHeight');
  Viewer.clipShaderTypeLocs[Viewer.ClipShadersCount] := GetShaderLocation(shader, 'cullType');
  Result := Viewer.ClipShadersCount;
  Inc(Viewer.ClipShadersCount);
end;

{ ------------------------- Perlin-fBm Noise ------------------------------- }

var
  Permutation: array[0..511] of Byte;

const
  GRAD_X: array[0..7] of single = (1, -1, 1, -1, 1, -1, 0, 0);
  GRAD_Y: array[0..7] of single = (1, 1, -1, -1, 0, 0, 1, -1);

procedure InitPerlin(seed: integer);
var
  i, j, t: integer;
  state: Cardinal;
begin
  state := (Cardinal(seed) * 2654435761) xor $9E3779B9;
  for i := 0 to 255 do
    Permutation[i] := i;
  for i := 255 downto 1 do
  begin
    state := state * 1664525 + 1013904223;   // intended wraparound
    j := (state shr 16) mod Cardinal(i + 1);
    t := Permutation[i];
    Permutation[i] := Permutation[j];
    Permutation[j] := t;
  end;
  for i := 0 to 255 do
    Permutation[256 + i] := Permutation[i];
end;

function Perlin2D(x, y: single): single;
var
  xi, yi: integer;
  fx, fy, u, v: single;
  g00, g10, g01, g11: integer;
begin
  xi := Floor(x);
  yi := Floor(y);
  fx := x - xi;
  fy := y - yi;
  u := fx * fx * fx * (fx * (fx * 6 - 15) + 10);
  v := fy * fy * fy * (fy * (fy * 6 - 15) + 10);
  xi := xi and 255;
  yi := yi and 255;
  g00 := Permutation[Permutation[xi] + yi] and 7;
  g10 := Permutation[Permutation[xi + 1] + yi] and 7;
  g01 := Permutation[Permutation[xi] + yi + 1] and 7;
  g11 := Permutation[Permutation[xi + 1] + yi + 1] and 7;
  Result := LerpF(
    LerpF(GRAD_X[g00] * fx + GRAD_Y[g00] * fy,
          GRAD_X[g10] * (fx - 1) + GRAD_Y[g10] * fy, u),
    LerpF(GRAD_X[g01] * fx + GRAD_Y[g01] * (fy - 1),
          GRAD_X[g11] * (fx - 1) + GRAD_Y[g11] * (fy - 1), u),
    v);
end;

function Fbm(x, y: single): single;
var
  sum, amp, norm, freq: single;
  o: integer;
begin
  sum := 0; amp := 1; norm := 0; freq := 1;
  for o := 1 to 5 do
  begin
    sum := sum + Perlin2D(x * freq, y * freq) * amp;
    norm := norm + amp;
    amp := amp * 0.5;
    freq := freq * 2.0;
  end;
  Result := sum / norm;
end;

{ ------------------------- TErosionMaker ------------------------------- }

constructor TErosionMaker.Create;
begin
  inherited Create;
  erosionRadius := 6;
  inertia := 0.05;
  sedimentCapacityFactor := 6.0;
  minSedimentCapacity := 0.01;
  erodeSpeed := 0.3;
  depositSpeed := 0.3;
  evaporateSpeed := 0.01;
  gravity := 4.0;
  maxDropletLifetime := 60;
  initialWaterVolume := 1.0;
  initialSpeed := 1.0;
  FCurrentErosionRadius := -1;
  FCurrentMapSize := -1;
end;

procedure TErosionMaker.Initialize(mapSize: integer; resetSeed: boolean);
begin
  if resetSeed then
  begin
    Randomize;
    FCurrentSeed := RandSeed;
  end;

  if (FCurrentErosionRadius <> erosionRadius) or (FCurrentMapSize <> mapSize) then
  begin
    InitializeBrushIndices(mapSize, erosionRadius);
    FCurrentErosionRadius := erosionRadius;
    FCurrentMapSize := mapSize;
  end;
end;

procedure TErosionMaker.Erode(var mapData: TArray<single>; mapSize, dropletAmount: integer; resetSeed: boolean);
var
  iteration, lifetime: integer;
  posX, posY: single;
  dirX, dirY: single;
  speed, water, sediment: single;
  nodeX, nodeY, dropletIndex: integer;
  cellOffsetX, cellOffsetY: single;
  hg: THeightAndGradient;
  len, newHeight, deltaHeight: single;
  sedimentCapacity, amountToDeposit, amountToErode: single;
  speedSq: single;
  offX, offY: TArray<integer>;
  wArr: TArray<single>;
  j, nodeIndex: integer;
  weighedErodeAmount, deltaSediment: single;
begin
  Initialize(mapSize, resetSeed);

  for iteration := 1 to dropletAmount do
  begin
    posX := Random(mapSize - 1);
    posY := Random(mapSize - 1);
    dirX := 0;
    dirY := 0;
    speed := initialSpeed;
    water := initialWaterVolume;
    sediment := 0;

    for lifetime := 0 to maxDropletLifetime - 1 do
    begin
      nodeX := Trunc(posX);
      nodeY := Trunc(posY);
      dropletIndex := nodeY * mapSize + nodeX;
      cellOffsetX := posX - nodeX;
      cellOffsetY := posY - nodeY;

      hg := CalculateHeightAndGradient(mapData, mapSize, posX, posY);

      dirX := dirX * inertia - hg.gradientX * (1 - inertia);
      dirY := dirY * inertia - hg.gradientY * (1 - inertia);

      len := Sqrt(dirX * dirX + dirY * dirY);
      if len > 0.0001 then
      begin
        dirX := dirX / len;
        dirY := dirY / len;
      end;

      posX := posX + dirX;
      posY := posY + dirY;

      if ((dirX = 0) and (dirY = 0)) or (posX < 0) or (posX >= mapSize - 1) or
         (posY < 0) or (posY >= mapSize - 1) then
        Break;

      newHeight := CalculateHeightAndGradient(mapData, mapSize, posX, posY).height;
      deltaHeight := newHeight - hg.height;

      sedimentCapacity := MaxF(-deltaHeight * speed * water * sedimentCapacityFactor,
        minSedimentCapacity);

      if (sediment > sedimentCapacity) or (deltaHeight > 0) then
      begin
        if deltaHeight > 0 then
          amountToDeposit := MinF(deltaHeight, sediment)
        else
          amountToDeposit := (sediment - sedimentCapacity) * depositSpeed;
        sediment := sediment - amountToDeposit;

        mapData[dropletIndex] := mapData[dropletIndex] +
          amountToDeposit * (1 - cellOffsetX) * (1 - cellOffsetY);
        mapData[dropletIndex + 1] := mapData[dropletIndex + 1] +
          amountToDeposit * cellOffsetX * (1 - cellOffsetY);
        mapData[dropletIndex + mapSize] := mapData[dropletIndex + mapSize] +
          amountToDeposit * (1 - cellOffsetX) * cellOffsetY;
        mapData[dropletIndex + mapSize + 1] := mapData[dropletIndex + mapSize + 1] +
          amountToDeposit * cellOffsetX * cellOffsetY;
      end
      else
      begin
        amountToErode := MinF((sedimentCapacity - sediment) * erodeSpeed, -deltaHeight);

        offX := FBrushOffX[dropletIndex];
        offY := FBrushOffY[dropletIndex];
        wArr := FBrushWeights[dropletIndex];

        for j := 0 to High(offX) do
        begin
          nodeIndex := (nodeY + offY[j]) * mapSize + nodeX + offX[j];
          weighedErodeAmount := amountToErode * wArr[j];
          deltaSediment := mapData[nodeIndex];
          if deltaSediment > weighedErodeAmount then
            deltaSediment := weighedErodeAmount;
          mapData[nodeIndex] := mapData[nodeIndex] - deltaSediment;
          sediment := sediment + deltaSediment;
        end;
      end;

      speedSq := speed * speed + deltaHeight * gravity;
      if speedSq < 0 then
        speed := 0
      else
        speed := Sqrt(speedSq);
      water := water * (1 - evaporateSpeed);
    end;
  end;
end;

procedure TErosionMaker.Gradient(var mapData: TArray<single>; mapSize: integer; normalizedOffset: single; gradientType: TGradientType);
var
  x, y, index: integer;
  radius, gradient, g1, g2: single;
begin
  radius := mapSize / 2.0;
  for y := 0 to mapSize - 1 do
    for x := 0 to mapSize - 1 do
    begin
      index := y * mapSize + x;
      case gradientType of
        gtSquare:    gradient := MaxF(Abs(x - radius), Abs(y - radius)) / radius;
        gtCircle:    gradient := MinF(((x - radius) * (x - radius) +
                          (y - radius) * (y - radius)) / (radius * radius), 1.0);
        gtDiamond:   gradient := MinF((Abs(x - radius) + Abs(y - radius)) / radius, 1.0);
        gtStar:      begin
                      g1 := MinF((Abs(x - radius) + Abs(y - radius)) / radius, 1.0);
                      g2 := MaxF(Abs(x - radius), Abs(y - radius)) / radius;
                      gradient := LerpF(g1, g2, 0.7);
                    end;
      else
        gradient := MinF(((x - radius) * (x - radius) +
                          (y - radius) * (y - radius)) / (radius * radius), 1.0);
      end;
      gradient := 1 - gradient;
      mapData[index] := mapData[index] * gradient;
    end;
end;

function TErosionMaker.CalculateHeightAndGradient(const mapData: TArray<single>;
  mapSize: integer; posX, posY: single): THeightAndGradient;
var
  coordX, coordY: integer;
  x, y: single;
  nodeIndexNW: integer;
  heightNW, heightNE, heightSW, heightSE: single;
begin
  coordX := Trunc(posX);
  coordY := Trunc(posY);

  x := posX - coordX;
  y := posY - coordY;

  nodeIndexNW := coordY * mapSize + coordX;

  heightNW := mapData[nodeIndexNW];
  heightNE := mapData[nodeIndexNW + 1];
  heightSW := mapData[nodeIndexNW + mapSize];
  heightSE := mapData[nodeIndexNW + mapSize + 1];

  Result.gradientX := (heightNE - heightNW) * (1 - y) + (heightSE - heightSW) * y;
  Result.gradientY := (heightSW - heightNW) * (1 - x) + (heightSE - heightNE) * x;

  Result.height := heightNW * (1 - x) * (1 - y) + heightNE * x * (1 - y) +
                   heightSW * (1 - x) * y + heightSE * x * y;
end;

procedure TErosionMaker.InitializeBrushIndices(mapSize, radius: integer);
var
  discX, discY: TArray<integer>;
  discW: TArray<single>;
  discCount, k, i, x, y: integer;
  centreX, centreY, coordX, coordY: integer;
  weightSum: single;
  fullX, fullY: TArray<integer>;
  fullW: TArray<single>;
  cx, cy: TArray<integer>;
  cw: TArray<single>;
  addIndex: integer;
  clipped: boolean;
begin
  SetLength(discX, radius * radius * 4);
  SetLength(discY, radius * radius * 4);
  SetLength(discW, radius * radius * 4);
  discCount := 0;
  for y := -radius to radius do
    for x := -radius to radius do
      if (x * x + y * y) < (radius * radius) then
      begin
        discX[discCount] := x;
        discY[discCount] := y;
        discW[discCount] := 1 - Sqrt(x * x + y * y) / radius;
        Inc(discCount);
      end;

  SetLength(fullX, discCount);
  SetLength(fullY, discCount);
  SetLength(fullW, discCount);
  weightSum := 0;
  for k := 0 to discCount - 1 do
    weightSum := weightSum + discW[k];
  for k := 0 to discCount - 1 do
  begin
    fullX[k] := discX[k];
    fullY[k] := discY[k];
    fullW[k] := discW[k] / weightSum;
  end;

  SetLength(FBrushOffX, mapSize * mapSize);
  SetLength(FBrushOffY, mapSize * mapSize);
  SetLength(FBrushWeights, mapSize * mapSize);

  SetLength(cx, discCount);
  SetLength(cy, discCount);
  SetLength(cw, discCount);

  for i := 0 to mapSize * mapSize - 1 do
  begin
    centreX := i mod mapSize;
    centreY := i div mapSize;

    clipped := False;
    addIndex := 0;
    weightSum := 0;
    for k := 0 to discCount - 1 do
    begin
      coordX := centreX + discX[k];
      coordY := centreY + discY[k];
      if (coordX >= 0) and (coordX < mapSize) and
         (coordY >= 0) and (coordY < mapSize) then
      begin
        cx[addIndex] := discX[k];
        cy[addIndex] := discY[k];
        cw[addIndex] := discW[k];
        weightSum := weightSum + cw[addIndex];
        Inc(addIndex);
      end
      else
        clipped := True;
    end;

    if not clipped then
    begin
      FBrushOffX[i] := fullX;
      FBrushOffY[i] := fullY;
      FBrushWeights[i] := fullW;
    end
    else
    begin
      SetLength(FBrushOffX[i], addIndex);
      SetLength(FBrushOffY[i], addIndex);
      SetLength(FBrushWeights[i], addIndex);
      if weightSum > 0 then
        for k := 0 to addIndex - 1 do
        begin
          FBrushOffX[i][k] := cx[k];
          FBrushOffY[i][k] := cy[k];
          FBrushWeights[i][k] := cw[k] / weightSum;
        end;
    end;
  end;
end;

function TErosionMaker.RemapValue(value: single): single;
const
  PX: array[0..3] of single = (0.0, 0.15, 0.2, 1.0);
  PY: array[0..3] of single = (0.0, 0.16, 0.16, 1.0);
var
  i: integer;
begin
  if value < 0 then
    Exit(value);
  for i := 1 to 3 do
    if value < PX[i] then
      Exit(LerpF(PY[i - 1], PY[i], (value - PX[i - 1]) / (PX[i] - PX[i - 1])));
  Result := value;
end;

function TErosionMaker.GetNormal(const mapData: TArray<single>;
  mapSize, x, y: integer): TVector3;
const
  strength = 20.0;
var
  u, v: integer;
  bl, b, br, l, r, tl, t, tr: single;
  dX, dY: single;
begin
  u := EnsureRange(x - 1, 0, mapSize - 1); v := EnsureRange(y + 1, 0, mapSize - 1);
  bl := mapData[v * mapSize + u];
  u := EnsureRange(x, 0, mapSize - 1);     v := EnsureRange(y + 1, 0, mapSize - 1);
  b := mapData[v * mapSize + u];
  u := EnsureRange(x + 1, 0, mapSize - 1); v := EnsureRange(y + 1, 0, mapSize - 1);
  br := mapData[v * mapSize + u];
  u := EnsureRange(x - 1, 0, mapSize - 1); v := EnsureRange(y, 0, mapSize - 1);
  l := mapData[v * mapSize + u];
  u := EnsureRange(x + 1, 0, mapSize - 1); v := EnsureRange(y, 0, mapSize - 1);
  r := mapData[v * mapSize + u];
  u := EnsureRange(x - 1, 0, mapSize - 1); v := EnsureRange(y - 1, 0, mapSize - 1);
  tl := mapData[v * mapSize + u];
  u := EnsureRange(x, 0, mapSize - 1);     v := EnsureRange(y - 1, 0, mapSize - 1);
  t := mapData[v * mapSize + u];
  u := EnsureRange(x + 1, 0, mapSize - 1); v := EnsureRange(y - 1, 0, mapSize - 1);
  tr := mapData[v * mapSize + u];

  dX := tr + 2.0 * r + br - tl - 2.0 * l - bl;
  dY := bl + 2.0 * b + br - tl - 2.0 * t - tr;

  Result := Vector3Normalize(Vector3Create(-dX, 1.0 / strength, -dY));
end;

procedure TErosionMaker.Remap(var mapData: TArray<single>; mapSize: integer);
var
  i: integer;
begin
  for i := 0 to mapSize * mapSize - 1 do
    mapData[i] := RemapValue(mapData[i]);
end;

{ ------------------------- TRaylibErosionViewer ------------------------------- }

constructor TRaylibErosionViewer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  FThreadActive := False;
  FPaused := True;
  FActive := False;
  FTargetFPS := 60;
  Width := 800;
  Height := 600;
  FInitialized := False;
  ClipShadersCount := 0;
end;

destructor TRaylibErosionViewer.Destroy;
begin
  StopThread;
  FreeAndNil(FLock);
  inherited;
end;

procedure TRaylibErosionViewer.CreateWindowHandle(const Params: TCreateParams);
begin
  inherited;
  // Window handle is created, ready for embedding when thread starts
end;

procedure TRaylibErosionViewer.DestroyWindowHandle;
begin
  StopThread;
  inherited;
end;

procedure TRaylibErosionViewer.Resize;
begin
  inherited;
  if FInitialized and (FRaylibWnd <> 0) then
    SetWindowPos(FRaylibWnd, 0, 0, 0, ClientWidth, ClientHeight, SWP_NOZORDER);
end;

procedure TRaylibErosionViewer.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    FActive := Value;
    if FActive then
    begin
      if not FThreadActive then
        StartThread;
      FPaused := False;
    end
    else
      FPaused := True;
  end;
end;

procedure TRaylibErosionViewer.SetTargetFPS(const Value: Integer);
begin
  if FTargetFPS <> Value then
    FTargetFPS := Value;
end;

procedure TRaylibErosionViewer.ThreadSafeInvalidate;
begin
  if csDestroying in ComponentState then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) and Assigned(Self) then
        Self.Invalidate;
    end);
end;

procedure TRaylibErosionViewer.StartThread;
begin
  if FThreadActive then Exit;
  FThreadActive := True;

  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LastTime, CurrentTime: Cardinal;
      DeltaSec: Double;
      SleepTime: Integer;
    begin
      try
        // 1. RAYLIB INITIALIZATION (In Thread)
        SetConfigFlags(FLAG_WINDOW_RESIZABLE or FLAG_MSAA_4X_HINT);
        InitWindow(1280, 720, 'Delphi Terrain Erosion');

        FRaylibWnd := FindWindow(nil, 'Delphi Terrain Erosion');
        if FRaylibWnd <> 0 then
        begin
          Winapi.Windows.SetParent(FRaylibWnd, Self.Handle);
          SetWindowLong(FRaylibWnd, GWL_STYLE, WS_CHILD or WS_VISIBLE);
          SetWindowPos(FRaylibWnd, 0, 0, 0, Self.ClientWidth, Self.ClientHeight, SWP_NOZORDER);
        end;

        // 2. ASSET & SCENE INIT
        Randomize;
        FNoiseSeed := Random(MaxInt);
        FBoSize := 2.5;
        FUseApplicationBuffer := False;
        FLockTo60FPS := False;
        FDayTime := 0.2;
        FDaySpeed := 0.015;
        FDayRunning := True;
        FAmbc[0] := 0.22; FAmbc[1] := 0.17; FAmbc[2] := 0.41; FAmbc[3] := 0.2;
        FCurrentDisplayResolutionIndex := 2;
        FCursorHidden := False;
        FTotalDroplets := 0;
        FDropletsSinceTreeRegen := 0;
        FWaterMoveFactor := 0; FCloudMoveFactor := 0; FSkyboxMoveFactor := 0; FTreeMoveFactor := 0;
        FLightRadius := 100.0;
        FWindowSizeChanged := False;
        FFullscreen := False;
        FillChar(FPrevKeys, SizeOf(FPrevKeys), 0);
        FCamYaw := 0.5; FCamPitch := 0.9; FCamDist := 42;
        FDragging := False;
        FCamera.target := Vector3Create(0, 1.5, 0);

        FPostProcessShader := LoadShader(nil, 'resources/shaders/postprocess.frag');
        FApplicationBuffer := LoadRenderTexture(GetScreenWidth(), GetScreenHeight());
        FReflectionBuffer := LoadRenderTexture(Trunc(GetScreenWidth() / FBoSize), Trunc(GetScreenHeight() / FBoSize));
        FRefractionBuffer := LoadRenderTexture(Trunc(GetScreenWidth() / FBoSize), Trunc(GetScreenHeight() / FBoSize));
        SetTextureFilter(FReflectionBuffer.texture, FILTER_BILINEAR);
        SetTextureFilter(FRefractionBuffer.texture, FILTER_BILINEAR);

        FCamera.position := Vector3Create(12.0, 32.0, 22.0);
        FCamera.target := Vector3Create(0, 0, 0);
        FCamera.up := Vector3Create(0, 1, 0);
        FCamera.fovy := 45.0;
        FCamera.projection := CAMERA_PERSPECTIVE;

        LoadAmbientColors;

        FErosion := TErosionMaker.Create;
        GenerateInitialHeightmap;
        FErosion.Gradient(FMap, MAP_RESOLUTION, 0.5, gtSquare);
        FErosion.Remap(FMap, MAP_RESOLUTION);
        FErosion.Erode(FMap, MAP_RESOLUTION, 0, True);
        UpdateHeightmapPixels;
        FHeightmapTexture := CreateTextureFromPixels;
        SetTextureFilter(FHeightmapTexture, FILTER_BILINEAR);
        SetTextureWrap(FHeightmapTexture, WRAP_CLAMP);
        GenTextureMipmaps(@FHeightmapTexture);

        InitTerrain; InitOcean; InitClouds; InitSkybox; InitTrees; InitLight;

        FInitialized := True;
        LastTime := TThread.GetTickCount;

        // 3. THREAD GAME LOOP
        while not TThread.CheckTerminated do
        begin
          CurrentTime := TThread.GetTickCount;
          DeltaSec := (CurrentTime - LastTime) / 1000.0;
          LastTime := CurrentTime;

          if WindowShouldClose() then Break;

          if not FPaused then
            UpdateGame;

          RenderGame;

          // FPS Control
          if FTargetFPS > 0 then SleepTime := Round(1000 / FTargetFPS)
          else SleepTime := 16;
          Sleep(SleepTime);
        end;

        // 4. CLEANUP
        FInitialized := False;
        if Assigned(FErosion) then FreeAndNil(FErosion);

        UnloadRenderTexture(FApplicationBuffer);
        UnloadRenderTexture(FReflectionBuffer);
        UnloadRenderTexture(FRefractionBuffer);
        CloseWindow();

      except
        on E: Exception do
          OutputDebugString(PChar('Raylib Thread Exception: ' + E.Message));
      end;
      FThreadActive := False;
    end);

  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TRaylibErosionViewer.StopThread;
begin
  if not FThreadActive then Exit;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(100); // Let loop finish gracefully
  end;
end;

{ ------------------------- Viewer Internal Methods --------------------------- }

function TRaylibErosionViewer.Txt(const AText: string): PAnsiChar;
begin
  FTxtBuf := AnsiString(AText);
  Result := PAnsiChar(FTxtBuf);
end;

function TRaylibErosionViewer.KeyDown(vk: integer): boolean;
begin
  Result := (GetAsyncKeyState(vk) and $8000) <> 0;
end;

function TRaylibErosionViewer.KeyPressed(vk: integer): boolean;
begin
  Result := KeyDown(vk) and not FPrevKeys[vk and 255];
  FPrevKeys[vk and 255] := KeyDown(vk);
end;

procedure TRaylibErosionViewer.LoadAmbientColors;
var
  img: TImage;
  src: ^TColorRec; // <-- HIER ÄNDERN: PColor -> ^TColorRec
  i: integer;
begin
  img := LoadImage('resources/ambientGradient.png');
  SetLength(FAmbientColors, img.width);
  src := img.data; // <-- Das funktioniert jetzt direkt, da TImage.data per PointerMath auf src[i] zugreift
  for i := 0 to img.width - 1 do
  begin
    FAmbientColors[i].r := src[i].r / 255.0; // .0 hinzugefügt, damit Extended-Typ eindeutig ist
    FAmbientColors[i].g := src[i].g / 255.0;
    FAmbientColors[i].b := src[i].b / 255.0;
    FAmbientColors[i].a := src[i].a / 255.0;
  end;
  UnloadImage(img);

  if Length(FAmbientColors) = 0 then
  begin
    SetLength(FAmbientColors, 1);
    FAmbientColors[0].r := 0.22;
    FAmbientColors[0].g := 0.17;
    FAmbientColors[0].b := 0.41;
    FAmbientColors[0].a := 1.0;
  end;
end;

procedure TRaylibErosionViewer.GenerateInitialHeightmap;
var
  x, y, i: integer;
  n: single;
begin
  SetLength(FMap, MAP_RESOLUTION * MAP_RESOLUTION);
  SetLength(FPixels, MAP_RESOLUTION * MAP_RESOLUTION);

  InitPerlin(FNoiseSeed);
  for y := 0 to MAP_RESOLUTION - 1 do
    for x := 0 to MAP_RESOLUTION - 1 do
    begin
      n := Perlin2D(x / MAP_RESOLUTION * 4.0  + 50, y / MAP_RESOLUTION * 4.0  + 50)
         + 0.5   * Perlin2D(x / MAP_RESOLUTION * 8.0  + 50, y / MAP_RESOLUTION * 8.0  + 50)
         + 0.25  * Perlin2D(x / MAP_RESOLUTION * 16.0 + 50, y / MAP_RESOLUTION * 16.0 + 50)
         + 0.125 * Perlin2D(x / MAP_RESOLUTION * 32.0 + 50, y / MAP_RESOLUTION * 32.0 + 50);
      n := n / 1.875;

      if n < -1 then n := -1;
      if n > 1 then n := 1;
      i := y * MAP_RESOLUTION + x;
      FMap[i] := (n + 1.0) / 2.0;
    end;

  FInitialMap := Copy(FMap, 0, Length(FMap));
end;

procedure TRaylibErosionViewer.NormalizeMap;
var
  i: integer;
  minV, maxV: single;
begin
  minV := MaxSingle;
  maxV := -MaxSingle;
  for i := 0 to High(FMap) do
  begin
    if FMap[i] < minV then minV := FMap[i];
    if FMap[i] > maxV then maxV := FMap[i];
  end;
  if maxV > minV then
    for i := 0 to High(FMap) do
      FMap[i] := (FMap[i] - minV) / (maxV - minV);
end;

function TRaylibErosionViewer.CreateTextureFromPixels: TTexture2D;
var
  img: TImage;
begin
  img := GenImageColor(MAP_RESOLUTION, MAP_RESOLUTION, BLACK);
  MoveMemory(img.data, @FPixels[0], MAP_RESOLUTION * MAP_RESOLUTION * SizeOf(TColor));
  Result := LoadTextureFromImage(img);
end;

procedure TRaylibErosionViewer.UpdateHeightmapPixels;
var
  i, v: integer;
begin
  for i := 0 to High(FMap) do
  begin
    v := Trunc(FMap[i] * 255);
    if v < 0 then v := 0;
    if v > 255 then v := 255;
    FPixels[i].r := v;
    FPixels[i].g := v;
    FPixels[i].b := v;
    FPixels[i].a := 255;
  end;
end;

procedure TRaylibErosionViewer.UpdateHeightmapTexture;
begin
  UpdateHeightmapPixels;
  UpdateTexture(FHeightmapTexture, @FPixels[0]);
  GenTextureMipmaps(@FHeightmapTexture);
end;

procedure TRaylibErosionViewer.InitTerrain;
var
  mesh: TMesh;
  param10: single;
  param11: integer;
  cs: integer;
  v, loc: integer;
begin
  mesh := GenMeshPlane(32, 32, 256, 256);
  FTerrainGradient := LoadTexture('resources/terrainGradient.png');
  SetTextureWrap(FTerrainGradient, WRAP_CLAMP);
  GenTextureMipmaps(@FTerrainGradient);

  FTerrainModel := LoadModelFromMesh(mesh);
  FTerrainModel.transform := MatrixTranslate(0, -1.2, 0);
  FTerrainModel.materials[0].maps[0].texture := FTerrainGradient;
  FTerrainModel.materials[0].maps[2].texture := FHeightmapTexture;

  FTerrainShader := LoadShader('resources/shaders/terrain.vert', 'resources/shaders/terrain.frag');
  FTerrainModel.materials[0].shader := FTerrainShader;

  FTerrainShader.locs[LOC_MAP_NORMAL] := GetShaderLocation(FTerrainShader, 'texture2');
  FTerrainShader.locs[LOC_MAP_ALBEDO] := GetShaderLocation(FTerrainShader, 'texture0');
  FTerrainShader.locs[LOC_MATRIX_MODEL] := GetShaderLocation(FTerrainShader, 'matModel');
  FTerrainShader.locs[LOC_VECTOR_VIEW] := GetShaderLocation(FTerrainShader, 'viewPos');
  FTerrainDaytimeLoc := GetShaderLocation(FTerrainShader, 'daytime');

  cs := AddClipShader(Self, FTerrainShader);
  param10 := 0.0;
  SetShaderValue(FTerrainShader, clipShaderHeightLocs[cs], @param10, UNIFORM_FLOAT);
  param11 := 2;
  SetShaderValue(FTerrainShader, clipShaderTypeLocs[cs], @param11, UNIFORM_INT);

  FTerrainAmbientLoc := GetShaderLocation(FTerrainShader, 'ambient');
  SetShaderValue(FTerrainShader, FTerrainAmbientLoc, @FAmbc, UNIFORM_VEC4);

  FRockNormalMap := LoadTexture('resources/rockNormalMap.png');
  SetTextureFilter(FRockNormalMap, FILTER_BILINEAR);
  GenTextureMipmaps(@FRockNormalMap);
  FTerrainShader.locs[LOC_MAP_ROUGHNESS] := GetShaderLocation(FTerrainShader, 'rockNormalMap');
  FTerrainModel.materials[0].maps[MAP_ROUGHNESS].texture := FRockNormalMap;

  v := 0; loc := GetShaderLocation(FTerrainShader, 'texture0');
  if loc >= 0 then SetShaderValue(FTerrainShader, loc, @v, UNIFORM_INT);
  v := 1; loc := GetShaderLocation(FTerrainShader, 'texture2');
  if loc >= 0 then SetShaderValue(FTerrainShader, loc, @v, UNIFORM_INT);
  v := 2; loc := GetShaderLocation(FTerrainShader, 'rockNormalMap');
  if loc >= 0 then SetShaderValue(FTerrainShader, loc, @v, UNIFORM_INT);
end;

procedure TRaylibErosionViewer.InitOcean;
var
  mesh, floorMesh: TMesh;
  whiteImage: TImage;
begin
  mesh := GenMeshPlane(5120, 5120, 10, 10);
  FOceanModel := LoadModelFromMesh(mesh);

  FDUDVTex := LoadTexture('resources/waterDUDV.png');
  SetTextureFilter(FDUDVTex, FILTER_BILINEAR);
  GenTextureMipmaps(@FDUDVTex);

  FOceanModel.transform := MatrixTranslate(0, 0, 0);
  FOceanModel.materials[0].maps[0].texture := FReflectionBuffer.texture;
  FOceanModel.materials[0].maps[1].texture := FRefractionBuffer.texture;
  FOceanModel.materials[0].maps[2].texture := FDUDVTex;

  FOceanShader := LoadShader('resources/shaders/water.vert', 'resources/shaders/water.frag');
  FOceanModel.materials[0].shader := FOceanShader;
  FWaterMoveFactorLoc := GetShaderLocation(FOceanShader, 'moveFactor');
  FOceanShader.locs[LOC_MATRIX_MODEL] := GetShaderLocation(FOceanShader, 'matModel');
  FOceanShader.locs[LOC_VECTOR_VIEW] := GetShaderLocation(FOceanShader, 'viewPos');
  BindSamplerUniforms(FOceanShader, 3);

  whiteImage := GenImageColor(8, 8, BLACK);
  FWhiteTexture := LoadTextureFromImage(whiteImage);
  UnloadImage(whiteImage);

  floorMesh := GenMeshPlane(5120, 5120, 10, 10);
  FOceanFloorModel := LoadModelFromMesh(floorMesh);
  FOceanFloorModel.transform := MatrixTranslate(0, -1.2, 0);
  FOceanFloorModel.materials[0].maps[0].texture := FTerrainGradient;
  FOceanFloorModel.materials[0].maps[2].texture := FWhiteTexture;
  FOceanFloorModel.materials[0].shader := FTerrainShader;
end;

procedure TRaylibErosionViewer.InitClouds;
var
  mesh: TMesh;
begin
  FCloudTexture := LoadTexture('resources/clouds.png');
  SetTextureFilter(FCloudTexture, FILTER_BILINEAR);
  GenTextureMipmaps(@FCloudTexture);

  mesh := GenMeshPlane(51200, 51200, 10, 10);
  FCloudModel := LoadModelFromMesh(mesh);
  FCloudModel.transform := MatrixTranslate(0, 1000.0, 0);

  FCloudShader := LoadShader('resources/shaders/cirrostratus.vert', 'resources/shaders/cirrostratus.frag');
  FCloudModel.materials[0].shader := FCloudShader;
  FCloudMoveFactorLoc := GetShaderLocation(FCloudShader, 'moveFactor');
  FCloudDaytimeLoc := GetShaderLocation(FCloudShader, 'daytime');
  FCloudShader.locs[LOC_MATRIX_MODEL] := GetShaderLocation(FCloudShader, 'matModel');
  FCloudShader.locs[LOC_VECTOR_VIEW] := GetShaderLocation(FCloudShader, 'viewPos');
  FCloudModel.materials[0].maps[0].texture := FCloudTexture;
  BindSamplerUniforms(FCloudShader, 1);
end;

procedure TRaylibErosionViewer.InitSkybox;
var
  cube: TMesh;
  v: integer;
  loc: integer;
  texHDR, texHDR2: TTexture2D;
begin
  cube := GenMeshCube(1.0, 1.0, 1.0);
  FSkybox := LoadModelFromMesh(cube);

  FSkyboxShader := LoadShader('resources/shaders/skybox.vert', 'resources/shaders/skybox.frag');
  FSkybox.materials[0].shader := FSkyboxShader;
  FSkyboxShader.locs[LOC_MATRIX_MODEL] := GetShaderLocation(FSkyboxShader, 'matModel');
  FSkyboxDaytimeLoc := GetShaderLocation(FSkyboxShader, 'daytime');
  FSkyboxDayrotationLoc := GetShaderLocation(FSkyboxShader, 'dayrotation');
  FSkyboxMoveFactorLoc := GetShaderLocation(FSkyboxShader, 'moveFactor');
  FSkyboxShader.locs[LOC_MATRIX_VIEW] := GetShaderLocation(FSkyboxShader, 'view');
  FSkyboxShader.locs[LOC_MATRIX_PROJECTION] := GetShaderLocation(FSkyboxShader, 'projection');

  texHDR := LoadTexture('resources/milkyWay.hdr');
  texHDR2 := LoadTexture('resources/daytime.hdr');

  FSkybox.materials[0].maps[0].texture := LoadTexture('resources/skyGradient.png');
  SetTextureFilter(FSkybox.materials[0].maps[0].texture, FILTER_BILINEAR);
  SetTextureWrap(FSkybox.materials[0].maps[0].texture, WRAP_CLAMP);

  FSkybox.materials[0].maps[MAP_CUBEMAP].texture := GenTextureCubemap(texHDR);
  FSkybox.materials[0].maps[MAP_IRRADIANCE].texture := GenTextureCubemap(texHDR2);
  SetTextureFilter(FSkybox.materials[0].maps[MAP_CUBEMAP].texture, FILTER_BILINEAR);
  SetTextureFilter(FSkybox.materials[0].maps[MAP_IRRADIANCE].texture, FILTER_BILINEAR);
  GenTextureMipmaps(@FSkybox.materials[0].maps[MAP_CUBEMAP].texture);
  GenTextureMipmaps(@FSkybox.materials[0].maps[MAP_IRRADIANCE].texture);

  FSkyboxShader.locs[LOC_MAP_CUBEMAP] := GetShaderLocation(FSkyboxShader, 'environmentMapNight');
  FSkyboxShader.locs[LOC_MAP_IRRADIANCE] := GetShaderLocation(FSkyboxShader, 'environmentMapDay');

  v := 0; loc := GetShaderLocation(FSkyboxShader, 'texture0');
  if loc >= 0 then SetShaderValue(FSkyboxShader, loc, @v, UNIFORM_INT);
  v := 1; SetShaderValue(FSkyboxShader, GetShaderLocation(FSkyboxShader, 'environmentMapNight'), @v, UNIFORM_INT);
  v := 2; SetShaderValue(FSkyboxShader, GetShaderLocation(FSkyboxShader, 'environmentMapDay'), @v, UNIFORM_INT);

  UnloadTexture(texHDR);
  UnloadTexture(texHDR2);
end;

function TRaylibErosionViewer.GenTextureCubemap(panorama: TTexture2D): TTexture2D;
const
  FACE_SIZE = 512;
  HDR_EXPOSURE = 1.0;
var
  equi, cross: TImage;
  w, h, x, y, face, x0, y0, x1, y1: integer;
  s, t, dx, dy, dz, u, v, fx, fy, tx, ty: single;
  r00, g00, b00, r10, g10, b10, r01, g01, b01, r11, g11, b11: single;
  r, g, b: single;
  dst: PColor;
  bytesPP: integer;
  isFloat: boolean;

  procedure SampleEqui(sx, sy: integer; out sr, sg, sb: single);
  var
    p8: PByte;
    p4: PSingle;
  begin
    if isFloat then
    begin
      p4 := PSingle(PByte(equi.data) + (sy * w + sx) * bytesPP);
      sr := p4[0] * HDR_EXPOSURE;
      sg := p4[1] * HDR_EXPOSURE;
      sb := p4[2] * HDR_EXPOSURE;
    end
    else
    begin
      p8 := PByte(equi.data) + (sy * w + sx) * bytesPP;
      sr := p8[0] / 255;
      sg := p8[1] / 255;
      sb := p8[2] / 255;
    end;
  end;

begin
  equi := LoadImageFromTexture(panorama);
  w := equi.width;
  h := equi.height;

  case equi.format of
    9:  begin bytesPP := 12; isFloat := True;  end;
    10: begin bytesPP := 16; isFloat := True;  end;
    2:  begin bytesPP := 3;  isFloat := False; end;
  else
        begin bytesPP := 4;  isFloat := False; end;
  end;

  cross := GenImageColor(FACE_SIZE * 6, FACE_SIZE, BLACK);

  for face := 0 to 5 do
    for y := 0 to FACE_SIZE - 1 do
      for x := 0 to FACE_SIZE - 1 do
      begin
        s := x / (FACE_SIZE - 1);
        t := y / (FACE_SIZE - 1);

        case face of
          0: begin dx := 1.0;       dy := 1 - 2 * t; dz := 1 - 2 * s; end;
          1: begin dx := -1.0;      dy := 1 - 2 * t; dz := 2 * s - 1; end;
          2: begin dx := 2 * s - 1; dy := 1.0;       dz := 2 * t - 1; end;
          3: begin dx := 2 * s - 1; dy := -1.0;      dz := 1 - 2 * t; end;
          4: begin dx := 2 * s - 1; dy := 1 - 2 * t; dz := 1.0;       end;
        else      begin dx := 1 - 2 * s; dy := 1 - 2 * t; dz := -1.0;      end;
        end;

        u := 0.5 + ArcTan2(dx, dz) / (2 * PI);
        v := 0.5 - ArcSin(dy) / PI;
        if u < 0 then u := u + 1;
        if u > 1 then u := u - 1;

        fx := u * (w - 1);
        fy := v * (h - 1);
        x0 := Trunc(fx); y0 := Trunc(fy);
        tx := fx - x0;   ty := fy - y0;
        x1 := x0 + 1; if x1 > w - 1 then x1 := w - 1;
        y1 := y0 + 1; if y1 > h - 1 then y1 := h - 1;
        if x0 < 0 then x0 := 0;
        if y0 < 0 then y0 := 0;

        SampleEqui(x0, y0, r00, g00, b00);
        SampleEqui(x1, y0, r10, g10, b10);
        SampleEqui(x0, y1, r01, g01, b01);
        SampleEqui(x1, y1, r11, g11, b11);

        r := (r00 * (1 - tx) + r10 * tx) * (1 - ty) + (r01 * (1 - tx) + r11 * tx) * ty;
        g := (g00 * (1 - tx) + g10 * tx) * (1 - ty) + (g01 * (1 - tx) + g11 * tx) * ty;
        b := (b00 * (1 - tx) + b10 * tx) * (1 - ty) + (b01 * (1 - tx) + b11 * tx) * ty;

        dst := PColor(PByte(cross.data) + (y * cross.width + face * FACE_SIZE + x) * 4);
        dst^.r := Round(Clamp01(r) * 255);
        dst^.g := Round(Clamp01(g) * 255);
        dst^.b := Round(Clamp01(b) * 255);
        dst^.a := 255;
      end;

  Result := LoadTextureCubemap(cross, CUBEMAP_LAYOUT_LINE_HORIZONTAL);
  UnloadImage(cross);
  UnloadImage(equi);
end;

procedure TRaylibErosionViewer.InitTrees;
var
  i: integer;
begin
  for i := 0 to TREE_TEXTURE_COUNT - 1 do
  begin
    FTreeTextures[i] := LoadTexture(Txt(Format('resources/trees/b/%d.png', [i])));
    SetTextureFilter(FTreeTextures[i], FILTER_BILINEAR);
  end;

  GenerateTrees(True);

  FTreeMaterial := LoadMaterialDefault();
  FTreeShader := LoadShader('resources/shaders/vegetation.vert', 'resources/shaders/vegetation.frag');
  FTreeShader.locs[LOC_MATRIX_MODEL] := GetShaderLocation(FTreeShader, 'matModel');
  FTreeAmbientLoc := GetShaderLocation(FTreeShader, 'ambient');
  SetShaderValue(FTreeShader, FTreeAmbientLoc, @FAmbc, UNIFORM_VEC4);
  FTreeMaterial.shader := FTreeShader;
  FTreeMaterial.maps[1].texture := FDUDVTex;
  FTreeMoveFactorLoc := GetShaderLocation(FTreeShader, 'moveFactor');
  BindSamplerUniforms(FTreeShader, 1);
end;

procedure TRaylibErosionViewer.InitLight;
var
  shaderList: array[0..3] of TShader;
begin
  shaderList[0] := FTerrainShader;
  shaderList[1] := FOceanShader;
  shaderList[2] := FTreeShader;
  shaderList[3] := FSkyboxShader;
  FLights[0] := CreateLight(Ord(LIGHT_DIRECTIONAL),
    Vector3Create(20, 10, 0), Vector3Create(0, 0, 0), WHITE, shaderList);
end;

procedure TRaylibErosionViewer.BindSamplerUniforms(shader: TShader; count: integer);
var
  i, v, loc: integer;
begin
  for i := 0 to count - 1 do
  begin
    v := i;
    loc := GetShaderLocation(shader, Txt(Format('texture%d', [i])));
    if loc >= 0 then
      SetShaderValue(shader, loc, @v, UNIFORM_INT);
  end;
end;

procedure TRaylibErosionViewer.GenerateTrees(generateNew: boolean);
const
  grassSlopeThreshold = 0.2;
  grassBlendAmount = 0.55;
  minGrassWeight = 0.45;
var
  i, px, py, tries: integer;
  billPosition, billNormal: TVector3;
  grassWeight, grassBlendHeight, slope, score: single;
  billColor: TColor;
  found: boolean;
  bestPos, bestNormal: TVector3;
  bestScore: single;
begin
  grassBlendHeight := grassSlopeThreshold * (1.0 - grassBlendAmount);

  if generateNew then
    SetLength(FTrees, TREE_COUNT);

  for i := 0 to High(FTrees) do
  begin
    found := False;
    bestScore := -1e9;
    tries := 0;
    repeat
      Inc(tries);
      billPosition.x := RandomRangeF(-16, 16);
      billPosition.z := RandomRangeF(-16, 16);
      px := Trunc((billPosition.x + 16.0) / 32.0 * (MAP_RESOLUTION - 1));
      py := Trunc((billPosition.z + 16.0) / 32.0 * (MAP_RESOLUTION - 1));
      billNormal := FErosion.GetNormal(FMap, MAP_RESOLUTION, px, py);
      billPosition.y := FMap[py * MAP_RESOLUTION + px] * 8 - 1.1;

      slope := 1.0 - billNormal.y;
      grassWeight := 1.0 - Clamp01((slope - grassBlendHeight) / (grassSlopeThreshold - grassBlendHeight));

      if (billPosition.y >= 0.32) and (billPosition.y <= 3.25) and (grassWeight >= minGrassWeight) then
      begin
        found := True;
        bestPos := billPosition;
        bestNormal := billNormal;
        Break;
      end;

      score := grassWeight;
      if (billPosition.y >= 0.32) and (billPosition.y <= 3.25) then
        score := score + 1.0;
      if score > bestScore then
      begin
        bestScore := score;
        bestPos := billPosition;
        bestNormal := billNormal;
      end;
    until tries >= 300;

    if (not found) and (bestPos.y < 0.3) then
      bestPos.y := 0.3;

    billPosition := bestPos;
    billNormal := bestNormal;

    billColor.r := Round((billNormal.x + 1) * 127.5);
    billColor.g := Round((billNormal.y + 1) * 127.5);
    billColor.b := Round((billNormal.z + 1) * 127.5);
    billColor.a := 255;

    if generateNew then
    begin
      FTrees[i].texture := FTreeTextures[Random(TREE_TEXTURE_COUNT)];
      FTrees[i].scale := RandomRangeF(0.6, 1.4) * 0.3;
    end;
    FTrees[i].position := billPosition;
    FTrees[i].color := billColor;
  end;
end;

procedure TRaylibErosionViewer.RebuildBuffers;
begin
  UnloadRenderTexture(FApplicationBuffer);
  UnloadRenderTexture(FReflectionBuffer);
  UnloadRenderTexture(FRefractionBuffer);

  FApplicationBuffer := LoadRenderTexture(GetScreenWidth(), GetScreenHeight());
  FReflectionBuffer := LoadRenderTexture(Trunc(GetScreenWidth() / FBoSize), Trunc(GetScreenHeight() / FBoSize));
  FRefractionBuffer := LoadRenderTexture(Trunc(GetScreenWidth() / FBoSize), Trunc(GetScreenHeight() / FBoSize));
  SetTextureFilter(FReflectionBuffer.texture, FILTER_BILINEAR);
  SetTextureFilter(FRefractionBuffer.texture, FILTER_BILINEAR);

  FOceanModel.materials[0].maps[0].texture := FReflectionBuffer.texture;
  FOceanModel.materials[0].maps[1].texture := FRefractionBuffer.texture;
end;

procedure TRaylibErosionViewer.ResetIsland(gradientType: TGradientType);
begin
  FTotalDroplets := 0;
  FDropletsSinceTreeRegen := 0;
  FMap := Copy(FInitialMap, 0, Length(FInitialMap));
  FErosion.Gradient(FMap, MAP_RESOLUTION, 0.5, gradientType);
  FErosion.Remap(FMap, MAP_RESOLUTION);
  UpdateHeightmapTexture;
  GenerateTrees(False);
end;

procedure TRaylibErosionViewer.ToggleFullscreenVCL;
var
  style: LONG;
  mon: TMonitor;
begin
  FFullscreen := not FFullscreen;
  mon := Screen.MonitorFromWindow(Self.Handle);
  if FFullscreen then
  begin
    FWindowWidthBeforeFullscreen := Self.Width;
    FWindowHeightBeforeFullscreen := Self.Height;
    style := GetWindowLong(Self.Handle, GWL_STYLE);
    SetWindowLong(Self.Handle, GWL_STYLE, style and not (WS_CAPTION or WS_THICKFRAME or WS_MINIMIZEBOX or WS_MAXIMIZEBOX));
    SetWindowPos(Self.Handle, HWND_TOP, mon.Left, mon.Top, mon.Width, mon.Height, SWP_FRAMECHANGED);
  end
  else
  begin
    style := GetWindowLong(Self.Handle, GWL_STYLE);
    SetWindowLong(Self.Handle, GWL_STYLE, style or WS_CAPTION or WS_THICKFRAME or WS_MINIMIZEBOX or WS_MAXIMIZEBOX);
    SetWindowPos(Self.Handle, HWND_TOP, (Screen.Width - FWindowWidthBeforeFullscreen) div 2,
      (Screen.Height - FWindowHeightBeforeFullscreen) div 2,
      FWindowWidthBeforeFullscreen, FWindowHeightBeforeFullscreen, SWP_FRAMECHANGED);
  end;
  FWindowSizeChanged := True;
end;

procedure TRaylibErosionViewer.HandleCameraInput;
var
  p: TPoint;
  wheel, dt, panSpeed: single;
  fwdX, fwdZ, rightX, rightZ: single;
  mx, my: integer;
begin
  dt := GetFrameTime();
  if dt <= 0 then dt := 1 / 60;

  GetCursorPos(p);
  fwdX := -Sin(FCamYaw);   fwdZ := -Cos(FCamYaw);
  rightX := Cos(FCamYaw);  rightZ := -Sin(FCamYaw);

  if (GetAsyncKeyState(VK_LBUTTON) and $8000) <> 0 then
  begin
    if FDragging then
    begin
      FCamYaw := FCamYaw - (p.x - FLastMouse.x) * 0.006;
      FCamPitch := EnsureRange(FCamPitch + (p.y - FLastMouse.y) * 0.006, 0.05, 1.5);
    end;
    FDragging := True;
  end
  else FDragging := False;

  if (GetAsyncKeyState(VK_RBUTTON) and $8000) <> 0 then
  begin
    if FRDragging then
    begin
      mx := p.x - FLastMouse.x;
      my := p.y - FLastMouse.y;
      panSpeed := FCamDist * 0.0015;
      FCamera.target.x := FCamera.target.x + (fwdX * my - rightX * mx) * panSpeed;
      FCamera.target.z := FCamera.target.z + (fwdZ * my - rightZ * mx) * panSpeed;
    end;
    FRDragging := True;
  end
  else FRDragging := False;

  FLastMouse := p;
  panSpeed := 25 * dt;
  if KeyDown(VK_UP) then
  begin
    FCamera.target.x := FCamera.target.x + fwdX * panSpeed;
    FCamera.target.z := FCamera.target.z + fwdZ * panSpeed;
  end;
  if KeyDown(VK_DOWN) then
  begin
    FCamera.target.x := FCamera.target.x - fwdX * panSpeed;
    FCamera.target.z := FCamera.target.z - fwdZ * panSpeed;
  end;
  if KeyDown(VK_LEFT) then
  begin
    FCamera.target.x := FCamera.target.x - rightX * panSpeed;
    FCamera.target.z := FCamera.target.z - rightZ * panSpeed;
  end;
  if KeyDown(VK_RIGHT) then
  begin
    FCamera.target.x := FCamera.target.x + rightX * panSpeed;
    FCamera.target.z := FCamera.target.z + rightZ * panSpeed;
  end;

  FCamera.target.x := EnsureRange(FCamera.target.x, -18, 18);
  FCamera.target.z := EnsureRange(FCamera.target.z, -18, 18);

  wheel := GetMouseWheelMove();
  if wheel <> 0 then FCamDist := EnsureRange(FCamDist - wheel * 3.0, 6, 200);
  if KeyDown(Ord('Q')) then FCamDist := EnsureRange(FCamDist + 30 * dt, 6, 200);
  if KeyDown(Ord('E')) then FCamDist := EnsureRange(FCamDist - 30 * dt, 6, 200);

  FCamera.position := Vector3Create(
    FCamera.target.x + Cos(FCamPitch) * Sin(FCamYaw) * FCamDist,
    FCamera.target.y + Sin(FCamPitch) * FCamDist,
    FCamera.target.z + Cos(FCamPitch) * Cos(FCamYaw) * FCamDist);
end;

procedure TRaylibErosionViewer.UpdateGame;
var
  dt, sunAngle, nDaytime: single;
  iDaytime: integer;
  cameraPos: array[0..2] of single;
begin
  dt := GetFrameTime();

  if IsWindowResized() or FWindowSizeChanged then
  begin
    FWindowSizeChanged := False;
    RebuildBuffers;
  end;

  HandleCameraInput;

  FWaterMoveFactor := FWaterMoveFactor + 0.03 * dt;
  while FWaterMoveFactor > 1.0 do FWaterMoveFactor := FWaterMoveFactor - 1.0;
  SetShaderValue(FOceanShader, FWaterMoveFactorLoc, @FWaterMoveFactor, UNIFORM_FLOAT);

  FTreeMoveFactor := FTreeMoveFactor + 0.125 * dt;
  while FTreeMoveFactor > 1.0 do FTreeMoveFactor := FTreeMoveFactor - 1.0;
  SetShaderValue(FTreeShader, FTreeMoveFactorLoc, @FTreeMoveFactor, UNIFORM_FLOAT);

  FCloudMoveFactor := FCloudMoveFactor + 0.0032 * dt;
  while FCloudMoveFactor > 1.0 do FCloudMoveFactor := FCloudMoveFactor - 1.0;
  SetShaderValue(FCloudShader, FCloudMoveFactorLoc, @FCloudMoveFactor, UNIFORM_FLOAT);

  FSkyboxMoveFactor := FSkyboxMoveFactor + 0.0085 * dt;
  while FSkyboxMoveFactor > 1.0 do FSkyboxMoveFactor := FSkyboxMoveFactor - 1.0;
  SetShaderValue(FSkyboxShader, FSkyboxMoveFactorLoc, @FSkyboxMoveFactor, UNIFORM_FLOAT);

  if FDayRunning then
  begin
    FDayTime := FDayTime + FDaySpeed * dt;
    while FDayTime > 1.0 do FDayTime := FDayTime - 1.0;
  end;
  if KeyDown(VK_SPACE) then
  begin
    FDayTime := FDayTime + FDaySpeed * (5.0 - Ord(FDayRunning)) * dt;
    while FDayTime > 1.0 do FDayTime := FDayTime - 1.0;
  end;

  sunAngle := LerpF(-90, 270, FDayTime) * DEG2RAD;
  nDaytime := Sin(sunAngle);
  iDaytime := Trunc(((nDaytime + 1.0) / 2.0) * (Length(FAmbientColors) - 1));
  if iDaytime < 0 then iDaytime := 0;
  if iDaytime > High(FAmbientColors) then iDaytime := High(FAmbientColors);

  FAmbc[0] := FAmbientColors[iDaytime].r;
  FAmbc[1] := FAmbientColors[iDaytime].g;
  FAmbc[2] := FAmbientColors[iDaytime].b;
  FAmbc[3] := LerpF(0.05, 0.25, (nDaytime + 1.0) / 2.0);

  SetShaderValue(FTerrainShader, FTerrainDaytimeLoc, @nDaytime, UNIFORM_FLOAT);
  SetShaderValue(FSkyboxShader, FSkyboxDaytimeLoc, @nDaytime, UNIFORM_FLOAT);
  SetShaderValue(FSkyboxShader, FSkyboxDayrotationLoc, @FDayTime, UNIFORM_FLOAT);
  SetShaderValue(FCloudShader, FCloudDaytimeLoc, @nDaytime, UNIFORM_FLOAT);
  SetShaderValue(FTerrainShader, FTerrainAmbientLoc, @FAmbc, UNIFORM_VEC4);
  SetShaderValue(FTreeShader, FTreeAmbientLoc, @FAmbc, UNIFORM_VEC4);

  FLights[0].position.x := Cos(sunAngle) * FLightRadius;
  FLights[0].position.y := Sin(sunAngle) * FLightRadius;
  FLights[0].position.z := MaxF(Sin(sunAngle) * FLightRadius * 0.9, -FLightRadius / 4.0);
  UpdateLightValues(FLights[0]);

  cameraPos[0] := FCamera.position.x;
  cameraPos[1] := FCamera.position.y;
  cameraPos[2] := FCamera.position.z;
  SetShaderValue(FTerrainShader, FTerrainShader.locs[LOC_VECTOR_VIEW], @cameraPos, UNIFORM_VEC3);
  SetShaderValue(FOceanShader, FOceanShader.locs[LOC_VECTOR_VIEW], @cameraPos, UNIFORM_VEC3);

  HandleGameplayInput;
end;

procedure TRaylibErosionViewer.HandleGameplayInput;
var
  rDown, tDown, yDown, uDown: boolean;
begin
  if KeyDown(Ord('Z')) then
  begin
    FErosion.Erode(FMap, MAP_RESOLUTION, 350, False);
    FTotalDroplets := FTotalDroplets + 350;
    FDropletsSinceTreeRegen := FDropletsSinceTreeRegen + 350;
    UpdateHeightmapTexture;
    if FDropletsSinceTreeRegen > 350 * 10 then
    begin
      GenerateTrees(False);
      FDropletsSinceTreeRegen := 0;
    end;
  end;

  if KeyPressed(Ord('X')) then
  begin
    FErosion.Erode(FMap, MAP_RESOLUTION, 100000, False);
    FTotalDroplets := FTotalDroplets + 100000;
    UpdateHeightmapTexture;
    GenerateTrees(False);
    FDropletsSinceTreeRegen := 0;
  end;

  rDown := KeyPressed(Ord('R'));
  tDown := KeyPressed(Ord('T'));
  yDown := KeyPressed(Ord('Y'));
  uDown := KeyPressed(Ord('U'));
  if rDown then ResetIsland(gtSquare)
  else if tDown then ResetIsland(gtCircle)
  else if yDown then ResetIsland(gtDiamond)
  else if uDown then ResetIsland(gtStar);

  if KeyPressed(VK_LCONTROL) then FDayRunning := not FDayRunning;

  if KeyPressed(VK_F2) then
  begin
    FLockTo60FPS := not FLockTo60FPS;
    if FLockTo60FPS then SetTargetFPS(60) else SetTargetFPS(0);
  end;

  if KeyPressed(VK_F3) then
  begin
    FCurrentDisplayResolutionIndex := FCurrentDisplayResolutionIndex + 1;
    if FCurrentDisplayResolutionIndex > 4 then FCurrentDisplayResolutionIndex := 0;
    Self.ClientWidth := DISPLAY_RESOLUTIONS[FCurrentDisplayResolutionIndex][0];
    Self.ClientHeight := DISPLAY_RESOLUTIONS[FCurrentDisplayResolutionIndex][1];
    FWindowSizeChanged := True;
  end;

  if KeyPressed(VK_F4) then ToggleFullscreenVCL;
  if KeyPressed(VK_F5) then FUseApplicationBuffer := not FUseApplicationBuffer;
end;

procedure TRaylibErosionViewer.RenderGame;
var
  reflCamera: TCamera3D;
  srcRect: TRectangle;
  dstPos: TVector2;
begin
  BeginDrawing();

  BeginTextureMode(FReflectionBuffer);
  ClearBackground(RED);
  reflCamera := FCamera;
  reflCamera.position.y := -reflCamera.position.y;
  Render3DScene(reflCamera, [FTerrainModel], [], 1);
  EndTextureMode();

  BeginTextureMode(FRefractionBuffer);
  ClearBackground(GREEN);
  Render3DScene(FCamera, [FTerrainModel, FOceanFloorModel], [], 0);
  EndTextureMode();

  if FUseApplicationBuffer then BeginTextureMode(FApplicationBuffer);
  ClearBackground(YELLOW);
  Render3DScene(FCamera, [FCloudModel, FTerrainModel, FOceanFloorModel, FOceanModel], FTrees, 2);
  if FUseApplicationBuffer then EndTextureMode();

  if FUseApplicationBuffer then
  begin
    BeginShaderMode(FPostProcessShader);
    srcRect.x := 0; srcRect.y := 0;
    srcRect.width := FApplicationBuffer.texture.width;
    srcRect.height := -FApplicationBuffer.texture.height;
    dstPos.x := 0; dstPos.y := 0;
    DrawTextureRec(FApplicationBuffer.texture, srcRect, dstPos, WHITE);
    EndShaderMode();
  end;

  DrawGUI;

  if KeyDown(Ord('S')) then
  begin
    srcRect.x := 0; srcRect.y := 0;
    srcRect.width := FReflectionBuffer.texture.width;
    srcRect.height := -FReflectionBuffer.texture.height;
    dstPos.x := 0; dstPos.y := 0;
    DrawTextureRec(FReflectionBuffer.texture, srcRect, dstPos, WHITE);
    dstPos.y := FReflectionBuffer.texture.height;
    srcRect.width := FRefractionBuffer.texture.width;
    srcRect.height := -FRefractionBuffer.texture.height;
    DrawTextureRec(FRefractionBuffer.texture, srcRect, dstPos, WHITE);
  end;

  if KeyDown(Ord('A')) then
  begin
    dstPos.x := GetScreenWidth() - FHeightmapTexture.width - 20;
    dstPos.y := 20;
    DrawTextureEx(FHeightmapTexture, dstPos, 0, 1, WHITE);
    DrawRectangleLines(Trunc(dstPos.x), Trunc(dstPos.y), FHeightmapTexture.width, FHeightmapTexture.height, GREEN);
  end;

  EndDrawing();
end;

procedure TRaylibErosionViewer.Render3DScene(const camera: TCamera3D; const models: array of TModel; const trees: array of TTreeBillboard; clipPlane: integer);
var
  i: integer;
  proj: TMatrix;
begin
  BeginMode3D(camera);

  for i := 0 to CLIP_SHADERS_COUNT - 1 do
    SetShaderValue(clipShaders[i], clipShaderTypeLocs[i], @clipPlane, UNIFORM_INT);

  SetShaderValueMatrix(FSkyboxShader, FSkyboxShader.locs[LOC_MATRIX_VIEW], GetCameraMatrix(camera));
  proj := MatrixPerspective(camera.fovy * DEG2RAD, GetScreenWidth() / GetScreenHeight(), 0.01, 1000.0);
  SetShaderValueMatrix(FSkyboxShader, FSkyboxShader.locs[LOC_MATRIX_PROJECTION], proj);

  rlDisableBackfaceCulling();
  DrawModel(FSkybox, Vector3Create(0, 0, 0), 1.0, WHITE);

  for i := 0 to High(models) do
    DrawModel(models[i], Vector3Create(0, 0, 0), 1.0, WHITE);

  BeginShaderMode(FTreeShader);
  for i := 0 to High(trees) do
    DrawBillboard(camera, trees[i].texture, trees[i].position, trees[i].scale, trees[i].color);
  EndShaderMode();

  EndMode3D();
end;

procedure TRaylibErosionViewer.DrawGUI;
var
  hour, minute: integer;
begin
  if KeyDown(VK_F6) then Exit;

  if not KeyDown(VK_F1) then
  begin
    DrawText(Txt('Hold F1 to display controls. Hold ALT to enable cursor.'), 10, 10, 20, WHITE);
    DrawText(Txt(Format('FPS: %d', [GetFPS()])), 10, 70, 20, WHITE);
    hour := Trunc(FDayTime * 24.0);
    minute := Trunc((FDayTime * 24.0 - hour) * 60.0);
    DrawText(Txt(Format('%.2d : %.2d', [hour, minute])), GetScreenWidth() - 80, 10, 20, WHITE);
  end
  else
  begin
    DrawText(Txt('Z - hold to erode'#10 +
      'X - press to erode 100000 droplets'#10 +
      'R - press to reset island (chebyshev)'#10 +
      'T - press to reset island (euclidean)'#10 +
      'Y - press to reset island (manhattan)'#10 +
      'U - press to reset island (star)'#10 +
      'CTRL - toggle sun movement'#10 +
      'Space - advance daytime'#10 +
      'S - display frame buffers'#10 +
      'A - display debug'#10 +
      'F2 - toggle 60 FPS lock'#10 +
      'F3 - change window resolution'#10 +
      'F4 - toggle fullscreen'#10 +
      'F5 - toggle application buffer'#10 +
      'F6 - hold to hide GUI'#10 +
      'F9 - take screenshot'), 10, 10, 20, WHITE);
  end;
end;

end.
