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
  DX.Delphi.CST,
  DX.Delphi.Conditions;

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

  [TestFixture]
  TTestParserConditionalStmts = class
  public
    [Test]
    procedure ConditionalGroupBasic;
    [Test]
    procedure ConditionalGroupElseIf;
    [Test]
    procedure ConditionalGroupNested;
    [Test]
    procedure ConditionalGroupProjection;
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

{ TTestParserConditionalStmts }

procedure TTestParserConditionalStmts.ConditionalGroupBasic;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LCond: TDLConditionalStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '{$IFDEF A}'#13#10+
      '  Foo(1);'#13#10+
      '{$ELSE}'#13#10+
      '  Foo(2);'#13#10+
      '{$ENDIF}'#13#10+
      '  Foo(3);'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.AreEqual(2, LBody.Statements.Count);
      LCond := TDLConditionalStmt(LBody.Statements[0]);
      Assert.AreEqual(2, LCond.Branches.Count);
      Assert.IsNotNull(LCond.Branches[0].Condition);
      Assert.AreEqual('Defined(A)', LCond.Branches[0].Condition.ToString);
      Assert.AreEqual(1, LCond.Branches[0].Statements.Count);
      Assert.AreEqual(ckAlways, LCond.Branches[1].Condition.Kind);
      Assert.AreEqual(1, LCond.Branches[1].Statements.Count);
      // The statement after {$ENDIF} is a sibling of the conditional group.
      Assert.IsTrue(LBody.Statements[1] is TDLExprStmt);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserConditionalStmts.ConditionalGroupElseIf;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LCond: TDLConditionalStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '{$IF Defined(A)}'#13#10+
      '  Foo(1);'#13#10+
      '{$ELSEIF Defined(B)}'#13#10+
      '  Foo(2);'#13#10+
      '{$ELSE}'#13#10+
      '  Foo(3);'#13#10+
      '{$ENDIF}'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LCond := TDLConditionalStmt(LBody.Statements[0]);
      Assert.AreEqual(3, LCond.Branches.Count);
      Assert.AreEqual('Defined(A)', LCond.Branches[0].Condition.ToString);
      Assert.AreEqual('Defined(B)', LCond.Branches[1].Condition.ToString);
      Assert.AreEqual(ckAlways, LCond.Branches[2].Condition.Kind);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserConditionalStmts.ConditionalGroupNested;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LCond, LInner: TDLConditionalStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '{$IFDEF A}'#13#10+
      '  {$IFDEF B}'#13#10+
      '    Foo(1);'#13#10+
      '  {$ELSE}'#13#10+
      '    Foo(2);'#13#10+
      '  {$ENDIF}'#13#10+
      '{$ELSE}'#13#10+
      '  Foo(3);'#13#10+
      '{$ENDIF}'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LCond := TDLConditionalStmt(LBody.Statements[0]);
      Assert.AreEqual(2, LCond.Branches.Count);
      // The first branch contains a nested conditional group.
      Assert.AreEqual(1, LCond.Branches[0].Statements.Count);
      LInner := TDLConditionalStmt(LCond.Branches[0].Statements[0]);
      Assert.AreEqual(2, LInner.Branches.Count);
      Assert.AreEqual('Defined(B)', LInner.Branches[0].Condition.ToString);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserConditionalStmts.ConditionalGroupProjection;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
  LCond: TDLConditionalStmt;
  LDefines: TDLDefineSet;
  LActive: Boolean;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '{$IFDEF A}'#13#10+
      '  Foo(1);'#13#10+
      '{$ELSEIF Defined(B)}'#13#10+
      '  Foo(2);'#13#10+
      '{$ELSE}'#13#10+
      '  Foo(3);'#13#10+
      '{$ENDIF}'#13#10'end.', LDiagnostics);
    try
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      LCond := TDLConditionalStmt(LBody.Statements[0]);
      LDefines := TDLDefineSet.Create;
      try
        // Configuration {B}: the second branch is active.
        LDefines.Define('B');
        LActive := False;
        if LCond.Branches[0].Condition.Evaluate(LDefines) then
          LActive := True
        else if LCond.Branches[1].Condition.Evaluate(LDefines) then
          LActive := True;
        Assert.IsTrue(LActive);
      finally
        LDefines.Free;
      end;
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
