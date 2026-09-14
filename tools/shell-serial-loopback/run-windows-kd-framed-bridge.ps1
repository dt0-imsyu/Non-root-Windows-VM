param(
    [Parameter(Mandatory = $true)] [string] $AdbPath,
    [Parameter(Mandatory = $true)] [string] $RemoteRunner,
    [Parameter(Mandatory = $true)] [string] $ArtifactDir,
    [Parameter(Mandatory = $true)] [string] $KdPath,
    [string] $PipeName = 'winavf-kd-framed-com1-20260907'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading.Tasks;
public static class WinAvfFramedKdBridge {
  static void LogCopy(Stream src, string file) { using(var f=new FileStream(file,FileMode.Create,FileAccess.Write,FileShare.Read)) { byte[] b=new byte[4096]; int n; while((n=src.Read(b,0,b.Length))>0){f.Write(b,0,n);f.Flush();} } }
  static void EncodeToAdb(Stream src, Stream dst, string file) {
    using(var log=new FileStream(file,FileMode.Create,FileAccess.Write,FileShare.Read)) {
      byte[] read=new byte[4096], pending=new byte[4098]; int carry=0,n;
      while((n=src.Read(read,0,read.Length))>0) {
        Buffer.BlockCopy(read,0,pending,carry,n); int total=carry+n, usable=total-total%3;
        if(usable>0) { log.Write(pending,0,usable); byte[] ascii=Encoding.ASCII.GetBytes(Convert.ToBase64String(pending,0,usable)); dst.Write(ascii,0,ascii.Length); dst.Flush(); }
        carry=total-usable; if(carry>0) Buffer.BlockCopy(pending,usable,pending,0,carry);
      }
      if(carry>0) { log.Write(pending,0,carry); byte[] ascii=Encoding.ASCII.GetBytes(Convert.ToBase64String(pending,0,carry)); dst.Write(ascii,0,ascii.Length); dst.Flush(); }
    }
    try { dst.Close(); } catch {}
  }
  static void DecodeFromAdb(Stream src, Stream dst, string file, string status) {
    using(var log=new FileStream(file,FileMode.Create,FileAccess.Write,FileShare.Read)) using(var r=new StreamReader(src,Encoding.ASCII,false,4096)) {
      string line; while((line=r.ReadLine())!=null) { if(!line.StartsWith("O:")){File.AppendAllText(status,"UNEXPECTED_STDOUT="+line+"\n");continue;} try { byte[] b=Convert.FromBase64String(line.Substring(2)); log.Write(b,0,b.Length);log.Flush();dst.Write(b,0,b.Length);dst.Flush(); } catch { File.AppendAllText(status,"INVALID_OUTPUT_RECORD=1\n"); } }
    }
  }
  public static int Run(string pipeName,string kdPath,string kdArgs,string adbPath,string runner,string artifactDir) {
    string status=Path.Combine(artifactDir,"bridge-status.txt");
    using(var pipe=new NamedPipeServerStream(pipeName,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous)) {
      File.WriteAllText(status,"PIPE_LISTENING_UTC="+DateTime.UtcNow.ToString("O")+"\n");
      var kdInfo=new ProcessStartInfo(); kdInfo.FileName=kdPath; kdInfo.Arguments=kdArgs; kdInfo.UseShellExecute=false; kdInfo.CreateNoWindow=true;
      var kd=Process.Start(kdInfo);
      pipe.WaitForConnection(); File.AppendAllText(status,"KD_PIPE_CONNECTED_UTC="+DateTime.UtcNow.ToString("O")+"\n");
      var adb=Process.Start(new ProcessStartInfo(adbPath,"shell -T sh "+runner){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true});
      File.AppendAllText(status,"ADB_VM_LAUNCH_UTC="+DateTime.UtcNow.ToString("O")+"\n");
      var tx=Task.Run(()=>EncodeToAdb(pipe,adb.StandardInput.BaseStream,Path.Combine(artifactDir,"raw-serial-tx.bin")));
      var rx=Task.Run(()=>DecodeFromAdb(adb.StandardOutput.BaseStream,pipe,Path.Combine(artifactDir,"raw-serial-rx.bin"),status));
      var err=Task.Run(()=>LogCopy(adb.StandardError.BaseStream,Path.Combine(artifactDir,"adb.stderr.txt")));
      adb.WaitForExit(115000); if(!adb.HasExited){adb.Kill();File.AppendAllText(status,"ADB_TIMEOUT_KILLED=1\n");}
      try{Task.WaitAll(new Task[]{tx,rx,err},10000);}catch{}
      File.AppendAllText(status,"ADB_EXIT="+adb.ExitCode+"\n"); if(!kd.WaitForExit(5000)){kd.Kill();File.AppendAllText(status,"KD_STOPPED_AFTER_RUN=1\n");} return adb.ExitCode;
    }
  }
}
'@
$target="com:pipe,port=\\.\pipe\$PipeName,baud=115200"
$args="-b -logo `"$(Join-Path $ArtifactDir 'kd.log.txt')`" -k `"$target`""
[WinAvfFramedKdBridge]::Run($PipeName,$KdPath,$args,$AdbPath,$RemoteRunner,$ArtifactDir)
