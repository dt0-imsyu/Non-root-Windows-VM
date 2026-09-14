param(
    [Parameter(Mandatory = $true)] [string] $AdbPath,
    [Parameter(Mandatory = $true)] [string] $RemoteRunner,
    [Parameter(Mandatory = $true)] [string] $PayloadPath,
    [Parameter(Mandatory = $true)] [string] $ArtifactDir
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
public static class ShellTBase64Loopback
{
    public static int Run(string adbPath, string remoteRunner, string payloadPath, string artifactDir)
    {
        byte[] marker = Encoding.ASCII.GetBytes("SHELL_SERIAL_LOOPBACK_READY");
        byte[] encoded = Encoding.ASCII.GetBytes(Convert.ToBase64String(File.ReadAllBytes(payloadPath)) + "\n");
        string statusPath = Path.Combine(artifactDir, "host-loopback-status.txt");
        string outputPath = Path.Combine(artifactDir, "uart-output-host-stream.bin");
        ManualResetEventSlim markerSeen = new ManualResetEventSlim(false);
        File.WriteAllText(statusPath, "ADB_SHELL_T_BASE64_STARTED_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);
        Process process = Process.Start(new ProcessStartInfo(adbPath, "shell -T sh " + remoteRunner) {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
        });
        Task output = Task.Run(() => {
            byte[] buffer = new byte[4096]; int matched = 0;
            using (FileStream file = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.Read)) {
                int count;
                while ((count = process.StandardOutput.BaseStream.Read(buffer, 0, buffer.Length)) > 0) {
                    file.Write(buffer, 0, count); file.Flush();
                    for (int i=0; i<count; i++) {
                        if (buffer[i] == marker[matched]) { if (++matched == marker.Length) markerSeen.Set(); }
                        else { matched = buffer[i] == marker[0] ? 1 : 0; }
                    }
                }
            }
        });
        Task error = Task.Run(() => File.WriteAllText(Path.Combine(artifactDir, "adb-shell-T.stderr.txt"), process.StandardError.ReadToEnd()));
        Task writer = Task.Run(() => {
            if (!markerSeen.Wait(15000)) { File.AppendAllText(statusPath, "MARKER_TIMEOUT=1\n"); return; }
            process.StandardInput.BaseStream.Write(encoded,0,encoded.Length);
            process.StandardInput.BaseStream.Flush(); process.StandardInput.Close();
            File.AppendAllText(statusPath, "BASE64_PAYLOAD_WRITTEN=" + encoded.Length + "\n");
        });
        process.WaitForExit(40000); if (!process.HasExited) { process.Kill(); File.AppendAllText(statusPath,"ADB_TIMEOUT_KILLED=1\n"); }
        try { Task.WaitAll(new Task[]{output,error,writer},10000); } catch { }
        File.AppendAllText(statusPath, "ADB_EXIT=" + process.ExitCode + "\n"); return process.ExitCode;
    }
}
'@
[ShellTBase64Loopback]::Run($AdbPath, $RemoteRunner, $PayloadPath, $ArtifactDir)
