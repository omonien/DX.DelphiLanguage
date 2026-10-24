/// <summary>
///   Tests.DX.Delphi.Lexer.Dcc32 — lexer tests that pin what dcc32 and
///   dcc64 37.0 do, from files in the Delphi 13 RTL that the lexer misread:
///   comments don't nest (System.ZLib), and asm numeric suffixes
///   (System.pas, CMP BYTE PTR [ECX],0EBH).
/// </summary>
/// <remarks>
///   Comment cases were checked by the contributor on dcc32 and dcc64 37.0:
///   "{ a { b } X" compiles X, "(* c (* d *) X" compiles X, and a comment of
///   the other kind inside one is text. NestedBlockComments and
///   NestedParenComments pin the same rule.
///   H, B and O suffixes follow the built-in assembler and apply only
///   inside asm ... end. Outside asm, 0EBH is an invalid float again.
/// </remarks>
/// <license>MIT</license>
unit Tests.DX.Delphi.Lexer.Dcc32;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.Lexer;

type
  [TestFixture]
  TTestLexerDcc32Comments = class
  public
    [Test]
    procedure BraceCommentEndsAtFirstClose;
    [Test]
    procedure ParenCommentEndsAtFirstClose;
    [Test]
    procedure OtherKindInsideIsText;
    [Test]
    procedure ParenCommentHoldingDirectives;
  end;

  [TestFixture]
  TTestLexerDcc32AsmNumbers = class
  public
    [Test]
    procedure IntelHexUpperSuffix;
    [Test]
    procedure IntelHexLowerSuffix;
    [Test]
    procedure IntelHexNotOutsideAsm;
    [Test]
    procedure HexSuffixEndsWithAsm;
    [Test]
    procedure BinarySuffixInsideAsm;
    [Test]
    procedure BinarySuffixNotOutsideAsm;
    [Test]
    procedure OctalSuffixInsideAsm;
    [Test]
    procedure OctalSuffixNotOutsideAsm;
    [Test]
    procedure ExponentStillFloat;
    [Test]
    procedure EndInsideStringOrCommentStaysInAsm;
    [Test]
    procedure AssemblerDirectiveIsNotAsmBlock;
    [Test]
    procedure IllegalBinaryDigitIsNotASuffix;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

// The first non-EOF token's text and kind, and the diagnostic count.
procedure Lex(const ASource: string; out AText: string; out AKind: TDLTokenKind;
  out AValue: Int64; out ADiagnostics: Integer);
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource(ASource, LDiagnostics);
    try
      AText := LTokens[0].Text;
      AKind := LTokens[0].Kind;
      AValue := LTokens[0].IntegerValue;
      ADiagnostics := LDiagnostics.Count;
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerDcc32Comments.BraceCommentEndsAtFirstClose;
var
  LText: string; LKind: TDLTokenKind; LValue: Int64; LCount: Integer;
begin
  Lex('{ outer { inner } x', LText, LKind, LValue, LCount);
  Assert.AreEqual(0, LCount);
  Assert.AreEqual('x', LText);
end;

procedure TTestLexerDcc32Comments.ParenCommentEndsAtFirstClose;
var
  LText: string; LKind: TDLTokenKind; LValue: Int64; LCount: Integer;
begin
  Lex('(* outer (* inner *) x', LText, LKind, LValue, LCount);
  Assert.AreEqual(0, LCount);
  Assert.AreEqual('x', LText);
end;

procedure TTestLexerDcc32Comments.OtherKindInsideIsText;
var
  LText: string; LKind: TDLTokenKind; LValue: Int64; LCount: Integer;
begin
  Lex('(* e { f } g *) { h (* i *) j } x', LText, LKind, LValue, LCount);
  Assert.AreEqual(0, LCount);
  Assert.AreEqual('x', LText);
end;

// The shape of System.ZLib's commented-out imports (line 1551 on)
procedure TTestLexerDcc32Comments.ParenCommentHoldingDirectives;
var
  LText: string; LKind: TDLTokenKind; LValue: Int64; LCount: Integer;
begin
  Lex('(*' + sLineBreak +
      'function gzfread(buf: Pointer; size, nitems: z_size_t; file_: gzFile): z_size_t; cdecl;' + sLineBreak +
      '  external {$IFDEF USE_LIBZLIB} libzlib name _PU + ''gzfread''{$ENDIF};' + sLineBreak +
      '*)' + sLineBreak + 'x', LText, LKind, LValue, LCount);
  Assert.AreEqual(0, LCount);
  Assert.AreEqual('x', LText);
end;

function FindTokenText(ATokens: TObjectList<TDLToken>;
  const AText: string): TDLToken;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ATokens.Count - 1 do
    if ATokens[i].Text = AText then
      Exit(ATokens[i]);
end;

procedure ExpectLiteral(const ASource, AText: string; AKind: TDLTokenKind;
  AValue: Int64; const AErrorCode: string);
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
  LToken: TDLToken;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource(ASource, LDiagnostics);
    try
      if AErrorCode = '' then
        Assert.AreEqual(0, LDiagnostics.Count)
      else
        Assert.AreEqual(AErrorCode, FirstErrorCode(LDiagnostics));
      LToken := FindTokenText(LTokens, AText);
      Assert.IsTrue(LToken <> nil, 'missing token ' + AText);
      Assert.AreEqual(Ord(AKind), Ord(LToken.Kind));
      if AKind = tkInteger then
        Assert.AreEqual(AValue, LToken.IntegerValue);
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerDcc32AsmNumbers.IntelHexUpperSuffix;
begin
  // System.pas: CMP BYTE PTR [ECX],0EBH. 0BAD4H is the form in the
  // assembler documentation (leading zero, then H).
  ExpectLiteral('asm CMP BYTE PTR [ECX],0EBH end', '0EBH', tkInteger, $EB, '');
  ExpectLiteral('asm DW 0BAD4H end', '0BAD4H', tkInteger, $BAD4, '');
  // B is a hex digit, so H wins: 10BH is $10B, not binary 2 followed by H.
  ExpectLiteral('asm DW 10BH end', '10BH', tkInteger, $10B, '');
end;

procedure TTestLexerDcc32AsmNumbers.IntelHexLowerSuffix;
begin
  ExpectLiteral('ASM DW 0ffh END', '0ffh', tkInteger, 255, '');
end;

procedure TTestLexerDcc32AsmNumbers.IntelHexNotOutsideAsm;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  // Pascal code: 0E is an invalid float and BH is an identifier.
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource('0EBH', LDiagnostics);
    try
      Assert.AreEqual('DLX-06', FirstErrorCode(LDiagnostics));
      Assert.AreEqual(Ord(tkFloat), Ord(LTokens[0].Kind));
      Assert.AreEqual('0E', LTokens[0].Text);
      Assert.AreEqual('BH', LTokens[1].Text);
      Assert.AreEqual(Ord(tkIdentifier), Ord(LTokens[1].Kind));
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerDcc32AsmNumbers.HexSuffixEndsWithAsm;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource('asm DW 10H end 10H', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual(7, LTokens.Count);
      Assert.AreEqual('10H', LTokens[2].Text);
      Assert.AreEqual(Ord(tkInteger), Ord(LTokens[2].Kind));
      Assert.AreEqual(Int64(16), LTokens[2].IntegerValue);
      Assert.AreEqual('10', LTokens[4].Text);
      Assert.AreEqual(Int64(10), LTokens[4].IntegerValue);
      Assert.AreEqual('H', LTokens[5].Text);
      Assert.AreEqual(Ord(tkIdentifier), Ord(LTokens[5].Kind));
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerDcc32AsmNumbers.BinarySuffixInsideAsm;
begin
  ExpectLiteral('asm DW 1010B end', '1010B', tkInteger, 10, '');
  ExpectLiteral('asm DW 1010b end', '1010b', tkInteger, 10, '');
end;

procedure TTestLexerDcc32AsmNumbers.BinarySuffixNotOutsideAsm;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource('1010B', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual('1010', LTokens[0].Text);
      Assert.AreEqual(Ord(tkInteger), Ord(LTokens[0].Kind));
      Assert.AreEqual(Int64(1010), LTokens[0].IntegerValue);
      Assert.AreEqual('B', LTokens[1].Text);
      Assert.AreEqual(Ord(tkIdentifier), Ord(LTokens[1].Kind));
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerDcc32AsmNumbers.OctalSuffixInsideAsm;
begin
  ExpectLiteral('asm DW 10O end', '10O', tkInteger, 8, '');
  ExpectLiteral('asm DW 10o end', '10o', tkInteger, 8, '');
end;

procedure TTestLexerDcc32AsmNumbers.OctalSuffixNotOutsideAsm;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource('10O', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual('10', LTokens[0].Text);
      Assert.AreEqual(Int64(10), LTokens[0].IntegerValue);
      Assert.AreEqual('O', LTokens[1].Text);
      Assert.AreEqual(Ord(tkIdentifier), Ord(LTokens[1].Kind));
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

// 1E5 has no suffix: still a float, inside asm as well as outside.
procedure TTestLexerDcc32AsmNumbers.ExponentStillFloat;
begin
  ExpectLiteral('1E5', '1E5', tkFloat, 0, '');
  ExpectLiteral('asm DW 1E5 end', '1E5', tkFloat, 0, '');
end;

procedure TTestLexerDcc32AsmNumbers.EndInsideStringOrCommentStaysInAsm;
begin
  ExpectLiteral('asm DB ''end'' 0EBH end', '0EBH', tkInteger, $EB, '');
  ExpectLiteral('asm // end' + sLineBreak + '0EBH end', '0EBH', tkInteger, $EB, '');
end;

procedure TTestLexerDcc32AsmNumbers.AssemblerDirectiveIsNotAsmBlock;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource('assembler 0EBH', LDiagnostics);
    try
      Assert.AreEqual('DLX-06', FirstErrorCode(LDiagnostics));
      Assert.AreEqual(Ord(tkKeyword), Ord(LTokens[0].Kind));
      Assert.AreEqual('assembler', LTokens[0].Text);
      Assert.AreEqual('0E', LTokens[1].Text);
      Assert.AreEqual(Ord(tkFloat), Ord(LTokens[1].Kind));
      Assert.AreEqual('BH', LTokens[2].Text);
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestLexerDcc32AsmNumbers.IllegalBinaryDigitIsNotASuffix;
var
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
begin
  // 2 is not a binary digit, so this is not the literal 2B.
  // 1010BYTE continues an identifier, so the B is not a suffix either.
  LDiagnostics := TDLDiagnostics.Create;
  try
    LTokens := LexSource('asm 2B 1010BYTE end', LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count);
      Assert.AreEqual('2', LTokens[1].Text);
      Assert.AreEqual(Int64(2), LTokens[1].IntegerValue);
      Assert.AreEqual('B', LTokens[2].Text);
      Assert.AreEqual(Ord(tkIdentifier), Ord(LTokens[2].Kind));
      Assert.AreEqual('1010', LTokens[3].Text);
      Assert.AreEqual(Int64(1010), LTokens[3].IntegerValue);
      Assert.AreEqual('BYTE', LTokens[4].Text);
      Assert.AreEqual(Ord(tkIdentifier), Ord(LTokens[4].Kind));
    finally
      LTokens.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLexerDcc32Comments);
  TDUnitX.RegisterTestFixture(TTestLexerDcc32AsmNumbers);

end.
