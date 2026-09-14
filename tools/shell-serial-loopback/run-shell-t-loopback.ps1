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

public static class ShellTLoopback
{
    public static int Run(string adbPath, string remoteRunner, string payloadPath, string artifactDir)
    {
        byte[] marker = Encoding.ASCII.GetBytes("SHELL_SERIAL_LOOPBACK_READY");
        byte[] payload = File.ReadAllBytes(payloadPath);
        string statusPath = Path.Combine(artifactDir, "host-loopback-status.txt");
        string outputPath = Path.Combine(artifactDir, "uart-output-raw.bin");
        string stderrPath = Path.Combine(artifactDir, "adb-shell-T.stderr.bin");
        ManualResetEventSlim markerSeen = new ManualResetEventSlim(false);
        File.WriteAllText(statusPath, "ADB_SHELL_T_STARTED_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);

        Process process = Process.Start(new ProcessStartInfo(adbPath, "shell -T sh " + remoteRunner) {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
        });

        Task output = Task.Run(() => {
            byte[] buffer = new byte[4096];
            byte[] scan = new byte[marker.Length];
            int scanCount = 0;
            using (FileStream file = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.Read)) {
                int count;
                while ((count = process.StandardOutput.BaseStream.Read(buffer, 0, buffer.Length)) > 0) {
                    file.Write(buffer, 0, count); file.Flush();
                    for (int i = 0; i < count; i++) {
                        if (buffer[i] == marker[scanCount]) {
                            scan[scanCount++] = buffer[i];
                            if (scanCount == marker.Length) markerSeen.Set();
                        } else {
                            scanCount = buffer[i] == marker[0] ? 1 : 0;
                            if (scanCount == 1) scan[0] = buffer[i];
                        }
                    }
                }
            }
        });
        Task stderr = Task.Run(() => {
            using (FileStream file = new FileStream(stderrPath, FileMode.Create, FileAccess.Write, FileShare.Read)) {
                process.StandardError.BaseStream.CopyTo(file);
            }
        });
        Task writer = Task.Run(() => {
            if (!markerSeen.Wait(15000)) {
                File.AppendAllText(statusPath, "MARKER_TIMEOUT=1" + Environment.NewLine);
                return;
            }
            process.StandardInput.BaseStream.Write(payload, 0, payload.Length);
            process.StandardInput.BaseStream.Flush();
            File.AppendAllText(statusPath, "PAYLOAD_WRITTEN=" + payload.Length + Environment.NewLine);
        });

        process.WaitForExit(40000);
        if (!process.HasExited) { process.Kill(); File.AppendAllText(statusPath, "ADB_TIMEOUT_KILLED=1" + Environment.NewLine); }
        try { Task.WaitAll(new Task[] { output, stderr, writer }, 10000); } catch { }
        File.AppendAllText(statusPath, "ADB_EXIT=" + process.ExitCode + Environment.NewLine);
        return process.ExitCode;
    }
}
'@

[ShellTLoopback]::Run($AdbPath, $RemoteRunner, $PayloadPath, $ArtifactDir)
