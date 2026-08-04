/// <summary>
///   DLDemo — console demo for the DX.Delphi language model: lex a Delphi
///   source file, build the CST, lower it to the AST and print both trees
///   plus diagnostics and the recorded symbol table.
/// </summary>
/// <remarks>
///   Usage: DLDemo [file.pas]
///   If no file is given, samples\Demo.pas is used.
///
///   Pipeline:
///     source -> TDLDelphiLexer -> tokens -> TDLDelphiParser -> CST
///            -> TDLDelphiAstBuilder -> AST
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
program DLDemo;

{$APPTYPE CONSOLE}
{$R *.res}

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

procedure DumpTokens(ATokens: TObjectList<TDLToken>);
var
  LToken: TDLToken;
begin
  Writeln('--- tokens ---');
  for LToken in ATokens do
    if LToken.IsTrivia then
      Writeln(Format('  %-12s %s', [TDLTokenKindNames[LToken.Kind], LToken.Text]))
    else
      Writeln(Format('  %-12s %-24s %s', [TDLTokenKindNames[LToken.Kind],
        LToken.Description, LToken.Span.ToString]));
end;

function ReadSource(const AFileName: string): string;
var
  LStream: TFileStream;
  LReader: TStreamReader;
begin
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    LReader := TStreamReader.Create(LStream, TEncoding.UTF8, True);
    try
      Result := LReader.ReadToEnd;
    finally
      LReader.Free;
    end;
  finally
    LStream.Free;
  end;
end;

var
  LFileName: string;
  LSource: string;
  LDiagnostics: TDLDiagnostics;
  LTokens: TObjectList<TDLToken>;
  LParser: TDLDelphiParser;
  LCST: TDLCompilationUnit;
  LBuilder: TDLDelphiAstBuilder;
  LAST: TDLModule;
  LSymbol: TDLSymbol;
  i: Integer;
begin
  if ParamCount > 0 then
    LFileName := ParamStr(1)
  else
    LFileName := 'samples\Demo.pas';

  if not FileExists(LFileName) then
  begin
    Writeln('File not found: ' + LFileName);
    ExitCode := 1;
    Exit;
  end;

  LSource := ReadSource(LFileName);
  LDiagnostics := TDLDiagnostics.Create;
  try
    // Lex
    LTokens := TDLDelphiLexer.Create(LSource, LDiagnostics).Tokenize;
    try
      DumpTokens(LTokens);

      // Parse (CST)
      LParser := TDLDelphiParser.Create(LTokens, LDiagnostics, LSource);
      try
        LCST := LParser.Parse;
        try
          Writeln('');
          Writeln('--- CST ---');
          Writeln(LCST.DumpToString);

          // Lower to AST
          LBuilder := TDLDelphiAstBuilder.Create(LDiagnostics);
          try
            LAST := LBuilder.Build(LCST);
            try
              Writeln('--- AST ---');
              Writeln(LAST.DumpToString);

              Writeln('--- symbols (' + IntToStr(LBuilder.Symbols.Count) +
                ') ---');
              for i := 0 to LBuilder.Symbols.Count - 1 do
              begin
                LSymbol := LBuilder.Symbols[i];
                Writeln(Format('  %-8s %s', [TDLSymbolKindNames[LSymbol.Kind],
                  LSymbol.Name]));
              end;
            finally
              LAST.Free;
            end;
          finally
            LBuilder.Free;
          end;
        finally
          LCST.Free;
        end;
      finally
        LParser.Free;
      end;
    finally
      LTokens.Free;
    end;

    // Diagnostics
    Writeln('');
    Writeln('--- diagnostics (' + IntToStr(LDiagnostics.Count) + ') ---');
    for i := 0 to LDiagnostics.Count - 1 do
      Writeln('  ' + LDiagnostics[i].ToString);
    if LDiagnostics.HasErrors then
      ExitCode := 2;
  finally
    LDiagnostics.Free;
  end;
end.
