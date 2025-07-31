Write-Host "Applying alternative project file fixes..."

$projectFiles = Get-ChildItem -Recurse -Filter "*.vcxproj"

foreach ($proj in $projectFiles) {
    Write-Host "Fixing: $($proj.Name)"

    try {
        $content = Get-Content $proj.FullName -Raw -Encoding UTF8
        $originalContent = $content

        # 建立標準的 PropertyGroup 區塊（無多餘縮排）
        $standardPropertyGroup = @"
<PropertyGroup>
  <WindowsTargetPlatformVersion>$env:WINDOWS_SDK_VERSION</WindowsTargetPlatformVersion>
  <PlatformToolset>v143</PlatformToolset>
</PropertyGroup>
"@.Trim()

        # 移除所有 WindowsTargetPlatformVersion 和 PlatformToolset 設定
        $content = $content -replace '<WindowsTargetPlatformVersion>[^<]*</WindowsTargetPlatformVersion>', ''
        $content = $content -replace '<PlatformToolset>[^<]*</PlatformToolset>', ''

        # 插入標準區塊
        if ($content -match '(<PropertyGroup[^>]*>[\s\S]*?</PropertyGroup>)') {
            $content = $content -replace '(<PropertyGroup[^>]*>[\s\S]*?</PropertyGroup>)', "`$1`n$standardPropertyGroup"
            Write-Host "  - Injected standard PropertyGroup after existing one"
        } else {
            $content = $content -replace '(<Project[^>]*>)', "`$1`n$standardPropertyGroup"
            Write-Host "  - Injected standard PropertyGroup after <Project>"
        }

        # 移除過多空行
        $content = $content -replace '(\r?\n){3,}', "`n`n"

        # 驗證是否為合法 XML
        try {
            [xml]$test = $content
        } catch {
            Write-Warning "  ⚠️ Invalid XML after patch! Skipping $($proj.Name)"
            continue
        }

        # 寫入檔案（如有改動）
        if ($content -ne $originalContent) {
            $content | Out-File $proj.FullName -Encoding UTF8 -NoNewline
            Write-Host "  ✅ Applied alternative fix to: $($proj.Name)"
        } else {
            Write-Host "  ℹ️  No changes applied to: $($proj.Name)"
        }

    } catch {
        Write-Warning "  ❌ Failed to fix $($proj.Name): $($_.Exception.Message)"
    }
}

Write-Host "`nAlternative fixes completed"
