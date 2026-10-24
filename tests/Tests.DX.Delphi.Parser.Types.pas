/// <summary>
///   Tests.DX.Delphi.Parser.Types — DUnitX coverage for advanced type
///   constructs: interfaces, objects, class references, sealed/abstract,
///   nested generics, enumerations, subranges and procedural types.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Parser.Types;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestParserInterfaceTypes = class
  public
    [Test]
    procedure InterfaceWithGuid;
    [Test]
    procedure DispInterfaceType;
    [Test]
    procedure OldStyleObject;
  end;

  [TestFixture]
  TTestParserClassKinds = class
  public
    [Test]
    procedure SealedAndAbstract;
    [Test]
    procedure ClassReference;
    [Test]
    procedure ClassVarSection;
    [Test]
    procedure NestedTypeSection;
  end;

  [TestFixture]
  TTestParserGenericTypes = class
  public
    [Test]
    procedure TwoTypeParameters;
    [Test]
    procedure NestedInstantiation;
    [Test]
    procedure GenericMethodTypeArgs;
  end;

  [TestFixture]
  TTestParserScalarTypes = class
  public
    [Test]
    procedure EnumWithValues;
    [Test]
    procedure IdentifierSubrange;
    [Test]
    procedure SetOfEnum;
    [Test]
    procedure PointerAndFile;
    [Test]
    procedure FixedString;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestParserInterfaceTypes }

procedure TTestParserInterfaceTypes.InterfaceWithGuid;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  IGreeter = interface'#13#10+
      '    [''{8A2C3B5E-4D61-4C2B-9A3F-0E7B1C5D2F8A}'']'#13#10+
      '    procedure Greet;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LClass.IsInterface);
      Assert.AreEqual<NativeInt>(1, LClass.Members.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserInterfaceTypes.DispInterfaceType;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  IAuto = dispinterface'#13#10+
      '    [''{11111111-2222-3333-4444-555555555555}'']'#13#10+
      '    procedure DoIt;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LClass.IsInterface);
      Assert.IsTrue(LClass.IsDispInterface);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserInterfaceTypes.OldStyleObject;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TRec = object'#13#10+
      '    FData: Integer;'#13#10+
      '    procedure Clear;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LClass.IsObject);
      Assert.AreEqual<NativeInt>(2, LClass.Members.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserClassKinds }

procedure TTestParserClassKinds.SealedAndAbstract;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TSealed = class sealed'#13#10'  end;'#13#10+
      '  TAbstract = class abstract'#13#10'  end;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LClass.IsSealed);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[1]).TypeExpr);
      Assert.IsTrue(LClass.IsAbstract);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserClassKinds.ClassReference;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TRef = class of TObject;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LClass.IsClassRef);
      Assert.IsNotNull(LClass.BaseType);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserClassKinds.ClassVarSection;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
  LFoundMethod: Boolean;
  LMember: TDLMember;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TCls = class'#13#10+
      '    class var'#13#10+
      '      FShared: Integer;'#13#10+
      '    procedure P;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      // class var sections are parsed and skipped; the method must survive
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LFoundMethod := False;
      for LMember in LClass.Members do
        if LMember is TDLMethodDecl then
          LFoundMethod := True;
      Assert.IsTrue(LFoundMethod, 'method after class var not found');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserClassKinds.NestedTypeSection;
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
      '    type'#13#10+
      '      TInner = class'#13#10+
      '        Value: Integer;'#13#10+
      '      end;'#13#10+
      '    procedure P;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LFoundMethod := False;
      for LMember in LClass.Members do
        if LMember is TDLMethodDecl then
          LFoundMethod := True;
      Assert.IsTrue(LFoundMethod, 'method after nested type section not found');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserGenericTypes }

procedure TTestParserGenericTypes.TwoTypeParameters;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TPair<TKey, TValue> = class'#13#10+
      '    procedure SetPair(const AKey: TKey; const AValue: TValue);'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.AreEqual<NativeInt>(1, LClass.Members.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserGenericTypes.NestedInstantiation;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LNamed: TDLNamedType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TNested = TList<TDictionary<string, Integer>>;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LNamed := TDLNamedType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.AreEqual<NativeInt>(1, LNamed.TypeArgs.Count);
      Assert.IsTrue(LNamed.TypeArgs[0].TypeExpr is TDLNamedType);
      Assert.AreEqual<NativeInt>(2, TDLNamedType(
        LNamed.TypeArgs[0].TypeExpr).TypeArgs.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserGenericTypes.GenericMethodTypeArgs;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodImpl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'implementation'#13#10+
      'procedure TCls.DoIt<T>(const AValue: T);'#13#10'begin end;'#13#10+
      'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLMethodImpl);
      LMethod := TDLMethodImpl(LUnit.Items[0]);
      Assert.AreEqual<NativeInt>(1, LMethod.Params.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserScalarTypes }

procedure TTestParserScalarTypes.EnumWithValues;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LEnum: TDLEnumType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TColor = (Red = 1, Green = 2, Blue = 4);'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LEnum := TDLEnumType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.AreEqual<NativeInt>(3, LEnum.Members.Count);
      Assert.IsNotNull(LEnum.Members[0].Value);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserScalarTypes.IdentifierSubrange;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSubrange: TDLSubrangeType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TIdx = LowIdx..HighIdx;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSubrange := TDLSubrangeType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsNotNull(LSubrange.Low);
      Assert.IsNotNull(LSubrange.High);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserScalarTypes.SetOfEnum;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSet: TDLSetType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TFlags = set of TColor;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSet := TDLSetType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsNotNull(LSet.BaseType);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserScalarTypes.PointerAndFile;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TPtr = ^Integer;'#13#10+
      '  TData = file of Byte;'#13#10+
      '  TAny = file;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr
        is TDLPointerType);
      Assert.IsTrue(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[1]).TypeExpr
        is TDLFileType);
      Assert.IsTrue(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[2]).TypeExpr
        is TDLFileType);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserScalarTypes.FixedString;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LStringType: TDLStringType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TName = string[32];'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LStringType := TDLStringType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsNotNull(LStringType.Length);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParserInterfaceTypes);
  TDUnitX.RegisterTestFixture(TTestParserClassKinds);
  TDUnitX.RegisterTestFixture(TTestParserGenericTypes);
  TDUnitX.RegisterTestFixture(TTestParserScalarTypes);

end.
