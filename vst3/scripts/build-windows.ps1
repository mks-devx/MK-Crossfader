$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Build = Join-Path $Root "build-windows"
$ConfigureArguments = @(
    "-S", $Root,
    "-B", $Build,
    "-A", "x64"
)

if ($env:JUCE_SOURCE_DIR) {
    $ConfigureArguments += "-DFETCHCONTENT_SOURCE_DIR_JUCE=$env:JUCE_SOURCE_DIR"
}

cmake @ConfigureArguments
if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed (exit $LASTEXITCODE)." }
cmake --build $Build --config Release --parallel 4
if ($LASTEXITCODE -ne 0) { throw "CMake build failed (exit $LASTEXITCODE)." }
ctest --test-dir $Build -C Release --output-on-failure --timeout 45
if ($LASTEXITCODE -ne 0) { throw "VST3 tests failed (exit $LASTEXITCODE)." }

$Plugin = Join-Path $Build "MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3"
if (-not (Test-Path -LiteralPath $Plugin -PathType Container)) {
    throw "The VST3 bundle is missing after a successful build."
}
Write-Host $Plugin
