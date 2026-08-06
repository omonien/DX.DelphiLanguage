/// <summary>
///   Tests.DX.Delphi.Ownership — verifies that CST/AST trees reclaim all
///   their nodes when freed. The DUnitX default leak monitor is a no-op,
///   so this fixture measures the process heap directly: parsing and
///   freeing a tree repeatedly must not grow committed memory, while the
///   same parses without freeing must grow it (self-calibrating baseline).
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-06</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Ownership;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST,
  Tests.DX.Delphi.Support;

type
  [TestFixture]
  TTestTreeOwnership = class
  public
    [Test]
    procedure FreeingTreesDoesNotLeak;
  end;

implementation

const
  // A moderately large unit exercising types, members, statements and
  // expressions so a parse allocates a representative tree.
  COwnershipSource =
    'unit U;'#13#10'interface'#13#10+
    'uses System.SysUtils, System.Classes, System.Generics.Collections;'#13#10+
    'type'#13#10+
    '  TFoo = class(TObject)'#13#10+
    '  private'#13#10+
    '    FItems: TList<Integer>;'#13#10+
    '    FData: array[0..9] of string;'#13#10+
    '  public'#13#10+
    '    constructor Create;'#13#10+
    '    procedure Add(A: Integer); overload;'#13#10+
    '    procedure Add(A, B: Integer); overload;'#13#10+
    '    function Get(I: Integer): Integer;'#13#10+
    '    property Items: TList<Integer> read FItems;'#13#10+
    '  end;'#13#10+
    '  TRec = record'#13#10+
    '    X, Y: Integer;'#13#10+
    '    case Boolean of'#13#10+
    '      True: (A: Integer);'#13#10+
    '      False: (B: Integer);'#13#10+
    '  end;'#13#10+
    '  TEnum = (eA, eB = 5, eC);'#13#10+
    '  TSet = set of TEnum;'#13#10+
    '  TProc = reference to function(A: Integer): Integer;'#13#10+
    'implementation'#13#10+
    'constructor TFoo.Create;'#13#10+
    'begin'#13#10+
    '  inherited Create;'#13#10+
    '  FItems := TList<Integer>.Create;'#13#10+
    'end;'#13#10+
    'procedure TFoo.Add(A: Integer);'#13#10+
    'var i: Integer;'#13#10+
    'begin'#13#10+
    '  for i := 0 to A do'#13#10+
    '    if i mod 2 = 0 then'#13#10+
    '      FItems.Add(i)'#13#10+
    '    else'#13#10+
    '      FItems.Add(A);'#13#10+
    'end;'#13#10+
    'function TFoo.Get(I: Integer): Integer;'#13#10+
    'var'#13#10+
    '  LAnon: TProc;'#13#10+
    'begin'#13#10+
    '  LAnon := function(A: Integer): Integer begin Result := A * 2; end;'#13#10+
    '  Result := FItems[I] + Length(FData) + LAnon(I);'#13#10+
    'end;'#13#10+
    'end.';

/// <summary>Parses ACount trees and returns the heap growth in ADelta.
/// When AFreeTrees is False the trees are retained until AFTER the delta is
/// captured, then freed, so the baseline measurement does not leak memory
/// into the rest of the test process.</summary>
procedure RunParseBatch(AFreeTrees: Boolean; ACount: Integer;
  ADiagnostics: TDLDiagnostics; out ADelta: Int64);
var
  LRetained: TObjectList<TDLCompilationUnit>;
  LUnit: TDLCompilationUnit;
  LBefore: Int64;
  i: Integer;
begin
  if AFreeTrees then
  begin
    LBefore := GetHeapStatus.TotalAllocated;
    for i := 1 to ACount do
    begin
      LUnit := ParseSource(COwnershipSource, ADiagnostics);
      LUnit.Free;
    end;
    ADelta := GetHeapStatus.TotalAllocated - LBefore;
  end
  else
  begin
    // Retain the trees so the no-free baseline can be measured, then release
    // them so the test process stays clean.
    LRetained := TObjectList<TDLCompilationUnit>.Create(True);
    try
      LBefore := GetHeapStatus.TotalAllocated;
      for i := 1 to ACount do
        LRetained.Add(ParseSource(COwnershipSource, ADiagnostics));
      ADelta := GetHeapStatus.TotalAllocated - LBefore;
    finally
      LRetained.Free;
    end;
  end;
end;

procedure TTestTreeOwnership.FreeingTreesDoesNotLeak;
var
  LDiagnostics: TDLDiagnostics;
  LFreeDelta, LNoFreeDelta: Int64;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // Warm up allocator arenas so the measured deltas are steady-state.
    RunParseBatch(True, 3, LDiagnostics, LFreeDelta);
    RunParseBatch(True, 20, LDiagnostics, LFreeDelta);
    RunParseBatch(False, 20, LDiagnostics, LNoFreeDelta);

    // Freeing 20 trees must reclaim the overwhelming majority of what not
    // freeing leaks; allow generous slack for allocator hysteresis.
    Assert.IsTrue(LNoFreeDelta > 0,
      'baseline without freeing should grow the heap');
    Assert.IsTrue(LFreeDelta * 4 < LNoFreeDelta,
      Format('tree free leaks: freeDelta=%d vs noFreeDelta=%d',
        [LFreeDelta, LNoFreeDelta]));
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTreeOwnership);

end.
