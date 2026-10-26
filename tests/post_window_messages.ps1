param(
	[Parameter(Mandatory = $true)]
	[long]$WindowHandle,
	# "message,wParam,lParam" entries in decimal, separated by semicolons.
	[Parameter(Mandatory = $true)]
	[string]$Messages
)

$ErrorActionPreference = 'Stop'
Add-Type -Namespace OpenDesktopPetTest -Name NativeMessages -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool PostMessageW(System.IntPtr window, uint message, System.IntPtr wParam, System.IntPtr lParam);
'@
foreach ($entry in $Messages.Split(';')) {
	$parts = $entry.Split(',')
	$posted = [OpenDesktopPetTest.NativeMessages]::PostMessageW(
		[System.IntPtr]$WindowHandle,
		[uint32]$parts[0],
		[System.IntPtr][long]$parts[1],
		[System.IntPtr][long]$parts[2]
	)
	if (-not $posted) {
		throw "PostMessageW failed for $entry"
	}
}
Write-Output 'POST_WINDOW_MESSAGES_OK'
