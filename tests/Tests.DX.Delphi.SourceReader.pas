/// <summary>
///   Tests.DX.Delphi.SourceReader — verifies the encoding detection of
///   DLReadSourceText: UTF-8 with BOM, UTF-16 LE with BOM, plain UTF-8,
///   and the ANSI fallback for legacy (non-UTF-8) Delphi files.
/// </summary>
/// <author>Olaf Monien</author>
/// <created>2026-08-06</created>
/// <license>MIT</license>
unit Tests.DX.Delphi.SourceReader;

interface

uses
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,
  DX.Delphi.SourceReader;

type
  [TestFixture]
  TTestSourceReader = class
  private
    function WriteTempFile(const ABytes: TBytes): string;
  public
    [Test]
    procedure ReadsUtf8WithBom;
    [Test]
    procedure ReadsPlainUtf8;
    [Test]
    procedure ReadsUtf16Le;
    [Test]
    procedure FallsBackToAnsiForLegacyFiles;
  end;

implementation

function TTestSourceReader.WriteTempFile(const ABytes: TBytes): string;
begin
  Result := TPath.GetTempFileName;
  TFile.WriteAllBytes(Result, ABytes);
end;

procedure TTestSourceReader.ReadsUtf8WithBom;
var
  LFile: string;
  LBytes: TBytes;
begin
  // EF BB BF BOM + 'unit A;'
  LBytes := TBytes.Create($EF, $BB, $BF, Ord('u'), Ord('n'), Ord('i'), Ord('t'),
    Ord(' '), Ord('A'), Ord(';'));
  LFile := WriteTempFile(LBytes);
  try
    Assert.AreEqual('unit A;', DLReadSourceText(LFile));
  finally
    TFile.Delete(LFile);
  end;
end;

procedure TTestSourceReader.ReadsPlainUtf8;
var
  LFile: string;
  LBytes: TBytes;
begin
  // 'é' as valid UTF-8 (C3 A9), no BOM.
  LBytes := TBytes.Create(Ord('a'), $C3, $A9, Ord('b'));
  LFile := WriteTempFile(LBytes);
  try
    Assert.AreEqual('a' + Char($00E9) + 'b', DLReadSourceText(LFile));
  finally
    TFile.Delete(LFile);
  end;
end;

procedure TTestSourceReader.ReadsUtf16Le;
var
  LFile: string;
  LBytes: TBytes;
begin
  // FF FE BOM + 'x' as UTF-16 LE.
  LBytes := TBytes.Create($FF, $FE, Ord('x'), 0);
  LFile := WriteTempFile(LBytes);
  try
    Assert.AreEqual('x', DLReadSourceText(LFile));
  finally
    TFile.Delete(LFile);
  end;
end;

procedure TTestSourceReader.FallsBackToAnsiForLegacyFiles;
var
  LFile: string;
  LBytes: TBytes;
  LText: string;
begin
  // 0x92 is a right single quote in Windows-1252; the byte sequence is NOT
  // valid UTF-8, so the reader must fall back to the ANSI codepage instead
  // of producing replacement characters or raising.
  LBytes := TBytes.Create(Ord('a'), $92, Ord('b'));
  LFile := WriteTempFile(LBytes);
  try
    LText := DLReadSourceText(LFile);
    Assert.IsFalse(LText.Contains(Char($FFFD)),
      'ANSI bytes must not become U+FFFD replacement characters');
    Assert.AreEqual(TEncoding.Default.GetString(LBytes), LText);
  finally
    TFile.Delete(LFile);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSourceReader);

end.
