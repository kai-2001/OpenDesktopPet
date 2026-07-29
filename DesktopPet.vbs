Option Explicit

Dim shell, fso, base, executable, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

base = fso.GetParentFolderName(WScript.ScriptFullName)
executable = base & "\build\public\OpenDesktopPet.exe"

If Not fso.FileExists(executable) Then
  MsgBox "The packaged desktop pet was not found:" & vbCrLf & executable & vbCrLf & vbCrLf & _
    "Export Windows Public first, or use Run_Godot_Dev.cmd for source development.", _
    vbCritical, "Open Desktop Pet"
  WScript.Quit 1
End If

command = """" & executable & """"
shell.Run command, 1, False
