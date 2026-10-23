/// <summary>
///   Tests.DX.Delphi.Lexer.Dcc32 — lexer tests that pin what dcc32 and
///   dcc64 37.0 do, from files in the Delphi 13 RTL that the lexer misread:
///   comments don't nest (System.ZLib).
/// </summary>
/// <remarks>
///   Checked on dcc32 and dcc64 37.0: "{ a { b } X" compiles X, "(* c (* d *) X"
///   compiles X, and a comment of the other kind inside one is text. These
///   contradict TTestLexerTrivia.NestedBlockComments and
///   TTestLexerComments.NestedParenComments, which expect nesting.
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

initialization
  TDUnitX.RegisterTestFixture(TTestLexerDcc32Comments);

end.
