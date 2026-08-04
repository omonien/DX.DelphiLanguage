/// <summary>
///   Tests.DX.Delphi.Core — DUnitX tests for DX.Delphi.Core: keyword table,
///   source positions/spans, diagnostics and symbol table.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Core;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core;

type
  [TestFixture]
  TTestKeywords = class
  public
    [Test]
    procedure KeywordLookupIsCaseInsensitive;
    [Test]
    procedure NonKeywordReturnsNone;
    [Test]
    procedure AllTableEntriesRoundTrip;
  end;

  [TestFixture]
  TTestDiagnostics = class
  public
    [Test]
    procedure ErrorsSetHasErrors;
    [Test]
    procedure WarningsDoNotSetHasErrors;
    [Test]
    procedure ToStringContainsSeverity;
  end;

  [TestFixture]
  TTestSymbols = class
  public
    [Test]
    procedure AddAndFind;
    [Test]
    procedure DuplicateRaises;
  end;

  [TestFixture]
  TTestSourceSpan = class
  public
    [Test]
    procedure PositionsAreOneBasedLines;
    [Test]
    procedure EmptySpan;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestKeywords }

procedure TTestKeywords.KeywordLookupIsCaseInsensitive;
begin
  Assert.AreEqual(kwBegin, TDLKeywords.ToKeyword('begin'));
  Assert.AreEqual(kwBegin, TDLKeywords.ToKeyword('BEGIN'));
  Assert.AreEqual(kwBegin, TDLKeywords.ToKeyword('Begin'));
  Assert.AreEqual(kwClass, TDLKeywords.ToKeyword('class'));
  Assert.AreEqual(kwOperator, TDLKeywords.ToKeyword('operator'));
  Assert.AreEqual(kwOn, TDLKeywords.ToKeyword('on'));
  Assert.AreEqual(kwName, TDLKeywords.ToKeyword('name'));
end;

procedure TTestKeywords.NonKeywordReturnsNone;
begin
  Assert.AreEqual(kwNone, TDLKeywords.ToKeyword('Beginner'));
  Assert.AreEqual(kwNone, TDLKeywords.ToKeyword('classy'));
  Assert.AreEqual(kwNone, TDLKeywords.ToKeyword(''));
end;

procedure TTestKeywords.AllTableEntriesRoundTrip;
var
  LKeyword: TDLKeyword;
  LText: string;
begin
  for LKeyword := Low(TDLKeyword) to High(TDLKeyword) do
  begin
    if LKeyword = kwNone then
      Continue;
    LText := TDLKeywords.ToText(LKeyword);
    Assert.IsTrue(LText <> '', 'ToText(' + Ord(LKeyword).ToString + ') is empty');
    Assert.AreEqual(LKeyword, TDLKeywords.ToKeyword(LText),
      'Round-trip failed for ' + LText);
  end;
end;

{ TTestDiagnostics }

procedure TTestDiagnostics.ErrorsSetHasErrors;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    Assert.IsFalse(LDiagnostics.HasErrors);
    LDiagnostics.Error('T1', 'boom', TDLSourceSpan.Create(
      TDLSourcePos.Create(0, 1, 1), TDLSourcePos.Create(1, 1, 2)));
    Assert.IsTrue(LDiagnostics.HasErrors);
    Assert.AreEqual(1, LDiagnostics.Count);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestDiagnostics.WarningsDoNotSetHasErrors;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LDiagnostics.Warning('T2', 'careful', TDLSourceSpan.Create(
      TDLSourcePos.Create(0, 1, 1), TDLSourcePos.Create(1, 1, 2)));
    Assert.IsFalse(LDiagnostics.HasErrors);
    Assert.AreEqual(1, LDiagnostics.Count);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestDiagnostics.ToStringContainsSeverity;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LDiagnostics.Error('T3', 'message text', TDLSourceSpan.Create(
      TDLSourcePos.Create(0, 3, 5), TDLSourcePos.Create(2, 3, 7)));
    Assert.IsTrue(Pos('Error', LDiagnostics[0].ToString) > 0);
    Assert.IsTrue(Pos('T3', LDiagnostics[0].ToString) > 0);
    Assert.IsTrue(Pos('3:5', LDiagnostics[0].ToString) > 0);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestSymbols }

procedure TTestSymbols.AddAndFind;
var
  LTable: TDLSymbolTable;
  LSymbol: TDLSymbol;
begin
  LTable := TDLSymbolTable.Create;
  try
    LTable.Add(TDLSymbol.Create('Foo', skType, TDLSourceSpan.Create(
      TDLSourcePos.Create(0, 1, 1), TDLSourcePos.Create(3, 1, 4))));
    LSymbol := LTable.Find('Foo');
    Assert.IsNotNull(LSymbol);
    Assert.AreEqual('Foo', LSymbol.Name);
    Assert.AreEqual(skType, LSymbol.Kind);
    Assert.IsTrue(LTable.Contains('Foo'));
    Assert.AreEqual(1, LTable.Count);
  finally
    LTable.Free;
  end;
end;

procedure TTestSymbols.DuplicateRaises;
var
  LTable: TDLSymbolTable;
begin
  LTable := TDLSymbolTable.Create;
  try
    LTable.Add(TDLSymbol.Create('Dup', skVar, TDLSourceSpan.Create(
      TDLSourcePos.Create(0, 1, 1), TDLSourcePos.Create(1, 1, 2))));
    // Flat table keeps the first occurrence; the duplicate is ignored.
    LTable.Add(TDLSymbol.Create('Dup', skVar, TDLSourceSpan.Create(
      TDLSourcePos.Create(0, 1, 1), TDLSourcePos.Create(1, 1, 2))));
    Assert.AreEqual(1, LTable.Count);
  finally
    LTable.Free;
  end;
end;

{ TTestSourceSpan }

procedure TTestSourceSpan.PositionsAreOneBasedLines;
var
  LPos: TDLSourcePos;
begin
  LPos := TDLSourcePos.Create(42, 7, 3);
  Assert.AreEqual(42, LPos.Offset);
  Assert.AreEqual(7, LPos.Line);
  Assert.AreEqual(3, LPos.Column);
end;

procedure TTestSourceSpan.EmptySpan;
begin
  Assert.IsTrue(TDLSourceSpan.Create(TDLSourcePos.Create(5, 1, 6),
    TDLSourcePos.Create(5, 1, 6)).IsEmpty);
  Assert.IsFalse(TDLSourceSpan.Create(TDLSourcePos.Create(0, 1, 1),
    TDLSourcePos.Create(3, 1, 4)).IsEmpty);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestKeywords);
  TDUnitX.RegisterTestFixture(TTestDiagnostics);
  TDUnitX.RegisterTestFixture(TTestSymbols);
  TDUnitX.RegisterTestFixture(TTestSourceSpan);

end.
