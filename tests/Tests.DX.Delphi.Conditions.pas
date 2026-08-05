/// <summary>
///   Tests.DX.Delphi.Conditions — DUnitX coverage for the conditional
///   compilation model: directive parsing into condition trees, evaluation
///   against define configurations, and the define set itself.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-05</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Conditions;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Conditions;

type
  [TestFixture]
  TTestConditionParser = class
  public
    [Test]
    procedure ParseIfDef;
    [Test]
    procedure ParseIfNdef;
    [Test]
    procedure ParseIfExpression;
    [Test]
    procedure ParseElse;
    [Test]
    procedure ParseNonConditionalReturnsNil;
  end;

  [TestFixture]
  TTestConditionEvaluation = class
  public
    [Test]
    procedure EvaluateDefined;
    [Test]
    procedure EvaluateNotAndOr;
    [Test]
    procedure EvaluatePrecedence;
    [Test]
    procedure EvaluateElseAlways;
  end;

  [TestFixture]
  TTestDefineSet = class
  public
    [Test]
    procedure DefineIsCaseInsensitive;
    [Test]
    procedure UndefineRemoves;
    [Test]
    procedure CloneIsIndependent;
  end;

implementation

{ ------------------------------------------------------------------ }
{ TTestConditionParser                                               }
{ ------------------------------------------------------------------ }

procedure TTestConditionParser.ParseIfDef;
var
  LCond: TDLCondition;
begin
  LCond := TDLConditionParser.ParseDirective('{$IFDEF DEBUG}');
  try
    Assert.IsNotNull(LCond);
    Assert.AreEqual(ckDefined, LCond.Kind);
    Assert.AreEqual('DEBUG', LCond.Symbol);
  finally
    LCond.Free;
  end;
end;

procedure TTestConditionParser.ParseIfNdef;
var
  LCond: TDLCondition;
begin
  LCond := TDLConditionParser.ParseDirective('{$IFNDEF POSIX}');
  try
    Assert.IsNotNull(LCond);
    Assert.AreEqual(ckNotDefined, LCond.Kind);
    Assert.AreEqual('POSIX', LCond.Symbol);
  finally
    LCond.Free;
  end;
end;

procedure TTestConditionParser.ParseIfExpression;
var
  LCond: TDLCondition;
begin
  LCond := TDLConditionParser.ParseDirective(
    '{$IF Defined(WIN32) or (Defined(LINUX) and not Defined(ARM))}');
  try
    Assert.IsNotNull(LCond);
    Assert.AreEqual(ckOr, LCond.Kind);
    Assert.AreEqual(ckDefined, LCond.Left.Kind);
    Assert.AreEqual('WIN32', LCond.Left.Symbol);
    Assert.AreEqual(ckAnd, LCond.Right.Kind);
  finally
    LCond.Free;
  end;
end;

procedure TTestConditionParser.ParseElse;
var
  LCond: TDLCondition;
begin
  LCond := TDLConditionParser.ParseDirective('{$ELSE}');
  try
    Assert.IsNotNull(LCond);
    Assert.AreEqual(ckAlways, LCond.Kind);
  finally
    LCond.Free;
  end;
end;

procedure TTestConditionParser.ParseNonConditionalReturnsNil;
begin
  Assert.IsNull(TDLConditionParser.ParseDirective('{$ENDIF}'));
  Assert.IsNull(TDLConditionParser.ParseDirective('{$MESSAGE HINT x}'));
  Assert.IsNull(TDLConditionParser.ParseDirective('not a directive'));
end;

{ ------------------------------------------------------------------ }
{ TTestConditionEvaluation                                            }
{ ------------------------------------------------------------------ }

procedure TTestConditionEvaluation.EvaluateDefined;
var
  LCond: TDLCondition;
  LDefines: TDLDefineSet;
begin
  LCond := TDLConditionParser.ParseDirective('{$IFDEF DEBUG}');
  LDefines := TDLDefineSet.Create;
  try
    Assert.IsFalse(LCond.Evaluate(LDefines));
    LDefines.Define('DEBUG');
    Assert.IsTrue(LCond.Evaluate(LDefines));
  finally
    LDefines.Free;
    LCond.Free;
  end;
end;

procedure TTestConditionEvaluation.EvaluateNotAndOr;
var
  LCond: TDLCondition;
  LDefines: TDLDefineSet;
begin
  LDefines := TDLDefineSet.Create;
  try
    LCond := TDLConditionParser.ParseDirective(
      '{$IFNDEF POSIX}');
    try
      Assert.IsTrue(LCond.Evaluate(LDefines));
    finally
      LCond.Free;
    end;

    LCond := TDLConditionParser.ParseDirective(
      '{$IF Defined(A) or Defined(B)}');
    try
      LDefines.Define('B');
      Assert.IsTrue(LCond.Evaluate(LDefines));
      LDefines.Undefine('B');
      Assert.IsFalse(LCond.Evaluate(LDefines));
    finally
      LCond.Free;
    end;
  finally
    LDefines.Free;
  end;
end;

procedure TTestConditionEvaluation.EvaluatePrecedence;
var
  LCond: TDLCondition;
  LDefines: TDLDefineSet;
begin
  // not binds tighter than and, and tighter than or:
  //   A or not B and C   ==  A or ((not B) and C)
  LDefines := TDLDefineSet.Create;
  try
    LCond := TDLConditionParser.ParseDirective(
      '{$IF Defined(A) or not Defined(B) and Defined(C)}');
    try
      // B defined -> (not B) = false -> overall depends on A only.
      LDefines.Define('B');
      LDefines.Define('C');
      Assert.IsFalse(LCond.Evaluate(LDefines));
      LDefines.Define('A');
      Assert.IsTrue(LCond.Evaluate(LDefines));
    finally
      LCond.Free;
    end;
  finally
    LDefines.Free;
  end;
end;

procedure TTestConditionEvaluation.EvaluateElseAlways;
var
  LCond: TDLCondition;
  LDefines: TDLDefineSet;
begin
  LCond := TDLConditionParser.ParseDirective('{$ELSE}');
  LDefines := TDLDefineSet.Create;
  try
    Assert.IsTrue(LCond.Evaluate(LDefines));
  finally
    LDefines.Free;
    LCond.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ TTestDefineSet                                                     }
{ ------------------------------------------------------------------ }

procedure TTestDefineSet.DefineIsCaseInsensitive;
var
  LDefines: TDLDefineSet;
begin
  LDefines := TDLDefineSet.Create;
  try
    LDefines.Define('Debug');
    Assert.IsTrue(LDefines.IsDefined('debug'));
    Assert.IsTrue(LDefines.IsDefined('DEBUG'));
  finally
    LDefines.Free;
  end;
end;

procedure TTestDefineSet.UndefineRemoves;
var
  LDefines: TDLDefineSet;
begin
  LDefines := TDLDefineSet.Create;
  try
    LDefines.Define('X');
    Assert.IsTrue(LDefines.IsDefined('X'));
    LDefines.Undefine('X');
    Assert.IsFalse(LDefines.IsDefined('X'));
  finally
    LDefines.Free;
  end;
end;

procedure TTestDefineSet.CloneIsIndependent;
var
  LDefines, LClone: TDLDefineSet;
begin
  LDefines := TDLDefineSet.Create;
  try
    LDefines.Define('A');
    LClone := LDefines.Clone;
    try
      Assert.IsTrue(LClone.IsDefined('A'));
      LClone.Undefine('A');
      Assert.IsTrue(LDefines.IsDefined('A'));
    finally
      LClone.Free;
    end;
  finally
    LDefines.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConditionParser);
  TDUnitX.RegisterTestFixture(TTestConditionEvaluation);
  TDUnitX.RegisterTestFixture(TTestDefineSet);

end.
