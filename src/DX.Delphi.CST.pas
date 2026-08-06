/// <summary>
///   DX.Delphi.CST — concrete syntax tree node hierarchy for Delphi source.
/// </summary>
/// <remarks>
///   The CST is a full-fidelity parse tree: every node carries a source span
///   and leading/trailing trivia (whitespace, comments, compiler directives).
///   Token information (identifiers, literals) is value-copied into
///   TDLTokenRef records so nodes fully own their data and the tree can be
///   dumped, traversed and lowered to the AST without referencing lexer
///   objects.
///
///   The grammar mirrors the Delphi language surface of Delphi 13.x: units,
///   programs, libraries and packages; type/const/var/threadvar/resourcestring/
///   label sections; records (with variant parts), classes, class/record
///   helpers, interfaces, object types, procedural types; methods, properties,
///   fields; the full statement and expression grammar (including inline var
///   declarations, anonymous methods and multiline strings).
///
///   Nodes are deliberately plain data holders; all logic lives in the parser
///   and in the CST -> AST lowering pass (DX.Delphi.AstBuilder).
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit DX.Delphi.CST;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Delphi.Core,
  DX.Delphi.Conditions;

type
  /// <summary>Class modifier on a method ('class' keyword).</summary>
  TDLClassModifier = (
    cmNone,
    cmClass,
    cmStaticClass
  );

  /// <summary>Lightweight copy of a significant token (identifier, literal).</summary>
  TDLTokenRef = record
    Kind: TDLTokenKind;
    Text: string;
    Value: string;
    IntegerValue: Int64;
    FloatValue: Double;
    Span: TDLSourceSpan;
    constructor Create(AKind: TDLTokenKind; const AText: string;
      ASpan: TDLSourceSpan);
  end;

  TDLNode = class;
  TDLExpr = class;
  TDLStatement = class;
  TDLTypeExpr = class;

  /// <summary>Base class of all CST nodes.</summary>
  TDLNode = class abstract(TDLDumpable)
  private
    FSpan: TDLSourceSpan;
    FLeadingTrivia: TList<TDLTrivia>;
    FTrailingTrivia: TList<TDLTrivia>;
    FFreed: Boolean;
    function GetTriviaCount: Integer;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    /// <summary>Prints the node header line (class name + details).</summary>
    procedure DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
      const AText: string); overload;
    /// <summary>Prints the node header line with formatted details.</summary>
    procedure DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
      const AText: string; const AArgs: array of const); overload;
    /// <summary>Prints trivia summary line(s), if any trivia is present.</summary>
    procedure DumpTrivia(ABuilder: TStringBuilder; AIndent: Integer);
    property Span: TDLSourceSpan read FSpan write FSpan;
    property LeadingTrivia: TList<TDLTrivia> read FLeadingTrivia;
    property TrailingTrivia: TList<TDLTrivia> read FTrailingTrivia;
    property TriviaCount: Integer read GetTriviaCount;
  end;

  /// <summary>An identifier occurrence (declaration or reference).</summary>
  TDLIdentifier = class(TDLNode)
  private
    FName: string;
    FToken: TDLTokenRef;
    FIsAmpersand: Boolean;
  public
    constructor Create(const AName: string; ASpan: TDLSourceSpan;
      AIsAmpersand: Boolean = False);
    procedure SetName(const AName: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
    property Token: TDLTokenRef read FToken;
    property IsAmpersand: Boolean read FIsAmpersand;
  end;

  /// <summary>A type expression (named type or type constructor).</summary>
  TDLTypeExpr = class abstract(TDLNode)
  end;

  /// <summary>An expression.</summary>
  TDLExpr = class abstract(TDLNode)
  public
    /// <summary>Renders this expression as compact source-like text
    /// (used by the AST lowering pass and dumps).</summary>
    function ToSourceText: string; virtual; abstract;
  end;

  /// <summary>A statement.</summary>
  TDLStatement = class abstract(TDLNode)
  end;

  TDLConditionalBranch = class;
  TDLConditionalStmt = class;
  TDLConditionalGroup = class;
  TDLConditionalDeclBranch = class;

  /// <summary>One conditional branch: a guard condition and its statements.</summary>
  TDLConditionalBranch = class(TDLNode)
  private
    FCondition: TDLCondition;
    FStatements: TList<TDLStatement>;
  public
    constructor Create(ASpan: TDLSourceSpan; ACondition: TDLCondition);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Condition: TDLCondition read FCondition;
    property Statements: TList<TDLStatement> read FStatements;
  end;

  /// <summary>
  ///  A conditional-compilation statement group:
  ///    {$IFDEF X} stmts {$ELSEIF Y} stmts {$ELSE} stmts {$ENDIF}
  ///  All branches are kept structurally so a code formatter can reformat
  ///  every conditional path; a projection pass selects the active branch
  ///  for a given define configuration.
  /// </summary>
  TDLConditionalStmt = class(TDLStatement)
  private
    FBranches: TList<TDLConditionalBranch>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Branches: TList<TDLConditionalBranch> read FBranches;
  end;

  /// <summary>One branch of a declaration conditional group.</summary>
  TDLConditionalDeclBranch = class(TDLNode)
  private
    FCondition: TDLCondition;
    FItems: TList<TDLNode>;
  public
    constructor Create(ASpan: TDLSourceSpan; ACondition: TDLCondition);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Condition: TDLCondition read FCondition;
    property Items: TList<TDLNode> read FItems;
  end;

  /// <summary>
  ///  A conditional group inside a declaration section:
  ///    type A = ...; {$IFDEF X} B = ...; {$ELSE} C = ...; {$ENDIF} D = ...;
  ///  Each branch holds a list of declaration nodes (TDLTypeDecl etc.).
  /// </summary>
  TDLConditionalGroup = class(TDLNode)
  private
    FBranches: TList<TDLConditionalDeclBranch>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Branches: TList<TDLConditionalDeclBranch> read FBranches;
  end;

  /// <summary>A type argument of a generic instantiation (e.g. TList&lt;Integer&gt;).</summary>
  TDLTypeArg = class(TDLNode)
  private
    FTypeExpr: TDLTypeExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ATypeExpr: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property TypeExpr: TDLTypeExpr read FTypeExpr;
  end;

  /// <summary>A named type reference, optionally generic-instantiated.</summary>
  TDLNamedType = class(TDLTypeExpr)
  private
    FName: TDLIdentifier;
    FTypeArgs: TList<TDLTypeArg>;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property TypeArgs: TList<TDLTypeArg> read FTypeArgs;
  end;

  /// <summary>Pointer type (^T).</summary>
  TDLPointerType = class(TDLTypeExpr)
  private
    FPointee: TDLTypeExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; APointee: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Pointee: TDLTypeExpr read FPointee;
  end;

  /// <summary>Set type (set of T).</summary>
  TDLSetType = class(TDLTypeExpr)
  private
    FBaseType: TDLTypeExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ABaseType: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property BaseType: TDLTypeExpr read FBaseType;
  end;

  /// <summary>Subrange type (Low..High).</summary>
  TDLSubrangeType = class(TDLTypeExpr)
  private
    FLow: TDLExpr;
    FHigh: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ALow, AHigh: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Low: TDLExpr read FLow;
    property High: TDLExpr read FHigh;
  end;

  /// <summary>String type with an optional fixed length (string[5]).</summary>
  TDLStringType = class(TDLTypeExpr)
  private
    FLength: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ALength: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Length: TDLExpr read FLength;
  end;

  /// <summary>File type (file / file of T).</summary>
  TDLFileType = class(TDLTypeExpr)
  private
    FBaseType: TDLTypeExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ABaseType: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property BaseType: TDLTypeExpr read FBaseType;
  end;

  /// <summary>One index bound of a static array (range or type name).</summary>
  TDLArrayBound = class(TDLNode)
  private
    FExpr: TDLExpr;         // low..high (subrange expr)
    FTypeExpr: TDLTypeExpr; // enumerated type name bound
  public
    constructor Create(ASpan: TDLSourceSpan; AExpr: TDLExpr; ATypeExpr: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expr: TDLExpr read FExpr;
    property TypeExpr: TDLTypeExpr read FTypeExpr;
  end;

  /// <summary>Static array type (array[1..10, TEnum] of X).</summary>
  TDLStaticArrayType = class(TDLTypeExpr)
  private
    FElementType: TDLTypeExpr;
    FBounds: TList<TDLArrayBound>;
  public
    constructor Create(ASpan: TDLSourceSpan; AElementType: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property ElementType: TDLTypeExpr read FElementType write FElementType;
    property Bounds: TList<TDLArrayBound> read FBounds;
  end;

  /// <summary>Dynamic array type (array of X, array of array of X).</summary>
  TDLDynamicArrayType = class(TDLTypeExpr)
  private
    FElementType: TDLTypeExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AElementType: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property ElementType: TDLTypeExpr read FElementType;
  end;

  /// <summary>Enumeration member (optional explicit value).</summary>
  TDLEnumMember = class(TDLNode)
  private
    FName: TDLIdentifier;
    FValue: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property Value: TDLExpr read FValue write FValue;
  end;

  /// <summary>Enumeration type ((A, B = 2, C)).</summary>
  TDLEnumType = class(TDLTypeExpr)
  private
    FIsPacked: Boolean;
    FMembers: TList<TDLEnumMember>;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property IsPacked: Boolean read FIsPacked write FIsPacked;
    property Members: TList<TDLEnumMember> read FMembers;
  end;

  TDLMember = class;
  TDLVariantSection = class;
  TDLVariantBranch = class;
  TDLFieldDecl = class;
  TDLAttribute = class;

  /// <summary>Record type (with optional variant part).</summary>
  TDLRecordType = class(TDLTypeExpr)
  private
    FIsPacked: Boolean;
    FMembers: TList<TDLMember>;
    FVariantPart: TDLVariantSection;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property IsPacked: Boolean read FIsPacked write FIsPacked;
    property Members: TList<TDLMember> read FMembers;
    property VariantPart: TDLVariantSection read FVariantPart write FVariantPart;
  end;

  /// <summary>Variant part of a record (case Tag: T of ...).</summary>
  TDLVariantSection = class(TDLNode)
  private
    FTag: TDLIdentifier;
    FTagType: TDLTypeExpr;
    FVariants: TList<TDLVariantBranch>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Tag: TDLIdentifier read FTag write FTag;
    property TagType: TDLTypeExpr read FTagType write FTagType;
    property Variants: TList<TDLVariantBranch> read FVariants;
  end;

  /// <summary>One branch of a record variant part.</summary>
  TDLVariantBranch = class(TDLNode)
  private
    FCaseLabels: TList<TDLExpr>;
    FFields: TList<TDLFieldDecl>;
    FVariantPart: TDLVariantSection;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property CaseLabels: TList<TDLExpr> read FCaseLabels;
    property Fields: TList<TDLFieldDecl> read FFields;
    property VariantPart: TDLVariantSection read FVariantPart write FVariantPart;
  end;

  /// <summary>Member of a class/record/interface body.</summary>
  TDLMember = class abstract(TDLNode)
  private
    FVisibility: TDLVisibility;
    FIsStrict: Boolean;
  public
    constructor Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
      AIsStrict: Boolean);
    property Visibility: TDLVisibility read FVisibility;
    property IsStrict: Boolean read FIsStrict;
  end;

  /// <summary>A visibility section marker (strict private, published, ...).</summary>
  TDLVisibilitySection = class(TDLMember)
  private
    FKind: TDLVisibility;
  public
    constructor Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
      AIsStrict: Boolean);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLVisibility read FKind;
  end;

  /// <summary>A field declaration (one or more names).</summary>
  TDLFieldDecl = class(TDLMember)
  private
    FNames: TList<TDLIdentifier>;
    FTypeExpr: TDLTypeExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
      AIsStrict: Boolean; ATypeExpr: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<TDLIdentifier> read FNames;
    property TypeExpr: TDLTypeExpr read FTypeExpr write FTypeExpr;
  end;

  TDLParameter = class;
  TDLDirective = class;

  /// <summary>Base of method declarations and implementations.</summary>
  TDLProcedureBase = class(TDLMember)
  private
    FKind: TDLProcKind;
    FName: TDLIdentifier;
    FClassModifier: TDLClassModifier;
    FParams: TList<TDLParameter>;
    FReturnType: TDLTypeExpr;
    FDirectives: TList<TDLDirective>;
    FAttributes: TList<TDLAttribute>;
    FOperatorName: TDLIdentifier;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      AName: TDLIdentifier; AClassModifier: TDLClassModifier);
    destructor Destroy; override;
    procedure DumpProcHeader(ABuilder: TStringBuilder; AIndent: Integer);
    property Kind: TDLProcKind read FKind;
    property Name: TDLIdentifier read FName;
    property ClassModifier: TDLClassModifier read FClassModifier;
    property Params: TList<TDLParameter> read FParams;
    property ReturnType: TDLTypeExpr read FReturnType write FReturnType;
    property Directives: TList<TDLDirective> read FDirectives;
    property Attributes: TList<TDLAttribute> read FAttributes;
    property OperatorName: TDLIdentifier read FOperatorName write FOperatorName;
  end;

  /// <summary>Procedural type (procedure/function type, of object, reference to).</summary>
  TDLProceduralType = class(TDLTypeExpr)
  private
    FKind: TDLProcKind;
    FIsOfObject: Boolean;
    FIsReferenceTo: Boolean;
    FParams: TList<TDLParameter>;
    FReturnType: TDLTypeExpr;
    FDirectives: TList<TDLDirective>;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      AIsOfObject, AIsReferenceTo: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLProcKind read FKind;
    property IsOfObject: Boolean read FIsOfObject write FIsOfObject;
    property IsReferenceTo: Boolean read FIsReferenceTo write FIsReferenceTo;
    property Params: TList<TDLParameter> read FParams;
    property ReturnType: TDLTypeExpr read FReturnType write FReturnType;
    property Directives: TList<TDLDirective> read FDirectives;
  end;

  /// <summary>Property declaration inside a class/interface body.</summary>
  TDLPropertyDecl = class(TDLMember)
  private
    FName: TDLIdentifier;
    FIndexParams: TList<TDLParameter>;
    FTypeExpr: TDLTypeExpr;
    FIndexSpec: TDLExpr;
    FReadName: TDLIdentifier;
    FWriteName: TDLIdentifier;
    FStoredName: TDLIdentifier;
    FReadIsFunc: Boolean;
    FWriteIsFunc: Boolean;
    FStoredIsFunc: Boolean;
    FStoredExpr: TDLExpr;
    FDefaultValue: TDLExpr;
    FIsDefault: Boolean;
    FIsNodefault: Boolean;
    FImplements: TList<TDLExpr>;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier;
      AVisibility: TDLVisibility = vsNone);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property IndexParams: TList<TDLParameter> read FIndexParams;
    property TypeExpr: TDLTypeExpr read FTypeExpr write FTypeExpr;
    property IndexSpec: TDLExpr read FIndexSpec write FIndexSpec;
    property ReadName: TDLIdentifier read FReadName write FReadName;
    property WriteName: TDLIdentifier read FWriteName write FWriteName;
    property StoredName: TDLIdentifier read FStoredName write FStoredName;
    property ReadIsFunc: Boolean read FReadIsFunc write FReadIsFunc;
    property WriteIsFunc: Boolean read FWriteIsFunc write FWriteIsFunc;
    property StoredIsFunc: Boolean read FStoredIsFunc write FStoredIsFunc;
    property StoredExpr: TDLExpr read FStoredExpr write FStoredExpr;
    property DefaultValue: TDLExpr read FDefaultValue write FDefaultValue;
    property IsDefault: Boolean read FIsDefault write FIsDefault;
    property IsNodefault: Boolean read FIsNodefault write FIsNodefault;
    property Implements: TList<TDLExpr> read FImplements;
  end;

  /// <summary>Class, class helper, class reference, interface, object type.</summary>
  TDLClassType = class(TDLTypeExpr)
  private
    FIsSealed: Boolean;
    FIsAbstract: Boolean;
    FIsHelper: Boolean;
    FIsClassRef: Boolean;
    FIsDispInterface: Boolean;
    FIsObject: Boolean;
    FIsInterface: Boolean;
    FBaseType: TDLTypeExpr;
    FHelperFor: TDLTypeExpr;
    FInterfaces: TList<TDLNamedType>;
    FMembers: TList<TDLMember>;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsSealed, AIsAbstract,
      AIsHelper, AIsClassRef, AIsDispInterface, AIsObject, AIsInterface: Boolean;
      ABaseType, AHelperFor: TDLTypeExpr; AMembers: TList<TDLMember>);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property IsSealed: Boolean read FIsSealed;
    property IsAbstract: Boolean read FIsAbstract;
    property IsHelper: Boolean read FIsHelper;
    property IsClassRef: Boolean read FIsClassRef;
    property IsDispInterface: Boolean read FIsDispInterface;
    property IsObject: Boolean read FIsObject;
    property IsInterface: Boolean read FIsInterface;
    property BaseType: TDLTypeExpr read FBaseType;
    property HelperFor: TDLTypeExpr read FHelperFor;
    property Interfaces: TList<TDLNamedType> read FInterfaces;
    property Members: TList<TDLMember> read FMembers;
  end;

  /// <summary>Method declaration without a body (interface part / forward).</summary>
  TDLMethodDecl = class(TDLProcedureBase)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>Method implementation (header + body).</summary>
  TDLMethodImpl = class(TDLProcedureBase)
  private
    FBody: TDLStatement;
    FLocalDecls: TList<TDLNode>;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      AName: TDLIdentifier; AClassModifier: TDLClassModifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStatement read FBody write FBody;
    /// <summary>Local var/label/const/type sections before the body.</summary>
    property LocalDecls: TList<TDLNode> read FLocalDecls;
  end;

  /// <summary>A method directive (virtual, message N, external 'x', ...).</summary>
  TDLDirective = class(TDLNode)
  private
    FName: TDLIdentifier;
    FValues: TList<TDLExpr>;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property Values: TList<TDLExpr> read FValues;
  end;

  /// <summary>A parameter declaration.</summary>
  TDLParameter = class(TDLNode)
  private
    FNames: TList<TDLIdentifier>;
    FModifier: TDLParamModifier;
    FTypeExpr: TDLTypeExpr;
    FDefaultValue: TDLExpr;
    FAttributes: TList<TDLAttribute>;
  public
    constructor Create(ASpan: TDLSourceSpan; AModifier: TDLParamModifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<TDLIdentifier> read FNames;
    property Modifier: TDLParamModifier read FModifier;
    property TypeExpr: TDLTypeExpr read FTypeExpr write FTypeExpr;
    property DefaultValue: TDLExpr read FDefaultValue write FDefaultValue;
    property Attributes: TList<TDLAttribute> read FAttributes;
  end;

  /// <summary>Attribute application ([Name(arg)]).</summary>
  TDLAttribute = class(TDLNode)
  private
    FNamePath: TList<TDLIdentifier>;
    FArgs: TList<TDLExpr>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property NamePath: TList<TDLIdentifier> read FNamePath;
    property Args: TList<TDLExpr> read FArgs;
  end;

  TDLUsesClause = class;
  TDLDeclItem = class;
  TDLInitSection = class;
  TDLFinalizationSection = class;

  /// <summary>Root node: a compilation unit (program/unit/library/package).</summary>
  TDLCompilationUnit = class abstract(TDLNode)
  private
    FProgramKind: TDLProgramKind;
    FName: TDLIdentifier;
    FProgramParams: TList<TDLIdentifier>; // program Foo(a, b);
    FUsesClauses: TList<TDLUsesClause>;
    FItems: TList<TDLNode>;
    FInitSection: TDLInitSection;
    FFinalizationSection: TDLFinalizationSection;
    FRequiresClause: TDLUsesClause; // package requires
    FContainsClause: TDLUsesClause; // package contains
  public
    constructor Create(ASpan: TDLSourceSpan; AProgramKind: TDLProgramKind;
      AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property ProgramKind: TDLProgramKind read FProgramKind;
    property Name: TDLIdentifier read FName;
    property ProgramParams: TList<TDLIdentifier> read FProgramParams;
    property UsesClauses: TList<TDLUsesClause> read FUsesClauses;
    property Items: TList<TDLNode> read FItems;
    property InitSection: TDLInitSection read FInitSection write FInitSection;
    property FinalizationSection: TDLFinalizationSection
      read FFinalizationSection write FFinalizationSection;
    property RequiresClause: TDLUsesClause read FRequiresClause write FRequiresClause;
    property ContainsClause: TDLUsesClause read FContainsClause write FContainsClause;
  end;

  /// <summary>Reference to another unit in a uses clause (name [in 'file']).</summary>
  TDLUnitReference = class(TDLNode)
  private
    FName: TDLIdentifier;
    FInFile: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property InFile: TDLExpr read FInFile write FInFile;
  end;

  /// <summary>A uses/requires/contains clause.</summary>
  TDLUsesClause = class(TDLNode)
  private
    FReferences: TList<TDLUnitReference>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property References: TList<TDLUnitReference> read FReferences;
  end;

  /// <summary>An export item (exports Name index N name 'x';).</summary>
  TDLExportItem = class(TDLNode)
  private
    FName: TDLIdentifier;
    FIndex: TDLExpr;
    FNameSpec: TDLExpr;
    FDirectives: TList<TDLDirective>;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property Index: TDLExpr read FIndex write FIndex;
    property NameSpec: TDLExpr read FNameSpec write FNameSpec;
    property Directives: TList<TDLDirective> read FDirectives;
  end;

  /// <summary>Base of items that appear at compilation-unit level.</summary>
  TDLDeclItem = class abstract(TDLNode)
  private
    FAttributes: TList<TDLAttribute>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    property Attributes: TList<TDLAttribute> read FAttributes;
  end;

  /// <summary>A type declaration (Name = TypeExpr).</summary>
  TDLTypeDecl = class(TDLNode)
  private
    FName: TDLIdentifier;
    FTypeExpr: TDLTypeExpr;
    FTypeParams: TList<TDLIdentifier>;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier;
      ATypeExpr: TDLTypeExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
    property TypeExpr: TDLTypeExpr read FTypeExpr;
    /// <summary>Generic type parameters (TList&lt;T&gt; -> [T]).</summary>
    property TypeParams: TList<TDLIdentifier> read FTypeParams;
  end;

  /// <summary>type section (one or more TDLTypeDecl).</summary>
  TDLTypeSection = class(TDLDeclItem)
  private
    FIsPacked: Boolean;
    FItems: TList<TDLNode>;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property IsPacked: Boolean read FIsPacked;
    property Items: TList<TDLNode> read FItems;
  end;

  /// <summary>A constant declaration (Name = Expr or typed Name: T = Expr).</summary>
  TDLConstDecl = class(TDLNode)
  private
    FNames: TList<TDLIdentifier>;
    FTypeExpr: TDLTypeExpr;
    FValue: TDLExpr;
    FIsTyped: Boolean;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<TDLIdentifier> read FNames;
    property TypeExpr: TDLTypeExpr read FTypeExpr write FTypeExpr;
    property Value: TDLExpr read FValue write FValue;
    property IsTyped: Boolean read FIsTyped write FIsTyped;
  end;

  /// <summary>const section.</summary>
  TDLConstSection = class(TDLDeclItem)
  private
    FItems: TList<TDLNode>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Items: TList<TDLNode> read FItems;
  end;

  /// <summary>resourcestring section.</summary>
  TDLResStringSection = class(TDLDeclItem)
  private
    FItems: TList<TDLConstDecl>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Items: TList<TDLConstDecl> read FItems;
  end;

  /// <summary>A variable declaration (one or more names, optional type/init).</summary>
  TDLVarDecl = class(TDLNode)
  private
    FNames: TList<TDLIdentifier>;
    FTypeExpr: TDLTypeExpr;
    FInit: TDLExpr;
    FAbsoluteTarget: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<TDLIdentifier> read FNames;
    property TypeExpr: TDLTypeExpr read FTypeExpr write FTypeExpr;
    property Init: TDLExpr read FInit write FInit;
    property AbsoluteTarget: TDLExpr read FAbsoluteTarget write FAbsoluteTarget;
  end;

  /// <summary>var / threadvar section.</summary>
  TDLVarSection = class(TDLDeclItem)
  private
    FIsThreadVar: Boolean;
    FItems: TList<TDLNode>;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsThreadVar: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property IsThreadVar: Boolean read FIsThreadVar;
    property Items: TList<TDLNode> read FItems;
  end;

  /// <summary>A label declaration.</summary>
  TDLLabelDecl = class(TDLNode)
  private
    FName: TDLIdentifier;
  public
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
  end;

  /// <summary>label section.</summary>
  TDLLabelSection = class(TDLDeclItem)
  private
    FItems: TList<TDLLabelDecl>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Items: TList<TDLLabelDecl> read FItems;
  end;

  /// <summary>exports clause.</summary>
  TDLExportsClause = class(TDLDeclItem)
  private
    FItems: TList<TDLExportItem>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Items: TList<TDLExportItem> read FItems;
  end;

  /// <summary>initialization section body.</summary>
  TDLInitSection = class(TDLNode)
  private
    FBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ABody: TDLStatement);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStatement read FBody;
  end;

  /// <summary>finalization section body.</summary>
  TDLFinalizationSection = class(TDLNode)
  private
    FBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ABody: TDLStatement);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStatement read FBody;
  end;

  // ---------------------------------------------------------------------------
  // Statements
  // ---------------------------------------------------------------------------

  /// <summary>begin ... end compound statement.</summary>
  TDLCompoundStmt = class(TDLStatement)
  private
    FStatements: TList<TDLStatement>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Statements: TList<TDLStatement> read FStatements;
  end;

  /// <summary>if ... then ... [else ...].</summary>
  TDLIfStmt = class(TDLStatement)
  private
    FCondition: TDLExpr;
    FThenBranch: TDLStatement;
    FElseBranch: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ACondition: TDLExpr;
      AThenBranch: TDLStatement);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Condition: TDLExpr read FCondition;
    property ThenBranch: TDLStatement read FThenBranch;
    property ElseBranch: TDLStatement read FElseBranch write FElseBranch;
  end;

  TDLCaseSelector = class;

  /// <summary>case ... of ... end statement.</summary>
  TDLCaseStmt = class(TDLStatement)
  private
    FSubject: TDLExpr;
    FSelectors: TList<TDLCaseSelector>;
    FElseBranch: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ASubject: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Subject: TDLExpr read FSubject;
    property Selectors: TList<TDLCaseSelector> read FSelectors;
    property ElseBranch: TDLStatement read FElseBranch write FElseBranch;
  end;

  /// <summary>One case selector: [label(s)] : statement.</summary>
  TDLCaseSelector = class(TDLNode)
  private
    FLabels: TList<TDLExpr>;
    FStatement: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Labels: TList<TDLExpr> read FLabels;
    property Statement: TDLStatement read FStatement write FStatement;
  end;

  /// <summary>for loop.</summary>
  TDLForStmt = class(TDLStatement)
  private
    FLoopVar: TDLIdentifier;
    FIsInlineVar: Boolean;
    FDirection: TDLKeyword; // kwTo, kwDownTo, kwIn
    FStartExpr: TDLExpr;
    FEndExpr: TDLExpr;
    FBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ALoopVar: TDLIdentifier;
      AIsInlineVar: Boolean; ADirection: TDLKeyword);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property LoopVar: TDLIdentifier read FLoopVar;
    property IsInlineVar: Boolean read FIsInlineVar;
    property Direction: TDLKeyword read FDirection;
    property StartExpr: TDLExpr read FStartExpr write FStartExpr;
    property EndExpr: TDLExpr read FEndExpr write FEndExpr;
    property Body: TDLStatement read FBody write FBody;
  end;

  /// <summary>while loop.</summary>
  TDLWhileStmt = class(TDLStatement)
  private
    FCondition: TDLExpr;
    FBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ACondition: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Condition: TDLExpr read FCondition;
    property Body: TDLStatement read FBody write FBody;
  end;

  /// <summary>repeat ... until condition.</summary>
  TDLRepeatStmt = class(TDLStatement)
  private
    FBody: TDLStatement;
    FCondition: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStatement read FBody write FBody;
    property Condition: TDLExpr read FCondition write FCondition;
  end;

  /// <summary>with expr1, expr2 do statement.</summary>
  TDLWithStmt = class(TDLStatement)
  private
    FExpressions: TList<TDLExpr>;
    FBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expressions: TList<TDLExpr> read FExpressions;
    property Body: TDLStatement read FBody write FBody;
  end;

  TDLOnHandler = class;

  /// <summary>try ... except|finally ... end.</summary>
  TDLTryStmt = class(TDLStatement)
  private
    FBody: TDLStatement;
    FIsExcept: Boolean;
    FOnHandlers: TList<TDLOnHandler>;
    FElseBranch: TDLStatement;
    FFinallyBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsExcept: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStatement read FBody write FBody;
    property IsExcept: Boolean read FIsExcept;
    property OnHandlers: TList<TDLOnHandler> read FOnHandlers;
    property ElseBranch: TDLStatement read FElseBranch write FElseBranch;
    property FinallyBody: TDLStatement read FFinallyBody write FFinallyBody;
  end;

  /// <summary>on E: TException do statement (except handler).</summary>
  TDLOnHandler = class(TDLNode)
  private
    FVarName: TDLIdentifier;
    FTypeName: TDLIdentifier;
    FBody: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property VarName: TDLIdentifier read FVarName write FVarName;
    property TypeName: TDLIdentifier read FTypeName write FTypeName;
    property Body: TDLStatement read FBody write FBody;
  end;

  /// <summary>raise [expr] [at addr].</summary>
  TDLRaiseStmt = class(TDLStatement)
  private
    FException: TDLExpr;
    FAtAddr: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AException: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Exception: TDLExpr read FException;
    property AtAddr: TDLExpr read FAtAddr write FAtAddr;
  end;

  /// <summary>goto label.</summary>
  TDLGotoStmt = class(TDLStatement)
  private
    FLabelName: TDLIdentifier;
  public
    constructor Create(ASpan: TDLSourceSpan; ALabelName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property LabelName: TDLIdentifier read FLabelName;
  end;

  /// <summary>label : statement.</summary>
  TDLLabelStmt = class(TDLStatement)
  private
    FLabelName: TDLIdentifier;
    FStatement: TDLStatement;
  public
    constructor Create(ASpan: TDLSourceSpan; ALabelName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property LabelName: TDLIdentifier read FLabelName;
    property Statement: TDLStatement read FStatement write FStatement;
  end;

  /// <summary>target := value.</summary>
  TDLAssignmentStmt = class(TDLStatement)
  private
    FTarget: TDLExpr;
    FValue: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ATarget, AValue: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property Value: TDLExpr read FValue;
  end;

  /// <summary>An expression used as a statement (procedure call, etc.).</summary>
  TDLExprStmt = class(TDLStatement)
  private
    FExpression: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AExpression: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expression: TDLExpr read FExpression;
  end;

  /// <summary>Raw asm ... end block (body kept as text).</summary>
  TDLAsmStmt = class(TDLStatement)
  private
    FText: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AText: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Text: string read FText;
  end;

  /// <summary>exit [expr].</summary>
  TDLExitStmt = class(TDLStatement)
  private
    FExpression: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AExpression: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expression: TDLExpr read FExpression;
  end;

  /// <summary>break.</summary>
  TDLBreakStmt = class(TDLStatement)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>continue.</summary>
  TDLContinueStmt = class(TDLStatement)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>Inline variable declaration (var i := expr / var i: T := expr).</summary>
  TDLVarDeclStmt = class(TDLStatement)
  private
    FVarDecl: TDLVarDecl;
  public
    constructor Create(ASpan: TDLSourceSpan; AVarDecl: TDLVarDecl);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property VarDecl: TDLVarDecl read FVarDecl;
  end;

  /// <summary>Empty statement (a stray ';').</summary>
  TDLEmptyStmt = class(TDLStatement)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  // ---------------------------------------------------------------------------
  // Expressions
  // ---------------------------------------------------------------------------

  /// <summary>Identifier reference.</summary>
  TDLIdentifierExpr = class(TDLExpr)
  private
    FName: TDLIdentifier;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: TDLIdentifier read FName;
  end;

  /// <summary>Numeric literal.</summary>
  TDLNumberExpr = class(TDLExpr)
  private
    FToken: TDLTokenRef;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; AToken: TDLTokenRef);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Token: TDLTokenRef read FToken;
  end;

  /// <summary>String literal (single token, or char-code/string concatenation).</summary>
  TDLStringExpr = class(TDLExpr)
  private
    FToken: TDLTokenRef;
    FValue: string;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; AToken: TDLTokenRef; const AValue: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Token: TDLTokenRef read FToken;
    property Value: string read FValue;
  end;

  /// <summary>nil literal.</summary>
  TDLNilExpr = class(TDLExpr)
  public
    function ToSourceText: string; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>Set constructor ([a, b..c]).</summary>
  TDLSetExpr = class(TDLExpr)
  private
    FElements: TList<TDLExpr>;
    FIsRanges: TList<Boolean>;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Elements: TList<TDLExpr> read FElements;
    property IsRanges: TList<Boolean> read FIsRanges;
  end;

  /// <summary>Array constructor ([a, b, c]).</summary>
  TDLArrayExpr = class(TDLExpr)
  private
    FElements: TList<TDLExpr>;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Elements: TList<TDLExpr> read FElements;
  end;

  /// <summary>Binary operation.</summary>
  TDLBinaryExpr = class(TDLExpr)
  private
    FOperator: TDLBinaryOp;
    FLeft: TDLExpr;
    FRight: TDLExpr;
    FOperatorText: string;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; AOperator: TDLBinaryOp;
      const AOperatorText: string; ALeft, ARight: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Operator: TDLBinaryOp read FOperator;
    property OperatorText: string read FOperatorText;
    property Left: TDLExpr read FLeft;
    property Right: TDLExpr read FRight;
  end;

  /// <summary>Unary operation.</summary>
  TDLUnaryExpr = class(TDLExpr)
  private
    FOperator: TDLUnaryOp;
    FOperand: TDLExpr;
    FOperatorText: string;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; AOperator: TDLUnaryOp;
      const AOperatorText: string; AOperand: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Operator: TDLUnaryOp read FOperator;
    property OperatorText: string read FOperatorText;
    property Operand: TDLExpr read FOperand;
  end;

  /// <summary>Indexing (a[i, j]).</summary>
  TDLIndexExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
    FIndices: TList<TDLExpr>;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property Indices: TList<TDLExpr> read FIndices;
  end;

  /// <summary>Call (callee(args)).</summary>
  TDLCallExpr = class(TDLExpr)
  private
    FCallee: TDLExpr;
    FArgs: TList<TDLExpr>;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; ACallee: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Callee: TDLExpr read FCallee;
    property Args: TList<TDLExpr> read FArgs;
  end;

  /// <summary>Member access (target.member).</summary>
  TDLMemberExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
    FMember: TDLIdentifier;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr; AMember: TDLIdentifier);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property Member: TDLIdentifier read FMember;
  end;

  /// <summary>Generic instantiation (Target&lt;TypeArgs&gt;).</summary>
  TDLGenericInstantiationExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
    FTypeArgs: TList<TDLTypeArg>;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property TypeArgs: TList<TDLTypeArg> read FTypeArgs;
  end;

  /// <summary>inherited [member] expression.</summary>
  TDLInheritedExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
  end;

  /// <summary>Anonymous method expression (procedure/function/reference to ...).</summary>
  TDLAnonymousMethodExpr = class(TDLExpr)
  private
    FKind: TDLProcKind;
    FIsReferenceTo: Boolean;
    FParams: TList<TDLParameter>;
    FReturnType: TDLTypeExpr;
    FBody: TDLStatement;
  public
    function ToSourceText: string; override;
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      AIsReferenceTo: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLProcKind read FKind;
    property IsReferenceTo: Boolean read FIsReferenceTo;
    property Params: TList<TDLParameter> read FParams;
    property ReturnType: TDLTypeExpr read FReturnType write FReturnType;
    property Body: TDLStatement read FBody write FBody;
  end;

/// <summary>Resets the defensive node-count guard (called per top-level parse).</summary>
procedure DLResetNodeCount;
/// <summary>Sets the parser context reported by the node-count guard.</summary>
procedure DLSetContext(const AText: string);

implementation

var
  GDLNodeCount: Integer = 0;
  GDLContext: string = '';

{ TDLTokenRef }

constructor TDLTokenRef.Create(AKind: TDLTokenKind; const AText: string;
  ASpan: TDLSourceSpan);
begin
  Kind := AKind;
  Text := AText;
  Value := '';
  IntegerValue := 0;
  FloatValue := 0;
  Span := ASpan;
end;

{ TDLNode }

constructor TDLNode.Create(ASpan: TDLSourceSpan);
begin
  inherited Create;
  FFreed := False;
  Inc(GDLNodeCount);
  // Defensive guard against node-creation loops on pathological input.
  if GDLNodeCount > 20000000 then
    raise Exception.Create('DLP-FATAL: CST node limit exceeded at ' +
      ClassName + ' (' + IntToStr(GDLNodeCount) + ') context=' + GDLContext);
  FSpan := ASpan;
  FLeadingTrivia := TList<TDLTrivia>.Create;
  FTrailingTrivia := TList<TDLTrivia>.Create;
end;

procedure DLResetNodeCount;
begin
  GDLNodeCount := 0;
  GDLContext := '';
end;

procedure DLSetContext(const AText: string);
begin
  GDLContext := AText;
end;

destructor TDLNode.Destroy;
begin
  if FFreed then
    raise Exception.Create('DOUBLE-FREE detected: ' + ClassName);
  FFreed := True;
  FLeadingTrivia.Free;
  FTrailingTrivia.Free;
  inherited Destroy;
end;

function TDLNode.GetTriviaCount: Integer;
begin
  Result := FLeadingTrivia.Count + FTrailingTrivia.Count;
end;

procedure TDLNode.DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
  const AText: string);
begin
  TDLDump.Line(ABuilder, AIndent, ClassName + '(' + AText + ')');
end;

procedure TDLNode.DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
  const AText: string; const AArgs: array of const);
begin
  TDLDump.Line(ABuilder, AIndent, ClassName + '(' + Format(AText, AArgs) + ')');
end;

procedure TDLNode.DumpTrivia(ABuilder: TStringBuilder; AIndent: Integer);
var
  i: Integer;
begin
  if FLeadingTrivia.Count > 0 then
  begin
    TDLDump.Line(ABuilder, AIndent, '  leading trivia:');
    for i := 0 to FLeadingTrivia.Count - 1 do
      TDLDump.Line(ABuilder, AIndent + 1, FLeadingTrivia[i].ToString);
  end;
  if FTrailingTrivia.Count > 0 then
  begin
    TDLDump.Line(ABuilder, AIndent, '  trailing trivia:');
    for i := 0 to FTrailingTrivia.Count - 1 do
      TDLDump.Line(ABuilder, AIndent + 1, FTrailingTrivia[i].ToString);
  end;
end;

{ TDLIdentifier }

constructor TDLIdentifier.Create(const AName: string; ASpan: TDLSourceSpan;
  AIsAmpersand: Boolean);
begin
  inherited Create(ASpan);
  FName := AName;
  FIsAmpersand := AIsAmpersand;
  FToken.Kind := tkIdentifier;
  FToken.Text := AName;
  FToken.Value := AName;
  FToken.Span := ASpan;
end;

procedure TDLIdentifier.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  if FIsAmpersand then
    DumpHeader(ABuilder, AIndent, '&%s', [FName])
  else
    DumpHeader(ABuilder, AIndent, FName);
end;

procedure TDLIdentifier.SetName(const AName: string);
begin
  FName := AName;
end;

{ TDLTypeArg }

constructor TDLTypeArg.Create(ASpan: TDLSourceSpan; ATypeExpr: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FTypeExpr := ATypeExpr;
end;

destructor TDLTypeArg.Destroy;
begin
  FTypeExpr.Free;
  inherited Destroy;
end;

procedure TDLTypeArg.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'typearg');
  FTypeExpr.Dump(ABuilder, AIndent + 1);
end;

{ TDLNamedType }

constructor TDLNamedType.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
  FTypeArgs := TList<TDLTypeArg>.Create;
end;

destructor TDLNamedType.Destroy;
begin
  FName.Free;
  FTypeArgs.Free;
  inherited Destroy;
end;

procedure TDLNamedType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LArg: TDLTypeArg;
begin
  DumpHeader(ABuilder, AIndent, '%s', [FName.Name]);
  for LArg in FTypeArgs do
    LArg.Dump(ABuilder, AIndent + 1);
end;

{ TDLPointerType }

constructor TDLPointerType.Create(ASpan: TDLSourceSpan; APointee: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FPointee := APointee;
end;

destructor TDLPointerType.Destroy;
begin
  FPointee.Free;
  inherited Destroy;
end;

procedure TDLPointerType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'pointer');
  FPointee.Dump(ABuilder, AIndent + 1);
end;

{ TDLSetType }

constructor TDLSetType.Create(ASpan: TDLSourceSpan; ABaseType: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FBaseType := ABaseType;
end;

destructor TDLSetType.Destroy;
begin
  FBaseType.Free;
  inherited Destroy;
end;

procedure TDLSetType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'set of');
  FBaseType.Dump(ABuilder, AIndent + 1);
end;

{ TDLSubrangeType }

constructor TDLSubrangeType.Create(ASpan: TDLSourceSpan; ALow, AHigh: TDLExpr);
begin
  inherited Create(ASpan);
  FLow := ALow;
  FHigh := AHigh;
end;

destructor TDLSubrangeType.Destroy;
begin
  FLow.Free;
  FHigh.Free;
  inherited Destroy;
end;

procedure TDLSubrangeType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'subrange');
  FLow.Dump(ABuilder, AIndent + 1);
  FHigh.Dump(ABuilder, AIndent + 1);
end;

{ TDLStringType }

constructor TDLStringType.Create(ASpan: TDLSourceSpan; ALength: TDLExpr);
begin
  inherited Create(ASpan);
  FLength := ALength;
end;

destructor TDLStringType.Destroy;
begin
  FLength.Free;
  inherited Destroy;
end;

procedure TDLStringType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'string');
  if FLength <> nil then
    FLength.Dump(ABuilder, AIndent + 1);
end;

{ TDLFileType }

constructor TDLFileType.Create(ASpan: TDLSourceSpan; ABaseType: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FBaseType := ABaseType;
end;

destructor TDLFileType.Destroy;
begin
  FBaseType.Free;
  inherited Destroy;
end;

procedure TDLFileType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'file');
  if FBaseType <> nil then
    FBaseType.Dump(ABuilder, AIndent + 1);
end;

{ TDLArrayBound }

constructor TDLArrayBound.Create(ASpan: TDLSourceSpan; AExpr: TDLExpr;
  ATypeExpr: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FExpr := AExpr;
  FTypeExpr := ATypeExpr;
end;

destructor TDLArrayBound.Destroy;
begin
  FExpr.Free;
  FTypeExpr.Free;
  inherited Destroy;
end;

procedure TDLArrayBound.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'bound');
  if FExpr <> nil then
    FExpr.Dump(ABuilder, AIndent + 1);
  if FTypeExpr <> nil then
    FTypeExpr.Dump(ABuilder, AIndent + 1);
end;

{ TDLStaticArrayType }

constructor TDLStaticArrayType.Create(ASpan: TDLSourceSpan;
  AElementType: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FElementType := AElementType;
  FBounds := TList<TDLArrayBound>.Create;
end;

destructor TDLStaticArrayType.Destroy;
begin
  FElementType.Free;
  FBounds.Free;
  inherited Destroy;
end;

procedure TDLStaticArrayType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LBound: TDLArrayBound;
begin
  DumpHeader(ABuilder, AIndent, 'static array');
  for LBound in FBounds do
    LBound.Dump(ABuilder, AIndent + 1);
  TDLDump.Line(ABuilder, AIndent, '  of');
  FElementType.Dump(ABuilder, AIndent + 1);
end;

{ TDLDynamicArrayType }

constructor TDLDynamicArrayType.Create(ASpan: TDLSourceSpan;
  AElementType: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FElementType := AElementType;
end;

destructor TDLDynamicArrayType.Destroy;
begin
  FElementType.Free;
  inherited Destroy;
end;

procedure TDLDynamicArrayType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'dynamic array');
  TDLDump.Line(ABuilder, AIndent, '  of');
  FElementType.Dump(ABuilder, AIndent + 1);
end;

{ TDLEnumMember }

constructor TDLEnumMember.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
end;

destructor TDLEnumMember.Destroy;
begin
  FName.Free;
  FValue.Free;
  inherited Destroy;
end;

procedure TDLEnumMember.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, FName.Name);
  if FValue <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  =');
    FValue.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLEnumType }

constructor TDLEnumType.Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
begin
  inherited Create(ASpan);
  FIsPacked := AIsPacked;
  FMembers := TList<TDLEnumMember>.Create;
end;

destructor TDLEnumType.Destroy;
begin
  FMembers.Free;
  inherited Destroy;
end;

procedure TDLEnumType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LMember: TDLEnumMember;
begin
  DumpHeader(ABuilder, AIndent, 'enum (%s)', [BoolToStr(FIsPacked, True)]);
  for LMember in FMembers do
    LMember.Dump(ABuilder, AIndent + 1);
end;

{ TDLRecordType }

constructor TDLRecordType.Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
begin
  inherited Create(ASpan);
  FIsPacked := AIsPacked;
  FMembers := TList<TDLMember>.Create;
end;

destructor TDLRecordType.Destroy;
begin
  FMembers.Free;
  FVariantPart.Free;
  inherited Destroy;
end;

procedure TDLRecordType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LMember: TDLMember;
begin
  DumpHeader(ABuilder, AIndent, 'record (%s)', [BoolToStr(FIsPacked, True)]);
  for LMember in FMembers do
    LMember.Dump(ABuilder, AIndent + 1);
  if FVariantPart <> nil then
    FVariantPart.Dump(ABuilder, AIndent + 1);
end;

{ TDLVariantSection }

constructor TDLVariantSection.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FVariants := TList<TDLVariantBranch>.Create;
end;

destructor TDLVariantSection.Destroy;
begin
  FTag.Free;
  FTagType.Free;
  FVariants.Free;
  inherited Destroy;
end;

procedure TDLVariantSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LVariant: TDLVariantBranch;
begin
  DumpHeader(ABuilder, AIndent, 'case %s :', [FTag.Name]);
  FTagType.Dump(ABuilder, AIndent + 1);
  for LVariant in FVariants do
    LVariant.Dump(ABuilder, AIndent + 1);
end;

{ TDLVariantBranch }

constructor TDLVariantBranch.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FCaseLabels := TList<TDLExpr>.Create;
  FFields := TList<TDLFieldDecl>.Create;
end;

destructor TDLVariantBranch.Destroy;
begin
  FCaseLabels.Free;
  FFields.Free;
  FVariantPart.Free;
  inherited Destroy;
end;

procedure TDLVariantBranch.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LLabel: TDLExpr;
  LField: TDLFieldDecl;
begin
  DumpHeader(ABuilder, AIndent, 'variant');
  for LLabel in FCaseLabels do
    LLabel.Dump(ABuilder, AIndent + 1);
  for LField in FFields do
    LField.Dump(ABuilder, AIndent + 1);
  if FVariantPart <> nil then
    FVariantPart.Dump(ABuilder, AIndent + 1);
end;

{ TDLMember }

constructor TDLMember.Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
  AIsStrict: Boolean);
begin
  inherited Create(ASpan);
  FVisibility := AVisibility;
  FIsStrict := AIsStrict;
end;

{ TDLVisibilitySection }

constructor TDLVisibilitySection.Create(ASpan: TDLSourceSpan;
  AVisibility: TDLVisibility; AIsStrict: Boolean);
begin
  inherited Create(ASpan, AVisibility, AIsStrict);
  FKind := AVisibility;
end;

procedure TDLVisibilitySection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LText: string;
begin
  if IsStrict then
    LText := 'strict ' + TDLVisibilityNames[FKind]
  else
    LText := TDLVisibilityNames[FKind];
  inherited DumpHeader(ABuilder, AIndent, LText);
end;

{ TDLFieldDecl }

constructor TDLFieldDecl.Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
  AIsStrict: Boolean; ATypeExpr: TDLTypeExpr);
begin
  inherited Create(ASpan, AVisibility, AIsStrict);
  FNames := TList<TDLIdentifier>.Create;
  FTypeExpr := ATypeExpr;
end;

destructor TDLFieldDecl.Destroy;
begin
  FNames.Free;
  FTypeExpr.Free;
  inherited Destroy;
end;

procedure TDLFieldDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LName: TDLIdentifier;
  LNames: string;
begin
  LNames := '';
  for LName in FNames do
  begin
    if LNames <> '' then
      LNames := LNames + ', ';
    LNames := LNames + LName.Name;
  end;
  DumpHeader(ABuilder, AIndent, 'field %s [%s]', [LNames,
    TDLVisibilityNames[Visibility]]);
  if FTypeExpr <> nil then
    FTypeExpr.Dump(ABuilder, AIndent + 1);
end;

{ TDLProcedureBase }

constructor TDLProcedureBase.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
  AName: TDLIdentifier; AClassModifier: TDLClassModifier);
begin
  inherited Create(ASpan, vsNone, False);
  FKind := AKind;
  FName := AName;
  FClassModifier := AClassModifier;
  FParams := TList<TDLParameter>.Create;
  FDirectives := TList<TDLDirective>.Create;
  FAttributes := TList<TDLAttribute>.Create;
end;

destructor TDLProcedureBase.Destroy;
begin
  FName.Free;
  FParams.Free;
  FReturnType.Free;
  FDirectives.Free;
  FAttributes.Free;
  FOperatorName.Free;
  inherited Destroy;
end;

procedure TDLProcedureBase.DumpProcHeader(ABuilder: TStringBuilder;
  AIndent: Integer);
var
  LParam: TDLParameter;
  LDirective: TDLDirective;
  LText: string;
begin
  LText := TDLProcKindNames[FKind] + ' ' + FName.Name;
  if FClassModifier = cmClass then
    LText := 'class ' + LText
  else if FClassModifier = cmStaticClass then
    LText := 'class static ' + LText;
  if FOperatorName <> nil then
    LText := LText + ' [' + FOperatorName.Name + ']';
  DumpHeader(ABuilder, AIndent, LText);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  :');
    FReturnType.Dump(ABuilder, AIndent + 1);
  end;
  for LDirective in FDirectives do
    LDirective.Dump(ABuilder, AIndent + 1);
end;

{ TDLMethodDecl }

procedure TDLMethodDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpProcHeader(ABuilder, AIndent);
end;

{ TDLProceduralType }

constructor TDLProceduralType.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
  AIsOfObject, AIsReferenceTo: Boolean);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FIsOfObject := AIsOfObject;
  FIsReferenceTo := AIsReferenceTo;
  FParams := TList<TDLParameter>.Create;
  FDirectives := TList<TDLDirective>.Create;
end;

destructor TDLProceduralType.Destroy;
begin
  FParams.Free;
  FReturnType.Free;
  FDirectives.Free;
  inherited Destroy;
end;

procedure TDLProceduralType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParameter;
  LDirective: TDLDirective;
  LKindText: string;
  LSuffix: string;
begin
  LKindText := TDLProcKindNames[FKind];
  if FIsReferenceTo then
    LKindText := 'reference to ' + LKindText;
  if FIsOfObject then
    LSuffix := ' (of object)'
  else
    LSuffix := '';
  DumpHeader(ABuilder, AIndent, 'proc type %s%s', [LKindText, LSuffix]);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  :');
    FReturnType.Dump(ABuilder, AIndent + 1);
  end;
  for LDirective in FDirectives do
    LDirective.Dump(ABuilder, AIndent + 1);
end;

{ TDLPropertyDecl }

constructor TDLPropertyDecl.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier;
  AVisibility: TDLVisibility);
begin
  inherited Create(ASpan, AVisibility, False);
  FName := AName;
  FIndexParams := TList<TDLParameter>.Create;
  FImplements := TList<TDLExpr>.Create;
end;

destructor TDLPropertyDecl.Destroy;
begin
  FName.Free;
  FIndexParams.Free;
  FTypeExpr.Free;
  FIndexSpec.Free;
  FReadName.Free;
  FWriteName.Free;
  FStoredName.Free;
  FStoredExpr.Free;
  FDefaultValue.Free;
  FImplements.Free;
  inherited Destroy;
end;

procedure TDLPropertyDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParameter;
  LImpl: TDLExpr;
  LDetails: string;
  LSuffix: string;
begin
  LDetails := FName.Name;
  if FIndexParams.Count > 0 then
    LDetails := LDetails + ' []';
  if FTypeExpr <> nil then
    LDetails := LDetails + ' : ' + FTypeExpr.ClassName;
  DumpHeader(ABuilder, AIndent, 'property %s', [LDetails]);
  for LParam in FIndexParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FTypeExpr <> nil then
    FTypeExpr.Dump(ABuilder, AIndent + 1);
  if FIndexSpec <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  index');
    FIndexSpec.Dump(ABuilder, AIndent + 1);
  end;
  if FReadName <> nil then
  begin
    if FReadIsFunc then
      LSuffix := ' (func)'
    else
      LSuffix := '';
    TDLDump.Line(ABuilder, AIndent, '  read %s%s', [FReadName.Name, LSuffix]);
  end;
  if FWriteName <> nil then
  begin
    if FWriteIsFunc then
      LSuffix := ' (func)'
    else
      LSuffix := '';
    TDLDump.Line(ABuilder, AIndent, '  write %s%s', [FWriteName.Name, LSuffix]);
  end;
  if FStoredName <> nil then
  begin
    if FStoredIsFunc then
      LSuffix := ' (func)'
    else
      LSuffix := '';
    TDLDump.Line(ABuilder, AIndent, '  stored %s%s', [FStoredName.Name,
      LSuffix]);
  end;
  if FIsDefault then
    TDLDump.Line(ABuilder, AIndent, '  default');
  if FIsNodefault then
    TDLDump.Line(ABuilder, AIndent, '  nodefault');
  for LImpl in FImplements do
  begin
    TDLDump.Line(ABuilder, AIndent, '  implements');
    LImpl.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLClassType }

constructor TDLClassType.Create(ASpan: TDLSourceSpan; AIsSealed, AIsAbstract,
  AIsHelper, AIsClassRef, AIsDispInterface, AIsObject, AIsInterface: Boolean;
  ABaseType, AHelperFor: TDLTypeExpr; AMembers: TList<TDLMember>);
begin
  inherited Create(ASpan);
  FIsSealed := AIsSealed;
  FIsAbstract := AIsAbstract;
  FIsHelper := AIsHelper;
  FIsClassRef := AIsClassRef;
  FIsDispInterface := AIsDispInterface;
  FIsObject := AIsObject;
  FIsInterface := AIsInterface;
  FBaseType := ABaseType;
  FHelperFor := AHelperFor;
  FMembers := AMembers;
  FInterfaces := TList<TDLNamedType>.Create;
end;

destructor TDLClassType.Destroy;
begin
  FBaseType.Free;
  FHelperFor.Free;
  FInterfaces.Free;
  FMembers.Free;
  inherited Destroy;
end;

procedure TDLClassType.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LMember: TDLMember;
  LKindText: string;
begin
  if FIsInterface then
    LKindText := 'interface'
  else if FIsObject then
    LKindText := 'object'
  else if FIsClassRef then
    LKindText := 'class of'
  else if FIsHelper then
    LKindText := 'class helper'
  else
    LKindText := 'class';
  if FIsSealed then
    LKindText := LKindText + ' sealed';
  if FIsAbstract then
    LKindText := LKindText + ' abstract';
  DumpHeader(ABuilder, AIndent, LKindText);
  if FHelperFor <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  for');
    FHelperFor.Dump(ABuilder, AIndent + 1);
  end;
  if FBaseType <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  base');
    FBaseType.Dump(ABuilder, AIndent + 1);
  end;
  for LMember in FMembers do
    LMember.Dump(ABuilder, AIndent + 1);
end;

{ TDLMethodImpl }

constructor TDLMethodImpl.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
  AName: TDLIdentifier; AClassModifier: TDLClassModifier);
begin
  inherited Create(ASpan, AKind, AName, AClassModifier);
  FLocalDecls := TList<TDLNode>.Create;
end;

destructor TDLMethodImpl.Destroy;
begin
  FLocalDecls.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLMethodImpl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LDecl: TDLNode;
begin
  DumpProcHeader(ABuilder, AIndent);
  for LDecl in FLocalDecls do
    LDecl.Dump(ABuilder, AIndent + 1);
  if FBody <> nil then
    FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLDirective }

constructor TDLDirective.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
  FValues := TList<TDLExpr>.Create;
end;

destructor TDLDirective.Destroy;
begin
  FName.Free;
  FValues.Free;
  inherited Destroy;
end;

procedure TDLDirective.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LValue: TDLExpr;
begin
  DumpHeader(ABuilder, AIndent, FName.Name);
  for LValue in FValues do
    LValue.Dump(ABuilder, AIndent + 1);
end;

{ TDLParameter }

constructor TDLParameter.Create(ASpan: TDLSourceSpan; AModifier: TDLParamModifier);
begin
  inherited Create(ASpan);
  FNames := TList<TDLIdentifier>.Create;
  FModifier := AModifier;
  FAttributes := TList<TDLAttribute>.Create;
end;

destructor TDLParameter.Destroy;
begin
  FNames.Free;
  FTypeExpr.Free;
  FDefaultValue.Free;
  FAttributes.Free;
  inherited Destroy;
end;

procedure TDLParameter.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LName: TDLIdentifier;
  LNames: string;
begin
  LNames := '';
  for LName in FNames do
  begin
    if LNames <> '' then
      LNames := LNames + ', ';
    LNames := LNames + LName.Name;
  end;
  DumpHeader(ABuilder, AIndent, '%s %s', [TDLParamModifierNames[FModifier], LNames]);
  if FTypeExpr <> nil then
    FTypeExpr.Dump(ABuilder, AIndent + 1);
  if FDefaultValue <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  =');
    FDefaultValue.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLAttribute }

constructor TDLAttribute.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FNamePath := TList<TDLIdentifier>.Create;
  FArgs := TList<TDLExpr>.Create;
end;

destructor TDLAttribute.Destroy;
begin
  FNamePath.Free;
  FArgs.Free;
  inherited Destroy;
end;

procedure TDLAttribute.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LName: TDLIdentifier;
  LArg: TDLExpr;
  LPath: string;
begin
  LPath := '';
  for LName in FNamePath do
  begin
    if LPath <> '' then
      LPath := LPath + '.';
    LPath := LPath + LName.Name;
  end;
  DumpHeader(ABuilder, AIndent, '[%s]', [LPath]);
  for LArg in FArgs do
    LArg.Dump(ABuilder, AIndent + 1);
end;

{ TDLCompilationUnit }

constructor TDLCompilationUnit.Create(ASpan: TDLSourceSpan;
  AProgramKind: TDLProgramKind; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FProgramKind := AProgramKind;
  FName := AName;
  FProgramParams := TList<TDLIdentifier>.Create;
  FUsesClauses := TList<TDLUsesClause>.Create;
  FItems := TList<TDLNode>.Create;
end;

destructor TDLCompilationUnit.Destroy;
begin
  FName.Free;
  FProgramParams.Free;
  FUsesClauses.Free;
  FItems.Free;
  FInitSection.Free;
  FFinalizationSection.Free;
  FRequiresClause.Free;
  FContainsClause.Free;
  inherited Destroy;
end;

procedure TDLCompilationUnit.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LUses: TDLUsesClause;
  LItem: TDLNode;
begin
  DumpHeader(ABuilder, AIndent, '%s %s', [TDLProgramKindNames[FProgramKind],
    FName.Name]);
  for LUses in FUsesClauses do
    LUses.Dump(ABuilder, AIndent + 1);
  if FRequiresClause <> nil then
    FRequiresClause.Dump(ABuilder, AIndent + 1);
  if FContainsClause <> nil then
    FContainsClause.Dump(ABuilder, AIndent + 1);
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
  if FInitSection <> nil then
    FInitSection.Dump(ABuilder, AIndent + 1);
  if FFinalizationSection <> nil then
    FFinalizationSection.Dump(ABuilder, AIndent + 1);
end;

{ TDLUnitReference }

constructor TDLUnitReference.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
end;

destructor TDLUnitReference.Destroy;
begin
  FName.Free;
  FInFile.Free;
  inherited Destroy;
end;

procedure TDLUnitReference.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, FName.Name);
  if FInFile <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  in');
    FInFile.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLUsesClause }

constructor TDLUsesClause.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FReferences := TList<TDLUnitReference>.Create;
end;

destructor TDLUsesClause.Destroy;
begin
  FReferences.Free;
  inherited Destroy;
end;

procedure TDLUsesClause.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LReference: TDLUnitReference;
begin
  DumpHeader(ABuilder, AIndent, 'uses');
  for LReference in FReferences do
    LReference.Dump(ABuilder, AIndent + 1);
end;

{ TDLExportItem }

constructor TDLExportItem.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
  FDirectives := TList<TDLDirective>.Create;
end;

destructor TDLExportItem.Destroy;
begin
  FName.Free;
  FIndex.Free;
  FNameSpec.Free;
  FDirectives.Free;
  inherited Destroy;
end;

procedure TDLExportItem.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LDirective: TDLDirective;
begin
  DumpHeader(ABuilder, AIndent, FName.Name);
  if FIndex <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  index');
    FIndex.Dump(ABuilder, AIndent + 1);
  end;
  if FNameSpec <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  name');
    FNameSpec.Dump(ABuilder, AIndent + 1);
  end;
  for LDirective in FDirectives do
    LDirective.Dump(ABuilder, AIndent + 1);
end;

{ TDLDeclItem }

constructor TDLDeclItem.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FAttributes := TList<TDLAttribute>.Create;
end;

destructor TDLDeclItem.Destroy;
begin
  FAttributes.Free;
  inherited Destroy;
end;

{ TDLTypeDecl }

constructor TDLTypeDecl.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier;
  ATypeExpr: TDLTypeExpr);
begin
  inherited Create(ASpan);
  FName := AName;
  FTypeExpr := ATypeExpr;
  FTypeParams := TList<TDLIdentifier>.Create;
end;

destructor TDLTypeDecl.Destroy;
begin
  FName.Free;
  FTypeExpr.Free;
  FTypeParams.Free;
  inherited Destroy;
end;

procedure TDLTypeDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLIdentifier;
  LParams: string;
begin
  if FTypeParams.Count > 0 then
  begin
    LParams := '';
    for LParam in FTypeParams do
    begin
      if LParams <> '' then
        LParams := LParams + ', ';
      LParams := LParams + LParam.Name;
    end;
    DumpHeader(ABuilder, AIndent, '%s<%s> =', [FName.Name, LParams]);
  end
  else
    DumpHeader(ABuilder, AIndent, '%s =', [FName.Name]);
  FTypeExpr.Dump(ABuilder, AIndent + 1);
end;

{ TDLTypeSection }

constructor TDLTypeSection.Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
begin
  inherited Create(ASpan);
  FIsPacked := AIsPacked;
  FItems := TList<TDLNode>.Create;
end;

destructor TDLTypeSection.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLTypeSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LItem: TDLNode;
begin
  DumpHeader(ABuilder, AIndent, 'type (%s)', [BoolToStr(FIsPacked, True)]);
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLConstDecl }

constructor TDLConstDecl.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FNames := TList<TDLIdentifier>.Create;
end;

destructor TDLConstDecl.Destroy;
begin
  FNames.Free;
  FTypeExpr.Free;
  FValue.Free;
  inherited Destroy;
end;

procedure TDLConstDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LName: TDLIdentifier;
  LNames: string;
  LSuffix: string;
begin
  LNames := '';
  for LName in FNames do
  begin
    if LNames <> '' then
      LNames := LNames + ', ';
    LNames := LNames + LName.Name;
  end;
  if FIsTyped then
    LSuffix := ' (typed)'
  else
    LSuffix := '';
  DumpHeader(ABuilder, AIndent, 'const %s%s', [LNames, LSuffix]);
  if FTypeExpr <> nil then
    FTypeExpr.Dump(ABuilder, AIndent + 1);
  if FValue <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  =');
    FValue.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLConstSection }

constructor TDLConstSection.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FItems := TList<TDLNode>.Create;
end;

destructor TDLConstSection.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLConstSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LItem: TDLNode;
begin
  DumpHeader(ABuilder, AIndent, 'const');
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLResStringSection }

constructor TDLResStringSection.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FItems := TList<TDLConstDecl>.Create;
end;

destructor TDLResStringSection.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLResStringSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LItem: TDLConstDecl;
begin
  DumpHeader(ABuilder, AIndent, 'resourcestring');
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLVarDecl }

constructor TDLVarDecl.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FNames := TList<TDLIdentifier>.Create;
end;

destructor TDLVarDecl.Destroy;
begin
  FNames.Free;
  FTypeExpr.Free;
  FInit.Free;
  FAbsoluteTarget.Free;
  inherited Destroy;
end;

procedure TDLVarDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LName: TDLIdentifier;
  LNames: string;
begin
  LNames := '';
  for LName in FNames do
  begin
    if LNames <> '' then
      LNames := LNames + ', ';
    LNames := LNames + LName.Name;
  end;
  DumpHeader(ABuilder, AIndent, 'var %s', [LNames]);
  if FTypeExpr <> nil then
    FTypeExpr.Dump(ABuilder, AIndent + 1);
  if FAbsoluteTarget <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  absolute');
    FAbsoluteTarget.Dump(ABuilder, AIndent + 1);
  end;
  if FInit <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  =');
    FInit.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLVarSection }

constructor TDLVarSection.Create(ASpan: TDLSourceSpan; AIsThreadVar: Boolean);
begin
  inherited Create(ASpan);
  FIsThreadVar := AIsThreadVar;
  FItems := TList<TDLNode>.Create;
end;

destructor TDLVarSection.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLVarSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LItem: TDLNode;
begin
  if FIsThreadVar then
    DumpHeader(ABuilder, AIndent, 'threadvar')
  else
    DumpHeader(ABuilder, AIndent, 'var');
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLLabelDecl }

constructor TDLLabelDecl.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
end;

destructor TDLLabelDecl.Destroy;
begin
  FName.Free;
  inherited Destroy;
end;

procedure TDLLabelDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, FName.Name);
end;

{ TDLLabelSection }

constructor TDLLabelSection.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FItems := TList<TDLLabelDecl>.Create;
end;

destructor TDLLabelSection.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLLabelSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LItem: TDLLabelDecl;
begin
  DumpHeader(ABuilder, AIndent, 'label');
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLExportsClause }

constructor TDLExportsClause.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FItems := TList<TDLExportItem>.Create;
end;

destructor TDLExportsClause.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDLExportsClause.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LItem: TDLExportItem;
begin
  DumpHeader(ABuilder, AIndent, 'exports');
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLInitSection }

constructor TDLInitSection.Create(ASpan: TDLSourceSpan; ABody: TDLStatement);
begin
  inherited Create(ASpan);
  FBody := ABody;
end;

destructor TDLInitSection.Destroy;
begin
  FBody.Free;
  inherited Destroy;
end;

procedure TDLInitSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'initialization');
  if FBody <> nil then
    FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLFinalizationSection }

constructor TDLFinalizationSection.Create(ASpan: TDLSourceSpan;
  ABody: TDLStatement);
begin
  inherited Create(ASpan);
  FBody := ABody;
end;

destructor TDLFinalizationSection.Destroy;
begin
  FBody.Free;
  inherited Destroy;
end;

procedure TDLFinalizationSection.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'finalization');
  if FBody <> nil then
    FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLCompoundStmt }

constructor TDLCompoundStmt.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FStatements := TList<TDLStatement>.Create;
end;

destructor TDLCompoundStmt.Destroy;
begin
  FStatements.Free;
  inherited Destroy;
end;

procedure TDLCompoundStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LStatement: TDLStatement;
begin
  DumpHeader(ABuilder, AIndent, 'begin');
  for LStatement in FStatements do
    LStatement.Dump(ABuilder, AIndent + 1);
  DumpHeader(ABuilder, AIndent, 'end');
end;

{ TDLConditionalBranch }

constructor TDLConditionalBranch.Create(ASpan: TDLSourceSpan;
  ACondition: TDLCondition);
begin
  inherited Create(ASpan);
  FCondition := ACondition;
  FStatements := TList<TDLStatement>.Create;
end;

destructor TDLConditionalBranch.Destroy;
begin
  FCondition.Free;
  FStatements.Free;
  inherited Destroy;
end;

procedure TDLConditionalBranch.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LStatement: TDLStatement;
begin
  if FCondition = nil then
    DumpHeader(ABuilder, AIndent, 'branch')
  else
    DumpHeader(ABuilder, AIndent, 'branch ' + FCondition.ToString);
  for LStatement in FStatements do
    LStatement.Dump(ABuilder, AIndent + 1);
end;

{ TDLConditionalStmt }

constructor TDLConditionalStmt.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FBranches := TList<TDLConditionalBranch>.Create;
end;

destructor TDLConditionalStmt.Destroy;
begin
  FBranches.Free;
  inherited Destroy;
end;

procedure TDLConditionalStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LBranch: TDLConditionalBranch;
begin
  DumpHeader(ABuilder, AIndent, 'conditional');
  for LBranch in FBranches do
    LBranch.Dump(ABuilder, AIndent + 1);
end;

{ TDLConditionalDeclBranch }

constructor TDLConditionalDeclBranch.Create(ASpan: TDLSourceSpan;
  ACondition: TDLCondition);
begin
  inherited Create(ASpan);
  FCondition := ACondition;
  FItems := TList<TDLNode>.Create;
end;

destructor TDLConditionalDeclBranch.Destroy;
begin
  FCondition.Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TDLConditionalDeclBranch.Dump(ABuilder: TStringBuilder;
  AIndent: Integer);
var
  LItem: TDLNode;
begin
  if FCondition = nil then
    DumpHeader(ABuilder, AIndent, 'decl-branch')
  else
    DumpHeader(ABuilder, AIndent, 'decl-branch ' + FCondition.ToString);
  for LItem in FItems do
    LItem.Dump(ABuilder, AIndent + 1);
end;

{ TDLConditionalGroup }

constructor TDLConditionalGroup.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FBranches := TList<TDLConditionalDeclBranch>.Create;
end;

destructor TDLConditionalGroup.Destroy;
begin
  FBranches.Free;
  inherited Destroy;
end;

procedure TDLConditionalGroup.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LBranch: TDLConditionalDeclBranch;
begin
  DumpHeader(ABuilder, AIndent, 'conditional-decls');
  for LBranch in FBranches do
    LBranch.Dump(ABuilder, AIndent + 1);
end;

{ TDLIfStmt }

constructor TDLIfStmt.Create(ASpan: TDLSourceSpan; ACondition: TDLExpr;
  AThenBranch: TDLStatement);
begin
  inherited Create(ASpan);
  FCondition := ACondition;
  FThenBranch := AThenBranch;
end;

destructor TDLIfStmt.Destroy;
begin
  FCondition.Free;
  FThenBranch.Free;
  FElseBranch.Free;
  inherited Destroy;
end;

procedure TDLIfStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'if');
  FCondition.Dump(ABuilder, AIndent + 1);
  TDLDump.Line(ABuilder, AIndent, '  then');
  FThenBranch.Dump(ABuilder, AIndent + 1);
  if FElseBranch <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  else');
    FElseBranch.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLCaseStmt }

constructor TDLCaseStmt.Create(ASpan: TDLSourceSpan; ASubject: TDLExpr);
begin
  inherited Create(ASpan);
  FSubject := ASubject;
  FSelectors := TList<TDLCaseSelector>.Create;
end;

destructor TDLCaseStmt.Destroy;
begin
  FSubject.Free;
  FSelectors.Free;
  FElseBranch.Free;
  inherited Destroy;
end;

procedure TDLCaseStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LSelector: TDLCaseSelector;
begin
  DumpHeader(ABuilder, AIndent, 'case');
  FSubject.Dump(ABuilder, AIndent + 1);
  TDLDump.Line(ABuilder, AIndent, '  of');
  for LSelector in FSelectors do
    LSelector.Dump(ABuilder, AIndent + 1);
  if FElseBranch <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  else');
    FElseBranch.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLCaseSelector }

constructor TDLCaseSelector.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FLabels := TList<TDLExpr>.Create;
end;

destructor TDLCaseSelector.Destroy;
begin
  FLabels.Free;
  FStatement.Free;
  inherited Destroy;
end;

procedure TDLCaseSelector.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LLabel: TDLExpr;
begin
  DumpHeader(ABuilder, AIndent, 'selector');
  for LLabel in FLabels do
    LLabel.Dump(ABuilder, AIndent + 1);
  if FStatement <> nil then
    FStatement.Dump(ABuilder, AIndent + 1);
end;

{ TDLForStmt }

constructor TDLForStmt.Create(ASpan: TDLSourceSpan; ALoopVar: TDLIdentifier;
  AIsInlineVar: Boolean; ADirection: TDLKeyword);
begin
  inherited Create(ASpan);
  FLoopVar := ALoopVar;
  FIsInlineVar := AIsInlineVar;
  FDirection := ADirection;
end;

destructor TDLForStmt.Destroy;
begin
  FLoopVar.Free;
  FStartExpr.Free;
  FEndExpr.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLForStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LDirection: string;
  LSuffix: string;
begin
  case FDirection of
    kwTo: LDirection := 'to';
    kwDownTo: LDirection := 'downto';
  else
    LDirection := 'in';
  end;
  if FIsInlineVar then
    LSuffix := ' (inline)'
  else
    LSuffix := '';
  DumpHeader(ABuilder, AIndent, 'for %s%s %s', [FLoopVar.Name, LSuffix,
    LDirection]);
  if FStartExpr <> nil then
    FStartExpr.Dump(ABuilder, AIndent + 1);
  if FEndExpr <> nil then
    FEndExpr.Dump(ABuilder, AIndent + 1);
  FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLWhileStmt }

constructor TDLWhileStmt.Create(ASpan: TDLSourceSpan; ACondition: TDLExpr);
begin
  inherited Create(ASpan);
  FCondition := ACondition;
end;

destructor TDLWhileStmt.Destroy;
begin
  FCondition.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLWhileStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'while');
  FCondition.Dump(ABuilder, AIndent + 1);
  FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLRepeatStmt }

constructor TDLRepeatStmt.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
end;

destructor TDLRepeatStmt.Destroy;
begin
  FBody.Free;
  FCondition.Free;
  inherited Destroy;
end;

procedure TDLRepeatStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'repeat');
  FBody.Dump(ABuilder, AIndent + 1);
  TDLDump.Line(ABuilder, AIndent, '  until');
  FCondition.Dump(ABuilder, AIndent + 1);
end;

{ TDLWithStmt }

constructor TDLWithStmt.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FExpressions := TList<TDLExpr>.Create;
end;

destructor TDLWithStmt.Destroy;
begin
  FExpressions.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLWithStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LExpression: TDLExpr;
begin
  DumpHeader(ABuilder, AIndent, 'with');
  for LExpression in FExpressions do
    LExpression.Dump(ABuilder, AIndent + 1);
  FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLTryStmt }

constructor TDLTryStmt.Create(ASpan: TDLSourceSpan; AIsExcept: Boolean);
begin
  inherited Create(ASpan);
  FIsExcept := AIsExcept;
  FOnHandlers := TList<TDLOnHandler>.Create;
end;

destructor TDLTryStmt.Destroy;
begin
  FBody.Free;
  FOnHandlers.Free;
  FElseBranch.Free;
  FFinallyBody.Free;
  inherited Destroy;
end;

procedure TDLTryStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LHandler: TDLOnHandler;
begin
  if FIsExcept then
    DumpHeader(ABuilder, AIndent, 'try except')
  else
    DumpHeader(ABuilder, AIndent, 'try finally');
  FBody.Dump(ABuilder, AIndent + 1);
  if FIsExcept then
  begin
    for LHandler in FOnHandlers do
      LHandler.Dump(ABuilder, AIndent + 1);
    if FElseBranch <> nil then
    begin
      TDLDump.Line(ABuilder, AIndent, '  else');
      FElseBranch.Dump(ABuilder, AIndent + 1);
    end;
  end
  else if FFinallyBody <> nil then
    FFinallyBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLOnHandler }

constructor TDLOnHandler.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
end;

destructor TDLOnHandler.Destroy;
begin
  FVarName.Free;
  FTypeName.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLOnHandler.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  if FVarName <> nil then
    DumpHeader(ABuilder, AIndent, 'on %s: %s', [FVarName.Name, FTypeName.Name])
  else
    DumpHeader(ABuilder, AIndent, 'on %s', [FTypeName.Name]);
  FBody.Dump(ABuilder, AIndent + 1);
end;

{ TDLRaiseStmt }

constructor TDLRaiseStmt.Create(ASpan: TDLSourceSpan; AException: TDLExpr);
begin
  inherited Create(ASpan);
  FException := AException;
end;

destructor TDLRaiseStmt.Destroy;
begin
  FException.Free;
  FAtAddr.Free;
  inherited Destroy;
end;

procedure TDLRaiseStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'raise');
  if FException <> nil then
    FException.Dump(ABuilder, AIndent + 1);
  if FAtAddr <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  at');
    FAtAddr.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLGotoStmt }

constructor TDLGotoStmt.Create(ASpan: TDLSourceSpan; ALabelName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FLabelName := ALabelName;
end;

destructor TDLGotoStmt.Destroy;
begin
  FLabelName.Free;
  inherited Destroy;
end;

procedure TDLGotoStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'goto %s', [FLabelName.Name]);
end;

{ TDLLabelStmt }

constructor TDLLabelStmt.Create(ASpan: TDLSourceSpan; ALabelName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FLabelName := ALabelName;
end;

destructor TDLLabelStmt.Destroy;
begin
  FLabelName.Free;
  FStatement.Free;
  inherited Destroy;
end;

procedure TDLLabelStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'label %s', [FLabelName.Name]);
  if FStatement <> nil then
    FStatement.Dump(ABuilder, AIndent + 1);
end;

{ TDLAssignmentStmt }

constructor TDLAssignmentStmt.Create(ASpan: TDLSourceSpan; ATarget, AValue: TDLExpr);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FValue := AValue;
end;

destructor TDLAssignmentStmt.Destroy;
begin
  FTarget.Free;
  FValue.Free;
  inherited Destroy;
end;

procedure TDLAssignmentStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, ':=');
  FTarget.Dump(ABuilder, AIndent + 1);
  FValue.Dump(ABuilder, AIndent + 1);
end;

{ TDLExprStmt }

constructor TDLExprStmt.Create(ASpan: TDLSourceSpan; AExpression: TDLExpr);
begin
  inherited Create(ASpan);
  FExpression := AExpression;
end;

destructor TDLExprStmt.Destroy;
begin
  FExpression.Free;
  inherited Destroy;
end;

procedure TDLExprStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'expr');
  FExpression.Dump(ABuilder, AIndent + 1);
end;

{ TDLAsmStmt }

constructor TDLAsmStmt.Create(ASpan: TDLSourceSpan; const AText: string);
begin
  inherited Create(ASpan);
  FText := AText;
end;

procedure TDLAsmStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'asm');
  TDLDump.Line(ABuilder, AIndent + 1, Trim(FText));
end;

{ TDLExitStmt }

constructor TDLExitStmt.Create(ASpan: TDLSourceSpan; AExpression: TDLExpr);
begin
  inherited Create(ASpan);
  FExpression := AExpression;
end;

destructor TDLExitStmt.Destroy;
begin
  FExpression.Free;
  inherited Destroy;
end;

procedure TDLExitStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'exit');
  if FExpression <> nil then
    FExpression.Dump(ABuilder, AIndent + 1);
end;

{ TDLBreakStmt }

procedure TDLBreakStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'break');
end;

{ TDLContinueStmt }

procedure TDLContinueStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'continue');
end;

{ TDLVarDeclStmt }

constructor TDLVarDeclStmt.Create(ASpan: TDLSourceSpan; AVarDecl: TDLVarDecl);
begin
  inherited Create(ASpan);
  FVarDecl := AVarDecl;
end;

destructor TDLVarDeclStmt.Destroy;
begin
  FVarDecl.Free;
  inherited Destroy;
end;

procedure TDLVarDeclStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'inline var');
  FVarDecl.Dump(ABuilder, AIndent + 1);
end;

{ TDLEmptyStmt }

procedure TDLEmptyStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'empty');
end;

{ TDLIdentifierExpr }

constructor TDLIdentifierExpr.Create(ASpan: TDLSourceSpan; AName: TDLIdentifier);
begin
  inherited Create(ASpan);
  FName := AName;
end;

destructor TDLIdentifierExpr.Destroy;
begin
  FName.Free;
  inherited Destroy;
end;

procedure TDLIdentifierExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'id %s', [FName.Name]);
end;

{ TDLNumberExpr }

constructor TDLNumberExpr.Create(ASpan: TDLSourceSpan; AToken: TDLTokenRef);
begin
  inherited Create(ASpan);
  FToken := AToken;
end;

procedure TDLNumberExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  if FToken.Kind = tkFloat then
    DumpHeader(ABuilder, AIndent, 'num %g', [FToken.FloatValue])
  else
    DumpHeader(ABuilder, AIndent, 'num %d', [FToken.IntegerValue]);
end;

{ TDLStringExpr }

constructor TDLStringExpr.Create(ASpan: TDLSourceSpan; AToken: TDLTokenRef;
  const AValue: string);
begin
  inherited Create(ASpan);
  FToken := AToken;
  FValue := AValue;
end;

procedure TDLStringExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'str %s', [FValue]);
end;

{ TDLNilExpr }

procedure TDLNilExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'nil');
end;

{ TDLSetExpr }

constructor TDLSetExpr.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FElements := TList<TDLExpr>.Create;
  FIsRanges := TList<Boolean>.Create;
end;

destructor TDLSetExpr.Destroy;
begin
  FElements.Free;
  FIsRanges.Free;
  inherited Destroy;
end;

procedure TDLSetExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  i: Integer;
begin
  DumpHeader(ABuilder, AIndent, 'set');
  for i := 0 to FElements.Count - 1 do
  begin
    if FIsRanges[i] then
      TDLDump.Line(ABuilder, AIndent, '  range');
    FElements[i].Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLArrayExpr }

constructor TDLArrayExpr.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FElements := TList<TDLExpr>.Create;
end;

destructor TDLArrayExpr.Destroy;
begin
  FElements.Free;
  inherited Destroy;
end;

procedure TDLArrayExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LElement: TDLExpr;
begin
  DumpHeader(ABuilder, AIndent, 'array');
  for LElement in FElements do
    LElement.Dump(ABuilder, AIndent + 1);
end;

{ TDLBinaryExpr }

constructor TDLBinaryExpr.Create(ASpan: TDLSourceSpan; AOperator: TDLBinaryOp;
  const AOperatorText: string; ALeft, ARight: TDLExpr);
begin
  inherited Create(ASpan);
  FOperator := AOperator;
  FOperatorText := AOperatorText;
  FLeft := ALeft;
  FRight := ARight;
end;

destructor TDLBinaryExpr.Destroy;
begin
  FLeft.Free;
  FRight.Free;
  inherited Destroy;
end;

procedure TDLBinaryExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, '%s', [FOperatorText]);
  FLeft.Dump(ABuilder, AIndent + 1);
  FRight.Dump(ABuilder, AIndent + 1);
end;

{ TDLUnaryExpr }

constructor TDLUnaryExpr.Create(ASpan: TDLSourceSpan; AOperator: TDLUnaryOp;
  const AOperatorText: string; AOperand: TDLExpr);
begin
  inherited Create(ASpan);
  FOperator := AOperator;
  FOperatorText := AOperatorText;
  FOperand := AOperand;
end;

destructor TDLUnaryExpr.Destroy;
begin
  FOperand.Free;
  inherited Destroy;
end;

procedure TDLUnaryExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, '%s', [FOperatorText]);
  FOperand.Dump(ABuilder, AIndent + 1);
end;

{ TDLIndexExpr }

constructor TDLIndexExpr.Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FIndices := TList<TDLExpr>.Create;
end;

destructor TDLIndexExpr.Destroy;
begin
  FTarget.Free;
  FIndices.Free;
  inherited Destroy;
end;

procedure TDLIndexExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LIndex: TDLExpr;
begin
  DumpHeader(ABuilder, AIndent, 'index');
  FTarget.Dump(ABuilder, AIndent + 1);
  for LIndex in FIndices do
    LIndex.Dump(ABuilder, AIndent + 1);
end;

{ TDLCallExpr }

constructor TDLCallExpr.Create(ASpan: TDLSourceSpan; ACallee: TDLExpr);
begin
  inherited Create(ASpan);
  FCallee := ACallee;
  FArgs := TList<TDLExpr>.Create;
end;

destructor TDLCallExpr.Destroy;
begin
  FCallee.Free;
  FArgs.Free;
  inherited Destroy;
end;

procedure TDLCallExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LArg: TDLExpr;
begin
  DumpHeader(ABuilder, AIndent, 'call');
  FCallee.Dump(ABuilder, AIndent + 1);
  for LArg in FArgs do
    LArg.Dump(ABuilder, AIndent + 1);
end;

{ TDLMemberExpr }

constructor TDLMemberExpr.Create(ASpan: TDLSourceSpan; ATarget: TDLExpr;
  AMember: TDLIdentifier);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FMember := AMember;
end;

destructor TDLMemberExpr.Destroy;
begin
  FTarget.Free;
  FMember.Free;
  inherited Destroy;
end;

procedure TDLMemberExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'member .%s', [FMember.Name]);
  FTarget.Dump(ABuilder, AIndent + 1);
end;

{ TDLGenericInstantiationExpr }

constructor TDLGenericInstantiationExpr.Create(ASpan: TDLSourceSpan;
  ATarget: TDLExpr);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FTypeArgs := TList<TDLTypeArg>.Create;
end;

destructor TDLGenericInstantiationExpr.Destroy;
begin
  FTarget.Free;
  FTypeArgs.Free;
  inherited Destroy;
end;

procedure TDLGenericInstantiationExpr.Dump(ABuilder: TStringBuilder;
  AIndent: Integer);
var
  LArg: TDLTypeArg;
begin
  DumpHeader(ABuilder, AIndent, 'generic');
  FTarget.Dump(ABuilder, AIndent + 1);
  for LArg in FTypeArgs do
    LArg.Dump(ABuilder, AIndent + 1);
end;

{ TDLInheritedExpr }

constructor TDLInheritedExpr.Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
end;

destructor TDLInheritedExpr.Destroy;
begin
  FTarget.Free;
  inherited Destroy;
end;

procedure TDLInheritedExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'inherited');
  if FTarget <> nil then
    FTarget.Dump(ABuilder, AIndent + 1);
end;

{ TDLAnonymousMethodExpr }

constructor TDLAnonymousMethodExpr.Create(ASpan: TDLSourceSpan;
  AKind: TDLProcKind; AIsReferenceTo: Boolean);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FIsReferenceTo := AIsReferenceTo;
  FParams := TList<TDLParameter>.Create;
end;

destructor TDLAnonymousMethodExpr.Destroy;
begin
  FParams.Free;
  FReturnType.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLAnonymousMethodExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParameter;
begin
  if FIsReferenceTo then
    DumpHeader(ABuilder, AIndent, 'reference to %s', [TDLProcKindNames[FKind]])
  else
    DumpHeader(ABuilder, AIndent, 'anonymous %s', [TDLProcKindNames[FKind]]);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  :');
    FReturnType.Dump(ABuilder, AIndent + 1);
  end;
  if FBody <> nil then
    FBody.Dump(ABuilder, AIndent + 1);
end;

{ ------------------------------------------------------------------ }
{ Expression source-text rendering                                    }
{ ------------------------------------------------------------------ }

function TDLIdentifierExpr.ToSourceText: string;
begin
  Result := FName.Name;
end;

function TDLNumberExpr.ToSourceText: string;
begin
  Result := FToken.Text;
end;

function TDLStringExpr.ToSourceText: string;
begin
  Result := StringReplace(FValue, '''', '''''', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
  Result := '''' + Result + '''';
end;

function TDLNilExpr.ToSourceText: string;
begin
  Result := 'nil';
end;

function TDLBinaryExpr.ToSourceText: string;
begin
  Result := FLeft.ToSourceText + ' ' + FOperatorText + ' ' +
    FRight.ToSourceText;
end;

function TDLUnaryExpr.ToSourceText: string;
begin
  Result := FOperatorText + FOperand.ToSourceText;
end;

function TDLCallExpr.ToSourceText: string;
var
  i: Integer;
begin
  Result := FCallee.ToSourceText + '(';
  for i := 0 to FArgs.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + FArgs[i].ToSourceText;
  end;
  Result := Result + ')';
end;

function TDLMemberExpr.ToSourceText: string;
begin
  Result := FTarget.ToSourceText + '.' + FMember.Name;
end;

function TDLIndexExpr.ToSourceText: string;
var
  i: Integer;
begin
  Result := FTarget.ToSourceText + '[';
  for i := 0 to FIndices.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + FIndices[i].ToSourceText;
  end;
  Result := Result + ']';
end;

function TDLGenericInstantiationExpr.ToSourceText: string;
var
  i: Integer;
begin
  Result := FTarget.ToSourceText + '<';
  for i := 0 to FTypeArgs.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    if FTypeArgs[i].TypeExpr is TDLNamedType then
      Result := Result + TDLNamedType(FTypeArgs[i].TypeExpr).Name.Name
    else
      Result := Result + '?';
  end;
  Result := Result + '>';
end;

function TDLSetExpr.ToSourceText: string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to FElements.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + FElements[i].ToSourceText;
  end;
  Result := Result + ']';
end;

function TDLArrayExpr.ToSourceText: string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to FElements.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + FElements[i].ToSourceText;
  end;
  Result := Result + ']';
end;

function TDLInheritedExpr.ToSourceText: string;
begin
  if FTarget <> nil then
    Result := 'inherited ' + FTarget.ToSourceText
  else
    Result := 'inherited';
end;

function TDLAnonymousMethodExpr.ToSourceText: string;
begin
  Result := '<anonymous method>';
end;

end.
