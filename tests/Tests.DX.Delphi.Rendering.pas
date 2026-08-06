/// <summary>
///   Tests.DX.Delphi.Rendering — DUnitX coverage for the ToSourceText
///   rendering contract of CST and AST expression nodes (added during the
///   SoC/DRY refactor; requested by the review bots).
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-06</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Rendering;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST,
  DX.Delphi.AST,
  Tests.DX.Delphi.Support;

type
  [TestFixture]
  TTestCstToSourceText = class
  public
    [Test]
    procedure OperatorCallMemberIndex;
    [Test]
    procedure UnaryNotSpacing;
    [Test]
    procedure StringEscaping;
    [Test]
    procedure SetArrayAndAnonymous;
  end;

  [TestFixture]
  TTestAstToSourceText = class
  public
    [Test]
    procedure ExpressionRendering;
    [Test]
    procedure SetArrayAndAnonymous;
  end;

implementation

uses
  DX.Delphi.AstBuilder;

function ProcSource(const AStatements: string): string;
begin
  Result := 'unit U; interface'#13#10'implementation'#13#10+
    'procedure P;'#13#10'var i: Integer; s: string;'#13#10'begin'#13#10+
    AStatements + 'end;'#13#10'end.';
end;

/// <summary>Parses a unit whose first procedure body contains AStatements;
/// the caller owns the returned CST tree.</summary>
function CstProcedure(const AStatements: string;
  ADiagnostics: TDLDiagnostics): TDLCompilationUnit;
begin
  Result := ParseSource(ProcSource(AStatements), ADiagnostics);
end;

/// <summary>Parses a unit whose first procedure body contains AStatements;
/// the caller owns the returned AST module.</summary>
function AstProcedure(const AStatements: string;
  ADiagnostics: TDLDiagnostics): TDLModule;
begin
  Result := BuildAst(ProcSource(AStatements), ADiagnostics);
end;

/// <summary>Value expression of the AIndex-th assignment in the first
/// procedure body of a parsed CST unit.</summary>
function CstAssignmentValue(AUnit: TDLCompilationUnit;
  AIndex: Integer): DX.Delphi.CST.TDLExpr;
var
  LBlock: TDLCompoundStmt;
begin
  LBlock := TDLCompoundStmt(TDLMethodImpl(AUnit.Items[0]).Body);
  Result := TDLAssignmentStmt(LBlock.Statements[AIndex]).Value;
end;

/// <summary>Value expression of the AIndex-th assignment in the first
/// procedure body of a lowered AST module.</summary>
function AstAssignmentValue(AModule: TDLModule;
  AIndex: Integer): DX.Delphi.AST.TDLExpr;
var
  LProc: TDLProcDecl;
begin
  LProc := TDLProcDecl(AModule.Declarations[0]);
  Result := TDLAssignStmt(LProc.Body[AIndex]).Value;
end;

{ TTestCstToSourceText }

procedure TTestCstToSourceText.OperatorCallMemberIndex;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := CstProcedure(
      'c := a + b;'#13#10'd := Foo(1, x.y);'#13#10'e := arr[i];',
      LDiagnostics);
    try
      Assert.AreEqual('a + b',
        CstAssignmentValue(LUnit, 0).ToSourceText);
      Assert.AreEqual('Foo(1, x.y)',
        CstAssignmentValue(LUnit, 1).ToSourceText);
      Assert.AreEqual('arr[i]',
        CstAssignmentValue(LUnit, 2).ToSourceText);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestCstToSourceText.UnaryNotSpacing;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := CstProcedure('x := not z;'#13#10'y := @p;', LDiagnostics);
    try
      Assert.AreEqual('not z', CstAssignmentValue(LUnit, 0).ToSourceText);
      Assert.AreEqual('@p', CstAssignmentValue(LUnit, 1).ToSourceText);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestCstToSourceText.StringEscaping;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // Apostrophe doubling and char-code literals for control characters.
    LUnit := CstProcedure('s := ''it''''s'';'#13#10, LDiagnostics);
    try
      Assert.AreEqual('''it''''s''',
        CstAssignmentValue(LUnit, 0).ToSourceText);
    finally
      LUnit.Free;
    end;
    LUnit := CstProcedure('s := ''a''#13#10''b'';'#13#10, LDiagnostics);
    try
      Assert.AreEqual('''a''#13#10''b''',
        CstAssignmentValue(LUnit, 0).ToSourceText);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestCstToSourceText.SetArrayAndAnonymous;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := CstProcedure('x := [1, 2, 3];'#13#10, LDiagnostics);
    try
      Assert.AreEqual('[1, 2, 3]', CstAssignmentValue(LUnit, 0).ToSourceText);
    finally
      LUnit.Free;
    end;
    // Range elements render compactly: [1..3] not [1 .. 3].
    LUnit := CstProcedure('x := [1..3, 5];'#13#10, LDiagnostics);
    try
      Assert.AreEqual('[1..3, 5]', CstAssignmentValue(LUnit, 0).ToSourceText);
    finally
      LUnit.Free;
    end;
    LUnit := CstProcedure(
      'f := function: Integer begin Result := 1; end;'#13#10, LDiagnostics);
    try
      Assert.AreEqual('<anonymous method>',
        CstAssignmentValue(LUnit, 0).ToSourceText);
    finally
      LUnit.Free;
    end;
    // inherited with a target renders the target.
    LUnit := CstProcedure('x := inherited Foo(1);'#13#10, LDiagnostics);
    try
      Assert.AreEqual('inherited Foo(1)',
        CstAssignmentValue(LUnit, 0).ToSourceText);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstToSourceText }

procedure TTestAstToSourceText.ExpressionRendering;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := AstProcedure(
      'c := a + b;'#13#10'd := Foo(1, x.y);'#13#10'e := arr[i];'#13#10+
      'n := not z;', LDiagnostics);
    try
      Assert.AreEqual('a + b', AstAssignmentValue(LModule, 0).ToSourceText);
      Assert.AreEqual('Foo(1, x.y)', AstAssignmentValue(LModule, 1).ToSourceText);
      Assert.AreEqual('arr[i]', AstAssignmentValue(LModule, 2).ToSourceText);
      Assert.AreEqual('not z', AstAssignmentValue(LModule, 3).ToSourceText);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstToSourceText.SetArrayAndAnonymous;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := AstProcedure('x := [1, 2];'#13#10, LDiagnostics);
    try
      Assert.AreEqual('[1, 2]', AstAssignmentValue(LModule, 0).ToSourceText);
    finally
      LModule.Free;
    end;
    LModule := AstProcedure('x := [1..3];'#13#10, LDiagnostics);
    try
      Assert.AreEqual('[1..3]', AstAssignmentValue(LModule, 0).ToSourceText);
    finally
      LModule.Free;
    end;
    LModule := AstProcedure('x := inherited Foo;'#13#10, LDiagnostics);
    try
      Assert.AreEqual('inherited Foo',
        AstAssignmentValue(LModule, 0).ToSourceText);
    finally
      LModule.Free;
    end;
    LModule := AstProcedure(
      'f := function: Integer begin Result := 1; end;'#13#10, LDiagnostics);
    try
      Assert.AreEqual('<anonymous method>',
        AstAssignmentValue(LModule, 0).ToSourceText);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCstToSourceText);
  TDUnitX.RegisterTestFixture(TTestAstToSourceText);

end.
