# AxNetScan.ps1 -- what a .NET assembly offers, for AxStudio's .NET adaptors.
#
# Run by the studio with Windows PowerShell 5.1, which is .NET Framework 4.x:
# the same runtime AHK# hosts, so what loads here loads there.
#
#   -Dll  a.dll[;b.dll]   read these (a NuGet package's lib folder)
#   -Type System.IO.Path  or these types, from the framework itself
#   -Out  file.json       where the answer goes
#
# Nothing in the assembly runs: it is loaded REFLECTION-ONLY, which reads
# its metadata and cannot execute a line of it. Methods a step cannot call
# plainly -- generic, ref/out, pointer, taking a delegate -- are left out.
param([string]$Dll = "", [string]$Type = "", [Parameter(Mandatory = $true)][string]$Out, [int]$Max = 300)
$ErrorActionPreference = "SilentlyContinue"

$kw = @{ "System.String" = "string"; "System.Int32" = "int"; "System.Int64" = "long"; "System.Double" = "double";
         "System.Single" = "float"; "System.Boolean" = "bool"; "System.Object" = "object"; "System.Void" = "void";
         "System.Decimal" = "decimal"; "System.Byte" = "byte"; "System.Int16" = "short"; "System.UInt32" = "uint";
         "System.Char" = "char"; "System.DateTime" = "System.DateTime"; "System.TimeSpan" = "System.TimeSpan" }
function CsName($t) {
    if ($t.IsArray) { return (CsName $t.GetElementType()) + "[]" }
    $f = $t.FullName
    if (!$f) { return $null }
    if ($kw.ContainsKey($f)) { return $kw[$f] }
    if ($t.IsGenericType -or $t.IsPointer -or $t.IsByRef) { return $null }
    return $f.Replace("+", ".")
}
function Plain($t) { return (!$t.IsByRef -and !$t.IsPointer -and !$t.ContainsGenericParameters -and !$t.IsGenericType -and
                             !($t.BaseType -and $t.BaseType.FullName -eq "System.MulticastDelegate")) }

function Scan($t) {
    if (!$t.IsPublic -or $t.IsInterface -or $t.IsGenericTypeDefinition -or $t.IsNested) { return $null }
    $isStatic = $t.IsAbstract -and $t.IsSealed
    $ctor = $false
    if (!$t.IsAbstract) { foreach ($c in $t.GetConstructors()) { if ($c.IsPublic -and $c.GetParameters().Count -eq 0) { $ctor = $true } } }
    $ms = @()
    $flags = [Reflection.BindingFlags]"Public,Static,Instance,DeclaredOnly"
    foreach ($m in $t.GetMethods($flags)) {
        if ($m.IsSpecialName -or $m.IsGenericMethod) { continue }
        if (!$m.IsStatic -and !$ctor) { continue }            # an instance method needs a way to make one
        $ok = $true; $ps = @()
        foreach ($p in $m.GetParameters()) {
            if (!(Plain $p.ParameterType) -or $p.IsOut) { $ok = $false; break }
            $cs = CsName $p.ParameterType
            if (!$cs) { $ok = $false; break }
            $ps += @{ n = $p.Name; t = $p.ParameterType.Name; cs = $cs; opt = [bool]$p.IsOptional }
        }
        if (!$ok) { continue }
        $r = CsName $m.ReturnType
        if (!$r) { $r = "object" }
        $ms += @{ n = $m.Name; s = [bool]$m.IsStatic; p = $ps; r = $r }
        if ($ms.Count -ge 80) { break }
    }
    $pr = @()
    foreach ($p in $t.GetProperties([Reflection.BindingFlags]"Public,Static,DeclaredOnly")) {
        $cs = CsName $p.PropertyType
        if ($cs -and $p.CanRead -and $p.GetIndexParameters().Count -eq 0) { $pr += @{ n = $p.Name; r = $cs } }
    }
    if ($ms.Count -eq 0 -and $pr.Count -eq 0) { return $null }
    return @{ t = $t.FullName.Replace("+", "."); n = $t.Name; ns = $t.Namespace; st = $isStatic; ctor = $ctor; m = $ms; pr = $pr }
}

$types = @()
if ($Dll -ne "") {
    $dir = Split-Path ($Dll.Split(";")[0])
    [AppDomain]::CurrentDomain.add_ReflectionOnlyAssemblyResolve({
        param($s, $e)
        $n = (New-Object Reflection.AssemblyName($e.Name)).Name
        $p = Join-Path $dir ($n + ".dll")
        if (Test-Path $p) { return [Reflection.Assembly]::ReflectionOnlyLoadFrom($p) }
        return [Reflection.Assembly]::ReflectionOnlyLoad($e.Name)
    })
    foreach ($d in $Dll.Split(";")) {
        if (!(Test-Path $d)) { continue }
        $a = [Reflection.Assembly]::ReflectionOnlyLoadFrom($d)
        try { $all = $a.GetExportedTypes() } catch [Reflection.ReflectionTypeLoadException] { $all = $_.Exception.Types | Where-Object { $_ } }
        foreach ($t in $all) { $x = Scan $t; if ($x) { $types += $x }; if ($types.Count -ge $Max) { break } }
    }
} else {
    foreach ($name in $Type.Split(",")) {
        $name = $name.Trim()
        $t = [Type]::GetType($name)
        if (!$t) { foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { $t = $a.GetType($name); if ($t) { break } } }
        if (!$t) { foreach ($asm in @("System", "System.Core", "System.Xml", "System.Drawing", "System.Windows.Forms", "System.Net.Http",
                                      "System.IO.Compression", "System.IO.Compression.FileSystem", "System.Speech", "System.Web")) {
                       $a = [Reflection.Assembly]::LoadWithPartialName($asm)
                       if ($a) { $t = $a.GetType($name); if ($t) { break } } } }
        if ($t) { $x = Scan $t; if ($x) { $x.asm = $t.Assembly.GetName().Name; $types += $x } }
    }
}
$json = ConvertTo-Json -InputObject @{ types = $types } -Depth 6 -Compress
[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding($false)))
