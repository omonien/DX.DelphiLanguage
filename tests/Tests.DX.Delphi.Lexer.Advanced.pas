/// <summary>
///   Tests.DX.Delphi.Lexer.Advanced — additional DUnitX lexer coverage:
///   operators, directives, nested comment styles, line counting, error
///   codes and multiline-string edge cases.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Lexer.Advanced;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.Lexer;

type
  [TestFixture]
  TTestLexerOperators = class
  public
    [Test]
    procedure TwoCharOperators;
    [Test]
    procedure SubrangeOperator;
    [Test]
    procedure NotPowerOperator;
  end;

  [TestFixture]
  TTestLexerComments = class
  public
    [Test]
    procedure ParenStyleComments;
    [Test]
    procedure NestedParenComments;
    [Test]
    procedure UnterminatedBlockComment;
    [Test]
    procedure UnterminatedDirective;
  end;

  [TestFixture]
  TTestLexerLines = class
  public
    [Test]
    procedure LineAndColumnTracking;
    [Test]
    procedure CrLfAndLfMix;
  end;

  [TestFixture]
  TTestLexerNumbersAdvanced = class
  public
    [Test]
    procedure FloatExponentForms;
    [Test]
    procedure HexUppercase;
    [Test]
    procedure InvalidHexReportsError;
    [Test]
    procedure InvalidBinaryReportsError;
  end;

  [TestFixture]
  TTestLexerCharCodesAdvanced = class
  public
    [Test]
    procedure CharCodeOutOfRange;
    [Test]
    procedure CharCodeNoDigits;
  end;

  [TestFixture]
  TTestLexerMultilineAdvanced = class
  public
    [Test]
    procedure SixQuoteRun;
    [Test]
    procedure OddQuoteRunReportsError;
    [Test]
    procedure UnterminatedMultilineReportsError;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

function TokenizeToArray(const ASource: string; ADiagnostics: TDLDiagnostics):
  TArray<TDLToken>;
var
  LTokens: TObjectList<TDLToken>;
  i: Integer;
  LCopy: TDLToken;
begin
  LTokens := LexSource(ASource, ADiagnostics);
  try
    SetLength(Result, LTokens.Count);
    for i := 0 to LTokens.Count - 1 do
    begin
      LCopy := TDLToken.Create(LTokens[i].Kind, LTokens[i].Text,
        LTokens[i].Span);
      LCopy.Value := LTokens[i].Value;
      LCopy.IntegerValue := LTokens[i].IntegerValue;
      LCopy.FloatValue := LTokens[i].FloatValue;
      LCopy.LeadingTrivia.AddRange(LTokens[i].LeadingTrivia);
      Result[i] := LCopy;
    end;
  finally
    LTokens.Free;
  end;
end;

{ TTestLexerOperators }

procedure TTestLexerOperators.TwoCharOperators;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('a := b; c <= d; e >= f; g <> h;', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(':=', LTokens[1].Text);
    Assert.AreEqual('<=', LTokens[5].Text);
    Assert.AreEqual('>=', LTokens[9].Text);
    Assert.AreEqual('<>', LTokens[13].Text);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerOperators.SubrangeOperator;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('0..9', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(4, Length(LTokens)); // 0, '..', 9, EOF
    Assert.AreEqual('..', LTokens[1].Text);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerOperators.NotPowerOperator;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  // '**' is NOT a Delphi operator; it lexes as two '*' tokens.
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('2 ** 3', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual('*', LTokens[1].Text);
    Assert.AreEqual('*', LTokens[2].Text);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerComments }

procedure TTestLexerComments.ParenStyleComments;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('(* a comment *) x', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(2, Length(LTokens));
    Assert.AreEqual(2, LTokens[0].LeadingTrivia.Count);
    Assert.AreEqual(trBlockComment, LTokens[0].LeadingTrivia[0].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerComments.NestedParenComments;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('(* outer (* inner *) done *) x', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(2, Length(LTokens));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerComments.UnterminatedBlockComment;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('{ never closed', LDiagnostics).Free;
    Assert.AreEqual('DLX-02', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerComments.UnterminatedDirective;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('{$IFDEF DEBUG', LDiagnostics).Free;
    Assert.AreEqual('DLX-03', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerLines }

procedure TTestLexerLines.LineAndColumnTracking;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('one'#13#10'two'#13#10'three', LDiagnostics);
    Assert.AreEqual('one', LTokens[0].Text);
    Assert.AreEqual(1, LTokens[0].Span.Start.Line);
    Assert.AreEqual(1, LTokens[0].Span.Start.Column);
    Assert.AreEqual('two', LTokens[1].Text);
    Assert.AreEqual(2, LTokens[1].Span.Start.Line);
    Assert.AreEqual(1, LTokens[1].Span.Start.Column);
    Assert.AreEqual('three', LTokens[2].Text);
    Assert.AreEqual(3, LTokens[2].Span.Start.Line);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerLines.CrLfAndLfMix;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('a'#10'b'#13#10'c'#10'd', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(1, LTokens[0].Span.Start.Line);
    Assert.AreEqual(2, LTokens[1].Span.Start.Line);
    Assert.AreEqual(3, LTokens[2].Span.Start.Line);
    Assert.AreEqual(4, LTokens[3].Span.Start.Line);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerNumbersAdvanced }

procedure TTestLexerNumbersAdvanced.FloatExponentForms;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('1e3 2.5E2 0.5', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(tkFloat, LTokens[0].Kind);
    Assert.AreEqual<Double>(1000, LTokens[0].FloatValue);
    Assert.AreEqual<Double>(250, LTokens[1].FloatValue);
    Assert.AreEqual<Double>(0.5, LTokens[2].FloatValue);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbersAdvanced.HexUppercase;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('$ABCDEF', LDiagnostics);
    Assert.AreEqual<Int64>($ABCDEF, LTokens[0].IntegerValue);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbersAdvanced.InvalidHexReportsError;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('$GG', LDiagnostics).Free;
    Assert.AreEqual('DLX-04', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbersAdvanced.InvalidBinaryReportsError;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // Lenient lexing: '%10' lexes as a binary literal, '2' as a separate
    // integer; no diagnostic is produced.
    LTokens := TokenizeToArray('%102', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual<Int64>(2, LTokens[0].IntegerValue);
    Assert.AreEqual(tkInteger, LTokens[1].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerCharCodesAdvanced }

procedure TTestLexerCharCodesAdvanced.CharCodeOutOfRange;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('#$10000', LDiagnostics).Free;
    Assert.AreEqual('DLX-11', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerCharCodesAdvanced.CharCodeNoDigits;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('#x', LDiagnostics).Free;
    Assert.AreEqual('DLX-10', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerMultilineAdvanced }

procedure TTestLexerMultilineAdvanced.SixQuoteRun;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
  LSource: string;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // ''' + a + '''''' (6 quotes = 3 literal) + b + '''
    LSource := StringOfChar('''', 3) + 'a' + StringOfChar('''', 6) + 'b' +
      StringOfChar('''', 3);
    LTokens := TokenizeToArray(LSource, LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual('a' + StringOfChar('''', 3) + 'b', LTokens[0].Value);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerMultilineAdvanced.OddQuoteRunReportsError;
var
  LDiagnostics: TDLDiagnostics;
  LSource: string;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // a run of 5 quotes is invalid (odd, > 3)
    LSource := StringOfChar('''', 3) + 'a' + StringOfChar('''', 5) + 'b' +
      StringOfChar('''', 3);
    LexSource(LSource, LDiagnostics).Free;
    Assert.AreEqual('DLX-09', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerMultilineAdvanced.UnterminatedMultilineReportsError;
var
  LDiagnostics: TDLDiagnostics;
  LSource: string;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LSource := StringOfChar('''', 3) + 'never closed';
    LexSource(LSource, LDiagnostics).Free;
    Assert.AreEqual('DLX-09', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLexerOperators);
  TDUnitX.RegisterTestFixture(TTestLexerComments);
  TDUnitX.RegisterTestFixture(TTestLexerLines);
  TDUnitX.RegisterTestFixture(TTestLexerNumbersAdvanced);
  TDUnitX.RegisterTestFixture(TTestLexerCharCodesAdvanced);
  TDUnitX.RegisterTestFixture(TTestLexerMultilineAdvanced);

end.
