unit DX.Delphi.Conditions;

(*----------------------------------------------------------------------------
  DX.Delphi.Conditions

  Conditional-compilation model for the DX.Delphi language toolkit.

  The lexer treats conditional-compilation directives (IFDEF / IFNDEF /
  IF / ELSEIF / ELSE / ENDIF) as trivia. This unit turns the *condition*
  part of such a directive into a first-class, evaluable expression tree
  and provides a configuration (set of defined symbols) against which the
  condition can be evaluated.

  Design: the CST keeps all conditional branches as structural alternates
  (no exponential cross-product is materialised). Given a TDLDefineSet, a
  projection pass picks the first branch whose condition evaluates to true,
  which yields the active sub-tree for that configuration instantly.
  Tools such as code formatters instead consume the full branch tree plus
  the token/trivia stream, so every conditional path is preserved.

  Copyright (c) 2026
  MIT License
----------------------------------------------------------------------------*)

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Kind of a condition node.</summary>
  TDLConditionKind = (
    ckAlways,    // {$ELSE} or an empty/absent condition
    ckDefined,   // Defined(X) / {$IFDEF X}
    ckNotDefined,// not Defined(X) / {$IFNDEF X}
    ckNot,       // not <operand>
    ckAnd,       // left and right
    ckOr);       // left or right

  TDLDefineSet = class;

  /// <summary>An evaluable boolean condition over define symbols.</summary>
  TDLCondition = class
  private
    FKind: TDLConditionKind;
    FSymbol: string;
    FLeft: TDLCondition;
    FRight: TDLCondition;
    FOperand: TDLCondition;
    function GetDisplayName: string;
  public
    constructor CreateDefined(const ASymbol: string);
    constructor CreateNotDefined(const ASymbol: string);
    constructor CreateNot(AOperand: TDLCondition);
    constructor CreateAnd(ALeft, ARight: TDLCondition);
    constructor CreateOr(ALeft, ARight: TDLCondition);
    constructor CreateAlways;
    destructor Destroy; override;

    /// <summary>Evaluates the condition against a define configuration.</summary>
    function Evaluate(const ADefines: TDLDefineSet): Boolean;
    /// <summary>Human-readable form, e.g. "Defined(DEBUG) and not Defined(POSIX)".</summary>
    function ToString: string; override;

    property Kind: TDLConditionKind read FKind;
    property Symbol: string read FSymbol;
    property Left: TDLCondition read FLeft;
    property Right: TDLCondition read FRight;
    property Operand: TDLCondition read FOperand;
  end;

  /// <summary>
  ///  A case-insensitive set of defined symbols. This is the "configuration"
  ///  that selects which conditional branch is active.
  /// </summary>
  TDLDefineSet = class
  private
    FNames: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Define(const AName: string);
    procedure Undefine(const AName: string);
    function IsDefined(const AName: string): Boolean;
    function Clone: TDLDefineSet;
    function Count: Integer;
  end;

  /// <summary>
  ///  Parses the condition part of a conditional-compilation directive into
  ///  a TDLCondition tree.
  /// </summary>
  TDLConditionParser = class
  public
    /// <summary>
    ///  Accepts the whole directive text, e.g. "{$IFDEF X}", "{$IFNDEF X}",
    ///  "{$IF Defined(A) and not Defined(B)}", "{$ELSEIF Defined(C) or D}",
    ///  or "{$ELSE}". Returns nil if the text is not a conditional directive.
    /// </summary>
    class function ParseDirective(const ADirectiveText: string): TDLCondition;
  end;

implementation

{ ------------------------------------------------------------------ }
{ TDLCondition                                                       }
{ ------------------------------------------------------------------ }

constructor TDLCondition.CreateDefined(const ASymbol: string);
begin
  inherited Create;
  FKind := ckDefined;
  FSymbol := ASymbol;
end;

constructor TDLCondition.CreateNotDefined(const ASymbol: string);
begin
  inherited Create;
  FKind := ckNotDefined;
  FSymbol := ASymbol;
end;

constructor TDLCondition.CreateNot(AOperand: TDLCondition);
begin
  inherited Create;
  FKind := ckNot;
  FOperand := AOperand;
end;

constructor TDLCondition.CreateAnd(ALeft, ARight: TDLCondition);
begin
  inherited Create;
  FKind := ckAnd;
  FLeft := ALeft;
  FRight := ARight;
end;

constructor TDLCondition.CreateOr(ALeft, ARight: TDLCondition);
begin
  inherited Create;
  FKind := ckOr;
  FLeft := ALeft;
  FRight := ARight;
end;

constructor TDLCondition.CreateAlways;
begin
  inherited Create;
  FKind := ckAlways;
end;

destructor TDLCondition.Destroy;
begin
  FLeft.Free;
  FRight.Free;
  FOperand.Free;
  inherited Destroy;
end;

function TDLCondition.Evaluate(const ADefines: TDLDefineSet): Boolean;
begin
  case FKind of
    ckAlways:
      Result := True;
    ckDefined:
      Result := ADefines.IsDefined(FSymbol);
    ckNotDefined:
      Result := not ADefines.IsDefined(FSymbol);
    ckNot:
      Result := not FOperand.Evaluate(ADefines);
    ckAnd:
      Result := FLeft.Evaluate(ADefines) and FRight.Evaluate(ADefines);
    ckOr:
      Result := FLeft.Evaluate(ADefines) or FRight.Evaluate(ADefines);
  else
    Result := False;
  end;
end;

function TDLCondition.GetDisplayName: string;
begin
  case FKind of
    ckDefined: Result := 'Defined';
    ckNotDefined: Result := 'not Defined';
    ckNot: Result := 'not';
    ckAnd: Result := 'and';
    ckOr: Result := 'or';
  else
    Result := 'else';
  end;
end;

function TDLCondition.ToString: string;
begin
  case FKind of
    ckAlways:
      Result := '{$ELSE}';
    ckDefined:
      Result := 'Defined(' + FSymbol + ')';
    ckNotDefined:
      Result := 'not Defined(' + FSymbol + ')';
    ckNot:
      Result := 'not ' + FOperand.ToString;
    ckAnd:
      Result := '(' + FLeft.ToString + ' and ' + FRight.ToString + ')';
    ckOr:
      Result := '(' + FLeft.ToString + ' or ' + FRight.ToString + ')';
  else
    Result := '?';
  end;
end;

{ ------------------------------------------------------------------ }
{ TDLDefineSet                                                       }
{ ------------------------------------------------------------------ }

constructor TDLDefineSet.Create;
begin
  inherited Create;
  FNames := TDictionary<string, Boolean>.Create;
end;

destructor TDLDefineSet.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure TDLDefineSet.Define(const AName: string);
begin
  FNames.AddOrSetValue(LowerCase(AName), True);
end;

procedure TDLDefineSet.Undefine(const AName: string);
begin
  FNames.Remove(LowerCase(AName));
end;

function TDLDefineSet.IsDefined(const AName: string): Boolean;
begin
  Result := FNames.ContainsKey(LowerCase(AName));
end;

function TDLDefineSet.Clone: TDLDefineSet;
var
  LPair: TPair<string, Boolean>;
begin
  Result := TDLDefineSet.Create;
  for LPair in FNames do
    Result.FNames.Add(LPair.Key, True);
end;

function TDLDefineSet.Count: Integer;
begin
  Result := FNames.Count;
end;

{ ------------------------------------------------------------------ }
{ TDLConditionParser                                                 }
{ ------------------------------------------------------------------ }

type
  /// <summary>Internal recursive-descent parser for a condition expression.</summary>
  TConditionExprParser = class
  private
    FText: string;
    FPos: Integer;
    procedure SkipWhitespace;
    function PeekWord: string;
    function PeekWordNoAdvance: string;
    function AtEnd: Boolean;
    function ParsePrimary: TDLCondition;
    function ParseNot: TDLCondition;
    function ParseAnd: TDLCondition;
    function ParseOr: TDLCondition;
    function ParseExpression: TDLCondition;
  public
    constructor Create(const AText: string);
    function Run: TDLCondition;
  end;

constructor TConditionExprParser.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

procedure TConditionExprParser.SkipWhitespace;
begin
  while (FPos <= Length(FText)) and
        CharInSet(FText[FPos], [' ', #9, #13, #10]) do
    Inc(FPos);
end;

function TConditionExprParser.AtEnd: Boolean;
begin
  SkipWhitespace;
  Result := FPos > Length(FText);
end;

function TConditionExprParser.PeekWord: string;
var
  LStart: Integer;
begin
  SkipWhitespace;
  LStart := FPos;
  while (FPos <= Length(FText)) and
        (CharInSet(FText[FPos], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) do
    Inc(FPos);
  Result := Copy(FText, LStart, FPos - LStart);
end;

function TConditionExprParser.ParsePrimary: TDLCondition;
var
  LWord: string;
  LInner: TDLCondition;
begin
  SkipWhitespace;
  if (FPos <= Length(FText)) and (FText[FPos] = '(') then
  begin
    Inc(FPos);
    LInner := ParseOr;
    SkipWhitespace;
    if (FPos <= Length(FText)) and (FText[FPos] = ')') then
      Inc(FPos);
    Result := LInner;
    Exit;
  end;
  LWord := PeekWord;
  if SameText(LWord, 'Defined') then
  begin
    SkipWhitespace;
    if (FPos <= Length(FText)) and (FText[FPos] = '(') then
      Inc(FPos);
    LWord := PeekWord;
    SkipWhitespace;
    if (FPos <= Length(FText)) and (FText[FPos] = ')') then
      Inc(FPos);
    Result := TDLCondition.CreateDefined(LWord);
  end
  else if LWord <> '' then
    // A bare identifier is shorthand for Defined(NAME) in {$IF ...} blocks.
    Result := TDLCondition.CreateDefined(LWord)
  else
    Result := TDLCondition.CreateAlways;
end;

function TConditionExprParser.PeekWordNoAdvance: string;
var
  LPos: Integer;
begin
  LPos := FPos;
  while (LPos <= Length(FText)) and
        CharInSet(FText[LPos], [' ', #9, #13, #10]) do
    Inc(LPos);
  Result := '';
  while (LPos <= Length(FText)) and
        CharInSet(FText[LPos], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Result := Result + FText[LPos];
    Inc(LPos);
  end;
end;

function TConditionExprParser.ParseNot: TDLCondition;
var
  LWord: string;
  LOperand: TDLCondition;
begin
  if SameText(PeekWordNoAdvance, 'not') then
  begin
    PeekWord; // consume 'not'
    LOperand := ParseNot;
    Result := TDLCondition.CreateNot(LOperand);
  end
  else
    Result := ParsePrimary;
end;

function TConditionExprParser.ParseAnd: TDLCondition;
var
  LLeft: TDLCondition;
  LRight: TDLCondition;
begin
  LLeft := ParseNot;
  while True do
  begin
    if SameText(PeekWordNoAdvance, 'and') then
    begin
      PeekWord; // consume 'and'
      LRight := ParseNot;
      LLeft := TDLCondition.CreateAnd(LLeft, LRight);
    end
    else
      Break;
  end;
  Result := LLeft;
end;

function TConditionExprParser.ParseOr: TDLCondition;
var
  LLeft: TDLCondition;
  LRight: TDLCondition;
begin
  LLeft := ParseAnd;
  while True do
  begin
    if SameText(PeekWordNoAdvance, 'or') then
    begin
      PeekWord; // consume 'or'
      LRight := ParseAnd;
      LLeft := TDLCondition.CreateOr(LLeft, LRight);
    end
    else
      Break;
  end;
  Result := LLeft;
end;

function TConditionExprParser.ParseExpression: TDLCondition;
begin
  Result := ParseOr;
end;

function TConditionExprParser.Run: TDLCondition;
begin
  Result := ParseExpression;
end;

class function TDLConditionParser.ParseDirective(
  const ADirectiveText: string): TDLCondition;
var
  LText: string;
  LInner: string;
  LStart, LPos: Integer;
  LWord: string;
  LParser: TConditionExprParser;
begin
  Result := nil;
  LText := Trim(ADirectiveText);
  if (Length(LText) < 4) or (LText[1] <> '{') or (LText[Length(LText)] <> '}') then
    Exit;
  LInner := Trim(Copy(LText, 2, Length(LText) - 2));
  if (Length(LInner) < 2) or (LInner[1] <> '$') then
    Exit;
  LInner := Trim(Copy(LInner, 2, Length(LInner) - 1));
  LPos := 1;
  while (LPos <= Length(LInner)) and
        CharInSet(LInner[LPos], ['A'..'Z', 'a'..'z']) do
    Inc(LPos);
  LWord := Copy(LInner, 1, LPos - 1);
  if SameText(LWord, 'IFDEF') or SameText(LWord, 'IFNDEF') then
  begin
    while (LPos <= Length(LInner)) and
          CharInSet(LInner[LPos], [' ', #9, #13, #10]) do
      Inc(LPos);
    LStart := LPos;
    while (LPos <= Length(LInner)) and
          CharInSet(LInner[LPos], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      Inc(LPos);
    if SameText(LWord, 'IFDEF') then
      Result := TDLCondition.CreateDefined(Copy(LInner, LStart, LPos - LStart))
    else
      Result := TDLCondition.CreateNotDefined(Copy(LInner, LStart, LPos - LStart));
  end
  else if SameText(LWord, 'IF') then
  begin
    LParser := TConditionExprParser.Create(Copy(LInner, LPos, Length(LInner)));
    try
      Result := LParser.Run;
    finally
      LParser.Free;
    end;
  end
  else if SameText(LWord, 'ELSEIF') then
  begin
    LParser := TConditionExprParser.Create(Copy(LInner, LPos, Length(LInner)));
    try
      Result := LParser.Run;
    finally
      LParser.Free;
    end;
  end
  else if SameText(LWord, 'ELSE') then
    Result := TDLCondition.CreateAlways;
end;

end.
