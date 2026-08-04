/// <summary>
///   Tests.DX.Delphi.Parser.Statements — DUnitX coverage for advanced
///   statements and expressions: raise at, asm, goto/labels, inline vars,
///   exit with value, pointer/address operators, string sequences and
///   inherited calls.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Parser.Statements;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestParserRaiseGotoAsm = class
  public
    [Test]
    procedure RaiseWithAt;
    [Test]
    procedure GotoAndLabel;
    [Test]
    procedure AsmStatement;
  end;

  [TestFixture]
  TTestParserInlineVars = class
  public
    [Test]
    procedure InlineVarDeclaration;
    [Test]
    procedure ExitWithValue;
  end;

  [TestFixture]
  TTestParserExprAdvanced = class
  public
    [Test]
    procedure StringSequence;
    [Test]
    procedure AddressAndDeref;
    [Test]
    procedure InheritedCall;
    [Test]
    procedure UnaryOperators;
  end;

  [TestFixture]
  TTestParserInitFinal = class
  public
    [Test]
    procedure InitializationAndFinalization;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestParserRaiseGotoAsm }

procedure TTestParserRaiseGotoAsm.RaiseWithAt;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LRaise: TDLRaiseStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  raise Exception.Create(''boom'') at AddressOf(x);'#13#10+
      '  raise;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LRaise := TDLRaiseStmt(LBody.Statements[0]);
      Assert.IsNotNull(LRaise.Exception);
      Assert.IsNotNull(LRaise.AtAddr);
      LRaise := TDLRaiseStmt(LBody.Statements[1]);
      Assert.IsNull(LRaise.Exception);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserRaiseGotoAsm.GotoAndLabel;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  goto Done;'#13#10+
      '  Done:'#13#10+
      '  x := 1;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.IsTrue(LBody.Statements[0] is TDLGotoStmt);
      Assert.IsTrue(LBody.Statements[1] is TDLLabelStmt);
      Assert.AreEqual('Done', TDLLabelStmt(LBody.Statements[1]).LabelName.Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserRaiseGotoAsm.AsmStatement;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  asm'#13#10+
      '    mov eax, 1'#13#10+
      '    add eax, 2'#13#10+
      '  end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.IsTrue(LBody.Statements[0] is TDLAsmStmt);
      Assert.IsTrue(Pos('eax', TDLAsmStmt(LBody.Statements[0]).Text) > 0);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserInlineVars }

procedure TTestParserInlineVars.InlineVarDeclaration;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  var local := 42;'#13#10+
      '  var typed: Integer := 7;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.IsTrue(LBody.Statements[0] is TDLVarDeclStmt);
      Assert.IsTrue(LBody.Statements[1] is TDLVarDeclStmt);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserInlineVars.ExitWithValue;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  exit;'#13#10+
      '  exit(42);'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.IsTrue(LBody.Statements[0] is TDLExitStmt);
      Assert.IsNull(TDLExitStmt(LBody.Statements[0]).Expression);
      Assert.IsNotNull(TDLExitStmt(LBody.Statements[1]).Expression);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserExprAdvanced }

procedure TTestParserExprAdvanced.StringSequence;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LAssign: TDLAssignmentStmt;
  LString: TDLStringExpr;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  s := ''a''#10''b''#9''c'';'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LAssign := TDLAssignmentStmt(LBody.Statements[0]);
      Assert.IsTrue(LAssign.Value is TDLStringExpr);
      LString := TDLStringExpr(LAssign.Value);
      Assert.AreEqual('a'#10'b'#9'c', LString.Value);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExprAdvanced.AddressAndDeref;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LAssign: TDLAssignmentStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'var p: ^Integer;'#13#10'begin'#13#10+
      '  p := @x;'#13#10+
      '  y := p^;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LAssign := TDLAssignmentStmt(LBody.Statements[0]);
      Assert.IsTrue(LAssign.Value is TDLUnaryExpr);
      Assert.AreEqual(uoAddr, TDLUnaryExpr(LAssign.Value).Operator);
      LAssign := TDLAssignmentStmt(LBody.Statements[1]);
      Assert.IsTrue(LAssign.Value is TDLUnaryExpr);
      Assert.AreEqual(uoDeref, TDLUnaryExpr(LAssign.Value).Operator);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExprAdvanced.InheritedCall;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LStmt: TDLExprStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  inherited;'#13#10+
      '  inherited Create(1);'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LStmt := TDLExprStmt(LBody.Statements[0]);
      Assert.IsTrue(LStmt.Expression is TDLInheritedExpr);
      Assert.IsNull(TDLInheritedExpr(LStmt.Expression).Target);
      LStmt := TDLExprStmt(LBody.Statements[1]);
      Assert.IsTrue(LStmt.Expression is TDLInheritedExpr);
      Assert.IsNotNull(TDLInheritedExpr(LStmt.Expression).Target);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExprAdvanced.UnaryOperators;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LAssign: TDLAssignmentStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  a := -x;'#13#10+
      '  b := +x;'#13#10+
      '  c := not x;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LAssign := TDLAssignmentStmt(LBody.Statements[0]);
      Assert.AreEqual(uoMinus, TDLUnaryExpr(LAssign.Value).Operator);
      LAssign := TDLAssignmentStmt(LBody.Statements[1]);
      Assert.AreEqual(uoPlus, TDLUnaryExpr(LAssign.Value).Operator);
      LAssign := TDLAssignmentStmt(LBody.Statements[2]);
      Assert.AreEqual(uoNot, TDLUnaryExpr(LAssign.Value).Operator);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserInitFinal }

procedure TTestParserInitFinal.InitializationAndFinalization;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'implementation'#13#10+
      'initialization'#13#10+
      '  Init1;'#13#10+
      '  Init2;'#13#10+
      'finalization'#13#10+
      '  Done;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsNotNull(LUnit.InitSection);
      Assert.IsNotNull(LUnit.FinalizationSection);
      Assert.AreEqual(2, TDLCompoundStmt(
        LUnit.InitSection.Body).Statements.Count);
      Assert.AreEqual(1, TDLCompoundStmt(
        LUnit.FinalizationSection.Body).Statements.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParserRaiseGotoAsm);
  TDUnitX.RegisterTestFixture(TTestParserInlineVars);
  TDUnitX.RegisterTestFixture(TTestParserExprAdvanced);
  TDUnitX.RegisterTestFixture(TTestParserInitFinal);

end.
