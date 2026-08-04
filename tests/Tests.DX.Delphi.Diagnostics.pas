/// <summary>
///   Tests.DX.Delphi.Diagnostics — DUnitX coverage for the diagnostic codes
///   produced by the lexer and parser on malformed input.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Diagnostics;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.CST;

type
  [TestFixture]
  TTestLexerErrorCodes = class
  public
    [Test]
    procedure UnrecognisedCharacter;
    [Test]
    procedure UnterminatedString;
    [Test]
    procedure UnterminatedMultiline;
    [Test]
    procedure InvalidNumber;
  end;

  [TestFixture]
  TTestParserErrorCodes = class
  public
    [Test]
    procedure MissingProgramKeyword;
    [Test]
    procedure MissingSemicolon;
    [Test]
    procedure UnexpectedTokenIsTolerated;
    [Test]
    procedure MultipleErrorsAreCollected;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

{ TTestLexerErrorCodes }

procedure TTestLexerErrorCodes.UnrecognisedCharacter;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('a ` b', LDiagnostics).Free;
    Assert.AreEqual('DLX-01', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerErrorCodes.UnterminatedString;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('''abc', LDiagnostics).Free;
    Assert.AreEqual('DLX-08', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerErrorCodes.UnterminatedMultiline;
var
  LDiagnostics: TDLDiagnostics;
  LSource: string;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LSource := StringOfChar('''', 3) + 'abc';
    LexSource(LSource, LDiagnostics).Free;
    Assert.AreEqual('DLX-09', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerErrorCodes.InvalidNumber;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LexSource('$ZZ', LDiagnostics).Free;
    Assert.AreEqual('DLX-04', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

{ TTestParserErrorCodes }

procedure TTestParserErrorCodes.MissingProgramKeyword;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    ParseSource('not a program;', LDiagnostics).Free;
    Assert.AreEqual('DLP-01', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserErrorCodes.MissingSemicolon;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    ParseSource('unit U interface implementation end.', LDiagnostics).Free;
    Assert.AreEqual('DLP-01', FirstErrorCode(LDiagnostics));
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestParserErrorCodes.UnexpectedTokenIsTolerated;
var
  LDiagnostics: TDLDiagnostics;
  LUnit: TDLCompilationUnit;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    // Garbage after a valid header must not crash the parser.
    LUnit := ParseSource('unit U; interface @@@ ; implementation end.',
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

procedure TTestParserErrorCodes.MultipleErrorsAreCollected;
var
  LDiagnostics: TDLDiagnostics;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    ParseSource(
      'unit U;'#13#10'interface'#13#10+
      'const A = ;'#13#10+
      'type = class'#13#10+
      'implementation'#13#10'end.',
      LDiagnostics).Free;
    Assert.IsTrue(LDiagnostics.Count >= 2,
      'expected multiple errors, got ' + IntToStr(LDiagnostics.Count));
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLexerErrorCodes);
  TDUnitX.RegisterTestFixture(TTestParserErrorCodes);

end.
