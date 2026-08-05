/// <summary>
///   Tests.DX.Delphi.Parser — DUnitX tests for the CST parser: unit
///   structure, declarations, types, class members, statements, expressions
///   and diagnostics.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Parser;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestParserUnits = class
  public
    [Test]
    procedure ParseProgram;
    [Test]
    procedure ParseUnitWithUses;
    [Test]
    procedure ParseLibrary;
    [Test]
    procedure DottedUsesNames;
  end;

  [TestFixture]
  TTestParserSections = class
  public
    [Test]
    procedure ConstAndVarSections;
    [Test]
    procedure TypeSections;
    [Test]
    procedure ThreadVarSection;
    [Test]
    procedure LabelAndExportsSections;
  end;

  [TestFixture]
  TTestParserTypes = class
  public
    [Test]
    procedure ClassWithMembers;
    [Test]
    procedure RecordWithVariantPart;
    [Test]
    procedure ClassHelperAndRecordHelper;
    [Test]
    procedure GenericTypeDeclaration;
    [Test]
    procedure ProceduralTypes;
  end;

  [TestFixture]
  TTestParserStatements = class
  public
    [Test]
    procedure CompoundAndIf;
    [Test]
    procedure CaseStatement;
    [Test]
    procedure ForLoops;
    [Test]
    procedure TryExceptWithOnHandlers;
    [Test]
    procedure WithAndRepeat;
  end;

  [TestFixture]
  TTestParserExpressions = class
  public
    [Test]
    procedure Precedence;
    [Test]
    procedure GenericInstantiation;
    [Test]
    procedure SetConstructors;
    [Test]
    procedure AnonymousMethods;
    [Test]
    procedure CallsAndIndexing;
  end;

  [TestFixture]
  TTestParserErrors = class
  public
    [Test]
    procedure ValidSourceHasNoDiagnostics;
    [Test]
    procedure MalformedSourceIsTolerated;
    [Test]
    procedure CstNodesCarrySpans;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestParserUnits }

procedure TTestParserUnits.ParseProgram;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource('program Hello; begin WriteLn(''hi''); end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkProgram, LUnit.ProgramKind);
      Assert.AreEqual('Hello', LUnit.Name.Name);
      Assert.IsNotNull(LUnit.InitSection);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserUnits.ParseUnitWithUses;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U1;' + #13#10 +
      'interface' + #13#10 +
      'uses System.SysUtils, System.Classes;' + #13#10 +
      'const X = 1;' + #13#10 +
      'implementation' + #13#10 +
      'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkUnit, LUnit.ProgramKind);
      Assert.AreEqual(1, LUnit.UsesClauses.Count);
      Assert.AreEqual(2, LUnit.UsesClauses[0].References.Count);
      Assert.AreEqual('System.SysUtils', LUnit.UsesClauses[0].References[0].Name.Name);
      Assert.AreEqual(1, LUnit.Items.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLConstSection);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserUnits.ParseLibrary;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource('library MyLib; exports Foo; end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(pkLibrary, LUnit.ProgramKind);
      Assert.AreEqual(1, LUnit.Items.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLExportsClause);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserUnits.DottedUsesNames;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'uses A.B.C.D;'#13#10'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual('A.B.C.D', LUnit.UsesClauses[0].References[0].Name.Name);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserSections }

procedure TTestParserSections.ConstAndVarSections;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LConst: TDLConstDecl;
  LVar: TDLVarDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'const A = 1; B = ''x'';'#13#10+
      'var i, j: Integer; s: string = ''init'';'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLConstSection);
      Assert.AreEqual(2, TDLConstSection(LUnit.Items[0]).Items.Count);
      LConst := TDLConstDecl(TDLConstSection(LUnit.Items[0]).Items[0]);
      Assert.AreEqual('A', LConst.Names[0].Name);
      Assert.IsTrue(LUnit.Items[1] is TDLVarSection);
      Assert.AreEqual(2, TDLVarSection(LUnit.Items[1]).Items.Count);
      LVar := TDLVarDecl(TDLVarSection(LUnit.Items[1]).Items[0]);
      Assert.AreEqual(2, LVar.Names.Count);
      Assert.AreEqual('Integer', TDLNamedType(LVar.TypeExpr).Name.Name);
      Assert.IsNotNull(TDLVarDecl(
        TDLVarSection(LUnit.Items[1]).Items[1]).Init);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserSections.TypeSections;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSection: TDLTypeSection;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'type TInt = Integer; TArr = array[0..9] of Integer;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSection := TDLTypeSection(LUnit.Items[0]);
      Assert.AreEqual(2, LSection.Items.Count);
      Assert.AreEqual('TInt', TDLTypeDecl(LSection.Items[0]).Name.Name);
      Assert.IsTrue(TDLTypeDecl(LSection.Items[1]).TypeExpr is TDLStaticArrayType);
      Assert.AreEqual(1, TDLStaticArrayType(
        TDLTypeDecl(LSection.Items[1]).TypeExpr).Bounds.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserSections.ThreadVarSection;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'threadvar t: Integer;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLVarSection);
      Assert.IsTrue(TDLVarSection(LUnit.Items[0]).IsThreadVar);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserSections.LabelAndExportsSections;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'library L;'#13#10'exports Foo index 1 name ''x'';'#13#10+
      'begin end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.IsTrue(LUnit.Items[0] is TDLExportsClause);
      Assert.AreEqual('Foo', TDLExportsClause(LUnit.Items[0]).Items[0].Name.Name);
      Assert.IsNotNull(TDLExportsClause(LUnit.Items[0]).Items[0].Index);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserTypes }

procedure TTestParserTypes.ClassWithMembers;
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
      'unit U;'#13#10'interface'#13#10+
      'type TFoo = class(TObject)'#13#10+
      '  private'#13#10+
      '    FValue: Integer;'#13#10+
      '  public'#13#10+
      '    constructor Create(AValue: Integer);'#13#10+
      '    procedure DoWork; virtual;'#13#10+
      '    property Value: Integer read FValue write FValue;'#13#10+
      '  end;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsNotNull(LClass.BaseType);
      LFoundMethod := False;
      for LMember in LClass.Members do
        if (LMember is TDLMethodDecl) and
           (TDLMethodDecl(LMember).Name.Name = 'DoWork') then
        begin
          LFoundMethod := True;
          Assert.AreEqual(1, TDLMethodDecl(LMember).Directives.Count);
        end;
      Assert.IsTrue(LFoundMethod, 'DoWork method not found');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserTypes.RecordWithVariantPart;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LRecord: TDLRecordType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'type TV = record'#13#10+
      '  case Kind: Integer of'#13#10+
      '    0: (I: Integer);'#13#10+
      '    1: (S: string);'#13#10+
      '  end;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LRecord := TDLRecordType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsNotNull(LRecord.VariantPart);
      Assert.AreEqual('Kind', LRecord.VariantPart.Tag.Name);
      Assert.AreEqual(2, LRecord.VariantPart.Variants.Count);
      Assert.AreEqual(1, LRecord.VariantPart.Variants[0].Fields.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserTypes.ClassHelperAndRecordHelper;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LHelper: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'type TH = class helper for TObject'#13#10+
      '  function Foo: Integer;'#13#10+
      'end;'#13#10+
      '     RH = record helper for TPoint'#13#10+
      '  function Bar: Integer;'#13#10+
      'end;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LHelper := TDLClassType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LHelper.IsHelper);
      Assert.IsNotNull(LHelper.HelperFor);
      LHelper := TDLClassType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[1]).TypeExpr);
      Assert.IsTrue(LHelper.IsHelper);
      Assert.AreEqual(1, LHelper.Members.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserTypes.GenericTypeDeclaration;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'type TList<T> = class'#13#10+
      '  private'#13#10+
      '    FItems: TArray<T>;'#13#10+
      '  public'#13#10+
      '    procedure Add(const AItem: T);'#13#10+
      '  end;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      // 4 members: private/public visibility markers + FItems field + Add method
      Assert.AreEqual(4, LClass.Members.Count);
      Assert.IsTrue(LClass.Members[1] is TDLFieldDecl);
      Assert.IsTrue(LClass.Members[3] is TDLMethodDecl);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserTypes.ProceduralTypes;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LProcType: TDLProceduralType;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'type TCallback = reference to function(AX: Integer): Integer;'#13#10+
      '     TNotify = procedure of object;'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LProcType := TDLProceduralType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      Assert.IsTrue(LProcType.IsReferenceTo);
      Assert.AreEqual(prFunction, LProcType.Kind);
      Assert.AreEqual(1, LProcType.Params.Count);
      LProcType := TDLProceduralType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[1]).TypeExpr);
      Assert.IsTrue(LProcType.IsOfObject);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserStatements }

procedure TTestParserStatements.CompoundAndIf;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  if x > 1 then y := 1 else y := 2;'#13#10+
      '  begin z := 3; end;'#13#10+
      'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.AreEqual(2, LBody.Statements.Count);
      Assert.IsTrue(LBody.Statements[0] is TDLIfStmt);
      Assert.IsNotNull(TDLIfStmt(LBody.Statements[0]).ElseBranch);
      Assert.IsTrue(LBody.Statements[1] is TDLCompoundStmt);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserStatements.CaseStatement;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LCase: TDLCaseStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'var x: Integer;'#13#10'begin'#13#10+
      '  case x of'#13#10+
      '    0: y := 1;'#13#10+
      '    1, 2: y := 2;'#13#10+
      '    3..5: y := 3;'#13#10+
      '  else y := 0;'#13#10+
      '  end;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LCase := TDLCaseStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      Assert.AreEqual(3, LCase.Selectors.Count);
      Assert.AreEqual(2, LCase.Selectors[1].Labels.Count);
      Assert.IsNotNull(LCase.ElseBranch);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserStatements.ForLoops;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'var a: array of Integer; i: Integer;'#13#10'begin'#13#10+
      '  for i := 0 to 10 do a[i] := i;'#13#10+
      '  for i := 10 downto 0 do a[i] := i;'#13#10+
      '  for var x in a do y := x;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.IsTrue(LBody.Statements[0] is TDLForStmt);
      Assert.AreEqual(kwTo, TDLForStmt(LBody.Statements[0]).Direction);
      Assert.IsNotNull(TDLForStmt(LBody.Statements[0]).StartExpr);
      Assert.AreEqual(kwDownTo, TDLForStmt(LBody.Statements[1]).Direction);
      Assert.IsTrue(TDLForStmt(LBody.Statements[2]).IsInlineVar);
      Assert.AreEqual(kwIn, TDLForStmt(LBody.Statements[2]).Direction);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserStatements.TryExceptWithOnHandlers;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LTry: TDLTryStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  try'#13#10+
      '    Foo;'#13#10+
      '  except'#13#10+
      '    on E: Exception do Bar;'#13#10+
      '  else'#13#10+
      '    Baz;'#13#10+
      '  end;'#13#10+
      '  try'#13#10+
      '    Foo;'#13#10+
      '  finally'#13#10+
      '    Bar;'#13#10+
      '  end;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LTry := TDLTryStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      Assert.IsTrue(LTry.IsExcept);
      Assert.AreEqual(1, LTry.OnHandlers.Count);
      Assert.AreEqual('E', LTry.OnHandlers[0].VarName.Name);
      Assert.AreEqual('Exception', LTry.OnHandlers[0].TypeName.Name);
      Assert.IsNotNull(LTry.ElseBranch);
      LTry := TDLTryStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[1]);
      Assert.IsFalse(LTry.IsExcept);
      Assert.IsNotNull(LTry.FinallyBody);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserStatements.WithAndRepeat;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LBody: TDLCompoundStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  with A, B do Foo;'#13#10+
      '  repeat'#13#10+
      '    Dec(i);'#13#10+
      '  until i = 0;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LBody := TDLCompoundStmt(LUnit.InitSection.Body);
      Assert.IsTrue(LBody.Statements[0] is TDLWithStmt);
      Assert.AreEqual(2, TDLWithStmt(LBody.Statements[0]).Expressions.Count);
      Assert.IsTrue(LBody.Statements[1] is TDLRepeatStmt);
      Assert.IsNotNull(TDLRepeatStmt(LBody.Statements[1]).Condition);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserExpressions }

procedure TTestParserExpressions.Precedence;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LExpr: TDLExpr;
  LAssign: TDLAssignmentStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  x := 1 + 2 * 3;'#13#10+
      '  x := (1 + 2) * 3;'#13#10+
      '  if a and b or c then ;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      // 1 + 2 * 3 -> + (1, * (2,3))
      Assert.IsTrue(LAssign.Value is TDLBinaryExpr);
      Assert.AreEqual(boAdd, TDLBinaryExpr(LAssign.Value).Operator);
      Assert.IsTrue(TDLBinaryExpr(LAssign.Value).Right is TDLBinaryExpr);
      Assert.AreEqual(boMultiply,
        TDLBinaryExpr(TDLBinaryExpr(LAssign.Value).Right).Operator);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExpressions.GenericInstantiation;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LAssign: TDLAssignmentStmt;
  LMember: TDLMemberExpr;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  L := TList<Integer>.Create;'#13#10+
      '  x := a < b;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      // TList<Integer>.Create -> member(Create, generic(TList, [Integer]))
      Assert.IsTrue(LAssign.Value is TDLMemberExpr);
      LMember := TDLMemberExpr(LAssign.Value);
      Assert.IsTrue(LMember.Target is TDLGenericInstantiationExpr);
      Assert.AreEqual(1, TDLGenericInstantiationExpr(
        LMember.Target).TypeArgs.Count);
      // a < b must remain a comparison
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[1]);
      Assert.IsTrue(LAssign.Value is TDLBinaryExpr);
      Assert.AreEqual(boLess, TDLBinaryExpr(LAssign.Value).Operator);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExpressions.SetConstructors;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LAssign: TDLAssignmentStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  x := [1, 2, 3];'#13#10+
      '  y := [Monday..Friday];'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      Assert.IsTrue(LAssign.Value is TDLSetExpr);
      Assert.AreEqual(3, TDLSetExpr(LAssign.Value).Elements.Count);
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[1]);
      Assert.IsTrue(LAssign.Value is TDLSetExpr);
      Assert.IsTrue(TDLSetExpr(LAssign.Value).IsRanges[0]);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExpressions.AnonymousMethods;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LAssign: TDLAssignmentStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  F := function(AX: Integer): Integer'#13#10+
      '  begin'#13#10+
      '    Result := AX * 2;'#13#10+
      '  end;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      Assert.IsTrue(LAssign.Value is TDLAnonymousMethodExpr);
      Assert.AreEqual(1, TDLAnonymousMethodExpr(
        LAssign.Value).Params.Count);
      Assert.IsNotNull(TDLAnonymousMethodExpr(
        LAssign.Value).Body);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserExpressions.CallsAndIndexing;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LStmt: TDLExprStmt;
  LAssign: TDLAssignmentStmt;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'program P;'#13#10'begin'#13#10+
      '  Foo.Bar(1, 2);'#13#10+
      '  x := A[1, 2];'#13#10+
      '  y := @Foo;'#13#10+
      '  z := not b;'#13#10'end.',
      LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LStmt := TDLExprStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[0]);
      Assert.IsTrue(LStmt.Expression is TDLCallExpr);
      Assert.IsTrue(TDLCallExpr(LStmt.Expression).Callee is TDLMemberExpr);
      Assert.AreEqual(2, TDLCallExpr(LStmt.Expression).Args.Count);
      LAssign := TDLAssignmentStmt(TDLCompoundStmt(
        LUnit.InitSection.Body).Statements[1]);
      Assert.IsTrue(LAssign.Value is TDLIndexExpr);
      Assert.AreEqual(2, TDLIndexExpr(LAssign.Value).Indices.Count);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserErrors }

procedure TTestParserErrors.ValidSourceHasNoDiagnostics;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'uses System.SysUtils;'#13#10+
      'type TFoo = class'#13#10+
      '  procedure P(A: Integer);'#13#10+
      'end;'#13#10'implementation'#13#10+
      'procedure TFoo.P(A: Integer);'#13#10'begin end;'#13#10+
      'end.', LDiagnostics).Free;
    Assert.AreEqual(0, LDiagnostics.Count);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserErrors.MalformedSourceIsTolerated;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // The parser must not crash and must produce diagnostics + a tree.
    LUnit := ParseSource('unit Broken; interface type = ; implementation',
      LDiagnostics);
    try
      Assert.IsTrue(LDiagnostics.Count > 0);
      Assert.IsNotNull(LUnit);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserErrors.CstNodesCarrySpans;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource('program P; begin end.', LDiagnostics);
    try
      Assert.IsFalse(LUnit.Span.IsEmpty);
      Assert.IsTrue(LUnit.Span.Start.Line >= 1);
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParserUnits);
  TDUnitX.RegisterTestFixture(TTestParserSections);
  TDUnitX.RegisterTestFixture(TTestParserTypes);
  TDUnitX.RegisterTestFixture(TTestParserStatements);
  TDUnitX.RegisterTestFixture(TTestParserExpressions);
  TDUnitX.RegisterTestFixture(TTestParserErrors);

end.
