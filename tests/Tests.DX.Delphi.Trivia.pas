/// <summary>
///   Tests.DX.Delphi.Trivia — DUnitX coverage for trivia preservation on CST
///   nodes: comments and directives survive lexing and are attached to the
///   nodes that own them.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Trivia;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestCstTrivia = class
  public
    [Test]
    procedure ConstCarriesLeadingComment;
    [Test]
    procedure DirectiveBeforeSectionIsTrivia;
    [Test]
    procedure TriviaDoesNotAffectStructure;
    [Test]
    procedure CommentsInsideClassBody;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestCstTrivia }

procedure TTestCstTrivia.ConstCarriesLeadingComment;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LConst: TDLConstDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'const'#13#10+
      '  { documented constant }'#13#10+
      '  A = 1;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LConst := TDLConstSection(LUnit.Items[0]).Items[0];
      Assert.IsTrue(LConst.TriviaCount > 0,
        'const should carry trivia');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestCstTrivia.DirectiveBeforeSectionIsTrivia;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LSection: TDLTypeSection;
  LFoundDirective: Boolean;
  LTrivia: TDLTrivia;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10+
      '{$IFDEF FOO}'#13#10+
      'type T = Integer;'#13#10+
      'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LSection := TDLTypeSection(LUnit.Items[0]);
      LFoundDirective := False;
      for LTrivia in LSection.LeadingTrivia do
        if LTrivia.Kind = trDirective then
          LFoundDirective := True;
      Assert.IsTrue(LFoundDirective, 'directive trivia missing');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestCstTrivia.TriviaDoesNotAffectStructure;
var
  LDiagnostics: TDLDiagnostics;
  LUnitWithComments: TDLCompilationUnit;
  LUnitPlain: TDLCompilationUnit;
  LWithCount: Integer;
  LPlainCount: Integer;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnitWithComments := ParseSource(
      'unit U;'#13#10'interface'#13#10'const'#13#10+
      '  { c } A = 1;'#13#10+
      '  // more'#13#10+
      '  B = 2;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      LUnitPlain := ParseSource(
        'unit U;'#13#10'interface'#13#10'const'#13#10+
        '  A = 1;'#13#10+
        '  B = 2;'#13#10'implementation'#13#10'end.', LDiagnostics);
      try
        LWithCount := TDLConstSection(
          LUnitWithComments.Items[0]).Items.Count;
        LPlainCount := TDLConstSection(LUnitPlain.Items[0]).Items.Count;
        Assert.AreEqual(LPlainCount, LWithCount);
      finally
        LUnitPlain.Free;
      end;
    finally
      LUnitWithComments.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestCstTrivia.CommentsInsideClassBody;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
  LClass: TDLClassType;
  LMethod: TDLMethodDecl;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LUnit := ParseSource(
      'unit U;'#13#10'interface'#13#10'type'#13#10+
      '  TFoo = class'#13#10+
      '    { the workhorse }'#13#10+
      '    procedure DoWork;'#13#10+
      '  end;'#13#10'implementation'#13#10'end.', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      LClass := TDLClassType(
        TDLTypeDecl(TDLTypeSection(LUnit.Items[0]).Items[0]).TypeExpr);
      LMethod := TDLMethodDecl(LClass.Members[0]);
      Assert.IsTrue(LMethod.TriviaCount > 0,
        'method should carry the comment as trivia');
    finally
      LUnit.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCstTrivia);

end.
