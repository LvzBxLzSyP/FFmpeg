Write-Host "Retargeting solution to use SDK: $env:WINDOWS_SDK_VERSION"

# 找出所有 .vcxproj 檔案
$projectFiles = Get-ChildItem -Recurse -Filter "*.vcxproj"
Write-Host "Found $($projectFiles.Count) project files to update`n"

foreach ($proj in $projectFiles) {
    Write-Host "Processing: $($proj.Name)"
    
    try {
        $content = Get-Content $proj.FullName -Raw -Encoding UTF8
        $originalContent = $content

        # 備份原始檔案
        Copy-Item $proj.FullName "$($proj.FullName).bak" -Force

        # 更新 WindowsTargetPlatformVersion
        if ($content -match '<WindowsTargetPlatformVersion>([^<]*)</WindowsTargetPlatformVersion>') {
            $content = $content -replace '<WindowsTargetPlatformVersion>[^<]*</WindowsTargetPlatformVersion>', "<WindowsTargetPlatformVersion>$env:WINDOWS_SDK_VERSION</WindowsTargetPlatformVersion>"
            Write-Host "  - Updated existing WindowsTargetPlatformVersion"
        } else {
            if ($content -match '(<PropertyGroup[^>]*>)([\s\S]*?)(</PropertyGroup>)') {
                $propertyGroupStart = $matches[1]
                $propertyGroupContent = $matches[2]
                $propertyGroupEnd = $matches[3]

                if ($propertyGroupContent -match '(Configuration|Platform)') {
                    $newPropertyGroupContent = $propertyGroupContent + "`n    <WindowsTargetPlatformVersion>$env:WINDOWS_SDK_VERSION</WindowsTargetPlatformVersion>"
                    $newPropertyGroup = $propertyGroupStart + $newPropertyGroupContent + $propertyGroupEnd
                    $content = $content -replace [regex]::Escape($matches[0]), $newPropertyGroup
                    Write-Host "  - Added WindowsTargetPlatformVersion to existing PropertyGroup"
                } else {
                    $newPropertyGroup = @"
<PropertyGroup>
  <WindowsTargetPlatformVersion>$env:WINDOWS_SDK_VERSION</WindowsTargetPlatformVersion>
</PropertyGroup>
"@

                    $content = $content -replace '(</PropertyGroup>)', "`$1`n$newPropertyGroup"
                    Write-Host "  - Added new PropertyGroup with WindowsTargetPlatformVersion"
                }
            } else {
                $newPropertyGroup = @"
<PropertyGroup>
  <WindowsTargetPlatformVersion>$env:WINDOWS_SDK_VERSION</WindowsTargetPlatformVersion>
</PropertyGroup>
"@

                $content = $content -replace '(<Project[^>]*>)', "`$1`n$newPropertyGroup"
                Write-Host "  - Added new PropertyGroup after Project element"
            }
        }

        # 更新或插入 PlatformToolset
        if ($content -match '<PlatformToolset>([^<]*)</PlatformToolset>') {
            $content = $content -replace '<PlatformToolset>[^<]*</PlatformToolset>', '<PlatformToolset>v143</PlatformToolset>'
            Write-Host "  - Updated PlatformToolset to v143"
        } elseif ($content -match '(<WindowsTargetPlatformVersion>[^<]*</WindowsTargetPlatformVersion>)') {
            $line = $matches[1]
            if ($line -match '^\s*') {
                $indent = ($line -match '^\s*')[0]
            } else {
                $indent = '    '
            }
            $content = $content -replace '(<WindowsTargetPlatformVersion>[^<]*</WindowsTargetPlatformVersion>)', "`$1`n${indent}<PlatformToolset>v143</PlatformToolset>"
            Write-Host "  - Added PlatformToolset v143"
        }

        # 驗證 XML 是否正確
        try {
            [xml]$testXml = $content
        } catch {
            Write-Warning "  ⚠️  Invalid XML format after update! Reverting changes."
            Move-Item "$($proj.FullName).bak" $proj.FullName -Force
            continue
        }

        # 寫入檔案（如果有變更）
        if ($content -ne $originalContent) {
            $content | Out-File $proj.FullName -Encoding UTF8 -NoNewline
            Write-Host "  ✅ Successfully updated: $($proj.Name)"
        } else {
            Write-Host "  ℹ️  No changes needed: $($proj.Name)"
        }

    } catch {
        Write-Warning "  ❌ Failed to process $($proj.Name): $($_.Exception.Message)"
    }
}  # ⬅️ 補這個 foreach 結尾的 }

Write-Host "`nAll project files processed."
