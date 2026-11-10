$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    'project.yml',
    'SuperTecladoApp/Models/ClipboardItem.swift',
    'SuperTecladoApp/Services/ClipboardRetentionPolicy.swift',
    'SuperTecladoApp/Views/ContentView.swift',
    'SuperTecladoKeyboard/KeyboardViewController.swift',
    'SuperTecladoTests/ClipboardRetentionPolicyTests.swift'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Falta el archivo obligatorio: $relativePath"
    }
}

$xmlFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object { $_.Extension -in '.plist', '.entitlements' }
foreach ($file in $xmlFiles) {
    [xml](Get-Content -LiteralPath $file.FullName -Raw) | Out-Null
}

$projectSpec = Get-Content -LiteralPath (Join-Path $projectRoot 'project.yml') -Raw
$packageSpec = Get-Content -LiteralPath (Join-Path $projectRoot 'SuperTecladoApp/Package.swift') -Raw
$projectVersion = [regex]::Match($projectSpec, 'MARKETING_VERSION:\s*"([^"]+)"').Groups[1].Value
$packageVersion = [regex]::Match($packageSpec, 'displayVersion:\s*"([^"]+)"').Groups[1].Value
if (-not $projectVersion -or $projectVersion -ne $packageVersion) {
    throw "Las versiones de XcodeGen ($projectVersion) y Swift Package ($packageVersion) no coinciden."
}

$appEntitlements = Get-Content -LiteralPath (Join-Path $projectRoot 'SuperTecladoApp/SuperTeclado.entitlements') -Raw
$keyboardEntitlements = Get-Content -LiteralPath (Join-Path $projectRoot 'SuperTecladoKeyboard/SuperTecladoKeyboard.entitlements') -Raw
$appGroupPattern = 'group\.[^<\s]+'
$appGroup = [regex]::Match($appEntitlements, $appGroupPattern).Value
$keyboardGroup = [regex]::Match($keyboardEntitlements, $appGroupPattern).Value
if (-not $appGroup -or $appGroup -ne $keyboardGroup) {
    throw 'Los App Groups de la aplicación y del teclado no coinciden.'
}

$contentView = Get-Content -LiteralPath (Join-Path $projectRoot 'SuperTecladoApp/Views/ContentView.swift') -Raw
foreach ($marker in 'isTemporary: true', 'promoteToPermanent()', 'captureAutomaticallyIfNeeded()', 'cleanExpiredItems()') {
    if (-not $contentView.Contains($marker)) {
        throw "Falta una regla del flujo temporal: $marker"
    }
}

$keyboard = Get-Content -LiteralPath (Join-Path $projectRoot 'SuperTecladoKeyboard/KeyboardViewController.swift') -Raw
foreach ($marker in 'captureClipboardAsTemporaryIfNeeded()', 'SharedClipboardStore.captureTemporaryText') {
    if (-not $keyboard.Contains($marker)) {
        throw "Falta la captura temporal desde el teclado: $marker"
    }
}

$sync = Get-Content -LiteralPath (Join-Path $projectRoot 'SuperTecladoApp/Services/KeyboardHistorySync.swift') -Raw
foreach ($marker in 'importTemporaryInbox(into: context, storage: storage)', 'SharedClipboardStore.replaceTemporaryInbox(') {
    if (-not $sync.Contains($marker)) {
        throw "Falta la importación de temporales del teclado: $marker"
    }
}

$swiftFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -Filter '*.swift' -File
foreach ($file in $swiftFiles) {
    $source = Get-Content -LiteralPath $file.FullName -Raw
    $openingBraces = ([regex]::Matches($source, '\{')).Count
    $closingBraces = ([regex]::Matches($source, '\}')).Count
    if ($openingBraces -ne $closingBraces) {
        throw "Llaves desequilibradas en $($file.FullName)"
    }
}

Write-Output "Validación estática correcta para Super Teclado $projectVersion."
Write-Output "App Group verificado: $appGroup"
Write-Output "Archivos Swift comprobados: $($swiftFiles.Count)"
