/// <summary>
///   Tests.DX.Delphi.Modules — DUnitX coverage for module-level constructs:
///   packages, programs with parameters, libraries with exports/main blocks,
///   and units with multiple uses clauses.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Modules;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestModulePackages = class
  public
    [Test]
    procedure PackageWithRequiresAndContains;
  end;

  [TestFixture]
  TTestModulePrograms = class
  public
    [Test]
    procedure ProgramWithParameters;
    [Test]
    procedure ProgramWithAsmMainBlock;
    [Test]
    procedure ProgramWithVarSection;
  end;

  [TestFixture]
  TTestModuleLibraries = class
  public
    [Test]
    procedure LibraryWithExportsAndMainBlock;
  end;

  [TestFixture]
  TTestModuleUnits = class
  public
    [Test]
    procedure UnitWithBothUsesClauses;
    [Test]
    procedure UnitWithResourcestringAndThreadvar;
    [Test]
    procedure UnitWithUsesInFile;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestModulePackages }

procedure TTestModulePackages.PackageWithRequiresAndContains;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'package MyPkg;'#13#10+
      'requires rtl, vcl;'#13#10+
      'contains UnitA, UnitB in ''UnitB.pas'';'#13#10+
      'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkPackage, LUnit.ProgramKind);
      Assert.AreEqual('MyPkg', LUnit.Name.Name);
      Assert.IsNotNull(LUnit.RequiresClause);
      Assert.AreEqual(2, LUnit.RequiresClause.References.Count);
      Assert.IsNotNull(LUnit.ContainsClause);
      Assert.AreEqual(2, LUnit.ContainsClause.References.Count);
      Assert.AreEqual('UnitB', LUnit.ContainsClause.References[1].Name.Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestModulePrograms }

procedure TTestModulePrograms.ProgramWithParameters;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program Tool(input, output);'#13#10'begin end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkProgram, LUnit.ProgramKind);
      Assert.AreEqual(2, LUnit.ProgramParams.Count);
      Assert.AreEqual('input', LUnit.ProgramParams[0].Name);
      Assert.AreEqual('output', LUnit.ProgramParams[1].Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestModulePrograms.ProgramWithAsmMainBlock;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program AsmProg;'#13#10'asm'#13#10'  xor eax, eax'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsNotNull(LUnit.InitSection);
      Assert.IsTrue(LUnit.InitSection.Body is TDLAsmStmt);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestModulePrograms.ProgramWithVarSection;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'var'#13#10'  G: Integer;'#13#10'begin'#13#10'  G := 1;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(1, LUnit.Items.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLVarSection);
      Assert.IsNotNull(LUnit.InitSection);
      Assert.AreEqual(1, TDLCompoundStmt(
        LUnit.InitSection.Body).Statements.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestModuleLibraries }

procedure TTestModuleLibraries.LibraryWithExportsAndMainBlock;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'library MyLib;'#13#10+
      'exports Foo index 1, Bar name ''bar'';'#13#10+
      'begin'#13#10+
      '  Foo;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkLibrary, LUnit.ProgramKind);
      Assert.IsTrue(LUnit.Items[0] is TDLExportsClause);
      Assert.AreEqual(2, TDLExportsClause(LUnit.Items[0]).Items.Count);
      Assert.IsNotNull(LUnit.InitSection);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestModuleUnits }

procedure TTestModuleUnits.UnitWithBothUsesClauses;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'uses System.SysUtils;'#13#10+
      'implementation'#13#10'uses System.Math;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(2, LUnit.UsesClauses.Count);
      Assert.AreEqual('System.SysUtils', LUnit.UsesClauses[0].References[0].Name.Name);
      Assert.AreEqual('System.Math', LUnit.UsesClauses[1].References[0].Name.Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestModuleUnits.UnitWithResourcestringAndThreadvar;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'resourcestring'#13#10'  rsHello = ''Hello'';'#13#10+
      'threadvar'#13#10'  TLocal: Integer;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLResStringSection);
      Assert.AreEqual(1, TDLResStringSection(LUnit.Items[0]).Items.Count);
      Assert.IsTrue(LUnit.Items[1] is TDLVarSection);
      Assert.IsTrue(TDLVarSection(LUnit.Items[1]).IsThreadVar);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestModuleUnits.UnitWithUsesInFile;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'uses Helper in ''Helper.pas'';'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsNotNull(LUnit.UsesClauses[0].References[0].InFile);
      Assert.AreEqual('Helper.pas',
        TDLStringExpr(LUnit.UsesClauses[0].References[0].InFile).Value);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestModulePackages);
  TDUnitX.RegisterTestFixture(TTestModulePrograms);
  TDUnitX.RegisterTestFixture(TTestModuleLibraries);
  TDUnitX.RegisterTestFixture(TTestModuleUnits);

end.
