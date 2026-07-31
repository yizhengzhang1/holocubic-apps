param(
  [Parameter(Mandatory = $true)][string]$Destination,
  [string]$HoloScript = 'C:\ws\holocubic\tools\holo.ps1',
  [ValidateSet(
    'peony', 'chrysanthemum', 'willow', 'strobe',
    'spinner', 'multibreak', 'rapidfire', 'comet',
    'waterfall', 'brocade_crown'
  )]
  [string[]]$Types = @(
    'peony', 'chrysanthemum', 'willow', 'strobe',
    'spinner', 'multibreak', 'rapidfire', 'comet',
    'waterfall', 'brocade_crown'
  )
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Destination)) {
  New-Item -ItemType Directory -Path $Destination | Out-Null
}
$destinationRoot = (Resolve-Path -LiteralPath $Destination).Path.TrimEnd('\')

. $HoloScript ip | Out-Null

foreach ($type in $Types) {
  $typeDirectory = Join-Path $Destination $type
  New-Item -ItemType Directory -Path $typeDirectory | Out-Null
  $remoteDirectory = if ($type -eq 'comet') {
    '/sd/fireworks-comet-gif'
  } elseif ($type -eq 'spinner') {
    '/sd/fireworks-spinner-gif'
  } else {
    '/sd/fireworks-gif'
  }
  foreach ($frame in 1..16) {
    $label = $frame.ToString('00')
    $remote = "$remoteDirectory/$type-$label.png"
    $local = Join-Path $typeDirectory "$label.png"
    if (-not $local.StartsWith($destinationRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to write outside destination: $local"
    }
    if ((Test-Path -LiteralPath $local) -and
        (Get-Item -LiteralPath $local).Length -eq 307528) {
      continue
    }
    if (Test-Path -LiteralPath $local) {
      Remove-Item -LiteralPath $local
    }
    Dev-Download $remote $local | Out-Null
  }
  Write-Output "downloaded $type (16/16)"
}
