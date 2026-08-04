/// <summary>
///   DX.Delphi.Core — foundational types for the Delphi language model:
///   source positions and spans, token kinds, keyword table, diagnostics,
///   symbols, and the tree-dump base class shared by CST and AST.
/// </summary>
/// <remarks>
///   This unit has no dependencies on the other DX.Delphi units. It is the
///   shared vocabulary for the lexer, parser, CST, AST and lowering pass.
///
///   Design notes:
///     - Positions are 0-based byte offsets into the source text; Line and
///       Column are 1-based for human-readable diagnostics.
///     - Token kinds distinguish real tokens from trivia (whitespace,
///       comments and compiler directives) so the parser can attach trivia
///       to CST nodes instead of modelling it in the grammar.
///     - Keywords are case-insensitive and stored lower-case in the table;
///       &-escaped identifiers never collide with keywords.
///     - The symbol table is deliberately minimal: the CST -> AST lowering
///       pass records declarations so later semantic passes have a starting
///       point. Full name resolution is out of scope.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit DX.Delphi.Core;

interface

uses
  System.SysUtils,
  System.Classes;

type
  /// <summary>A 0-based offset plus 1-based line/column pair.</summary>
  TDLSourcePos = record
    Offset: Integer;
    Line: Integer;
    Column: Integer;
    constructor Create(AOffset, ALine, AColumn: Integer);
    function ToString: string;
  end;

  /// <summary>Half-open [Start, Stop) range in the source text.</summary>
  TDLSourceSpan = record
    Start: TDLSourcePos;
    Stop: TDLSourcePos;
    constructor Create(AStart, AStop: TDLSourcePos);
    function IsEmpty: Boolean;
    function ToString: string;
  end;

  /// <summary>Classification of a lexed token.</summary>
  TDLTokenKind = (
    tkEOF,          // end of file
    tkIdentifier,   // identifier (possibly &-escaped, unicode)
    tkKeyword,      // reserved word (see TDLKeyword)
    tkInteger,      // integer literal (dec/hex/bin, with _ separators)
    tkFloat,        // floating point literal
    tkString,       // quoted string literal (single or ''' multiline)
    tkCharCode,     // #<code> char-code sequence element
    tkSymbol,       // operator or punctuation
    tkWhitespace,   // trivia: space, tab, newline
    tkLineComment,  // trivia: // ... (incl. ///)
    tkBlockComment, // trivia: { ... } or (* ... *)
    tkDirective,    // trivia: {$ ... }
    tkUnknown       // lexing failure; text holds the offending run
  );

  /// <summary>Kind of a trivia item attached to a CST node.</summary>
  TDLTriviaKind = (
    trWhitespace,
    trLineComment,
    trBlockComment,
    trDirective
  );

  /// <summary>A single trivia item (whitespace, comment or directive).</summary>
  TDLTrivia = record
    Kind: TDLTriviaKind;
    Text: string;
    Span: TDLSourceSpan;
    constructor Create(AKind: TDLTriviaKind; const AText: string;
      ASpan: TDLSourceSpan);
    function ToString: string;
  end;

  /// <summary>Reserved words of the Delphi language (Delphi 13.x surface).</summary>
  TDLKeyword = (
    kwNone,
    kwAbsolute, kwAbstract, kwAnd, kwArray, kwAs, kwAsm, kwAssembler,
    kwAutomated, kwBegin, kwCase, kwCdecl, kwClass, kwConst, kwConstructor,
    kwContains, kwDefault, kwDeprecated, kwDestructor, kwDispInterface,
    kwDiv, kwDo, kwDownTo, kwDynamic, kwElse, kwEnd, kwExcept, kwExit,
    kwExperimental, kwExports, kwExternal, kwFar, kwFile, kwFinal,
    kwFinalization, kwFinally, kwFor, kwForward, kwFunction, kwGoto,
    kwIf, kwImplementation, kwImplements, kwIn, kwIndex, kwInherited,
    kwInitialization, kwInline, kwInterface, kwIs, kwLabel, kwLibrary,
    kwMessage, kwMod, kwNear, kwNil, kwNodefault, kwNot, kwObject, kwOf,
    kwOr, kwOut, kwOverload, kwOverride, kwPackage, kwPacked, kwPascal,
    kwPlatform, kwPrivate, kwProcedure, kwProgram, kwProperty, kwProtected,
    kwPublic, kwPublished, kwRaise, kwRead, kwReadOnly, kwRecord, kwReference,
    kwRegister, kwReintroduce, kwRepeat, kwRequires, kwResourcestring,
    kwSafecall, kwSealed, kwSet, kwShl, kwShr, kwStatic, kwStdcall,
    kwStored, kwStrict, kwString, kwThen, kwThreadvar, kwTo, kwTry, kwType,
    kwUnit, kwUnsafe, kwUntil, kwUses, kwVar, kwVarargs, kwVirtual,
    kwWhile, kwWith, kwWrite, kwWriteOnly, kwXor,
    // contextual/directive-like keywords used by the parser
    kwBreak, kwContinue, kwHelper, kwName, kwOn, kwOperator, kwRef, kwAt
  );

  /// <summary>Severity of a diagnostic message.</summary>
  TDLDiagnosticSeverity = (
    dsHint,
    dsWarning,
    dsError
  );

  /// <summary>Category of a declared symbol.</summary>
  TDLSymbolKind = (
    skUnit,
    skProgram,
    skLibrary,
    skPackage,
    skNamespace,
    skType,
    skTypeAlias,
    skEnumMember,
    skConst,
    skResourceString,
    skVar,
    skThreadVar,
    skField,
    skClassVar,
    skProperty,
    skParameter,
    skProcedure,
    skFunction,
    skConstructor,
    skDestructor,
    skOperator,
    skLabel,
    skLocalVar,
    skUnknown
  );

  TDLDiagnostic = class;
  TDLDiagnostics = class;

  /// <summary>A single compiler-style diagnostic with a source span.</summary>
  TDLDiagnostic = class
  private
    FSeverity: TDLDiagnosticSeverity;
    FCode: string;
    FMessage: string;
    FSpan: TDLSourceSpan;
  public
    constructor Create(ASeverity: TDLDiagnosticSeverity; const ACode,
      AMessage: string; ASpan: TDLSourceSpan);
    property Severity: TDLDiagnosticSeverity read FSeverity;
    property Code: string read FCode;
    property Message: string read FMessage;
    property Span: TDLSourceSpan read FSpan;
    function ToString: string; override;
  end;

  /// <summary>Ordered collection of diagnostics produced while lexing/parsing.</summary>
  TDLDiagnostics = class
  private
    FItems: TList;
    FHasErrors: Boolean;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TDLDiagnostic;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(ASeverity: TDLDiagnosticSeverity; const ACode, AMessage: string;
      ASpan: TDLSourceSpan); overload;
    procedure Add(ADiagnostic: TDLDiagnostic); overload;
    procedure Error(const ACode, AMessage: string; ASpan: TDLSourceSpan);
    procedure Warning(const ACode, AMessage: string; ASpan: TDLSourceSpan);
    procedure Hint(const ACode, AMessage: string; ASpan: TDLSourceSpan);
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TDLDiagnostic read GetItem; default;
    property HasErrors: Boolean read FHasErrors;
  end;

  /// <summary>Symbol table entry recorded during lowering.</summary>
  TDLSymbol = class
  private
    FName: string;
    FKind: TDLSymbolKind;
    FSpan: TDLSourceSpan;
  public
    constructor Create(const AName: string; AKind: TDLSymbolKind; ASpan: TDLSourceSpan);
    property Name: string read FName;
    property Kind: TDLSymbolKind read FKind;
    property Span: TDLSourceSpan read FSpan;
  end;

  /// <summary>Minimal, scope-less symbol table (declarations indexed by name).</summary>
  TDLSymbolTable = class
  private
    FItems: TStringList;
    function GetCount: Integer;
    function GetSymbol(AIndex: Integer): TDLSymbol;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(ASymbol: TDLSymbol);
    function Find(const AName: string): TDLSymbol;
    function Contains(const AName: string): Boolean;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TDLSymbol read GetSymbol; default;
  end;

  /// <summary>Base class for CST/AST nodes that can render a tree dump.</summary>
  TDLDumpable = class abstract
  public
    /// <summary>Appends an indented, human-readable tree fragment.</summary>
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); virtual; abstract;
    /// <summary>Convenience wrapper producing a full tree dump string.</summary>
    function DumpToString: string;
  end;

  /// <summary>Static helpers for tree dumps.</summary>
  TDLDump = class
  public
    class procedure Indent(ABuilder: TStringBuilder; AIndent: Integer);
    class procedure Line(ABuilder: TStringBuilder; AIndent: Integer;
      const AText: string); overload;
    class procedure Line(ABuilder: TStringBuilder; AIndent: Integer;
      const AText: string; const AArgs: array of const); overload;
  end;

  /// <summary>Static keyword table (lower-case names, case-insensitive lookup).</summary>
  TDLKeywords = class
  public
    class function ToKeyword(const AName: string): TDLKeyword;
    class function ToText(AKeyword: TDLKeyword): string;
    class function IsKeyword(const AName: string): Boolean;
  end;

const
  /// <summary>Human-readable names for token kinds (for dumps/tools).</summary>
  TDLTokenKindNames: array[TDLTokenKind] of string = (
    'eof', 'identifier', 'keyword', 'integer', 'float', 'string', 'charcode',
    'symbol', 'whitespace', 'linecomment', 'blockcomment', 'directive',
    'unknown');

  /// <summary>Human-readable names for symbol kinds (for dumps/tools).</summary>
  TDLSymbolKindNames: array[TDLSymbolKind] of string = (
    'unit', 'program', 'library', 'package', 'namespace', 'type', 'alias',
    'enum', 'const', 'resstr', 'var', 'threadvar', 'field', 'classvar',
    'property', 'param', 'proc', 'func', 'ctor', 'dtor', 'operator', 'label',
    'local', 'unknown');

implementation

uses
  System.Character;

type
  TDLKeywordEntry = record
    Name: string;
    Keyword: TDLKeyword;
  end;

const
  // Sorted alphabetically for binary search; used by TDLKeywords.
  CDLKeywordTable: array[0..118] of TDLKeywordEntry = (
    (Name: 'absolute';    Keyword: kwAbsolute),
    (Name: 'abstract';    Keyword: kwAbstract),
    (Name: 'and';         Keyword: kwAnd),
    (Name: 'array';       Keyword: kwArray),
    (Name: 'as';          Keyword: kwAs),
    (Name: 'asm';         Keyword: kwAsm),
    (Name: 'assembler';   Keyword: kwAssembler),
    (Name: 'at';          Keyword: kwAt),
    (Name: 'automated';   Keyword: kwAutomated),
    (Name: 'begin';       Keyword: kwBegin),
    (Name: 'break';       Keyword: kwBreak),
    (Name: 'case';        Keyword: kwCase),
    (Name: 'cdecl';       Keyword: kwCdecl),
    (Name: 'class';       Keyword: kwClass),
    (Name: 'const';       Keyword: kwConst),
    (Name: 'constructor'; Keyword: kwConstructor),
    (Name: 'contains';    Keyword: kwContains),
    (Name: 'continue';    Keyword: kwContinue),
    (Name: 'default';     Keyword: kwDefault),
    (Name: 'deprecated';  Keyword: kwDeprecated),
    (Name: 'destructor';  Keyword: kwDestructor),
    (Name: 'dispinterface'; Keyword: kwDispInterface),
    (Name: 'div';         Keyword: kwDiv),
    (Name: 'do';          Keyword: kwDo),
    (Name: 'downto';      Keyword: kwDownTo),
    (Name: 'dynamic';     Keyword: kwDynamic),
    (Name: 'else';        Keyword: kwElse),
    (Name: 'end';         Keyword: kwEnd),
    (Name: 'except';      Keyword: kwExcept),
    (Name: 'exit';        Keyword: kwExit),
    (Name: 'experimental'; Keyword: kwExperimental),
    (Name: 'exports';     Keyword: kwExports),
    (Name: 'external';    Keyword: kwExternal),
    (Name: 'far';         Keyword: kwFar),
    (Name: 'file';        Keyword: kwFile),
    (Name: 'final';       Keyword: kwFinal),
    (Name: 'finalization'; Keyword: kwFinalization),
    (Name: 'finally';     Keyword: kwFinally),
    (Name: 'for';         Keyword: kwFor),
    (Name: 'forward';     Keyword: kwForward),
    (Name: 'function';    Keyword: kwFunction),
    (Name: 'goto';        Keyword: kwGoto),
    (Name: 'helper';      Keyword: kwHelper),
    (Name: 'if';          Keyword: kwIf),
    (Name: 'implementation'; Keyword: kwImplementation),
    (Name: 'implements';  Keyword: kwImplements),
    (Name: 'in';          Keyword: kwIn),
    (Name: 'index';       Keyword: kwIndex),
    (Name: 'inherited';   Keyword: kwInherited),
    (Name: 'initialization'; Keyword: kwInitialization),
    (Name: 'inline';      Keyword: kwInline),
    (Name: 'interface';   Keyword: kwInterface),
    (Name: 'is';          Keyword: kwIs),
    (Name: 'label';       Keyword: kwLabel),
    (Name: 'library';     Keyword: kwLibrary),
    (Name: 'message';     Keyword: kwMessage),
    (Name: 'mod';         Keyword: kwMod),
    (Name: 'name';        Keyword: kwName),
    (Name: 'near';        Keyword: kwNear),
    (Name: 'nil';         Keyword: kwNil),
    (Name: 'nodefault';   Keyword: kwNodefault),
    (Name: 'not';         Keyword: kwNot),
    (Name: 'object';      Keyword: kwObject),
    (Name: 'of';          Keyword: kwOf),
    (Name: 'on';          Keyword: kwOn),
    (Name: 'operator';    Keyword: kwOperator),
    (Name: 'or';          Keyword: kwOr),
    (Name: 'out';         Keyword: kwOut),
    (Name: 'overload';    Keyword: kwOverload),
    (Name: 'override';    Keyword: kwOverride),
    (Name: 'package';     Keyword: kwPackage),
    (Name: 'packed';      Keyword: kwPacked),
    (Name: 'pascal';      Keyword: kwPascal),
    (Name: 'platform';    Keyword: kwPlatform),
    (Name: 'private';     Keyword: kwPrivate),
    (Name: 'procedure';   Keyword: kwProcedure),
    (Name: 'program';     Keyword: kwProgram),
    (Name: 'property';    Keyword: kwProperty),
    (Name: 'protected';   Keyword: kwProtected),
    (Name: 'public';      Keyword: kwPublic),
    (Name: 'published';   Keyword: kwPublished),
    (Name: 'raise';       Keyword: kwRaise),
    (Name: 'read';        Keyword: kwRead),
    (Name: 'readonly';    Keyword: kwReadOnly),
    (Name: 'record';      Keyword: kwRecord),
    (Name: 'ref';         Keyword: kwRef),
    (Name: 'reference';   Keyword: kwReference),
    (Name: 'register';    Keyword: kwRegister),
    (Name: 'reintroduce'; Keyword: kwReintroduce),
    (Name: 'repeat';      Keyword: kwRepeat),
    (Name: 'requires';    Keyword: kwRequires),
    (Name: 'resourcestring'; Keyword: kwResourcestring),
    (Name: 'safecall';    Keyword: kwSafecall),
    (Name: 'sealed';      Keyword: kwSealed),
    (Name: 'set';         Keyword: kwSet),
    (Name: 'shl';         Keyword: kwShl),
    (Name: 'shr';         Keyword: kwShr),
    (Name: 'static';      Keyword: kwStatic),
    (Name: 'stdcall';     Keyword: kwStdcall),
    (Name: 'stored';      Keyword: kwStored),
    (Name: 'strict';      Keyword: kwStrict),
    (Name: 'string';      Keyword: kwString),
    (Name: 'then';        Keyword: kwThen),
    (Name: 'threadvar';   Keyword: kwThreadvar),
    (Name: 'to';          Keyword: kwTo),
    (Name: 'try';         Keyword: kwTry),
    (Name: 'type';        Keyword: kwType),
    (Name: 'unit';        Keyword: kwUnit),
    (Name: 'unsafe';      Keyword: kwUnsafe),
    (Name: 'until';       Keyword: kwUntil),
    (Name: 'uses';        Keyword: kwUses),
    (Name: 'var';         Keyword: kwVar),
    (Name: 'varargs';     Keyword: kwVarargs),
    (Name: 'virtual';     Keyword: kwVirtual),
    (Name: 'while';       Keyword: kwWhile),
    (Name: 'with';        Keyword: kwWith),
    (Name: 'write';       Keyword: kwWrite),
    (Name: 'writeonly';   Keyword: kwWriteOnly),
    (Name: 'xor';         Keyword: kwXor)
  );

{ TDLSourcePos }

constructor TDLSourcePos.Create(AOffset, ALine, AColumn: Integer);
begin
  Offset := AOffset;
  Line := ALine;
  Column := AColumn;
end;

function TDLSourcePos.ToString: string;
begin
  Result := Format('%d:%d', [Line, Column]);
end;

{ TDLSourceSpan }

constructor TDLSourceSpan.Create(AStart, AStop: TDLSourcePos);
begin
  Start := AStart;
  Stop := AStop;
end;

function TDLSourceSpan.IsEmpty: Boolean;
begin
  Result := Stop.Offset <= Start.Offset;
end;

function TDLSourceSpan.ToString: string;
begin
  Result := Format('%s-%s', [Start.ToString, Stop.ToString]);
end;

{ TDLTrivia }

constructor TDLTrivia.Create(AKind: TDLTriviaKind; const AText: string;
  ASpan: TDLSourceSpan);
begin
  Kind := AKind;
  Text := AText;
  Span := ASpan;
end;

function TDLTrivia.ToString: string;
const
  CKind: array[TDLTriviaKind] of string = ('ws', 'line', 'block', 'dir');
begin
  Result := Format('[%s %s]', [CKind[Kind], Text]);
end;

{ TDLDiagnostic }

constructor TDLDiagnostic.Create(ASeverity: TDLDiagnosticSeverity; const ACode,
  AMessage: string; ASpan: TDLSourceSpan);
begin
  inherited Create;
  FSeverity := ASeverity;
  FCode := ACode;
  FMessage := AMessage;
  FSpan := ASpan;
end;

function TDLDiagnostic.ToString: string;
const
  CSeverity: array[TDLDiagnosticSeverity] of string = ('Hint', 'Warning', 'Error');
begin
  Result := Format('%s [%s] at %s: %s',
    [CSeverity[FSeverity], FCode, FSpan.ToString, FMessage]);
end;

{ TDLDiagnostics }

constructor TDLDiagnostics.Create;
begin
  inherited Create;
  FItems := TList.Create;
end;

destructor TDLDiagnostics.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TDLDiagnostics.Clear;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    TDLDiagnostic(FItems[i]).Free;
  FItems.Clear;
  FHasErrors := False;
end;

function TDLDiagnostics.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TDLDiagnostics.GetItem(AIndex: Integer): TDLDiagnostic;
begin
  Result := TDLDiagnostic(FItems[AIndex]);
end;

procedure TDLDiagnostics.Add(ASeverity: TDLDiagnosticSeverity; const ACode,
  AMessage: string; ASpan: TDLSourceSpan);
begin
  Add(TDLDiagnostic.Create(ASeverity, ACode, AMessage, ASpan));
end;

procedure TDLDiagnostics.Add(ADiagnostic: TDLDiagnostic);
begin
  FItems.Add(ADiagnostic);
  if ADiagnostic.Severity = dsError then
    FHasErrors := True;
end;

procedure TDLDiagnostics.Error(const ACode, AMessage: string; ASpan: TDLSourceSpan);
begin
  Add(dsError, ACode, AMessage, ASpan);
end;

procedure TDLDiagnostics.Warning(const ACode, AMessage: string; ASpan: TDLSourceSpan);
begin
  Add(dsWarning, ACode, AMessage, ASpan);
end;

procedure TDLDiagnostics.Hint(const ACode, AMessage: string; ASpan: TDLSourceSpan);
begin
  Add(dsHint, ACode, AMessage, ASpan);
end;

{ TDLSymbol }

constructor TDLSymbol.Create(const AName: string; AKind: TDLSymbolKind;
  ASpan: TDLSourceSpan);
begin
  inherited Create;
  FName := AName;
  FKind := AKind;
  FSpan := ASpan;
end;

{ TDLSymbolTable }

constructor TDLSymbolTable.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.OwnsObjects := True;
  // A flat symbol table may see the same name in different scopes
  // (e.g. interface declaration + implementation body); keep the first.
end;

destructor TDLSymbolTable.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLSymbolTable.Clear;
begin
  FItems.Clear;
end;

function TDLSymbolTable.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TDLSymbolTable.GetSymbol(AIndex: Integer): TDLSymbol;
begin
  Result := TDLSymbol(FItems.Objects[AIndex]);
end;

procedure TDLSymbolTable.Add(ASymbol: TDLSymbol);
begin
  if FItems.IndexOf(ASymbol.Name) >= 0 then
  begin
    ASymbol.Free;
    Exit;
  end;
  FItems.AddObject(ASymbol.Name, ASymbol);
end;

function TDLSymbolTable.Find(const AName: string): TDLSymbol;
var
  LIndex: Integer;
begin
  LIndex := FItems.IndexOf(AName);
  if LIndex >= 0 then
    Result := TDLSymbol(FItems.Objects[LIndex])
  else
    Result := nil;
end;

function TDLSymbolTable.Contains(const AName: string): Boolean;
begin
  Result := FItems.IndexOf(AName) >= 0;
end;

{ TDLDumpable }

function TDLDumpable.DumpToString: string;
var
  LBuilder: TStringBuilder;
begin
  LBuilder := TStringBuilder.Create;
  try
    Dump(LBuilder, 0);
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

{ TDLDump }

class procedure TDLDump.Indent(ABuilder: TStringBuilder; AIndent: Integer);
var
  i: Integer;
begin
  for i := 1 to AIndent do
    ABuilder.Append('  ');
end;

class procedure TDLDump.Line(ABuilder: TStringBuilder; AIndent: Integer;
  const AText: string);
begin
  Indent(ABuilder, AIndent);
  ABuilder.AppendLine(AText);
end;

class procedure TDLDump.Line(ABuilder: TStringBuilder; AIndent: Integer;
  const AText: string; const AArgs: array of const);
begin
  Indent(ABuilder, AIndent);
  ABuilder.AppendLine(Format(AText, AArgs));
end;

{ TDLKeywords }

class function TDLKeywords.ToKeyword(const AName: string): TDLKeyword;
var
  LLower, LHigh, LMid: Integer;
  LCompare: Integer;
  LName: string;
begin
  LName := LowerCase(AName);
  LLower := 0;
  LHigh := High(CDLKeywordTable);
  while LLower <= LHigh do
  begin
    LMid := (LLower + LHigh) div 2;
    LCompare := CompareStr(CDLKeywordTable[LMid].Name, LName);
    if LCompare < 0 then
      LLower := LMid + 1
    else if LCompare > 0 then
      LHigh := LMid - 1
    else
      Exit(CDLKeywordTable[LMid].Keyword);
  end;
  Result := kwNone;
end;

class function TDLKeywords.ToText(AKeyword: TDLKeyword): string;
var
  LEntry: TDLKeywordEntry;
begin
  for LEntry in CDLKeywordTable do
    if LEntry.Keyword = AKeyword then
      Exit(LEntry.Name);
  Result := '';
end;

class function TDLKeywords.IsKeyword(const AName: string): Boolean;
begin
  Result := ToKeyword(AName) <> kwNone;
end;

end.
