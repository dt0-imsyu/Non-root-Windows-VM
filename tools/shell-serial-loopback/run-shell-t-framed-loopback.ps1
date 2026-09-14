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
public static class ShellTFramedLoopback
{
    public static int Run(string adbPath, string runner, string payloadPath, string artifactDir)
    {
        byte[] marker = Encoding.ASCII.GetBytes("SHELL_SERIAL_LOOPBACK_READY");
        byte[] payload = File.ReadAllBytes(payloadPath);
        string status = Path.Combine(artifactDir, "host-loopback-status.txt");
        string output = Path.Combine(artifactDir, "uart-output-decoded.bin");
        ManualResetEventSlim ready = new ManualResetEventSlim(false);
        ManualResetEventSlim complete = new ManualResetEventSlim(false);
        File.WriteAllText(status, "FRAMED_ADB_STARTED_UTC=" + DateTime.UtcNow.ToString("O") + Environment.NewLine);
        Process p = Process.Start(new ProcessStartInfo(adbPath, "shell -T sh " + runner) {
            UseShellExecute=false, CreateNoWindow=true, RedirectStandardInput=true,
            RedirectStandardOutput=true, RedirectStandardError=true
        });
        Task rx = Task.Run(() => {
            int matched=0; long total=0;
            using (FileStream f=new FileStream(output,FileMode.Create,FileAccess.Write,FileShare.Read))
            using (StreamReader r=new StreamReader(p.StandardOutput.BaseStream,Encoding.ASCII,false,4096)) {
                string line;
                while ((line=r.ReadLine()) != null) {
                    if (!line.StartsWith("O:")) { File.AppendAllText(status,"UNEXPECTED_STDOUT="+line+"\n"); continue; }
                    byte[] data;
                    try { data=Convert.FromBase64String(line.Substring(2)); }
                    catch { File.AppendAllText(status,"INVALID_OUTPUT_RECORD=1\n"); continue; }
                    f.Write(data,0,data.Length); f.Flush(); total += data.Length;
                    foreach (byte b in data) {
                        if (b==marker[matched]) {
                            if (++matched==marker.Length) { ready.Set(); matched=0; }
                        }
                        else matched = b==marker[0] ? 1 : 0;
                    }
                    if (total >= marker.Length + payload.Length) complete.Set();
                }
            }
        });
        Task err = Task.Run(() => File.WriteAllText(Path.Combine(artifactDir,"adb-shell-T.stderr.txt"),p.StandardError.ReadToEnd()));
        Task tx = Task.Run(() => {
            if (!ready.Wait(15000)) { File.AppendAllText(status,"MARKER_TIMEOUT=1\n"); return; }
            string frame=Convert.ToBase64String(payload)+"\n";
            p.StandardInput.Write(frame); p.StandardInput.Flush();
            if (!complete.Wait(15000)) File.AppendAllText(status,"OUTPUT_TIMEOUT=1\n");
            p.StandardInput.Close();
            File.AppendAllText(status,"INPUT_FRAME_BYTES="+frame.Length+"\n");
        });
        p.WaitForExit(40000);
        if (!p.HasExited) { p.Kill(); File.AppendAllText(status,"ADB_TIMEOUT_KILLED=1\n"); }
        try { Task.WaitAll(new Task[]{rx,err,tx},10000); } catch { }
        File.AppendAllText(status,"ADB_EXIT="+p.ExitCode+"\n");
        return p.ExitCode;
    }
}
'@

[ShellTFramedLoopback]::Run($AdbPath, $RemoteRunner, $PayloadPath, $ArtifactDir)
