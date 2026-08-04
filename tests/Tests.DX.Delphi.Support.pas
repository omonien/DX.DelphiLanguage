/// <summary>
///   Tests.DX.Delphi.Support — shared helpers for the DX.Delphi unit tests:
///   lexing/parsing source snippets and lowering to the AST.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Support;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Delphi.Core,
  DX.Delphi.Lexer,
  DX.Delphi.CST,
  DX.Delphi.Parser,
  DX.Delphi.AST,
  DX.Delphi.AstBuilder;

/// <summary>Shared helpers for the DX.Delphi unit tests.</summary>
  /// <summary>Lexes a source text; returns the owned token list.</summary>
  function LexSource(const ASource: string; ADiagnostics: TDLDiagnostics):
    TObjectList<TDLToken>;

  /// <summary>Lexes and parses a source text; returns the owned CST unit.</summary>
  function ParseSource(const ASource: string; ADiagnostics: TDLDiagnostics):
    TDLCompilationUnit;

  /// <summary>Lexes, parses and lowers; returns the owned AST module.</summary>
  function BuildAst(const ASource: string; ADiagnostics: TDLDiagnostics):
    TDLModule;

  /// <summary>Returns the first diagnostic's code ('' if none).</summary>
  function FirstErrorCode(ADiagnostics: TDLDiagnostics): string;

implementation

function LexSource(const ASource: string; ADiagnostics: TDLDiagnostics):
  TObjectList<TDLToken>;
begin
  Result := TDLDelphiLexer.Create(ASource, ADiagnostics).Tokenize;
end;

function ParseSource(const ASource: string; ADiagnostics: TDLDiagnostics):
  TDLCompilationUnit;
var
  LTokens: TObjectList<TDLToken>;
  LParser: TDLDelphiParser;
begin
  LTokens := LexSource(ASource, ADiagnostics);
  try
    LParser := TDLDelphiParser.Create(LTokens, ADiagnostics, ASource);
    try
      Result := LParser.Parse;
    finally
      LParser.Free;
    end;
  finally
    LTokens.Free;
  end;
end;

function BuildAst(const ASource: string; ADiagnostics: TDLDiagnostics):
  TDLModule;
var
  LCST: TDLCompilationUnit;
  LBuilder: TDLDelphiAstBuilder;
begin
  LCST := ParseSource(ASource, ADiagnostics);
  try
    LBuilder := TDLDelphiAstBuilder.Create(ADiagnostics);
    try
      Result := LBuilder.Build(LCST);
    finally
      LBuilder.Free;
    end;
  finally
    LCST.Free;
  end;
end;

function FirstErrorCode(ADiagnostics: TDLDiagnostics): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ADiagnostics.Count - 1 do
    if ADiagnostics[i].Severity = dsError then
      Exit(ADiagnostics[i].Code);
end;

end.
