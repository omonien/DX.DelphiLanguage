/// <summary>
///   Demo — sample Delphi source exercising the DX.Delphi language model:
///   declarations, types (classes/records/helpers/interfaces/generics),
///   methods, properties, statements and expressions of the Delphi 13.x
///   surface. The file is intentionally a showcase for the lexer/parser
///   rather than a compilable program on its own.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Demo;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections in 'System.Generics.Collections.pas';

const
  cMaxRetries = 5;
  cBaseUrl = 'https://example.com';
  cFlags = [1, 2, 4, 8];
  cBits = $FF_00;
  cBin = %1010_0101;
  cPi = 3.14159;
  cExp = 1.5e10;
  cChar = #13#10;
  cSeq = 'a'#10'b'#9'c';
  cMulti = '''line one
line two''';

resourcestring
  rsWelcome = 'Welcome';
  rsFarewell = 'Goodbye';

var
  GGlobal: Integer;
  GNames: TArray<string>;
  GText: string = 'initial';

threadvar
  TThreadLocal: Integer;

type
  TDay = (Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday);
  TWeek = set of TDay;
  TRange = 1..10;
  TSmall = 0..99;
  TMatrix = array[1..3, 1..3] of Double;
  TDynInts = array of Integer;
  TDynGrid = array of array of string;
  TName = string[32];
  TIntPtr = ^Integer;
  TDataFile = file of Byte;

  TPoint = record
    X, Y: Integer;
    procedure MoveTo(AX, AY: Integer);
    function Distance: Double;
  end;

  TVariant = record
    case Kind: Integer of
      0: (IntVal: Integer);
      1: (FloatVal: Double);
      2: (StrVal: string);
  end;

  TManaged = record
    Data: Pointer;
    class operator Initialize(out ADest: TManaged);
    class operator Finalize(var ADest: TManaged);
    class operator Assign(var ADest: TManaged; const ASource: TManaged);
    class operator Add(const A, B: TManaged): TManaged;
  end;

  TBaseClass = class(TObject)
  strict private
    FValue: Integer;
    FName: string;
  private
    FSecret: Integer;
  protected
    function GetDisplayName: string; virtual;
    procedure SetValue(AValue: Integer); virtual;
  public
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    procedure DoWork; virtual; abstract;
    class function MakeDefault: TBaseClass; static;
    property Value: Integer read FValue write SetValue default 0;
    property Name: string read FName write FName;
    property DisplayName: string read GetDisplayName;
  published
    property Secret: Integer read FSecret write FSecret;
  end;

  TDerived = class(TBaseClass)
  private
    FExtra: string;
  public
    procedure DoWork; override;
    procedure DoMore; reintroduce; overload;
    procedure DoMore(AX: Integer); overload; virtual;
    procedure Notify; message WM_USER;
  end;

  IGreeter = interface
    ['{8A2C3B5E-4D61-4C2B-9A3F-0E7B1C5D2F8A}']
    procedure Greet(const AName: string);
    function FormatGreeting(const AName: string): string;
  end;

  TGreeter = class(TInterfacedObject, IGreeter)
  public
    procedure Greet(const AName: string);
    function FormatGreeting(const AName: string): string;
  end;

  TStringHelper = class helper for string
    function IsEmptyEx: Boolean;
  end;

  TPointHelper = record helper for TPoint
    function Scaled(AFactor: Integer): TPoint;
  end;

  TList<T> = class
  private
    FItems: TArray<T>;
  public
    procedure Add(const AItem: T);
    function Count: Integer;
    property Items[AIndex: Integer]: T read GetItem write SetItem; default;
  end;

  TKeyValuePair<TKey, TValue> = record
    Key: TKey;
    Value: TValue;
  end;

  TBinaryTree<T> = class
  public
    type
      TNode = class
        Value: T;
        Left, Right: TNode;
      end;
  private
    FRoot: TNode;
  public
    procedure Insert(const AValue: T);
  end;

  TCalcFunc = reference to function(AX, AY: Integer): Integer;
  TNotifyProc = procedure(const AMessage: string) of object;

  TClassRef = class of TBaseClass;

  TProcessor = class
  public
    class operator Implicit(const AValue: Integer): TProcessor;
    class operator Explicit(const AValue: TProcessor): Integer;
    class operator Add(const A, B: TProcessor): TProcessor;
  end;

implementation

uses
  System.Math;

label
  Done;

var
  GCalc: TCalcFunc;

procedure DoWork(const AValue: Integer; var AResult: Integer;
  const AList: TArray<string>; AFlag: Boolean = True);
var
  i: Integer;
begin
  AResult := 0;
  for i := 0 to High(AList) do
    AResult := AResult + Length(AList[i]);
  if AFlag then
    AResult := AResult + AValue
  else
    AResult := AResult - AValue;
end;

function Compute(AMode: Integer): Integer;
begin
  case AMode of
    0: Result := 0;
    1, 2, 3: Result := 10;
    4..10: Result := 20;
  else
    Result := -1;
  end;
end;

procedure TestStatements;
var
  i: Integer;
  j: Integer;
  x: Integer;
begin
  i := 0;
  while i < 10 do
    Inc(i);
  repeat
    Dec(i);
  until i = 0;
  for j := 1 to 10 do
    x := x + j;
  for var k := 0 to 4 do
    x := x + k;
  for var s in ['a', 'b', 'c'] do
    x := x + Ord(s);
  with TPoint.Create do
    MoveTo(1, 2);
  try
    try
      if x > 100 then
        raise Exception.Create('too big')
      else
        x := x * 2;
    except
      on E: Exception do
        x := 0;
      else
        x := -1;
    end;
  finally
    x := x + 1;
  end;
  goto Done;
  Done:
  Exit(x);
end;

procedure TestTypes;
var
  LList: TList<Integer>;
  LMap: TDictionary<string, Integer>;
  LPtr: TIntPtr;
  LSet: TWeek;
  LPoint: TPoint;
  LCalc: TCalcFunc;
  LGrid: TDynGrid;
  LByte: Byte;
  LAnon: TFunc<Integer, Integer>;
begin
  LList := TList<Integer>.Create;
  LList.Add(42);
  LPtr := @LByte;
  LPtr^ := 7;
  LSet := [Monday, Wednesday, Friday];
  LSet := [Monday..Thursday];
  LPoint := TPoint.Create;
  LPoint.MoveTo(3, 4);
  LCalc := function(AX, AY: Integer): Integer
  begin
    Result := AX + AY;
  end;
  LAnon := function(AX: Integer): Integer
  begin
    Result := AX * 2;
  end;
  SetLength(LGrid, 3, 3);
  LGrid[0, 0] := 'origin';
  if LPoint.X > 0 then
    LPoint.X := LPoint.X shl 1;
  x := (1 + 2) * 3 div 4 mod 5;
end;

initialization
  GGlobal := cMaxRetries;
  RegisterClass(TGreeter);

finalization
  GGlobal := 0;

end.
