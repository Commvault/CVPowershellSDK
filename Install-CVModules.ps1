#
# Package install script for 'CommvaultPSModule'
#
# Author: Gary Stoops
# Company: Commvault
#
# Original Source: © 2019 Rogier Langeveld, Waternet, NL
#

param(
    [Parameter(Mandatory = $False)]
    [ValidateSet('AllUsers', 'CurrentUser')] 
    [String] $Scope = 'AllUsers',
    [Switch] $Offline,
    [Switch] $PersistModulePath
)

Clear-Host

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$WorkingDir = Join-Path $PSScriptRoot 'Modules'

function InstallModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $False)]
        [ValidateSet('AllUsers', 'CurrentUser')] 
        [String] $Scope = 'AllUsers',
        [Switch] $Offline,
        [Switch] $PersistModulePath
    )

    begin {

        try {
            if (-not $offline.IsPresent) {
                $Repository = Register-CVTempRepository $WorkingDir
            }
            else {
                $ModulePathFound = Find-PSModulePath $WorkingDir
                if (-not $ModulePathFound) {
                    if ($PersistModulePath.IsPresent) {
                        if ($Scope -eq 'AllUsers') {
                            try {
                                $curPSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
                                [Environment]::SetEnvironmentVariable("PSModulePath", $curPSModulePath + [System.IO.Path]::PathSeparator + $WorkingDir, "Machine")
                            }
                            catch [System.Management.Automation.MethodInvocationException] {
                                $errorId = 'SecurityException'
                                if ($_.FullyQualifiedErrorId.SubString(0, $errorId.Length) -eq $errorId) {
                                    Write-Warning -Message "$($MyInvocation.MyCommand): To persist the modification of the PSModulePath, either reduce scope to 'CurrentUser' (-Scope CurrentUser) or start PowerShell with Run as Administrator option"
                                    throw $_
                                }
                            }
                        }
                        else {
                            $curPSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
                            [Environment]::SetEnvironmentVariable("PSModulePath", $curPSModulePath + [System.IO.Path]::PathSeparator + $WorkingDir, "User")
                        }
                    }
                    $env:PSModulePath = $env:PSModulePath + ";" + $WorkingDir
                }
            }
        }
        catch {
            throw $_
        }
    }

    process {

        try {
            if (-not $offline.IsPresent) {
                $ModuleFiles = Get-ChildItem $WorkingDir -Include "*.psm1" -Recurse
                $curModule = 0
                $complete = [math]::Round($curModule/$ModuleFiles.Length * 100)
                Write-Progress -Activity "Installing Commvault Modules" -Status "$complete% Complete:" -PercentComplete $complete;
    
                foreach ($ModuleFile in $ModuleFiles) {
                    try { # Publish module to repository
                        Publish-Module -Repository $Repository.Name -Path $ModuleFile.DirectoryName -Force -ErrorAction Stop
                    }
                    catch [System.InvalidOperationException] {
                        $errorId = 'ModuleVersionIsAlreadyAvailableInTheGallery'
                        if ($_.FullyQualifiedErrorId.SubString(0, $errorId.Length) -ne $errorId) {
                            throw $_
                        }
                    }
    
                    try { # Install module from repository
                        Install-Module -Repository $Repository.Name -Name $ModuleFile.BaseName -Scope $Scope -Force -ErrorAction Stop
                    }
                    catch [System.ArgumentException] {
                        $errorId = 'InstallModuleNeedsCurrentUserScopeParameterForNonAdminUser'
                        if ($_.FullyQualifiedErrorId.SubString(0, $errorId.Length) -eq $errorId) {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Please elevate current user execution policy or start PowerShell with Run as Administrator option"
                            break outer
                        }
                        else {
                            throw $_
                        }
                    }
    
                    $curModule++
                    $complete = [math]::Round($curModule/$ModuleFiles.Length * 100)
                    Write-Progress -Activity "Installing Commvault Modules" -Status "$complete% Complete:" -PercentComplete $complete;
                }
            }
        }
        catch {
            throw $_
        }
    }

    end {

        try {
            if (-not $Offline.IsPresent) {
                Unregister-PSRepository -Name $Repository.Name
                Get-InstalledModule -Name 'Commvault.*' -ErrorAction Stop | Out-Null
            }
            elseif ($PersistModulePath.IsPresent) {
                if (-not $ModulePathFound) {
                    if ($Scope -eq 'AllUsers') {
                        Write-Information -InformationAction Continue -MessageData "INFO: $($MyInvocation.MyCommand): The module path '$($WorkingDir)' has been persisted to the system PSModulePath environment variable"
                    }
                    else {
                        Write-Information -InformationAction Continue -MessageData "INFO: $($MyInvocation.MyCommand): The module path '$($WorkingDir)' has been persisted to the current user PSModulePath environment variable"
                    }
                }
            }
            else {
                Write-Information -InformationAction Continue -MessageData "INFO: $($MyInvocation.MyCommand): The module path '$($WorkingDir)' has been added to the current PowerShell session PSModulePath environment variable"
                Write-Information -InformationAction Continue -MessageData "INFO: $($MyInvocation.MyCommand): To persist the module path '$($WorkingDir)' across Powershell sessions, run 'Install-CVModules -Scope AllUsers/CurrentUser -Offline -PersistModulePath'"
            }
            Write-Information -InformationAction Continue -MessageData "INFO: $($MyInvocation.MyCommand): To get started, use the cvps.ps1 script to login to your CommServe and view available Commvault modules/commands"
        }
        catch [System.Exception] {
            if (-not ($_.CategoryInfo.Category -eq 'ObjectNotFound')) {
                throw $_
            }
        }
        catch {
            throw $_
        }
    }
}


function Register-CVTempRepository {
    param (
        [String] $Path
    )

    [System.Uri] $RepositoryPath = "\\localhost\" + $($(Split-Path $Path -Qualifier) -replace ':', '$') + $(Split-Path $Path -NoQualifier)
    
    $Repository = @{
        Name = 'Commvault Repository'
        SourceLocation = $RepositoryPath
        PublishLocation = $RepositoryPath
        InstallationPolicy = 'Trusted'
    }

    try {
        New-Item -Path $Path -ItemType Directory -ErrorAction Stop | Out-Null
    }
    catch [System.IO.IOException] {
        if (-not ($_.CategoryInfo.Category -eq 'ResourceExists')) {
            throw $_
        }
    }
    catch {
        throw $_
    }
    
    try {
        Get-PSRepository $Repository.Name -ErrorAction Stop | Out-Null
    }
    catch [System.Exception] {
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound') {
            Register-PSRepository @Repository
            Get-PSRepository $Repository.Name | Format-List | Out-String | Write-Debug
        }
        else {
            throw $_
        }
    }
    catch {
        throw $_
    }

    return (Get-PSRepository $Repository.Name)
}


function Find-PSModulePath {
    param (
        [String] $Path
    )

    return (($env:PSmodulePath -split(";") | Where-Object {$_ -eq $Path}).Length -gt 0)
}


####
if ($Offline.IsPresent) {
    if ($PersistModulePath.IsPresent) {
        InstallModules -Scope $Scope -Offline -PersistModulePath
    }
    else {
        InstallModules -Scope $Scope -Offline
    }
}
else {
    InstallModules -Scope $Scope
}
