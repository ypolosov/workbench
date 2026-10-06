param([Parameter(Mandatory=$true)][string]$Plan)
$ErrorActionPreference = 'Stop'
$wbPlanData = Get-Content -LiteralPath $Plan -Raw -Encoding UTF8 | ConvertFrom-Json
$wbOwnedEntries = @($wbPlanData.bins -split ';' | Where-Object { $_ })
$wbPathStore = [string]$wbPlanData.store
if ($wbPathStore) {
    $wbOldPath = if (Test-Path -LiteralPath $wbPathStore) { [IO.File]::ReadAllText($wbPathStore) } else { '' }
} else {
    $wbRegistry = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $wbOldPath = [string]$wbRegistry.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}
$wbOtherEntries = @($wbOldPath -split ';' | Where-Object {
    $wbEntry = $_.TrimEnd('\','/')
    $_ -and -not ($wbOwnedEntries | Where-Object { $_.TrimEnd('\','/') -ieq $wbEntry })
})
$wbNewPath = (@($wbOwnedEntries) + @($wbOtherEntries)) -join ';'
if ($wbPathStore) {
    [IO.File]::WriteAllText($wbPathStore, $wbNewPath, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($wbPathStore+'.environment.json', ($wbPlanData.variables | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
} else {
    $wbRegistry.SetValue('Path', $wbNewPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    foreach ($wbVariable in $wbPlanData.variables.PSObject.Properties) {
        $wbRegistry.SetValue($wbVariable.Name, [string]$wbVariable.Value, [Microsoft.Win32.RegistryValueKind]::String)
    }
    $wbRegistry.Dispose()
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class WorkbenchPathNotice { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wparam, string value, uint flags, uint timeout, out UIntPtr result); }'
    $wbNoticeResult = [UIntPtr]::Zero
    [void][WorkbenchPathNotice]::SendMessageTimeout([IntPtr]0xffff,0x1a,[UIntPtr]::Zero,'Environment',2,5000,[ref]$wbNoticeResult)
}
