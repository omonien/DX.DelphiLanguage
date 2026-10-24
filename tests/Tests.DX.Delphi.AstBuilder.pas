/// <summary>
///   Tests.DX.Delphi.AstBuilder — DUnitX tests for the CST -> AST lowering:
///   module structure, type definitions, members, statements, expressions
///   and the recorded symbol table.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.AstBuilder;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST,
  DX.Delphi.AST;

type
  [TestFixture]
  TTestAstModule = class
  public
    [Test]
    procedure ModuleKindAndName;
    [Test]
    procedure UsesAreFlattened;
  end;

  [TestFixture]
  TTestAstDeclarations = class
  public
    [Test]
    procedure ConstAndVarDeclarations;
    [Test]
    procedure EnumAndClassTypes;
    [Test]
    procedure SymbolsAreRecorded;
  end;

  [TestFixture]
  TTestAstStatements = class
  public
    [Test]
    procedure MethodBodyStatements;
    [Test]
    procedure AnonymousMethodLowering;
  end;

implementation

uses
  DX.Delphi.AstBuilder,
  Tests.DX.Delphi.Support;

{ TTestAstModule }

procedure TTestAstModule.ModuleKindAndName;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst('unit Demo; interface implementation end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkUnit, LModule.Kind);
      Assert.AreEqual('Demo', LModule.Name);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstModule.UsesAreFlattened;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'uses System.SysUtils, System.Classes;'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual<NativeInt>(2, LModule.UsedUnits.Count);
      Assert.AreEqual('System.SysUtils', LModule.UsedUnits[0].Name);
      Assert.AreEqual('System.Classes', LModule.UsedUnits[1].Name);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstDeclarations }

procedure TTestAstDeclarations.ConstAndVarDeclarations;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'const A = 1;'#13#10+
      'var B: Integer = 5;'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual<NativeInt>(2, LModule.Declarations.Count);
      Assert.IsTrue(LModule.Declarations[0] is TDLConstDecl);
      Assert.IsNotNull(TDLConstDecl(LModule.Declarations[0]).Value);
      Assert.IsTrue(TDLConstDecl(LModule.Declarations[0]).Value
        is TDLNumberExpr);
      Assert.IsTrue(LModule.Declarations[1] is TDLVarDecl);
      Assert.AreEqual('Integer', TDLVarDecl(LModule.Declarations[1]).TypeName);
      Assert.IsNotNull(TDLVarDecl(LModule.Declarations[1]).Init);
      Assert.IsTrue(TDLVarDecl(LModule.Declarations[1]).Init is TDLNumberExpr);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstDeclarations.EnumAndClassTypes;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LTypeDecl: TDLTypeDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'type TDay = (Sun, Mon, Tue);'#13#10+
      '     TFoo = class(TObject)'#13#10+
      '       private'#13#10+
      '         FValue: Integer;'#13#10+
      '       public'#13#10+
      '         procedure DoIt;'#13#10+
      '     end;'#13#10+
      'implementation end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LTypeDecl := TDLTypeDecl(LModule.Declarations[0]);
      Assert.IsTrue(LTypeDecl.TypeDef is TDLEnumTypeDef);
      Assert.AreEqual<NativeInt>(3, TDLEnumTypeDef(LTypeDecl.TypeDef).Members.Count);
      LTypeDecl := TDLTypeDecl(LModule.Declarations[1]);
      Assert.IsTrue(LTypeDecl.TypeDef is TDLClassTypeDef);
      Assert.AreEqual('TObject', TDLClassTypeDef(LTypeDecl.TypeDef).Ancestor);
      // private/public markers + FValue field + DoIt method
      Assert.AreEqual<NativeInt>(4, TDLClassTypeDef(LTypeDecl.TypeDef).Members.Count);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstDeclarations.SymbolsAreRecorded;
var
  LDiagnostics: TDLDiagnostics;
  LBuilder: TDLDelphiAstBuilder;
  LCST: TDLCompilationUnit;
  LModule: TDLModule;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LCST := ParseSource(
      'unit U; interface'#13#10+
      'type TPoint = record X, Y: Integer; end;'#13#10+
      'const C = 1;'#13#10+
      'implementation end.', LDiagnostics);
    try
      LBuilder := TDLDelphiAstBuilder.Create(LDiagnostics);
      try
        LModule := LBuilder.Build(LCST);
        try
          Assert.IsTrue(LBuilder.Symbols.Contains('TPoint'));
          Assert.IsTrue(LBuilder.Symbols.Contains('C'));
          Assert.IsTrue(LBuilder.Symbols.Contains('X'));
          Assert.IsTrue(LBuilder.Symbols.Contains('U'));
        finally
          LModule.Free;
        end;
      finally
        LBuilder.Free;
      end;
    finally
      LCST.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestAstStatements }

procedure TTestAstStatements.MethodBodyStatements;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'implementation'#13#10+
      'procedure P;'#13#10+
      'var i: Integer;'#13#10+
      'begin'#13#10+
      '  i := 1;'#13#10+
      '  if i > 0 then'#13#10+
      '    i := i * 2;'#13#10+
      'end;'#13#10+
      'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      Assert.IsTrue(LProc.HasBody);
      Assert.AreEqual<NativeInt>(2, LProc.Body.Count);
      Assert.IsTrue(LProc.Body[0] is TDLAssignStmt);
      Assert.IsTrue(LProc.Body[1] is TDLIfStmt);
      Assert.IsTrue(TDLIfStmt(LProc.Body[1]).Condition is TDLBinaryExpr);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestAstStatements.AnonymousMethodLowering;
var
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LProc: TDLProcDecl;
  LAssign: TDLAssignStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(
      'unit U; interface'#13#10+
      'implementation'#13#10+
      'procedure P;'#13#10+
      'var F: TFunc<Integer, Integer>;'#13#10+
      'begin'#13#10+
      '  F := function(AX: Integer): Integer'#13#10+
      '  begin Result := AX + 1; end;'#13#10+
      'end;'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProc := TDLProcDecl(LModule.Declarations[0]);
      LAssign := TDLAssignStmt(LProc.Body[0]);
      Assert.IsTrue(LAssign.Value is TDLAnonMethodExpr);
      Assert.AreEqual(prFunction, TDLAnonMethodExpr(
        LAssign.Value).Kind);
      Assert.AreEqual('Integer', TDLAnonMethodExpr(
        LAssign.Value).ReturnType);
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAstModule);
  TDUnitX.RegisterTestFixture(TTestAstDeclarations);
  TDUnitX.RegisterTestFixture(TTestAstStatements);

end.
