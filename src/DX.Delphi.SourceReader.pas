/// <summary>
///   DX.Delphi.SourceReader — reads Delphi source files with encoding
///   detection. Older Delphi projects are frequently ANSI (Windows-1252)
///   encoded instead of UTF-8, so a plain UTF-8 read rejects them.
/// </summary>
/// <remarks>
///   Strategy:
///     - a byte-order mark (UTF-8 / UTF-16 LE / UTF-16 BE) selects the
///       encoding;
///     - without a BOM the bytes are validated as strict UTF-8 (the
///       project's own convention is UTF-8 with BOM);
///     - if that fails, the bytes are decoded with the ANSI system
///       codepage (Windows-1252 on Western Windows), which is what legacy
///       Delphi files use.
/// </remarks>
/// <author>Olaf Monien</author>
/// <created>2026-08-06</created>
/// <license>MIT</license>
unit DX.Delphi.SourceReader;

interface

uses
  System.SysUtils,
  System.Classes;

/// <summary>Reads and decodes a Delphi source file (see unit remarks).</summary>
function DLReadSourceText(const AFileName: string): string;

implementation

/// <summary>Strict UTF-8 validation: every multi-byte sequence must have
/// well-formed leading and continuation bytes. TEncoding.UTF8.GetString
/// silently replaces invalid sequences, so this is needed to distinguish
/// true UTF-8 from ANSI content.</summary>
function IsValidUtf8(const ABytes: TBytes): Boolean;
var
  i, LSeqLen, k: Integer;
  LByte: Byte;
begin
  i := 0;
  while i < Length(ABytes) do
  begin
    LByte := ABytes[i];
    if LByte < $80 then
      LSeqLen := 1
    else if (LByte and $E0) = $C0 then
      LSeqLen := 2
    else if (LByte and $F0) = $E0 then
      LSeqLen := 3
    else if (LByte and $F8) = $F0 then
      LSeqLen := 4
    else
      Exit(False);
    if i + LSeqLen > Length(ABytes) then
      Exit(False);
    for k := 1 to LSeqLen - 1 do
      if (ABytes[i + k] and $C0) <> $80 then
        Exit(False);
    Inc(i, LSeqLen);
  end;
  Result := True;
end;

function DLReadSourceText(const AFileName: string): string;
var
  LStream: TFileStream;
  LBytes: TBytes;
begin
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(LBytes, LStream.Size);
    if Length(LBytes) > 0 then
      LStream.ReadBuffer(LBytes[0], Length(LBytes));
  finally
    LStream.Free;
  end;

  // BOM-based decoding.
  if (Length(LBytes) >= 3) and (LBytes[0] = $EF) and (LBytes[1] = $BB) and
     (LBytes[2] = $BF) then
  begin
    Result := TEncoding.UTF8.GetString(LBytes, 3, Length(LBytes) - 3);
    Exit;
  end;
  if (Length(LBytes) >= 2) and (LBytes[0] = $FF) and (LBytes[1] = $FE) then
  begin
    Result := TEncoding.Unicode.GetString(LBytes, 2, Length(LBytes) - 2);
    Exit;
  end;
  if (Length(LBytes) >= 2) and (LBytes[0] = $FE) and (LBytes[1] = $FF) then
  begin
    Result := TEncoding.BigEndianUnicode.GetString(LBytes, 2, Length(LBytes) - 2);
    Exit;
  end;

  // No BOM: strict UTF-8 first, ANSI system codepage as the legacy fallback.
  if IsValidUtf8(LBytes) then
    Result := TEncoding.UTF8.GetString(LBytes)
  else
    Result := TEncoding.Default.GetString(LBytes);
end;

end.
