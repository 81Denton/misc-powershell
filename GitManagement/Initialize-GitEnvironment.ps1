<#
.SYNOPSIS
    Sets up the GitHub Git Shell Environment in PowerShell

.DESCRIPTION
    Sets up the proper PATH and ENV to use GitHub for Window's shell environment
    
    This is a refactored version of $env:LOCALAPPDATA\GitHub\shell.ps1 that gets installed
    with GitDesktop for Windows.

.PARAMETER SkipSSHSetup
    If true, skips calling GitHub.exe to autoset and upload ssh-keys

.EXAMPLE
    Initialize-GitEnvironment

#>

function Initialize-GitEnvironment {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$False)]
        [switch]$SkipSSHSetup = $false,

        [Parameter(Mandatory=$False)]
        [string]$ExistingSSHPrivateKeyPath = "$HOME\.ssh\github_rsa"

    )

    ##### BEGIN Native Helper Functions #####

    Function Check-InstalledPrograms {
        [CmdletBinding(
            PositionalBinding=$True,
            DefaultParameterSetName='Default Param Set'
        )]
        Param(
            [Parameter(
                Mandatory=$False,
                ParameterSetName='Default Param Set'
            )]
            [string]$ProgramTitleSearchTerm,

            [Parameter(
                Mandatory=$False,
                ParameterSetName='Default Param Set'
            )]
            [string[]]$HostName = $env:COMPUTERNAME,

            [Parameter(
                Mandatory=$False,
                ParameterSetName='Secondary Param Set'
            )]
            [switch]$AllADWindowsComputers

        )

        ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####

        $RegPaths = @("HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
        
        ##### END Variable/Parameter Transforms and PreRun Prep #####

        ##### BEGIN Main Body #####
        # Get a list of Windows Computers from AD
        if ($AllADWindowsComputers) {
            $ComputersArray = $(Get-ADComputer -Filter * -Property * | Where-Object {$_.OperatingSystem -like "*Windows*"}).Name
        }
        else {
            $ComputersArray = $HostName
        }

        foreach ($computer in $ComputersArray) {
            if ($computer -eq $env:COMPUTERNAME -or $computer.Split("\.")[0] -eq $env:COMPUTERNAME) {
                try {
                    $InstalledPrograms = foreach ($regpath in $RegPaths) {Get-ItemProperty $regpath}
                    if (!$?) {
                        throw
                    }
                }
                catch {
                    Write-Warning "Unable to find registry path(s) on $computer. Skipping..."
                    continue
                }
            }
            else {
                try {
                    $InstalledPrograms = Invoke-Command -ComputerName $computer -ScriptBlock {
                        foreach ($regpath in $RegPaths) {
                            Get-ItemProperty $regpath
                        }
                    } -ErrorAction SilentlyContinue
                    if (!$?) {
                        throw
                    }
                }
                catch {
                    Write-Warning "Unable to connect to $computer. Skipping..."
                    continue
                }
            }

            if ($ProgramTitleSearchTerm) {
                $InstalledPrograms | Where-Object {$_.DisplayName -like "*$ProgramTitleSearchTerm*"}
            }
            else {
                $InstalledPrograms
            }
        }

        ##### END Main Body #####

    }

    ##### END Native Helper Functions #####

    # Check to make sure Git Desktop is Installed
    $GitDesktopCheck1 = Check-InstalledPrograms -ProgramTitleSearchTerm "GitDesktop"
    $GitDesktopCheck2 = Resolve-Path "$env:LocalAppData\GitHub\PoshGit_*" -ErrorAction SilentlyContinue
    $GitDesktopCheck3 = Resolve-Path "$env:LocalAppData\GitHub\PortableGit_*" -ErrorAction SilentlyContinue
    $GitDesktopCheck4 = $(Get-ChildItem -Recurse -Path "$env:LocalAppData\Apps" | Where-Object {$_.Name -match "^gith..tion*" -and $_.FullName -notlike "*manifests*" -and $_.FullName -notlike "*\Data\*"}).FullName
    if (!$GitDesktopCheck1 -and !$GitDesktopCheck2 -and !$GitDesktopCheck3 -and !$GitDesktopCheck4) {
        Write-Verbose "GitDesktop is NOT currently installed! Halting!"
        Write-Error "GitDesktop is NOT currently installed! Halting!"
        $global:FunctionResult = "1"
        return
    }


    # Set the Git PowerShell Environment
    if ($env:github_shell -eq $null) {
        $env:github_posh_git = Resolve-Path "$env:LocalAppData\GitHub\PoshGit_*" -ErrorAction Continue
        $env:github_git = Resolve-Path "$env:LocalAppData\GitHub\PortableGit_*" -ErrorAction Continue
        $env:PLINK_PROTOCOL = "ssh"
        $env:TERM = "msys"
        $env:HOME = $HOME
        $env:TMP = $env:TEMP = [system.io.path]::gettemppath()
        if ($env:EDITOR -eq $null) {
          $env:EDITOR = "GitPad"
        }

        # Setup PATH
        $pGitPath = $env:github_git
        #$appPath = Resolve-Path "$env:LocalAppData\Apps\2.0\XE9KPQJJ.N9E\GALTN70J.73D\gith..tion_317444273a93ac29_0003.0003_5794af8169eeff14"
        $appPath = $(Get-ChildItem -Recurse -Path "$env:LocalAppData\Apps" | Where-Object {$_.Name -match "^gith..tion*" -and $_.FullName -notlike "*manifests*" -and $_.FullName -notlike "*\Data\*"}).FullName
        $HighestNetVer = $($(Get-ChildItem "$env:SystemRoot\Microsoft.NET\Framework" | Where-Object {$_.Name -match "^v[0-9]"}).Name -replace "v","" | Measure-Object -Maximum).Maximum
        $msBuildPath = "$env:SystemRoot\Microsoft.NET\Framework\v$HighestNetVer"
        $lfsamd64Path = Resolve-Path "$env:LocalAppData\GitHub\lfs-*"

        $env:Path = "$env:Path;$pGitPath\cmd;$pGitPath\usr\bin;$pGitPath\usr\share\git-tfs;$lfsamd64Path;$appPath;$msBuildPath"

        $env:github_shell = $true
        $env:git_install_root = $pGitPath
        if ($env:github_posh_git) {
            $env:posh_git = "$env:github_posh_git\profile.example.ps1"
        }

        # Setup SSH
        if (!$SkipSSHSetup) {
            & "$appPath\GitHub.exe" --set-up-ssh

            if (!$(Get-Module -List -Name posh-git)) {
                if ($PSVersionTable.PSVersion.Major -ge 5) {
                    Install-Module posh-git -Scope CurrentUser
                    Import-Module posh-git -Verbose
                }
                if ($PSVersionTable.PSVersion.Major -lt 5) {
                    Update-PackageManagement
                    Install-Module posh-git -Scope CurrentUser
                    Import-Module posh-git -Verbose
                }
            }
            Start-SshAgent
            Add-SshKey $ExistingSSHPrivateKeyPath
        }
    } 
    else {
        Write-Verbose "GitHub shell environment already setup"
    }
}





# SIG # Begin signature block
# MIIMLAYJKoZIhvcNAQcCoIIMHTCCDBkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUt0iw6VSMelw972HWfeDJzPDw
# +OWgggmhMIID/jCCAuagAwIBAgITawAAAAQpgJFit9ZYVQAAAAAABDANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE1MDkwOTA5NTAyNFoXDTE3MDkwOTEwMDAyNFowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCmRIzy6nwK
# uqvhoz297kYdDXs2Wom5QCxzN9KiqAW0VaVTo1eW1ZbwZo13Qxe+6qsIJV2uUuu/
# 3jNG1YRGrZSHuwheau17K9C/RZsuzKu93O02d7zv2mfBfGMJaJx8EM4EQ8rfn9E+
# yzLsh65bWmLlbH5OVA0943qNAAJKwrgY9cpfDhOWiYLirAnMgzhQd3+DGl7X79aJ
# h7GdVJQ/qEZ6j0/9bTc7ubvLMcJhJCnBZaFyXmoGfoOO6HW1GcuEUwIq67hT1rI3
# oPx6GtFfhCqyevYtFJ0Typ40Ng7U73F2hQfsW+VPnbRJI4wSgigCHFaaw38bG4MH
# Nr0yJDM0G8XhAgMBAAGjggECMIH/MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQW
# BBQ4uUFq5iV2t7PneWtOJALUX3gTcTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBR2
# lbqmEvZFA0XsBkGBBXi2Cvs4TTAxBgNVHR8EKjAoMCagJKAihiBodHRwOi8vcGtp
# L2NlcnRkYXRhL1plcm9EQzAxLmNybDA8BggrBgEFBQcBAQQwMC4wLAYIKwYBBQUH
# MAKGIGh0dHA6Ly9wa2kvY2VydGRhdGEvWmVyb0RDMDEuY3J0MA0GCSqGSIb3DQEB
# CwUAA4IBAQAUFYmOmjvbp3goa3y95eKMDVxA6xdwhf6GrIZoAg0LM+9f8zQOhEK9
# I7n1WbUocOVAoP7OnZZKB+Cx6y6Ek5Q8PeezoWm5oPg9XUniy5bFPyl0CqSaNWUZ
# /zC1BE4HBFF55YM0724nBtNYUMJ93oW/UxsWL701c3ZuyxBhrxtlk9TYIttyuGJI
# JtbuFlco7veXEPfHibzE+JYc1MoGF/whz6l7bC8XbgyDprU1JS538gbgPBir4RPw
# dFydubWuhaVzRlU3wedYMsZ4iejV2xsf8MHF/EHyc/Ft0UnvcxBqD0sQQVkOS82X
# +IByWP0uDQ2zOA1L032uFHHA65Bt32w8MIIFmzCCBIOgAwIBAgITWAAAADw2o858
# ZSLnRQAAAAAAPDANBgkqhkiG9w0BAQsFADA9MRMwEQYKCZImiZPyLGQBGRYDTEFC
# MRQwEgYKCZImiZPyLGQBGRYEWkVSTzEQMA4GA1UEAxMHWmVyb1NDQTAeFw0xNTEw
# MjcxMzM1MDFaFw0xNzA5MDkxMDAwMjRaMD4xCzAJBgNVBAYTAlVTMQswCQYDVQQI
# EwJWQTEPMA0GA1UEBxMGTWNMZWFuMREwDwYDVQQDEwhaZXJvQ29kZTCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ8LM3f3308MLwBHi99dvOQqGsLeC11p
# usrqMgmEgv9FHsYv+IIrW/2/QyBXVbAaQAt96Tod/CtHsz77L3F0SLuQjIFNb522
# sSPAfDoDpsrUnZYVB/PTGNDsAs1SZhI1kTKIjf5xShrWxo0EbDG5+pnu5QHu+EY6
# irn6C1FHhOilCcwInmNt78Wbm3UcXtoxjeUl+HlrAOxG130MmZYWNvJ71jfsb6lS
# FFE6VXqJ6/V78LIoEg5lWkuNc+XpbYk47Zog+pYvJf7zOric5VpnKMK8EdJj6Dze
# 4tJ51tDoo7pYDEUJMfFMwNOO1Ij4nL7WAz6bO59suqf5cxQGd5KDJ1ECAwEAAaOC
# ApEwggKNMA4GA1UdDwEB/wQEAwIHgDA9BgkrBgEEAYI3FQcEMDAuBiYrBgEEAYI3
# FQiDuPQ/hJvyeYPxjziDsLcyhtHNeIEnofPMH4/ZVQIBZAIBBTAdBgNVHQ4EFgQU
# a5b4DOy+EUyy2ILzpUFMmuyew40wHwYDVR0jBBgwFoAUOLlBauYldrez53lrTiQC
# 1F94E3EwgeMGA1UdHwSB2zCB2DCB1aCB0qCBz4aBq2xkYXA6Ly8vQ049WmVyb1ND
# QSxDTj1aZXJvU0NBLENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxD
# Tj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NlcnRp
# ZmljYXRlUmV2b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmli
# dXRpb25Qb2ludIYfaHR0cDovL3BraS9jZXJ0ZGF0YS9aZXJvU0NBLmNybDCB4wYI
# KwYBBQUHAQEEgdYwgdMwgaMGCCsGAQUFBzAChoGWbGRhcDovLy9DTj1aZXJvU0NB
# LENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxD
# Tj1Db25maWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NBQ2VydGlmaWNhdGU/YmFz
# ZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MCsGCCsGAQUFBzAC
# hh9odHRwOi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EuY3J0MBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYBBQUHAwMwDQYJKoZIhvcNAQEL
# BQADggEBACbc1NDl3NTMuqFwTFd8NHHCsSudkVhuroySobzUaFJN2XHbdDkzquFF
# 6f7KFWjqR3VN7RAi8arW8zESCKovPolltpp3Qu58v59qZLhbXnQmgelpA620bP75
# zv8xVxB9/xmmpOHNkM6qsye4IJur/JwhoHLGqCRwU2hxP1pu62NUK2vd/Ibm8c6w
# PZoB0BcC7SETNB8x2uKzJ2MyAIuyN0Uy/mGDeLyz9cSboKoG6aQibnjCnGAVOVn6
# J7bvYWJsGu7HukMoTAIqC6oMGerNakhOCgrhU7m+cERPkTcADVH/PWhy+FJWd2px
# ViKcyzWQSyX93PcOj2SsHvi7vEAfCGcxggH1MIIB8QIBATBUMD0xEzARBgoJkiaJ
# k/IsZAEZFgNMQUIxFDASBgoJkiaJk/IsZAEZFgRaRVJPMRAwDgYDVQQDEwdaZXJv
# U0NBAhNYAAAAPDajznxlIudFAAAAAAA8MAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3
# AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisG
# AQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQMmL0YAzoT
# Iu4f8m9wP/dEfnUwhTANBgkqhkiG9w0BAQEFAASCAQCQjj2P0dZ7Dag5WynnMPZu
# A4SKOpWv0EDLGFEe7S5Kr5d680eE6AWfG1B6KMYBFpIANPS3lPs5rFhEKOYs3oW7
# HPhKiMqHJuI9iCFlO5v4RYRo0uajjhOyNkJNJVHdbfZkxACMeg95vTF/AvMqallC
# /RtvA341uO4YhLxTJf07fWhVZKXZPro+bZDqoXc7MaS40ApN7sMdUYw5TsPJAw/3
# pKaEcvQsoqROKqqVGdIfFiJJjfxWtFdZeaGLT7992iGnD7GvhD99oA6MtDh5dJHF
# 3n8IFt9K8TqTOfDoKcNsQtfqNDs2PvKD4h1OQ4VMmL9dzxZTO4olMSpOUKuLfuhD
# SIG # End signature block
