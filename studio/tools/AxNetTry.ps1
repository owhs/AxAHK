# AxNetTry.ps1 -- run one .NET method now, so an adaptor can be tried before
# it is written into a program.
#
# The scanner beside this file (AxNetScan.ps1) reads what a type offers and
# never runs a line of it. This one does the opposite: it calls the method,
# with the values typed into the wizard, and says what came back. It is the
# difference between "the name looks right" and "it works" -- and it answers
# in Windows PowerShell 5.1, which is .NET Framework 4.x: the same runtime
# AHK# hosts, so what runs here runs there.
#
#   -Target System.IO.File.ReadAllText   the full name of the method
#   -Kind   static | new | prop          how it is reached
#   -Args   a.json                       a JSON array of the values, as text
#   -Dll    a.dll;b.dll                  a package's assemblies, loaded first
#   -Out    r.json                       {ok, value, type, error}
#
# IT RUNS THE METHOD. Everything it can do to this machine, it can do here:
# the studio asks before the first time, and says so each time after.
param([Parameter(Mandatory = $true)][string]$Target, [string]$Kind = "static",
      [string]$Args = "", [string]$Dll = "", [Parameter(Mandatory = $true)][string]$Out,
      [int]$Max = 4000)
$ErrorActionPreference = "Stop"

function Give($o) {
    $json = $o | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText($Out, $json, [Text.Encoding]::UTF8)
    exit 0
}
function Say($v) {
    if ($null -eq $v) { return "" }
    if ($v -is [string]) { return $v }
    if ($v -is [Array]) {
        $n = $v.Length
        $head = ($v | Select-Object -First 12 | ForEach-Object { Say $_ }) -join ", "
        return "$n item(s): $head"
    }
    try { return [string]$v } catch { return $v.GetType().FullName }
}

try {
    if ($Dll -ne "") {
        $dir = Split-Path ($Dll.Split(";")[0])
        [AppDomain]::CurrentDomain.add_AssemblyResolve({
            param($s, $e)
            $n = (New-Object Reflection.AssemblyName($e.Name)).Name
            $p = Join-Path $dir ($n + ".dll")
            if (Test-Path $p) { return [Reflection.Assembly]::LoadFrom($p) }
            return $null
        })
        foreach ($d in $Dll.Split(";")) { if (Test-Path $d) { [void][Reflection.Assembly]::LoadFrom($d) } }
    }

    $i = $Target.LastIndexOf(".")
    if ($i -lt 1) { Give @{ ok = $false; error = "The method's full name, with dots: System.IO.File.ReadAllText." } }
    $typeName = $Target.Substring(0, $i)
    $member = $Target.Substring($i + 1)

    # The framework does not load every assembly by itself: the type is looked
    # for in what is loaded, then in the assemblies the scanner's shelves need.
    $t = [Type]::GetType($typeName, $false, $true)
    if (!$t) {
        foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) {
            $t = $a.GetType($typeName, $false, $true)
            if ($t) { break }
        }
    }
    if (!$t) {
        foreach ($nm in @("System.Drawing", "System.Speech", "System.Windows.Forms", "System.Web",
                          "System.IO.Compression", "System.IO.Compression.FileSystem", "System.Net.Http",
                          "System.Xml", "System.Core", "System.Management", "WindowsBase")) {
            try { [void][Reflection.Assembly]::LoadWithPartialName($nm) } catch { }
        }
        foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) {
            $t = $a.GetType($typeName, $false, $true)
            if ($t) { break }
        }
    }
    if (!$t) { Give @{ ok = $false; error = "No .NET type called $typeName. Check the spelling, or the package it comes from." } }

    $vals = @()
    if ($Args -ne "" -and (Test-Path $Args)) {
        $raw = [IO.File]::ReadAllText($Args, [Text.Encoding]::UTF8)
        if ($raw.Trim() -ne "") {
            $parsed = $raw | ConvertFrom-Json
            if ($null -ne $parsed) { $vals = @($parsed) }
        }
    }

    if ($Kind -eq "prop") {
        $pi = $t.GetProperty($member, [Reflection.BindingFlags]"Public,Static,IgnoreCase")
        if (!$pi) { Give @{ ok = $false; error = "$typeName has no property called $member." } }
        $r = $pi.GetValue($null, $null)
        Give @{ ok = $true; value = (Say $r); type = $(if ($null -eq $r) { "nothing" } else { $r.GetType().FullName }) }
    }

    $names = "Public,IgnoreCase," + $(if ($Kind -eq "new") { "Instance" } else { "Static" })
    $flags = [Reflection.BindingFlags]$names
    $cands = @($t.GetMethods($flags) | Where-Object { $_.Name -ieq $member -and $_.GetParameters().Count -eq $vals.Count })
    if ($cands.Count -eq 0) {
        $any = @($t.GetMethods() | Where-Object { $_.Name -ieq $member })
        if ($any.Count -eq 0) { Give @{ ok = $false; error = "$typeName has no method called $member." } }
        $takes = ($any | ForEach-Object { $_.GetParameters().Count } | Sort-Object -Unique) -join " or "
        Give @{ ok = $false; error = "$member takes $takes value(s); $($vals.Count) given." }
    }

    $m = $cands[0]
    $ps = $m.GetParameters()
    $conv = New-Object object[] $ps.Count
    for ($k = 0; $k -lt $ps.Count; $k++) {
        $pt = $ps[$k].ParameterType
        $raw = $vals[$k]
        try {
            if ($pt -eq [string]) { $conv[$k] = [string]$raw }
            elseif ($pt.IsEnum) { $conv[$k] = [Enum]::Parse($pt, [string]$raw, $true) }
            elseif ($pt.IsArray -and $pt.GetElementType() -eq [string]) { $conv[$k] = @([string]$raw) }
            else { $conv[$k] = [Convert]::ChangeType($raw, $pt) }
        } catch {
            Give @{ ok = $false; error = "$($ps[$k].Name) wants $($pt.Name), and '$raw' is not one." }
        }
    }

    $inst = $null
    if ($Kind -eq "new") {
        try { $inst = [Activator]::CreateInstance($t) }
        catch { Give @{ ok = $false; error = "A new $($t.Name) could not be made: $($_.Exception.Message)" } }
    }
    $r = $m.Invoke($inst, $conv)
    if ($inst -is [IDisposable]) { try { $inst.Dispose() } catch { } }
    $txt = Say $r
    if ($txt.Length -gt $Max) { $txt = $txt.Substring(0, $Max) + " ... (" + $txt.Length + " characters)" }
    Give @{ ok = $true; value = $txt
            type = $(if ($null -eq $r) { $(if ($m.ReturnType -eq [void]) { "nothing" } else { "nothing came back" }) } else { $r.GetType().FullName }) }
}
catch {
    $e = $_.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    Give @{ ok = $false; error = $e.Message }
}
