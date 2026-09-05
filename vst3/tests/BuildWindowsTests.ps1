$ErrorActionPreference = "Stop"
$Script = Join-Path $PSScriptRoot "../scripts/build-windows.ps1"
$global:BuildCalls = @()
$global:FailureStage = ""
$global:BundlePresent = $true

function global:cmake {
    $stage = if ($args[0] -eq "--build") { "build" } else { "configure" }
    $global:BuildCalls += $stage
    $global:LASTEXITCODE = if ($global:FailureStage -eq $stage) { 17 } else { 0 }
}
function global:ctest {
    $global:BuildCalls += "test"
    $global:LASTEXITCODE = if ($global:FailureStage -eq "test") { 19 } else { 0 }
}
function global:Test-Path { return $global:BundlePresent }

try {
    foreach ($stage in @("configure", "build", "test", "missing-bundle", "success")) {
        $global:BuildCalls = @()
        $global:FailureStage = $stage
        $global:BundlePresent = $stage -ne "missing-bundle"
        $failed = $false
        try { & $Script } catch { $failed = $true }
        if ($failed -ne ($stage -ne "success")) { throw "Unexpected result for $stage" }
        $expected = switch ($stage) {
            "configure" { "configure" }
            "build" { "configure,build" }
            default { "configure,build,test" }
        }
        if (($global:BuildCalls -join ",") -ne $expected) {
            throw "Native commands continued after failure at $stage"
        }
    }
    Write-Host "Windows build failure handling passed."
} finally {
    Remove-Item Function:\cmake, Function:\ctest, Function:\Test-Path
    Remove-Variable BuildCalls, FailureStage, BundlePresent -Scope Global
}
