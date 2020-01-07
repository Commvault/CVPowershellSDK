#
# Package install script for 'CommvaultPSModule'
#
# Author: Gary Stoops
# Company: Commvault
#
# Original Source: © 2019 Rogier Langeveld, Waternet, NL
#

Clear-Host

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RootDir = $PSScriptRoot

$WorkingDir = Join-Path $RootDir 'Modules'

function InstallModules {

    begin {

        try {
            $Repository = Register-CVTempRepository $WorkingDir
        }
        catch {
            throw $_
        }
    }

    process {

        try {
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
                    Install-Module -Repository $Repository.Name -Name $ModuleFile.BaseName -Force -ErrorAction Stop
                }
                catch [System.ArgumentException] {
                    $errorId = 'InstallModuleNeedsCurrentUserScopeParameterForNonAdminUser'
                    if ($_.FullyQualifiedErrorId.SubString(0, $errorId.Length) -eq $errorId) {
                        Write-Warning -Message "$($MyInvocation.MyCommand): Please elevate current user execution policy or start PowerShell with Run as Administrator"
                        break
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
        catch {
            throw $_
        }
    }

    end {

        try {
            Start-Sleep -Seconds 3
            Unregister-PSRepository -Name $Repository.Name
            Get-InstalledModule -Name 'Commvault.*' -ErrorAction Stop | Out-Null
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


####
InstallModules