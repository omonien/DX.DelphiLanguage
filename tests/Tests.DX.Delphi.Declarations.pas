/// <summary>
///   Tests.DX.Delphi.Declarations — DUnitX coverage for declaration forms:
///   typed constants, absolute vars, attributes, nested class sections,
///   procedural types with directives and class interfaces.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Declarations;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST,
  DX.Delphi.Conditions;

type
  [TestFixture]
  TTestConstDeclarations = class
  public
    [Test]
    procedure TypedConstant;
    [Test]
    procedure ConstWithExpression;
    [Test]
    procedure ConstMultipleNames;
  end;

  [TestFixture]
  TTestVarDeclarations = class
  public
    [Test]
    procedure VarWithAbsolute;
    [Test]
    procedure VarWithInit;
    [Test]
    procedure ThreadVarWithInit;
  end;

  [TestFixture]
  TTestConditionalTypeDeclarations = class
  public
    [Test]
    procedure ConditionalTypeGroup;
    [Test]
    procedure ConditionalTypeGroupProjection;
  end;

  [TestFixture]
  TTestConditionalConstVarDeclarations = class
  public
    [Test]
    procedure ConditionalConstGroup;
    [Test]
    procedure ConditionalVarGroup;
    [Test]
    procedure SharedEndInterfaceBody;
  end;

  [TestFixture]
  TTestAttributesDeclarations = class
  public
    [Test]
    procedure AttributesOnVarSection;
    [Test]
    procedure AttributesOnType;
  end;

  [TestFixture]
  TTestClassDeclarations = class
  public
    [Test]
    procedure ClassWithInterfaceList;
    [Test]
    procedure InterfaceInheritance;
    [Test]
    procedure ClassWithNestedConstAndType;
    [Test]
    procedure ProceduralTypeWithDirective;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestConstDeclarations }

procedure TTestConstDeclarations.TypedConstant;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LConst: TDLConstDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'const L: Integer = 42;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LConst := TDLConstDecl(TDLConstSection(LUnit.Items[0]).Items[0]);
      Assert.IsTrue(LConst.IsTyped);
      Assert.IsNotNull(LConst.TypeExpr);
      Assert.IsNotNull(LConst.Value);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestConstDeclarations.ConstWithExpression;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LConst: TDLConstDecl;
  LExpr: TDLExpr;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'const A = 2 * 3 + 1;'#13#10+
      '      B = ''x'' + ''y'';'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LConst := TDLConstDecl(TDLConstSection(LUnit.Items[0]).Items[0]);
      Assert.IsNotNull(LConst.Value);
      LExpr := LConst.Value;
      Assert.IsTrue(LExpr is TDLBinaryExpr);
      Assert.AreEqual(boAdd, TDLBinaryExpr(LExpr).Operator);
      LConst := TDLConstDecl(TDLConstSection(LUnit.Items[0]).Items[1]);
      Assert.IsTrue(LConst.Value is TDLBinaryExpr);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestConstDeclarations.ConstMultipleNames;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LConst: TDLConstDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'const A, B, C = 1;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LConst := TDLConstDecl(TDLConstSection(LUnit.Items[0]).Items[0]);
      Assert.AreEqual<NativeInt>(3, LConst.Names.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestVarDeclarations }

procedure TTestVarDeclarations.VarWithAbsolute;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LVar: TDLVarDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'var'#13#10+
      '  Low: Byte;'#13#10+
      '  HighByte: Byte absolute Low;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LVar := TDLVarDecl(TDLVarSection(LUnit.Items[0]).Items[1]);
      Assert.IsNotNull(LVar.AbsoluteTarget);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestVarDeclarations.VarWithInit;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LVar: TDLVarDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'var S: string = ''hello'';'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LVar := TDLVarDecl(TDLVarSection(LUnit.Items[0]).Items[0]);
      Assert.IsNotNull(LVar.Init);
      Assert.IsTrue(LVar.Init is TDLStringExpr);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestVarDeclarations.ThreadVarWithInit;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LVar: TDLVarDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'threadvar'#13#10'  TCount: Integer = 0;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LVar := TDLVarDecl(TDLVarSection(LUnit.Items[0]).Items[0]);
      Assert.IsNotNull(LVar.Init);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAttributesDeclarations }

procedure TTestAttributesDeclarations.AttributesOnVarSection;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      '[FieldOffset(0)]'#13#10'var X: Integer;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLVarSection);
      Assert.AreEqual<NativeInt>(1, TDLVarSection(LUnit.Items[0]).Attributes.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAttributesDeclarations.AttributesOnType;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LDecl: TDLTypeDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  [Serializable]'#13#10'  TFoo = class end;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      // attributes on type declarations are parsed; the section carries them
      Assert.AreEqual(0, LDiagnostics.Count);
      LDecl := TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]);
      Assert.AreEqual('TFoo', LDecl.Name.Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestClassDeclarations }

procedure TTestClassDeclarations.ClassWithInterfaceList;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TFoo = class(TInterfacedObject, IOne, ITwo)'#13#10'  end;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsNotNull(LClass.BaseType);
      Assert.AreEqual('TInterfacedObject',
        TDLNamedType(LClass.BaseType).Name.Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestClassDeclarations.InterfaceInheritance;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  IChild = interface(IBase)'#13#10'    procedure Go;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LClass.IsInterface);
      Assert.IsNotNull(LClass.BaseType);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestClassDeclarations.ClassWithNestedConstAndType;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
  LMember: TDLMember;
  LFoundMethod: Boolean;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TOuter = class'#13#10+
      '    const'#13#10+
      '      C = 1;'#13#10+
      '    type'#13#10+
      '      TInner = Integer;'#13#10+
      '    procedure Go;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LFoundMethod := False;
      for LMember in LClass.Members do
        if LMember is TDLMethodDecl then
          LFoundMethod := True;
      Assert.IsTrue(LFoundMethod, 'method after nested const/type not found');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestClassDeclarations.ProceduralTypeWithDirective;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LProc: TDLProceduralType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TCallback = function(X: Integer): Integer; stdcall;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProceduralType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.AreEqual(prFunction, LProc.Kind);
      Assert.AreEqual<NativeInt>(1, LProc.Params.Count);
      Assert.AreEqual<NativeInt>(1, LProc.Directives.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestConditionalTypeDeclarations.ConditionalTypeGroup;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSection: TDLTypeSection;
  LGroup: TDLConditionalGroup;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  A = Integer;'#13#10+
      '{$IFDEF POSIX}'#13#10+
      '  B = Single;'#13#10+
      '{$ELSE}'#13#10+
      '  B = Double;'#13#10+
      '{$ENDIF}'#13#10+
      '  C = Cardinal;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSection := TDLTypeSection(LUnit.Items[0]);
      // A, [conditional group], C
      Assert.AreEqual<NativeInt>(3, LSection.Items.Count);
      Assert.IsTrue(LSection.Items[0] is TDLTypeDecl);
      Assert.IsTrue(LSection.Items[1] is TDLConditionalGroup);
      Assert.IsTrue(LSection.Items[2] is TDLTypeDecl);
      LGroup := TDLConditionalGroup(LSection.Items[1]);
      Assert.AreEqual<NativeInt>(2, LGroup.Branches.Count);
      Assert.AreEqual('Defined(POSIX)', LGroup.Branches[0].Condition.ToString);
      Assert.AreEqual<NativeInt>(1, LGroup.Branches[0].Items.Count);
      Assert.AreEqual(ckAlways, LGroup.Branches[1].Condition.Kind);
      Assert.AreEqual<NativeInt>(1, LGroup.Branches[1].Items.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestConditionalTypeDeclarations.ConditionalTypeGroupProjection;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSection: TDLTypeSection;
  LGroup: TDLConditionalGroup;
  LDefines: TDLDefineSet;
  LActive: TDLConditionalDeclBranch;
  i: Integer;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '{$IFDEF POSIX}'#13#10+
      '  B = Single;'#13#10+
      '{$ELSE}'#13#10+
      '  B = Double;'#13#10+
      '{$ENDIF}'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      LSection := TDLTypeSection(LUnit.Items[0]);
      LGroup := TDLConditionalGroup(LSection.Items[0]);
      LDefines := TDLDefineSet.Create;
      try
        LActive := nil;
        for i := 0 to LGroup.Branches.Count - 1 do
          if LGroup.Branches[i].Condition.Evaluate(LDefines) then
          begin
            LActive := LGroup.Branches[i];
            Break;
          end;
        // Empty configuration: the {$ELSE} branch (Double) is active.
        Assert.IsNotNull(LActive);
        Assert.AreEqual<NativeInt>(1, LActive.Items.Count);
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

procedure TTestConditionalConstVarDeclarations.ConditionalConstGroup;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSection: TDLConstSection;
  LGroup: TDLConditionalGroup;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'const'#13#10+
      '  A = 1;'#13#10+
      '{$IFDEF POSIX}'#13#10+
      '  B = 2;'#13#10+
      '{$ELSE}'#13#10+
      '  B = 3;'#13#10+
      '{$ENDIF}'#13#10+
      '  C = 4;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSection := TDLConstSection(LUnit.Items[0]);
      // A, [conditional group], C
      Assert.AreEqual<NativeInt>(3, LSection.Items.Count);
      Assert.IsTrue(LSection.Items[0] is TDLConstDecl);
      Assert.IsTrue(LSection.Items[1] is TDLConditionalGroup);
      Assert.IsTrue(LSection.Items[2] is TDLConstDecl);
      LGroup := TDLConditionalGroup(LSection.Items[1]);
      Assert.AreEqual<NativeInt>(2, LGroup.Branches.Count);
      Assert.AreEqual('Defined(POSIX)', LGroup.Branches[0].Condition.ToString);
      Assert.AreEqual<NativeInt>(1, LGroup.Branches[0].Items.Count);
      Assert.IsTrue(LGroup.Branches[0].Items[0] is TDLConstDecl);
      Assert.AreEqual('B', TDLConstDecl(
        LGroup.Branches[0].Items[0]).Names[0].Name);
      Assert.AreEqual(ckAlways, LGroup.Branches[1].Condition.Kind);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestConditionalConstVarDeclarations.ConditionalVarGroup;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSection: TDLVarSection;
  LGroup: TDLConditionalGroup;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'var'#13#10+
      '  X: Integer;'#13#10+
      '{$IFDEF POSIX}'#13#10+
      '  Y: Single;'#13#10+
      '{$ELSE}'#13#10+
      '  Y: Double;'#13#10+
      '{$ENDIF}'#13#10+
      '  Z: Byte;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSection := TDLVarSection(LUnit.Items[0]);
      Assert.AreEqual<NativeInt>(3, LSection.Items.Count);
      Assert.IsTrue(LSection.Items[0] is TDLVarDecl);
      Assert.IsTrue(LSection.Items[1] is TDLConditionalGroup);
      Assert.IsTrue(LSection.Items[2] is TDLVarDecl);
      LGroup := TDLConditionalGroup(LSection.Items[1]);
      Assert.AreEqual<NativeInt>(2, LGroup.Branches.Count);
      Assert.AreEqual('Defined(POSIX)', LGroup.Branches[0].Condition.ToString);
      Assert.AreEqual<NativeInt>(1, LGroup.Branches[0].Items.Count);
      Assert.IsTrue(LGroup.Branches[0].Items[0] is TDLVarDecl);
      Assert.AreEqual('Y', TDLVarDecl(
        LGroup.Branches[0].Items[0]).Names[0].Name);
      Assert.AreEqual(ckAlways, LGroup.Branches[1].Condition.Kind);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestConditionalConstVarDeclarations.SharedEndInterfaceBody;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  // A shared-`end` construct: the interface base type is selected by a
  // conditional, but the member list continues after {$ENDIF}.
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TBase1 = interface'#13#10'  end;'#13#10+
      '  TBase2 = interface'#13#10'  end;'#13#10+
      '{$IFDEF IOS}'#13#10+
      '  TView = interface(TBase1)'#13#10+
      '{$ELSE}'#13#10+
      '  TView = interface(TBase2)'#13#10+
      '{$ENDIF}'#13#10+
      '    [''{B1CA7942-7BD4-41C1-A928-4AA9D2229C1A}'']'#13#10+
      '    procedure Bar;'#13#10+
      '  end;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      // One type section holding all interface declarations.
      Assert.AreEqual<NativeInt>(1, LUnit.Items.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLTypeSection);
      Assert.AreEqual<NativeInt>(3, TDLTypeSection(LUnit.Items[0]).Items.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstDeclarations);
  TDUnitX.RegisterTestFixture(TTestVarDeclarations);
  TDUnitX.RegisterTestFixture(TTestConditionalTypeDeclarations);
  TDUnitX.RegisterTestFixture(TTestConditionalConstVarDeclarations);
  TDUnitX.RegisterTestFixture(TTestAttributesDeclarations);
  TDUnitX.RegisterTestFixture(TTestClassDeclarations);

end.
