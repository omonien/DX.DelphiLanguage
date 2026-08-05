/// <summary>
///   DX.Delphi.Parser — recursive-descent parser producing a concrete syntax
///   tree (CST) for the Delphi language surface of Delphi 13.x.
/// </summary>
/// <remarks>
///   The parser consumes the flat token stream produced by TDLDelphiLexer
///   (trivia has already been attached to the significant tokens) and builds
///   a TDLCompilationUnit tree. It is deliberately tolerant: unknown or
///   malformed constructs produce diagnostics and the parser skips ahead to
///   a safe resynchronisation point instead of aborting.
///
///   Supported grammar (Delphi 13.x):
///     - programs, units, libraries and packages (uses/requires/contains)
///     - interface + implementation sections with all declaration sections
///       (type/const/var/threadvar/resourcestring/label/exports)
///     - classes, records (incl. variant parts), helpers, interfaces,
///       dispinterfaces, object types, procedural types, generics
///     - methods with the full directive surface, properties, fields
///     - the complete statement and expression grammar, including inline var
///       declarations, anonymous methods and generic instantiation.
///
///   Design notes:
///     - T(x) casts parse as ordinary calls (syntactically identical).
///     - Default(T), SizeOf etc. parse as ordinary calls.
///     - Generic instantiation 'TList&lt;Integer&gt;' is disambiguated from the
///       less-than comparison by speculative parsing (position save/restore).
///     - Conditional compilation is not evaluated; every branch is parsed.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit DX.Delphi.Parser;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Delphi.Core,
  DX.Delphi.Lexer,
  DX.Delphi.CST,
  DX.Delphi.Conditions;

type
  /// <summary>Item parser used inside a declaration conditional group.</summary>
  TDLDeclItemParser = function: TDLNode of object;

  /// <summary>Recursive-descent parser: token stream -> CST.</summary>
  TDLDelphiParser = class
  private
    FTokens: TObjectList<TDLToken>;
    FPos: Integer;
    FDiagnostics: TDLDiagnostics;
    FSource: string;
    FCurrentVisibility: TDLVisibility;
    FCurrentStrict: Boolean;
    FSuppressCount: Integer;
    FConditionalDepth: Integer;
    FSteps: Integer;
    FCompoundGuard: Integer;
    FStmtDepth: Integer;
    FDirectiveStmt: Boolean;
    function GetCur: TDLToken;
    function GetKind: TDLTokenKind;
    function GetKeyword: TDLKeyword;
    function GetText: string;
    function GetSpan: TDLSourceSpan;
    function Peek(AAhead: Integer): TDLToken;
    procedure Advance;
    function IsKeyword(AKeyword: TDLKeyword): Boolean;
    function IsKwAhead(AKeyword: TDLKeyword; AAhead: Integer): Boolean;
    function IsIdentifier: Boolean;
    function IsSoftNameKeyword: Boolean;
    function IsSymbol(const ASymbol: string): Boolean;
    function IsSymbolAhead(const ASymbol: string; AAhead: Integer): Boolean;
    procedure ExpectSymbol(const ASymbol: string);
    procedure ExpectKeyword(AKeyword: TDLKeyword);
    procedure ExpectSemicolon;
    procedure Error(const AMessage: string);
    procedure Warning(const AMessage: string);
    function MakeIdentifier: TDLIdentifier;
    function MakeIdentifierFromToken(AToken: TDLToken): TDLIdentifier;
    procedure ExpandDottedName(var AName: TDLIdentifier);
    function TakeTrivia(AToken: TDLToken; ANode: TDLNode): TDLNode;
    procedure TakeLeadingTrivia(ANode: TDLNode);
    function TakeTriviaCopy: TList<TDLTrivia>;
    function HasDirectiveTrivia: Boolean;
    function HasConditionalStartTrivia: Boolean;
    function HasConditionalContinuationTrivia: Boolean;
    function HasConditionalBranchTrivia: Boolean;
    procedure SkipConditionalBranchesToEndIf;
    function LastConditionalDirective(out ACondition: TDLCondition)
      : TDLConditionDirectiveKind;
    function FirstConditionalDirective(out ACondition: TDLCondition)
      : TDLConditionDirectiveKind;
    function CanStartConditionalGroup(ADeclGroup: Boolean): Boolean;
    function SingleConditionalInTrivia: Boolean;
    function ParseConditionalStatementGroup: TDLConditionalStmt;
    function ParseConditionalDeclGroup(
      AItemParser: TDLDeclItemParser): TDLConditionalGroup;
    function ParseTypeDeclNode: TDLNode;
    function ParseConstDeclNode: TDLNode;
    function ParseVarDeclNode: TDLNode;
    function IsQualifiedFollowedByDotDot: Boolean;
    function SectionLeadsToBody: Boolean;
    procedure SkipConditionalExpressionBranches;
    procedure SkipUntil(const AKeywords: array of TDLKeyword);
    procedure SkipToSemicolon;

    // Declarations
    function ParseCompilationUnit: TDLCompilationUnit;
    function ParseUsesClause: TDLUsesClause;
    function ParseDeclItem(AAllowBodies: Boolean): TDLNode;
    function ParseTypeSection: TDLTypeSection;
    function ParseConstSection: TDLConstSection;
    function ParseResStringSection: TDLResStringSection;
    function ParseVarSection(AIsThreadVar: Boolean): TDLVarSection;
    function ParseLabelSection: TDLLabelSection;
    function ParseExportsClause: TDLExportsClause;
    function ParseAttributes: TList<TDLAttribute>;
    function ParseAttribute: TDLAttribute;
    function ParseTypeDecl: TDLTypeDecl;
    function ParseConstDecl: TDLConstDecl;
    function ParseVarDecl: TDLVarDecl;

    // Types
    function ParseTypeExpr: TDLTypeExpr;
    function ParseNamedType: TDLNamedType;
    function ParseTypeParams(ANames: TList<TDLIdentifier>): Boolean;
    function ParseEnumOrSubrange: TDLTypeExpr;
    function ParseSubrangeType: TDLSubrangeType;
    function ParseRecordType: TDLRecordType;
    function ParseRecordHelper: TDLTypeExpr;
    function ParseVariantSection: TDLVariantSection;
    function ParseClassLike(AKind: TDLProgramKind): TDLTypeExpr;
    function ParseProceduralType: TDLProceduralType;
    function ParseParameterList: TList<TDLParameter>;
    function ParseParameter: TDLParameter;
    function ParseTypeArgs: TList<TDLTypeArg>;
    function ParseTypeArg: TDLTypeArg;
    function ParseMemberSection(AMembers: TList<TDLMember>): Boolean;
    function ParseFieldDecl: TDLFieldDecl;
    function ParseFieldDeclBody: TDLFieldDecl;
    function ParseMethodHeader(AKind: TDLProcKind; AClassModifier: TDLClassModifier;
      AAllowBody: Boolean): TDLProcedureBase;
    function ParseMethodDirectives(ADirectives: TList<TDLDirective>): Boolean;
    function IsMethodDirectiveStart: Boolean;
    procedure ParseMethodDirectivesAndSemicolons(
      ADirectives: TList<TDLDirective>);
    function ParsePropertyDecl: TDLPropertyDecl;
    function ParseVisibility: TDLVisibility;

    // Statements
    function ParseStatementList(ATerminators: TArray<TDLKeyword>): TList<TDLStatement>;
    function ParseStatement: TDLStatement;
    function ParseCompoundStmt: TDLCompoundStmt;
    function ParseIfStmt: TDLIfStmt;
    function ParseCaseStmt: TDLCaseStmt;
    function ParseForStmt: TDLForStmt;
    function ParseWhileStmt: TDLWhileStmt;
    function ParseRepeatStmt: TDLRepeatStmt;
    function ParseWithStmt: TDLWithStmt;
    function ParseTryStmt: TDLTryStmt;
    function ParseRaiseStmt: TDLRaiseStmt;
    function ParseGotoStmt: TDLGotoStmt;
    function ParseAsmStmt: TDLAsmStmt;
    function ParseLabelStmt: TDLLabelStmt;
    function ParseVarDeclStmt: TDLVarDeclStmt;

    // Expressions
    function ParseExpression: TDLExpr;
    function ParseBinary(AMinPrec: Integer): TDLExpr;
    function ParseUnary: TDLExpr;
    function ParsePostfix: TDLExpr;
    function ParsePrimary: TDLExpr;
    function ParseCallArgs: TList<TDLExpr>;
    function ParseSetOrArrayConstructor: TDLExpr;
    function ParseStringSequence: TDLStringExpr;
    function ParseAnonymousMethod: TDLAnonymousMethodExpr;
    function GetBinaryOp(out AOperator: TDLBinaryOp; out AText: string;
      out APrecedence: Integer): Boolean;
    function IsCaseLabelStart: Boolean;
  public
    constructor Create(ATokens: TObjectList<TDLToken>; ADiagnostics: TDLDiagnostics;
      const ASource: string);
    /// <summary>Parses the whole token stream into a compilation unit.</summary>
    function Parse: TDLCompilationUnit;
    property Diagnostics: TDLDiagnostics read FDiagnostics;
  end;

implementation


type
  TDLTypeSectionKind = (
    tskType,
    tskConst,
    tskVar,
    tskResString,
    tskLabel
  );

function TDLDelphiParser.GetCur: TDLToken;
begin
  if FPos < FTokens.Count then
    Result := FTokens[FPos]
  else
    Result := FTokens.Last;
end;

function TDLDelphiParser.GetKind: TDLTokenKind;
begin
  Result := GetCur.Kind;
end;

function TDLDelphiParser.GetKeyword: TDLKeyword;
begin
  if GetKind = tkKeyword then
    Result := TDLKeywords.ToKeyword(GetCur.Text)
  else
    Result := kwNone;
end;

function TDLDelphiParser.GetText: string;
begin
  Result := GetCur.Text;
end;

function TDLDelphiParser.GetSpan: TDLSourceSpan;
begin
  Result := GetCur.Span;
end;

function TDLDelphiParser.Peek(AAhead: Integer): TDLToken;
var
  LIndex: Integer;
begin
  LIndex := FPos + AAhead;
  if LIndex < FTokens.Count then
    Result := FTokens[LIndex]
  else
    Result := FTokens.Last;
end;

procedure TDLDelphiParser.Advance;
begin
  Inc(FSteps);
  // Defensive guard against runaway loops on pathological input.
  if FSteps > 50000000 then
    raise Exception.Create('DLP-FATAL: parser step limit exceeded');
  if FPos < FTokens.Count - 1 then
    Inc(FPos);
end;

function TDLDelphiParser.IsKeyword(AKeyword: TDLKeyword): Boolean;
begin
  Result := GetKeyword = AKeyword;
end;

function TDLDelphiParser.IsKwAhead(AKeyword: TDLKeyword; AAhead: Integer): Boolean;
begin
  Result := (Peek(AAhead).Kind = tkKeyword) and
    (TDLKeywords.ToKeyword(Peek(AAhead).Text) = AKeyword);
end;

function TDLDelphiParser.IsIdentifier: Boolean;
begin
  Result := GetKind = tkIdentifier;
end;

function TDLDelphiParser.IsSoftNameKeyword: Boolean;
begin
  // Contextual/directive keywords that Delphi allows as identifiers.
  Result := IsKeyword(kwIndex) or IsKeyword(kwName) or IsKeyword(kwOn) or
    IsKeyword(kwAt) or IsKeyword(kwBreak) or IsKeyword(kwContinue) or
    IsKeyword(kwRef) or IsKeyword(kwHelper) or IsKeyword(kwOperator) or
    IsKeyword(kwDefault) or IsKeyword(kwImplements) or IsKeyword(kwRead) or
    IsKeyword(kwWrite) or IsKeyword(kwStored) or IsKeyword(kwReadOnly) or
    IsKeyword(kwWriteOnly) or IsKeyword(kwMessage) or IsKeyword(kwDeprecated) or
    IsKeyword(kwExternal) or IsKeyword(kwForward) or IsKeyword(kwVirtual) or
    IsKeyword(kwDynamic) or IsKeyword(kwOverride) or IsKeyword(kwOverload) or
    IsKeyword(kwReintroduce) or IsKeyword(kwAbstract) or IsKeyword(kwFinal) or
    IsKeyword(kwSealed) or IsKeyword(kwInline) or IsKeyword(kwStatic) or
    IsKeyword(kwAssembler) or IsKeyword(kwRegister) or IsKeyword(kwPascal) or
    IsKeyword(kwCdecl) or IsKeyword(kwStdcall) or IsKeyword(kwSafecall) or
    IsKeyword(kwPlatform) or IsKeyword(kwExperimental) or IsKeyword(kwUnsafe) or
    IsKeyword(kwVarargs) or IsKeyword(kwNear) or IsKeyword(kwFar) or
    IsKeyword(kwAutomated) or IsKeyword(kwDispInterface) or
    IsKeyword(kwContains) or IsKeyword(kwRequires) or IsKeyword(kwPackage) or
    IsKeyword(kwString) or
    IsKeyword(kwNoReturn) or IsKeyword(kwReference);
end;

function TDLDelphiParser.IsSymbol(const ASymbol: string): Boolean;
begin
  Result := (GetKind = tkSymbol) and (GetText = ASymbol);
end;

function TDLDelphiParser.IsSymbolAhead(const ASymbol: string;
  AAhead: Integer): Boolean;
begin
  Result := (Peek(AAhead).Kind = tkSymbol) and (Peek(AAhead).Text = ASymbol);
end;

procedure TDLDelphiParser.ExpectSymbol(const ASymbol: string);
begin
  if IsSymbol(ASymbol) then
    Advance
  else
    Error(Format('Expected "%s" but found "%s"', [ASymbol, GetCur.Text]));
end;

procedure TDLDelphiParser.ExpectKeyword(AKeyword: TDLKeyword);
begin
  if IsKeyword(AKeyword) then
    Advance
  else
    Error(Format('Expected "%s" but found "%s"',
      [TDLKeywords.ToText(AKeyword), GetCur.Text]));
end;

procedure TDLDelphiParser.ExpectSemicolon;
begin
  if IsSymbol(';') then
    Advance
  else
    Error(Format('Expected ";" but found "%s"', [GetCur.Text]));
end;

procedure TDLDelphiParser.Error(const AMessage: string);
begin
  if FSuppressCount = 0 then
    FDiagnostics.Error('DLP-01', AMessage, GetSpan);
  Advance;
end;

procedure TDLDelphiParser.Warning(const AMessage: string);
begin
  if FSuppressCount = 0 then
    FDiagnostics.Warning('DLP-02', AMessage, GetSpan);
end;

function TDLDelphiParser.MakeIdentifierFromToken(AToken: TDLToken): TDLIdentifier;
begin
  Result := TDLIdentifier.Create(AToken.Value, AToken.Span,
    (Length(AToken.Text) > 0) and (AToken.Text[1] = '&'));
end;

procedure TDLDelphiParser.ExpandDottedName(var AName: TDLIdentifier);
var
  LFullName: string;
begin
  LFullName := AName.Name;
  while IsSymbol('.') do
  begin
    Advance;
    if IsIdentifier or (GetKind = tkKeyword) then
    begin
      AName.Free;
      AName := MakeIdentifier;
      LFullName := LFullName + '.' + AName.Name;
    end
    else
      Error('Expected unit name segment after "."');
  end;
  AName.SetName(LFullName);
end;

function TDLDelphiParser.MakeIdentifier: TDLIdentifier;
begin
  // Keywords are accepted as identifiers: Delphi treats many reserved words
  // as valid member/type names contextually (property Name, type TOn, ...).
  if IsIdentifier or (GetKind = tkKeyword) then
  begin
    Result := MakeIdentifierFromToken(GetCur);
    Advance;
  end
  else
  begin
    Result := TDLIdentifier.Create(GetCur.Text, GetSpan);
    Error(Format('Expected identifier but found "%s"', [GetCur.Text]));
  end;
end;

function TDLDelphiParser.TakeTrivia(AToken: TDLToken; ANode: TDLNode): TDLNode;
var
  i: Integer;
begin
  for i := 0 to AToken.LeadingTrivia.Count - 1 do
    ANode.LeadingTrivia.Add(AToken.LeadingTrivia[i]);
  Result := ANode;
end;

procedure TDLDelphiParser.TakeLeadingTrivia(ANode: TDLNode);
var
  i: Integer;
begin
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    ANode.LeadingTrivia.Add(GetCur.LeadingTrivia[i]);
end;

function TDLDelphiParser.TakeTriviaCopy: TList<TDLTrivia>;
var
  i: Integer;
begin
  Result := TList<TDLTrivia>.Create;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    Result.Add(GetCur.LeadingTrivia[i]);
end;

function TDLDelphiParser.HasDirectiveTrivia: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
      Exit(True);
end;

function TDLDelphiParser.HasConditionalStartTrivia: Boolean;
var
  i: Integer;
  LText: string;
begin
  // True when a compiler directive in the leading trivia OPENS a conditional
  // branch ({$IFDEF}, {$IFNDEF}, {$IF ...}, {$ELSE}, {$ELSEIF}). An {$ENDIF}
  // closes a branch and must not trigger body/branch continuation handling.
  Result := False;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LText := LowerCase(Trim(GetCur.LeadingTrivia[i].Text));
      if (Pos('{$ifdef', LText) = 1) or (Pos('{$ifndef', LText) = 1) or
         (Pos('{$if ', LText) = 1) or (Pos('{$if(', LText) = 1) or
         (Pos('{$else', LText) = 1) then
        Exit(True);
    end;
end;

function TDLDelphiParser.HasConditionalContinuationTrivia: Boolean;
var
  i: Integer;
  LText: string;
begin
  // True only for {$ELSE}/{$ELSEIF} directives (continuation of the CURRENT
  // conditional branch chain), never for a fresh {$IFDEF}/{$IF}.
  Result := False;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LText := LowerCase(Trim(GetCur.LeadingTrivia[i].Text));
      if Pos('{$else', LText) = 1 then
        Exit(True);
    end;
end;

function TDLDelphiParser.IsQualifiedFollowedByDotDot: Boolean;
var
  LIndex: Integer;
  LDepth: Integer;
begin
  // Current token is an identifier; skip ".segment" pairs and balanced
  // "(...)" calls, then check whether the next token is ".." (subrange with
  // qualified/call endpoints: TEnum.Member..TEnum.Member, Low(X)..High(X)).
  LIndex := 1;
  while (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '.') and
        ((Peek(LIndex + 1).Kind = tkIdentifier) or
         (Peek(LIndex + 1).Kind = tkKeyword)) do
    Inc(LIndex, 2);
  if (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '(') then
  begin
    LDepth := 0;
    while (Peek(LIndex).Kind <> tkEOF) do
    begin
      if (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '(') then
        Inc(LDepth)
      else if (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = ')') then
      begin
        Dec(LDepth);
        if LDepth = 0 then
        begin
          Inc(LIndex);
          Break;
        end;
      end;
      Inc(LIndex);
    end;
  end;
  Result := (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '..');
end;

function TDLDelphiParser.LastConditionalDirective(
  out ACondition: TDLCondition): TDLConditionDirectiveKind;
var
  i: Integer;
  LKind: TDLConditionDirectiveKind;
  LCond: TDLCondition;
begin
  // Examine the leading trivia of the current token and return the LAST
  // conditional directive (the innermost / most recent one).
  Result := cdNone;
  ACondition := nil;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(GetCur.LeadingTrivia[i].Text, LCond);
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

function TDLDelphiParser.HasConditionalBranchTrivia: Boolean;
var
  i: Integer;
  LCond: TDLCondition;
begin
  // True when the current token carries a branch directive of an ongoing
  // conditional chain ({$ELSE}/{$ELSEIF}/{$ENDIF}); used to detect
  // shared-`end` constructs where a declaration spans a conditional
  // boundary without a clean `;`-terminated group.
  Result := False;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      if ClassifyDirective(GetCur.LeadingTrivia[i].Text, LCond) in
         [cdElseIf, cdElse, cdEndIf] then
      begin
        LCond.Free;
        Exit(True);
      end
      else
        LCond.Free;
    end;
end;

procedure TDLDelphiParser.SkipConditionalBranchesToEndIf;
var
  LDepth: Integer;
  i: Integer;
  LCond: TDLCondition;
  LKind: TDLConditionDirectiveKind;
  LHaveSkip: Boolean;
  LFirst: Boolean;
begin
  // The current token starts or continues an "unmanaged" conditional (one
  // that was not recognised as a clean group, e.g. a shared-`end` construct
  // or a conditional-compiled expression). Skip the remaining branches up to
  // the matching {$ENDIF} so the enclosing statement/declaration resumes
  // after it. If the token only carries the closing {$ENDIF} of a branch that
  // was already parsed, there is nothing to skip.
  LHaveSkip := False;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(GetCur.LeadingTrivia[i].Text, LCond);
      LCond.Free;
      if LKind in [cdStart, cdElseIf, cdElse] then
      begin
        LHaveSkip := True;
        Break;
      end;
    end;
  if not LHaveSkip then
    Exit;
  LDepth := 1;
  LFirst := True;
  while GetKind <> tkEOF do
  begin
    for i := 0 to GetCur.LeadingTrivia.Count - 1 do
      if GetCur.LeadingTrivia[i].Kind = trDirective then
      begin
        LCond := nil;
        LKind := ClassifyDirective(GetCur.LeadingTrivia[i].Text, LCond);
        LCond.Free;
        if LKind = cdStart then
        begin
          // The start directive on the very first token belongs to the
          // conditional we are skipping (already counted in LDepth := 1).
          if not LFirst then
            Inc(LDepth);
        end
        else if LKind = cdEndIf then
        begin
          Dec(LDepth);
          if LDepth = 0 then
            Exit; // current token stays; its {$ENDIF} closes this conditional
        end;
      end;
    LFirst := False;
    Advance;
  end;
end;

function TDLDelphiParser.FirstConditionalDirective(
  out ACondition: TDLCondition): TDLConditionDirectiveKind;
var
  i: Integer;
  LCond: TDLCondition;
  LKind: TDLConditionDirectiveKind;
begin
  // Examine the leading trivia of the current token and return the FIRST
  // conditional directive (the outermost one). Inside a conditional group
  // loop this is the directive that belongs to the group itself; later
  // directives on the same token belong to nested groups that the enclosing
  // parsing level will handle.
  Result := cdNone;
  ACondition := nil;
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      LKind := ClassifyDirective(GetCur.LeadingTrivia[i].Text, LCond);
      if LKind <> cdNone then
      begin
        ACondition := LCond;
        Result := LKind;
        Exit;
      end
      else
        LCond.Free;
    end;
end;

function TDLDelphiParser.CanStartConditionalGroup(ADeclGroup: Boolean): Boolean;
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
         (LTok.Text = 'record') or (LTok.Text = 'class') or
         (LTok.Text = 'interface') or (LTok.Text = 'object') or
         (LTok.Text = 'dispinterface') then
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

function TDLDelphiParser.SingleConditionalInTrivia: Boolean;
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
  for i := 0 to GetCur.LeadingTrivia.Count - 1 do
    if GetCur.LeadingTrivia[i].Kind = trDirective then
    begin
      LCond := nil;
      if ClassifyDirective(GetCur.LeadingTrivia[i].Text, LCond) <> cdNone then
        Inc(LCount);
      LCond.Free;
    end;
  Result := LCount = 1;
end;

function TDLDelphiParser.ParseConditionalStatementGroup: TDLConditionalStmt;
var
  LGroup: TDLConditionalStmt;
  LBranch: TDLConditionalBranch;
  LStartDepth: Integer;
  LDir: TDLConditionDirectiveKind;
  LCond: TDLCondition;
  LStatement: TDLStatement;
  LSkipCheck: Boolean;
  LGuard: Integer;
  LPrevPos: Integer;
begin
  // Current token carries a conditional-start directive in its trivia.
  LStartDepth := FConditionalDepth;
  Inc(FConditionalDepth);
  LGroup := TDLConditionalStmt.Create(GetSpan);
  LCond := nil;
  LastConditionalDirective(LCond);
  LBranch := TDLConditionalBranch.Create(GetSpan, LCond);
  LGroup.Branches.Add(LBranch);
  LSkipCheck := True; // the opening directive belongs to this group
  LGuard := 0;
  while True do
  begin
    Inc(LGuard);
    if LGuard > 1000000 then
      raise Exception.Create('DLP-FATAL: conditional group loop at "' +
        GetText + '"');
    if GetKind = tkEOF then
    begin
      // Unterminated conditional group (missing {$ENDIF}).
      Error('Unterminated conditional group');
      Dec(FConditionalDepth);
      Break;
    end;
    LDir := cdNone;
    LCond := nil;
    if not LSkipCheck then
      LDir := LastConditionalDirective(LCond);
    LSkipCheck := False;
    if LDir = cdEndIf then
    begin
      LCond.Free;
      Dec(FConditionalDepth);
      Break; // the {$ENDIF} trivia remains attached to the following token
    end;
    if (LDir = cdElseIf) or (LDir = cdElse) then
    begin
      // A new branch starts at this token; the directive is its condition.
      LBranch := TDLConditionalBranch.Create(GetSpan, LCond);
      LGroup.Branches.Add(LBranch);
      LSkipCheck := True; // do not re-interpret this token's directive
      Continue;
    end;
    LCond.Free;
    if (LDir = cdStart) and CanStartConditionalGroup(False) then
      LStatement := ParseConditionalStatementGroup // nested group
    else if LDir = cdStart then
      LStatement := ParseStatement // conditional inside a single statement
    else
      LStatement := ParseStatement;
    LPrevPos := FPos;
    if LStatement <> nil then
      LBranch.Statements.Add(LStatement);
    if IsSymbol(';') then
      Advance;
    if (FPos = LPrevPos) and (LStatement = nil) and (not IsSymbol(';')) then
      Advance; // resynchronise on an unexpected terminator/block keyword
  end;
  Result := LGroup;
end;

function TDLDelphiParser.ParseConditionalDeclGroup(
  AItemParser: TDLDeclItemParser): TDLConditionalGroup;
var
  LGroup: TDLConditionalGroup;
  LBranch: TDLConditionalDeclBranch;
  LDir: TDLConditionDirectiveKind;
  LCond: TDLCondition;
  LSkipCheck: Boolean;
  LPrevPos: Integer;
  LFoundEndIf: Boolean;
  j: Integer;
begin
  // Current token carries a conditional-start directive; the following
  // declarations (types, consts, vars ...) form a conditional group with one
  // branch per path. AItemParser parses one declaration of the section kind.
  LGroup := TDLConditionalGroup.Create(GetSpan);
  LCond := nil;
  LastConditionalDirective(LCond);
  LBranch := TDLConditionalDeclBranch.Create(GetSpan, LCond);
  LGroup.Branches.Add(LBranch);
  LSkipCheck := True; // the opening directive belongs to this group
  while True do
  begin
    if GetKind = tkEOF then
    begin
      Error('Unterminated conditional declaration group');
      Break;
    end;
    // Process every conditional directive on the current token in source
    // order (outermost first). A token may carry several directives at once
    // (e.g. {$ELSE}{$MESSAGE}{$ENDIF} or {$ENDIF}{$IFDEF ...}); the group
    // must not stop after the first one or it will miss its own {$ENDIF}.
    LFoundEndIf := False;
    if not LSkipCheck then
      for j := 0 to GetCur.LeadingTrivia.Count - 1 do
        if GetCur.LeadingTrivia[j].Kind = trDirective then
        begin
          LCond := nil;
          LDir := ClassifyDirective(GetCur.LeadingTrivia[j].Text, LCond);
          if LDir = cdEndIf then
          begin
            LCond.Free;
            LFoundEndIf := True;
            Break;
          end;
          if (LDir = cdElseIf) or (LDir = cdElse) then
          begin
            LBranch := TDLConditionalDeclBranch.Create(GetSpan, LCond);
            LGroup.Branches.Add(LBranch);
          end
          else
            LCond.Free;
        end;
    LSkipCheck := False;
    if LFoundEndIf then
      Break;
    if (GetKind = tkIdentifier) or IsSoftNameKeyword then
    begin
      LPrevPos := FPos;
      LBranch.Items.Add(AItemParser);
      if FPos = LPrevPos then
        Advance; // resynchronise
    end
    else if IsSymbol(';') then
      Advance
    else
      Advance; // resynchronise on an unexpected token
  end;
  Result := LGroup;
end;

function TDLDelphiParser.SectionLeadsToBody: Boolean;
var
  i: Integer;
  LInHeader: Boolean;
  LDepth: Integer;
begin
  // Scan (bounded) from the current token; if a body keyword (begin/asm)
  // appears before a new declaration keyword, the section belongs to a
  // method body branch. Used to decide whether a fresh {$IFDEF}-introduced
  // section continues the current body or is a new enclosing-scope section.
  Result := False;
  LInHeader := (Peek(0).Kind = tkKeyword) and
               ((Peek(0).Text = 'procedure') or (Peek(0).Text = 'function'));
  LDepth := 0;
  for i := 0 to 100 do
  begin
    if Peek(i).Kind = tkEOF then
      Exit;
    if LInHeader then
    begin
      // Skip the method header up to its terminating ';' at paren depth 0.
      if (Peek(i).Kind = tkSymbol) and (Peek(i).Text = '(') then
        Inc(LDepth)
      else if (Peek(i).Kind = tkSymbol) and (Peek(i).Text = ')') then
        Dec(LDepth)
      else if (Peek(i).Kind = tkSymbol) and (Peek(i).Text = ';') and
              (LDepth = 0) then
        LInHeader := False;
      Continue;
    end;
    if Peek(i).Kind = tkKeyword then
      if (Peek(i).Text = 'begin') or (Peek(i).Text = 'asm') then
        Exit(True)
      else if (Peek(i).Text = 'function') or (Peek(i).Text = 'procedure') or
              (Peek(i).Text = 'end') or (Peek(i).Text = 'class') or
              (Peek(i).Text = 'interface') or (Peek(i).Text = 'type') then
        Exit(False);
  end;
end;

procedure TDLDelphiParser.SkipConditionalExpressionBranches;
begin
  // A branch may be terminated by a semicolon before the next branch's
  // continuation operator:
  //   X := A or B; {$ELSE} or C; {$ENDIF}
  if IsSymbol(';') then
    Advance;
  // An expression may continue over conditional-compilation branches:
  //   X := A
  // {$IFDEF Y} or B; {$ELSE} or C; {$ENDIF}
  while HasConditionalStartTrivia and
        (IsKeyword(kwOr) or IsKeyword(kwAnd) or IsKeyword(kwXor) or
         IsKeyword(kwDiv) or IsKeyword(kwMod) or IsKeyword(kwShl) or
         IsKeyword(kwShr) or IsSymbol('+') or IsSymbol('-') or
         IsSymbol('*') or IsSymbol('/') or IsSymbol('=') or
         IsSymbol('>') or IsSymbol('<') or IsSymbol('>=') or
         IsSymbol('<=') or IsSymbol('<>')) do
  begin
    Advance; // the continuation operator begins the alternate branch
    ParseExpression.Free;
    if IsSymbol(';') then
      Advance
    else
      Break;
  end;
end;

procedure TDLDelphiParser.SkipUntil(const AKeywords: array of TDLKeyword);
var
  i: Integer;
  LFound: Boolean;
begin
  while GetKind <> tkEOF do
  begin
    LFound := False;
    for i := Low(AKeywords) to High(AKeywords) do
      if IsKeyword(AKeywords[i]) then
      begin
        LFound := True;
        Break;
      end;
    if LFound then
      Exit;
    Advance;
  end;
end;

procedure TDLDelphiParser.SkipToSemicolon;
begin
  while (GetKind <> tkEOF) and (not IsSymbol(';')) do
    Advance;
  if IsSymbol(';') then
    Advance;
end;

{ ------------------------------------------------------------------ }
{ Top level                                                           }
{ ------------------------------------------------------------------ }

function TDLDelphiParser.ParseCompilationUnit: TDLCompilationUnit;
var
  LStart: TDLSourceSpan;
  LKind: TDLProgramKind;
  LName: TDLIdentifier;
  LUnit: TDLCompilationUnit;
  LInInterface: Boolean;
  LItem: TDLNode;
  LBody: TDLStatement;
  LSpan: TDLSourceSpan;
  LProgramParams: TList<TDLIdentifier>;
  LStatements: TList<TDLStatement>;
  LStatement: TDLStatement;
  LPrevPos: Integer;
begin
  LStart := GetSpan;
  LProgramParams := TList<TDLIdentifier>.Create;
  if IsKeyword(kwProgram) then
  begin
    Advance;
    LKind := pkProgram;
    LName := MakeIdentifier;
    ExpandDottedName(LName);
    if IsSymbol('(') then
    begin
      Advance;
      while not IsSymbol(')') do
      begin
        if GetKind = tkEOF then
          Break;
        if IsIdentifier then
          LProgramParams.Add(MakeIdentifier)
        else
          Advance;
      end;
      ExpectSymbol(')');
    end;
    ExpectSemicolon;
  end
  else if IsKeyword(kwUnit) then
  begin
    Advance;
    LKind := pkUnit;
    LName := MakeIdentifier;
    ExpandDottedName(LName);
    if IsKeyword(kwDeprecated) then
    begin
      Advance;
      if GetKind = tkString then
        Advance;
    end;
    ExpectSemicolon;
  end
  else if IsKeyword(kwLibrary) then
  begin
    Advance;
    LKind := pkLibrary;
    LName := MakeIdentifier;
    ExpandDottedName(LName);
    ExpectSemicolon;
  end
  else if IsKeyword(kwPackage) then
  begin
    Advance;
    LKind := pkPackage;
    LName := MakeIdentifier;
    ExpandDottedName(LName);
    ExpectSemicolon;
  end
  else
  begin
    LKind := pkProgram;
    LName := TDLIdentifier.Create('', GetSpan);
    Error('Expected program, unit, library or package');
  end;
  LUnit := nil;
  case LKind of
    pkProgram: LUnit := TDLCompilationUnit.Create(LStart, pkProgram, LName);
    pkUnit: LUnit := TDLCompilationUnit.Create(LStart, pkUnit, LName);
    pkLibrary: LUnit := TDLCompilationUnit.Create(LStart, pkLibrary, LName);
    pkPackage: LUnit := TDLCompilationUnit.Create(LStart, pkPackage, LName);
  end;
  LUnit.ProgramParams.AddRange(LProgramParams);
  LProgramParams.Free;
  TakeTrivia(Peek(0), LUnit);

  if LKind = pkPackage then
  begin
    while GetKind <> tkEOF do
    begin
      if IsKeyword(kwRequires) then
      begin
        Advance;
        LUnit.RequiresClause := ParseUsesClause;
      end
      else if IsKeyword(kwContains) then
      begin
        Advance;
        LUnit.ContainsClause := ParseUsesClause;
      end
      else if IsKeyword(kwEnd) then
        Break
      else
        Advance;
    end;
    ExpectKeyword(kwEnd);
    ExpectSymbol('.');
    Result := LUnit;
    Exit;
  end;

  LInInterface := True;
  while GetKind <> tkEOF do
  begin
    LPrevPos := FPos;
    if IsKeyword(kwUses) then
    begin
      Advance;
      LUnit.UsesClauses.Add(ParseUsesClause);
    end
    else if (LKind = pkUnit) and IsKeyword(kwInterface) then
    begin
      Advance;
      LInInterface := True;
    end
    else if (LKind = pkUnit) and IsKeyword(kwImplementation) then
    begin
      Advance;
      LInInterface := False;
    end
    else if (LKind = pkUnit) and IsKeyword(kwInitialization) then
    begin
      Advance;
      LStatements := ParseStatementList([kwFinalization, kwEnd]);
      LBody := TDLCompoundStmt.Create(GetSpan);
      for LStatement in LStatements do
        TDLCompoundStmt(LBody).Statements.Add(LStatement);
      LStatements.Free;
      LUnit.InitSection := TDLInitSection.Create(GetSpan, LBody);
    end
    else if (LKind = pkUnit) and IsKeyword(kwFinalization) then
    begin
      Advance;
      LStatements := ParseStatementList([kwEnd]);
      LBody := TDLCompoundStmt.Create(GetSpan);
      for LStatement in LStatements do
        TDLCompoundStmt(LBody).Statements.Add(LStatement);
      LStatements.Free;
      LUnit.FinalizationSection := TDLFinalizationSection.Create(GetSpan, LBody);
    end
    else if IsKeyword(kwEnd) then
    begin
      if LKind = pkUnit then
      begin
        if not LInInterface then
        begin
          Advance;
          ExpectSymbol('.');
          Break;
        end;
        Advance;
      end;
      if LKind in [pkProgram, pkLibrary] then
        Break;
    end
    else if (LKind in [pkProgram, pkLibrary]) and
            (IsKeyword(kwBegin) or IsKeyword(kwAsm)) then
      Break
    else
    begin
      LItem := ParseDeclItem(not LInInterface);
      if (FPos = LPrevPos) and (LItem = nil) then
        Advance; // resynchronise
      if LItem <> nil then
        LUnit.Items.Add(LItem)
      else
        Advance;
    end;
  end;

  if LKind in [pkProgram, pkLibrary] then
  begin
    // Main block: begin ... end. or asm ... end. or empty.
    if IsKeyword(kwBegin) then
    begin
      Advance;
      LStatements := ParseStatementList([kwEnd]);
      LBody := TDLCompoundStmt.Create(GetSpan);
      for LStatement in LStatements do
        TDLCompoundStmt(LBody).Statements.Add(LStatement);
      LStatements.Free;
      ExpectKeyword(kwEnd);
    end
    else if IsKeyword(kwAsm) then
    begin
      LBody := ParseAsmStmt;
    end
    else
      LBody := TDLCompoundStmt.Create(GetSpan);
    if IsKeyword(kwEnd) then
      Advance;
    ExpectSymbol('.');
    LSpan := TDLSourceSpan.Create(LStart.Start, GetSpan.Stop);
    LUnit.Span := LSpan;
    LUnit.InitSection := TDLInitSection.Create(LSpan, LBody);
  end;

  Result := LUnit;
end;

function TDLDelphiParser.ParseUsesClause: TDLUsesClause;
var
  LClause: TDLUsesClause;
  LReference: TDLUnitReference;
  LName: TDLIdentifier;
  LFullName: string;
begin
  LClause := TDLUsesClause.Create(GetSpan);
  while GetKind <> tkEOF do
  begin
    if IsSymbol(';') then
      Break;
    if IsIdentifier or (GetKind = tkKeyword) then
    begin
      LName := MakeIdentifier;
      LFullName := LName.Name;
      while IsSymbol('.') do
      begin
        Advance;
        if IsIdentifier or (GetKind = tkKeyword) then
        begin
          LName.Free;
          LName := MakeIdentifier;
          LFullName := LFullName + '.' + LName.Name;
        end
        else
          Error('Expected unit name segment after "."');
      end;
      LReference := TDLUnitReference.Create(LName.Span, LName);
      LReference.Name.SetName(LFullName);
      if IsKeyword(kwIn) then
      begin
        Advance;
        if (GetKind = tkString) then
          LReference.InFile := ParseStringSequence
        else
          Error('Expected string literal after "in"');
      end;
      LClause.References.Add(LReference);
    end
    else if IsSymbol(',') then
      Advance
    else
      Error(Format('Unexpected "%s" in uses clause', [GetText]));
  end;
  ExpectSemicolon;
  // Alternate conditional uses branches:  uses A; {$ELSE} uses B; {$ENDIF}
  while HasConditionalStartTrivia do
  begin
    while (GetKind <> tkEOF) and (not IsSymbol(';')) and
          not (IsKeyword(kwImplementation) or IsKeyword(kwInterface) or
               IsKeyword(kwType) or IsKeyword(kwVar) or IsKeyword(kwConst) or
               IsKeyword(kwEnd) or IsKeyword(kwInitialization) or
               IsKeyword(kwFinalization) or IsKeyword(kwFunction) or
               IsKeyword(kwProcedure)) do
      Advance;
    if IsSymbol(';') then
      Advance
    else
      Break;
  end;
  Result := LClause;
end;

function TDLDelphiParser.ParseDeclItem(AAllowBodies: Boolean): TDLNode;
var
  LAttributes: TList<TDLAttribute>;
  LKeyword: TDLKeyword;
  LMethod: TDLProcedureBase;
  LImpl: TDLMethodImpl;
  LProcKind: TDLProcKind;
begin
  Result := nil;
  LAttributes := nil;
  if IsSymbol('[') then
  begin
    LAttributes := ParseAttributes;
    // The declaration follows; attributes are attached by the caller of this
    // function's sub-parsers where relevant. We keep it simple: if the next
    // token is not a declaration keyword, skip ahead.
  end;
  if IsKeyword(kwClass) and (IsKwAhead(kwFunction, 1) or
     IsKwAhead(kwProcedure, 1) or IsKwAhead(kwConstructor, 1) or
     IsKwAhead(kwDestructor, 1) or IsKwAhead(kwOperator, 1)) then
  begin
    Advance; // class
    case GetKeyword of
      kwFunction: LProcKind := prFunction;
      kwProcedure: LProcKind := prProcedure;
      kwConstructor: LProcKind := prConstructor;
      kwOperator: LProcKind := prOperator;
    else
      LProcKind := prDestructor;
    end;
    LMethod := ParseMethodHeader(LProcKind, cmClass, AAllowBodies);
    Result := LMethod;
    if (LAttributes <> nil) and (LAttributes.Count > 0) then
    begin
      TDLProcedureBase(Result).Attributes.AddRange(LAttributes);
      LAttributes.Clear;
    end;
    LAttributes.Free;
    Exit;
  end;
  LKeyword := GetKeyword;
  case LKeyword of
    kwType:
      Result := ParseTypeSection;
    kwConst:
      Result := ParseConstSection;
    kwVar:
      Result := ParseVarSection(False);
    kwThreadvar:
      Result := ParseVarSection(True);
    kwResourcestring:
      Result := ParseResStringSection;
    kwLabel:
      Result := ParseLabelSection;
    kwExports:
      Result := ParseExportsClause;
    kwProcedure, kwFunction, kwConstructor, kwDestructor:
      begin
        case LKeyword of
          kwProcedure: LProcKind := prProcedure;
          kwFunction: LProcKind := prFunction;
          kwConstructor: LProcKind := prConstructor;
        else
          LProcKind := prDestructor;
        end;
        LMethod := ParseMethodHeader(LProcKind, cmNone, AAllowBodies);
        if LMethod is TDLMethodImpl then
          Result := LMethod
        else
        begin
          // Header-only in implementation context with no body: empty stub.
          if AAllowBodies then
          begin
            LImpl := TDLMethodImpl.Create(LMethod.Span, LMethod.Kind,
              TDLIdentifier.Create(LMethod.Name.Name, LMethod.Name.Span,
                LMethod.Name.IsAmpersand), LMethod.ClassModifier);
            LImpl.Params.AddRange(LMethod.Params);
            LMethod.Params.Clear;
            LImpl.ReturnType := LMethod.ReturnType;
            LMethod.ReturnType := nil;
            LImpl.Directives.AddRange(LMethod.Directives);
            LMethod.Directives.Clear;
            LMethod.Free;
            Result := LImpl;
          end
          else
            Result := LMethod;
        end;
      end;
  else
    Error(Format('Unexpected "%s" at declaration level', [GetText]));
  end;
  if (LAttributes <> nil) and (LAttributes.Count > 0) then
  begin
    if Result is TDLProcedureBase then
    begin
      TDLProcedureBase(Result).Attributes.AddRange(LAttributes);
      LAttributes.Clear;
    end
    else if Result is TDLDeclItem then
    begin
      TDLDeclItem(Result).Attributes.AddRange(LAttributes);
      LAttributes.Clear;
    end;
  end;
  if LAttributes <> nil then
    LAttributes.Free;
end;

function TDLDelphiParser.ParseTypeSection: TDLTypeSection;
var
  LSection: TDLTypeSection;
  LPrevPos: Integer;
  LSawConditional: Boolean;
begin
  LSawConditional := False;
  LSection := TDLTypeSection.Create(GetSpan, False);
  TakeLeadingTrivia(LSection);
  ExpectKeyword(kwType);
  while GetKind <> tkEOF do
  begin
    LPrevPos := FPos;    if HasConditionalStartTrivia then
      LSawConditional := True;
    if IsSymbol('[') then
    begin
      // attributes on the declaration
      ParseAttributes.Free;
    end;
    if (GetKind = tkIdentifier) or IsSoftNameKeyword then
    begin
      // A clean conditional group: {$IFDEF X} A = ...; {$ELSE} B = ...; {$ENDIF}
      if HasConditionalStartTrivia and CanStartConditionalGroup(True) and
         SingleConditionalInTrivia then
        LSection.Items.Add(ParseConditionalDeclGroup(ParseTypeDeclNode))
      else if LSawConditional and IsSymbolAhead('=', 1) and
         not ((Peek(2).Kind = tkInteger) and
              (Peek(3).Kind = tkSymbol) and (Peek(3).Text = '..')) and
         ((Peek(2).Kind in [tkInteger, tkString, tkFloat, tkCharCode]) or
          ((Peek(2).Kind = tkIdentifier) and (Peek(3).Kind = tkSymbol) and
           (Peek(3).Text = '(')) or
          ((Peek(2).Kind = tkKeyword) and (Peek(2).Text = 'nil'))) then
        ParseConstDecl.Free // a const in a conditional branch of a type section
      else
        LSection.Items.Add(ParseTypeDecl);
    end
    else if LSawConditional and
            (IsKeyword(kwConst) or IsKeyword(kwVar) or IsKeyword(kwType) or
             IsKeyword(kwLabel)) then
    begin
      // Conditional branches may contain other section kinds:
      //   type A = ...; {$IF X} const ... {$ELSEIF Y} type B = ...; {$ENDIF}
      case GetKeyword of
        kwConst: ParseConstSection.Free;
        kwVar: ParseVarSection(False).Free;
        kwType:
          Advance; // a nested 'type' keyword continues this section
      else
        ParseLabelSection.Free;
      end;
    end
    else
      Break;
    if FPos = LPrevPos then
      Advance; // resynchronise
  end;
  Result := LSection;
end;

function TDLDelphiParser.ParseTypeDecl: TDLTypeDecl;
var
  LName: TDLIdentifier;
  LTypeExpr: TDLTypeExpr;
  LStart: TDLSourceSpan;
  LDecl: TDLTypeDecl;
  LParams: TList<TDLIdentifier>;
  LTrivia: TList<TDLTrivia>;
begin
  LStart := GetSpan;
  LTrivia := TakeTriviaCopy;
  try
  LName := MakeIdentifier;
  if IsSymbol('<') then
  begin
    LParams := TList<TDLIdentifier>.Create;
    if ParseTypeParams(LParams) then
    begin
      // Generic type declaration: name<T> = ...; we wrap the type expr later.
      ExpectSymbol('=');
      LTypeExpr := ParseTypeExpr;
      // Represent as nested named type for simplicity (type params dropped
      // from CST name; builder records them when needed).
      LDecl := TDLTypeDecl.Create(TDLSourceSpan.Create(LStart.Start,
        GetSpan.Stop), LName, LTypeExpr);
      LDecl.LeadingTrivia.AddRange(LTrivia);
      LDecl.TypeParams.AddRange(LParams);
      LParams.Clear;
      LParams.Free;
      ExpectSemicolon;
      Result := LDecl;
      Exit;
    end;
    LParams.Free;
  end;
  if IsSymbol('=') then
    Advance
  else
    Error('Expected "=" in type declaration');
  if IsKeyword(kwType) then
    Advance; // 'type X = type Y' alias form
  LTypeExpr := ParseTypeExpr;
  // type X = ... platform/deprecated;  (directives after the type)
  while IsKeyword(kwDeprecated) or IsKeyword(kwPlatform) or
        IsKeyword(kwExperimental) do
  begin
    Advance;
    if GetKind = tkString then
      ParseStringSequence.Free;
  end;
  LDecl := TDLTypeDecl.Create(TDLSourceSpan.Create(LStart.Start, GetSpan.Stop),
    LName, LTypeExpr);
  LDecl.LeadingTrivia.AddRange(LTrivia);
  ExpectSemicolon;
  Result := LDecl;
  finally
    LTrivia.Free;
  end;
end;

function TDLDelphiParser.ParseTypeDeclNode: TDLNode;
begin
  Result := ParseTypeDecl;
end;

function TDLDelphiParser.ParseTypeParams(ANames: TList<TDLIdentifier>): Boolean;
begin
  // <T, U: constraint>
  Result := False;
  if not IsSymbol('<') then
    Exit;
  Advance;
  while GetKind <> tkEOF do
  begin
    if IsSymbol('>') then
    begin
      Advance;
      Result := True;
      Exit;
    end;
    if IsIdentifier then
      ANames.Add(MakeIdentifier)
    else if IsSymbol(',') then
      Advance
    else if IsSymbol(':') then
    begin
      // constraint list (T: A, constructor); stop at a new parameter
      Advance;
      while (GetKind <> tkEOF) and (not IsSymbol('>')) do
        if IsIdentifier and IsSymbolAhead(':', 1) then
          Break // a new type parameter name begins (U: B)
        else
          Advance;
    end
    else
      Break;
  end;
  // Unterminated; restore is not possible, report error.
  Error('Unterminated type parameter list');
end;

function TDLDelphiParser.ParseConstSection: TDLConstSection;
var
  LSection: TDLConstSection;
  LPrevPos: Integer;
begin
  LSection := TDLConstSection.Create(GetSpan);
  TakeLeadingTrivia(LSection);
  ExpectKeyword(kwConst);
  while GetKind <> tkEOF do
  begin
    LPrevPos := FPos;
    // An alternate conditional branch may contain a type declaration
    // instead of a const:  const X = 1; {$ELSEIF Y} type T = record ...;
    if (IsIdentifier or IsSoftNameKeyword) and HasConditionalStartTrivia and
       IsSymbolAhead('=', 1) and (Peek(2).Kind = tkKeyword) and
       ((Peek(2).Text = 'record') or (Peek(2).Text = 'class') or
        (Peek(2).Text = 'interface') or (Peek(2).Text = 'dispinterface') or
        (Peek(2).Text = 'object')) then
      Break;
    if (GetKind = tkIdentifier) or IsSoftNameKeyword then
    begin
      // A clean conditional group: {$IFDEF X} A = ...; {$ELSE} A = ...; {$ENDIF}
      if HasConditionalStartTrivia and CanStartConditionalGroup(True) and
         SingleConditionalInTrivia then
        LSection.Items.Add(ParseConditionalDeclGroup(ParseConstDeclNode))
      else
        LSection.Items.Add(ParseConstDecl);
    end
    else
      Break;
    if FPos = LPrevPos then
      Advance; // resynchronise
    // Skip alternate branches of conditional compilation in const value
    // position:  X = {$IFDEF A}1{$ELSE}2{$ENDIF};
    // A clean declaration group ({$IFDEF X} B = ...; {$ELSE} B = ...;
    // {$ENDIF}) is handled by the outer loop as a structural group; do not
    // skip its branches here.
    while HasConditionalStartTrivia and
          not (CanStartConditionalGroup(True) and SingleConditionalInTrivia) and
          ((GetKind in [tkString, tkInteger, tkFloat, tkCharCode]) or
           IsIdentifier or IsSymbol('[')) do
    begin
      if (IsIdentifier or IsSoftNameKeyword) and
         (IsSymbolAhead('=', 1) or IsSymbolAhead(':', 1)) then
        if (Peek(2).Kind = tkKeyword) and
           ((Peek(2).Text = 'record') or (Peek(2).Text = 'class') or
            (Peek(2).Text = 'interface') or (Peek(2).Text = 'dispinterface') or
            (Peek(2).Text = 'object')) then
          Break // the alternate branch contains a type, not a const
        else
          // Alternate const declaration in a conditional branch:
          //   X = 1; {$ELSE} X = 2; {$ENDIF}
          ParseConstDecl.Free
      else
      begin
        ParseExpression.Free;
        if IsSymbol(';') then
          Advance
        else
          Break;
      end;
    end;
  end;
  Result := LSection;
end;

function TDLDelphiParser.ParseConstDecl: TDLConstDecl;
var
  LDecl: TDLConstDecl;
  LName: TDLIdentifier;
  LDepth: Integer;
  LIsRecordConst: Boolean;
begin
  LDecl := TDLConstDecl.Create(GetSpan);
  TakeLeadingTrivia(LDecl);
  while True do
  begin
    LName := MakeIdentifier;
    LDecl.Names.Add(LName);
    if IsSymbol(',') then
    begin
      Advance;
      Continue;
    end;
    Break;
  end;
  if IsSymbol(':') then
  begin
    Advance;
    LDecl.IsTyped := True;
    LDecl.TypeExpr := ParseTypeExpr;
  end;
  if IsSymbol('=') then
  begin
    Advance;
    LIsRecordConst := False;
    if IsSymbol('(') then
    begin
      if (Peek(1).Kind = tkSymbol) and (Peek(1).Text = '(') then
        LIsRecordConst := True // array of records: ( (A: ...); ... )
      else if (Peek(1).Kind = tkSymbol) and (Peek(1).Text = ')') then
        LIsRecordConst := True // empty record value: ()
      else if ((Peek(1).Kind = tkIdentifier) or (Peek(1).Kind = tkKeyword)) and
              (Peek(2).Kind = tkSymbol) and (Peek(2).Text = ':') then
        LIsRecordConst := True; // record value: (A: ...)
      if LIsRecordConst then
      begin
        // Typed constant with a record value:  X: T = (Field: v; ...);
        // Skip the value with balanced parentheses (records and arrays of
        // records); the exact structure is not represented in the CST.
        Advance;
        LDepth := 1;
        while (GetKind <> tkEOF) and (LDepth > 0) do
        begin
          if IsSymbol('(') then
            Inc(LDepth)
          else if IsSymbol(')') then
            Dec(LDepth);
          Advance;
        end;
      end
      else
        LDecl.Value := ParseExpression;
    end
    else
      LDecl.Value := ParseExpression;
    // A const value may be split by conditional compilation:
    //   X = {$IFDEF A}1{$ELSE}2{$ENDIF};
    while HasConditionalStartTrivia and
          ((GetKind in [tkString, tkInteger, tkFloat, tkCharCode]) or
           IsIdentifier or IsSymbol('[')) do
    begin
      if (IsIdentifier or IsSoftNameKeyword) and
         (IsSymbolAhead('=', 1) or IsSymbolAhead(':', 1)) then
        Break; // a new const declaration, not an alternate branch value
      ParseExpression.Free;
      if IsSymbol(';') then
        Break; // the terminating ';' is consumed by ExpectSemicolon below
    end;
  end;
  // const X = expr platform deprecated;  (multiple directives allowed)
  while IsKeyword(kwDeprecated) or IsKeyword(kwPlatform) or
        IsKeyword(kwExperimental) do
  begin
    Advance;
    if GetKind = tkString then
      ParseStringSequence.Free;
  end;
  ExpectSemicolon;
  Result := LDecl;
end;

function TDLDelphiParser.ParseConstDeclNode: TDLNode;
begin
  Result := ParseConstDecl;
end;

function TDLDelphiParser.ParseResStringSection: TDLResStringSection;
var
  LSection: TDLResStringSection;
begin
  LSection := TDLResStringSection.Create(GetSpan);
  TakeLeadingTrivia(LSection);
  ExpectKeyword(kwResourcestring);
  while GetKind <> tkEOF do
  begin
    if IsIdentifier or IsSoftNameKeyword then
      LSection.Items.Add(ParseConstDecl)
    else
      Break;
  end;
  Result := LSection;
end;

function TDLDelphiParser.ParseVarSection(AIsThreadVar: Boolean): TDLVarSection;
var
  LSection: TDLVarSection;
  LPrevPos: Integer;
begin
  LSection := TDLVarSection.Create(GetSpan, AIsThreadVar);
  TakeLeadingTrivia(LSection);
  if AIsThreadVar then
    ExpectKeyword(kwThreadvar)
  else
    ExpectKeyword(kwVar);
  while GetKind <> tkEOF do
  begin
    LPrevPos := FPos;
    if IsSymbol('[') then
    begin
      // Attribute on a variable declaration:  [Unsafe] X: T;
      ParseAttributes.Free;
      Continue;
    end;
    if IsIdentifier or IsSoftNameKeyword then
    begin
      // A clean conditional group:
      //   {$IFDEF X} A: T; {$ELSE} A: U; {$ENDIF}
      if HasConditionalStartTrivia and CanStartConditionalGroup(True) and
         SingleConditionalInTrivia then
        LSection.Items.Add(ParseConditionalDeclGroup(ParseVarDeclNode))
      else
        LSection.Items.Add(ParseVarDecl);
    end
    else
      Break;
    if FPos = LPrevPos then
      Advance; // resynchronise
  end;
  Result := LSection;
end;

function TDLDelphiParser.ParseVarDecl: TDLVarDecl;
var
  LDecl: TDLVarDecl;
  LName: TDLIdentifier;
  LDepth: Integer;
begin
  LDecl := TDLVarDecl.Create(GetSpan);
  TakeLeadingTrivia(LDecl);
  while True do
  begin
    LName := MakeIdentifier;
    LDecl.Names.Add(LName);
    if IsSymbol(',') then
    begin
      Advance;
      Continue;
    end;
    Break;
  end;
  if IsSymbol(':') then
  begin
    Advance;
    LDecl.TypeExpr := ParseTypeExpr;
  end;
  if IsKeyword(kwAbsolute) then
  begin
    Advance;
    LDecl.AbsoluteTarget := ParseExpression;
  end;
  if IsSymbol('=') then
  begin
    Advance;
    if IsSymbol('(') and
       (((Peek(1).Kind = tkIdentifier) or (Peek(1).Kind = tkKeyword)) and
        (Peek(2).Kind = tkSymbol) and (Peek(2).Text = ':')) then
    begin
      // var X: T = (Field: v; ...);  -- record constant initializer
      Advance;
      LDepth := 1;
      while (GetKind <> tkEOF) and (LDepth > 0) do
      begin
        if IsSymbol('(') then
          Inc(LDepth)
        else if IsSymbol(')') then
          Dec(LDepth);
        Advance;
      end;
    end
    else
      LDecl.Init := ParseExpression;
  end;
  if IsSymbol(':=') then
  begin
    // inline var initialization (var x := 42;)
    Advance;
    LDecl.Init := ParseExpression;
  end;
  // var X: T = nil platform deprecated;
  while IsKeyword(kwPlatform) or IsKeyword(kwDeprecated) or
        IsKeyword(kwExperimental) do
  begin
    Advance;
    if GetKind = tkString then
      ParseStringSequence.Free;
  end;
  ExpectSemicolon;
  Result := LDecl;
end;

function TDLDelphiParser.ParseLabelSection: TDLLabelSection;
var
  LSection: TDLLabelSection;
begin
  LSection := TDLLabelSection.Create(GetSpan);
  TakeLeadingTrivia(LSection);
  ExpectKeyword(kwLabel);  while GetKind <> tkEOF do
  begin
    if (GetKind = tkIdentifier) or (GetKind = tkInteger) then
    begin
      LSection.Items.Add(TDLLabelDecl.Create(GetSpan, MakeIdentifier));
      if IsSymbol(',') then
        Advance
      else
        Break;
    end
    else
      Break;
  end;
  ExpectSemicolon;
  Result := LSection;
end;

function TDLDelphiParser.ParseExportsClause: TDLExportsClause;
var
  LSection: TDLExportsClause;
  LItem: TDLExportItem;
begin
  LSection := TDLExportsClause.Create(GetSpan);
  TakeLeadingTrivia(LSection);
  ExpectKeyword(kwExports);
  while GetKind <> tkEOF do
  begin
    if IsIdentifier then
    begin
      LItem := TDLExportItem.Create(GetSpan, MakeIdentifier);
      if IsKeyword(kwIndex) then
      begin
        Advance;
        LItem.Index := ParseExpression;
      end;
      if IsKeyword(kwName) then
      begin
        Advance;
        LItem.NameSpec := ParseStringSequence;
      end;
      LSection.Items.Add(LItem);
    end
    else if IsSymbol(',') then
      Advance
    else if IsSymbol(';') then
      Break
    else
      Advance;
  end;
  ExpectSemicolon;
  Result := LSection;
end;

function TDLDelphiParser.ParseVarDeclNode: TDLNode;
begin
  Result := ParseVarDecl;
end;

function TDLDelphiParser.ParseAttributes: TList<TDLAttribute>;
var
  LAttributes: TList<TDLAttribute>;
  LPrevPos: Integer;
begin
  LAttributes := TList<TDLAttribute>.Create;
  while IsSymbol('[') do
  begin
    Advance;
    while (GetKind <> tkEOF) and (not IsSymbol(']')) do
    begin
      LPrevPos := FPos;
      LAttributes.Add(ParseAttribute);
      if FPos = LPrevPos then
        Advance;
      if IsSymbol(',') then
        Advance;
    end;
    ExpectSymbol(']');
  end;
  Result := LAttributes;
end;

function TDLDelphiParser.ParseAttribute: TDLAttribute;
var
  LAttribute: TDLAttribute;
begin
  LAttribute := TDLAttribute.Create(GetSpan);
  // GUID attribute of an interface body: ['{...}']
  if GetKind = tkString then
  begin
    Advance;
    Result := LAttribute;
    Exit;
  end;
  while IsIdentifier or (GetKind = tkKeyword) do
  begin
    LAttribute.NamePath.Add(MakeIdentifier);
    if IsSymbol('.') then
      Advance
    else
      Break;
  end;
  if LAttribute.NamePath.Count = 0 then
    Error('Expected attribute name');
  if IsSymbol('(') then
  begin
    Advance;
    while (GetKind <> tkEOF) and (not IsSymbol(')')) do
    begin
      LAttribute.Args.Add(ParseExpression);
      if IsSymbol(',') then
        Advance;
    end;
    ExpectSymbol(')');
  end;
  Result := LAttribute;
end;

{ ------------------------------------------------------------------ }
{ Types                                                              }
{ ------------------------------------------------------------------ }

function TDLDelphiParser.ParseTypeExpr: TDLTypeExpr;
var
  LStart: TDLSourceSpan;
  LIsPacked: Boolean;
  LBoundExpr: TDLExpr;
  LBoundHigh: TDLExpr;
begin
  Inc(FStmtDepth);
  if FStmtDepth > 200 then
    raise Exception.Create('DLP-FATAL: type recursion at "' + GetText +
      '" line=' + IntToStr(GetSpan.Start.Line));
  try
  LStart := GetSpan;
  LIsPacked := False;
  if IsKeyword(kwPacked) then
  begin
    LIsPacked := True;
    Advance;
  end;
  case GetKeyword of
    kwArray:
      begin
        Advance;
        if IsSymbol('[') then
        begin
          // static array
          Advance;
          Result := TDLStaticArrayType.Create(LStart, nil);
          while GetKind <> tkEOF do
          begin
            if IsSymbol(']') then
            begin
              Advance;
              Break;
            end;
            if IsSymbol(',') then
              Advance
            else if IsKeyword(kwFile) or IsKeyword(kwRecord) or
                    IsKeyword(kwClass) then
              TDLStaticArrayType(Result).Bounds.Add(
                TDLArrayBound.Create(GetSpan, nil, ParseTypeExpr))
            else if (GetKind = tkIdentifier) or (GetKind = tkInteger) or
                    (GetKind = tkString) or (GetKind = tkCharCode) or
                    (GetKind = tkSymbol) then
            begin
              // bound: expression, optionally a subrange (low..high)
              LBoundExpr := ParseExpression;
              if IsSymbol('..') then
              begin
                Advance;
                LBoundHigh := ParseExpression;
                LBoundExpr := TDLBinaryExpr.Create(
                  TDLSourceSpan.Create(LBoundExpr.Span.Start, GetSpan.Stop),
                  boNone, '..', LBoundExpr, LBoundHigh);
              end;
              TDLStaticArrayType(Result).Bounds.Add(
                TDLArrayBound.Create(GetSpan, LBoundExpr, nil));
            end
            else
              Advance;
          end;
          ExpectKeyword(kwOf);
          TDLStaticArrayType(Result).ElementType := ParseTypeExpr;
        end
        else
        begin
          ExpectKeyword(kwOf);
          Result := TDLDynamicArrayType.Create(LStart, ParseTypeExpr);
        end;
      end;
    kwSet:
      begin
        Advance;
        ExpectKeyword(kwOf);
        Result := TDLSetType.Create(LStart, ParseTypeExpr);
      end;
    kwFile:
      begin
        Advance;
        if IsKeyword(kwOf) then
        begin
          Advance;
          Result := TDLFileType.Create(LStart, ParseTypeExpr);
        end
        else
          Result := TDLFileType.Create(LStart, nil);
      end;
    kwString:
      begin
        Advance;
        if IsSymbol('[') then
        begin
          Advance;
          Result := TDLStringType.Create(LStart, ParseExpression);
          ExpectSymbol(']');
        end
        else
          Result := TDLStringType.Create(LStart, nil);
      end;
    kwRecord:
      begin
        if IsKwAhead(kwHelper, 1) then
          Result := ParseRecordHelper
        else
          Result := ParseRecordType;
      end;
    kwClass:
      Result := ParseClassLike(pkProgram);
    kwInterface:
      Result := ParseClassLike(pkUnit);
    kwDispInterface:
      Result := ParseClassLike(pkLibrary);
    kwObject:
      Result := ParseClassLike(pkPackage);
    kwReference:
      if IsKwAhead(kwTo, 1) then
      begin
        Advance;
        ExpectKeyword(kwTo);
        Result := ParseProceduralType;
        TDLProceduralType(Result).IsReferenceTo := True;
      end
      else
        Result := ParseNamedType; // 'Reference' as a type name
    kwProcedure, kwFunction:
      Result := ParseProceduralType;
    kwPacked:
      begin
        // handled by LIsPacked above
        Result := ParseTypeExpr;
      end;
    kwCdecl, kwStdcall, kwRegister, kwPascal, kwSafecall:
      begin
        // procedural type with a leading calling convention (rare)
        Result := ParseProceduralType;
      end;
    kwType:
      begin
        Advance; // 'type X' alias reference
        Result := ParseTypeExpr;
      end;
  else
    if IsSymbol('(') then
      Result := ParseEnumOrSubrange
    else if (GetKind = tkIdentifier) or (GetKind = tkKeyword) then
    begin
      // Subrange with a qualified endpoint: TEnum.Member..TEnum.Member
      if IsSymbolAhead('..', 1) or
         ((GetKind = tkIdentifier) and IsQualifiedFollowedByDotDot) then
        Result := ParseSubrangeType
      else
        Result := ParseNamedType;
    end
    else if (GetKind = tkInteger) or (GetKind = tkString) or
            (GetKind = tkCharCode) or
            (IsSymbol('-') and ((Peek(1).Kind = tkInteger) or
             (Peek(1).Kind = tkIdentifier))) then
      Result := ParseSubrangeType
    else if IsSymbol('^') then
    begin
      Advance;
      Result := TDLPointerType.Create(LStart, ParseTypeExpr);
    end
    else
    begin
      Error('Expected a type expression');
      Result := TDLNamedType.Create(LStart, TDLIdentifier.Create('?', LStart));
    end;
  end;
  if LIsPacked then
  begin
    // record/array/set/enum packed flags
    if Result is TDLRecordType then
      TDLRecordType(Result).IsPacked := True
    else if Result is TDLStaticArrayType then
      ; // packed static arrays carry no separate flag in our CST
  end;
  // Skip alternate branches of conditional compilation in type position:
  // x: {$IFDEF A}T1{$ELSE}T2{$ENDIF};  (conditional compilation is not
  // evaluated; the alternate branch token carries {$IFDEF}/{$ELSE} trivia).
  while ((IsIdentifier) or (GetKind = tkKeyword)) and HasDirectiveTrivia do
    Advance;
  finally
    Dec(FStmtDepth);
  end;
end;

function TDLDelphiParser.ParseNamedType: TDLNamedType;
var
  LName: TDLIdentifier;
  LType: TDLNamedType;
  LStart: TDLSourceSpan;
begin
  LStart := GetSpan;
  LName := MakeIdentifier;
  // Qualified type references: System.Types.TWaitResult
  ExpandDottedName(LName);
  LType := TDLNamedType.Create(LStart, LName);
  if IsSymbol('<') then
    LType.TypeArgs.AddRange(ParseTypeArgs);
  // Qualified member of a generic instantiation: TList<T>.ParrayofT
  if IsSymbol('.') then
    ExpandDottedName(LName);
  Result := LType;
end;

function TDLDelphiParser.ParseTypeArgs: TList<TDLTypeArg>;
var
  LArgs: TList<TDLTypeArg>;
begin
  LArgs := TList<TDLTypeArg>.Create;
  if not IsSymbol('<') then
    Exit(LArgs);
  Advance;
  while GetKind <> tkEOF do
  begin
    if IsSymbol('>') then
    begin
      Advance;
      Exit(LArgs);
    end;
    if IsSymbol(',') then
      Advance
    else
      LArgs.Add(ParseTypeArg);
  end;
  Error('Unterminated type argument list');
  Result := LArgs;
end;

function TDLDelphiParser.ParseTypeArg: TDLTypeArg;
var
  LStart: TDLSourceSpan;
  LTypeExpr: TDLTypeExpr;
begin
  LStart := GetSpan;
  LTypeExpr := ParseTypeExpr;
  Result := TDLTypeArg.Create(LStart, LTypeExpr);
end;

function TDLDelphiParser.ParseEnumOrSubrange: TDLTypeExpr;
var
  LStart: TDLSourceSpan;
  LFirst: TDLExpr;
  LEnum: TDLEnumType;
  LMember: TDLEnumMember;
  LName: TDLIdentifier;
begin
  LStart := GetSpan;
  ExpectSymbol('(');
  if (GetKind = tkInteger) or (GetKind = tkString) or (GetKind = tkCharCode) or
     (IsSymbol('-') and (Peek(1).Kind = tkInteger)) then
  begin
    LFirst := ParseExpression;
    ExpectSymbol('..');
    Result := TDLSubrangeType.Create(LStart, LFirst, ParseExpression);
    ExpectSymbol(')');
    Exit;
  end;
  LEnum := TDLEnumType.Create(LStart, False);
  while GetKind <> tkEOF do
  begin
    if IsSymbol(')') then
    begin
      Advance;
      Break;
    end;
    if IsIdentifier then
    begin
      LName := MakeIdentifier;
      LMember := TDLEnumMember.Create(LName.Span, LName);
      if IsSymbol('=') then
      begin
        Advance;
        LMember.Value := ParseExpression;
      end;
      LEnum.Members.Add(LMember);
    end
    else if IsSymbol(',') then
      Advance
    else
      Advance;
  end;
  // (a, b, c) platform/deprecated  -- directive after an enum type
  if IsKeyword(kwPlatform) or IsKeyword(kwDeprecated) or
     IsKeyword(kwExperimental) then
  begin
    Advance;
    if GetKind = tkString then
      ParseStringSequence.Free;
  end;
  Result := LEnum;
end;

function TDLDelphiParser.ParseSubrangeType: TDLSubrangeType;
var
  LStart: TDLSourceSpan;
  LLow, LHigh: TDLExpr;
begin
  LStart := GetSpan;
  LLow := ParseExpression;
  if IsSymbol('..') then
    Advance
  else
    Error('Expected ".." in subrange type');
  LHigh := ParseExpression;
  Result := TDLSubrangeType.Create(LStart, LLow, LHigh);
end;

function TDLDelphiParser.ParseRecordType: TDLRecordType;
var
  LRecord: TDLRecordType;
  LPrevPos: Integer;
begin
  LRecord := TDLRecordType.Create(GetSpan, False);
  ExpectKeyword(kwRecord);
  FCurrentVisibility := vsPublic;
  FCurrentStrict := False;
  while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
  begin
    LPrevPos := FPos;
    if IsKeyword(kwCase) then
    begin
      // variant part
      Advance;
      LRecord.VariantPart := ParseVariantSection;
    end
    else
      if not ParseMemberSection(LRecord.Members) then
        if not IsKeyword(kwEnd) then
          Advance;
    if FPos = LPrevPos then
      Advance; // resynchronise
  end;
  ExpectKeyword(kwEnd);
  if IsIdentifier and (LowerCase(GetText) = 'align') then
  begin
    // "end align 16;" alignment specifier after a record/class type
    Advance;
    if GetKind = tkInteger then
      Advance;
  end;
  if IsKeyword(kwDeprecated) or IsKeyword(kwPlatform) or
     IsKeyword(kwExperimental) then
  begin
    Advance;
    if GetKind = tkString then
      ParseStringSequence.Free;
  end;
  Result := LRecord;
end;

function TDLDelphiParser.ParseRecordHelper: TDLTypeExpr;
var
  LStart: TDLSourceSpan;
  LHelperFor: TDLTypeExpr;
  LMembers: TList<TDLMember>;
begin
  LStart := GetSpan;
  ExpectKeyword(kwRecord);
  ExpectKeyword(kwHelper);
  ExpectKeyword(kwFor);
  LHelperFor := ParseTypeExpr;
  LMembers := TList<TDLMember>.Create;
  FCurrentVisibility := vsPublic;
  FCurrentStrict := False;
  while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
  begin
    if not ParseMemberSection(LMembers) then
      if not IsKeyword(kwEnd) then
        Advance;
  end;
  ExpectKeyword(kwEnd);
  Result := TDLClassType.Create(LStart, False, False, True, False, False,
    False, False, nil, LHelperFor, LMembers);
end;

function TDLDelphiParser.ParseVariantSection: TDLVariantSection;
var
  LSection: TDLVariantSection;
  LBranch: TDLVariantBranch;
begin
  LSection := TDLVariantSection.Create(GetSpan);
  // Variant part: "case [Tag:] Type of"  (the tag is optional).
  if IsIdentifier and IsSymbolAhead(':', 1) then
  begin
    LSection.Tag := MakeIdentifier;
    ExpectSymbol(':');
  end;
  LSection.TagType := ParseTypeExpr;
  ExpectKeyword(kwOf);
  while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) and
        (not IsSymbol(')')) do
  begin
    LBranch := TDLVariantBranch.Create(GetSpan);
    LSection.Variants.Add(LBranch);
    // branch labels: expr [.. expr] {, expr}
    while True do
    begin
      LBranch.CaseLabels.Add(ParseExpression);
      if IsSymbol('..') then
      begin
        Advance;
        LBranch.CaseLabels.Add(ParseExpression);
      end;
      if IsSymbol(',') then
        Advance
      else
        Break;
    end;
    ExpectSymbol(':');
    // branch fields, optionally wrapped in parentheses
    if IsSymbol('(') then
      Advance;
    while (GetKind <> tkEOF) and (not IsSymbol(')')) and
          (not IsKeyword(kwEnd)) do
    begin
      if IsKeyword(kwCase) then
      begin
        Advance;
        LBranch.VariantPart := ParseVariantSection;
      end
      else if IsIdentifier then
      begin
        LBranch.Fields.Add(ParseFieldDeclBody);
        if IsSymbol(';') then
          Advance;
      end
      else
        Advance;
    end;
    if IsSymbol(')') then
      Advance;
    if IsSymbol(';') then
      Advance; // branch separator
    // Alternate conditional field lists of the same branch:
    //   3: (A: X); {$ELSE} (B: Y); {$ENDIF}
    while IsSymbol('(') and HasConditionalStartTrivia do
    begin
      Advance;
      while (GetKind <> tkEOF) and (not IsSymbol(')')) and
            (not IsKeyword(kwEnd)) do
      begin
        if IsIdentifier then
        begin
          ParseFieldDeclBody.Free;
          if IsSymbol(';') then
            Advance;
        end
        else
          Advance;
      end;
      if IsSymbol(')') then
        Advance;
      if IsSymbol(';') then
        Advance;
    end;
  end;
  Result := LSection;
end;

function TDLDelphiParser.ParseClassLike(AKind: TDLProgramKind): TDLTypeExpr;
var
  LStart: TDLSourceSpan;
  LClass: TDLTypeExpr;
  LMembers: TList<TDLMember>;
  LIsSealed: Boolean;
  LIsAbstract: Boolean;
  LIsHelper: Boolean;
  LIsClassRef: Boolean;
  LIsDisp: Boolean;
  LIsObject: Boolean;
  LIsInterface: Boolean;
  LHelperFor: TDLTypeExpr;
  LBase: TDLTypeExpr;
  LAncestor: TDLNamedType;
  LName: TDLIdentifier;
begin
  LStart := GetSpan;
  LIsSealed := False;
  LIsAbstract := False;
  LIsHelper := False;
  LIsClassRef := False;
  LIsDisp := False;
  LIsObject := False;
  LIsInterface := False;
  LHelperFor := nil;
  LBase := nil;
  case AKind of
    pkProgram: Advance; // 'class'
    pkUnit: begin Advance; LIsInterface := True; end;
    pkLibrary: begin Advance; LIsDisp := True; LIsInterface := True; end;
    pkPackage: begin Advance; LIsObject := True; end;
  end;
  if (not LIsInterface) and IsKeyword(kwHelper) then
  begin
    LIsHelper := True;
    Advance;
    if IsKeyword(kwFor) then
    begin
      Advance;
      LHelperFor := ParseTypeExpr;
    end;
  end
  else if IsKeyword(kwSealed) then
  begin
    LIsSealed := True;
    Advance;
  end
  else if IsKeyword(kwAbstract) then
  begin
    LIsAbstract := True;
    Advance;
  end;
  if IsKeyword(kwOf) then
  begin
    LIsClassRef := True;
    Advance;
    LBase := ParseTypeExpr;
  end
  else if IsSymbol('(') then
  begin
    Advance;
    // ancestor + interfaces
    while GetKind <> tkEOF do
    begin
      if IsSymbol(')') then
      begin
        Advance;
        Break;
      end;
      if IsIdentifier then
      begin
        LName := MakeIdentifier;
        LAncestor := TDLNamedType.Create(LName.Span, LName);
        if IsSymbol('<') then
          LAncestor.TypeArgs.AddRange(ParseTypeArgs);
        if LBase = nil then
          LBase := LAncestor
        else
          LAncestor.Free; // additional interfaces are merged into the base list
      end
      else if IsSymbol(',') then
        Advance
      else
        Advance;
    end;
  end;
  // GUID for interfaces/dispinterfaces
  if LIsInterface and IsSymbol('[') then
  begin
    Advance;
    while (GetKind <> tkEOF) and (not IsSymbol(']')) do
      Advance;
    ExpectSymbol(']');
  end;
  LMembers := TList<TDLMember>.Create;
  if (not LIsClassRef) and (not IsSymbol(';')) then
  begin
    FCurrentVisibility := vsPublished;
    FCurrentStrict := False;
    while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
    begin
      if not ParseMemberSection(LMembers) then
        if not IsKeyword(kwEnd) then
          Advance;
    end;
    ExpectKeyword(kwEnd);
    if IsIdentifier and (LowerCase(GetText) = 'align') then
    begin
      Advance;
      if GetKind = tkInteger then
        Advance;
    end;
    if IsKeyword(kwDeprecated) or IsKeyword(kwPlatform) or
       IsKeyword(kwExperimental) then
    begin
      Advance;
      if GetKind = tkString then
        ParseStringSequence.Free;
    end;
  end;
  LClass := TDLClassType.Create(LStart, LIsSealed, LIsAbstract, LIsHelper,
    LIsClassRef, LIsDisp, LIsObject, LIsInterface, LBase, LHelperFor, LMembers);
  Result := LClass;
end;

function TDLDelphiParser.ParseProceduralType: TDLProceduralType;
var
  LStart: TDLSourceSpan;
  LKind: TDLProcKind;
  LType: TDLProceduralType;
  LSavePos: Integer;
begin
  LStart := GetSpan;
  if IsKeyword(kwFunction) then
  begin
    LKind := prFunction;
    Advance;
  end
  else
  begin
    LKind := prProcedure;
    if IsKeyword(kwProcedure) then
      Advance
    else
      Advance; // calling convention token
  end;
  LType := TDLProceduralType.Create(LStart, LKind, False, False);
  if IsSymbol('(') then
    LType.Params.AddRange(ParseParameterList);
  if (LKind = prFunction) and IsSymbol(':') then
  begin
    Advance;
    LType.ReturnType := ParseTypeExpr;
  end;
  if IsKeyword(kwOf) then
  begin
    Advance;
    ExpectKeyword(kwObject);
    LType.IsOfObject := True;
  end;
  // Directives may follow the ';' (function(X): Integer; stdcall;). Only
  // consume the ';' when a directive actually follows; otherwise leave it
  // for the enclosing declaration parser.
  while True do
  begin
    if IsSymbol(';') then
    begin
      LSavePos := FPos;
      Advance;
      if not IsMethodDirectiveStart then
      begin
        FPos := LSavePos;
        Break;
      end;
    end;
    if not ParseMethodDirectives(LType.Directives) then
      Break;
  end;
  Result := LType;
end;

function TDLDelphiParser.ParseParameterList: TList<TDLParameter>;
var
  LParams: TList<TDLParameter>;
begin
  LParams := TList<TDLParameter>.Create;
  ExpectSymbol('(');
  while (GetKind <> tkEOF) and (not IsSymbol(')')) do
  begin
    LParams.Add(ParseParameter);
    if IsSymbol(';') then
      Advance
    else
      Break;
  end;
  ExpectSymbol(')');
  Result := LParams;
end;

function TDLDelphiParser.ParseParameter: TDLParameter;
var
  LModifier: TDLParamModifier;
  LParam: TDLParameter;
  LAttributes: TList<TDLAttribute>;
  i: Integer;
begin
  LModifier := pmNone;
  LAttributes := nil;
  if IsSymbol('[') then
    LAttributes := ParseAttributes;
  if HasConditionalStartTrivia and
     ((IsIdentifier and (LowerCase(GetText) = 'constref')) or
      (IsKeyword(kwConst) and (Peek(1).Kind = tkKeyword))) then
  begin
    // Conditional parameter modifier: {$IFDEF A}constref{$ELSE}const{$ENDIF}
    LModifier := pmConst; // keep the first branch
    while HasConditionalStartTrivia and
          (IsIdentifier or IsKeyword(kwConst) or IsKeyword(kwVar) or
           IsKeyword(kwOut)) do
      Advance;
  end
  else if IsKeyword(kwConst) then
  begin
    Advance;
    if IsKeyword(kwRef) then
    begin
      Advance;
      LModifier := pmConstRef;
    end
    else if IsSymbol('[') then
    begin
      // const [Ref] A: Integer (Delphi 10.4+)
      Advance;
      if IsKeyword(kwRef) then
      begin
        Advance;
        LModifier := pmConstRef;
      end
      else
        LModifier := pmConst;
      if IsSymbol(']') then
        Advance
      else
        Error('Expected "]" after [Ref]');
    end
    else
      LModifier := pmConst;
  end
  else if IsKeyword(kwVar) then
  begin
    Advance;
    if IsKeyword(kwRef) then
    begin
      Advance;
      LModifier := pmVarRef;
    end
    else if IsSymbol('[') then
    begin
      // var [Ref] B: Integer
      Advance;
      if IsKeyword(kwRef) then
      begin
        Advance;
        LModifier := pmVarRef;
      end
      else
        LModifier := pmVar;
      if IsSymbol(']') then
        Advance
      else
        Error('Expected "]" after [Ref]');
    end
    else
      LModifier := pmVar;
  end
  else if IsKeyword(kwOut) then
  begin
    Advance;
    LModifier := pmOut;
  end;
  LParam := TDLParameter.Create(GetSpan, LModifier);
  if LAttributes <> nil then
  begin
    for i := 0 to LAttributes.Count - 1 do
      LParam.Attributes.Add(LAttributes[i]);
    LAttributes.Clear;
    LAttributes.Free;
  end;
  while IsIdentifier or (GetKind = tkKeyword) do
  begin
    LParam.Names.Add(MakeIdentifier);
    if IsSymbol(',') then
      Advance
    else
      Break;
  end;
  if IsSymbol(':') then
  begin
    Advance;
    LParam.TypeExpr := ParseTypeExpr;
  end;
  if IsSymbol('=') then
  begin
    Advance;
    LParam.DefaultValue := ParseExpression;
    // Default value may span conditional branches:
    //   X: T = {$IFDEF A} v1 {$ENDIF} {$IFDEF B} v2 {$ENDIF};
    while HasConditionalStartTrivia and IsIdentifier do
      ParseExpression.Free;
  end;
  Result := LParam;
end;

{ ------------------------------------------------------------------ }
{ Members (class/record bodies)                                      }
{ ------------------------------------------------------------------ }

function TDLDelphiParser.ParseVisibility: TDLVisibility;
begin
  Result := vsNone;
  case GetKeyword of
    kwPrivate: Result := vsPrivate;
    kwProtected: Result := vsProtected;
    kwPublic: Result := vsPublic;
    kwPublished: Result := vsPublished;
    kwAutomated: Result := vsAutomated;
  end;
end;

function TDLDelphiParser.ParseMemberSection(AMembers: TList<TDLMember>): Boolean;
var
  LVisibility: TDLVisibility;
  LIsStrict: Boolean;
  LMarker: TDLVisibilitySection;
  LKeyword: TDLKeyword;
  LMethod: TDLProcedureBase;
  LClassModifier: TDLClassModifier;
  LProcKind: TDLProcKind;
begin
  Result := True;
  LIsStrict := False;
  // A shared-`end` construct: a class/interface/record member list runs into
  // a conditional branch marker without a terminating 'end'. Skip the
  // remaining branches so the declaration resumes after the {$ENDIF}.
  if HasConditionalBranchTrivia then
    SkipConditionalBranchesToEndIf;
  if IsKeyword(kwStrict) then
  begin
    LIsStrict := True;
    Advance;
  end;
  LVisibility := ParseVisibility;
  if LVisibility <> vsNone then
  begin
    Advance;
    FCurrentVisibility := LVisibility;
    FCurrentStrict := LIsStrict;
    LMarker := TDLVisibilitySection.Create(GetSpan, LVisibility, LIsStrict);
    AMembers.Add(LMarker);
    Exit;
  end;
  if LIsStrict then
  begin
    Error('"strict" must be followed by private or protected');
    Exit;
  end;

  if IsSymbol('[') then
    ParseAttributes.Free; // member attributes; cosmetic for parsing

  LClassModifier := cmNone;
  if IsKeyword(kwClass) then
  begin
    if IsKwAhead(kwVar, 1) or IsKwAhead(kwThreadvar, 1) then
    begin
      Advance; // class
      if IsKeyword(kwThreadvar) then
        ParseVarSection(True).Free
      else
        ParseVarSection(False).Free; // TODO: class var section node
      Exit;
    end
    else if IsKwAhead(kwOperator, 1) then
    begin
      Advance; // class
      LProcKind := prOperator;
      LClassModifier := cmClass;
      LMethod := ParseMethodHeader(LProcKind, LClassModifier, False);
      AMembers.Add(TDLMember(LMethod));
      Exit;
    end
    else if IsKwAhead(kwFunction, 1) or IsKwAhead(kwProcedure, 1) or
            IsKwAhead(kwConstructor, 1) or IsKwAhead(kwDestructor, 1) or
            IsKwAhead(kwProperty, 1) then
    begin
      Advance; // class
      LClassModifier := cmClass;
      LKeyword := GetKeyword;
      case LKeyword of
        kwProperty:
          begin
            AMembers.Add(ParsePropertyDecl);
            Exit;
          end;
        kwConstructor: LProcKind := prConstructor;
        kwDestructor: LProcKind := prDestructor;
        kwFunction: LProcKind := prFunction;
      else
        LProcKind := prProcedure;
      end;
      LMethod := ParseMethodHeader(LProcKind, LClassModifier, False);
      AMembers.Add(TDLMember(LMethod));
      Exit;
    end
    else if IsKwAhead(kwConst, 1) or IsKwAhead(kwType, 1) then
    begin
      Advance; // class
      if IsKeyword(kwConst) then
        ParseConstSection.Free
      else
        ParseTypeSection.Free;
      Exit;
    end
    else
    begin
      Error('Unexpected "class" in member section');
      Exit;
    end;
  end;

  LKeyword := GetKeyword;
  case LKeyword of
    kwProcedure, kwFunction, kwConstructor, kwDestructor:
      begin
        case LKeyword of
          kwProcedure: LProcKind := prProcedure;
          kwFunction: LProcKind := prFunction;
          kwConstructor: LProcKind := prConstructor;
        else
          LProcKind := prDestructor;
        end;
        LMethod := ParseMethodHeader(LProcKind, cmNone, False);
        AMembers.Add(TDLMember(LMethod));
      end;
    kwOperator:
      AMembers.Add(TDLMember(ParseMethodHeader(prOperator, cmNone, False)));
    kwProperty:
      AMembers.Add(ParsePropertyDecl);
    kwVar:
      begin
        Advance;
        while IsIdentifier or IsSoftNameKeyword do
          AMembers.Add(ParseFieldDecl);
      end;
    kwType:
      ParseTypeSection.Free;
    kwConst:
      ParseConstSection.Free;
    kwCase:
      begin
        // variant part inside a record (handled by ParseRecordType);
        // here just report and skip
        Error('Unexpected variant part here');
        Result := False;
      end;
  else
    if IsIdentifier or IsSoftNameKeyword then
      AMembers.Add(ParseFieldDecl)
    else
      Result := False;
  end;
end;

function TDLDelphiParser.ParseFieldDecl: TDLFieldDecl;
begin
  Result := ParseFieldDeclBody;
  // The final field of an inline record type may omit the ';' before "end":
  //   array[0..3] of record A: X; B: Y end
  if not (IsKeyword(kwEnd) or IsSymbol(')') or IsKeyword(kwCase) or
          IsKeyword(kwBegin)) then
    ExpectSemicolon;
end;

function TDLDelphiParser.ParseFieldDeclBody: TDLFieldDecl;
var
  LField: TDLFieldDecl;
  LName: TDLIdentifier;
begin
  LField := TDLFieldDecl.Create(GetSpan, FCurrentVisibility, FCurrentStrict, nil);
  TakeLeadingTrivia(LField);
  while True do
  begin
    LName := MakeIdentifier;
    LField.Names.Add(LName);
    if IsSymbol(',') then
    begin
      Advance;
      Continue;
    end;
    Break;
  end;
  ExpectSymbol(':');
  LField.TypeExpr := ParseTypeExpr;
  // FHandle: THandle platform;
  while IsKeyword(kwPlatform) or IsKeyword(kwDeprecated) or
        IsKeyword(kwExperimental) do
  begin
    Advance;
    if GetKind = tkString then
      ParseStringSequence.Free;
  end;
  Result := LField;
end;

function TDLDelphiParser.ParseMethodHeader(AKind: TDLProcKind;
  AClassModifier: TDLClassModifier; AAllowBody: Boolean): TDLProcedureBase;
var
  LStart: TDLSourceSpan;
  LName: TDLIdentifier;
  LHeader: TDLProcedureBase;
  LImpl: TDLMethodImpl;
  LIsClassOperator: Boolean;
  LHasForward: Boolean;
  LDirective: TDLDirective;
  LContDirs: TList<TDLDirective>;
  LContSave: Integer;
  LEnclosingName: string;
  LBodyConditional: Boolean;
  LDbgLine: Integer;
  LFullName: string;
  LTrivia: TList<TDLTrivia>;
begin
  LStart := GetSpan;
  LDbgLine := LStart.Start.Line;
  FDirectiveStmt := False;
  LTrivia := TakeTriviaCopy;
  try
  if AKind = prOperator then
    LIsClassOperator := True
  else
    LIsClassOperator := False;
  // Consume the leading keyword (procedure/function/constructor/destructor/
  // operator). Callers leave the keyword in place.
  if not IsKeyword(kwProcedure) and not IsKeyword(kwFunction) and
     not IsKeyword(kwConstructor) and not IsKeyword(kwDestructor) and
     not IsKeyword(kwOperator) then
    Error('Expected method keyword');
  Advance;
  LName := nil;
  if LIsClassOperator and
     ((GetKind = tkSymbol) or IsKeyword(kwIn) or IsKeyword(kwNot) or
      IsKeyword(kwAnd) or IsKeyword(kwOr) or IsKeyword(kwXor) or
      IsKeyword(kwDiv) or IsKeyword(kwMod) or IsKeyword(kwShl) or
      IsKeyword(kwShr)) then
  begin
    // operator name is a symbol/keyword (+, -, In, ...); exclude '(' and ')'.
    if (GetText = '(') or (GetText = ')') then
      LName := MakeIdentifier
    else
    begin
      LName := TDLIdentifier.Create(GetText, GetSpan);
      Advance;
    end;
  end;
  if LName = nil then
    LName := MakeIdentifier;
  // Qualified implementation names (procedure TFoo.Bar;).
  if IsSymbol('.') then
  begin
    LFullName := LName.Name;
    while IsSymbol('.') do
    begin
      Advance;
      LName.Free;
      LName := MakeIdentifier;
      LFullName := LFullName + '.' + LName.Name;
    end;
    LName.SetName(LFullName);
  end;
  // Generic method type parameters (procedure TCls.DoIt<T>(...)).
  if IsSymbol('<') then
  begin
    Advance;
    while (GetKind <> tkEOF) and (not IsSymbol('>')) do
    begin
      if IsSymbol(',') then
        Advance
      else if IsIdentifier or (GetKind = tkKeyword) then
        MakeIdentifier
      else if IsSymbol(':') then
      begin
        Advance;
        while (GetKind <> tkEOF) and (not IsSymbol(',')) and
              (not IsSymbol('>')) do
          Advance;
      end
      else
        Advance;
    end;
    ExpectSymbol('>');
    // Generic class name with a member method: TCls<T>.Method
    if IsSymbol('.') then
    begin
      LFullName := LName.Name;
      while IsSymbol('.') do
      begin
        Advance;
        LName.Free;
        LName := MakeIdentifier;
        LFullName := LFullName + '.' + LName.Name;
      end;
      LName.SetName(LFullName);
    end;
  end;
  // Interface-implementation mapping:  function IRef.M = ImplMethod;
  if IsSymbol('=') then
  begin
    Advance;
    if IsIdentifier then
      MakeIdentifier.Free
    else
      Error('Expected implementing method name after "="');
  end;
  LHeader := TDLMethodDecl.Create(LStart, AKind, LName, AClassModifier);
  if IsSymbol('(') then
    LHeader.Params.AddRange(ParseParameterList);
  if ((AKind = prFunction) or (AKind = prOperator)) and IsSymbol(':') then
  begin
    Advance;
    LHeader.ReturnType := ParseTypeExpr;
  end;
  ParseMethodDirectivesAndSemicolons(LHeader.Directives);
  // A missing ';' between external declarations is tolerated when the next
  // token starts a new declaration (some RTL files omit it).
  if IsSymbol(';') then
    Advance
  else if not (IsKeyword(kwProcedure) or IsKeyword(kwFunction) or
               IsKeyword(kwClass) or IsKeyword(kwType) or IsKeyword(kwVar) or
               IsKeyword(kwConst) or IsKeyword(kwEnd) or
               IsKeyword(kwInterface)) then
    ExpectSemicolon;
  // A forward-declared routine has no body; the following token belongs to
  // the enclosing scope even if it is a section keyword (var/type/...).
  // Externally imported routines (external ...) likewise have no body.
  LHasForward := False;
  for LDirective in LHeader.Directives do
    if SameText(LDirective.Name.Name, 'forward') or
       SameText(LDirective.Name.Name, 'external') then
      LHasForward := True;
  // Conditional alternates of directive-only (external/forward) declarations:
  //   procedure X; external A name 'b'; {$ELSE} ; {$L f.obj} {$ENDIF}
  if LHasForward then
    while HasConditionalStartTrivia do
    begin
      // Skip the alternate branch up to its ';', but never across a
      // declaration boundary (procedure/function/class/...).
      while (GetKind <> tkEOF) and (not IsSymbol(';')) and
            not (IsKeyword(kwProcedure) or IsKeyword(kwFunction) or
                 IsKeyword(kwClass) or IsKeyword(kwType) or
                 IsKeyword(kwVar) or IsKeyword(kwConst) or
                 IsKeyword(kwEnd) or IsKeyword(kwImplementation) or
                 IsKeyword(kwInterface)) do
        Advance;
      if IsSymbol(';') then
        Advance
      else
        Break;
    end;
  if AAllowBody and (not LHasForward) and
     (IsKeyword(kwBegin) or IsKeyword(kwAsm) or
      IsKeyword(kwVar) or IsKeyword(kwLabel) or IsKeyword(kwConst) or
      IsKeyword(kwType) or IsKeyword(kwFunction) or IsKeyword(kwProcedure)) then
  begin
    LBodyConditional := HasConditionalStartTrivia or FDirectiveStmt;
    LImpl := TDLMethodImpl.Create(LStart, AKind,
      TDLIdentifier.Create(LName.Name, LName.Span, LName.IsAmpersand),
      AClassModifier);
    LImpl.Params.AddRange(LHeader.Params);
    LHeader.Params.Clear;
    LImpl.ReturnType := LHeader.ReturnType;
    LHeader.ReturnType := nil;
    LImpl.Directives.AddRange(LHeader.Directives);
    LHeader.Directives.Clear;
    if LHeader.OperatorName <> nil then
      LImpl.OperatorName := TDLIdentifier.Create(LHeader.OperatorName.Name,
        LHeader.OperatorName.Span, LHeader.OperatorName.IsAmpersand);
    LEnclosingName := LName.Name; // LName is owned by LHeader (freed below)
    LHeader.Free;
    // Local declarations (var/label/const/type sections and nested
    // procedure/function declarations) before the body.
    while IsKeyword(kwVar) or IsKeyword(kwLabel) or IsKeyword(kwConst) or
          IsKeyword(kwType) or IsKeyword(kwFunction) or
          IsKeyword(kwProcedure) do
    begin
      case GetKeyword of
        kwVar: LImpl.LocalDecls.Add(ParseVarSection(False));
        kwLabel: LImpl.LocalDecls.Add(ParseLabelSection);
        kwConst: LImpl.LocalDecls.Add(ParseConstSection);
        kwType: LImpl.LocalDecls.Add(ParseTypeSection);
        kwFunction, kwProcedure:
          begin
          if HasConditionalStartTrivia and
             (Peek(1).Kind = tkIdentifier) and
             ((SameText(Peek(1).Text, LEnclosingName)) or
              ((Pos('.', LEnclosingName) > 0) and
               SameText(Peek(1).Text,
                 Copy(LEnclosingName, 1, Pos('.', LEnclosingName) - 1)))) then
          begin
            // An alternate conditional header branch ({$IFDEF X}
            // procedure A; {$ELSE} procedure B; {$ENDIF}) is parsed header-only
            // and discarded; it is not a nested routine.
            if IsKeyword(kwFunction) then
              ParseMethodHeader(prFunction, cmNone, False).Free
            else
              ParseMethodHeader(prProcedure, cmNone, False).Free;
          end
          else if IsKeyword(kwFunction) then
            LImpl.LocalDecls.Add(ParseMethodHeader(prFunction, cmNone, True))
          else
            LImpl.LocalDecls.Add(ParseMethodHeader(prProcedure, cmNone, True));
          end;
      end;
    end;
    if IsKeyword(kwAsm) then
      LImpl.Body := ParseAsmStmt
    else
    begin
      if HasConditionalStartTrivia then
        LBodyConditional := True;
      LImpl.Body := ParseCompoundStmt;
    end;
    ExpectSemicolon;
    // Conditional compilation may split one method body into several
    // begin...end; blocks ({$IFDEF X} var..begin..end; {$ENDIF}). Parse every
    // additional branch but keep only the first as the method body.
    // Only a conditional body (split into {$IFDEF}/{$ELSE} branches) needs
    // continuation handling; a plain body followed by a directive-introduced
    // section belongs to the enclosing scope.
    FDirectiveStmt := False;
    while LBodyConditional and
          (((IsKeyword(kwBegin) or IsKeyword(kwAsm) or IsKeyword(kwVar) or
             IsKeyword(kwType) or IsKeyword(kwConst) or IsKeyword(kwLabel)) and
            (HasConditionalStartTrivia or FDirectiveStmt)) or
           ((IsKeyword(kwProcedure) or IsKeyword(kwFunction)) and
            (FDirectiveStmt or HasConditionalContinuationTrivia or
             ((HasConditionalStartTrivia and (GetSpan.Start.Column > 1) and
               SectionLeadsToBody)))) or
           (IsMethodDirectiveStart and HasConditionalStartTrivia)) do
    begin
      LContDirs := nil;
      case GetKeyword of
        kwVar, kwType, kwConst, kwLabel:
          begin
            LContSave := FPos;
            case GetKeyword of
              kwVar: ParseVarSection(False).Free;
              kwType: ParseTypeSection.Free;
              kwConst: ParseConstSection.Free;
            else
              ParseLabelSection.Free;
            end;
            // A fresh {$IFDEF}-introduced section that is not followed by a
            // body (begin/asm) belongs to the enclosing scope, not to this
            // method body: backtrack so the section is parsed at module level.
            if (not SectionLeadsToBody) and
               (not HasConditionalContinuationTrivia) and
               (not FDirectiveStmt) then
            begin
              FPos := LContSave;
              FDirectiveStmt := False;
              Break;
            end;
            // A body section following a directive-introduced declaration
            // continues this body (the directive trivia sits on the section
            // keyword token).
            FDirectiveStmt := True;
          end;
        kwProcedure, kwFunction:
          begin
            // Nested routine inside a conditional body branch.
            if IsKeyword(kwProcedure) then
              ParseMethodHeader(prProcedure, cmNone, True).Free
            else
              ParseMethodHeader(prFunction, cmNone, True).Free;
            FDirectiveStmt := True;
          end;
      else
      begin
        if IsMethodDirectiveStart then
        begin
          // A directive-only conditional branch (e.g. external ...).
          LContDirs := TList<TDLDirective>.Create;
          ParseMethodDirectivesAndSemicolons(LContDirs);
          if IsSymbol(';') then
            Advance;
          LContDirs.Free;
          FDirectiveStmt := False;
        end
        else
        begin
          if IsKeyword(kwAsm) then
            ParseAsmStmt.Free
          else
            ParseCompoundStmt.Free;
          ExpectSemicolon;
          FDirectiveStmt := False;
        end;
      end;
      end;
    end;
    LImpl.LeadingTrivia.AddRange(LTrivia);
    Result := LImpl;
  end
  else
  begin
    LHeader.LeadingTrivia.AddRange(LTrivia);
    Result := LHeader;
  end;
  finally
    LTrivia.Free;
  end;
end;

function TDLDelphiParser.ParseMethodDirectives(
  ADirectives: TList<TDLDirective>): Boolean;
var
  LDirective: TDLDirective;
  LName: TDLIdentifier;
  LKeyword: TDLKeyword;
  LText: string;
begin
  Result := False;
  LKeyword := GetKeyword;
  case LKeyword of
    kwVirtual, kwDynamic, kwOverride, kwAbstract, kwReintroduce, kwOverload,
    kwStatic, kwFinal, kwSealed, kwInline, kwAssembler, kwForward,
    kwPlatform, kwExperimental, kwVarargs, kwUnsafe, kwFar, kwNear,
    kwNoReturn,
    kwRegister, kwPascal, kwCdecl, kwStdcall, kwSafecall:
      begin
        LDirective := TDLDirective.Create(GetSpan, MakeIdentifier);
        ADirectives.Add(LDirective);
        Result := True;
      end;
    kwMessage:
      begin
        LDirective := TDLDirective.Create(GetSpan, MakeIdentifier);
        ADirectives.Add(LDirective);
        LDirective.Values.Add(ParseExpression);
        Result := True;
      end;
    kwDeprecated:
      begin
        LDirective := TDLDirective.Create(GetSpan, MakeIdentifier);
        ADirectives.Add(LDirective);
        if GetKind = tkString then
          LDirective.Values.Add(ParseStringSequence);
        Result := True;
      end;
    kwExternal:
      begin
        LDirective := TDLDirective.Create(GetSpan, MakeIdentifier);
        ADirectives.Add(LDirective);
        if IsIdentifier and (LowerCase(GetText) = 'framework') then
        begin
          // external framework 'Name' name '...'  (iOS)
          Advance;
          if GetKind = tkString then
            LDirective.Values.Add(ParseStringSequence);
        end;
        if GetKind = tkString then
          LDirective.Values.Add(ParseStringSequence)
        else if (IsIdentifier or IsSoftNameKeyword) and
                (GetKeyword <> kwName) and (GetKeyword <> kwIndex) then
          // external <const-name> [name '...']  (the external library may be
          // a constant, e.g. RTLHelperLibName)
          LDirective.Values.Add(TDLIdentifierExpr.Create(GetSpan,
            MakeIdentifier));
        // external {$IFDEF A}lib1{$ELSE}lib2{$ENDIF} [name 'x'];
        while HasConditionalStartTrivia and
              ((IsIdentifier or IsSoftNameKeyword) and
               (GetKeyword <> kwName) and (GetKeyword <> kwIndex)) do
          MakeIdentifier.Free;
        if IsKeyword(kwName) then
        begin
          Advance;
          // name '_' + 'x'  or  name SomeConst  (expression handles string
          // concatenation and identifiers).
          LDirective.Values.Add(ParseExpression);
        end;
        if IsKeyword(kwIndex) then
        begin
          Advance;
          LDirective.Values.Add(ParseExpression);
        end;
        // More conditional branches may follow the name/index specifier.
        while HasConditionalStartTrivia and
              (IsIdentifier or IsSoftNameKeyword) do
        begin
          MakeIdentifier.Free; // branch keyword (name) or library name
          // Consume the branch value until the next branch or the ';'.
          while (GetKind <> tkEOF) and (not IsSymbol(';')) and
                (not HasConditionalStartTrivia) do
            ParseExpression.Free; // the branch's value
        end;
        Result := True;
      end;
  else
    LText := GetText;
    if IsIdentifier and (LowerCase(LText) = 'dispid') then
    begin
      LDirective := TDLDirective.Create(GetSpan, MakeIdentifier);
      ADirectives.Add(LDirective);
      LDirective.Values.Add(ParseExpression);
      Result := True;
      Exit;
    end;
    if IsIdentifier and
       ((LowerCase(LText) = 'winapi') or (LowerCase(LText) = 'export') or
        (LowerCase(LText) = 'delayed') or (LowerCase(LText) = 'safecall') or
        (LowerCase(LText) = 'local')) then
    begin
      LName := MakeIdentifier;
      LDirective := TDLDirective.Create(LName.Span, LName);
      ADirectives.Add(LDirective);
      Result := True;
    end;
  end;
end;

function TDLDelphiParser.IsMethodDirectiveStart: Boolean;
var
  LText: string;
begin
  case GetKeyword of
    kwVirtual, kwDynamic, kwOverride, kwAbstract, kwReintroduce, kwOverload,
    kwStatic, kwFinal, kwSealed, kwInline, kwAssembler, kwForward,
    kwPlatform, kwExperimental, kwVarargs, kwUnsafe, kwFar, kwNear,
    kwNoReturn,
    kwRegister, kwPascal, kwCdecl, kwStdcall, kwSafecall, kwMessage,
    kwDeprecated, kwExternal:
      Result := True;
  else
    LText := GetText;
    Result := IsIdentifier and
      ((LowerCase(LText) = 'winapi') or (LowerCase(LText) = 'export') or
       (LowerCase(LText) = 'delayed') or (LowerCase(LText) = 'dispid') or
       (LowerCase(LText) = 'local'));
  end;
end;

procedure TDLDelphiParser.ParseMethodDirectivesAndSemicolons(
  ADirectives: TList<TDLDirective>);
var
  LSavePos: Integer;
begin
  while True do
  begin
    while ParseMethodDirectives(ADirectives) do
      ;
    if not IsSymbol(';') then
      Break;
    LSavePos := FPos;
    Advance;
    if IsMethodDirectiveStart then
      Continue
    else
    begin
      // The ';' terminates the header (next is a body or another member).
      FPos := LSavePos;
      Break;
    end;
  end;
end;

function TDLDelphiParser.ParsePropertyDecl: TDLPropertyDecl;
var
  LProperty: TDLPropertyDecl;
  LName: TDLIdentifier;
begin
  ExpectKeyword(kwProperty);
  LName := MakeIdentifier;
  LProperty := TDLPropertyDecl.Create(GetSpan, LName, FCurrentVisibility);
  TakeLeadingTrivia(LProperty);
  // indexed property parameters
  if IsSymbol('[') then
  begin
    Advance;
    while (GetKind <> tkEOF) and (not IsSymbol(']')) do
    begin
      LProperty.IndexParams.Add(ParseParameter);
      if IsSymbol(';') then
        Advance;
    end;
    ExpectSymbol(']');
  end;
  if IsSymbol(':') then
  begin
    Advance;
    LProperty.TypeExpr := ParseTypeExpr;
  end;
  if IsKeyword(kwIndex) then
  begin
    Advance;
    LProperty.IndexSpec := ParseExpression;
  end;
  if IsKeyword(kwRead) then
  begin
    Advance;
    if IsKeyword(kwFunction) then
      Advance;
    LProperty.ReadName := MakeIdentifier;
    LProperty.ReadIsFunc := True;
    while HasConditionalStartTrivia and (IsIdentifier or IsSoftNameKeyword) do
      MakeIdentifier.Free; // alternate branch: read {$IFNDEF X}A{$ELSE}B{$ENDIF}
  end;
  if IsKeyword(kwWrite) then
  begin
    Advance;
    if IsKeyword(kwFunction) then
      Advance;
    LProperty.WriteName := MakeIdentifier;
    LProperty.WriteIsFunc := True;
    while HasConditionalStartTrivia and (IsIdentifier or IsSoftNameKeyword) do
      MakeIdentifier.Free;
  end;
  if IsKeyword(kwStored) then
  begin
    Advance;
    if IsKeyword(kwFunction) then
      Advance;
    if (GetKind = tkIdentifier) then
    begin
      LProperty.StoredName := MakeIdentifier;
      LProperty.StoredIsFunc := True;
    end
    else
      LProperty.StoredExpr := ParseExpression;
  end;
  if IsKeyword(kwDefault) then
  begin
    Advance;
    LProperty.DefaultValue := ParseExpression;
    LProperty.IsDefault := True;
  end;
  if IsKeyword(kwNodefault) then
  begin
    Advance;
    LProperty.IsNodefault := True;
  end;
  if IsKeyword(kwImplements) then
  begin
    Advance;
    while IsIdentifier or (GetKind = tkKeyword) do
    begin
      LProperty.Implements.Add(TDLIdentifierExpr.Create(GetSpan, MakeIdentifier));
      if IsSymbol(',') then
        Advance
      else
        Break;
    end;
  end;
  if IsKeyword(kwReadOnly) then
    Advance;
  if IsKeyword(kwWriteOnly) then
    Advance;
  if IsIdentifier and (LowerCase(GetText) = 'dispid') then
  begin
    // dispinterface property:  property X: T readonly dispid N;
    Advance;
    if GetKind = tkInteger then
      Advance;
    if IsSymbol('-') and (Peek(1).Kind = tkInteger) then
    begin
      Advance; // dispid -4
      Advance;
    end;
  end;
  ExpectSemicolon;
  // A default/nodefault directive may also follow the terminating semicolon
  // (default array property marker: "property X: T read F; default;").
  if IsKeyword(kwDefault) then
  begin
    Advance;
    LProperty.IsDefault := True;
    ExpectSemicolon;
  end
  else if IsKeyword(kwNodefault) then
  begin
    Advance;
    LProperty.IsNodefault := True;
    ExpectSemicolon;
  end;
  Result := LProperty;
end;

{ ------------------------------------------------------------------ }
{ Statements                                                         }
{ ------------------------------------------------------------------ }

function TDLDelphiParser.ParseStatementList(
  ATerminators: TArray<TDLKeyword>): TList<TDLStatement>;
var
  LStatements: TList<TDLStatement>;
  LStatement: TDLStatement;
  i: Integer;
  LTerminated: Boolean;
  LPrevPos: Integer;
  LCond: TDLCondition;
begin
  LStatements := TList<TDLStatement>.Create;
  FDirectiveStmt := False;
  while GetKind <> tkEOF do
  begin
    LPrevPos := FPos;
    LTerminated := False;
    for i := Low(ATerminators) to High(ATerminators) do
      if IsKeyword(ATerminators[i]) then
      begin
        LTerminated := True;
        Break;
      end;
    if LTerminated then
      Break;
    if IsSymbol(';') then
    begin
      Advance;
      LStatements.Add(TDLEmptyStmt.Create(GetSpan));
      Continue;
    end;
    if HasConditionalStartTrivia then
      FDirectiveStmt := True;
    LCond := nil;
    if (LastConditionalDirective(LCond) = cdStart) and
       CanStartConditionalGroup(False) and SingleConditionalInTrivia then
      begin
        LCond.Free;
        LStatement := ParseConditionalStatementGroup;
      end
      else
      begin
        LCond.Free;
        LStatement := ParseStatement;
      end;
    if (FPos = LPrevPos) and (LStatement = nil) and (not IsSymbol(';')) then
      Advance; // resynchronise on an unexpected terminator/block keyword
    if LStatement <> nil then
      LStatements.Add(LStatement);
    if IsSymbol(';') then
      Advance;
    SkipConditionalExpressionBranches;
  end;
  Result := LStatements;
end;

function TDLDelphiParser.ParseStatement: TDLStatement;
var
  LStart: TDLSourceSpan;
  LExpression: TDLExpr;
  LTarget: TDLExpr;
  LKeyword: TDLKeyword;
  LLabelName: TDLIdentifier;
begin
  LStart := GetSpan;
  DLSetContext('stmt:' + GetText);
  Inc(FStmtDepth);
  if FStmtDepth > 200 then
    raise Exception.Create('DLP-FATAL: statement recursion at "' + GetText +
      '" line=' + IntToStr(GetSpan.Start.Line));
  if IsSymbol(';') then
  begin
    Result := TDLEmptyStmt.Create(LStart);
    Dec(FStmtDepth);
    Exit;
  end;
  LKeyword := GetKeyword;
  case LKeyword of
    kwBegin:
      if FDirectiveStmt or HasConditionalStartTrivia then
      begin
        // A begin introduced by a conditional-compilation directive
        // ({$IFDEF}/{$ELSE}/{$ENDIF}) continues the enclosing block (the
        // compiler evaluates conditionals; we parse every branch literally,
        // so a second "begin" inside a conditional body is not a nested
        // compound statement).
        Advance;
        FDirectiveStmt := False;
        Result := nil;
      end
      else
        Result := ParseCompoundStmt;
    kwIf: Result := ParseIfStmt;
    kwCase: Result := ParseCaseStmt;
    kwFor: Result := ParseForStmt;
    kwWhile: Result := ParseWhileStmt;
    kwRepeat: Result := ParseRepeatStmt;
    kwWith: Result := ParseWithStmt;
    kwTry: Result := ParseTryStmt;
    kwRaise: Result := ParseRaiseStmt;
    kwGoto: Result := ParseGotoStmt;
    kwExit:
      begin
        Advance;
        if IsSymbol(';') or IsKeyword(kwEnd) or IsKeyword(kwElse) or
           IsKeyword(kwUntil) then
          Result := TDLExitStmt.Create(LStart, nil)
        else
          Result := TDLExitStmt.Create(LStart, ParseExpression);
      end;
    kwBreak: begin Advance; Result := TDLBreakStmt.Create(LStart); end;
    kwContinue: begin Advance; Result := TDLContinueStmt.Create(LStart); end;
    kwAsm: Result := ParseAsmStmt;
    kwVar:
      Result := ParseVarDeclStmt;
    kwEnd, kwElse, kwUntil, kwFinally, kwExcept:
      Result := nil;
  else
    // label? identifier : or number : (not :=)
    if (IsIdentifier or (GetKind = tkInteger)) and IsSymbolAhead(':', 1) and
       (not IsSymbolAhead('=', 2)) then
    begin
      Result := ParseLabelStmt;
    end
    else
    begin
      LExpression := ParseExpression;
      if IsSymbol(':=') then
      begin
        Advance;
        LTarget := LExpression;
        LExpression := ParseExpression;
        // Conditional-compiled value:
        //   X := {$IFDEF A}1{$ELSE}2{$ENDIF};
        SkipConditionalBranchesToEndIf;
        Result := TDLAssignmentStmt.Create(TDLSourceSpan.Create(LStart.Start,
          GetSpan.Stop), LTarget, LExpression);
      end
      else
        Result := TDLExprStmt.Create(LStart, LExpression);
    end;
  end;
  Dec(FStmtDepth);
end;

function TDLDelphiParser.ParseCompoundStmt: TDLCompoundStmt;
var
  LCompound: TDLCompoundStmt;
  LStatements: TList<TDLStatement>;
  LStatement: TDLStatement;
begin
  Inc(FCompoundGuard);
  if FCompoundGuard > 5000000 then
    raise Exception.Create('DLP-FATAL: compound statement loop at "' +
      GetText + '"');
  LCompound := TDLCompoundStmt.Create(GetSpan);
  ExpectKeyword(kwBegin);
  LStatements := ParseStatementList([kwEnd]);
  for LStatement in LStatements do
    LCompound.Statements.Add(LStatement);
  LStatements.Free;
  ExpectKeyword(kwEnd);
  Result := LCompound;
end;

function TDLDelphiParser.ParseIfStmt: TDLIfStmt;
var
  LCondition: TDLExpr;
  LThen: TDLStatement;
  LIf: TDLIfStmt;
  LStart: TDLSourceSpan;
  LElse: TDLStatement;
begin
  LStart := GetSpan;
  ExpectKeyword(kwIf);
  LCondition := ParseExpression;
  // if {$IFDEF A}x{$ELSE}y{$ENDIF} then  (condition over conditional
  // branches; keep the first branch, skip the alternates)
  while HasConditionalStartTrivia and
        (IsIdentifier or IsSoftNameKeyword or
         (GetKind in [tkInteger, tkString, tkFloat, tkCharCode]) or
         IsKeyword(kwNot)) do
  begin
    ParseExpression.Free;
    if IsKeyword(kwThen) then
      Break;
  end;
  ExpectKeyword(kwThen);
  FDirectiveStmt := False; // do not leak the list's directive flag into the branch
  LThen := ParseStatement;
  LIf := TDLIfStmt.Create(LStart, LCondition, LThen);
  if IsKeyword(kwElse) then
  begin
    Advance;
    FDirectiveStmt := False;
    LElse := ParseStatement;
    LIf.ElseBranch := LElse;
    SkipConditionalExpressionBranches;
  end;
  Result := LIf;
end;

function TDLDelphiParser.ParseCaseStmt: TDLCaseStmt;
var
  LStart: TDLSourceSpan;
  LSubject: TDLExpr;
  LCase: TDLCaseStmt;
  LSelector: TDLCaseSelector;
  LPrevPos: Integer;
  LGuard: Integer;
begin
  LStart := GetSpan;
  ExpectKeyword(kwCase);
  LSubject := ParseExpression;
  ExpectKeyword(kwOf);
  LCase := TDLCaseStmt.Create(LStart, LSubject);
  while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
  begin
    if IsKeyword(kwElse) then
    begin
      Advance;
      LCase.ElseBranch := TDLCompoundStmt.Create(GetSpan);
      LGuard := 0;
      while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
      begin
        Inc(LGuard);
        if LGuard > 5000000 then
          raise Exception.Create('DLP-FATAL: case else loop');
        LPrevPos := FPos;
        if IsSymbol(';') then
        begin
          Advance;
          Continue;
        end;
        TDLCompoundStmt(LCase.ElseBranch).Statements.Add(ParseStatement);
        if FPos = LPrevPos then
          Advance; // resynchronise on an unexpected terminator
        if IsSymbol(';') then
          Advance;
      end;
      Break;
    end;
    if not IsCaseLabelStart then
    begin
      Error('Expected case label');
      SkipUntil([kwEnd]);
      Break;
    end;
    LSelector := TDLCaseSelector.Create(GetSpan);
    while True do
    begin
      LSelector.Labels.Add(ParseExpression);
      if IsSymbol('..') then
      begin
        Advance;
        LSelector.Labels.Add(ParseExpression);
      end;
      if IsSymbol(',') then
        Advance
      else
        Break;
    end;
    ExpectSymbol(':');
    // statement(s) until next selector label, else or end
    while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) and
          (not IsKeyword(kwElse)) and (not IsCaseLabelStart) do
    begin
      LPrevPos := FPos;
      if IsSymbol(';') then
      begin
        Advance;
        Continue;
      end;
      FDirectiveStmt := False;
      LSelector.Statement := ParseStatement;
      if FPos = LPrevPos then
        Advance; // resynchronise on an unexpected terminator
      if IsSymbol(';') then
        Advance;
      if LSelector.Statement is TDLCompoundStmt then
        Break;
    end;
    LCase.Selectors.Add(LSelector);
  end;
  ExpectKeyword(kwEnd);
  Result := LCase;
end;

function TDLDelphiParser.IsCaseLabelStart: Boolean;
var
  LKind: TDLTokenKind;
  LIndex: Integer;
  LDepth: Integer;
begin
  LKind := GetKind;
  Result := False;
  if (LKind = tkInteger) or (LKind = tkString) or (LKind = tkCharCode) then
    Result := True
  else if LKind = tkIdentifier then
  begin
    // An identifier (optionally qualified: Enum.Member) is a case label when
    // followed by a selector separator/range/colon (never by ":=").
    LIndex := 1;
    while (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '.') do
      Inc(LIndex, 2);
    // Case label with 'or'/'and':  A or B or C:
    while (Peek(LIndex).Kind = tkKeyword) and
          ((Peek(LIndex).Text = 'or') or (Peek(LIndex).Text = 'and')) do
      Inc(LIndex, 2);
    // with '+'/'-':  A + B, A - B:
    while (Peek(LIndex).Kind = tkSymbol) and
          ((Peek(LIndex).Text = '+') or (Peek(LIndex).Text = '-')) and
          ((Peek(LIndex + 1).Kind = tkIdentifier) or
           (Peek(LIndex + 1).Kind = tkKeyword)) do
      Inc(LIndex, 2);
    // Case label may be a call:  SizeOf(Byte):
    if (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '(') then
    begin
      LDepth := 0;
      while (Peek(LIndex).Kind <> tkEOF) do
      begin
        if (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = '(') then
          Inc(LDepth)
        else if (Peek(LIndex).Kind = tkSymbol) and (Peek(LIndex).Text = ')') then
        begin
          Dec(LDepth);
          if LDepth = 0 then
          begin
            Inc(LIndex);
            Break;
          end;
        end;
        Inc(LIndex);
      end;
    end;
    Result := (Peek(LIndex).Kind = tkSymbol) and
      ((Peek(LIndex).Text = ',') or (Peek(LIndex).Text = '..') or
       (Peek(LIndex).Text = ':'));
  end
  else if (LKind = tkSymbol) and (GetText = '-') and
          (Peek(1).Kind = tkInteger) then
    Result := True;
end;

function TDLDelphiParser.ParseForStmt: TDLForStmt;
var
  LStart: TDLSourceSpan;
  LLoopVar: TDLIdentifier;
  LIsInline: Boolean;
  LDirection: TDLKeyword;
  LFor: TDLForStmt;
  LStartExpr: TDLExpr;
begin
  LStart := GetSpan;
  ExpectKeyword(kwFor);
  LIsInline := False;
  if IsKeyword(kwVar) then
  begin
    LIsInline := True;
    Advance;
  end;
  LLoopVar := MakeIdentifier;
  LDirection := kwNone;
  if IsSymbol(':=') then
  begin
    Advance;
    LStartExpr := ParseExpression;
    if IsKeyword(kwTo) then
      LDirection := kwTo
    else if IsKeyword(kwDownTo) then
      LDirection := kwDownTo
    else
      Error('Expected "to" or "downto" in for loop');
    if LDirection <> kwNone then
      Advance;
    LFor := TDLForStmt.Create(LStart, LLoopVar, LIsInline, LDirection);
    LFor.StartExpr := LStartExpr;
    LFor.EndExpr := ParseExpression;
    ExpectKeyword(kwDo);
  end
  else if IsKeyword(kwTo) or IsKeyword(kwDownTo) then
  begin
    if IsKeyword(kwTo) then
      LDirection := kwTo
    else
      LDirection := kwDownTo;
    Advance;
    LFor := TDLForStmt.Create(LStart, LLoopVar, LIsInline, LDirection);
    LFor.StartExpr := ParseExpression;
    ExpectKeyword(kwDo);
  end
  else if IsKeyword(kwIn) then
  begin
    Advance;
    LFor := TDLForStmt.Create(LStart, LLoopVar, LIsInline, kwIn);
    LFor.EndExpr := ParseExpression;
    ExpectKeyword(kwDo);
  end
  else
  begin
    LDirection := kwIn;
    LFor := TDLForStmt.Create(LStart, LLoopVar, LIsInline, kwIn);
    LFor.EndExpr := ParseExpression;
    ExpectKeyword(kwDo);
  end;
  FDirectiveStmt := False;
  LFor.Body := ParseStatement;
  Result := LFor;
end;

function TDLDelphiParser.ParseWhileStmt: TDLWhileStmt;
var
  LStart: TDLSourceSpan;
  LCondition: TDLExpr;
  LWhile: TDLWhileStmt;
begin
  LStart := GetSpan;
  ExpectKeyword(kwWhile);
  LCondition := ParseExpression;
  ExpectKeyword(kwDo);
  LWhile := TDLWhileStmt.Create(LStart, LCondition);
  FDirectiveStmt := False;
  LWhile.Body := ParseStatement;
  Result := LWhile;
end;

function TDLDelphiParser.ParseRepeatStmt: TDLRepeatStmt;
var
  LStart: TDLSourceSpan;
  LRepeat: TDLRepeatStmt;
  LStatements: TList<TDLStatement>;
  LStatement: TDLStatement;
begin
  LStart := GetSpan;
  ExpectKeyword(kwRepeat);
  LRepeat := TDLRepeatStmt.Create(LStart);
  LStatements := ParseStatementList([kwUntil]);
  for LStatement in LStatements do
  begin
    if LRepeat.Body = nil then
      LRepeat.Body := TDLCompoundStmt.Create(LStart);
    TDLCompoundStmt(LRepeat.Body).Statements.Add(LStatement);
  end;
  LStatements.Free;
  ExpectKeyword(kwUntil);
  LRepeat.Condition := ParseExpression;
  Result := LRepeat;
end;

function TDLDelphiParser.ParseWithStmt: TDLWithStmt;
var
  LStart: TDLSourceSpan;
  LWith: TDLWithStmt;
begin
  LStart := GetSpan;
  ExpectKeyword(kwWith);
  LWith := TDLWithStmt.Create(LStart);
  while True do
  begin
    LWith.Expressions.Add(ParseExpression);
    if IsSymbol(',') then
      Advance
    else
      Break;
  end;
  ExpectKeyword(kwDo);
  FDirectiveStmt := False;
  LWith.Body := ParseStatement;
  Result := LWith;
end;

function TDLDelphiParser.ParseTryStmt: TDLTryStmt;
var
  LStart: TDLSourceSpan;
  LTry: TDLTryStmt;
  LStatements: TList<TDLStatement>;
  LStatement: TDLStatement;
  LHandler: TDLOnHandler;
  LTypeName: TDLIdentifier;
  LPrevPos: Integer;
begin
  Inc(FCompoundGuard);
  if FCompoundGuard > 5000000 then
    raise Exception.Create('DLP-FATAL: try statement loop at "' +
      GetText + '"');
  LStart := GetSpan;
  ExpectKeyword(kwTry);
  LStatements := ParseStatementList([kwExcept, kwFinally, kwEnd]);
  LTry := TDLTryStmt.Create(LStart, IsKeyword(kwExcept));
  LTry.Body := TDLCompoundStmt.Create(LStart);
  for LStatement in LStatements do
    TDLCompoundStmt(LTry.Body).Statements.Add(LStatement);
  LStatements.Free;
  if LTry.IsExcept then
  begin
    Advance; // except
    while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
    begin
      if IsKeyword(kwOn) then
      begin
        Advance;
        LHandler := TDLOnHandler.Create(GetSpan);
        if IsIdentifier and IsSymbolAhead(':', 1) then
        begin
          LHandler.VarName := MakeIdentifier;
          ExpectSymbol(':');
          LHandler.TypeName := MakeIdentifier;
          LTypeName := LHandler.TypeName;
          ExpandDottedName(LTypeName); // on E: System.SysUtils.Exxx
          LHandler.TypeName := LTypeName;
        end
        else if IsIdentifier then
        begin
          LHandler.TypeName := MakeIdentifier;
          LTypeName := LHandler.TypeName;
          ExpandDottedName(LTypeName); // on System.SysUtils.Exxx do
          LHandler.TypeName := LTypeName;
        end;
        ExpectKeyword(kwDo);
        FDirectiveStmt := False;
        LHandler.Body := ParseStatement;
        LTry.OnHandlers.Add(LHandler);
      end
      else if IsKeyword(kwElse) then
      begin
        Advance;
        Inc(FCompoundGuard);
        if FCompoundGuard > 5000000 then
          raise Exception.Create('DLP-FATAL: try-else loop');
        LTry.ElseBranch := TDLCompoundStmt.Create(GetSpan);
        while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
        begin
          LPrevPos := FPos;
          if IsSymbol(';') then
          begin
            Advance;
            Continue;
          end;
          TDLCompoundStmt(LTry.ElseBranch).Statements.Add(ParseStatement);
          if FPos = LPrevPos then
            Advance; // resynchronise
          if IsSymbol(';') then
            Advance;
        end;
      end
      else
      begin
        // statements in except block (without on-handlers)
        if IsSymbol(';') then
          Advance
        else
          ParseStatement;
      end;
    end;
    ExpectKeyword(kwEnd);
  end
  else
  begin
    Advance; // finally
    Inc(FCompoundGuard);
    if FCompoundGuard > 5000000 then
      raise Exception.Create('DLP-FATAL: try-finally loop');
    LTry.FinallyBody := TDLCompoundStmt.Create(GetSpan);
    while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
    begin
      LPrevPos := FPos;
      if IsSymbol(';') then
      begin
        Advance;
        Continue;
      end;
      TDLCompoundStmt(LTry.FinallyBody).Statements.Add(ParseStatement);
      if FPos = LPrevPos then
        Advance; // resynchronise
      if IsSymbol(';') then
        Advance;
    end;
    ExpectKeyword(kwEnd);
  end;
  Result := LTry;
end;

function TDLDelphiParser.ParseRaiseStmt: TDLRaiseStmt;
var
  LStart: TDLSourceSpan;
  LException: TDLExpr;
begin
  LStart := GetSpan;
  ExpectKeyword(kwRaise);
  if IsSymbol(';') or IsKeyword(kwEnd) or IsKeyword(kwElse) or IsKeyword(kwUntil) then
    LException := nil
  else
    LException := ParseExpression;
  Result := TDLRaiseStmt.Create(LStart, LException);
  if IsKeyword(kwAt) then
  begin
    Advance;
    Result.AtAddr := ParseExpression;
  end;
end;

function TDLDelphiParser.ParseGotoStmt: TDLGotoStmt;
var
  LStart: TDLSourceSpan;
  LLabelName: TDLIdentifier;
begin
  LStart := GetSpan;
  ExpectKeyword(kwGoto);
  LLabelName := MakeIdentifier;
  Result := TDLGotoStmt.Create(LStart, LLabelName);
end;

function TDLDelphiParser.ParseAsmStmt: TDLAsmStmt;
var
  LStart: TDLSourceSpan;
  LStartOffset: Integer;
  LText: string;
begin
  LStart := GetSpan;
  ExpectKeyword(kwAsm);
  LStartOffset := GetSpan.Stop.Offset;
  while (GetKind <> tkEOF) and (not IsKeyword(kwEnd)) do
    Advance;
  LText := Copy(FSource, LStartOffset + 1, GetSpan.Start.Offset - LStartOffset);
  ExpectKeyword(kwEnd);
  Result := TDLAsmStmt.Create(LStart, LText);
end;

function TDLDelphiParser.ParseLabelStmt: TDLLabelStmt;
var
  LStart: TDLSourceSpan;
  LLabelName: TDLIdentifier;
begin
  LStart := GetSpan;
  LLabelName := MakeIdentifier;
  ExpectSymbol(':');
  Result := TDLLabelStmt.Create(LStart, LLabelName);
  if IsSymbol(';') then
  begin
    Advance;
    Result.Statement := TDLEmptyStmt.Create(GetSpan);
  end
  else
    FDirectiveStmt := False;
    Result.Statement := ParseStatement;
end;

function TDLDelphiParser.ParseVarDeclStmt: TDLVarDeclStmt;
var
  LStart: TDLSourceSpan;
  LDecl: TDLVarDecl;
begin
  LStart := GetSpan;
  ExpectKeyword(kwVar);
  LDecl := ParseVarDecl;
  Result := TDLVarDeclStmt.Create(LStart, LDecl);
  // Conditional compilation can place several var declarations after a single
  // var keyword inside a body; parse (and discard) any further declarations.
  while (IsIdentifier or IsSoftNameKeyword) and
        (IsSymbolAhead(':', 1) or IsSymbolAhead(',', 1)) do
    ParseVarDecl.Free;
end;

{ ------------------------------------------------------------------ }
{ Expressions                                                        }
{ ------------------------------------------------------------------ }

function TDLDelphiParser.GetBinaryOp(out AOperator: TDLBinaryOp;
  out AText: string; out APrecedence: Integer): Boolean;
begin
  Result := True;
  case GetKeyword of
    kwOr: begin AOperator := boOr; AText := 'or'; APrecedence := 1; end;
    kwXor: begin AOperator := boXor; AText := 'xor'; APrecedence := 1; end;
    kwAnd: begin AOperator := boAnd; AText := 'and'; APrecedence := 2; end;
    kwDiv: begin AOperator := boDiv; AText := 'div'; APrecedence := 2; end;
    kwMod: begin AOperator := boMod; AText := 'mod'; APrecedence := 2; end;
    kwShl: begin AOperator := boShl; AText := 'shl'; APrecedence := 2; end;
    kwShr: begin AOperator := boShr; AText := 'shr'; APrecedence := 2; end;
    kwAs: begin AOperator := boAs; AText := 'as'; APrecedence := 2; end;
    kwIn: begin AOperator := boIn; AText := 'in'; APrecedence := 0; end;
    kwIs: begin AOperator := boIs; AText := 'is'; APrecedence := 0; end;
  else
    if IsSymbol('+') then begin AOperator := boAdd; AText := '+'; APrecedence := 1; end
    else if IsSymbol('-') then begin AOperator := boSubtract; AText := '-'; APrecedence := 1; end
    else if IsSymbol('*') then begin AOperator := boMultiply; AText := '*'; APrecedence := 2; end
    else if IsSymbol('/') then begin AOperator := boDivide; AText := '/'; APrecedence := 2; end
    else if IsSymbol('=') then begin AOperator := boEqual; AText := '='; APrecedence := 0; end
    else if IsSymbol('<>') then begin AOperator := boNotEqual; AText := '<>'; APrecedence := 0; end
    else if IsSymbol('<') then begin AOperator := boLess; AText := '<'; APrecedence := 0; end
    else if IsSymbol('<=') then begin AOperator := boLessEqual; AText := '<='; APrecedence := 0; end
    else if IsSymbol('>') then begin AOperator := boGreater; AText := '>'; APrecedence := 0; end
    else if IsSymbol('>=') then begin AOperator := boGreaterEqual; AText := '>='; APrecedence := 0; end
    else
      Result := False;
  end;
end;

function TDLDelphiParser.ParseExpression: TDLExpr;
begin
  DLSetContext('expr:' + GetText);
  Inc(FStmtDepth);
  if FStmtDepth > 200 then
    raise Exception.Create('DLP-FATAL: expression recursion at "' + GetText +
      '" line=' + IntToStr(GetSpan.Start.Line));
  try
    Result := ParseBinary(0);
  finally
    Dec(FStmtDepth);
  end;
end;

function TDLDelphiParser.ParseBinary(AMinPrec: Integer): TDLExpr;
var
  LLeft: TDLExpr;
  LOperator: TDLBinaryOp;
  LText: string;
  LPrec: Integer;
  LRight: TDLExpr;
  LStart: TDLSourceSpan;
begin
  LLeft := ParseUnary;
  while True do
  begin
    if not GetBinaryOp(LOperator, LText, LPrec) then
      Break;
    if LPrec < AMinPrec then
      Break;
    LStart := GetSpan;
    Advance;
    LRight := ParseBinary(LPrec + 1);
    LLeft := TDLBinaryExpr.Create(TDLSourceSpan.Create(LStart.Start,
      GetSpan.Stop), LOperator, LText, LLeft, LRight);
  end;
  Result := LLeft;
end;

function TDLDelphiParser.ParseUnary: TDLExpr;
var
  LStart: TDLSourceSpan;
  LOperand: TDLExpr;
begin
  LStart := GetSpan;
  if IsSymbol('@') then
  begin
    Advance;
    LOperand := ParseUnary;
    Result := TDLUnaryExpr.Create(TDLSourceSpan.Create(LStart.Start,
      GetSpan.Stop), uoAddr, '@', LOperand);
  end
  else if IsKeyword(kwNot) then
  begin
    Advance;
    LOperand := ParseUnary;
    Result := TDLUnaryExpr.Create(TDLSourceSpan.Create(LStart.Start,
      GetSpan.Stop), uoNot, 'not', LOperand);
  end
  else if IsSymbol('-') then
  begin
    Advance;
    LOperand := ParseUnary;
    Result := TDLUnaryExpr.Create(TDLSourceSpan.Create(LStart.Start,
      GetSpan.Stop), uoMinus, '-', LOperand);
  end
  else if IsSymbol('+') then
  begin
    Advance;
    LOperand := ParseUnary;
    Result := TDLUnaryExpr.Create(TDLSourceSpan.Create(LStart.Start,
      GetSpan.Stop), uoPlus, '+', LOperand);
  end
  else
    Result := ParsePostfix;
end;

function TDLDelphiParser.ParsePostfix: TDLExpr;
var
  LExpression: TDLExpr;
  LMember: TDLIdentifier;
  LIndex: TDLIndexExpr;
  LStart: TDLSourceSpan;
  LArgs: TList<TDLExpr>;
  LArg: TDLExpr;
  LSavePos: Integer;
  LTypeArgs: TList<TDLTypeArg>;
  LOk: Boolean;
  LNext: TDLToken;
begin
  LExpression := ParsePrimary;
  while True do
  begin
    if IsSymbol('.') then
    begin
      Advance;
      if IsIdentifier or (GetKind = tkKeyword) then
      begin
        LMember := MakeIdentifier;
        LExpression := TDLMemberExpr.Create(TDLSourceSpan.Create(
          LExpression.Span.Start, GetSpan.Stop), LExpression, LMember);
      end
      else
        Error('Expected member name after "."');
    end
    else if IsSymbol('[') then
    begin
      Advance;
      LIndex := TDLIndexExpr.Create(LExpression.Span, LExpression);
      while (GetKind <> tkEOF) and (not IsSymbol(']')) do
      begin
        LIndex.Indices.Add(ParseExpression);
        if IsSymbol(',') then
          Advance;
      end;
      ExpectSymbol(']');
      LExpression := LIndex;
    end
    else if IsSymbol('(') then
    begin
      LStart := GetSpan;
      LArgs := ParseCallArgs;
      LExpression := TDLCallExpr.Create(TDLSourceSpan.Create(
        LExpression.Span.Start, GetSpan.Stop), LExpression);
      for LArg in LArgs do
        TDLCallExpr(LExpression).Args.Add(LArg);
      LArgs.Free;
    end
    else if IsSymbol('<') then
    begin
      // speculative generic instantiation
      LSavePos := FPos;
      LTypeArgs := nil;
      LOk := False;
      Inc(FSuppressCount);
      try
      Advance;
      LTypeArgs := TList<TDLTypeArg>.Create;
      while (GetKind <> tkEOF) and (not IsSymbol('>')) do
      begin
        if IsSymbol(',') then
          Advance
        else
        begin
          // Bound the speculation: real generic arguments are few. Abort
          // once this limit is reached so 'a < b' comparisons never scan
          // the rest of the file as type arguments.
          if LTypeArgs.Count >= 12 then
          begin
            LOk := False;
            Break;
          end;
          LTypeArgs.Add(ParseTypeArg);
        end;
      end;
      if IsSymbol('>') then
      begin
        LNext := Peek(1);
        if ((LNext.Kind = tkSymbol) and
            ((LNext.Text = '(') or (LNext.Text = ')') or (LNext.Text = ';') or
             (LNext.Text = ':') or (LNext.Text = ',') or (LNext.Text = '=') or
             (LNext.Text = '.') or (LNext.Text = '[') or (LNext.Text = ']') or
             (LNext.Text = '<>') or (LNext.Text = '<=') or
             (LNext.Text = '>='))) or
           (LNext.Kind = tkKeyword) then
        begin
          Advance; // '>'
          LOk := True;
        end;
      end;
      finally
        if not LOk then
        begin
          FPos := LSavePos;
          LTypeArgs.Free;
        end;
        Dec(FSuppressCount);
      end;
      if LOk then
      begin
        LExpression := TDLGenericInstantiationExpr.Create(
          TDLSourceSpan.Create(LExpression.Span.Start, GetSpan.Stop),
          LExpression);
        TDLGenericInstantiationExpr(LExpression).TypeArgs.AddRange(LTypeArgs);
        LTypeArgs := nil;
      end
      else
        Break; // treat '<' as comparison in the caller
    end
    else if IsSymbol('^') then
    begin
      Advance;
      LExpression := TDLUnaryExpr.Create(TDLSourceSpan.Create(
        LExpression.Span.Start, GetSpan.Stop), uoDeref, '^', LExpression);
    end
    else
      Break;
  end;
  Result := LExpression;
end;

function TDLDelphiParser.ParseCallArgs: TList<TDLExpr>;
var
  LArgs: TList<TDLExpr>;
begin
  LArgs := TList<TDLExpr>.Create;
  ExpectSymbol('(');
  while (GetKind <> tkEOF) and (not IsSymbol(')')) do
  begin
    LArgs.Add(ParseExpression);
    // A call argument may contain a conditional-compilation type cast:
    // ({$IFDEF A}TypeA{$ELSE}TypeB{$ENDIF}(value))  -- keep the first branch,
    // parse (and discard) the alternates.
    while HasDirectiveTrivia and
          (IsIdentifier or IsSoftNameKeyword or
           (GetKind in [tkString, tkInteger, tkFloat, tkCharCode])) do
    begin
      ParseExpression.Free;
      Break; // the separator (',' or ')') is handled by the caller
    end;
    if IsSymbol(',') then
      Advance
    else
      Break;
  end;
  ExpectSymbol(')');
  Result := LArgs;
end;

function TDLDelphiParser.ParsePrimary: TDLExpr;
var
  LStart: TDLSourceSpan;
  LName: TDLIdentifier;
  LTokenRef: TDLTokenRef;
  LExpression: TDLExpr;
begin
  LStart := GetSpan;
  if (GetKind = tkKeyword) and IsSoftNameKeyword then
  begin
    // Contextual keywords (index, name, on, at, break, ...) are identifiers
    // in expression position.
    LName := MakeIdentifier;
    Result := TDLIdentifierExpr.Create(LName.Span, LName);
    Exit;
  end;
  case GetKind of
    tkInteger:
      begin
        LTokenRef := TDLTokenRef.Create(GetKind, GetText, GetSpan);
        LTokenRef.IntegerValue := GetCur.IntegerValue;
        Advance;
        Result := TDLNumberExpr.Create(LStart, LTokenRef);
      end;
    tkFloat:
      begin
        LTokenRef := TDLTokenRef.Create(GetKind, GetText, GetSpan);
        LTokenRef.FloatValue := GetCur.FloatValue;
        Advance;
        Result := TDLNumberExpr.Create(LStart, LTokenRef);
      end;
    tkString, tkCharCode:
      Result := ParseStringSequence;
    tkIdentifier:
      begin
        LName := MakeIdentifier;
        Result := TDLIdentifierExpr.Create(LName.Span, LName);
      end;
  else
    case GetKeyword of
      kwNil:
        begin
          Advance;
          Result := TDLNilExpr.Create(LStart);
        end;
      kwInherited:
        begin
          Advance;
          if (GetKind = tkIdentifier) or IsSoftNameKeyword or
             IsSymbol('(') then
            Result := TDLInheritedExpr.Create(LStart, ParsePostfix)
          else
            Result := TDLInheritedExpr.Create(LStart, nil);
        end;
      kwProcedure, kwFunction:
        Result := ParseAnonymousMethod;
      kwReference:
        if IsKwAhead(kwTo, 1) then
        begin
          Advance;
          ExpectKeyword(kwTo);
          Result := ParseAnonymousMethod;
        end
        else
        begin
          // 'Reference' used as a plain identifier (a variable/type name).
          LName := MakeIdentifier;
          Result := TDLIdentifierExpr.Create(LName.Span, LName);
        end;
      kwNot, kwAnd, kwOr, kwXor, kwDiv, kwMod, kwShl, kwShr, kwAs, kwIn, kwIs,
      kwTo, kwDownTo:
        begin
          // these cannot start a primary; fall through to error
          Error(Format('Unexpected "%s" in expression', [GetText]));
          Result := TDLIdentifierExpr.Create(LStart,
            TDLIdentifier.Create(GetText, LStart));
        end;
    else
      if IsSymbol('(') then
      begin
        Advance;
        LExpression := ParseExpression;
        if IsSymbol(',') then
        begin
          // Parenthesized array constructor: (a, b, c).
          Result := TDLArrayExpr.Create(LStart);
          TDLArrayExpr(Result).Elements.Add(LExpression);
          while IsSymbol(',') do
          begin
            Advance;
            TDLArrayExpr(Result).Elements.Add(ParseExpression);
          end;
          ExpectSymbol(')');
        end
        else
        begin
          ExpectSymbol(')');
          Result := LExpression;
        end;
      end
      else if IsSymbol('[') then
        Result := ParseSetOrArrayConstructor
      else
      begin
        Error(Format('Unexpected "%s" in expression', [GetText]));
        Result := TDLIdentifierExpr.Create(LStart,
          TDLIdentifier.Create('?', LStart));
      end;
    end;
  end;
end;

function TDLDelphiParser.ParseStringSequence: TDLStringExpr;
var
  LStart: TDLSourceSpan;
  LTokenRef: TDLTokenRef;
  LValue: string;
begin
  LStart := GetSpan;
  LTokenRef := TDLTokenRef.Create(GetKind, GetText, GetSpan);
  LTokenRef.Value := GetCur.Value;
  LValue := GetCur.Value;
  Advance;
  while (GetKind = tkString) or (GetKind = tkCharCode) do
  begin
    LValue := LValue + GetCur.Value;
    Advance;
  end;
  Result := TDLStringExpr.Create(TDLSourceSpan.Create(LStart.Start,
    GetSpan.Stop), LTokenRef, LValue);
end;

function TDLDelphiParser.ParseSetOrArrayConstructor: TDLExpr;
var
  LStart: TDLSourceSpan;
  LSet: TDLSetExpr;
  LArray: TDLArrayExpr;
  LExpression: TDLExpr;
  LIsArray: Boolean;
begin
  LStart := GetSpan;
  ExpectSymbol('[');
  // decide: if first element is a type-like identifier followed by '(' it is
  // an array constructor of typed elements; we keep a single set-like node
  // unless elements contain ranges — simple heuristic: track ranges.
  LSet := TDLSetExpr.Create(LStart);
  LArray := TDLArrayExpr.Create(LStart);
  LIsArray := False;
  while (GetKind <> tkEOF) and (not IsSymbol(']')) do
  begin
    LExpression := ParseExpression;
    if IsSymbol('..') then
    begin
      Advance;
      LExpression := TDLBinaryExpr.Create(LExpression.Span, boNone, '..',
        LExpression, ParseExpression);
      LSet.Elements.Add(LExpression);
      LSet.IsRanges.Add(True);
    end
    else
    begin
      LSet.Elements.Add(LExpression);
      LSet.IsRanges.Add(False);
      LArray.Elements.Add(nil);
    end;
    if IsSymbol(',') then
      Advance
    else
      Break;
  end;
  ExpectSymbol(']');
  LArray.Free;
  Result := LSet;
end;

function TDLDelphiParser.ParseAnonymousMethod: TDLAnonymousMethodExpr;
var
  LKind: TDLProcKind;
  LMethod: TDLAnonymousMethodExpr;
  LStart: TDLSourceSpan;
  LIsReference: Boolean;
begin
  LStart := GetSpan;
  LIsReference := False;
  if IsKeyword(kwProcedure) then
  begin
    LKind := prProcedure;
    Advance;
  end
  else
  begin
    LKind := prFunction;
    Advance;
  end;
  LMethod := TDLAnonymousMethodExpr.Create(LStart, LKind, LIsReference);
  if IsSymbol('(') then
    LMethod.Params.AddRange(ParseParameterList);
  if (LKind = prFunction) and IsSymbol(':') then
  begin
    Advance;
    LMethod.ReturnType := ParseTypeExpr;
  end;
  // Local declarations (var/label/const/type) before the body.
  while IsKeyword(kwVar) or IsKeyword(kwLabel) or IsKeyword(kwConst) or
        IsKeyword(kwType) do
  begin
    case GetKeyword of
      kwVar: ParseVarSection(False).Free;
      kwLabel: ParseLabelSection.Free;
      kwConst: ParseConstSection.Free;
      kwType: ParseTypeSection.Free;
    end;
  end;
  if IsSymbol(';') then
    Advance // declaration-style anonymous method without a body
  else
    LMethod.Body := ParseCompoundStmt;
  Result := LMethod;
end;

constructor TDLDelphiParser.Create(ATokens: TObjectList<TDLToken>;
  ADiagnostics: TDLDiagnostics; const ASource: string);
begin
  inherited Create;
  FTokens := ATokens;
  FDiagnostics := ADiagnostics;
  FSource := ASource;
  FPos := 0;
  FSteps := 0;
  FCompoundGuard := 0;
  FStmtDepth := 0;
  FSuppressCount := 0;
  FConditionalDepth := 0;
  FDirectiveStmt := False;
  FCurrentVisibility := vsPublished;
  FCurrentStrict := False;
end;

function TDLDelphiParser.Parse: TDLCompilationUnit;
begin
  DLResetNodeCount;
  Result := ParseCompilationUnit;
end;

end.
