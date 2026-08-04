/// <summary>
///   DX.Delphi.AstBuilder — CST to AST lowering pass.
/// </summary>
/// <remarks>
///   Walks a DX.Delphi.CST.TDLCompilationUnit (CST) and produces a TDLModule (AST). The
///   lowering is structural: trivia, tokens and concrete layout are dropped,
///   identifiers become plain strings, and declarations/statements/expressions
///   are mapped to their abstract counterparts.
///
///   While lowering, a flat symbol table is populated with the declared
///   names (types, consts, vars, labels, methods, fields, properties).
///
///   Type disambiguation note: both DX.Delphi.CST and DX.Delphi.AST define
///   classes named e.g. DX.Delphi.CST.TDLExpr. All references to AST classes are written
///   with the explicit DX.Delphi.AST. unit prefix; unqualified names resolve to the CST
///   unit (listed first in the uses clause).
///
///   Known simplifications:
///     - Expressions stored as string fields (const values, initializers,
///       property defaults) are rendered to compact source-like text.
///     - 'resourcestring' declarations become const declarations.
///     - Generic type declaration parameters are not yet carried over.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit DX.Delphi.AstBuilder;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Delphi.Core,
  DX.Delphi.CST,
  DX.Delphi.AST;

type
  /// <summary>Builds an abstract syntax tree from a concrete syntax tree.</summary>
  TDLDelphiAstBuilder = class
  private
    FDiagnostics: TDLDiagnostics;
    FSymbols: TDLSymbolTable;
    function RenderExpr(AExpr: DX.Delphi.CST.TDLExpr): string;
    function RenderTypeName(ATypeExpr: DX.Delphi.CST.TDLTypeExpr): string;
    function BuildTypeDef(ATypeExpr: DX.Delphi.CST.TDLTypeExpr): DX.Delphi.AST.TDLTypeDef;
    function BuildParams(AParams: TList<DX.Delphi.CST.TDLParameter>): TList<DX.Delphi.AST.TDLParam>;
    function BuildStatements(AStmts: TList<DX.Delphi.CST.TDLStatement>): TList<DX.Delphi.AST.TDLStmt>;
    function BuildStatement(AStmt: DX.Delphi.CST.TDLStatement): DX.Delphi.AST.TDLStmt;
    function BuildExpression(AExpr: DX.Delphi.CST.TDLExpr): DX.Delphi.AST.TDLExpr;
    function BuildCaseSelector(ASelector: DX.Delphi.CST.TDLCaseSelector): DX.Delphi.AST.TDLCaseSelector;
    function BuildOnHandler(AHandler: DX.Delphi.CST.TDLOnHandler): DX.Delphi.AST.TDLOnHandler;
    procedure BuildMembers(ACSTMembers: TList<DX.Delphi.CST.TDLMember>;
      AASTMembers: TList<DX.Delphi.AST.TDLMember>);
    function BuildVariantPart(ACSTPart: DX.Delphi.CST.TDLVariantSection): DX.Delphi.AST.TDLVariantPart;
  public
    constructor Create(ADiagnostics: TDLDiagnostics);
    destructor Destroy; override;
    /// <summary>Lowers the CST compilation unit into an AST module.</summary>
    function Build(ACST: DX.Delphi.CST.TDLCompilationUnit): DX.Delphi.AST.TDLModule;
    property Symbols: TDLSymbolTable read FSymbols;
    property Diagnostics: TDLDiagnostics read FDiagnostics;
  end;

implementation

uses
  System.StrUtils;

const
  CProcKindMap: array[DX.Delphi.CST.TDLProcKind] of DX.Delphi.AST.TDLProcKind = (
    DX.Delphi.AST.pkProcedure, DX.Delphi.AST.pkFunction, DX.Delphi.AST.pkConstructor, DX.Delphi.AST.pkDestructor,
    DX.Delphi.AST.pkOperator);

{ TDLDelphiAstBuilder }

constructor TDLDelphiAstBuilder.Create(ADiagnostics: TDLDiagnostics);
begin
  inherited Create;
  FDiagnostics := ADiagnostics;
  FSymbols := TDLSymbolTable.Create;
end;

destructor TDLDelphiAstBuilder.Destroy;
begin
  FSymbols.Free;
  inherited Destroy;
end;

function TDLDelphiAstBuilder.RenderExpr(AExpr: DX.Delphi.CST.TDLExpr): string;
var
  LBinary: DX.Delphi.CST.TDLBinaryExpr;
  LUnary: DX.Delphi.CST.TDLUnaryExpr;
  LCall: DX.Delphi.CST.TDLCallExpr;
  LMember: DX.Delphi.CST.TDLMemberExpr;
  LIndex: DX.Delphi.CST.TDLIndexExpr;
  LGeneric: DX.Delphi.CST.TDLGenericInstantiationExpr;
  LIdent: DX.Delphi.CST.TDLIdentifierExpr;
  LNumber: DX.Delphi.CST.TDLNumberExpr;
  LString: DX.Delphi.CST.TDLStringExpr;
  LSet: DX.Delphi.CST.TDLSetExpr;
  LArray: DX.Delphi.CST.TDLArrayExpr;
  LInherited: DX.Delphi.CST.TDLInheritedExpr;
  i: Integer;
begin
  if AExpr is DX.Delphi.CST.TDLIdentifierExpr then
  begin
    LIdent := DX.Delphi.CST.TDLIdentifierExpr(AExpr);
    Result := LIdent.Name.Name;
  end
  else if AExpr is DX.Delphi.CST.TDLNumberExpr then
  begin
    LNumber := DX.Delphi.CST.TDLNumberExpr(AExpr);
    Result := LNumber.Token.Text;
  end
  else if AExpr is DX.Delphi.CST.TDLStringExpr then
  begin
    LString := DX.Delphi.CST.TDLStringExpr(AExpr);
    Result := StringReplace(LString.Value, '''', '''''', [rfReplaceAll]);
    Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
    Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
    Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
    Result := '''' + Result + '''';
  end
  else if AExpr is DX.Delphi.CST.TDLNilExpr then
    Result := 'nil'
  else if AExpr is DX.Delphi.CST.TDLBinaryExpr then
  begin
    LBinary := DX.Delphi.CST.TDLBinaryExpr(AExpr);
    Result := RenderExpr(LBinary.Left) + ' ' + LBinary.OperatorText + ' ' +
      RenderExpr(LBinary.Right);
  end
  else if AExpr is DX.Delphi.CST.TDLUnaryExpr then
  begin
    LUnary := DX.Delphi.CST.TDLUnaryExpr(AExpr);
    Result := LUnary.OperatorText + RenderExpr(LUnary.Operand);
  end
  else if AExpr is DX.Delphi.CST.TDLCallExpr then
  begin
    LCall := DX.Delphi.CST.TDLCallExpr(AExpr);
    Result := RenderExpr(LCall.Callee) + '(';
    for i := 0 to LCall.Args.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      Result := Result + RenderExpr(LCall.Args[i]);
    end;
    Result := Result + ')';
  end
  else if AExpr is DX.Delphi.CST.TDLMemberExpr then
  begin
    LMember := DX.Delphi.CST.TDLMemberExpr(AExpr);
    Result := RenderExpr(LMember.Target) + '.' + LMember.Member.Name;
  end
  else if AExpr is DX.Delphi.CST.TDLIndexExpr then
  begin
    LIndex := DX.Delphi.CST.TDLIndexExpr(AExpr);
    Result := RenderExpr(LIndex.Target) + '[';
    for i := 0 to LIndex.Indices.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      Result := Result + RenderExpr(LIndex.Indices[i]);
    end;
    Result := Result + ']';
  end
  else if AExpr is DX.Delphi.CST.TDLGenericInstantiationExpr then
  begin
    LGeneric := DX.Delphi.CST.TDLGenericInstantiationExpr(AExpr);
    Result := RenderExpr(LGeneric.Target) + '<';
    for i := 0 to LGeneric.TypeArgs.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      if LGeneric.TypeArgs[i].TypeExpr is DX.Delphi.CST.TDLNamedType then
        Result := Result + DX.Delphi.CST.TDLNamedType(LGeneric.TypeArgs[i].TypeExpr).Name.Name
      else
        Result := Result + '?';
    end;
    Result := Result + '>';
  end
  else if AExpr is DX.Delphi.CST.TDLSetExpr then
  begin
    LSet := DX.Delphi.CST.TDLSetExpr(AExpr);
    Result := '[';
    for i := 0 to LSet.Elements.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      Result := Result + RenderExpr(LSet.Elements[i]);
    end;
    Result := Result + ']';
  end
  else if AExpr is DX.Delphi.CST.TDLArrayExpr then
  begin
    LArray := DX.Delphi.CST.TDLArrayExpr(AExpr);
    Result := '[';
    for i := 0 to LArray.Elements.Count - 1 do
    begin
      if i > 0 then
        Result := Result + ', ';
      Result := Result + RenderExpr(LArray.Elements[i]);
    end;
    Result := Result + ']';
  end
  else if AExpr is DX.Delphi.CST.TDLInheritedExpr then
  begin
    LInherited := DX.Delphi.CST.TDLInheritedExpr(AExpr);
    if LInherited.Target <> nil then
      Result := 'inherited ' + RenderExpr(LInherited.Target)
    else
      Result := 'inherited';
  end
  else if AExpr is DX.Delphi.CST.TDLAnonymousMethodExpr then
    Result := '<anonymous method>'
  else
    Result := '?';
end;

function TDLDelphiAstBuilder.RenderTypeName(ATypeExpr: DX.Delphi.CST.TDLTypeExpr): string;
var
  LNamed: DX.Delphi.CST.TDLNamedType;
  LArg: DX.Delphi.CST.TDLTypeArg;
  i: Integer;
begin
  if ATypeExpr = nil then
    Exit('');
  if ATypeExpr is DX.Delphi.CST.TDLNamedType then
  begin
    LNamed := DX.Delphi.CST.TDLNamedType(ATypeExpr);
    Result := LNamed.Name.Name;
    if LNamed.TypeArgs.Count > 0 then
    begin
      Result := Result + '<';
      for i := 0 to LNamed.TypeArgs.Count - 1 do
      begin
        if i > 0 then
          Result := Result + ', ';
        LArg := LNamed.TypeArgs[i];
        Result := Result + RenderTypeName(LArg.TypeExpr);
      end;
      Result := Result + '>';
    end;
  end
  else if ATypeExpr is DX.Delphi.CST.TDLStringType then
    Result := 'string'
  else if ATypeExpr is DX.Delphi.CST.TDLDynamicArrayType then
    Result := 'array of ' + RenderTypeName(
      DX.Delphi.CST.TDLDynamicArrayType(ATypeExpr).ElementType)
  else if ATypeExpr is DX.Delphi.CST.TDLPointerType then
    Result := '^' + RenderTypeName(DX.Delphi.CST.TDLPointerType(ATypeExpr).Pointee)
  else
    Result := '<type>';
end;

function TDLDelphiAstBuilder.BuildTypeDef(ATypeExpr: DX.Delphi.CST.TDLTypeExpr): DX.Delphi.AST.TDLTypeDef;
var
  LNamed: DX.Delphi.CST.TDLNamedType;
  LPointer: DX.Delphi.CST.TDLPointerType;
  LSet: DX.Delphi.CST.TDLSetType;
  LSubrange: DX.Delphi.CST.TDLSubrangeType;
  LStringType: DX.Delphi.CST.TDLStringType;
  LFileType: DX.Delphi.CST.TDLFileType;
  LStatic: DX.Delphi.CST.TDLStaticArrayType;
  LDynamic: DX.Delphi.CST.TDLDynamicArrayType;
  LEnum: DX.Delphi.CST.TDLEnumType;
  LRecord: DX.Delphi.CST.TDLRecordType;
  LClass: DX.Delphi.CST.TDLClassType;
  LProc: DX.Delphi.CST.TDLProceduralType;
  LDef: DX.Delphi.AST.TDLTypeDef;
  LMember: DX.Delphi.CST.TDLEnumMember;
  LArg: DX.Delphi.CST.TDLTypeArg;
  LBound: DX.Delphi.CST.TDLArrayBound;
  LName: string;
begin
  if ATypeExpr is DX.Delphi.CST.TDLNamedType then
  begin
    LNamed := DX.Delphi.CST.TDLNamedType(ATypeExpr);
    LDef := DX.Delphi.AST.TDLNamedTypeRef.Create(ATypeExpr.Span, LNamed.Name.Name);
    for LArg in LNamed.TypeArgs do
      if LArg.TypeExpr is DX.Delphi.CST.TDLNamedType then
        DX.Delphi.AST.TDLNamedTypeRef(LDef).TypeArgs.Add(
          DX.Delphi.CST.TDLNamedType(LArg.TypeExpr).Name.Name);
    Result := LDef;
  end
  else if ATypeExpr is DX.Delphi.CST.TDLPointerType then
  begin
    LPointer := DX.Delphi.CST.TDLPointerType(ATypeExpr);
    Result := DX.Delphi.AST.TDLPointerTypeDef.Create(ATypeExpr.Span,
      RenderTypeName(LPointer.Pointee));
  end
  else if ATypeExpr is DX.Delphi.CST.TDLSetType then
  begin
    LSet := DX.Delphi.CST.TDLSetType(ATypeExpr);
    Result := DX.Delphi.AST.TDLSetTypeDef.Create(ATypeExpr.Span,
      RenderTypeName(LSet.BaseType));
  end
  else if ATypeExpr is DX.Delphi.CST.TDLSubrangeType then
  begin
    LSubrange := DX.Delphi.CST.TDLSubrangeType(ATypeExpr);
    Result := DX.Delphi.AST.TDLSubrangeTypeDef.Create(ATypeExpr.Span,
      RenderExpr(LSubrange.Low), RenderExpr(LSubrange.High));
  end
  else if ATypeExpr is DX.Delphi.CST.TDLStringType then
  begin
    LStringType := DX.Delphi.CST.TDLStringType(ATypeExpr);
    if LStringType.Length <> nil then
      Result := DX.Delphi.AST.TDLStringTypeDef.Create(ATypeExpr.Span,
        StrToIntDef(RenderExpr(LStringType.Length), 0))
    else
      Result := DX.Delphi.AST.TDLStringTypeDef.Create(ATypeExpr.Span, 0);
  end
  else if ATypeExpr is DX.Delphi.CST.TDLFileType then
  begin
    LFileType := DX.Delphi.CST.TDLFileType(ATypeExpr);
    if LFileType.BaseType <> nil then
      Result := DX.Delphi.AST.TDLFileTypeDef.Create(ATypeExpr.Span,
        RenderTypeName(LFileType.BaseType))
    else
      Result := DX.Delphi.AST.TDLFileTypeDef.Create(ATypeExpr.Span, '');
  end
  else if ATypeExpr is DX.Delphi.CST.TDLStaticArrayType then
  begin
    LStatic := DX.Delphi.CST.TDLStaticArrayType(ATypeExpr);
    LDef := DX.Delphi.AST.TDLStaticArrayTypeDef.Create(ATypeExpr.Span,
      RenderTypeName(LStatic.ElementType));
    for LBound in LStatic.Bounds do
    begin
      if LBound.Expr <> nil then
        DX.Delphi.AST.TDLStaticArrayTypeDef(LDef).Bounds.Add(RenderExpr(LBound.Expr))
      else if LBound.TypeExpr <> nil then
        DX.Delphi.AST.TDLStaticArrayTypeDef(LDef).Bounds.Add(
          RenderTypeName(LBound.TypeExpr));
    end;
    Result := LDef;
  end
  else if ATypeExpr is DX.Delphi.CST.TDLDynamicArrayType then
  begin
    LDynamic := DX.Delphi.CST.TDLDynamicArrayType(ATypeExpr);
    Result := DX.Delphi.AST.TDLDynamicArrayTypeDef.Create(ATypeExpr.Span,
      RenderTypeName(LDynamic.ElementType));
  end
  else if ATypeExpr is DX.Delphi.CST.TDLEnumType then
  begin
    LEnum := DX.Delphi.CST.TDLEnumType(ATypeExpr);
    LDef := DX.Delphi.AST.TDLEnumTypeDef.Create(ATypeExpr.Span, LEnum.IsPacked);
    for LMember in LEnum.Members do
    begin
      DX.Delphi.AST.TDLEnumTypeDef(LDef).Members.Add(LMember.Name.Name);
      FSymbols.Add(TDLSymbol.Create(LMember.Name.Name, skEnumMember,
        LMember.Name.Span));
    end;
    Result := LDef;
  end
  else if ATypeExpr is DX.Delphi.CST.TDLRecordType then
  begin
    LRecord := DX.Delphi.CST.TDLRecordType(ATypeExpr);
    LDef := DX.Delphi.AST.TDLRecordTypeDef.Create(ATypeExpr.Span, LRecord.IsPacked);
    BuildMembers(LRecord.Members, DX.Delphi.AST.TDLRecordTypeDef(LDef).Members);
    if LRecord.VariantPart <> nil then
      DX.Delphi.AST.TDLRecordTypeDef(LDef).VariantPart :=
        BuildVariantPart(LRecord.VariantPart);
    Result := LDef;
  end
  else if ATypeExpr is DX.Delphi.CST.TDLClassType then
  begin
    LClass := DX.Delphi.CST.TDLClassType(ATypeExpr);
    LName := 'class';
    if LClass.IsSealed then
      LName := LName + ' sealed';
    if LClass.IsAbstract then
      LName := LName + ' abstract';
    if LClass.IsHelper then
      LName := 'class helper';
    if LClass.IsClassRef then
      LName := 'class of';
    if LClass.IsInterface then
      LName := IfThen(LClass.IsDispInterface, 'dispinterface', 'interface');
    if LClass.IsObject then
      LName := 'object';
    LDef := DX.Delphi.AST.TDLClassTypeDef.Create(ATypeExpr.Span, LName,
      IfThen(LClass.BaseType <> nil, RenderTypeName(LClass.BaseType), ''));
    if LClass.HelperFor <> nil then
      DX.Delphi.AST.TDLClassTypeDef(LDef).HelperFor :=
        RenderTypeName(LClass.HelperFor);
    BuildMembers(LClass.Members, DX.Delphi.AST.TDLClassTypeDef(LDef).Members);
    Result := LDef;
  end
  else if ATypeExpr is DX.Delphi.CST.TDLProceduralType then
  begin
    LProc := DX.Delphi.CST.TDLProceduralType(ATypeExpr);
    LDef := DX.Delphi.AST.TDLProceduralTypeDef.Create(ATypeExpr.Span,
      CProcKindMap[LProc.Kind], LProc.IsOfObject, LProc.IsReferenceTo);
    DX.Delphi.AST.TDLProceduralTypeDef(LDef).Params.AddRange(
      BuildParams(LProc.Params));
    if LProc.ReturnType <> nil then
      DX.Delphi.AST.TDLProceduralTypeDef(LDef).ReturnType :=
        RenderTypeName(LProc.ReturnType);
    Result := LDef;
  end
  else
    Result := DX.Delphi.AST.TDLNamedTypeRef.Create(ATypeExpr.Span, '?');
end;

function TDLDelphiAstBuilder.BuildParams(
  AParams: TList<DX.Delphi.CST.TDLParameter>): TList<DX.Delphi.AST.TDLParam>;
var
  LParam: DX.Delphi.CST.TDLParameter;
  LAstParam: DX.Delphi.AST.TDLParam;
  LName: DX.Delphi.CST.TDLIdentifier;
begin
  Result := TList<DX.Delphi.AST.TDLParam>.Create;
  for LParam in AParams do
  begin
    LAstParam := DX.Delphi.AST.TDLParam.Create(LParam.Span,
      DX.Delphi.AST.TDLParamMode(LParam.Modifier));
    for LName in LParam.Names do
      LAstParam.Names.Add(LName.Name);
    if LParam.TypeExpr <> nil then
      LAstParam.TypeName := RenderTypeName(LParam.TypeExpr);
    if LParam.DefaultValue <> nil then
      LAstParam.DefaultValue := RenderExpr(LParam.DefaultValue);
    Result.Add(LAstParam);
  end;
end;

function TDLDelphiAstBuilder.BuildStatements(
  AStmts: TList<DX.Delphi.CST.TDLStatement>): TList<DX.Delphi.AST.TDLStmt>;
var
  LStmt: DX.Delphi.CST.TDLStatement;
begin
  Result := TList<DX.Delphi.AST.TDLStmt>.Create;
  for LStmt in AStmts do
    Result.Add(BuildStatement(LStmt));
end;

function TDLDelphiAstBuilder.BuildStatement(AStmt: DX.Delphi.CST.TDLStatement): DX.Delphi.AST.TDLStmt;
var
  LCompound: DX.Delphi.CST.TDLCompoundStmt;
  LIf: DX.Delphi.CST.TDLIfStmt;
  LCase: DX.Delphi.CST.TDLCaseStmt;
  LFor: DX.Delphi.CST.TDLForStmt;
  LWhile: DX.Delphi.CST.TDLWhileStmt;
  LRepeat: DX.Delphi.CST.TDLRepeatStmt;
  LWith: DX.Delphi.CST.TDLWithStmt;
  LTry: DX.Delphi.CST.TDLTryStmt;
  LRaise: DX.Delphi.CST.TDLRaiseStmt;
  LGoto: DX.Delphi.CST.TDLGotoStmt;
  LAssign: DX.Delphi.CST.TDLAssignmentStmt;
  LExprStmt: DX.Delphi.CST.TDLExprStmt;
  LAsm: DX.Delphi.CST.TDLAsmStmt;
  LExit: DX.Delphi.CST.TDLExitStmt;
  LVarDecl: DX.Delphi.CST.TDLVarDeclStmt;
  LLabel: DX.Delphi.CST.TDLLabelStmt;
  LAst: DX.Delphi.AST.TDLStmt;
  LSelector: DX.Delphi.CST.TDLCaseSelector;
  LHandler: DX.Delphi.CST.TDLOnHandler;
  LName: DX.Delphi.CST.TDLIdentifier;
  LDirection: string;
  LExpression: DX.Delphi.CST.TDLExpr;
begin
  if AStmt is DX.Delphi.CST.TDLCompoundStmt then
  begin
    LCompound := DX.Delphi.CST.TDLCompoundStmt(AStmt);
    LAst := DX.Delphi.AST.TDLBlock.Create(AStmt.Span);
    DX.Delphi.AST.TDLBlock(LAst).Statements.AddRange(
      BuildStatements(LCompound.Statements));
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLIfStmt then
  begin
    LIf := DX.Delphi.CST.TDLIfStmt(AStmt);
    LAst := DX.Delphi.AST.TDLIfStmt.Create(AStmt.Span,
      BuildExpression(LIf.Condition), BuildStatement(LIf.ThenBranch));
    if LIf.ElseBranch <> nil then
      DX.Delphi.AST.TDLIfStmt(LAst).ElseBranch := BuildStatement(LIf.ElseBranch);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLCaseStmt then
  begin
    LCase := DX.Delphi.CST.TDLCaseStmt(AStmt);
    LAst := DX.Delphi.AST.TDLCaseStmt.Create(AStmt.Span,
      BuildExpression(LCase.Subject));
    for LSelector in LCase.Selectors do
      DX.Delphi.AST.TDLCaseStmt(LAst).Selectors.Add(BuildCaseSelector(LSelector));
    if LCase.ElseBranch <> nil then
      DX.Delphi.AST.TDLCaseStmt(LAst).ElseBranch := BuildStatement(LCase.ElseBranch);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLForStmt then
  begin
    LFor := DX.Delphi.CST.TDLForStmt(AStmt);
    case LFor.Direction of
      kwTo: LDirection := 'to';
      kwDownTo: LDirection := 'downto';
    else
      LDirection := 'in';
    end;
    LAst := DX.Delphi.AST.TDLForStmt.Create(AStmt.Span, LFor.LoopVar.Name,
      LFor.IsInlineVar, LDirection);
    if LFor.StartExpr <> nil then
      DX.Delphi.AST.TDLForStmt(LAst).StartExpr := BuildExpression(LFor.StartExpr);
    if LFor.EndExpr <> nil then
      DX.Delphi.AST.TDLForStmt(LAst).EndExpr := BuildExpression(LFor.EndExpr);
    if LFor.Body <> nil then
      DX.Delphi.AST.TDLForStmt(LAst).Body := BuildStatement(LFor.Body);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLWhileStmt then
  begin
    LWhile := DX.Delphi.CST.TDLWhileStmt(AStmt);
    LAst := DX.Delphi.AST.TDLWhileStmt.Create(AStmt.Span,
      BuildExpression(LWhile.Condition));
    DX.Delphi.AST.TDLWhileStmt(LAst).Body := BuildStatement(LWhile.Body);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLRepeatStmt then
  begin
    LRepeat := DX.Delphi.CST.TDLRepeatStmt(AStmt);
    LAst := DX.Delphi.AST.TDLRepeatStmt.Create(AStmt.Span);
    DX.Delphi.AST.TDLRepeatStmt(LAst).Body := BuildStatement(LRepeat.Body);
    DX.Delphi.AST.TDLRepeatStmt(LAst).Condition :=
      BuildExpression(LRepeat.Condition);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLWithStmt then
  begin
    LWith := DX.Delphi.CST.TDLWithStmt(AStmt);
    LAst := DX.Delphi.AST.TDLWithStmt.Create(AStmt.Span);
    LExpression := nil;
    for LExpression in LWith.Expressions do
      DX.Delphi.AST.TDLWithStmt(LAst).Expressions.Add(BuildExpression(LExpression));
    DX.Delphi.AST.TDLWithStmt(LAst).Body := BuildStatement(LWith.Body);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLTryStmt then
  begin
    LTry := DX.Delphi.CST.TDLTryStmt(AStmt);
    LAst := DX.Delphi.AST.TDLTryStmt.Create(AStmt.Span, LTry.IsExcept);
    DX.Delphi.AST.TDLTryStmt(LAst).Body := BuildStatement(LTry.Body);
    for LHandler in LTry.OnHandlers do
      DX.Delphi.AST.TDLTryStmt(LAst).Handlers.Add(BuildOnHandler(LHandler));
    if LTry.ElseBranch <> nil then
      DX.Delphi.AST.TDLTryStmt(LAst).ElseBranch := BuildStatement(LTry.ElseBranch);
    if LTry.FinallyBody <> nil then
      DX.Delphi.AST.TDLTryStmt(LAst).FinallyBody :=
        BuildStatement(LTry.FinallyBody);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLRaiseStmt then
  begin
    LRaise := DX.Delphi.CST.TDLRaiseStmt(AStmt);
    if LRaise.Exception <> nil then
      LAst := DX.Delphi.AST.TDLRaiseStmt.Create(AStmt.Span,
        BuildExpression(LRaise.Exception))
    else
      LAst := DX.Delphi.AST.TDLRaiseStmt.Create(AStmt.Span, nil);
    if LRaise.AtAddr <> nil then
      DX.Delphi.AST.TDLRaiseStmt(LAst).AtAddr := BuildExpression(LRaise.AtAddr);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLGotoStmt then
  begin
    LGoto := DX.Delphi.CST.TDLGotoStmt(AStmt);
    Result := DX.Delphi.AST.TDLGotoStmt.Create(AStmt.Span, LGoto.LabelName.Name);
  end
  else if AStmt is DX.Delphi.CST.TDLAssignmentStmt then
  begin
    LAssign := DX.Delphi.CST.TDLAssignmentStmt(AStmt);
    Result := DX.Delphi.AST.TDLAssignStmt.Create(AStmt.Span,
      BuildExpression(LAssign.Target), BuildExpression(LAssign.Value));
  end
  else if AStmt is DX.Delphi.CST.TDLExprStmt then
  begin
    LExprStmt := DX.Delphi.CST.TDLExprStmt(AStmt);
    Result := DX.Delphi.AST.TDLExprStmt.Create(AStmt.Span,
      BuildExpression(LExprStmt.Expression));
  end
  else if AStmt is DX.Delphi.CST.TDLAsmStmt then
  begin
    LAsm := DX.Delphi.CST.TDLAsmStmt(AStmt);
    Result := DX.Delphi.AST.TDLAsmStmt.Create(AStmt.Span, LAsm.Text);
  end
  else if AStmt is DX.Delphi.CST.TDLExitStmt then
  begin
    LExit := DX.Delphi.CST.TDLExitStmt(AStmt);
    if LExit.Expression <> nil then
      Result := DX.Delphi.AST.TDLExitStmt.Create(AStmt.Span,
        BuildExpression(LExit.Expression))
    else
      Result := DX.Delphi.AST.TDLExitStmt.Create(AStmt.Span, nil);
  end
  else if AStmt is DX.Delphi.CST.TDLBreakStmt then
    Result := DX.Delphi.AST.TDLBreakStmt.Create(AStmt.Span)
  else if AStmt is DX.Delphi.CST.TDLContinueStmt then
    Result := DX.Delphi.AST.TDLContinueStmt.Create(AStmt.Span)
  else if AStmt is DX.Delphi.CST.TDLEmptyStmt then
    Result := DX.Delphi.AST.TDLEmptyStmt.Create(AStmt.Span)
  else if AStmt is DX.Delphi.CST.TDLVarDeclStmt then
  begin
    LVarDecl := DX.Delphi.CST.TDLVarDeclStmt(AStmt);
    LAst := DX.Delphi.AST.TDLVarDeclStmt.Create(AStmt.Span);
    for LName in LVarDecl.VarDecl.Names do
      DX.Delphi.AST.TDLVarDeclStmt(LAst).Names.Add(LName.Name);
    if LVarDecl.VarDecl.TypeExpr <> nil then
      DX.Delphi.AST.TDLVarDeclStmt(LAst).TypeName :=
        RenderTypeName(LVarDecl.VarDecl.TypeExpr);
    if LVarDecl.VarDecl.Init <> nil then
      DX.Delphi.AST.TDLVarDeclStmt(LAst).Init :=
        RenderExpr(LVarDecl.VarDecl.Init);
    Result := LAst;
  end
  else if AStmt is DX.Delphi.CST.TDLLabelStmt then
  begin
    LLabel := DX.Delphi.CST.TDLLabelStmt(AStmt);
    LAst := DX.Delphi.AST.TDLLabelStmt.Create(AStmt.Span, LLabel.LabelName.Name);
    if LLabel.Statement <> nil then
      DX.Delphi.AST.TDLLabelStmt(LAst).Statement :=
        BuildStatement(LLabel.Statement);
    Result := LAst;
  end
  else
    Result := DX.Delphi.AST.TDLEmptyStmt.Create(AStmt.Span);
end;

function TDLDelphiAstBuilder.BuildCaseSelector(
  ASelector: DX.Delphi.CST.TDLCaseSelector): DX.Delphi.AST.TDLCaseSelector;
var
  LAst: DX.Delphi.AST.TDLCaseSelector;
  LLabel: DX.Delphi.CST.TDLExpr;
begin
  LAst := DX.Delphi.AST.TDLCaseSelector.Create(ASelector.Span);
  for LLabel in ASelector.Labels do
    LAst.Labels.Add(BuildExpression(LLabel));
  if ASelector.Statement <> nil then
    LAst.Statement := BuildStatement(ASelector.Statement);
  Result := LAst;
end;

function TDLDelphiAstBuilder.BuildOnHandler(
  AHandler: DX.Delphi.CST.TDLOnHandler): DX.Delphi.AST.TDLOnHandler;
var
  LAst: DX.Delphi.AST.TDLOnHandler;
begin
  LAst := DX.Delphi.AST.TDLOnHandler.Create(AHandler.Span);
  if AHandler.VarName <> nil then
    LAst.VarName := AHandler.VarName.Name;
  if AHandler.TypeName <> nil then
    LAst.TypeName := AHandler.TypeName.Name;
  if AHandler.Body <> nil then
    LAst.Body := BuildStatement(AHandler.Body);
  Result := LAst;
end;

function TDLDelphiAstBuilder.BuildExpression(AExpr: DX.Delphi.CST.TDLExpr): DX.Delphi.AST.TDLExpr;
var
  LIdent: DX.Delphi.CST.TDLIdentifierExpr;
  LNumber: DX.Delphi.CST.TDLNumberExpr;
  LString: DX.Delphi.CST.TDLStringExpr;
  LBinary: DX.Delphi.CST.TDLBinaryExpr;
  LUnary: DX.Delphi.CST.TDLUnaryExpr;
  LIndex: DX.Delphi.CST.TDLIndexExpr;
  LCall: DX.Delphi.CST.TDLCallExpr;
  LMember: DX.Delphi.CST.TDLMemberExpr;
  LGeneric: DX.Delphi.CST.TDLGenericInstantiationExpr;
  LInherited: DX.Delphi.CST.TDLInheritedExpr;
  LAnon: DX.Delphi.CST.TDLAnonymousMethodExpr;
  LSet: DX.Delphi.CST.TDLSetExpr;
  LArray: DX.Delphi.CST.TDLArrayExpr;
  LAst: DX.Delphi.AST.TDLExpr;
  LArg: DX.Delphi.CST.TDLExpr;
  LTypeArg: DX.Delphi.CST.TDLTypeArg;
  i: Integer;
begin
  if AExpr is DX.Delphi.CST.TDLIdentifierExpr then
  begin
    LIdent := DX.Delphi.CST.TDLIdentifierExpr(AExpr);
    Result := DX.Delphi.AST.TDLIdentExpr.Create(AExpr.Span, LIdent.Name.Name);
  end
  else if AExpr is DX.Delphi.CST.TDLNumberExpr then
  begin
    LNumber := DX.Delphi.CST.TDLNumberExpr(AExpr);
    Result := DX.Delphi.AST.TDLNumberExpr.Create(AExpr.Span, LNumber.Token.Text,
      LNumber.Token.Kind = tkFloat);
  end
  else if AExpr is DX.Delphi.CST.TDLStringExpr then
  begin
    LString := DX.Delphi.CST.TDLStringExpr(AExpr);
    Result := DX.Delphi.AST.TDLStringExpr.Create(AExpr.Span, LString.Value);
  end
  else if AExpr is DX.Delphi.CST.TDLNilExpr then
    Result := DX.Delphi.AST.TDLNilExpr.Create(AExpr.Span)
  else if AExpr is DX.Delphi.CST.TDLBinaryExpr then
  begin
    LBinary := DX.Delphi.CST.TDLBinaryExpr(AExpr);
    Result := DX.Delphi.AST.TDLBinaryExpr.Create(AExpr.Span,
      DX.Delphi.AST.TDLBinOp(LBinary.Operator), LBinary.OperatorText,
      BuildExpression(LBinary.Left), BuildExpression(LBinary.Right));
  end
  else if AExpr is DX.Delphi.CST.TDLUnaryExpr then
  begin
    LUnary := DX.Delphi.CST.TDLUnaryExpr(AExpr);
    Result := DX.Delphi.AST.TDLUnaryExpr.Create(AExpr.Span,
      DX.Delphi.AST.TDLUnOp(LUnary.Operator), LUnary.OperatorText,
      BuildExpression(LUnary.Operand));
  end
  else if AExpr is DX.Delphi.CST.TDLIndexExpr then
  begin
    LIndex := DX.Delphi.CST.TDLIndexExpr(AExpr);
    LAst := DX.Delphi.AST.TDLIndexExpr.Create(AExpr.Span,
      BuildExpression(LIndex.Target));
    for i := 0 to LIndex.Indices.Count - 1 do
      DX.Delphi.AST.TDLIndexExpr(LAst).Indices.Add(
        BuildExpression(LIndex.Indices[i]));
    Result := LAst;
  end
  else if AExpr is DX.Delphi.CST.TDLCallExpr then
  begin
    LCall := DX.Delphi.CST.TDLCallExpr(AExpr);
    LAst := DX.Delphi.AST.TDLCallExpr.Create(AExpr.Span,
      BuildExpression(LCall.Callee));
    for LArg in LCall.Args do
      DX.Delphi.AST.TDLCallExpr(LAst).Args.Add(BuildExpression(LArg));
    Result := LAst;
  end
  else if AExpr is DX.Delphi.CST.TDLMemberExpr then
  begin
    LMember := DX.Delphi.CST.TDLMemberExpr(AExpr);
    Result := DX.Delphi.AST.TDLMemberExpr.Create(AExpr.Span,
      BuildExpression(LMember.Target), LMember.Member.Name);
  end
  else if AExpr is DX.Delphi.CST.TDLGenericInstantiationExpr then
  begin
    LGeneric := DX.Delphi.CST.TDLGenericInstantiationExpr(AExpr);
    LAst := DX.Delphi.AST.TDLGenericInstExpr.Create(AExpr.Span,
      BuildExpression(LGeneric.Target));
    for LTypeArg in LGeneric.TypeArgs do
      if LTypeArg.TypeExpr is DX.Delphi.CST.TDLNamedType then
        DX.Delphi.AST.TDLGenericInstExpr(LAst).TypeArgs.Add(
          DX.Delphi.CST.TDLNamedType(LTypeArg.TypeExpr).Name.Name);
    Result := LAst;
  end
  else if AExpr is DX.Delphi.CST.TDLInheritedExpr then
  begin
    LInherited := DX.Delphi.CST.TDLInheritedExpr(AExpr);
    if LInherited.Target <> nil then
      Result := DX.Delphi.AST.TDLInheritedExpr.Create(AExpr.Span,
        BuildExpression(LInherited.Target))
    else
      Result := DX.Delphi.AST.TDLInheritedExpr.Create(AExpr.Span, nil);
  end
  else if AExpr is DX.Delphi.CST.TDLAnonymousMethodExpr then
  begin
    LAnon := DX.Delphi.CST.TDLAnonymousMethodExpr(AExpr);
    LAst := DX.Delphi.AST.TDLAnonMethodExpr.Create(AExpr.Span,
      CProcKindMap[LAnon.Kind]);
    DX.Delphi.AST.TDLAnonMethodExpr(LAst).Params.AddRange(
      BuildParams(LAnon.Params));
    if LAnon.ReturnType <> nil then
      DX.Delphi.AST.TDLAnonMethodExpr(LAst).ReturnType :=
        RenderTypeName(LAnon.ReturnType);
    DX.Delphi.AST.TDLAnonMethodExpr(LAst).Body := BuildStatement(LAnon.Body);
    Result := LAst;
  end
  else if AExpr is DX.Delphi.CST.TDLSetExpr then
  begin
    LSet := DX.Delphi.CST.TDLSetExpr(AExpr);
    LAst := DX.Delphi.AST.TDLSetExpr.Create(AExpr.Span);
    for i := 0 to LSet.Elements.Count - 1 do
    begin
      DX.Delphi.AST.TDLSetExpr(LAst).Elements.Add(
        BuildExpression(LSet.Elements[i]));
      DX.Delphi.AST.TDLSetExpr(LAst).IsRanges.Add(LSet.IsRanges[i]);
    end;
    Result := LAst;
  end
  else if AExpr is DX.Delphi.CST.TDLArrayExpr then
  begin
    LArray := DX.Delphi.CST.TDLArrayExpr(AExpr);
    LAst := DX.Delphi.AST.TDLArrayExpr.Create(AExpr.Span);
    for LArg in LArray.Elements do
      DX.Delphi.AST.TDLArrayExpr(LAst).Elements.Add(BuildExpression(LArg));
    Result := LAst;
  end
  else
    Result := DX.Delphi.AST.TDLNilExpr.Create(AExpr.Span);
end;

procedure TDLDelphiAstBuilder.BuildMembers(ACSTMembers: TList<DX.Delphi.CST.TDLMember>;
  AASTMembers: TList<DX.Delphi.AST.TDLMember>);
var
  LMember: DX.Delphi.CST.TDLMember;
  LField: DX.Delphi.CST.TDLFieldDecl;
  LMethod: DX.Delphi.CST.TDLProcedureBase;
  LProperty: DX.Delphi.CST.TDLPropertyDecl;
  LVisibility: DX.Delphi.CST.TDLVisibilitySection;
  LAst: DX.Delphi.AST.TDLMember;
  LName: DX.Delphi.CST.TDLIdentifier;
  LImpl: DX.Delphi.CST.TDLMethodImpl;
  LDirective: DX.Delphi.CST.TDLDirective;
  LAstMethod: DX.Delphi.AST.TDLMethod;
begin
  for LMember in ACSTMembers do
  begin
    if LMember is DX.Delphi.CST.TDLVisibilitySection then
    begin
      LVisibility := DX.Delphi.CST.TDLVisibilitySection(LMember);
      AASTMembers.Add(DX.Delphi.AST.TDLVisibilitySection.Create(LMember.Span,
        DX.Delphi.AST.TDLVisibility(LVisibility.Kind), LVisibility.IsStrict));
    end
    else if LMember is DX.Delphi.CST.TDLFieldDecl then
    begin
      LField := DX.Delphi.CST.TDLFieldDecl(LMember);
      LAst := DX.Delphi.AST.TDLField.Create(LMember.Span,
        DX.Delphi.AST.TDLVisibility(LField.Visibility), LField.IsStrict);
      for LName in LField.Names do
        DX.Delphi.AST.TDLField(LAst).Names.Add(LName.Name);
      if LField.TypeExpr <> nil then
        DX.Delphi.AST.TDLField(LAst).TypeName := RenderTypeName(LField.TypeExpr);
      for LName in LField.Names do
        FSymbols.Add(TDLSymbol.Create(LName.Name, skField, LName.Span));
      AASTMembers.Add(LAst);
    end
    else if LMember is DX.Delphi.CST.TDLMethodDecl then
    begin
      LMethod := DX.Delphi.CST.TDLMethodDecl(LMember);
      LAstMethod := DX.Delphi.AST.TDLMethod.Create(LMember.Span,
        CProcKindMap[LMethod.Kind], LMethod.Name.Name,
        LMethod.ClassModifier = cmClass,
        DX.Delphi.AST.TDLVisibility(LMethod.Visibility));
      LAstMethod.Params.AddRange(BuildParams(LMethod.Params));
      if LMethod.ReturnType <> nil then
        LAstMethod.ReturnType := RenderTypeName(LMethod.ReturnType);
      for LDirective in LMethod.Directives do
        LAstMethod.Directives.Add(LDirective.Name.Name);
      LAstMethod.HasBody := False;
      FSymbols.Add(TDLSymbol.Create(LMethod.Name.Name, skProcedure,
        LMethod.Name.Span));
      AASTMembers.Add(LAstMethod);
    end
    else if LMember is DX.Delphi.CST.TDLMethodImpl then
    begin
      LImpl := DX.Delphi.CST.TDLMethodImpl(LMember);
      LAstMethod := DX.Delphi.AST.TDLMethod.Create(LMember.Span,
        CProcKindMap[LImpl.Kind], LImpl.Name.Name,
        LImpl.ClassModifier = cmClass,
        DX.Delphi.AST.TDLVisibility(LImpl.Visibility));
      LAstMethod.Params.AddRange(BuildParams(LImpl.Params));
      if LImpl.ReturnType <> nil then
        LAstMethod.ReturnType := RenderTypeName(LImpl.ReturnType);
      for LDirective in LImpl.Directives do
        LAstMethod.Directives.Add(LDirective.Name.Name);
      LAstMethod.HasBody := LImpl.Body <> nil;
      if (LImpl.Body <> nil) and (LImpl.Body is DX.Delphi.CST.TDLCompoundStmt) then
        LAstMethod.Body.AddRange(BuildStatements(
          DX.Delphi.CST.TDLCompoundStmt(LImpl.Body).Statements));
      AASTMembers.Add(LAstMethod);
    end
    else if LMember is DX.Delphi.CST.TDLPropertyDecl then
    begin
      LProperty := DX.Delphi.CST.TDLPropertyDecl(LMember);
      LAst := DX.Delphi.AST.TDLProperty.Create(LMember.Span, LProperty.Name.Name,
        DX.Delphi.AST.TDLVisibility(LProperty.Visibility));
      DX.Delphi.AST.TDLProperty(LAst).TypeName :=
        RenderTypeName(LProperty.TypeExpr);
      DX.Delphi.AST.TDLProperty(LAst).IndexParams.AddRange(
        BuildParams(LProperty.IndexParams));
      if LProperty.ReadName <> nil then
        DX.Delphi.AST.TDLProperty(LAst).ReadName := LProperty.ReadName.Name;
      if LProperty.WriteName <> nil then
        DX.Delphi.AST.TDLProperty(LAst).WriteName := LProperty.WriteName.Name;
      if LProperty.StoredName <> nil then
        DX.Delphi.AST.TDLProperty(LAst).StoredName := LProperty.StoredName.Name;
      DX.Delphi.AST.TDLProperty(LAst).IsDefault := LProperty.IsDefault;
      if LProperty.DefaultValue <> nil then
        DX.Delphi.AST.TDLProperty(LAst).DefaultValue :=
          RenderExpr(LProperty.DefaultValue);
      if LProperty.IndexSpec <> nil then
        DX.Delphi.AST.TDLProperty(LAst).IndexExpr :=
          RenderExpr(LProperty.IndexSpec);
      AASTMembers.Add(LAst);
    end
    else
      AASTMembers.Add(DX.Delphi.AST.TDLVisibilitySection.Create(LMember.Span,
        DX.Delphi.AST.vsPublic, False));
  end;
end;

function TDLDelphiAstBuilder.BuildVariantPart(
  ACSTPart: DX.Delphi.CST.TDLVariantSection): DX.Delphi.AST.TDLVariantPart;
var
  LPart: DX.Delphi.AST.TDLVariantPart;
  LLabel: DX.Delphi.CST.TDLExpr;
  LBranch: DX.Delphi.CST.TDLVariantBranch;
  LField: DX.Delphi.CST.TDLFieldDecl;
  LName: DX.Delphi.CST.TDLIdentifier;
  LAstField: DX.Delphi.AST.TDLField;
begin
  LPart := DX.Delphi.AST.TDLVariantPart.Create(ACSTPart.Span);
  if ACSTPart.Tag <> nil then
    LPart.Tag := ACSTPart.Tag.Name;
  if ACSTPart.TagType <> nil then
    LPart.TagType := RenderTypeName(ACSTPart.TagType);
  for LBranch in ACSTPart.Variants do
  begin
    for LLabel in LBranch.CaseLabels do
      LPart.Labels.Add(RenderExpr(LLabel));
    for LField in LBranch.Fields do
    begin
      LAstField := DX.Delphi.AST.TDLField.Create(LField.Span, DX.Delphi.AST.vsPublic, False);
      for LName in LField.Names do
        LAstField.Names.Add(LName.Name);
      if LField.TypeExpr <> nil then
        LAstField.TypeName := RenderTypeName(LField.TypeExpr);
      LPart.Fields.Add(LAstField);
    end;
    if LBranch.VariantPart <> nil then
      LPart.SubVariants.Add(BuildVariantPart(LBranch.VariantPart));
  end;
  Result := LPart;
end;

function TDLDelphiAstBuilder.Build(ACST: DX.Delphi.CST.TDLCompilationUnit): DX.Delphi.AST.TDLModule;
var
  LModule: DX.Delphi.AST.TDLModule;
  LKind: DX.Delphi.AST.TDLModuleKind;
  LUse: DX.Delphi.CST.TDLUsesClause;
  LReference: DX.Delphi.CST.TDLUnitReference;
  LItem: DX.Delphi.CST.TDLNode;
  LTypeSection: DX.Delphi.CST.TDLTypeSection;
  LTypeDecl: DX.Delphi.CST.TDLTypeDecl;
  LConstSection: DX.Delphi.CST.TDLConstSection;
  LConstDecl: DX.Delphi.CST.TDLConstDecl;
  LResStringSection: DX.Delphi.CST.TDLResStringSection;
  LVarSection: DX.Delphi.CST.TDLVarSection;
  LVarDecl: DX.Delphi.CST.TDLVarDecl;
  LLabelSection: DX.Delphi.CST.TDLLabelSection;
  LLabelDecl: DX.Delphi.CST.TDLLabelDecl;
  LExports: DX.Delphi.CST.TDLExportsClause;
  LExport: DX.Delphi.CST.TDLExportItem;
  LProc: DX.Delphi.CST.TDLProcedureBase;
  LImpl: DX.Delphi.CST.TDLMethodImpl;
  LAstConst: DX.Delphi.AST.TDLConstDecl;
  LAstVar: DX.Delphi.AST.TDLVarDecl;
  LAstLabel: DX.Delphi.AST.TDLLabelDecl;
  LAstExport: DX.Delphi.AST.TDLExportDecl;
  LAstProc: DX.Delphi.AST.TDLProcDecl;
  LAstUse: DX.Delphi.AST.TDLUse;
  LName: DX.Delphi.CST.TDLIdentifier;
  LDirective: DX.Delphi.CST.TDLDirective;
  LStmt: DX.Delphi.CST.TDLStatement;
begin
  case ACST.ProgramKind of
    pkProgram: LKind := DX.Delphi.AST.mkProgram;
    pkUnit: LKind := DX.Delphi.AST.mkUnit;
    pkLibrary: LKind := DX.Delphi.AST.mkLibrary;
  else
    LKind := DX.Delphi.AST.mkPackage;
  end;
  LModule := DX.Delphi.AST.TDLModule.Create(ACST.Span, LKind, ACST.Name.Name);
  FSymbols.Add(TDLSymbol.Create(ACST.Name.Name, skUnit, ACST.Name.Span));

  for LUse in ACST.UsesClauses do
    for LReference in LUse.References do
    begin
      LAstUse := DX.Delphi.AST.TDLUse.Create(LReference.Span, LReference.Name.Name);
      if LReference.InFile is DX.Delphi.CST.TDLStringExpr then
        LAstUse.InFile := DX.Delphi.CST.TDLStringExpr(LReference.InFile).Value;
      LModule.UsedUnits.Add(LAstUse);
    end;

  for LItem in ACST.Items do
  begin
    if LItem is DX.Delphi.CST.TDLTypeSection then
    begin
      LTypeSection := DX.Delphi.CST.TDLTypeSection(LItem);
      for LTypeDecl in LTypeSection.Items do
      begin
        LModule.Declarations.Add(DX.Delphi.AST.TDLTypeDecl.Create(LTypeDecl.Span,
          LTypeDecl.Name.Name, BuildTypeDef(LTypeDecl.TypeExpr)));
        FSymbols.Add(TDLSymbol.Create(LTypeDecl.Name.Name, skType,
          LTypeDecl.Name.Span));
      end;
    end
    else if LItem is DX.Delphi.CST.TDLConstSection then
    begin
      LConstSection := DX.Delphi.CST.TDLConstSection(LItem);
      for LConstDecl in LConstSection.Items do
      begin
        LAstConst := DX.Delphi.AST.TDLConstDecl.Create(LConstDecl.Span);
        for LName in LConstDecl.Names do
          LAstConst.Names.Add(LName.Name);
        if LConstDecl.TypeExpr <> nil then
          LAstConst.TypeName := RenderTypeName(LConstDecl.TypeExpr);
        if LConstDecl.Value <> nil then
          LAstConst.Value := RenderExpr(LConstDecl.Value);
        LModule.Declarations.Add(LAstConst);
        for LName in LConstDecl.Names do
          FSymbols.Add(TDLSymbol.Create(LName.Name, skConst, LName.Span));
      end;
    end
    else if LItem is DX.Delphi.CST.TDLResStringSection then
    begin
      LResStringSection := DX.Delphi.CST.TDLResStringSection(LItem);
      for LConstDecl in LResStringSection.Items do
      begin
        LAstConst := DX.Delphi.AST.TDLConstDecl.Create(LConstDecl.Span);
        for LName in LConstDecl.Names do
          LAstConst.Names.Add(LName.Name);
        if LConstDecl.Value <> nil then
          LAstConst.Value := RenderExpr(LConstDecl.Value);
        LModule.Declarations.Add(LAstConst);
        for LName in LConstDecl.Names do
          FSymbols.Add(TDLSymbol.Create(LName.Name, skResourceString,
            LName.Span));
      end;
    end
    else if LItem is DX.Delphi.CST.TDLVarSection then
    begin
      LVarSection := DX.Delphi.CST.TDLVarSection(LItem);
      for LVarDecl in LVarSection.Items do
      begin
        LAstVar := DX.Delphi.AST.TDLVarDecl.Create(LVarDecl.Span,
          LVarSection.IsThreadVar);
        for LName in LVarDecl.Names do
          LAstVar.Names.Add(LName.Name);
        if LVarDecl.TypeExpr <> nil then
          LAstVar.TypeName := RenderTypeName(LVarDecl.TypeExpr);
        if LVarDecl.Init <> nil then
          LAstVar.Init := RenderExpr(LVarDecl.Init);
        if LVarDecl.AbsoluteTarget <> nil then
          LAstVar.AbsoluteOf := RenderExpr(LVarDecl.AbsoluteTarget);
        LModule.Declarations.Add(LAstVar);
        for LName in LVarDecl.Names do
          if LVarSection.IsThreadVar then
            FSymbols.Add(TDLSymbol.Create(LName.Name, skThreadVar, LName.Span))
          else
            FSymbols.Add(TDLSymbol.Create(LName.Name, skVar, LName.Span));
      end;
    end
    else if LItem is DX.Delphi.CST.TDLLabelSection then
    begin
      LLabelSection := DX.Delphi.CST.TDLLabelSection(LItem);
      for LLabelDecl in LLabelSection.Items do
      begin
        LAstLabel := DX.Delphi.AST.TDLLabelDecl.Create(LLabelDecl.Span,
          LLabelDecl.Name.Name);
        LModule.Declarations.Add(LAstLabel);
        FSymbols.Add(TDLSymbol.Create(LLabelDecl.Name.Name, skLabel,
          LLabelDecl.Name.Span));
      end;
    end
    else if LItem is DX.Delphi.CST.TDLExportsClause then
    begin
      LExports := DX.Delphi.CST.TDLExportsClause(LItem);
      for LExport in LExports.Items do
      begin
        LAstExport := DX.Delphi.AST.TDLExportDecl.Create(LExport.Span,
          LExport.Name.Name);
        if LExport.Index <> nil then
          LAstExport.Index := RenderExpr(LExport.Index);
        if LExport.NameSpec is DX.Delphi.CST.TDLStringExpr then
          LAstExport.ExportName :=
            DX.Delphi.CST.TDLStringExpr(LExport.NameSpec).Value;
        LModule.Declarations.Add(LAstExport);
      end;
    end
    else if LItem is DX.Delphi.CST.TDLMethodImpl then
    begin
      LImpl := DX.Delphi.CST.TDLMethodImpl(LItem);
      LAstProc := DX.Delphi.AST.TDLProcDecl.Create(LImpl.Span,
        CProcKindMap[LImpl.Kind], LImpl.Name.Name,
        LImpl.ClassModifier = cmClass);
      LAstProc.Params.AddRange(BuildParams(LImpl.Params));
      if LImpl.ReturnType <> nil then
        LAstProc.ReturnType := RenderTypeName(LImpl.ReturnType);
      for LDirective in LImpl.Directives do
        LAstProc.Directives.Add(LDirective.Name.Name);
      LAstProc.HasBody := LImpl.Body <> nil;
      if (LImpl.Body <> nil) and (LImpl.Body is DX.Delphi.CST.TDLCompoundStmt) then
        LAstProc.Body.AddRange(BuildStatements(
          DX.Delphi.CST.TDLCompoundStmt(LImpl.Body).Statements));
      LModule.Declarations.Add(LAstProc);
      FSymbols.Add(TDLSymbol.Create(LImpl.Name.Name, skProcedure,
        LImpl.Name.Span));
    end
    else if LItem is DX.Delphi.CST.TDLMethodDecl then
    begin
      LProc := DX.Delphi.CST.TDLMethodDecl(LItem);
      LAstProc := DX.Delphi.AST.TDLProcDecl.Create(LProc.Span,
        CProcKindMap[LProc.Kind], LProc.Name.Name,
        LProc.ClassModifier = cmClass);
      LAstProc.Params.AddRange(BuildParams(LProc.Params));
      if LProc.ReturnType <> nil then
        LAstProc.ReturnType := RenderTypeName(LProc.ReturnType);
      for LDirective in LProc.Directives do
        LAstProc.Directives.Add(LDirective.Name.Name);
      LAstProc.HasBody := False;
      LModule.Declarations.Add(LAstProc);
      FSymbols.Add(TDLSymbol.Create(LProc.Name.Name, skProcedure,
        LProc.Name.Span));
    end;
  end;

  if ACST.InitSection <> nil then
  begin
    LStmt := ACST.InitSection.Body;
    if LStmt is DX.Delphi.CST.TDLCompoundStmt then
      LModule.InitStatements.AddRange(
        BuildStatements(DX.Delphi.CST.TDLCompoundStmt(LStmt).Statements));
  end;
  if ACST.FinalizationSection <> nil then
  begin
    LStmt := ACST.FinalizationSection.Body;
    if LStmt is DX.Delphi.CST.TDLCompoundStmt then
      LModule.FinalStatements.AddRange(
        BuildStatements(DX.Delphi.CST.TDLCompoundStmt(LStmt).Statements));
  end;
  Result := LModule;
end;

end.
