/// <summary>
///   Tests.DX.Delphi.Lexer — DUnitX tests for the tokenizer: identifiers,
///   keywords, numeric literals, strings (incl. multiline), char codes,
///   comments/directives and error tolerance.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Lexer;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.Lexer;

type
  [TestFixture]
  TTestLexerBasics = class
  public
    [Test]
    procedure EmptySourceYieldsEofOnly;
    [Test]
    procedure IdentifiersAndKeywords;
    [Test]
    procedure EscapedIdentifiers;
    [Test]
    procedure UnicodeIdentifiers;
  end;

  [TestFixture]
  TTestLexerNumbers = class
  public
    [Test]
    procedure DecimalIntegers;
    [Test]
    procedure HexAndBinary;
    [Test]
    procedure UnderscoreSeparators;
    [Test]
    procedure Floats;
    [Test]
    procedure DigitSeparatorsInFloats;
  end;

  [TestFixture]
  TTestLexerStrings = class
  public
    [Test]
    procedure SingleQuotedWithEscapes;
    [Test]
    procedure CharCodeSequence;
    [Test]
    procedure MultilineString;
    [Test]
    procedure MultilineStringQuoteRun;
    [Test]
    procedure DigitSeparatorsInCharCodes;
  end;

  [TestFixture]
  TTestLexerTrivia = class
  public
    [Test]
    procedure LineCommentAttachedToNextToken;
    [Test]
    procedure NestedBlockComments;
    [Test]
    procedure DirectiveIsTrivia;
  end;

  [TestFixture]
  TTestLexerErrors = class
  public
    [Test]
    procedure UnterminatedStringReportsError;
    [Test]
    procedure UnknownCharacterIsTolerated;
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

function FindToken(const ATokens: TArray<TDLToken>; AKind: TDLTokenKind;
  const AText: string): TDLToken;
var
  LToken: TDLToken;
begin
  Result := nil;
  for LToken in ATokens do
    if (LToken.Kind = AKind) and (LToken.Text = AText) then
      Exit(LToken);
end;

{ TTestLexerBasics }

procedure TTestLexerBasics.EmptySourceYieldsEofOnly;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('', LDiagnostics);
    Assert.AreEqual<NativeInt>(1, Length(LTokens));
    Assert.AreEqual(tkEOF, LTokens[0].Kind);
    Assert.AreEqual(0, LDiagnostics.Count);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerBasics.IdentifiersAndKeywords;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('alpha beta12 begin', LDiagnostics);
    Assert.AreEqual(tkIdentifier, LTokens[0].Kind);
    Assert.AreEqual('alpha', LTokens[0].Value);
    Assert.AreEqual(tkIdentifier, LTokens[1].Kind);
    Assert.AreEqual('beta12', LTokens[1].Value);
    Assert.AreEqual(tkKeyword, LTokens[2].Kind);
    Assert.AreEqual('begin', LTokens[2].Text);
    Assert.AreEqual(tkEOF, LTokens[3].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerBasics.EscapedIdentifiers;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
  LToken: TDLToken;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('&type &begin &End', LDiagnostics);
    LToken := FindToken(LTokens, tkIdentifier, '&type');
    Assert.IsNotNull(LToken);
    Assert.AreEqual('type', LToken.Value);
    LToken := FindToken(LTokens, tkIdentifier, '&begin');
    Assert.IsNotNull(LToken);
    LToken := FindToken(LTokens, tkIdentifier, '&End');
    Assert.IsNotNull(LToken);
    Assert.AreEqual('End', LToken.Value);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerBasics.UnicodeIdentifiers;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray(#$00C4#$00C4'pfel g'#$00FC'ltig', LDiagnostics);
    Assert.AreEqual(tkIdentifier, LTokens[0].Kind);
    Assert.AreEqual('g'#$00FC'ltig', LTokens[1].Value);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerNumbers }

procedure TTestLexerNumbers.DecimalIntegers;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('0 42 123456789', LDiagnostics);
    Assert.AreEqual(tkInteger, LTokens[0].Kind);
    Assert.AreEqual<Int64>(0, LTokens[0].IntegerValue);
    Assert.AreEqual<Int64>(42, LTokens[1].IntegerValue);
    Assert.AreEqual<Int64>(123456789, LTokens[2].IntegerValue);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbers.HexAndBinary;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('$FF %1010 $1A', LDiagnostics);
    Assert.AreEqual<Int64>(255, LTokens[0].IntegerValue);
    Assert.AreEqual<Int64>(10, LTokens[1].IntegerValue);
    Assert.AreEqual<Int64>(26, LTokens[2].IntegerValue);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbers.UnderscoreSeparators;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('1_000_000 $FF_FF %1010_0101', LDiagnostics);
    Assert.AreEqual<Int64>(1000000, LTokens[0].IntegerValue);
    Assert.AreEqual<Int64>($FFFF, LTokens[1].IntegerValue);
    Assert.AreEqual<Int64>(165, LTokens[2].IntegerValue);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbers.Floats;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('3.14 1.5e10 2E-3', LDiagnostics);
    Assert.AreEqual(tkFloat, LTokens[0].Kind);
    Assert.AreEqual<Double>(3.14, LTokens[0].FloatValue);
    Assert.AreEqual(tkFloat, LTokens[1].Kind);
    Assert.AreEqual<Double>(1.5e10, LTokens[1].FloatValue);
    Assert.AreEqual(tkFloat, LTokens[2].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerNumbers.DigitSeparatorsInFloats;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  // Delphi 11 ignores '_' inside a numeric literal, including the fraction
  // and the exponent. 1_0..2_0 must stay a range, not a float.
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('1_000.25 6.022_140e23 1.5e1_0 1_0..2_0',
      LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual(tkFloat, LTokens[0].Kind);
    Assert.AreEqual<Double>(1000.25, LTokens[0].FloatValue);
    Assert.AreEqual(tkFloat, LTokens[1].Kind);
    Assert.AreEqual<Double>(
      StrToFloat('6.022140E23', TFormatSettings.Invariant),
      LTokens[1].FloatValue);
    Assert.AreEqual(tkFloat, LTokens[2].Kind);
    Assert.AreEqual<Double>(1.5e10, LTokens[2].FloatValue);
    Assert.AreEqual(tkInteger, LTokens[3].Kind);
    Assert.AreEqual<Int64>(10, LTokens[3].IntegerValue);
    Assert.AreEqual('..', LTokens[4].Text);
    Assert.AreEqual<Int64>(20, LTokens[5].IntegerValue);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerStrings }

procedure TTestLexerStrings.SingleQuotedWithEscapes;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('''hello''''world''', LDiagnostics);
    Assert.AreEqual(tkString, LTokens[0].Kind);
    Assert.AreEqual('hello''world', LTokens[0].Value);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerStrings.CharCodeSequence;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('#65#$41#%1000001', LDiagnostics);
    Assert.AreEqual<NativeInt>(3, Length(LTokens) - 1); // 3 char codes + EOF
    Assert.AreEqual(tkCharCode, LTokens[0].Kind);
    Assert.AreEqual('A', LTokens[0].Value);
    Assert.AreEqual('A', LTokens[1].Value);
    Assert.AreEqual('A', LTokens[2].Value);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerStrings.MultilineString;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
  LSource: string;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // The multiline delimiter ''' is recognised only when followed by a
    // line break (verified against dcc32 37.0).
    LSource := StringOfChar('''', 3) + #13#10 + 'line1' + #13#10 + 'line2' +
      #13#10 + StringOfChar('''', 3);
    LTokens := TokenizeToArray(LSource, LDiagnostics);
    Assert.AreEqual(tkString, LTokens[0].Kind);
    Assert.AreEqual('line1'#13#10'line2', LTokens[0].Value);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerStrings.MultilineStringQuoteRun;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
  LSource: string;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // even quote runs inside a multiline string are literal quotes
    LSource := StringOfChar('''', 3) + #13#10 + 'it' + StringOfChar('''', 4) +
      's' + #13#10 + StringOfChar('''', 3);
    LTokens := TokenizeToArray(LSource, LDiagnostics);
    Assert.AreEqual(tkString, LTokens[0].Kind);
    Assert.AreEqual('it''''s', LTokens[0].Value);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerStrings.DigitSeparatorsInCharCodes;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('#6_5#$4_1#%100_0001', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual<NativeInt>(4, Length(LTokens));
    Assert.AreEqual(tkCharCode, LTokens[0].Kind);
    Assert.AreEqual('A', LTokens[0].Value);
    Assert.AreEqual('A', LTokens[1].Value);
    Assert.AreEqual('A', LTokens[2].Value);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerTrivia }

procedure TTestLexerTrivia.LineCommentAttachedToNextToken;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('a// comment'#13#10'b', LDiagnostics);
    // tokens: a, b, EOF (comments/whitespace are trivia, not tokens)
    Assert.AreEqual<NativeInt>(3, Length(LTokens));
    // b carries the line comment AND the line break
    Assert.AreEqual(2, LTokens[1].LeadingTrivia.Count);
    Assert.AreEqual(trLineComment, LTokens[1].LeadingTrivia[0].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerTrivia.NestedBlockComments;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  // dcc ends a { } comment at the first '}'. Text after that closer is
  // real source. There is no second '}' left over (that token is DLX-01).
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('{ outer { inner } still x', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual<NativeInt>(3, Length(LTokens));
    Assert.AreEqual('still', LTokens[0].Text);
    Assert.AreEqual(2, LTokens[0].LeadingTrivia.Count);
    Assert.AreEqual(trBlockComment, LTokens[0].LeadingTrivia[0].Kind);
    Assert.AreEqual('{ outer { inner }', LTokens[0].LeadingTrivia[0].Text);
    Assert.AreEqual('x', LTokens[1].Text);
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerTrivia.DirectiveIsTrivia;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('{$IFDEF DEBUG} x', LDiagnostics);
    Assert.AreEqual(0, LDiagnostics.Count);
    Assert.AreEqual<NativeInt>(2, Length(LTokens));
    Assert.AreEqual(trDirective, LTokens[0].LeadingTrivia[0].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestLexerErrors }

procedure TTestLexerErrors.UnterminatedStringReportsError;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('''never closed', LDiagnostics).Free;
    Assert.AreEqual('DLX-08', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerErrors.UnknownCharacterIsTolerated;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TArray<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := TokenizeToArray('a ? b', LDiagnostics);
    Assert.AreEqual('DLX-01', FirstErrorCode(LDiagnostics));
    Assert.AreEqual<NativeInt>(4, Length(LTokens)); // a, ?, b, EOF
    Assert.AreEqual(tkUnknown, LTokens[1].Kind);
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLexerBasics);
  TDUnitX.RegisterTestFixture(TTestLexerNumbers);
  TDUnitX.RegisterTestFixture(TTestLexerStrings);
  TDUnitX.RegisterTestFixture(TTestLexerTrivia);
  TDUnitX.RegisterTestFixture(TTestLexerErrors);

end.
