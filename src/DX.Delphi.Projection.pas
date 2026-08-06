(*----------------------------------------------------------------------------
  DX.Delphi.Projection

  Projection of a CST onto a concrete define configuration.

  The CST keeps all conditional branches structurally (see
  DX.Delphi.Conditions). Given a TDLDefineSet, the projector selects the
  first branch whose guard evaluates to true and yields the active
  statement sequence — without re-parsing. This is the "instant
  configuration" view for compilers, refactorings and IDE tooling.

  Code formatters do NOT use the projection: they consume the full branch
  tree plus trivia so every conditional path is preserved.

  Copyright (c) 2026
  MIT License
----------------------------------------------------------------------------*)
unit DX.Delphi.Projection;

interface

uses
  System.Generics.Collections,
  DX.Delphi.CST,
  DX.Delphi.Conditions;

type
  /// <summary>A compound block rebuilt by the projection. Marked so callers
  /// can dispose the wrapper nodes without touching the original CST.</summary>
  TDLProjectedCompoundStmt = class(TDLCompoundStmt)
  end;

  /// <summary>
  ///  Selects the active conditional branches for a define configuration.
  ///  The returned statements are references into the original CST (do not
  ///  free them separately); blocks that were rebuilt are TDLProjectedCompoundStmt
  ///  instances that must be released via DisposeProjected before the list is
  ///  freed.
  /// </summary>
  TDLTreeProjector = class
  public
    /// <summary>
    ///  Flattens a statement list: each conditional group is replaced by the
    ///  statements of its first branch whose guard evaluates to true (the
    ///  {$ELSE} branch always matches). Compound statements are rebuilt with
    ///  their inner statements projected.
    /// </summary>
    class function ProjectStatements(
      AStatements: TList<TDLStatement>;
      const ADefines: TDLDefineSet): TList<TDLStatement>;
    /// <summary>Releases the wrapper nodes built by ProjectStatements.
    /// Original CST references are left untouched. Call on the returned
    /// list before freeing it.</summary>
    class procedure DisposeProjected(AStatements: TList<TDLStatement>);
  end;

implementation

class function TDLTreeProjector.ProjectStatements(
  AStatements: TList<TDLStatement>;
  const ADefines: TDLDefineSet): TList<TDLStatement>;
var
  LStmt: TDLStatement;
  LCond: TDLConditionalStmt;
  LActive: TDLConditionalBranch;
  LCompound: TDLCompoundStmt;
  LNewCompound: TDLCompoundStmt;
  LProjected: TList<TDLStatement>;
  LInner: TDLStatement;
  i: Integer;
begin
  Result := TList<TDLStatement>.Create;
  for LStmt in AStatements do
    if LStmt is TDLConditionalStmt then
    begin
      LCond := TDLConditionalStmt(LStmt);
      LActive := nil;
      for i := 0 to LCond.Branches.Count - 1 do
        if LCond.Branches[i].Condition.Evaluate(ADefines) then
        begin
          LActive := LCond.Branches[i];
          Break;
        end;
      if LActive <> nil then
        for LInner in LActive.Statements do
          Result.Add(LInner);
    end
    else if LStmt is TDLCompoundStmt then
    begin
      // Rebuild the block with projected inner statements.
      LCompound := TDLCompoundStmt(LStmt);
      LNewCompound := TDLProjectedCompoundStmt.Create(LCompound.Span);
      // The projected statements are references into the original CST (see
      // the class contract); the rebuilt compound must not own them.
      LNewCompound.Statements.OwnsObjects := False;
      LProjected := ProjectStatements(LCompound.Statements, ADefines);
      try
        LNewCompound.Statements.AddRange(LProjected);
      finally
        LProjected.Free;
      end;
      Result.Add(LNewCompound);
    end
    else
      Result.Add(LStmt);
end;

class procedure TDLTreeProjector.DisposeProjected(
  AStatements: TList<TDLStatement>);
var
  LStmt: TDLStatement;
begin
  for LStmt in AStatements do
    if LStmt is TDLProjectedCompoundStmt then
    begin
      DisposeProjected(TDLProjectedCompoundStmt(LStmt).Statements);
      LStmt.Free;
    end;
end;

end.
