/// <summary>
///   Tests.DX.Delphi.Ast.Lowering — DUnitX coverage for the CST -> AST
///   lowering of types, members, statements and expressions.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Ast.Lowering;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.AST;

type
  [TestFixture]
  TTestAstTypeLowering = class
  public
    [Test]
    procedure ScalarTypes;
    [Test]
    procedure ArrayTypes;
    [Test]
    procedure RecordWithVariant;
    [Test]
    procedure GenericInstantiation;
  end;

  [TestFixture]
  TTestAstMemberLowering = class
  public
    [Test]
    procedure MethodDirectivesAndReturn;
    [Test]
    procedure PropertyLowering;
  end;

  [TestFixture]
  TTestAstStatementLowering = class
  public
    [Test]
    procedure AllLoopForms;
    [Test]
    procedure TryExceptAndOnHandlers;
  end;

  [TestFixture]
  TTestAstExpressionLowering = class
  public
    [Test]
    procedure BinaryAndUnary;
    [Test]
    procedure CallsAndMembers;
  end;

  [TestFixture]
  TTestAstResolvedLimitations = class
  public
    [Test]
    procedure LocalDeclarationsAreLowered;
    [Test]
    procedure GenericTypeDeclarationParameters;
    [Test]
    procedure ConstValuesAreExpressionTrees;
    [Test]
    procedure MethodImplLocalDeclarations;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestAstTypeLowering }

procedure TTestAstTypeLowering.ScalarTypes;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LDecl: TDLTypeDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type'#13#10+
      '  TSet = set of Byte;'#13#10+
      '  TPtr = ^Integer;'#13#10+
      '  TRange = 1..10;'#13#10+
      '  TName = string[20];'#13#10+
      '  TData = file of Byte;'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(TDLTypeDecl(LModule.Declarations[0]).TypeDef
        is TDLSetTypeDef);
      Assert.IsTrue(TDLTypeDecl(LModule.Declarations[1]).TypeDef
        is TDLPointerTypeDef);
      Assert.IsTrue(TDLTypeDecl(LModule.Declarations[2]).TypeDef
        is TDLSubrangeTypeDef);
      LDecl := TDLTypeDecl(LModule.Declarations[3]);
      Assert.IsTrue(LDecl.TypeDef is TDLStringTypeDef);
      Assert.AreEqual(20, TDLStringTypeDef(LDecl.TypeDef).FixedLength);
      Assert.IsTrue(TDLTypeDecl(LModule.Declarations[4]).TypeDef
        is TDLFileTypeDef);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstTypeLowering.ArrayTypes;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LDecl: TDLTypeDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type'#13#10+
      '  TGrid = array[1..3, 1..3] of Double;'#13#10+
      '  TDyn = array of array of string;'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LDecl := TDLTypeDecl(LModule.Declarations[0]);
      Assert.IsTrue(LDecl.TypeDef is TDLStaticArrayTypeDef);
      Assert.AreEqual<NativeInt>(2, TDLStaticArrayTypeDef(
        LDecl.TypeDef).Bounds.Count);
      Assert.AreEqual('Double', TDLStaticArrayTypeDef(
        LDecl.TypeDef).ElementType);
      LDecl := TDLTypeDecl(LModule.Declarations[1]);
      Assert.IsTrue(LDecl.TypeDef is TDLDynamicArrayTypeDef);
      Assert.AreEqual('array of string', TDLDynamicArrayTypeDef(
        LDecl.TypeDef).ElementType);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstTypeLowering.RecordWithVariant;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LRecord: TDLRecordTypeDef;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type TV = record'#13#10+
      '  case Kind: Integer of'#13#10+
      '    0: (I: Integer);'#13#10+
      '    1: (S: string);'#13#10+
      'end;'#13#10'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LRecord := TDLRecordTypeDef(
        TDLTypeDecl(LModule.Declarations[0]).TypeDef);
      Assert.IsNotNull(LRecord.VariantPart);
      Assert.AreEqual('Kind', LRecord.VariantPart.Tag);
      Assert.AreEqual<NativeInt>(2, LRecord.VariantPart.Fields.Count);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstTypeLowering.GenericInstantiation;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LVar: TDLVarDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'var'#13#10+
      '  L: TList<Integer>;'#13#10+
      '  M: TDictionary<string, TList<Double>>;'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LVar := TDLVarDecl(LModule.Declarations[0]);
      Assert.AreEqual('TList<Integer>', LVar.TypeName);
      LVar := TDLVarDecl(LModule.Declarations[1]);
      Assert.AreEqual('TDictionary<string, TList<Double>>', LVar.TypeName);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstMemberLowering }

procedure TTestAstMemberLowering.MethodDirectivesAndReturn;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LClass: TDLClassTypeDef;
  LMethod: TDLMethod;
  LMember: TDLMember;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type TFoo = class'#13#10+
      '  public'#13#10+
      '    function Compute(AX: Integer): Integer; virtual;'#13#10+
      'end;'#13#10'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassTypeDef(
        TDLTypeDecl(LModule.Declarations[0]).TypeDef);
      LMethod := nil;
      for LMember in LClass.Members do
        if LMember is TDLMethod then
          LMethod := TDLMethod(LMember);
      Assert.IsNotNull(LMethod);
      Assert.AreEqual('Compute', LMethod.Name);
      Assert.AreEqual(prFunction, LMethod.Kind);
      Assert.AreEqual('Integer', LMethod.ReturnType);
      Assert.AreEqual<NativeInt>(1, LMethod.Params.Count);
      Assert.AreEqual<NativeInt>(1, LMethod.Directives.Count);
      Assert.AreEqual('virtual', LMethod.Directives[0]);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstMemberLowering.PropertyLowering;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LClass: TDLClassTypeDef;
  LProperty: TDLProperty;
  LMember: TDLMember;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type TFoo = class'#13#10+
      '  private'#13#10+
      '    FValue: Integer;'#13#10+
      '    function GetValue: Integer;'#13#10+
      '    procedure SetValue(AValue: Integer);'#13#10+
      '  published'#13#10+
      '    property Value: Integer read GetValue write SetValue'#13#10+
      '      stored False default 0;'#13#10+
      'end;'#13#10'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassTypeDef(
        TDLTypeDecl(LModule.Declarations[0]).TypeDef);
      LProperty := nil;
      for LMember in LClass.Members do
        if LMember is TDLProperty then
          LProperty := TDLProperty(LMember);
      Assert.IsNotNull(LProperty);
      Assert.AreEqual('Value', LProperty.Name);
      Assert.AreEqual('Integer', LProperty.TypeName);
      Assert.AreEqual('GetValue', LProperty.ReadName);
      Assert.AreEqual('SetValue', LProperty.WriteName);
      Assert.IsTrue(LProperty.IsDefault);
      Assert.AreEqual(vsPublished, LProperty.Visibility);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstStatementLowering }

procedure TTestAstStatementLowering.AllLoopForms;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10'implementation'#13#10+
      'procedure P;'#13#10'var a: array of Integer; i: Integer;'#13#10'begin'#13#10+
      '  for i := 0 to 9 do a[i] := i;'#13#10+
      '  while i > 0 do Dec(i);'#13#10+
      '  repeat Inc(i); until i = 10;'#13#10+
      '  for var x in a do i := x;'#13#10'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      Assert.AreEqual<NativeInt>(4, LProc.Body.Count);
      Assert.IsTrue(LProc.Body[0] is TDLForStmt);
      Assert.AreEqual('to', TDLForStmt(LProc.Body[0]).Direction);
      Assert.IsTrue(LProc.Body[1] is TDLWhileStmt);
      Assert.IsTrue(LProc.Body[2] is TDLRepeatStmt);
      Assert.IsTrue(LProc.Body[3] is TDLForStmt);
      Assert.AreEqual('in', TDLForStmt(LProc.Body[3]).Direction);
      Assert.IsTrue(TDLForStmt(LProc.Body[3]).IsInline);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstStatementLowering.TryExceptAndOnHandlers;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
  LTry: TDLTryStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10'implementation'#13#10+
      'procedure P;'#13#10'begin'#13#10+
      '  try'#13#10+
      '    Foo;'#13#10+
      '  except'#13#10+
      '    on E: Exception do Bar;'#13#10+
      '  else'#13#10+
      '    Baz;'#13#10+
      '  end;'#13#10'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      LTry := TDLTryStmt(LProc.Body[0]);
      Assert.IsTrue(LTry.IsExcept);
      Assert.AreEqual<NativeInt>(1, LTry.Handlers.Count);
      Assert.AreEqual('E', LTry.Handlers[0].VarName);
      Assert.AreEqual('Exception', LTry.Handlers[0].TypeName);
      Assert.IsNotNull(LTry.ElseBranch);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstExpressionLowering }

procedure TTestAstExpressionLowering.BinaryAndUnary;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
  LAssign: TDLAssignStmt;
  LBinary: TDLBinaryExpr;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10'implementation'#13#10+
      'procedure P;'#13#10'begin'#13#10+
      '  x := a + b * c;'#13#10+
      '  y := not z;'#13#10'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      LAssign := TDLAssignStmt(LProc.Body[0]);
      LBinary := TDLBinaryExpr(LAssign.Value);
      Assert.AreEqual(boAdd, LBinary.Operator);
      Assert.AreEqual('+', LBinary.OperatorText);
      Assert.IsTrue(LBinary.Right is TDLBinaryExpr);
      Assert.AreEqual(boMultiply, TDLBinaryExpr(LBinary.Right).Operator);
      LAssign := TDLAssignStmt(LProc.Body[1]);
      Assert.IsTrue(LAssign.Value is TDLUnaryExpr);
      Assert.AreEqual(uoNot, TDLUnaryExpr(LAssign.Value).Operator);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstExpressionLowering.CallsAndMembers;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
  LExprStmt: TDLExprStmt;
  LCall: TDLCallExpr;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10'implementation'#13#10+
      'procedure P;'#13#10'begin'#13#10+
      '  Foo.Bar(1, 2);'#13#10'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      LExprStmt := TDLExprStmt(LProc.Body[0]);
      LCall := TDLCallExpr(LExprStmt.Expression);
      Assert.AreEqual<NativeInt>(2, LCall.Args.Count);
      Assert.IsTrue(LCall.Callee is TDLMemberExpr);
      Assert.AreEqual('Bar', TDLMemberExpr(LCall.Callee).Member);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstResolvedLimitations }

procedure TTestAstResolvedLimitations.LocalDeclarationsAreLowered;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
  LDecl: TDLDeclaration;
  LFoundVar: Boolean;
  LFoundLabel: Boolean;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10'implementation'#13#10+
      'procedure P;'#13#10+
      'label Done;'#13#10+
      'var i: Integer;'#13#10'begin'#13#10+
      '  i := 1;'#13#10'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      Assert.AreEqual<NativeInt>(2, LProc.LocalDeclarations.Count);
      LFoundVar := False;
      LFoundLabel := False;
      for LDecl in LProc.LocalDeclarations do
      begin
        if LDecl is TDLVarDecl then
          LFoundVar := True;
        if LDecl is TDLLabelDecl then
          LFoundLabel := True;
      end;
      Assert.IsTrue(LFoundVar, 'local var not lowered');
      Assert.IsTrue(LFoundLabel, 'local label not lowered');
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstResolvedLimitations.GenericTypeDeclarationParameters;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LTypeDecl: TDLTypeDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type TBox<T> = class'#13#10+
      '  private'#13#10+
      '    FValue: T;'#13#10+
      '  public'#13#10+
      '    procedure SetValue(const AValue: T);'#13#10+
      'end;'#13#10'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LTypeDecl := TDLTypeDecl(LModule.Declarations[0]);
      Assert.IsTrue(LTypeDecl.TypeDef is TDLGenericTypeDef);
      Assert.AreEqual<NativeInt>(1, TDLGenericTypeDef(LTypeDecl.TypeDef).TypeParams.Count);
      Assert.AreEqual('T', TDLGenericTypeDef(
        LTypeDecl.TypeDef).TypeParams[0]);
      Assert.IsTrue(TDLGenericTypeDef(LTypeDecl.TypeDef).BaseDef
        is TDLClassTypeDef);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstResolvedLimitations.ConstValuesAreExpressionTrees;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LConst: TDLConstDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'const'#13#10+
      '  A = 1 + 2;'#13#10+
      '  S = [1, 2, 4];'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LConst := TDLConstDecl(LModule.Declarations[0]);
      Assert.IsTrue(LConst.Value is TDLBinaryExpr);
      Assert.AreEqual(boAdd, TDLBinaryExpr(LConst.Value).Operator);
      LConst := TDLConstDecl(LModule.Declarations[1]);
      Assert.IsTrue(LConst.Value is TDLSetExpr);
      Assert.AreEqual<NativeInt>(3, TDLSetExpr(LConst.Value).Elements.Count);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstResolvedLimitations.MethodImplLocalDeclarations;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type TFoo = class'#13#10'end;'#13#10'implementation'#13#10+
      'procedure TFoo.DoIt;'#13#10+
      'var x: Integer;'#13#10'begin'#13#10+
      '  x := 1;'#13#10'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[1]);
      Assert.AreEqual<NativeInt>(1, LProc.LocalDeclarations.Count);
      Assert.IsTrue(LProc.LocalDeclarations[0] is TDLVarDecl);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAstTypeLowering);
  TDUnitX.RegisterTestFixture(TTestAstMemberLowering);
  TDUnitX.RegisterTestFixture(TTestAstStatementLowering);
  TDUnitX.RegisterTestFixture(TTestAstExpressionLowering);
  TDUnitX.RegisterTestFixture(TTestAstResolvedLimitations);

end.
