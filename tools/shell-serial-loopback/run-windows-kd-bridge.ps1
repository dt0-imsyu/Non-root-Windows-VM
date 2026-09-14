param(
    [Parameter(Mandatory = $true)] [string] $AdbPath,
    [Parameter(Mandatory = $true)] [string] $RemoteRunner,
    [Parameter(Mandatory = $true)] [string] $ArtifactDir,
    [Parameter(Mandatory = $true)] [string] $KdPath,
    [string] $PipeName = 'winavf-kd-com1-20260907'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;

public static class WinAvfKdBridge
{
    private static void Copy(Stream input, Stream output, string logPath)
    {
        byte[] buffer = new byte[4096];
        using (FileStream log = new FileStream(logPath, FileMode.Create, FileAccess.Write, FileShare.Read))
        {
            try
            {
                int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    log.Write(buffer, 0, count);
                    log.Flush();
                    output.Write(buffer, 0, count);
                    output.Flush();
                }
            }
            catch (IOException) { }
            finally { try { output.Close(); } catch { } }
        }
    }

    private static void CopyToFile(Stream input, string logPath)
    {
        byte[] buffer = new byte[4096];
        using (FileStream log = new FileStream(logPath, FileMode.Create, FileAccess.Write, FileShare.Read))
        {
            try
            {
                int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    log.Write(buffer, 0, count);
                    log.Flush();
                }
            }
            catch (IOException) { }
        }
    }

    public static int Run(string pipeName, string kdPath, string kdArgs, string adbPath,
                          string adbArgs, string artifactDir)
    {
        string statusPath = Path.Combine(artifactDir, "bridge-status.txt");
        string kdLog = Path.Combine(artifactDir, "kd.log.txt");
        string serialRx = Path.Combine(artifactDir, "raw-serial-rx.bin");
        string serialTx = Path.Combine(artifactDir, "raw-serial-tx.bin");
        string adbErr = Path.Combine(artifactDir, "adb-exec-out.stderr.bin");

        using (NamedPipeServerStream pipe = new NamedPipeServerStream(
            pipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous))
        {
            File.WriteAllText(statusPath, "PIPE_LISTENING_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);
            Process kd = Process.Start(new ProcessStartInfo(kdPath, kdArgs) {
                UseShellExecute = false, CreateNoWindow = true
            });

            pipe.WaitForConnection();
            File.AppendAllText(statusPath, "KD_PIPE_CONNECTED_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);

            Process adb = Process.Start(new ProcessStartInfo(adbPath, adbArgs) {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
            });
            File.AppendAllText(statusPath, "ADB_VM_LAUNCH_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);

            Task tx = Task.Run(() => Copy(pipe, adb.StandardInput.BaseStream, serialTx));
            Task rx = Task.Run(() => Copy(adb.StandardOutput.BaseStream, pipe, serialRx));
            Task err = Task.Run(() => CopyToFile(adb.StandardError.BaseStream, adbErr));

            adb.WaitForExit(115000);
            if (!adb.HasExited) {
                try { adb.Kill(); } catch { }
                File.AppendAllText(statusPath, "ADB_TIMEOUT_KILLED=1" + Environment.NewLine);
            }
            try { Task.WaitAll(new Task[] { tx, rx, err }, 10000); } catch { }
            File.AppendAllText(statusPath, "ADB_EXIT=" + adb.ExitCode + Environment.NewLine);

            if (!kd.WaitForExit(5000)) {
                try { kd.Kill(); } catch { }
                File.AppendAllText(statusPath, "KD_STOPPED_AFTER_RUN=1" + Environment.NewLine);
            }
            File.AppendAllText(statusPath, "BRIDGE_END_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);
            return adb.ExitCode;
        }
    }
}
'@

$pipeTarget = "com:pipe,port=\\.\pipe\$PipeName,baud=115200"
$kdLog = Join-Path $ArtifactDir 'kd.log.txt'
$kdArgs = "-b -logo `"$kdLog`" -k `"$pipeTarget`" -c `"r; k; lm; !thread; !irql`""
$adbArgs = "exec-out sh $RemoteRunner"
[WinAvfKdBridge]::Run($PipeName, $KdPath, $kdArgs, $AdbPath, $adbArgs, $ArtifactDir)
