/// <summary>
///   Tests.DX.Delphi.Samples — DUnitX integration test: the shipped
///   samples\Demo.pas (if found) must lex, parse and lower without any
///   diagnostics, and must expose the expected top-level declarations.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-04</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.Samples;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DUnitX.TestFramework,
  DX.Delphi.Core,
  DX.Delphi.AST;

type
  [TestFixture]
  TTestSample = class
  private
    function FindSampleFile: string;
  public
    [Test]
    procedure SampleParsesWithoutErrors;
    [Test]
    procedure SampleContainsExpectedDeclarations;
  end;

implementation

uses
  Tests.DX.Delphi.Support;

function TTestSample.FindSampleFile: string;
const
  CCandidates: array[0..5] of string = (
    'samples\Demo.pas',
    '..\samples\Demo.pas',
    '..\..\samples\Demo.pas',
    '..\..\..\samples\Demo.pas',
    '..\..\..\..\samples\Demo.pas',
    'samples/Demo.pas');
var
  LPath: string;
begin
  for LPath in CCandidates do
    if FileExists(LPath) then
      Exit(LPath);
  Result := '';
end;

procedure TTestSample.SampleParsesWithoutErrors;
var
  LFileName: string;
  LSource: string;
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
begin
  LFileName := FindSampleFile;
  if LFileName = '' then
    Exit; // sample not present in this environment; nothing to verify
  LSource := TFile.ReadAllText(LFileName, TEncoding.UTF8);
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(LSource, LDiagnostics);
    try
      Assert.AreEqual(0, LDiagnostics.Count,
        'sample produced diagnostics: ' + IntToStr(LDiagnostics.Count));
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

procedure TTestSample.SampleContainsExpectedDeclarations;
var
  LFileName: string;
  LSource: string;
  LDiagnostics: TDLDiagnostics;
  LModule: TDLModule;
  LDecl: TDLDeclaration;
  LFoundType: Boolean;
  LFoundProc: Boolean;
begin
  LFileName := FindSampleFile;
  if LFileName = '' then
    Exit;
  LSource := TFile.ReadAllText(LFileName, TEncoding.UTF8);
  LDiagnostics := TDLDiagnostics.Create;
  try
    LModule := BuildAst(LSource, LDiagnostics);
    try
      LFoundType := False;
      LFoundProc := False;
      for LDecl in LModule.Declarations do
      begin
        if (LDecl is TDLTypeDecl) and (TDLTypeDecl(LDecl).Name = 'TDay') then
          LFoundType := True;
        if (LDecl is TDLProcDecl) and (TDLProcDecl(LDecl).Name = 'Compute') then
          LFoundProc := True;
      end;
      Assert.IsTrue(LFoundType, 'TDay type not found in sample');
      Assert.IsTrue(LFoundProc, 'Compute procedure not found in sample');
    finally
      LModule.Free;
    end;
  finally
    LDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSample);

end.
