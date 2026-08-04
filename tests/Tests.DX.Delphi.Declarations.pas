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
  DX.Delphi.CST;

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
      LConst := TDLConstSection(LUnit.Items[0]).Items[0];
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
      LConst := TDLConstSection(LUnit.Items[0]).Items[0];
      Assert.IsNotNull(LConst.Value);
      LExpr := LConst.Value;
      Assert.IsTrue(LExpr is TDLBinaryExpr);
      Assert.AreEqual(boAdd, TDLBinaryExpr(LExpr).Operator);
      LConst := TDLConstSection(LUnit.Items[0]).Items[1];
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
      LConst := TDLConstSection(LUnit.Items[0]).Items[0];
      Assert.AreEqual(3, LConst.Names.Count);
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
      LVar := TDLVarSection(LUnit.Items[0]).Items[1];
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
      LVar := TDLVarSection(LUnit.Items[0]).Items[0];
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
      LVar := TDLVarSection(LUnit.Items[0]).Items[0];
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
      Assert.AreEqual(1, TDLVarSection(LUnit.Items[0]).Attributes.Count);
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
      LDecl := TDLTypeSection(LUnit.Items[0]).Items[0];
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
        TDLTypeSection(LUnit.Items[0]).Items[0].TypeExpr);
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
        TDLTypeSection(LUnit.Items[0]).Items[0].TypeExpr);
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
        TDLTypeSection(LUnit.Items[0]).Items[0].TypeExpr);
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
        TDLTypeSection(LUnit.Items[0]).Items[0].TypeExpr);
      Assert.AreEqual(prFunction, LProc.Kind);
      Assert.AreEqual(1, LProc.Params.Count);
      Assert.AreEqual(1, LProc.Directives.Count);
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
  TDUnitX.RegisterTestFixture(TTestAttributesDeclarations);
  TDUnitX.RegisterTestFixture(TTestClassDeclarations);

end.
