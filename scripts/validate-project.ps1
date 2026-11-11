$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    'project.yml',
    'Shared/SharedClipboardStore.swift',
    'SuperTecladoApp/Models/ClipboardItem.swift',
    'SuperTecladoApp/Services/KeyboardHistorySync.swift',
    'SuperTecladoKeyboard/KeyboardViewController.swift',
    'SuperTecladoKeyboard/KeyboardEngine.swift',
    'SuperTecladoKeyboard/Views/KeyGridUIView.swift',
    'SuperTecladoShare/ShareViewController.swift',
    'SuperTecladoWidget/SuperTecladoWidgets.swift',
    'SharedIntents/ClipboardSharedIntents.swift',
    'SuperTecladoTests/ClipboardRetentionPolicyTests.swift',
    'SuperTecladoApp/Assets.xcassets/AppIcon.appiconset/Contents.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf)) {
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
$versions = @([regex]::Matches($projectSpec, 'MARKETING_VERSION:\s*"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$builds = @([regex]::Matches($projectSpec, 'CURRENT_PROJECT_VERSION:\s*"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$packageVersion = [regex]::Match($packageSpec, 'displayVersion:\s*"([^"]+)"').Groups[1].Value
$packageBuild = [regex]::Match($packageSpec, 'bundleVersion:\s*"([^"]+)"').Groups[1].Value
if ($versions.Count -ne 4 -or @($versions | Select-Object -Unique).Count -ne 1 -or
    -not $packageVersion -or $versions[0] -ne $packageVersion) {
    throw 'La version debe coincidir en la app, las tres extensiones y Swift Package.'
}
if ($builds.Count -ne 4 -or @($builds | Select-Object -Unique).Count -ne 1 -or
    -not $packageBuild -or $builds[0] -ne $packageBuild) {
    throw 'La compilacion debe coincidir en la app, las tres extensiones y Swift Package.'
}

$appGroup = $null
foreach ($target in 'SuperTecladoApp', 'SuperTecladoKeyboard', 'SuperTecladoShare', 'SuperTecladoWidget') {
    $entitlementFile = Get-ChildItem -LiteralPath (Join-Path $projectRoot $target) -Filter '*.entitlements' -File
    if (@($entitlementFile).Count -ne 1) { throw "Entitlements ausentes o ambiguos en $target" }
    [xml]$entitlements = Get-Content -LiteralPath $entitlementFile.FullName -Raw
    $groupNode = $entitlements.SelectSingleNode("//key[.='com.apple.security.application-groups']/following-sibling::array[1]/string")
    if (-not $groupNode) { throw "Falta el App Group en $target" }
    if ($null -eq $appGroup) { $appGroup = $groupNode.InnerText }
    elseif ($groupNode.InnerText -ne $appGroup) { throw "El App Group de $target no coincide con la app." }
}

$iconDirectory = Join-Path $projectRoot 'SuperTecladoApp/Assets.xcassets/AppIcon.appiconset'
$icon = Get-Content -LiteralPath (Join-Path $iconDirectory 'Contents.json') -Raw | ConvertFrom-Json
$iconFiles = @($icon.images | Where-Object { $_.filename })
if ($iconFiles.Count -eq 0) { throw 'El catalogo AppIcon no declara ninguna imagen.' }
foreach ($image in $iconFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $iconDirectory $image.filename) -PathType Leaf)) {
        throw "Falta la imagen del icono: $($image.filename)"
    }
}

# No se cuentan llaves: cadenas, interpolaciones y comentarios producen falsos errores.
# La sintaxis Swift, UIKit y el comportamiento se comprueban con Xcode/XCTest en CI.
Write-Output "Estructura y metadatos correctos: Super Teclado $($versions[0]), compilacion $($builds[0])."
Write-Output "App Group verificado en la app y las tres extensiones: $appGroup"
Write-Output 'Esta comprobacion no sustituye la compilacion ni las pruebas de GitHub Actions.'
