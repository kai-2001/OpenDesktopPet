param(
    [Parameter(Mandatory = $true)]
    [string]$SignalPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Desktop Pet Click-Through Validation Host'
$form.StartPosition = 'Manual'
$form.Bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(35, 45, 55)
$form.FormBorderStyle = 'None'
$form.TopMost = $false
$form.Add_MouseDown({
    [System.IO.File]::WriteAllText($SignalPath, 'WINDOWS_CLICK_RECEIVED')
})
$form.Show()
$form.Activate()
[System.Windows.Forms.Application]::Run($form)
