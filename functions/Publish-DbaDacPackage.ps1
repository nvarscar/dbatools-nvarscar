﻿function Publish-DbaDacPackage {
    <#
    .SYNOPSIS
        The Publish-DbaDacPackage command takes a dacpac which is the output from an SSDT project and publishes it to a database. Changing the schema to match the dacpac and also to run any scripts in the dacpac (pre/post deploy scripts).

    .DESCRIPTION
        Deploying a dacpac uses the DacFx which historically needed to be installed on a machine prior to use. In 2016 the DacFx was supplied by Microsoft as a nuget package (Microsoft.Data.Tools.MSBuild) and this uses that nuget package.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        Specifies the filesystem path to the DACPAC

    .PARAMETER PublishXml
        Specifies the publish profile which will include options and sqlCmdVariables.

    .PARAMETER Database
        Specifies the name of the database being published.

    .PARAMETER ConnectionString
        Specifies the connection string to the database you are upgrading. This is not required if SqlInstance is specified.

    .PARAMETER GenerateDeploymentScript
        If this switch is enabled, the publish script will be generated.

    .PARAMETER GenerateDeploymentReport
        If this switch is enabled, the publish XML report  will be generated.
        
    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.
        
    .PARAMETER DacOption
        Export options for a corresponding export type. Can be created by New-DbaDacOption -Type Dacpac | Bacpac

    .PARAMETER OutputPath
        Specifies the filesystem path (directory) where output files will be generated.

    .PARAMETER ScriptOnly
        If this switch is enabled, only the change scripts will be generated.

    .PARAMETER IncludeSqlCmdVars
        If this switch is enabled, SqlCmdVars in publish.xml will have their values overwritten.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER DacFxPath
        Path to the dac dll. If this is ommited, then the version of dac dll which is packaged with dbatools is used.

    .NOTES
        Tags: Migration, Database, Dacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Publish-DbaDacPackage

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml

        Updates WideWorldImporters on sql2017 from the sql2016-WideWorldImporters.dacpac using the sql2016-WideWorldImporters-publish.xml publish profile

    .EXAMPLE
        PS C:\> New-DbaDacProfile -SqlInstance sql2016 -Database db2 -Path C:\temp
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database db2 | Publish-DbaDacPackage -PublishXml C:\temp\sql2016-db2-publish.xml -Database db1, db2 -SqlInstance sql2017

        Creates a publish profile at C:\temp\sql2016-db2-publish.xml, exports the .dacpac to $home\Documents\sql2016-db2.dacpac
        then publishes it to the sql2017 server database db2

    .EXAMPLE
        PS C:\> $loc = "C:\Users\bob\source\repos\Microsoft.Data.Tools.Msbuild\lib\net46\Microsoft.SqlServer.Dac.dll"
        PS C:\> Publish-DbaDacPackage -SqlInstance "local" -Database WideWorldImporters -Path C:\temp\WideWorldImporters.dacpac -PublishXml C:\temp\WideWorldImporters.publish.xml -DacFxPath $loc

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml -GenerateDeploymentScript -ScriptOnly

        Does not deploy the changes, but will generate the deployment script that would be executed against WideWorldImporters.

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml -GenerateDeploymentReport -ScriptOnly

        Does not deploy the changes, but will generate the deployment report that would be executed against WideWorldImporters.
#>
    [CmdletBinding(DefaultParameterSetName = 'Obj')]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Xml')]
        [string]$PublishXml,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$Database,
        [string[]]$ConnectionString,
        [parameter(ParameterSetName = 'Xml')]
        [switch]$GenerateDeploymentScript,
        [parameter(ParameterSetName = 'Xml')]
        [switch]$GenerateDeploymentReport,
        [parameter(ParameterSetName = 'Xml')]
        [Switch]$ScriptOnly,
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [string]$OutputPath = "$home\Documents",
        [parameter(ParameterSetName = 'Xml')]
        [switch]$IncludeSqlCmdVars,
        [Parameter(ParameterSetName = 'Obj')]
        [object]$DacOption,
        [switch]$EnableException,
        [String]$DacFxPath
    )

    begin {
        if ((Test-Bound -Not -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName ConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString."
        }
        if ($Type -eq 'Dacpac') {
            if ((Test-Bound -ParameterName GenerateDeploymentScript) -or (Test-Bound -ParameterName GenerateDeploymentReport)) {
                $defaultcolumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DatabaseScriptPath', 'MasterDbScriptPath', 'DeploymentReport', 'DeployOptions', 'SqlCmdVariableValues'
            }
            else {
                $defaultcolumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DeployOptions', 'SqlCmdVariableValues'
            }
        }
        elseif ($Type -eq 'Bacpac') {
            if ($ScriptOnly -or $GenerateDeploymentReport -or $GenerateDeploymentScript) {
                Stop-Function -Message "ScriptOnly, GenerateDeploymentScript, and GenerateDeploymentReport cannot be used in a Bacpac scenario." -ErrorRecord $_
                return
            }
            $defaultcolumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Bacpac', 'Result', 'DeployOptions'
        }

        if ((Test-Bound -ParameterName ScriptOnly) -and (Test-Bound -Not -ParameterName GenerateDeploymentScript) -and (Test-Bound -Not -ParameterName GenerateDeploymentScript)) {
            Stop-Function -Message "You must at least one of GenerateDeploymentScript or GenerateDeploymentReport when using ScriptOnly"
        }

        function Get-ServerName ($connstring) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connstring)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            return $instance.ToString().Replace('\', '-').Replace('(', '').Replace(')', '')
        }
        if (Test-Bound -Not -ParameterName 'DacfxPath') {
            $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
        }

        if ((Test-Path $dacfxPath) -eq $false) {
            Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException
        }
        else {
            try {
                Add-Type -Path $dacfxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded."
            }
            catch {
                Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException -ErrorRecord $_
            }
        }
        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.PublishOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.PublishOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        }
        elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacImportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacImportOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not (Test-Path -Path $Path)) {
            Stop-Function -Message "$Path not found!"
            return
        }

        if ($PsCmdlet.ParameterSetName -eq 'Xml') {
            if (-not (Test-Path -Path $PublishXml)) {
                Stop-Function -Message "$PublishXml not found!"
                return
            }
        }

        foreach ($instance in $sqlinstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace('"', "'")
        }

        #Use proper class to load the object
        if ($Type -eq 'Dacpac') {
            try {
                $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Path)
            }
            catch {
                Stop-Function -Message "Could not load Dacpac." -ErrorRecord $_
                return
            }
        }
        elseif ($Type -eq 'Bacpac') {
            try {
                $bacPackage = [Microsoft.SqlServer.Dac.BacPackage]::Load($Path)
            }
            catch {
                Stop-Function -Message "Could not load Bacpac." -ErrorRecord $_
                return
            }
        }
        #Load XML profile when used
        if ($PsCmdlet.ParameterSetName -eq 'Xml') {
            try {
                $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($PublishXml)
            }
            catch {
                Stop-Function -Message "Could not load profile." -ErrorRecord $_
                return
            }

            if ($IncludeSqlCmdVars) {
                Get-SqlCmdVars -SqlCommandVariableValues $dacProfile.DeployOptions.SqlCommandVariableValues
            }
        }

        foreach ($connstring in $ConnectionString) {
            $cleaninstance = Get-ServerName $connstring
            $instance = $cleaninstance.ToString().Replace('--', '\')

            foreach ($dbname in $database) {
                #Create deployment options object of a proper type
                if (!$DacOption) {
                    $options = New-DbaDacOption -Type $Type -Action Publish
                }
                else {
                    $options = $DacOption
                }
                #Set deployment properties when specified
                if ($GenerateDeploymentScript -or $GenerateDeploymentReport) {
                    $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
                    $DeploymentReport = Join-Path $OutputPath "$cleaninstance-$dbname`_Result.DeploymentReport_$timeStamp.xml"
                    if (!$options.DatabaseScriptPath) {
                        $options.DatabaseScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname`_DeployScript_$timeStamp.sql"
                    }
                    if (!$options.MasterDbScriptPath) {
                        $options.MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname`_Master.DeployScript_$timeStamp.sql"
                    }
                }
                if (Test-Bound -ParameterName GenerateDeploymentScript) {
                    $options.GenerateDeploymentScript = $GenerateDeploymentScript
                }
                if (Test-Bound -ParameterName GenerateDeploymentReport) {
                    $options.GenerateDeploymentReport = $GenerateDeploymentReport
                }

                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbname"
                }
                
                #Create services object
                try {
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connstring
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }

                #Assign deployment options when loaded from Xml
                if ($PsCmdlet.ParameterSetName -eq 'Xml') {
                    $options.DeployOptions = $dacProfile.DeployOptions
                }

                try {
                    $global:output = @()
                    Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -Action { $global:output += $EventArgs.Message.Message } | Out-Null
                    #Perform proper action depending on the Type
                    if ($Type -eq 'Dacpac') {
                        if ($ScriptOnly) {
                            Write-Message -Level Verbose -Message "Generating script."
                            $result = $dacServices.Script($dacPackage, $dbname, $options)
                        }
                        else {
                            Write-Message -Level Verbose -Message "Executing Dacpac publish."
                            $result = $dacServices.Publish($dacPackage, $dbname, $options)
                        }
                    }
                    elseif ($Type -eq 'Bacpac') {
                        Write-Message -Level Verbose -Message "Executing Bacpac import."
                        $dacServices.ImportBacpac($bacPackage, $dbname, $options, $null)
                    }
                }
                catch [Microsoft.SqlServer.Dac.DacServicesException] {
                    Stop-Function -Message "Deployment failed" -ErrorRecord $_ -EnableException $true
                }
                finally {
                    Unregister-Event -SourceIdentifier "msg"
                    if ($GenerateDeploymentReport) {
                        $result.DeploymentReport | Out-File $DeploymentReport
                        Write-Message -Level Verbose -Message "Deployment Report - $DeploymentReport."
                    }
                    if ($GenerateDeploymentScript) {
                        Write-Message -Level Verbose -Message "Database change script - $DatabaseScriptPath."
                        if ((Test-Path $MasterDbScriptPath)) {
                            Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)."
                        }
                    }
                    $resultoutput = ($global:output -join "`r`n" | Out-String).Trim()
                    if ($resultoutput -match "Failed" -and ($GenerateDeploymentReport -or $GenerateDeploymentScript)) {
                        Write-Message -Level Warning -Message "Seems like the attempt to publish/script may have failed. If scripts have not generated load dacpac into Visual Studio to check SQL is valid."
                    }
                    $server = [dbainstance]$instance
                    $deployOptions = $options.DeployOptions | Select-Object -Property * -ExcludeProperty "SqlCommandVariableValues"
                    if ($Type -eq 'Dacpac') {
                        $output = [pscustomobject]@{
                            ComputerName         = $server.ComputerName
                            InstanceName         = $server.InstanceName
                            SqlInstance          = $server.FullName
                            Database             = $dbname
                            Result               = $resultoutput
                            Dacpac               = $Path
                            PublishXml           = $PublishXml
                            ConnectionString     = $connstring
                            DatabaseScriptPath   = $options.DatabaseScriptPath
                            MasterDbScriptPath   = $options.MasterDbScriptPath
                            DeploymentReport     = $DeploymentReport
                            DeployOptions        = $deployOptions
                            SqlCmdVariableValues = $options.DeployOptions.SqlCommandVariableValues.Keys
                        }
                    }
                    elseif ($Type -eq 'Bacpac') {
                        $output = [pscustomobject]@{
                            ComputerName     = $server.ComputerName
                            InstanceName     = $server.InstanceName
                            SqlInstance      = $server.FullName
                            Database         = $dbname
                            Result           = $resultoutput
                            Bacpac           = $Path
                            ConnectionString = $connstring
                            DeployOptions    = $deployOptions
                        }
                    }
                    $output | Select-DefaultView -Property $defaultcolumns
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Publish-DbaDacpac
    }
}