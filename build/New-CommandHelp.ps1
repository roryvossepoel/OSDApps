[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [string]$HelpDataPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'help\CommandHelp.psd1')
)

$ErrorActionPreference = 'Stop'
$data = Import-PowerShellDataFile -LiteralPath $HelpDataPath -ErrorAction Stop
if ($data.SchemaVersion -ne 1) { throw 'Unsupported command-help schema.' }
$moduleRoot = (Resolve-Path -LiteralPath $ModulePath).Path
$manifestPath = Join-Path $moduleRoot 'OSDApps.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
$module = Import-Module $manifestPath -Force -PassThru -ErrorAction Stop
$names = @($manifest.FunctionsToExport | Sort-Object)
$unknown = @($data.Commands.Keys | Where-Object { $_ -notin $names })
if ($unknown.Count) { throw "Help names are not exported: $($unknown -join ', ')" }

$common = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction',
    'ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')
$data.CommonParameters['WhatIf'] = 'Request a preview for operations using ShouldProcess. Read the command description for any documented limitations; this is not a universal transaction guarantee.'
$data.CommonParameters['Confirm'] = 'Request confirmation for operations using ShouldProcess. Read the command description for any documented limitations.'

$maml = 'http://schemas.microsoft.com/maml/2004/10'
$commandNs = 'http://schemas.microsoft.com/maml/dev/command/2004/10'
$dev = 'http://schemas.microsoft.com/maml/dev/2004/10'
$destination = Join-Path $moduleRoot 'OSDApps-help.xml'
$temp = "$destination.tmp"
$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$settings.NewLineChars = "`n"
$writer = [System.Xml.XmlWriter]::Create($temp, $settings)

function Write-HelpText {
    param([string]$Prefix,[string]$Name,[string]$Namespace,[string]$Value)
    $writer.WriteElementString($Prefix,$Name,$Namespace,$Value)
}
function Write-HelpParagraph {
    param([string]$Text)
    Write-HelpText -Prefix 'maml' -Name 'para' -Namespace $maml -Value $Text
}
function Write-HelpParameter {
    param($Parameter,[string]$Description,[string]$DefaultText,[bool]$Syntax)
    $writer.WriteStartElement('command','parameter',$commandNs)
    $writer.WriteAttributeString('required',([string][bool]$Parameter.IsMandatory).ToLowerInvariant())
    $writer.WriteAttributeString('position',$(if ($Parameter.Position -lt 0) { 'named' } else { [string]$Parameter.Position }))
    $pipeline = if ($Parameter.ValueFromPipeline -and $Parameter.ValueFromPipelineByPropertyName) {
        'true (ByValue, ByPropertyName)'
    } elseif ($Parameter.ValueFromPipeline) { 'true (ByValue)' }
    elseif ($Parameter.ValueFromPipelineByPropertyName) { 'true (ByPropertyName)' } else { 'false' }
    $writer.WriteAttributeString('pipelineInput',$pipeline)
    Write-HelpText 'maml' 'name' $maml $Parameter.Name
    if (-not $Syntax) {
        $writer.WriteStartElement('maml','description',$maml)
        Write-HelpParagraph $Description
        $writer.WriteEndElement()
    }
    if ($Parameter.ParameterType -ne [System.Management.Automation.SwitchParameter]) {
        $writer.WriteStartElement('command','parameterValue',$commandNs)
        $writer.WriteAttributeString('required','true')
        $writer.WriteAttributeString('variableLength',([string]$Parameter.ParameterType.IsArray).ToLowerInvariant())
        $writer.WriteString($Parameter.ParameterType.Name)
        $writer.WriteEndElement()
    }
    if (-not $Syntax) {
        $writer.WriteStartElement('dev','type',$dev)
        Write-HelpText 'maml' 'name' $maml $Parameter.ParameterType.FullName
        $writer.WriteEndElement()
        Write-HelpText 'dev' 'defaultValue' $dev $DefaultText
    }
    $writer.WriteEndElement()
}

try {
    $writer.WriteStartDocument()
    $writer.WriteStartElement('helpItems')
    $writer.WriteAttributeString('schema','maml')
    $writer.WriteAttributeString('xmlns','maml',$null,$maml)
    $writer.WriteAttributeString('xmlns','command',$null,$commandNs)
    $writer.WriteAttributeString('xmlns','dev',$null,$dev)
    foreach ($name in $names) {
        $spec = $data.Commands[$name]
        foreach ($field in @('Synopsis','Description','Environment','Output','Link')) {
            if (-not $spec -or [string]::IsNullOrWhiteSpace([string]$spec[$field])) {
                throw "Missing help $field for $name."
            }
        }
        if (@($spec.Examples).Count -eq 0) { throw "No examples for $name." }
        $cmd = $module.ExportedFunctions[$name]
        if (-not $cmd) { throw "Function $name is unavailable in the built module." }
        $defaults = @{}
        $bodyAst = $cmd.ScriptBlock.Ast
        if ($bodyAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $bodyAst = $bodyAst.Body
        }
        $parameterAsts = @()
        if ($bodyAst -is [System.Management.Automation.Language.ScriptBlockAst] -and $bodyAst.ParamBlock) {
            $parameterAsts = @($bodyAst.ParamBlock.Parameters)
        }
        foreach ($parameterAst in $parameterAsts) {
            if ($parameterAst.DefaultValue) {
                $defaults[$parameterAst.Name.VariablePath.UserPath] = $parameterAst.DefaultValue.Extent.Text
            }
        }
        $documented = @{}
        foreach ($set in $cmd.ParameterSets) {
            foreach ($p in $set.Parameters) {
                if ($p.Name -notin $common -and -not $documented.ContainsKey($p.Name)) { $documented[$p.Name] = $p }
            }
        }
        if ($spec['Parameters']) {
            foreach ($parameterName in $spec['Parameters'].Keys) {
                if (-not $documented.ContainsKey($parameterName)) { throw "Unknown help parameter $name/$parameterName." }
            }
        }
        $writer.WriteStartElement('command','command',$commandNs)
        $writer.WriteStartElement('command','details',$commandNs)
        Write-HelpText 'command' 'name' $commandNs $name
        $writer.WriteStartElement('maml','description',$maml)
        Write-HelpParagraph $spec.Synopsis
        $writer.WriteEndElement()
        $parts = $name -split '-',2
        Write-HelpText 'command' 'verb' $commandNs $parts[0]
        Write-HelpText 'command' 'noun' $commandNs $parts[1]
        $writer.WriteEndElement()
        $writer.WriteStartElement('maml','description',$maml)
        Write-HelpParagraph $spec.Description
        Write-HelpParagraph ("Execution environment: " + $spec.Environment)
        $writer.WriteEndElement()
        $writer.WriteStartElement('command','syntax',$commandNs)
        foreach ($set in $cmd.ParameterSets) {
            $writer.WriteStartElement('command','syntaxItem',$commandNs)
            Write-HelpText 'maml' 'name' $maml $name
            foreach ($p in $set.Parameters) {
                if ($p.Name -notin $common) { Write-HelpParameter -Parameter $p -Syntax $true }
            }
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()
        $writer.WriteStartElement('command','parameters',$commandNs)
        foreach ($parameterName in @($documented.Keys | Sort-Object)) {
            $p = $documented[$parameterName]
            $description = if ($spec['Parameters'] -and $spec['Parameters'].ContainsKey($parameterName)) {
                [string]$spec['Parameters'][$parameterName]
            } else { [string]$data.CommonParameters[$parameterName] }
            if ([string]::IsNullOrWhiteSpace($description)) { throw "No help for parameter $name/$parameterName." }
            $valid = @($cmd.Parameters[$parameterName].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
            if ($valid.Count) { $description += ' Allowed values: ' + (@($valid[0].ValidValues) -join ', ') + '.' }
            $defaultText = if ($defaults.ContainsKey($parameterName)) { $defaults[$parameterName] } else { 'Not explicitly set in the function declaration.' }
            Write-HelpParameter -Parameter $p -Description $description -DefaultText $defaultText -Syntax $false
        }
        $writer.WriteEndElement()
        $writer.WriteStartElement('command','inputTypes',$commandNs)
        $writer.WriteStartElement('command','inputType',$commandNs)
        $writer.WriteStartElement('dev','type',$dev)
        $acceptsPipeline = @($documented.Values | Where-Object { $_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName }).Count -gt 0
        Write-HelpText 'maml' 'name' $maml $(if ($acceptsPipeline) { 'System.String' } else { 'None' })
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteStartElement('command','returnValues',$commandNs)
        $writer.WriteStartElement('command','returnValue',$commandNs)
        $writer.WriteStartElement('dev','type',$dev)
        Write-HelpText 'maml' 'name' $maml $(if ($name -eq 'Show-OSDAppUI') { 'None' } else { 'System.Management.Automation.PSObject' })
        $writer.WriteEndElement()
        $writer.WriteStartElement('maml','description',$maml)
        Write-HelpParagraph $spec.Output
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteStartElement('command','examples',$commandNs)
        $i = 0
        foreach ($example in $spec.Examples) {
            $i++
            if ([string]::IsNullOrWhiteSpace([string]$example.Code) -or [string]::IsNullOrWhiteSpace([string]$example.Remarks)) {
                throw "Incomplete example $i for $name."
            }
            $writer.WriteStartElement('command','example',$commandNs)
            Write-HelpText 'maml' 'title' $maml ("Example ${i}: $name")
            Write-HelpText 'dev' 'code' $dev $example.Code
            $writer.WriteStartElement('dev','remarks',$dev)
            Write-HelpParagraph $example.Remarks
            $writer.WriteEndElement()
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()
        $writer.WriteStartElement('command','relatedLinks',$commandNs)
        $writer.WriteStartElement('maml','navigationLink',$maml)
        Write-HelpText 'maml' 'linkText' $maml 'OSDApps documentation'
        Write-HelpText 'maml' 'uri' $maml ('https://github.com/roryvossepoel/OSDApps/blob/main/' + $spec.Link)
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
    }
    $writer.WriteEndElement()
    $writer.WriteEndDocument()
}
finally { $writer.Dispose() }

# Verify generated XML before replacing the package's help file.
[xml]$parsed = Get-Content -LiteralPath $temp -Raw -Encoding UTF8
$namespace = [System.Xml.XmlNamespaceManager]::new($parsed.NameTable)
$namespace.AddNamespace('command',$commandNs)
if ($parsed.SelectNodes('/helpItems/command:command',$namespace).Count -ne $names.Count) {
    throw 'Generated help does not contain every exported function.'
}
Move-Item -LiteralPath $temp -Destination $destination -Force -ErrorAction Stop
Get-Item -LiteralPath $destination
