#
# Package uninstall script for 'CommvaultPSModule'
#
# Author: Gary Stoops
# Company: Commvault
#

Clear-Host

function UninstallModules {

    begin {

        try {
            $InstalledModules = Get-InstalledModule -Name 'Commvault.*' -ErrorAction Stop
        }
        catch [System.Exception] {
            if (-not ($_.CategoryInfo.Category -eq 'ObjectNotFound')) {
                throw $_
            }
            else {
                Write-Information -InformationAction Continue -MessageData "INFO: $($MyInvocation.MyCommand): Existing Commvault PowerShell module installation not found"
            }
        }
        catch {
            throw $_
        }
    }

    process {

        try {
            if ($InstalledModules.Length -gt 0) {
                $curModule = 0
                $complete = [math]::Round($curModule/$InstalledModules.Length * 100)
                Write-Progress -Activity "Uninstalling Commvault Modules" -Status "$complete% Complete:" -PercentComplete $complete;
        
                foreach ($Module in $InstalledModules) {
                    if ($Module.Name.SubString(0, 10) -eq 'Commvault.') {
                        try { # uninstall module from local computer
                            Uninstall-Module -Name $Module.Name -ErrorAction Stop
                        }
                        catch [System.Exception] {
                            $errorId = 'AdminPrivilegesRequiredForUninstall'
                            if ($_.FullyQualifiedErrorId.SubString(0, $errorId.Length) -eq $errorId) {
                                Write-Warning -Message "$($MyInvocation.MyCommand): Please elevate current user execution policy or start PowerShell with Run as Administrator"
                                break
                            }
                            else {
                                throw $_
                            }
                        }
                    }
    
                    $curModule++
                    $complete = [math]::Round($curModule/$InstalledModules.Length * 100)
                    Write-Progress -Activity "Uninstalling Commvault modules" -Status "$complete% complete:" -PercentComplete $complete;
                }
            }
        }
        catch {
            throw $_
        }
    }

    end {
        Start-Sleep -Seconds 3
    }
}

####
UninstallModules