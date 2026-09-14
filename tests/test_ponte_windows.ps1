param([string]$Bridge = "$PSScriptRoot/../tools/ponte_serial.ps1")
$ErrorActionPreference = 'Stop'
# Exercises the real Windows PowerShell process and pipes; only the COM
# hardware and the duration of the PnP query are replaced in a temp copy.
$source = Get-Content -Raw $Bridge
$fake = @'
Add-Type -TypeDefinition @"
using System;
public class TestSerialPort : IDisposable {
 public int ReadTimeout, WriteTimeout, BaudRate;
 public string NewLine, Handshake;
 public System.Text.Encoding Encoding;
 public bool DtrEnable, RtsEnable, IsOpen;
 private DateTime next = DateTime.MinValue;
 public void Open() { IsOpen = true; }
 public void Close() { IsOpen = false; }
 public void Dispose() { Close(); }
 public void DiscardInBuffer() { }
 public void DiscardOutBuffer() { }
 public void Write(string s) { }
 public string ReadExisting() {
  if (DateTime.UtcNow < next) return "";
  next = DateTime.UtcNow.AddMilliseconds(100);
  return "PONG\n";
 }
}
"@
'@
$source = $source.Replace('$ErrorActionPreference = "Continue"', $fake + "`n" + '$ErrorActionPreference = "Continue"')
$source = $source.Replace('New-Object System.IO.Ports.SerialPort($nome, $velocidade, "None", 8, "One")', '(New-Object TestSerialPort)')
$source = $source.Replace('[System.IO.Ports.SerialPort]::GetPortNames()', '@("COM99")')
$source = $source.Replace('Get-CimInstance Win32_PnPEntity -Filter', 'Start-Sleep -Seconds 8; Get-CimInstance Win32_PnPEntity -Filter')
$temp = Join-Path ([IO.Path]::GetTempPath()) ("punch-test-" + [guid]::NewGuid() + '.ps1')
[IO.File]::WriteAllText($temp, $source, (New-Object Text.UTF8Encoding($true)))
$p = New-Object Diagnostics.Process
$p.StartInfo.FileName = "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe"
$p.StartInfo.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $temp + '"'
$p.StartInfo.UseShellExecute = $false
$p.StartInfo.CreateNoWindow = $true
$p.StartInfo.RedirectStandardInput = $true
$p.StartInfo.RedirectStandardOutput = $true
$p.StartInfo.RedirectStandardError = $true
try {
 [void]$p.Start()
 $errors = $p.StandardError.ReadToEndAsync()
 $script:pending = $p.StandardOutput.ReadLineAsync()
 function NextLine([int]$ms) {
  if (-not $script:pending.Wait($ms)) { throw "Bridge output timed out after $ms ms" }
  $line = $script:pending.Result
  if ($null -eq $line) { throw 'Bridge exited unexpectedly' }
  $script:pending = $p.StandardOutput.ReadLineAsync()
  return $line
 }
 do { $line = NextLine 20000 } until ($line -like '#PORTAS,*')
 $clock = [Diagnostics.Stopwatch]::StartNew()
 $p.StandardInput.WriteLine('@ABRIR,COM99,115200')
 $p.StandardInput.Flush()
 do { $line = NextLine 3000 } until ($line -eq '#ABERTA,COM99')
 if ($clock.Elapsed.TotalSeconds -ge 3.5) { throw 'PnP blocked opening' }
 # No stdin commands for ten seconds: autonomous serial data must flow.
 $clock.Restart()
 $samples = 0
 while ($clock.Elapsed.TotalSeconds -lt 10) {
  $line = NextLine 1500
  if ($line -eq 'PONG') { $samples++ }
  if ($line -like '#FECHADA*' -or $line -like '#FALHA*') { throw $line }
 }
 if ($samples -lt 30) { throw "Serial reads starved: $samples samples" }
 $p.StandardInput.Close()
 if (-not $p.WaitForExit(5000)) { throw 'Bridge failed to exit on stdin EOF' }
 if ($p.ExitCode -ne 0) { throw $errors.Result }
 Write-Host "WINDOWS_BRIDGE_OK: $samples autonomous samples; PnP delay did not block opening"
} finally {
 if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
 $p.Dispose()
 Remove-Item $temp -Force
}
