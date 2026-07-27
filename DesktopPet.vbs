Option Explicit

Dim shell, fso, base, godot, logFile, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

base = fso.GetParentFolderName(WScript.ScriptFullName)
godot = "C:\Apache24\tools\godot-4.6.3\Godot_v4.6.3-stable_win64.exe"
logFile = base & "\godot-launch.log"

If Not fso.FileExists(godot) Then
  MsgBox "Godot 4.6.3 portable editor not found:" & vbCrLf & godot, vbCritical, "Open Desktop Pet"
  WScript.Quit 1
End If

command = """" & godot & """ --path """ & base & """ --log-file """ & logFile & """"
shell.Run command, 0, False
