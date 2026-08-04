/// <summary>
///   DX.Delphi.Lexer — full tokenizer for the Delphi language surface of
///   Delphi 13.x (Florence).
/// </summary>
/// <remarks>
///   The lexer turns a source text into an owned list of TDLToken objects.
///   Trivia (whitespace, line/block comments, {$...} compiler directives) is
///   attached to the following non-trivia token as leading trivia, so the
///   parser can transfer it onto CST nodes without modelling it in the
///   grammar.
///
///   Supported surface:
///     - case-insensitive keywords, &-escaped identifiers, Unicode identifiers
///     - single-quoted strings with '' escaping, #code char-code sequences
///     - Delphi 12+ multiline strings '''...''' (empirically verified rules:
///       an even run of quotes inside yields run/2 literal quotes; a run of
///       exactly three closes the string; odd runs > 3 are an error)
///     - integers (dec / $hex / %binary) with _ separators, floats with
///       mantissa/exponent
///     - nested block comments { ... } and (* ... *), // line comments,
///       {$...} directives (kept as trivia; conditional compilation is NOT
///       evaluated)
///
///   The tokenizer is tolerant: unexpected input yields a tkUnknown token and
///   a diagnostic instead of aborting.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit DX.Delphi.Lexer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Delphi.Core;

type
  /// <summary>A single token produced by the lexer (trivia or real token).</summary>
  TDLToken = class
  public
    Kind: TDLTokenKind;
    Text: string;             // exact source slice (incl. '&' for escaped ids)
    Span: TDLSourceSpan;
    Value: string;            // decoded: identifier without '&', or string content
    IntegerValue: Int64;      // decoded integer literal
    FloatValue: Double;       // decoded float literal
    LeadingTrivia: TList<TDLTrivia>; // trivia before this token (owned)
    constructor Create(AKind: TDLTokenKind; const AText: string; ASpan: TDLSourceSpan);
    destructor Destroy; override;
    function IsTrivia: Boolean;
    function Description: string;
  end;

  /// <summary>Tolerant recursive-descent-friendly tokenizer for Delphi source.</summary>
  TDLDelphiLexer = class
  private
    FSource: string;
    FOffset: Integer;
    FLine: Integer;
    FColumn: Integer;
    FDiagnostics: TDLDiagnostics;
    FTokens: TObjectList<TDLToken>;
    FLeadingTrivia: TList<TDLTrivia>;
    function GetCurChar: Char;
    function GetCharAt(AOffset: Integer): Char;
    function GetCurrentPos: TDLSourcePos;
    procedure Advance;
    procedure AddToken(AKind: TDLTokenKind; AStartPos: TDLSourcePos);
    procedure AddTrivia(AKind: TDLTriviaKind; AStartPos: TDLSourcePos);
    procedure AddUnknown(AStartPos: TDLSourcePos);
    procedure ScanWhitespace;
    procedure ScanLineComment;
    procedure ScanBlockComment(AStartPos: TDLSourcePos; AKind: TDLTriviaKind);
    procedure ScanDirective;
    procedure ScanIdentifier;
    procedure ScanNumber;
    procedure ScanString;
    procedure ScanMultilineString;
    procedure ScanCharCode;
    procedure ScanSymbol;
  public
    constructor Create(const ASource: string; ADiagnostics: TDLDiagnostics);
    destructor Destroy; override;
    /// <summary>Tokenizes the whole source; caller owns the returned list.</summary>
    function Tokenize: TObjectList<TDLToken>;
    property Diagnostics: TDLDiagnostics read FDiagnostics;
  end;

implementation

uses
  System.Character;

const
  CTokenKindText: array[TDLTokenKind] of string = (
    'eof', 'identifier', 'keyword', 'integer', 'float', 'string', 'charcode',
    'symbol', 'whitespace', 'linecomment', 'blockcomment', 'directive',
    'unknown');

function BinToInt64(const ABits: string): Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(ABits) do
  begin
    Result := Result shl 1;
    case ABits[i] of
      '0': ;
      '1': Inc(Result);
    else
      raise EConvertError.Create('invalid binary digit "' + ABits[i] + '"');
    end;
  end;
end;

{ TDLToken }

constructor TDLToken.Create(AKind: TDLTokenKind; const AText: string;
  ASpan: TDLSourceSpan);
begin
  inherited Create;
  Kind := AKind;
  Text := AText;
  Span := ASpan;
  LeadingTrivia := TList<TDLTrivia>.Create;
end;

destructor TDLToken.Destroy;
begin
  LeadingTrivia.Free;
  inherited Destroy;
end;

function TDLToken.IsTrivia: Boolean;
begin
  Result := (Kind >= tkWhitespace) and (Kind <= tkDirective);
end;

function TDLToken.Description: string;
begin
  case Kind of
    tkInteger: Result := Format('integer(%d)', [IntegerValue]);
    tkFloat: Result := Format('float(%g)', [FloatValue]);
    tkString, tkCharCode: Result := Format('string(%s)', [Value]);
    tkEOF: Result := 'eof';
  else
    Result := Text;
  end;
end;

{ TDLDelphiLexer }

constructor TDLDelphiLexer.Create(const ASource: string;
  ADiagnostics: TDLDiagnostics);
begin
  inherited Create;
  // Strip a leading UTF-8 BOM if present (EF BB BF decoded as U+FEFF).
  FSource := ASource;
  if (Length(FSource) > 0) and (FSource[1] = #$FEFF) then
    Delete(FSource, 1, 1);
  FOffset := 0;
  FLine := 1;
  FColumn := 1;
  FDiagnostics := ADiagnostics;
  FTokens := TObjectList<TDLToken>.Create(True);
  FLeadingTrivia := TList<TDLTrivia>.Create;
end;

destructor TDLDelphiLexer.Destroy;
begin
  FTokens.Free;
  FLeadingTrivia.Free;
  inherited Destroy;
end;

function TDLDelphiLexer.GetCurChar: Char;
begin
  if FOffset < Length(FSource) then
    Result := FSource[FOffset + 1]
  else
    Result := #0;
end;

function TDLDelphiLexer.GetCharAt(AOffset: Integer): Char;
begin
  if AOffset < Length(FSource) then
    Result := FSource[AOffset + 1]
  else
    Result := #0;
end;

function TDLDelphiLexer.GetCurrentPos: TDLSourcePos;
begin
  Result := TDLSourcePos.Create(FOffset, FLine, FColumn);
end;

procedure TDLDelphiLexer.Advance;
var
  LChar: Char;
begin
  if FOffset >= Length(FSource) then
    Exit;
  LChar := FSource[FOffset + 1];
  Inc(FOffset);
  if LChar = #13 then
  begin
    // CRLF: consume the LF as part of the same line break.
    if (FOffset < Length(FSource)) and (FSource[FOffset + 1] = #10) then
      Inc(FOffset);
    Inc(FLine);
    FColumn := 1;
  end
  else if LChar = #10 then
  begin
    Inc(FLine);
    FColumn := 1;
  end
  else
    Inc(FColumn);
end;

procedure TDLDelphiLexer.AddToken(AKind: TDLTokenKind; AStartPos: TDLSourcePos);
var
  LToken: TDLToken;
  i: Integer;
begin
  LToken := TDLToken.Create(AKind, Copy(FSource, AStartPos.Offset + 1,
    FOffset - AStartPos.Offset), TDLSourceSpan.Create(AStartPos, GetCurrentPos));
  for i := 0 to FLeadingTrivia.Count - 1 do
    LToken.LeadingTrivia.Add(FLeadingTrivia[i]);
  FLeadingTrivia.Clear;
  FTokens.Add(LToken);
end;

procedure TDLDelphiLexer.AddTrivia(AKind: TDLTriviaKind; AStartPos: TDLSourcePos);
begin
  FLeadingTrivia.Add(TDLTrivia.Create(AKind,
    Copy(FSource, AStartPos.Offset + 1, FOffset - AStartPos.Offset),
    TDLSourceSpan.Create(AStartPos, GetCurrentPos)));
end;

procedure TDLDelphiLexer.AddUnknown(AStartPos: TDLSourcePos);
begin
  Advance;
  FDiagnostics.Error('DLX-01', 'Unrecognised character "' + GetCharAt(AStartPos.Offset) + '"',
    TDLSourceSpan.Create(AStartPos, GetCurrentPos));
  AddToken(tkUnknown, AStartPos);
end;

procedure TDLDelphiLexer.ScanWhitespace;
var
  LStart: TDLSourcePos;
begin
  LStart := GetCurrentPos;
  while CharInSet(GetCurChar, [' ', #9, #13, #10, #12]) do
    Advance;
  AddTrivia(trWhitespace, LStart);
end;

procedure TDLDelphiLexer.ScanLineComment;
var
  LStart: TDLSourcePos;
begin
  LStart := GetCurrentPos;
  Advance; // '/'
  Advance; // '/'
  while not CharInSet(GetCurChar, [#0, #13, #10]) do
    Advance;
  AddTrivia(trLineComment, LStart);
end;

procedure TDLDelphiLexer.ScanBlockComment(AStartPos: TDLSourcePos;
  AKind: TDLTriviaKind);
var
  LDepth: Integer;
  LIsParenStyle: Boolean;
begin
  LIsParenStyle := GetCurChar = '(';
  Advance; // '{' or '('
  if LIsParenStyle then
    Advance; // '*'
  LDepth := 1;
  while (GetCurChar <> #0) and (LDepth > 0) do
  begin
    if LIsParenStyle and (GetCurChar = '*') and (GetCharAt(FOffset + 1) = ')') then
    begin
      Advance;
      Advance;
      Dec(LDepth);
    end
    else if (not LIsParenStyle) and (GetCurChar = '{') then
    begin
      // '{' inside a { } comment: nested comment. '{' is also the end marker
      // only via '}', so a plain '{' simply deepens.
      Advance;
      Inc(LDepth);
    end
    else if (not LIsParenStyle) and (GetCurChar = '}') then
    begin
      Advance;
      Dec(LDepth);
    end
    else
      Advance;
  end;
  if LDepth > 0 then
    FDiagnostics.Error('DLX-02', 'Unterminated block comment',
      TDLSourceSpan.Create(AStartPos, GetCurrentPos));
  AddTrivia(AKind, AStartPos);
end;

procedure TDLDelphiLexer.ScanDirective;
var
  LStart: TDLSourcePos;
begin
  LStart := GetCurrentPos;
  Advance; // '{'
  Advance; // '$'
  while (GetCurChar <> #0) and (GetCurChar <> '}') do
    Advance;
  if GetCurChar = '}' then
    Advance
  else
    FDiagnostics.Error('DLX-03', 'Unterminated compiler directive',
      TDLSourceSpan.Create(LStart, GetCurrentPos));
  AddTrivia(trDirective, LStart);
end;

procedure TDLDelphiLexer.ScanIdentifier;
var
  LStart: TDLSourcePos;
  LToken: TDLToken;
  LKeyword: TDLKeyword;
  LName: string;
  LIsAmpersand: Boolean;
begin
  LStart := GetCurrentPos;
  LIsAmpersand := False;
  if GetCurChar = '&' then
  begin
    LIsAmpersand := True;
    Advance;
  end;
  while (GetCurChar <> #0) and
        (CharInSet(GetCurChar, ['_', '0'..'9']) or GetCurChar.IsLetter) do
    Advance;
  LName := Copy(FSource, LStart.Offset + 1, FOffset - LStart.Offset);
  if (Length(LName) > 0) and (LName[1] = '&') then
    Delete(LName, 1, 1);
  if LIsAmpersand then
    LKeyword := kwNone
  else
    LKeyword := TDLKeywords.ToKeyword(LName);
  AddToken(tkIdentifier, LStart);
  LToken := FTokens.Last;
  LToken.Value := LName;
  if LKeyword <> kwNone then
    LToken.Kind := tkKeyword;
end;

procedure TDLDelphiLexer.ScanNumber;
var
  LStart: TDLSourcePos;
  LToken: TDLToken;
  LDigits: string;
  LIsFloat: Boolean;
begin
  LStart := GetCurrentPos;
  LIsFloat := False;
  if GetCurChar = '$' then
  begin
    Advance;
    LDigits := '';
    while CharInSet(GetCurChar, ['0'..'9', 'A'..'F', 'a'..'f', '_']) do
    begin
      if GetCurChar <> '_' then
        LDigits := LDigits + GetCurChar;
      Advance;
    end;
    AddToken(tkInteger, LStart);
    LToken := FTokens.Last;
    try
      LToken.IntegerValue := StrToInt64('$' + LDigits);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-04', 'Invalid hexadecimal literal "' + LDigits + '"',
          LToken.Span);
    end;
    Exit;
  end;
  if GetCurChar = '%' then
  begin
    Advance;
    LDigits := '';
    while CharInSet(GetCurChar, ['0', '1', '_']) do
    begin
      if GetCurChar <> '_' then
        LDigits := LDigits + GetCurChar;
      Advance;
    end;
    AddToken(tkInteger, LStart);
    LToken := FTokens.Last;
    // StrToInt64 does not understand the '%' prefix; parse the bits manually.
    LToken.IntegerValue := 0;
    try
      LToken.IntegerValue := BinToInt64(LDigits);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-05', 'Invalid binary literal "' + LDigits + '"',
          LToken.Span);
    end;
    Exit;
  end;
  // Decimal (integer or float).
  LDigits := '';
  while CharInSet(GetCurChar, ['0'..'9', '_']) do
  begin
    if GetCurChar <> '_' then
      LDigits := LDigits + GetCurChar;
    Advance;
  end;
  if (GetCurChar = '.') and CharInSet(GetCharAt(FOffset + 1), ['0'..'9']) then
  begin
    LIsFloat := True;
    Advance; // '.'
    LDigits := LDigits + '.';
    while CharInSet(GetCurChar, ['0'..'9', '_']) do
    begin
      if GetCurChar <> '_' then
        LDigits := LDigits + GetCurChar;
      Advance;
    end;
  end;
  if CharInSet(GetCurChar, ['e', 'E']) then
  begin
    LIsFloat := True;
    LDigits := LDigits + 'E';
    Advance;
    if CharInSet(GetCurChar, ['+', '-']) then
    begin
      LDigits := LDigits + GetCurChar;
      Advance;
    end;
    while CharInSet(GetCurChar, ['0'..'9']) do
    begin
      LDigits := LDigits + GetCurChar;
      Advance;
    end;
  end;
  AddToken(tkInteger, LStart);
  LToken := FTokens.Last;
  if LIsFloat then
  begin
    LToken.Kind := tkFloat;
    try
      LToken.FloatValue := StrToFloat(LDigits, TFormatSettings.Invariant);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-06', 'Invalid float literal "' + LDigits + '"',
          LToken.Span);
    end;
  end
  else
  begin
    try
      LToken.IntegerValue := StrToInt64(LDigits);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-07', 'Invalid integer literal "' + LDigits + '"',
          LToken.Span);
    end;
  end;
end;

procedure TDLDelphiLexer.ScanString;
var
  LStart: TDLSourcePos;
  LToken: TDLToken;
  LValue: string;
  LClosed: Boolean;
begin
  LStart := GetCurrentPos;
  Advance; // opening '
  LValue := '';
  LClosed := False;
  while GetCurChar <> #0 do
  begin
    if GetCurChar = '''' then
    begin
      if GetCharAt(FOffset + 1) = '''' then
      begin
        LValue := LValue + '''';
        Advance;
        Advance;
      end
      else
      begin
        Advance;
        LClosed := True;
        Break;
      end;
    end
    else if CharInSet(GetCurChar, [#13, #10]) then
    begin
      FDiagnostics.Error('DLX-08', 'Unterminated string literal (raw line break)',
        TDLSourceSpan.Create(LStart, GetCurrentPos));
      Break;
    end
    else
    begin
      LValue := LValue + GetCurChar;
      Advance;
    end;
  end;
  if (not LClosed) and (GetCurChar = #0) then
    FDiagnostics.Error('DLX-08', 'Unterminated string literal',
      TDLSourceSpan.Create(LStart, GetCurrentPos));
  AddToken(tkString, LStart);
  LToken := FTokens.Last;
  LToken.Value := LValue;
end;

procedure TDLDelphiLexer.ScanMultilineString;
var
  LStart: TDLSourcePos;
  LToken: TDLToken;
  LValue: string;
  LClosed: Boolean;
  LQuoteCount: Integer;
begin
  LStart := GetCurrentPos;
  Advance; // '''
  Advance;
  Advance;
  LValue := '';
  LClosed := False;
  while GetCurChar <> #0 do
  begin
    if GetCurChar = '''' then
    begin
      // Count the run of consecutive quotes.
      LQuoteCount := 0;
      while GetCharAt(FOffset + LQuoteCount) = '''' do
        Inc(LQuoteCount);
      if (LQuoteCount mod 2) = 1 then
      begin
        if LQuoteCount = 3 then
        begin
          // Closing delimiter.
          Advance;
          Advance;
          Advance;
          LClosed := True;
          Break;
        end;
        FDiagnostics.Error('DLX-09',
          'Invalid quote run in multiline string (odd count > 3)',
          TDLSourceSpan.Create(LStart, GetCurrentPos));
        Break;
      end;
      // Even run: run/2 literal quotes.
      LValue := LValue + StringOfChar('''', LQuoteCount div 2);
      while LQuoteCount > 0 do
      begin
        Advance;
        Dec(LQuoteCount);
      end;
    end
    else if GetCurChar = #13 then
    begin
      // Advance() consumes CRLF as one line break; restore both chars.
      LValue := LValue + #13#10;
      Advance;
    end
    else if GetCurChar = #10 then
    begin
      LValue := LValue + #10;
      Advance;
    end
    else
    begin
      LValue := LValue + GetCurChar;
      Advance;
    end;
  end;
  if (not LClosed) and (GetCurChar = #0) then
    FDiagnostics.Error('DLX-09', 'Unterminated multiline string literal',
      TDLSourceSpan.Create(LStart, GetCurrentPos));
  AddToken(tkString, LStart);
  LToken := FTokens.Last;
  LToken.Value := LValue;
end;

procedure TDLDelphiLexer.ScanCharCode;
var
  LStart: TDLSourcePos;
  LToken: TDLToken;
  LDigits: string;
  LValue: Integer;
begin
  LStart := GetCurrentPos;
  Advance; // '#'
  LDigits := '';
  if GetCurChar = '$' then
  begin
    LDigits := '$';
    Advance;
    while CharInSet(GetCurChar, ['0'..'9', 'A'..'F', 'a'..'f']) do
    begin
      LDigits := LDigits + GetCurChar;
      Advance;
    end;
  end
  else if GetCurChar = '%' then
  begin
    LDigits := '%';
    Advance;
    while CharInSet(GetCurChar, ['0', '1']) do
    begin
      LDigits := LDigits + GetCurChar;
      Advance;
    end;
  end
  else
  begin
    while CharInSet(GetCurChar, ['0'..'9']) do
    begin
      LDigits := LDigits + GetCurChar;
      Advance;
    end;
  end;
  AddToken(tkCharCode, LStart);
  LToken := FTokens.Last;
  if LDigits = '' then
    FDiagnostics.Error('DLX-10', 'Expected digit after "#"', LToken.Span)
  else
  begin
    try
      if (Length(LDigits) > 0) and (LDigits[1] = '%') then
        LValue := Integer(BinToInt64(Copy(LDigits, 2, MaxInt)))
      else
        LValue := StrToInt(LDigits);
      if LValue > $FFFF then
        FDiagnostics.Error('DLX-11', 'Char code out of range: #' + LDigits,
          LToken.Span)
      else
        LToken.Value := WideChar(LValue);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-12', 'Invalid char code "#' + LDigits + '"',
          LToken.Span);
    end;
  end;
end;

procedure TDLDelphiLexer.ScanSymbol;
var
  LStart: TDLSourcePos;
begin
  LStart := GetCurrentPos;
  case GetCurChar of
    ':':
      begin
        Advance;
        if GetCurChar = '=' then
          Advance
        else if GetCurChar = ':' then
        begin
          Advance;
          FDiagnostics.Warning('DLX-13', '"::" is not a Delphi operator; treat as ":"',
            TDLSourceSpan.Create(LStart, GetCurrentPos));
        end;
      end;
    '<':
      begin
        Advance;
        if CharInSet(GetCurChar, ['=', '>']) then
          Advance;
      end;
    '>', '=', '+', '-', '*', '/', '(', ')', '[', ']', ',', ';', '.', '@',
    '^', '|':
      begin
        Advance;
        if (GetCharAt(LStart.Offset) = '.') and (GetCurChar = '.') then
          Advance; // '..' subrange/range operator
      end;
  else
    // Defensive: caller only invokes this for known symbols.
    Advance;
  end;
  AddToken(tkSymbol, LStart);
end;

function TDLDelphiLexer.Tokenize: TObjectList<TDLToken>;
var
  LStart: TDLSourcePos;
  LChar: Char;
begin
  while GetCurChar <> #0 do
  begin
    LStart := GetCurrentPos;
    LChar := GetCurChar;
    if CharInSet(LChar, [' ', #9, #13, #10, #12]) then
      ScanWhitespace
    else if LChar = '/' then
    begin
      if GetCharAt(FOffset + 1) = '/' then
        ScanLineComment
      else
        ScanSymbol;
    end
    else if LChar = '{' then
    begin
      if GetCharAt(FOffset + 1) = '$' then
        ScanDirective
      else
        ScanBlockComment(LStart, trBlockComment);
    end
    else if (LChar = '(') and (GetCharAt(FOffset + 1) = '*') then
      ScanBlockComment(LStart, trBlockComment)
    else if LChar = '''' then
    begin
      if (GetCharAt(FOffset + 1) = '''') and (GetCharAt(FOffset + 2) = '''') then
        ScanMultilineString
      else
        ScanString;
    end
    else if LChar = '#' then
      ScanCharCode
    else if CharInSet(LChar, ['0'..'9']) then
      ScanNumber
    else if (LChar = '$') or (LChar = '%') then
      ScanNumber
    else if (LChar = '&') or LChar.IsLetter or (LChar = '_') then
      ScanIdentifier
    else if CharInSet(LChar, [':', '<', '>', '=', '+', '-', '*', '(', ')',
      '[', ']', ',', ';', '.', '@', '^', '|']) then
      ScanSymbol
    else
      AddUnknown(LStart);
  end;
  AddToken(tkEOF, GetCurrentPos);
  Result := FTokens;
  FTokens := nil; // transfer ownership to the caller
end;

end.
