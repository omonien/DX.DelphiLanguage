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
///       mantissa/exponent; inside asm, H/B/O numeric suffixes
///     - block comments { ... } and (* ... *) do not nest, // line comments,
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
  DX.Delphi.Core,
  DX.Delphi.Conditions;

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
    FFreed: Boolean;
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
    FSteps: Integer;
    // True from the keyword asm until the next keyword end (ParseAsmStmt
    // stops at that same end). H/B/O numeric suffixes are integers only then.
    FInAsm: Boolean;
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
    function TryAsmSuffixedNumber(AStart: TDLSourcePos): Boolean;
    procedure ScanString(ADelimiter: Char);
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

  /// <summary>
  ///  Pure analysis of the trivia attached to tokens: detects compiler
  ///  directives and conditional-compilation branch markers. Used by the
  ///  parser to model {$IFDEF}/{$ELSE}/{$ENDIF} groups structurally.
  ///  All members are static and side-effect free.
  /// </summary>
  TDLTriviaAnalyzer = class
  public
    /// <summary>True when the token carries any compiler directive trivia.</summary>
    class function HasDirective(AToken: TDLToken): Boolean;
    /// <summary>True when the token's trivia OPENS a conditional branch
    /// ({$IFDEF}, {$IFNDEF}, {$IF ...}, {$ELSE}, {$ELSEIF}).</summary>
    class function HasConditionalStart(AToken: TDLToken): Boolean;
    /// <summary>True only for {$ELSE}/{$ELSEIF} (continuation of the current
    /// conditional chain), never for a fresh {$IFDEF}/{$IF}.</summary>
    class function HasConditionalContinuation(AToken: TDLToken): Boolean;
    /// <summary>True only for a bare {$ELSE} directive (not {$ELSEIF}).</summary>
    class function HasBareElse(AToken: TDLToken): Boolean;
    /// <summary>True when the token carries a branch directive of an ongoing
    /// conditional chain ({$ELSE}/{$ELSEIF}/{$ENDIF}).</summary>
    class function HasConditionalBranch(AToken: TDLToken): Boolean;
    /// <summary>Returns the LAST (innermost) conditional directive of the
    /// token's leading trivia; ACondition is nil for cdNone/cdEndIf.</summary>
    class function LastConditionalDirective(AToken: TDLToken;
      out ACondition: TDLCondition): TDLConditionDirectiveKind;
    /// <summary>True when exactly one conditional directive is present on the
    /// token (nested conditionals stack several directives onto one token).</summary>
    class function SingleConditional(AToken: TDLToken): Boolean;
    /// <summary>True when the statement sequence starting at AStart forms a
    /// clean conditional group (a ';' at depth 0 precedes each branch marker).</summary>
    class function CanStartConditionalGroup(ATokens: TObjectList<TDLToken>;
      AStart: Integer; ADeclGroup: Boolean): Boolean;
  end;

implementation

uses
  System.Character;

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

function OctToInt64(const ADigits: string): Int64;
var
  i: Integer;
  LDigit: Integer;
begin
  Result := 0;
  for i := 1 to Length(ADigits) do
  begin
    LDigit := Ord(ADigits[i]) - Ord('0');
    if (LDigit < 0) or (LDigit > 7) then
      raise EConvertError.Create('invalid octal digit "' + ADigits[i] + '"');
    if Result > (High(Int64) div 8) then
      raise EConvertError.Create('octal literal out of range');
    Result := Result * 8 + LDigit;
  end;
end;

{ TDLToken }

constructor TDLToken.Create(AKind: TDLTokenKind; const AText: string;
  ASpan: TDLSourceSpan);
begin
  inherited Create;
  FFreed := False;
  Kind := AKind;
  Text := AText;
  Span := ASpan;
  LeadingTrivia := TList<TDLTrivia>.Create;
end;

destructor TDLToken.Destroy;
begin
  if FFreed then
    raise Exception.Create('DOUBLE-FREE detected: TDLToken ' + Text);
  FFreed := True;
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
  FSteps := 0;
  FInAsm := False;
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
  Inc(FSteps);
  // Defensive guard against runaway scan loops on pathological input.
  if FSteps > 50000000 then
    raise Exception.Create('DLX-FATAL: lexer step limit exceeded');
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
  LClosed: Boolean;
  LIsParenStyle: Boolean;
begin
  // Delphi does not nest comments: a { } comment ends at the first '}', a
  // (* *) comment at the first '*)', whatever they contain (dcc32 and dcc64
  // 37.0: "{ a { b } X" compiles X). A '{' or '(*' inside is plain text, so
  // System.ZLib's (* ... *) blocks holding {$IFDEF ...} close where dcc32
  // closes them.
  LIsParenStyle := GetCurChar = '(';
  Advance; // '{' or '('
  if LIsParenStyle then
    Advance; // '*'
  LClosed := False;
  while GetCurChar <> #0 do
  begin
    if LIsParenStyle and (GetCurChar = '*') and (GetCharAt(FOffset + 1) = ')') then
    begin
      Advance;
      Advance;
      LClosed := True;
      Break;
    end
    else if (not LIsParenStyle) and (GetCurChar = '}') then
    begin
      Advance;
      LClosed := True;
      Break;
    end
    else
      Advance;
  end;
  if not LClosed then
    FDiagnostics.Error('DLX-02', 'Unterminated block comment',
      TDLSourceSpan.Create(AStartPos, GetCurrentPos));
  AddTrivia(AKind, AStartPos);
end;

procedure TDLDelphiLexer.ScanDirective;
var
  LStart: TDLSourcePos;
  LIsParenStyle: Boolean;
begin
  LStart := GetCurrentPos;
  LIsParenStyle := GetCurChar = '(';
  Advance; // '{' or '('
  if LIsParenStyle then
    Advance; // '*'
  Advance; // '$'
  if LIsParenStyle then
  begin
    while (GetCurChar <> #0) do
      if (GetCurChar = '*') and (GetCharAt(FOffset + 1) = ')') then
      begin
        Advance;
        Advance;
        Break;
      end
      else
        Advance;
  end
  else
  begin
    while (GetCurChar <> #0) and (GetCurChar <> '}') do
      Advance;
    if GetCurChar = '}' then
      Advance
    else
      FDiagnostics.Error('DLX-03', 'Unterminated compiler directive',
        TDLSourceSpan.Create(LStart, GetCurrentPos));
  end;
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
        (CharInSet(GetCurChar, ['_', '0'..'9', '&']) or GetCurChar.IsLetter) do
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
  // '&asm' is an identifier (kwNone) and does not open a block. A second
  // 'asm' before 'end' stays inside the block; the next 'end' closes it.
  if LKeyword = kwAsm then
    FInAsm := True
  else if (LKeyword = kwEnd) and FInAsm then
    FInAsm := False;
end;

function TDLDelphiLexer.TryAsmSuffixedNumber(AStart: TDLSourcePos): Boolean;
var
  LEnd: Integer;
  LDigits: string;
  LToken: TDLToken;

  function EndsNumber(AAt: Integer): Boolean;
  var
    LNext: Char;
  begin
    // The suffix letter ends the literal when the next character cannot
    // continue an identifier, so 1010B is binary and 1010BYTE is not.
    LNext := GetCharAt(AAt);
    Result := not (CharInSet(LNext, ['_', '0'..'9']) or LNext.IsLetter);
  end;

  function DigitsUntil(ASuffixAt: Integer): string;
  begin
    Result := '';
    while FOffset < ASuffixAt do
    begin
      Result := Result + GetCurChar;
      Advance;
    end;
    Advance; // suffix letter
  end;

begin
  // Assembler numeric suffixes (Assembly Expressions): H hex, B binary,
  // O octal. Scanning starts on a digit, so a hex form such as 0EBH already
  // has the leading zero the compiler requires. A suffix is recognised only
  // when every digit is legal for that base, so 2B stays a decimal integer
  // plus an identifier. Hex is tried first because B is also a hex digit
  // (10BH is $10B).
  Result := False;

  LEnd := FOffset;
  while CharInSet(GetCharAt(LEnd), ['0'..'9', 'A'..'F', 'a'..'f']) do
    Inc(LEnd);
  if (LEnd > FOffset) and CharInSet(GetCharAt(LEnd), ['H', 'h']) and
     EndsNumber(LEnd + 1) then
  begin
    LDigits := DigitsUntil(LEnd);
    AddToken(tkInteger, AStart);
    LToken := FTokens.Last;
    try
      LToken.IntegerValue := StrToInt64('$' + LDigits);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-04', 'Invalid hexadecimal literal "' + LDigits + 'H"',
          LToken.Span);
    end;
    Exit(True);
  end;

  LEnd := FOffset;
  while CharInSet(GetCharAt(LEnd), ['0', '1']) do
    Inc(LEnd);
  if (LEnd > FOffset) and CharInSet(GetCharAt(LEnd), ['B', 'b']) and
     EndsNumber(LEnd + 1) then
  begin
    LDigits := DigitsUntil(LEnd);
    AddToken(tkInteger, AStart);
    LToken := FTokens.Last;
    try
      LToken.IntegerValue := BinToInt64(LDigits);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-05', 'Invalid binary literal "' + LDigits + 'B"',
          LToken.Span);
    end;
    Exit(True);
  end;

  LEnd := FOffset;
  while CharInSet(GetCharAt(LEnd), ['0'..'7']) do
    Inc(LEnd);
  if (LEnd > FOffset) and CharInSet(GetCharAt(LEnd), ['O', 'o']) and
     EndsNumber(LEnd + 1) then
  begin
    LDigits := DigitsUntil(LEnd);
    AddToken(tkInteger, AStart);
    LToken := FTokens.Last;
    try
      LToken.IntegerValue := OctToInt64(LDigits);
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-14', 'Invalid octal literal "' + LDigits + 'O"',
          LToken.Span);
    end;
    Exit(True);
  end;
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
  if FInAsm and TryAsmSuffixedNumber(LStart) then
    Exit;
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
      // Accept full 64-bit range (e.g. UInt64($FFFFFFFFFFFFFFFF)).
      LToken.IntegerValue := Int64(StrToUInt64(LDigits));
    except
      on E: EConvertError do
        FDiagnostics.Error('DLX-07', 'Invalid integer literal "' + LDigits + '"',
          LToken.Span);
    end;
  end;
end;

procedure TDLDelphiLexer.ScanString(ADelimiter: Char);
var
  LStart: TDLSourcePos;
  LToken: TDLToken;
  LValue: string;
  LClosed: Boolean;
begin
  LStart := GetCurrentPos;
  Advance; // opening delimiter
  LValue := '';
  LClosed := False;
  while GetCurChar <> #0 do
  begin
    if GetCurChar = ADelimiter then
    begin
      if GetCharAt(FOffset + 1) = ADelimiter then
      begin
        LValue := LValue + ADelimiter;
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
  // The opening delimiter's line break is not part of the content.
  if GetCurChar = #13 then
    Advance
  else if GetCurChar = #10 then
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
          // The line break immediately before the closing delimiter is not
          // part of the content.
          if (Length(LValue) > 0) and (LValue[Length(LValue)] = #10) then
            Delete(LValue, Length(LValue), 1);
          if (Length(LValue) > 0) and (LValue[Length(LValue)] = #13) then
            Delete(LValue, Length(LValue), 1);
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
        if (GetCharAt(LStart.Offset) = '>') and (GetCurChar = '=') then
          Advance; // '>=' comparison operator
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
    begin
      if GetCharAt(FOffset + 2) = '$' then
        ScanDirective // (*$HPPEMIT ...*)  paren-style compiler directive
      else
        ScanBlockComment(LStart, trBlockComment);
    end
    else if LChar = '''' then
    begin
      if (GetCharAt(FOffset + 1) = '''') and (GetCharAt(FOffset + 2) = '''') then
      begin
        // '''' opens a multiline string only when followed by a line break;
        // otherwise it is a normal string with '' escaping.
        if CharInSet(GetCharAt(FOffset + 3), [#13, #10]) then
          ScanMultilineString
        else
          ScanString('''');
      end
      else
        ScanString('''');
    end
    else if LChar = '"' then
      ScanString('"') // double-quoted characters in asm blocks
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

{ TDLTriviaAnalyzer }

class function TDLTriviaAnalyzer.HasDirective(AToken: TDLToken): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
      Exit(True);
end;

class function TDLTriviaAnalyzer.HasConditionalStart(AToken: TDLToken): Boolean;
var
  i: Integer;
  LKind: TDLConditionDirectiveKind;
  LCond: TDLCondition;
begin
  // True when a compiler directive in the leading trivia OPENS a conditional
  // branch ({$IFDEF}, {$IFNDEF}, {$IF ...}, {$ELSE}, {$ELSEIF}). An {$ENDIF}
  // closes a branch and must not trigger body/branch continuation handling.
  // Classification goes through the shared ClassifyDirective so brace- and
  // paren-style directives behave like the other analyzer predicates.
  Result := False;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(AToken.LeadingTrivia[i].Text, LCond);
      LCond.Free;
      if LKind in [cdStart, cdElseIf, cdElse] then
        Exit(True);
    end;
end;

class function TDLTriviaAnalyzer.HasConditionalContinuation(
  AToken: TDLToken): Boolean;
var
  i: Integer;
  LKind: TDLConditionDirectiveKind;
  LCond: TDLCondition;
begin
  // True only for {$ELSE}/{$ELSEIF} directives (continuation of the CURRENT
  // conditional branch chain), never for a fresh {$IFDEF}/{$IF}.
  Result := False;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(AToken.LeadingTrivia[i].Text, LCond);
      LCond.Free;
      if LKind in [cdElseIf, cdElse] then
        Exit(True);
    end;
end;

class function TDLTriviaAnalyzer.HasBareElse(AToken: TDLToken): Boolean;
var
  i: Integer;
  LKind: TDLConditionDirectiveKind;
  LCond: TDLCondition;
begin
  // True only for a bare {$ELSE} directive (not {$ELSEIF}); the body-branch
  // loop uses this so an {$ELSEIF} (outer chain, new declaration branch)
  // stops it instead of swallowing the next function as a body branch.
  Result := False;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(AToken.LeadingTrivia[i].Text, LCond);
      LCond.Free;
      if LKind = cdElse then
        Exit(True);
    end;
end;

class function TDLTriviaAnalyzer.HasConditionalBranch(
  AToken: TDLToken): Boolean;
var
  i: Integer;
  LCond: TDLCondition;
begin
  // True when the current token carries a branch directive of an ongoing
  // conditional chain ({$ELSE}/{$ELSEIF}/{$ENDIF}); used to detect
  // shared-`end` constructs where a declaration spans a conditional
  // boundary without a clean `;`-terminated group.
  Result := False;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      if ClassifyDirective(AToken.LeadingTrivia[i].Text, LCond) in
         [cdElseIf, cdElse, cdEndIf] then
      begin
        LCond.Free;
        Exit(True);
      end
      else
        LCond.Free;
    end;
end;

class function TDLTriviaAnalyzer.LastConditionalDirective(
  AToken: TDLToken; out ACondition: TDLCondition): TDLConditionDirectiveKind;
var
  i: Integer;
  LKind: TDLConditionDirectiveKind;
  LCond: TDLCondition;
begin
  // Examine the leading trivia of the current token and return the LAST
  // conditional directive (the innermost / most recent one).
  Result := cdNone;
  ACondition := nil;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(AToken.LeadingTrivia[i].Text, LCond);
      if LKind <> cdNone then
      begin
        ACondition.Free;
        ACondition := LCond;
        Result := LKind;
      end
      else
        LCond.Free;
    end;
end;

class function TDLTriviaAnalyzer.SingleConditional(AToken: TDLToken): Boolean;
var
  i: Integer;
  LCount: Integer;
  LCond: TDLCondition;
begin
  // Nested conditionals stack several directives onto one token's trivia
  // ({$IFDEF A}{$IFDEF B} stmt ...). The flat group model cannot represent
  // that nesting, so only group when exactly one conditional directive is
  // present on the current token.
  LCount := 0;
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    if AToken.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      if ClassifyDirective(AToken.LeadingTrivia[i].Text, LCond) <> cdNone then
        Inc(LCount);
      LCond.Free;
    end;
  Result := LCount = 1;
end;

class function TDLTriviaAnalyzer.CanStartConditionalGroup(
  ATokens: TObjectList<TDLToken>; AStart: Integer;
  ADeclGroup: Boolean): Boolean;

  function Peek(AAhead: Integer): TDLToken;
  var
    LIndex: Integer;
  begin
    LIndex := AStart + AAhead;
    if LIndex < ATokens.Count then
      Result := ATokens[LIndex]
    else
      Result := ATokens.Last;
  end;

var
  i: Integer;
  LParenDepth: Integer;
  LStmtDepth: Integer;
  LTok: TDLToken;
  j: Integer;
  LKind: TDLConditionDirectiveKind;
  LCond: TDLCondition;
begin
  // A statement-level conditional group is created only when the first
  // branch is a clean, complete statement sequence: a ';' at paren depth 0
  // (and outside any open begin/case/repeat/try block) must immediately
  // precede the next branch marker ({$ELSE}/{$ELSEIF}/{$ENDIF}). Otherwise
  // the conditional lies inside a single statement (shared begin/end
  // constructs) and normal parsing keeps the first path.
  Result := False;
  LParenDepth := 0;
  LStmtDepth := 0;
  i := 0;
  while i < 100000 do
  begin
    LTok := Peek(i);
    if LTok.Kind = tkEOF then
      Exit(False);
    if LTok.LeadingTrivia.Count > 0 then
      for j := 0 to LTok.LeadingTrivia.Count - 1 do
        if LTok.LeadingTrivia[j].Kind = trDirective then
        begin
          LCond := nil;
          LKind := ClassifyDirective(LTok.LeadingTrivia[j].Text, LCond);
          LCond.Free;
          if (LKind = cdElseIf) or (LKind = cdElse) or (LKind = cdEndIf) then
          begin
            // The branch marker must follow a ';' at paren depth 0 and
            // statement depth 0. For declaration groups (type sections) the
            // first token of the next branch must also be an identifier (a
            // declaration name), not a section keyword (const/var/type) which
            // would belong to the enclosing scope; statement branches may
            // start with any token (keywords like 'end', 'if', ...).
            if (i = 0) or (LParenDepth <> 0) or (LStmtDepth <> 0) or
               (Peek(i - 1).Kind <> tkSymbol) or
               (Peek(i - 1).Text <> ';') or
               (ADeclGroup and (LKind <> cdEndIf) and
                (Peek(i).Kind <> tkIdentifier)) then
              Exit(False);
            if LKind = cdEndIf then
            begin
              Result := True;
              Exit;
            end;
            // { $ELSE}/{$ELSEIF}: keep scanning; a section keyword inside a
            // later branch (e.g. {$ELSE} ... const ... {$ENDIF}) invalidates
            // the whole group.
          end
          else if (LKind = cdStart) and (i > 0) then
            // A nested conditional opening inside the scanned range (before
            // this group's own {$ENDIF}) means a branch contains another
            // conditional group: the flat model cannot represent it, so fall
            // back to normal parsing.
            Exit(False);
        end;
    if LTok.Kind = tkKeyword then
    begin
      if (LTok.Text = 'begin') or (LTok.Text = 'case') or
         (LTok.Text = 'repeat') or (LTok.Text = 'try') or
         (LTok.Text = 'record') or (LTok.Text = 'object') or
         (LTok.Text = 'interface') or
         (LTok.Text = 'dispinterface') or
         // 'class' only opens a block when it is not a class-reference
         // ('class of') or a member prefix ('class function/procedure/var/
         // property/...'), which have no matching 'end'. 'class helper'
         // DOES open a block ('... end').
         ((LTok.Text = 'class') and not
          ((Peek(i + 1).Kind = tkKeyword) and
            ((Peek(i + 1).Text = 'of') or (Peek(i + 1).Text = 'function') or
             (Peek(i + 1).Text = 'procedure') or (Peek(i + 1).Text = 'var') or
             (Peek(i + 1).Text = 'threadvar') or
             (Peek(i + 1).Text = 'const') or (Peek(i + 1).Text = 'property') or
             (Peek(i + 1).Text = 'operator') or
             (Peek(i + 1).Text = 'constructor') or
             (Peek(i + 1).Text = 'destructor')))) then
        Inc(LStmtDepth)
      else if (LTok.Text = 'end') or (LTok.Text = 'until') then
        Dec(LStmtDepth);
    end
    else if LTok.Kind = tkSymbol then
      if LTok.Text = '(' then
        Inc(LParenDepth)
      else if LTok.Text = ')' then
        Dec(LParenDepth);
    // A section keyword directly after a ';' at depth 0 means the conditional
    // encloses more than a bare declaration (e.g. a type followed by a const
    // section): do not treat it as a declaration group.
    if (LParenDepth = 0) and (LStmtDepth = 0) and (LTok.Kind = tkKeyword) and
       (i > 0) and (Peek(i - 1).Kind = tkSymbol) and
       (Peek(i - 1).Text = ';') and
       ((LTok.Text = 'const') or (LTok.Text = 'var') or
        (LTok.Text = 'type') or (LTok.Text = 'end') or
        (LTok.Text = 'begin') or (LTok.Text = 'implementation') or
        (LTok.Text = 'initialization') or (LTok.Text = 'finalization')) then
      Exit(False);
    Inc(i);
  end;
end;

end.
