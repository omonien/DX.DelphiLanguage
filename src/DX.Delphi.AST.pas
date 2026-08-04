/// <summary>
///   DX.Delphi.AST — abstract syntax tree node hierarchy for Delphi source.
/// </summary>
/// <remarks>
///   The AST is the semantic, cleaned-up counterpart of the CST: trivia,
///   tokens and source-layout details are dropped, identifiers are plain
///   strings, and constructs are folded into their meaning (e.g. a "type
///   section" becomes a list of type declarations, anonymous-method
///   expressions and method declarations share the procedural shape).
///
///   The AST is produced from the CST by DX.Delphi.AstBuilder (lowering
///   pass). It is the tree consumed by semantic analysis, tooling and code
///   generation.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit DX.Delphi.AST;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Delphi.Core;

type
  /// <summary>Module kind.</summary>
  TDLModuleKind = (
    mkProgram,
    mkUnit,
    mkLibrary,
    mkPackage
  );

  /// <summary>Procedure/function kind.</summary>
  TDLProcKind = (
    pkProcedure,
    pkFunction,
    pkConstructor,
    pkDestructor,
    pkOperator
  );

  /// <summary>Parameter passing mode.</summary>
  TDLParamMode = (
    pmDefault,
    pmConst,
    pmVar,
    pmOut,
    pmConstRef,
    pmVarRef
  );

  /// <summary>Member visibility.</summary>
  TDLVisibility = (
    vsNone,
    vsPrivate,
    vsProtected,
    vsPublic,
    vsPublished,
    vsAutomated
  );

  /// <summary>Binary operator.</summary>
  TDLBinOp = (
    boNone,
    boAdd, boSubtract, boMultiply, boDivide, boDiv, boMod,
    boAnd, boOr, boXor, boShl, boShr,
    boAs, boIs, boIn,
    boEq, boNeq, boLt, boLe, boGt, boGe
  );

  /// <summary>Unary operator.</summary>
  TDLUnOp = (
    uoNone,
    uoPlus, uoMinus, uoNot, uoAddr, uoDeref
  );

  TDLNode = class;
  TDLTypeDef = class;
  TDLStmt = class;
  TDLExpr = class;

  /// <summary>Base class of all AST nodes.</summary>
  TDLNode = class abstract(TDLDumpable)
  private
    FSpan: TDLSourceSpan;
  public
    constructor Create(ASpan: TDLSourceSpan);
    procedure DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
      const AText: string; const AArgs: array of const); overload;
    procedure DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
      const AText: string); overload;
    property Span: TDLSourceSpan read FSpan write FSpan;
  end;

  /// <summary>Use of another unit.</summary>
  TDLUse = class(TDLNode)
  private
    FName: string;
    FInFile: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
    property InFile: string read FInFile write FInFile;
  end;

  TDLDeclaration = class;

  /// <summary>A compilation module (program/unit/library/package).</summary>
  TDLModule = class abstract(TDLNode)
  private
    FKind: TDLModuleKind;
    FName: string;
    FUses: TList<TDLUse>;
    FDeclarations: TList<TDLDeclaration>;
    FInitStatements: TList<TDLStmt>;
    FFinalStatements: TList<TDLStmt>;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLModuleKind;
      const AName: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLModuleKind read FKind;
    property Name: string read FName;
    property UsedUnits: TList<TDLUse> read FUses;
    property Declarations: TList<TDLDeclaration> read FDeclarations;
    property InitStatements: TList<TDLStmt> read FInitStatements;
    property FinalStatements: TList<TDLStmt> read FFinalStatements;
  end;

  /// <summary>A declaration at module scope.</summary>
  TDLDeclaration = class abstract(TDLNode)
  end;

  /// <summary>A type definition (right-hand side of 'Name = ...').</summary>
  TDLTypeDef = class abstract(TDLNode)
  end;

  TDLParam = class;
  TDLMethod = class;
  TDLProperty = class;
  TDLField = class;
  TDLVariantPart = class;
  TDLOnHandler = class;

  /// <summary>A member of a class/record/interface body.</summary>
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

  /// <summary>Visibility marker section.</summary>
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
  TDLField = class(TDLMember)
  private
    FNames: TList<string>;
    FTypeName: string;
  public
    constructor Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
      AIsStrict: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<string> read FNames;
    property TypeName: string read FTypeName write FTypeName;
  end;

  /// <summary>class var section.</summary>
  TDLClassVar = class(TDLMember)
  private
    FFields: TList<TDLField>;
  public
    constructor Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
      AIsStrict: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Fields: TList<TDLField> read FFields;
  end;

  /// <summary>A method (declaration or implementation).</summary>
  TDLMethod = class(TDLMember)
  private
    FKind: TDLProcKind;
    FName: string;
    FIsClass: Boolean;
    FIsStatic: Boolean;
    FParams: TList<TDLParam>;
    FReturnType: string;
    FBody: TList<TDLStmt>;
    FHasBody: Boolean;
    FDirectives: TList<string>;
    FOperatorName: string;
    FLocalDeclarations: TList<TDLDeclaration>;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      const AName: string; AIsClass: Boolean; AVisibility: TDLVisibility);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLProcKind read FKind;
    property Name: string read FName;
    property IsClass: Boolean read FIsClass write FIsClass;
    property IsStatic: Boolean read FIsStatic write FIsStatic;
    property Params: TList<TDLParam> read FParams;
    property ReturnType: string read FReturnType write FReturnType;
    property Body: TList<TDLStmt> read FBody;
    property HasBody: Boolean read FHasBody write FHasBody;
    property Directives: TList<string> read FDirectives;
    property OperatorName: string read FOperatorName write FOperatorName;
    /// <summary>Local declarations (vars/labels/consts/types) of the body.</summary>
    property LocalDeclarations: TList<TDLDeclaration> read FLocalDeclarations;
  end;

  /// <summary>A property declaration.</summary>
  TDLProperty = class(TDLMember)
  private
    FName: string;
    FTypeName: string;
    FIndexParams: TList<TDLParam>;
    FReadName: string;
    FWriteName: string;
    FStoredName: string;
    FIsDefault: Boolean;
    FDefaultValue: TDLExpr;
    FIndexExpr: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string;
      AVisibility: TDLVisibility);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
    property TypeName: string read FTypeName write FTypeName;
    property IndexParams: TList<TDLParam> read FIndexParams;
    property ReadName: string read FReadName write FReadName;
    property WriteName: string read FWriteName write FWriteName;
    property StoredName: string read FStoredName write FStoredName;
    property IsDefault: Boolean read FIsDefault write FIsDefault;
    property DefaultValue: TDLExpr read FDefaultValue write FDefaultValue;
    property IndexExpr: TDLExpr read FIndexExpr write FIndexExpr;
  end;

  /// <summary>A record variant part.</summary>
  TDLVariantPart = class(TDLNode)
  private
    FTag: string;
    FTagType: string;
    FLabels: TList<string>;
    FFields: TList<TDLField>;
    FSubVariants: TList<TDLVariantPart>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Tag: string read FTag write FTag;
    property TagType: string read FTagType write FTagType;
    property Labels: TList<string> read FLabels;
    property Fields: TList<TDLField> read FFields;
    property SubVariants: TList<TDLVariantPart> read FSubVariants;
  end;

  /// <summary>Named type reference (optionally generic).</summary>
  TDLNamedTypeRef = class(TDLTypeDef)
  private
    FName: string;
    FTypeArgs: TList<string>;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
    property TypeArgs: TList<string> read FTypeArgs;
  end;

  /// <summary>string / string[n] type.</summary>
  TDLStringTypeDef = class(TDLTypeDef)
  private
    FFixedLength: Integer;
  public
    constructor Create(ASpan: TDLSourceSpan; AFixedLength: Integer);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property FixedLength: Integer read FFixedLength;
  end;

  /// <summary>Subrange type.</summary>
  TDLSubrangeTypeDef = class(TDLTypeDef)
  private
    FLow: string;
    FHigh: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const ALow, AHigh: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Low: string read FLow;
    property High: string read FHigh;
  end;

  /// <summary>Enumeration type.</summary>
  TDLEnumTypeDef = class(TDLTypeDef)
  private
    FMembers: TList<string>;
    FIsPacked: Boolean;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Members: TList<string> read FMembers;
    property IsPacked: Boolean read FIsPacked;
  end;

  /// <summary>set of T.</summary>
  TDLSetTypeDef = class(TDLTypeDef)
  private
    FBaseType: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const ABaseType: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property BaseType: string read FBaseType;
  end;

  /// <summary>^T.</summary>
  TDLPointerTypeDef = class(TDLTypeDef)
  private
    FPointee: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const APointee: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Pointee: string read FPointee;
  end;

  /// <summary>file / file of T.</summary>
  TDLFileTypeDef = class(TDLTypeDef)
  private
    FBaseType: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const ABaseType: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property BaseType: string read FBaseType;
  end;

  /// <summary>Static array type.</summary>
  TDLStaticArrayTypeDef = class(TDLTypeDef)
  private
    FElementType: string;
    FBounds: TList<string>;
  public
    constructor Create(ASpan: TDLSourceSpan; const AElementType: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property ElementType: string read FElementType;
    property Bounds: TList<string> read FBounds;
  end;

  /// <summary>Dynamic array type.</summary>
  TDLDynamicArrayTypeDef = class(TDLTypeDef)
  private
    FElementType: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AElementType: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property ElementType: string read FElementType;
  end;

  /// <summary>Record type (with optional variant part).</summary>
  TDLRecordTypeDef = class(TDLTypeDef)
  private
    FIsPacked: Boolean;
    FMembers: TList<TDLMember>;
    FVariantPart: TDLVariantPart;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property IsPacked: Boolean read FIsPacked;
    property Members: TList<TDLMember> read FMembers;
    property VariantPart: TDLVariantPart read FVariantPart write FVariantPart;
  end;

  /// <summary>Class, helper, interface, object, class-reference type.</summary>
  TDLClassTypeDef = class(TDLTypeDef)
  private
    FKind: string; // 'class', 'class sealed', 'class abstract', 'class helper',
                   // 'interface', 'dispinterface', 'object', 'class of'
    FAncestor: string;
    FHelperFor: string;
    FInterfaces: TList<string>;
    FMembers: TList<TDLMember>;
  public
    constructor Create(ASpan: TDLSourceSpan; const AKind: string;
      const AAncestor: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: string read FKind;
    property Ancestor: string read FAncestor;
    property HelperFor: string read FHelperFor write FHelperFor;
    property Interfaces: TList<string> read FInterfaces;
    property Members: TList<TDLMember> read FMembers;
  end;

  /// <summary>Procedural type.</summary>
  TDLProceduralTypeDef = class(TDLTypeDef)
  private
    FKind: TDLProcKind;
    FIsOfObject: Boolean;
    FIsReferenceTo: Boolean;
    FParams: TList<TDLParam>;
    FReturnType: string;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      AIsOfObject, AIsReferenceTo: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLProcKind read FKind;
    property IsOfObject: Boolean read FIsOfObject;
    property IsReferenceTo: Boolean read FIsReferenceTo;
    property Params: TList<TDLParam> read FParams;
    property ReturnType: string read FReturnType write FReturnType;
  end;

  /// <summary>Generic type (Name&lt;T, U&gt; = ...).</summary>
  TDLGenericTypeDef = class(TDLTypeDef)
  private
    FTypeParams: TList<string>;
    FBaseDef: TDLTypeDef;
  public
    constructor Create(ASpan: TDLSourceSpan; ABaseDef: TDLTypeDef);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property TypeParams: TList<string> read FTypeParams;
    property BaseDef: TDLTypeDef read FBaseDef;
  end;

  /// <summary>Parameter declaration.</summary>
  TDLParam = class(TDLNode)
  private
    FNames: TList<string>;
    FMode: TDLParamMode;
    FTypeName: string;
    FDefault: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AMode: TDLParamMode);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<string> read FNames;
    property Mode: TDLParamMode read FMode;
    property TypeName: string read FTypeName write FTypeName;
    property DefaultValue: TDLExpr read FDefault write FDefault;
  end;

  /// <summary>Type declaration (Name = TypeDef).</summary>
  TDLTypeDecl = class(TDLDeclaration)
  private
    FName: string;
    FTypeDef: TDLTypeDef;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string;
      ATypeDef: TDLTypeDef);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
    property TypeDef: TDLTypeDef read FTypeDef;
  end;

  /// <summary>Constant declaration(s).</summary>
  TDLConstDecl = class(TDLDeclaration)
  private
    FNames: TList<string>;
    FTypeName: string;
    FValue: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<string> read FNames;
    property TypeName: string read FTypeName write FTypeName;
    property Value: TDLExpr read FValue write FValue;
  end;

  /// <summary>Variable declaration(s).</summary>
  TDLVarDecl = class(TDLDeclaration)
  private
    FNames: TList<string>;
    FTypeName: string;
    FInit: TDLExpr;
    FAbsoluteOf: TDLExpr;
    FIsThreadVar: Boolean;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsThreadVar: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<string> read FNames;
    property TypeName: string read FTypeName write FTypeName;
    property Init: TDLExpr read FInit write FInit;
    property AbsoluteOf: TDLExpr read FAbsoluteOf write FAbsoluteOf;
    property IsThreadVar: Boolean read FIsThreadVar;
  end;

  /// <summary>Label declaration.</summary>
  TDLLabelDecl = class(TDLDeclaration)
  private
    FName: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
  end;

  /// <summary>Procedure/function declaration or implementation at module scope.</summary>
  TDLProcDecl = class(TDLDeclaration)
  private
    FKind: TDLProcKind;
    FName: string;
    FIsClass: Boolean;
    FParams: TList<TDLParam>;
    FReturnType: string;
    FBody: TList<TDLStmt>;
    FHasBody: Boolean;
    FDirectives: TList<string>;
    FLocalDeclarations: TList<TDLDeclaration>;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
      const AName: string; AIsClass: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLProcKind read FKind;
    property Name: string read FName;
    property IsClass: Boolean read FIsClass;
    property Params: TList<TDLParam> read FParams;
    property ReturnType: string read FReturnType write FReturnType;
    property Body: TList<TDLStmt> read FBody;
    property HasBody: Boolean read FHasBody write FHasBody;
    property Directives: TList<string> read FDirectives;
    /// <summary>Local declarations (vars/labels/consts/types) of the body.</summary>
    property LocalDeclarations: TList<TDLDeclaration> read FLocalDeclarations;
  end;

  /// <summary>Export item.</summary>
  TDLExportDecl = class(TDLDeclaration)
  private
    FName: string;
    FIndex: string;
    FExportName: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
    property Index: string read FIndex write FIndex;
    property ExportName: string read FExportName write FExportName;
  end;

  // ---------------------------------------------------------------------------
  // Statements
  // ---------------------------------------------------------------------------

  /// <summary>Base class of statements.</summary>
  TDLStmt = class abstract(TDLNode)
  end;

  /// <summary>A block of statements.</summary>
  TDLBlock = class(TDLStmt)
  private
    FStatements: TList<TDLStmt>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Statements: TList<TDLStmt> read FStatements;
  end;

  /// <summary>if statement.</summary>
  TDLIfStmt = class(TDLStmt)
  private
    FCondition: TDLExpr;
    FThenBranch: TDLStmt;
    FElseBranch: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; ACondition: TDLExpr;
      AThenBranch: TDLStmt);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Condition: TDLExpr read FCondition;
    property ThenBranch: TDLStmt read FThenBranch;
    property ElseBranch: TDLStmt read FElseBranch write FElseBranch;
  end;

  /// <summary>One case selector.</summary>
  TDLCaseSelector = class(TDLNode)
  private
    FLabels: TList<TDLExpr>;
    FStatement: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Labels: TList<TDLExpr> read FLabels;
    property Statement: TDLStmt read FStatement write FStatement;
  end;

  /// <summary>case statement.</summary>
  TDLCaseStmt = class(TDLStmt)
  private
    FSubject: TDLExpr;
    FSelectors: TList<TDLCaseSelector>;
    FElseBranch: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; ASubject: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Subject: TDLExpr read FSubject;
    property Selectors: TList<TDLCaseSelector> read FSelectors;
    property ElseBranch: TDLStmt read FElseBranch write FElseBranch;
  end;

  /// <summary>for statement.</summary>
  TDLForStmt = class(TDLStmt)
  private
    FLoopVar: string;
    FIsInline: Boolean;
    FDirection: string; // 'to', 'downto', 'in'
    FStartExpr: TDLExpr;
    FEndExpr: TDLExpr;
    FBody: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; const ALoopVar: string;
      AIsInline: Boolean; const ADirection: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property LoopVar: string read FLoopVar;
    property IsInline: Boolean read FIsInline;
    property Direction: string read FDirection;
    property StartExpr: TDLExpr read FStartExpr write FStartExpr;
    property EndExpr: TDLExpr read FEndExpr write FEndExpr;
    property Body: TDLStmt read FBody write FBody;
  end;

  /// <summary>while statement.</summary>
  TDLWhileStmt = class(TDLStmt)
  private
    FCondition: TDLExpr;
    FBody: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; ACondition: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Condition: TDLExpr read FCondition;
    property Body: TDLStmt read FBody write FBody;
  end;

  /// <summary>repeat statement.</summary>
  TDLRepeatStmt = class(TDLStmt)
  private
    FBody: TDLStmt;
    FCondition: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStmt read FBody write FBody;
    property Condition: TDLExpr read FCondition write FCondition;
  end;

  /// <summary>with statement.</summary>
  TDLWithStmt = class(TDLStmt)
  private
    FExpressions: TList<TDLExpr>;
    FBody: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expressions: TList<TDLExpr> read FExpressions;
    property Body: TDLStmt read FBody write FBody;
  end;

  /// <summary>try statement.</summary>
  TDLTryStmt = class(TDLStmt)
  private
    FBody: TDLStmt;
    FIsExcept: Boolean;
    FHandlers: TList<TDLOnHandler>;
    FElseBranch: TDLStmt;
    FFinallyBody: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; AIsExcept: Boolean);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Body: TDLStmt read FBody write FBody;
    property IsExcept: Boolean read FIsExcept;
    property Handlers: TList<TDLOnHandler> read FHandlers;
    property ElseBranch: TDLStmt read FElseBranch write FElseBranch;
    property FinallyBody: TDLStmt read FFinallyBody write FFinallyBody;
  end;

  /// <summary>on-handler.</summary>
  TDLOnHandler = class(TDLNode)
  private
    FVarName: string;
    FTypeName: string;
    FBody: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property VarName: string read FVarName write FVarName;
    property TypeName: string read FTypeName write FTypeName;
    property Body: TDLStmt read FBody write FBody;
  end;

  /// <summary>raise statement.</summary>
  TDLRaiseStmt = class(TDLStmt)
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

  /// <summary>goto statement.</summary>
  TDLGotoStmt = class(TDLStmt)
  private
    FLabelName: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const ALabelName: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property LabelName: string read FLabelName;
  end;

  /// <summary>Label definition statement.</summary>
  TDLLabelStmt = class(TDLStmt)
  private
    FLabelName: string;
    FStatement: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; const ALabelName: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property LabelName: string read FLabelName;
    property Statement: TDLStmt read FStatement write FStatement;
  end;

  /// <summary>Assignment statement.</summary>
  TDLAssignStmt = class(TDLStmt)
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

  /// <summary>Expression statement.</summary>
  TDLExprStmt = class(TDLStmt)
  private
    FExpression: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AExpression: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expression: TDLExpr read FExpression;
  end;

  /// <summary>asm statement (raw text).</summary>
  TDLAsmStmt = class(TDLStmt)
  private
    FText: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AText: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Text: string read FText;
  end;

  /// <summary>exit [expr] statement.</summary>
  TDLExitStmt = class(TDLStmt)
  private
    FExpression: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AExpression: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Expression: TDLExpr read FExpression;
  end;

  /// <summary>break statement.</summary>
  TDLBreakStmt = class(TDLStmt)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>continue statement.</summary>
  TDLContinueStmt = class(TDLStmt)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>Inline variable declaration statement.</summary>
  TDLVarDeclStmt = class(TDLStmt)
  private
    FNames: TList<string>;
    FTypeName: string;
    FInit: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Names: TList<string> read FNames;
    property TypeName: string read FTypeName write FTypeName;
    property Init: TDLExpr read FInit write FInit;
  end;

  /// <summary>Empty statement.</summary>
  TDLEmptyStmt = class(TDLStmt)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  // ---------------------------------------------------------------------------
  // Expressions
  // ---------------------------------------------------------------------------

  /// <summary>Base class of expressions.</summary>
  TDLExpr = class abstract(TDLNode)
  end;

  /// <summary>Identifier reference.</summary>
  TDLIdentExpr = class(TDLExpr)
  private
    FName: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AName: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Name: string read FName;
  end;

  /// <summary>Numeric literal.</summary>
  TDLNumberExpr = class(TDLExpr)
  private
    FValue: string;
    FIsFloat: Boolean;
  public
    constructor Create(ASpan: TDLSourceSpan; const AValue: string;
      AIsFloat: Boolean);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Value: string read FValue;
    property IsFloat: Boolean read FIsFloat;
  end;

  /// <summary>String literal.</summary>
  TDLStringExpr = class(TDLExpr)
  private
    FValue: string;
  public
    constructor Create(ASpan: TDLSourceSpan; const AValue: string);
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Value: string read FValue;
  end;

  /// <summary>nil literal.</summary>
  TDLNilExpr = class(TDLExpr)
  public
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
  end;

  /// <summary>Set constructor.</summary>
  TDLSetExpr = class(TDLExpr)
  private
    FElements: TList<TDLExpr>;
    FIsRanges: TList<Boolean>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Elements: TList<TDLExpr> read FElements;
    property IsRanges: TList<Boolean> read FIsRanges;
  end;

  /// <summary>Array constructor.</summary>
  TDLArrayExpr = class(TDLExpr)
  private
    FElements: TList<TDLExpr>;
  public
    constructor Create(ASpan: TDLSourceSpan);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Elements: TList<TDLExpr> read FElements;
  end;

  /// <summary>Binary expression.</summary>
  TDLBinaryExpr = class(TDLExpr)
  private
    FOperator: TDLBinOp;
    FOperatorText: string;
    FLeft: TDLExpr;
    FRight: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AOperator: TDLBinOp;
      const AOperatorText: string; ALeft, ARight: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Operator: TDLBinOp read FOperator;
    property OperatorText: string read FOperatorText;
    property Left: TDLExpr read FLeft;
    property Right: TDLExpr read FRight;
  end;

  /// <summary>Unary expression.</summary>
  TDLUnaryExpr = class(TDLExpr)
  private
    FOperator: TDLUnOp;
    FOperatorText: string;
    FOperand: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; AOperator: TDLUnOp;
      const AOperatorText: string; AOperand: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Operator: TDLUnOp read FOperator;
    property OperatorText: string read FOperatorText;
    property Operand: TDLExpr read FOperand;
  end;

  /// <summary>Index expression.</summary>
  TDLIndexExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
    FIndices: TList<TDLExpr>;
  public
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property Indices: TList<TDLExpr> read FIndices;
  end;

  /// <summary>Call expression.</summary>
  TDLCallExpr = class(TDLExpr)
  private
    FCallee: TDLExpr;
    FArgs: TList<TDLExpr>;
  public
    constructor Create(ASpan: TDLSourceSpan; ACallee: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Callee: TDLExpr read FCallee;
    property Args: TList<TDLExpr> read FArgs;
  end;

  /// <summary>Member access.</summary>
  TDLMemberExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
    FMember: string;
  public
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr;
      const AMember: string);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property Member: string read FMember;
  end;

  /// <summary>Generic instantiation.</summary>
  TDLGenericInstExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
    FTypeArgs: TList<string>;
  public
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
    property TypeArgs: TList<string> read FTypeArgs;
  end;

  /// <summary>inherited expression.</summary>
  TDLInheritedExpr = class(TDLExpr)
  private
    FTarget: TDLExpr;
  public
    constructor Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Target: TDLExpr read FTarget;
  end;

  /// <summary>Anonymous method expression.</summary>
  TDLAnonMethodExpr = class(TDLExpr)
  private
    FKind: TDLProcKind;
    FParams: TList<TDLParam>;
    FReturnType: string;
    FBody: TDLStmt;
  public
    constructor Create(ASpan: TDLSourceSpan; AKind: TDLProcKind);
    destructor Destroy; override;
    procedure Dump(ABuilder: TStringBuilder; AIndent: Integer); override;
    property Kind: TDLProcKind read FKind;
    property Params: TList<TDLParam> read FParams;
    property ReturnType: string read FReturnType write FReturnType;
    property Body: TDLStmt read FBody write FBody;
  end;

implementation

const
  CModuleKindText: array[TDLModuleKind] of string = ('program', 'unit',
    'library', 'package');
  CProcKindText: array[TDLProcKind] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator');
  CParamModeText: array[TDLParamMode] of string = ('', 'const', 'var', 'out',
    'const ref', 'var ref');
  CVisibilityText: array[TDLVisibility] of string = ('', 'private',
    'protected', 'public', 'published', 'automated');

/// <summary>Renders an AST expression to compact source-like text.</summary>
function DLExprText(AExpr: TDLExpr): string;
var
  LBinary: TDLBinaryExpr;
  LUnary: TDLUnaryExpr;
  LCall: TDLCallExpr;
  LMember: TDLMemberExpr;
  LIndex: TDLIndexExpr;
  LGeneric: TDLGenericInstExpr;
  i: Integer;
begin
  if AExpr = nil then
    Exit('');
  if AExpr is TDLIdentExpr then
    Result := TDLIdentExpr(AExpr).Name
  else if AExpr is TDLNumberExpr then
    Result := TDLNumberExpr(AExpr).Value
  else if AExpr is TDLStringExpr then
    Result := '''' + StringReplace(TDLStringExpr(AExpr).Value, '''', '''''',
      [rfReplaceAll]) + ''''
  else if AExpr is TDLNilExpr then
    Result := 'nil'
  else if AExpr is TDLBinaryExpr then
  begin
    LBinary := TDLBinaryExpr(AExpr);
    Result := DLExprText(LBinary.Left) + ' ' + LBinary.OperatorText + ' ' +
      DLExprText(LBinary.Right);
  end
  else if AExpr is TDLUnaryExpr then
  begin
    LUnary := TDLUnaryExpr(AExpr);
    Result := LUnary.OperatorText + DLExprText(LUnary.Operand);
  end
  else if AExpr is TDLCallExpr then
  begin
    LCall := TDLCallExpr(AExpr);
    Result := DLExprText(LCall.Callee) + '(';
    for i := 0 to LCall.Args.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      Result := Result + DLExprText(LCall.Args[i]);
    end;
    Result := Result + ')';
  end
  else if AExpr is TDLMemberExpr then
  begin
    LMember := TDLMemberExpr(AExpr);
    Result := DLExprText(LMember.Target) + '.' + LMember.Member;
  end
  else if AExpr is TDLIndexExpr then
  begin
    LIndex := TDLIndexExpr(AExpr);
    Result := DLExprText(LIndex.Target) + '[';
    for i := 0 to LIndex.Indices.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      Result := Result + DLExprText(LIndex.Indices[i]);
    end;
    Result := Result + ']';
  end
  else if AExpr is TDLGenericInstExpr then
  begin
    LGeneric := TDLGenericInstExpr(AExpr);
    Result := DLExprText(LGeneric.Target) + '<' +
      String.Join(', ', LGeneric.TypeArgs.ToArray) + '>';
  end
  else if AExpr is TDLSetExpr then
    Result := '[set]'
  else if AExpr is TDLArrayExpr then
    Result := '[array]'
  else if AExpr is TDLInheritedExpr then
    Result := 'inherited'
  else
    Result := '?';
end;

{ TDLNode }

constructor TDLNode.Create(ASpan: TDLSourceSpan);
begin
  inherited Create;
  FSpan := ASpan;
end;

procedure TDLNode.DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
  const AText: string; const AArgs: array of const);
begin
  TDLDump.Line(ABuilder, AIndent, ClassName + '(' + Format(AText, AArgs) + ')');
end;

procedure TDLNode.DumpHeader(ABuilder: TStringBuilder; AIndent: Integer;
  const AText: string);
begin
  TDLDump.Line(ABuilder, AIndent, ClassName + '(' + AText + ')');
end;

{ TDLUse }

constructor TDLUse.Create(ASpan: TDLSourceSpan; const AName: string);
begin
  inherited Create(ASpan);
  FName := AName;
end;

procedure TDLUse.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  if FInFile = '' then
    DumpHeader(ABuilder, AIndent, 'use %s', [FName])
  else
    DumpHeader(ABuilder, AIndent, 'use %s in %s', [FName, FInFile]);
end;

{ TDLModule }

constructor TDLModule.Create(ASpan: TDLSourceSpan; AKind: TDLModuleKind;
  const AName: string);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FName := AName;
  FUses := TList<TDLUse>.Create;
  FDeclarations := TList<TDLDeclaration>.Create;
  FInitStatements := TList<TDLStmt>.Create;
  FFinalStatements := TList<TDLStmt>.Create;
end;

destructor TDLModule.Destroy;
begin
  FUses.Free;
  FDeclarations.Free;
  FInitStatements.Free;
  FFinalStatements.Free;
  inherited Destroy;
end;

procedure TDLModule.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LUse: TDLUse;
  LDecl: TDLDeclaration;
  LStmt: TDLStmt;
begin
  DumpHeader(ABuilder, AIndent, '%s %s', [CModuleKindText[FKind], FName]);
  for LUse in FUses do
    LUse.Dump(ABuilder, AIndent + 1);
  for LDecl in FDeclarations do
    LDecl.Dump(ABuilder, AIndent + 1);
  if FInitStatements.Count > 0 then
  begin
    TDLDump.Line(ABuilder, AIndent, '  initialization');
    for LStmt in FInitStatements do
      LStmt.Dump(ABuilder, AIndent + 1);
  end;
  if FFinalStatements.Count > 0 then
  begin
    TDLDump.Line(ABuilder, AIndent, '  finalization');
    for LStmt in FFinalStatements do
      LStmt.Dump(ABuilder, AIndent + 1);
  end;
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
begin
  if IsStrict then
    DumpHeader(ABuilder, AIndent, 'strict %s', [CVisibilityText[FKind]])
  else
    DumpHeader(ABuilder, AIndent, '%s', [CVisibilityText[FKind]]);
end;

{ TDLField }

constructor TDLField.Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
  AIsStrict: Boolean);
begin
  inherited Create(ASpan, AVisibility, AIsStrict);
  FNames := TList<string>.Create;
end;

destructor TDLField.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure TDLField.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'field %s : %s',
    [String.Join(', ', FNames.ToArray), FTypeName]);
end;

{ TDLClassVar }

constructor TDLClassVar.Create(ASpan: TDLSourceSpan; AVisibility: TDLVisibility;
  AIsStrict: Boolean);
begin
  inherited Create(ASpan, AVisibility, AIsStrict);
  FFields := TList<TDLField>.Create;
end;

destructor TDLClassVar.Destroy;
begin
  FFields.Free;
  inherited Destroy;
end;

procedure TDLClassVar.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LField: TDLField;
begin
  DumpHeader(ABuilder, AIndent, 'class var');
  for LField in FFields do
    LField.Dump(ABuilder, AIndent + 1);
end;

{ TDLMethod }

constructor TDLMethod.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
  const AName: string; AIsClass: Boolean; AVisibility: TDLVisibility);
begin
  inherited Create(ASpan, AVisibility, False);
  FKind := AKind;
  FName := AName;
  FIsClass := AIsClass;
  FParams := TList<TDLParam>.Create;
  FBody := TList<TDLStmt>.Create;
  FDirectives := TList<string>.Create;
  FLocalDeclarations := TList<TDLDeclaration>.Create;
end;

destructor TDLMethod.Destroy;
begin
  FParams.Free;
  FBody.Free;
  FDirectives.Free;
  FLocalDeclarations.Free;
  inherited Destroy;
end;

procedure TDLMethod.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParam;
  LStmt: TDLStmt;
  LDirective: string;
  LDecl: TDLDeclaration;
begin
  if FIsClass then
    DumpHeader(ABuilder, AIndent, '%s %s (class)', [CProcKindText[FKind], FName])
  else
    DumpHeader(ABuilder, AIndent, '%s %s', [CProcKindText[FKind], FName]);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> '' then
    TDLDump.Line(ABuilder, AIndent, '  : %s', [FReturnType]);
  for LDirective in FDirectives do
    TDLDump.Line(ABuilder, AIndent, '  directive %s', [LDirective]);
  if FLocalDeclarations.Count > 0 then
  begin
    TDLDump.Line(ABuilder, AIndent, '  locals');
    for LDecl in FLocalDeclarations do
      LDecl.Dump(ABuilder, AIndent + 1);
  end;
  if FHasBody then
  begin
    TDLDump.Line(ABuilder, AIndent, '  begin');
    for LStmt in FBody do
      LStmt.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLProperty }

constructor TDLProperty.Create(ASpan: TDLSourceSpan; const AName: string;
  AVisibility: TDLVisibility);
begin
  inherited Create(ASpan, AVisibility, False);
  FName := AName;
  FIndexParams := TList<TDLParam>.Create;
end;

destructor TDLProperty.Destroy;
begin
  FIndexParams.Free;
  FDefaultValue.Free;
  FIndexExpr.Free;
  inherited Destroy;
end;

procedure TDLProperty.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParam;
begin
  DumpHeader(ABuilder, AIndent, 'property %s : %s', [FName, FTypeName]);
  for LParam in FIndexParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReadName <> '' then
    TDLDump.Line(ABuilder, AIndent, '  read %s', [FReadName]);
  if FWriteName <> '' then
    TDLDump.Line(ABuilder, AIndent, '  write %s', [FWriteName]);
  if FIsDefault then
    TDLDump.Line(ABuilder, AIndent, '  default %s', [DLExprText(FDefaultValue)]);
end;

{ TDLVariantPart }

constructor TDLVariantPart.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FLabels := TList<string>.Create;
  FFields := TList<TDLField>.Create;
  FSubVariants := TList<TDLVariantPart>.Create;
end;

destructor TDLVariantPart.Destroy;
begin
  FLabels.Free;
  FFields.Free;
  FSubVariants.Free;
  inherited Destroy;
end;

procedure TDLVariantPart.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LField: TDLField;
  LSub: TDLVariantPart;
begin
  DumpHeader(ABuilder, AIndent, 'case %s : %s', [FTag, FTagType]);
  for LField in FFields do
    LField.Dump(ABuilder, AIndent + 1);
  for LSub in FSubVariants do
    LSub.Dump(ABuilder, AIndent + 1);
end;

{ TDLNamedTypeRef }

constructor TDLNamedTypeRef.Create(ASpan: TDLSourceSpan; const AName: string);
begin
  inherited Create(ASpan);
  FName := AName;
  FTypeArgs := TList<string>.Create;
end;

destructor TDLNamedTypeRef.Destroy;
begin
  FTypeArgs.Free;
  inherited Destroy;
end;

procedure TDLNamedTypeRef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'type ref %s', [FName]);
end;

{ TDLStringTypeDef }

constructor TDLStringTypeDef.Create(ASpan: TDLSourceSpan; AFixedLength: Integer);
begin
  inherited Create(ASpan);
  FFixedLength := AFixedLength;
end;

procedure TDLStringTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  if FFixedLength > 0 then
    DumpHeader(ABuilder, AIndent, 'string[%d]', [FFixedLength])
  else
    DumpHeader(ABuilder, AIndent, 'string');
end;

{ TDLSubrangeTypeDef }

constructor TDLSubrangeTypeDef.Create(ASpan: TDLSourceSpan; const ALow,
  AHigh: string);
begin
  inherited Create(ASpan);
  FLow := ALow;
  FHigh := AHigh;
end;

procedure TDLSubrangeTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'subrange %s..%s', [FLow, FHigh]);
end;

{ TDLEnumTypeDef }

constructor TDLEnumTypeDef.Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
begin
  inherited Create(ASpan);
  FIsPacked := AIsPacked;
  FMembers := TList<string>.Create;
end;

destructor TDLEnumTypeDef.Destroy;
begin
  FMembers.Free;
  inherited Destroy;
end;

procedure TDLEnumTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'enum (%s)', [String.Join(', ', FMembers.ToArray)]);
end;

{ TDLSetTypeDef }

constructor TDLSetTypeDef.Create(ASpan: TDLSourceSpan; const ABaseType: string);
begin
  inherited Create(ASpan);
  FBaseType := ABaseType;
end;

procedure TDLSetTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'set of %s', [FBaseType]);
end;

{ TDLPointerTypeDef }

constructor TDLPointerTypeDef.Create(ASpan: TDLSourceSpan; const APointee: string);
begin
  inherited Create(ASpan);
  FPointee := APointee;
end;

procedure TDLPointerTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, '^%s', [FPointee]);
end;

{ TDLFileTypeDef }

constructor TDLFileTypeDef.Create(ASpan: TDLSourceSpan; const ABaseType: string);
begin
  inherited Create(ASpan);
  FBaseType := ABaseType;
end;

procedure TDLFileTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  if FBaseType = '' then
    DumpHeader(ABuilder, AIndent, 'file')
  else
    DumpHeader(ABuilder, AIndent, 'file of %s', [FBaseType]);
end;

{ TDLStaticArrayTypeDef }

constructor TDLStaticArrayTypeDef.Create(ASpan: TDLSourceSpan;
  const AElementType: string);
begin
  inherited Create(ASpan);
  FElementType := AElementType;
  FBounds := TList<string>.Create;
end;

destructor TDLStaticArrayTypeDef.Destroy;
begin
  FBounds.Free;
  inherited Destroy;
end;

procedure TDLStaticArrayTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'array[%s] of %s',
    [String.Join(', ', FBounds.ToArray), FElementType]);
end;

{ TDLDynamicArrayTypeDef }

constructor TDLDynamicArrayTypeDef.Create(ASpan: TDLSourceSpan;
  const AElementType: string);
begin
  inherited Create(ASpan);
  FElementType := AElementType;
end;

procedure TDLDynamicArrayTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'array of %s', [FElementType]);
end;

{ TDLRecordTypeDef }

constructor TDLRecordTypeDef.Create(ASpan: TDLSourceSpan; AIsPacked: Boolean);
begin
  inherited Create(ASpan);
  FIsPacked := AIsPacked;
  FMembers := TList<TDLMember>.Create;
end;

destructor TDLRecordTypeDef.Destroy;
begin
  FMembers.Free;
  FVariantPart.Free;
  inherited Destroy;
end;

procedure TDLRecordTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LMember: TDLMember;
begin
  DumpHeader(ABuilder, AIndent, 'record');
  for LMember in FMembers do
    LMember.Dump(ABuilder, AIndent + 1);
  if FVariantPart <> nil then
    FVariantPart.Dump(ABuilder, AIndent + 1);
end;

{ TDLClassTypeDef }

constructor TDLClassTypeDef.Create(ASpan: TDLSourceSpan; const AKind: string;
  const AAncestor: string);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FAncestor := AAncestor;
  FInterfaces := TList<string>.Create;
  FMembers := TList<TDLMember>.Create;
end;

destructor TDLClassTypeDef.Destroy;
begin
  FInterfaces.Free;
  FMembers.Free;
  inherited Destroy;
end;

procedure TDLClassTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LMember: TDLMember;
begin
  DumpHeader(ABuilder, AIndent, '%s%s', [FKind,
    IfThen(FAncestor <> '', ' (' + FAncestor + ')', '')]);
  if FHelperFor <> '' then
    TDLDump.Line(ABuilder, AIndent, '  for %s', [FHelperFor]);
  for LMember in FMembers do
    LMember.Dump(ABuilder, AIndent + 1);
end;

{ TDLProceduralTypeDef }

constructor TDLProceduralTypeDef.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
  AIsOfObject, AIsReferenceTo: Boolean);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FIsOfObject := AIsOfObject;
  FIsReferenceTo := AIsReferenceTo;
  FParams := TList<TDLParam>.Create;
end;

destructor TDLProceduralTypeDef.Destroy;
begin
  FParams.Free;
  inherited Destroy;
end;

procedure TDLProceduralTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParam;
begin
  DumpHeader(ABuilder, AIndent, 'proc type %s%s', [CProcKindText[FKind],
    IfThen(FIsOfObject, ' of object', IfThen(FIsReferenceTo, ' reference to', ''))]);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> '' then
    TDLDump.Line(ABuilder, AIndent, '  : %s', [FReturnType]);
end;

{ TDLGenericTypeDef }

constructor TDLGenericTypeDef.Create(ASpan: TDLSourceSpan; ABaseDef: TDLTypeDef);
begin
  inherited Create(ASpan);
  FBaseDef := ABaseDef;
  FTypeParams := TList<string>.Create;
end;

destructor TDLGenericTypeDef.Destroy;
begin
  FTypeParams.Free;
  FBaseDef.Free;
  inherited Destroy;
end;

procedure TDLGenericTypeDef.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'generic <%s>',
    [String.Join(', ', FTypeParams.ToArray)]);
  FBaseDef.Dump(ABuilder, AIndent + 1);
end;

{ TDLParam }

constructor TDLParam.Create(ASpan: TDLSourceSpan; AMode: TDLParamMode);
begin
  inherited Create(ASpan);
  FMode := AMode;
  FNames := TList<string>.Create;
end;

destructor TDLParam.Destroy;
begin
  FNames.Free;
  FDefault.Free;
  inherited Destroy;
end;

procedure TDLParam.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, '%s %s : %s%s',
    [CParamModeText[FMode], String.Join(', ', FNames.ToArray), FTypeName,
     IfThen(FDefault <> nil, ' = ' + DLExprText(FDefault), '')]);
end;

{ TDLTypeDecl }

constructor TDLTypeDecl.Create(ASpan: TDLSourceSpan; const AName: string;
  ATypeDef: TDLTypeDef);
begin
  inherited Create(ASpan);
  FName := AName;
  FTypeDef := ATypeDef;
end;

destructor TDLTypeDecl.Destroy;
begin
  FTypeDef.Free;
  inherited Destroy;
end;

procedure TDLTypeDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'type %s =', [FName]);
  FTypeDef.Dump(ABuilder, AIndent + 1);
end;

{ TDLConstDecl }

constructor TDLConstDecl.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FNames := TList<string>.Create;
end;

destructor TDLConstDecl.Destroy;
begin
  FNames.Free;
  FValue.Free;
  inherited Destroy;
end;

procedure TDLConstDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'const %s%s%s',
    [String.Join(', ', FNames.ToArray),
     IfThen(FTypeName <> '', ' : ' + FTypeName, ''),
     IfThen(FValue <> nil, ' = ' + DLExprText(FValue), '')]);
end;

{ TDLVarDecl }

constructor TDLVarDecl.Create(ASpan: TDLSourceSpan; AIsThreadVar: Boolean);
begin
  inherited Create(ASpan);
  FIsThreadVar := AIsThreadVar;
  FNames := TList<string>.Create;
end;

destructor TDLVarDecl.Destroy;
begin
  FNames.Free;
  FInit.Free;
  FAbsoluteOf.Free;
  inherited Destroy;
end;

procedure TDLVarDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, '%s %s : %s%s%s',
    [IfThen(FIsThreadVar, 'threadvar', 'var'),
     String.Join(', ', FNames.ToArray), FTypeName,
     IfThen(FAbsoluteOf <> nil, ' absolute ' + DLExprText(FAbsoluteOf), ''),
     IfThen(FInit <> nil, ' = ' + DLExprText(FInit), '')]);
end;

{ TDLLabelDecl }

constructor TDLLabelDecl.Create(ASpan: TDLSourceSpan; const AName: string);
begin
  inherited Create(ASpan);
  FName := AName;
end;

procedure TDLLabelDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'label %s', [FName]);
end;

{ TDLProcDecl }

constructor TDLProcDecl.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind;
  const AName: string; AIsClass: Boolean);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FName := AName;
  FIsClass := AIsClass;
  FParams := TList<TDLParam>.Create;
  FBody := TList<TDLStmt>.Create;
  FDirectives := TList<string>.Create;
  FLocalDeclarations := TList<TDLDeclaration>.Create;
end;

destructor TDLProcDecl.Destroy;
begin
  FParams.Free;
  FBody.Free;
  FDirectives.Free;
  FLocalDeclarations.Free;
  inherited Destroy;
end;

procedure TDLProcDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParam;
  LStmt: TDLStmt;
  LDirective: string;
  LDecl: TDLDeclaration;
begin
  DumpHeader(ABuilder, AIndent, '%s %s', [CProcKindText[FKind], FName]);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> '' then
    TDLDump.Line(ABuilder, AIndent, '  : %s', [FReturnType]);
  for LDirective in FDirectives do
    TDLDump.Line(ABuilder, AIndent, '  directive %s', [LDirective]);
  if FLocalDeclarations.Count > 0 then
  begin
    TDLDump.Line(ABuilder, AIndent, '  locals');
    for LDecl in FLocalDeclarations do
      LDecl.Dump(ABuilder, AIndent + 1);
  end;
  if FHasBody then
  begin
    TDLDump.Line(ABuilder, AIndent, '  begin');
    for LStmt in FBody do
      LStmt.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLExportDecl }

constructor TDLExportDecl.Create(ASpan: TDLSourceSpan; const AName: string);
begin
  inherited Create(ASpan);
  FName := AName;
end;

procedure TDLExportDecl.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'export %s%s%s', [FName,
    IfThen(FIndex <> '', ' index ' + FIndex, ''),
    IfThen(FExportName <> '', ' name ' + FExportName, '')]);
end;

{ TDLBlock }

constructor TDLBlock.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FStatements := TList<TDLStmt>.Create;
end;

destructor TDLBlock.Destroy;
begin
  FStatements.Free;
  inherited Destroy;
end;

procedure TDLBlock.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LStmt: TDLStmt;
begin
  DumpHeader(ABuilder, AIndent, 'begin');
  for LStmt in FStatements do
    LStmt.Dump(ABuilder, AIndent + 1);
  DumpHeader(ABuilder, AIndent, 'end');
end;

{ TDLIfStmt }

constructor TDLIfStmt.Create(ASpan: TDLSourceSpan; ACondition: TDLExpr;
  AThenBranch: TDLStmt);
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
  for LSelector in FSelectors do
    LSelector.Dump(ABuilder, AIndent + 1);
  if FElseBranch <> nil then
  begin
    TDLDump.Line(ABuilder, AIndent, '  else');
    FElseBranch.Dump(ABuilder, AIndent + 1);
  end;
end;

{ TDLForStmt }

constructor TDLForStmt.Create(ASpan: TDLSourceSpan; const ALoopVar: string;
  AIsInline: Boolean; const ADirection: string);
begin
  inherited Create(ASpan);
  FLoopVar := ALoopVar;
  FIsInline := AIsInline;
  FDirection := ADirection;
end;

destructor TDLForStmt.Destroy;
begin
  FStartExpr.Free;
  FEndExpr.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLForStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'for %s%s %s', [FLoopVar,
    IfThen(FIsInline, ' (inline)', ''), FDirection]);
  if FStartExpr <> nil then
    FStartExpr.Dump(ABuilder, AIndent + 1);
  if FEndExpr <> nil then
    FEndExpr.Dump(ABuilder, AIndent + 1);
  if FBody <> nil then
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
  FHandlers := TList<TDLOnHandler>.Create;
end;

destructor TDLTryStmt.Destroy;
begin
  FBody.Free;
  FHandlers.Free;
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
    for LHandler in FHandlers do
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
  FBody.Free;
  inherited Destroy;
end;

procedure TDLOnHandler.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'on %s: %s', [FVarName, FTypeName]);
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

constructor TDLGotoStmt.Create(ASpan: TDLSourceSpan; const ALabelName: string);
begin
  inherited Create(ASpan);
  FLabelName := ALabelName;
end;

procedure TDLGotoStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'goto %s', [FLabelName]);
end;

{ TDLLabelStmt }

constructor TDLLabelStmt.Create(ASpan: TDLSourceSpan; const ALabelName: string);
begin
  inherited Create(ASpan);
  FLabelName := ALabelName;
end;

destructor TDLLabelStmt.Destroy;
begin
  FStatement.Free;
  inherited Destroy;
end;

procedure TDLLabelStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'label %s', [FLabelName]);
  if FStatement <> nil then
    FStatement.Dump(ABuilder, AIndent + 1);
end;

{ TDLAssignStmt }

constructor TDLAssignStmt.Create(ASpan: TDLSourceSpan; ATarget, AValue: TDLExpr);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FValue := AValue;
end;

destructor TDLAssignStmt.Destroy;
begin
  FTarget.Free;
  FValue.Free;
  inherited Destroy;
end;

procedure TDLAssignStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
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

constructor TDLVarDeclStmt.Create(ASpan: TDLSourceSpan);
begin
  inherited Create(ASpan);
  FNames := TList<string>.Create;
end;

destructor TDLVarDeclStmt.Destroy;
begin
  FNames.Free;
  FInit.Free;
  inherited Destroy;
end;

procedure TDLVarDeclStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'var %s : %s = %s',
    [String.Join(', ', FNames.ToArray), FTypeName, DLExprText(FInit)]);
end;

{ TDLEmptyStmt }

procedure TDLEmptyStmt.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'empty');
end;

{ TDLIdentExpr }

constructor TDLIdentExpr.Create(ASpan: TDLSourceSpan; const AName: string);
begin
  inherited Create(ASpan);
  FName := AName;
end;

procedure TDLIdentExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'id %s', [FName]);
end;

{ TDLNumberExpr }

constructor TDLNumberExpr.Create(ASpan: TDLSourceSpan; const AValue: string;
  AIsFloat: Boolean);
begin
  inherited Create(ASpan);
  FValue := AValue;
  FIsFloat := AIsFloat;
end;

procedure TDLNumberExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'num %s', [FValue]);
end;

{ TDLStringExpr }

constructor TDLStringExpr.Create(ASpan: TDLSourceSpan; const AValue: string);
begin
  inherited Create(ASpan);
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

constructor TDLBinaryExpr.Create(ASpan: TDLSourceSpan; AOperator: TDLBinOp;
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

constructor TDLUnaryExpr.Create(ASpan: TDLSourceSpan; AOperator: TDLUnOp;
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
  const AMember: string);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FMember := AMember;
end;

destructor TDLMemberExpr.Destroy;
begin
  FTarget.Free;
  inherited Destroy;
end;

procedure TDLMemberExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'member .%s', [FMember]);
  FTarget.Dump(ABuilder, AIndent + 1);
end;

{ TDLGenericInstExpr }

constructor TDLGenericInstExpr.Create(ASpan: TDLSourceSpan; ATarget: TDLExpr);
begin
  inherited Create(ASpan);
  FTarget := ATarget;
  FTypeArgs := TList<string>.Create;
end;

destructor TDLGenericInstExpr.Destroy;
begin
  FTarget.Free;
  FTypeArgs.Free;
  inherited Destroy;
end;

procedure TDLGenericInstExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
begin
  DumpHeader(ABuilder, AIndent, 'generic <%s>',
    [String.Join(', ', FTypeArgs.ToArray)]);
  FTarget.Dump(ABuilder, AIndent + 1);
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

{ TDLAnonMethodExpr }

constructor TDLAnonMethodExpr.Create(ASpan: TDLSourceSpan; AKind: TDLProcKind);
begin
  inherited Create(ASpan);
  FKind := AKind;
  FParams := TList<TDLParam>.Create;
end;

destructor TDLAnonMethodExpr.Destroy;
begin
  FParams.Free;
  FBody.Free;
  inherited Destroy;
end;

procedure TDLAnonMethodExpr.Dump(ABuilder: TStringBuilder; AIndent: Integer);
var
  LParam: TDLParam;
begin
  DumpHeader(ABuilder, AIndent, 'anon %s', [CProcKindText[FKind]]);
  for LParam in FParams do
    LParam.Dump(ABuilder, AIndent + 1);
  if FReturnType <> '' then
    TDLDump.Line(ABuilder, AIndent, '  : %s', [FReturnType]);
  if FBody <> nil then
    FBody.Dump(ABuilder, AIndent + 1);
end;

end.
