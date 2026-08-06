/// <summary>
///   DX.Delphi.Tests — DUnitX console runner for the DX.Delphi language model
///   tests.
/// </summary>
/// <remarks>
///   Build: dcc32 -U..\src -U..\libs\DUnitX\Source DX.Delphi.Tests.dpr
///   The runner auto-discovers [TestFixture] classes via RTTI from the units
///   listed in the uses clause.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
program DX.Delphi.Tests;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.TestRunner,
  DUnitX.MemoryLeakMonitor.Default,
  DUnitX.AutoDetect.Console,
  DUnitX.Windows.Console,
  Tests.DX.Delphi.Support in 'Tests.DX.Delphi.Support.pas',
  Tests.DX.Delphi.Core in 'Tests.DX.Delphi.Core.pas',
  Tests.DX.Delphi.Lexer in 'Tests.DX.Delphi.Lexer.pas',
  Tests.DX.Delphi.Lexer.Advanced in 'Tests.DX.Delphi.Lexer.Advanced.pas',
  Tests.DX.Delphi.Parser in 'Tests.DX.Delphi.Parser.pas',
  Tests.DX.Delphi.Parser.Types in 'Tests.DX.Delphi.Parser.Types.pas',
  Tests.DX.Delphi.Parser.Members in 'Tests.DX.Delphi.Parser.Members.pas',
  Tests.DX.Delphi.Parser.Statements in 'Tests.DX.Delphi.Parser.Statements.pas',
  Tests.DX.Delphi.Modules in 'Tests.DX.Delphi.Modules.pas',
  Tests.DX.Delphi.Declarations in 'Tests.DX.Delphi.Declarations.pas',
  Tests.DX.Delphi.AstBuilder in 'Tests.DX.Delphi.AstBuilder.pas',
  Tests.DX.Delphi.Ast.Lowering in 'Tests.DX.Delphi.Ast.Lowering.pas',
  Tests.DX.Delphi.Diagnostics in 'Tests.DX.Delphi.Diagnostics.pas',
  Tests.DX.Delphi.Conditions in 'Tests.DX.Delphi.Conditions.pas',
  Tests.DX.Delphi.Trivia in 'Tests.DX.Delphi.Trivia.pas',
  Tests.DX.Delphi.Rendering in 'Tests.DX.Delphi.Rendering.pas',
  Tests.DX.Delphi.RealWorld in 'Tests.DX.Delphi.RealWorld.pas',
  Tests.DX.Delphi.Samples in 'Tests.DX.Delphi.Samples.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;
begin
  try
    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    if TDUnitX.Options.ConsoleMode <> TDUnitXConsoleMode.Off then
      LRunner.AddLogger(TDUnitXConsoleLogger.Create(
        TDUnitX.Options.ConsoleMode = TDUnitXConsoleMode.Quiet));
    LResults := LRunner.Execute;
    if not LResults.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
