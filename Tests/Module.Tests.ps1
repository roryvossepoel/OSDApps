Describe 'OSDStage module' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
        $manifest = Test-ModuleManifest -Path $script:manifestPath
    }

    It 'has a valid module manifest' {
        $manifest | Should -Not -BeNullOrEmpty
        $manifest.Name | Should -Be 'OSDStage'
    }

    It 'imports successfully' {
        Get-Module OSDStage | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions declared in the manifest' {
        $declared = @((Import-PowerShellDataFile -Path $script:manifestPath).FunctionsToExport | Sort-Object)
        $exported = @(Get-Command -Module OSDStage -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        Compare-Object -ReferenceObject $declared -DifferenceObject $exported | Should -BeNullOrEmpty
    }

    It 'uses the Runtime.log default' {
        $configuration = Get-OSDStageConfiguration
        $configuration.LogPath | Should -Be '%ProgramData%\OSDStage\Logs\Runtime.log'
        $configuration.ResultPath | Should -Be '%ProgramData%\OSDStage\Results\Latest.json'
    }

    It 'uses safe default runtime configuration' {
        $configuration = Get-OSDStageConfiguration
        $configuration.CleanupMode | Should -Be 'OnSuccess'
        $configuration.CacheVolumeLabel | Should -Be 'OSDCloud'
        $configuration.Scope | Should -Be 'Session'
    }
}
