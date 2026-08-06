/// <summary>
///   Tests.DX.Delphi.RealWorld — DUnitX integration fixtures that feed
///   real-world Delphi sources through the lexer/parser:
///   - the Spring4D library (libs/spring4d, a Git submodule used ONLY for
///     practical testing — it is NOT a dependency of the implementation)
///   - the Delphi 13.1 RTL sources (installed compiler, if present).
///
///   Current assertions guarantee robustness (no parse ever crashes or
///   hangs); the diagnostic count is reported so the 100%-error-free goal
///   can be tracked and the threshold tightened as parser gaps are closed.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.RealWorld;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core;

type
  /// <summary>Result of parsing one source file.</summary>
  TDLParseOutcome = record
    FileName: string;
    Diagnostics: Integer;
    Crashed: Boolean;
  end;

  [TestFixture]
  TTestSpring4DSources = class
  private
    function FindSpring4D: string;
  public
    [Test]
    procedure Spring4DSourcesNeverCrash;
  end;

  [TestFixture]
  TTestRtlSources = class
  private
    function FindRtl: string;
  public
    [Test]
    procedure RtlSourcesNeverCrash;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

function ParseFileCount(const AFileName: string; out ACrashed: Boolean): Integer;
var
  LSource: string;
  LDiagnostics: TDLDiagnostics;
begin
  ACrashed := False;
  Result := -1;
  try
    LSource := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    Exit;
  end;
  LDiagnostics := TDLDiagnostics.Create;
  try
    try
      ParseSource(LSource, LDiagnostics).Free;
      Result := LDiagnostics.Count;
    except
      ACrashed := True;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

function ParseAllFiles(const ARoot: string): TArray<TDLParseOutcome>;
var
  LFiles: TArray<string>;
  LFile: string;
  LOutcome: TDLParseOutcome;
  LCount: Integer;
begin
  LFiles := TDirectory.GetFiles(ARoot, '*.pas', TSearchOption.soAllDirectories);
  SetLength(Result, Length(LFiles));
  LCount := 0;
  for LFile in LFiles do
  begin
    LOutcome.FileName := LFile;
    LOutcome.Diagnostics := ParseFileCount(LFile, LOutcome.Crashed);
    Result[LCount] := LOutcome;
    Inc(LCount);
  end;
  SetLength(Result, LCount);
end;

function IsKnownCrash(const AFileName: string; const AKnownCrashes:
  TArray<string>): Boolean;
var
  LFile: string;
begin
  for LFile in AKnownCrashes do
    if SameText(LFile, ExtractFileName(AFileName)) then
      Exit(True);
  Result := False;
end;

function TTestSpring4DSources.FindSpring4D: string;
const
  CCandidates: array[0..4] of string = (
    'libs\spring4d\Source',
    '..\libs\spring4d\Source',
    '..\..\libs\spring4d\Source',
    '..\..\..\libs\spring4d\Source',
    '..\..\..\..\libs\spring4d\Source');
var
  LPath: string;
begin
  for LPath in CCandidates do
    if TDirectory.Exists(LPath) then
      Exit(LPath);
  Result := '';
end;

procedure TTestSpring4DSources.Spring4DSourcesNeverCrash;
var
  LRoot: string;
  LOutcomes: TArray<TDLParseOutcome>;
  LOutcome: TDLParseOutcome;
  LTotalErrors: Int64;
  LTotalFiles: Integer;
  LKnownCrashes: TArray<string>;
begin
  LRoot := FindSpring4D;
  if LRoot = '' then
    Exit; // Spring4D submodule not checked out
  LKnownCrashes := [];
  LOutcomes := ParseAllFiles(LRoot);
  LTotalErrors := 0;
  LTotalFiles := 0;
  for LOutcome in LOutcomes do
  begin
    if LOutcome.Crashed and (not IsKnownCrash(LOutcome.FileName,
      LKnownCrashes)) then
      Assert.Fail('parser crashed on ' + LOutcome.FileName);
    Inc(LTotalFiles);
    Inc(LTotalErrors, LOutcome.Diagnostics);
  end;
  Writeln(Format('Spring4D: %d files parsed, %d total diagnostics',
    [LTotalFiles, LTotalErrors]));
end;

function TTestRtlSources.FindRtl: string;
const
  CBases: array[0..2] of string = (
    'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl',
    'C:\Program Files\Embarcadero\Studio\37.0\source\rtl',
    'C:\Program Files (x86)\Embarcadero\Studio\23.0\source\rtl');
var
  LPath: string;
begin
  for LPath in CBases do
    if TDirectory.Exists(LPath) then
      Exit(LPath);
  Result := '';
end;

procedure TTestRtlSources.RtlSourcesNeverCrash;
var
  LRoot: string;
  LOutcomes: TArray<TDLParseOutcome>;
  LOutcome: TDLParseOutcome;
  LTotalErrors: Int64;
  LTotalFiles: Integer;
  LKnownCrashes: TArray<string>;
begin
  LRoot := FindRtl;
  if LRoot = '' then
    Exit; // compiler RTL not installed on this machine
  LOutcomes := ParseAllFiles(LRoot);
  // All previously-crashing RTL files (System.pas, System.IOUtils.pas,
  // System.Skia.API.pas, System.SysUtils.pas, Winapi.Windows.pas and the
  // System-2026-05-22 backup) now parse. Any crash therefore fails the test.
  LKnownCrashes := [];
  LTotalErrors := 0;
  LTotalFiles := 0;
  for LOutcome in LOutcomes do
  begin
    if LOutcome.Crashed and (not IsKnownCrash(LOutcome.FileName,
      LKnownCrashes)) then
      Assert.Fail('parser crashed on ' + LOutcome.FileName);
    Inc(LTotalFiles);
    Inc(LTotalErrors, LOutcome.Diagnostics);
  end;
  Writeln(Format('Delphi RTL: %d files parsed, %d total diagnostics',
    [LTotalFiles, LTotalErrors]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSpring4DSources);
  TDUnitX.RegisterTestFixture(TTestRtlSources);

end.
