/// <summary>
///   Tests.DX.Delphi.Parser.Members — DUnitX coverage for class members:
///   properties (all clauses), method directives, class operators,
///   parameter modes and attributes.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Parser.Members;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestParserProperties = class
  public
    [Test]
    procedure PropertyWithAllClauses;
    [Test]
    procedure IndexedProperty;
    [Test]
    procedure PropertyImplements;
  end;

  [TestFixture]
  TTestParserDirectives = class
  public
    [Test]
    procedure MessageDirective;
    [Test]
    procedure ExternalDirective;
    [Test]
    procedure DeprecatedAndCallingConventions;
    [Test]
    procedure ForwardDeclaration;
  end;

  [TestFixture]
  TTestParserOperators = class
  public
    [Test]
    procedure OperatorSymbolNames;
    [Test]
    procedure OperatorImplicitExplicit;
  end;

  [TestFixture]
  TTestParserParameters = class
  public
    [Test]
    procedure AllParameterModes;
    [Test]
    procedure ConstRefAndVarRef;
    [Test]
    procedure DefaultValues;
    [Test]
    procedure MultipleNames;
  end;

  [TestFixture]
  TTestParserAttributes = class
  public
    [Test]
    procedure AttributesOnTypeAndMethod;
    [Test]
    procedure AttributeWithArguments;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestParserProperties }

procedure TTestParserProperties.PropertyWithAllClauses;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
  LProperty: TDLPropertyDecl;
  LMember: TDLMember;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TFoo = class'#13#10+
      '    private'#13#10+
      '      FValue: Integer;'#13#10+
      '      function GetValue: Integer;'#13#10+
      '      procedure SetValue(AValue: Integer);'#13#10+
      '    published'#13#10+
      '      property Value: Integer read GetValue write SetValue'#13#10+
      '        stored False default 0 nodefault;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LProperty := nil;
      for LMember in LClass.Members do
        if LMember is TDLPropertyDecl then
          LProperty := TDLPropertyDecl(LMember);
      Assert.IsNotNull(LProperty, 'property not found');
      Assert.AreEqual('Value', LProperty.Name.Name);
      Assert.IsNotNull(LProperty.ReadName);
      Assert.AreEqual('GetValue', LProperty.ReadName.Name);
      Assert.IsNotNull(LProperty.WriteName);
      Assert.IsNotNull(LProperty.StoredName);
      Assert.IsTrue(LProperty.IsDefault);
      Assert.IsTrue(LProperty.IsNodefault);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserProperties.IndexedProperty;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
  LProperty: TDLPropertyDecl;
  LMember: TDLMember;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TGrid = class'#13#10+
      '    property Cells[ARow, ACol: Integer]: string read GetCell'#13#10+
      '      write SetCell;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LProperty := nil;
      for LMember in LClass.Members do
        if LMember is TDLPropertyDecl then
          LProperty := TDLPropertyDecl(LMember);
      Assert.IsNotNull(LProperty);
      // Cells[ARow, ACol: Integer] is ONE parameter group with two names
      Assert.AreEqual(1, LProperty.IndexParams.Count);
      Assert.AreEqual(2, LProperty.IndexParams[0].Names.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserProperties.PropertyImplements;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
  LProperty: TDLPropertyDecl;
  LMember: TDLMember;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TFoo = class'#13#10+
      '    property MyGreeter: IGreeter read FGreeter implements IGreeter;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LProperty := nil;
      for LMember in LClass.Members do
        if LMember is TDLPropertyDecl then
          LProperty := TDLPropertyDecl(LMember);
      Assert.IsNotNull(LProperty);
      Assert.AreEqual(1, LProperty.Implements.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserDirectives }

procedure TTestParserDirectives.MessageDirective;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
  LDirective: TDLDirective;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TWin = class'#13#10+
      '    procedure Notify; message WM_USER;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(
        TDLClassType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr)
          .Members[0]);
      Assert.AreEqual(1, LMethod.Directives.Count);
      LDirective := LMethod.Directives[0];
      Assert.AreEqual('message', LDirective.Name.Name);
      Assert.AreEqual(1, LDirective.Values.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserDirectives.ExternalDirective;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
  LDirective: TDLDirective;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'procedure Foo; external ''user32.dll'' name ''MessageBoxA'';'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLMethodDecl);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      Assert.AreEqual(1, LMethod.Directives.Count);
      LDirective := LMethod.Directives[0];
      Assert.AreEqual('external', LDirective.Name.Name);
      Assert.IsTrue(LDirective.Values.Count >= 2);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserDirectives.DeprecatedAndCallingConventions;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
  LFoundDeprecated: Boolean;
  LFoundStdcall: Boolean;
  LDirective: TDLDirective;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'function Old: Integer; stdcall; deprecated ''use New'';'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      LFoundDeprecated := False;
      LFoundStdcall := False;
      for LDirective in LMethod.Directives do
      begin
        if LDirective.Name.Name = 'deprecated' then
          LFoundDeprecated := True;
        if LDirective.Name.Name = 'stdcall' then
          LFoundStdcall := True;
      end;
      Assert.IsTrue(LFoundStdcall);
      Assert.IsTrue(LFoundDeprecated);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserDirectives.ForwardDeclaration;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
  LDirective: TDLDirective;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'procedure Later; forward;'#13#10'implementation'#13#10+
      'procedure Later;'#13#10'begin end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLMethodDecl);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      LDirective := LMethod.Directives[0];
      Assert.AreEqual('forward', LDirective.Name.Name);
      // implementation with body
      Assert.IsTrue(LUnit.Items[1] is TDLMethodImpl);
      Assert.IsNotNull(TDLMethodImpl(LUnit.Items[1]).Body);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserOperators }

procedure TTestParserOperators.OperatorSymbolNames;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TVec = record'#13#10+
      '    class operator Add(const A, B: TVec): TVec;'#13#10+
      '    class operator Implicit(const A: Integer): TVec;'#13#10+
      '    class operator Equal(const A, B: TVec): Boolean;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(
        TDLRecordType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr)
          .Members[0]);
      Assert.AreEqual('Add', LMethod.Name.Name);
      Assert.IsNotNull(LMethod.ReturnType);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserOperators.OperatorImplicitExplicit;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TConv = record'#13#10+
      '    class operator Explicit(const A: TConv): Integer;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(
        TDLRecordType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr)
          .Members[0]);
      Assert.AreEqual('Explicit', LMethod.Name.Name);
      Assert.AreEqual(prOperator, LMethod.Kind);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserParameters }

procedure TTestParserParameters.AllParameterModes;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
  LParams: TList<TDLParameter>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'procedure P(const A: Integer; var B: Integer; out C: Integer);'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      LParams := LMethod.Params;
      Assert.AreEqual(3, LParams.Count);
      Assert.AreEqual(pmConst, LParams[0].Modifier);
      Assert.AreEqual(pmVar, LParams[1].Modifier);
      Assert.AreEqual(pmOut, LParams[2].Modifier);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserParameters.ConstRefAndVarRef;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'procedure P(const [Ref] A: Integer; var [Ref] B: Integer);'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      Assert.AreEqual(2, LMethod.Params.Count);
      Assert.AreEqual(pmConstRef, LMethod.Params[0].Modifier);
      Assert.AreEqual(pmVarRef, LMethod.Params[1].Modifier);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserParameters.DefaultValues;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'procedure P(A: Integer = 42; S: string = ''x'');'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      Assert.IsNotNull(LMethod.Params[0].DefaultValue);
      Assert.IsNotNull(LMethod.Params[1].DefaultValue);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserParameters.MultipleNames;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'procedure P(A, B, C: Integer);'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      Assert.AreEqual(1, LMethod.Params.Count);
      Assert.AreEqual(3, LMethod.Params[0].Names.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserAttributes }

procedure TTestParserAttributes.AttributesOnTypeAndMethod;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      '[Reflect]'#13#10+
      '[Custom(''arg'')]'#13#10+
      'procedure P;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLMethodDecl);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      Assert.AreEqual(2, LMethod.Attributes.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserAttributes.AttributeWithArguments;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      '[MyAttr(1, ''two'', True)]'#13#10+
      'procedure P;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LMethod := TDLMethodDecl(LUnit.Items[0]);
      Assert.AreEqual(1, LMethod.Attributes.Count);
      Assert.AreEqual(3, LMethod.Attributes[0].Args.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParserProperties);
  TDUnitX.RegisterTestFixture(TTestParserDirectives);
  TDUnitX.RegisterTestFixture(TTestParserOperators);
  TDUnitX.RegisterTestFixture(TTestParserParameters);
  TDUnitX.RegisterTestFixture(TTestParserAttributes);

end.
