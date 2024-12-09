###############################################################################################################
# Language     :  PowerShell 4.0
# Filename     :  checkrds_devicecals.ps1
# Autor        :  https://github.com/BornToBeRoot
# Description  :  Check your available rds device cals with usage in percent using NRPE/NSClient++
# Repository   :  https://github.com/BornToBeRoot/check_rdsdevicecals
###############################################################################################################

<#
    .SYNOPSIS
    Check your available rds device cals with usage in percent

    .DESCRIPTION
    Check your available remote desktop services (rds) device cals with usage in percent using NRPE/NSClient++.

    -- KeyPackType --
    0 - The Remote Desktop Services license key pack type is unknown.
    1 - The Remote Desktop Services license key pack type is a retail purchase.
    2 - The Remote Desktop Services license key pack type is a volume purchase.
    3 - The Remote Desktop Services license key pack type is a concurrent license.
    4 - The Remote Desktop Services license key pack type is temporary.
    5 - The Remote Desktop Services license key pack type is an open license.
    6 - Not supported.

    -- ProductVersionID --
    0 - Not supported.
    1 - Not supported.
    2 - Windows Server 2008
    3 - Windows Server 2008 R2
    4 - Windows Server 2012
    5 - Windows Server 2016
    6 - Windows Server 2019
    7 - Windows Server 2022
    8 - Windows Server 2025
       
    .EXAMPLE
    .\check_rds_device_cals.ps1 -Warning 20 -Critical 5 -KeyPackTypes 2 -ProductVersionID 2,3
        
    .LINK
    https://github.com/BornToBeRoot/Nagios_Plugins/blob/master/Documentation/Scripts/Windows_NRPE/check_rds_device_cals.README.md
#>

[CmdletBinding()]
Param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        HelpMessage='Number of free licenses before the status "warning" is returned.')]
    [Int32]$Warning,

    [Parameter(
        Position=1,
        Mandatory=$true,
        HelpMessage='Number of free licenses before the status "critical" is returned.')]
    [ValidateScript({
        if($_ -ge $Warning)
        {
            throw "Critical value cannot be greater or equal than warning value!"
        }
        else 
        {
            return $true
        }
    })]
    [Int32]$Critical,

    [Parameter(
        Position=2,
        HelpMessage="Select your license key pack [KeyPackType --> 0 = unkown, 1 = retail, 2 = volume, 3 = concurrent, 4 = temporary, 5 = open license, 6 = not supported] (More details under: https://msdn.microsoft.com/en-us/library/windows/desktop/aa383803%28v=vs.85%29.aspx)")]
    [ValidateRange(0,6)]
    [Int32[]]$KeyPackTypes=(0,1,2,3,4,5,6),

        [Parameter(
        Position=3,
        HelpMessage="Select your product version [ProductVersionID --> 0 = not supported, 1 = not supported, 2 = 2008, 3 = 2008R2, 4 = 2012, 5 = 2016, 6 = 2019, 7 = 2022, 8 = 2025] (More details under: https://msdn.microsoft.com/en-us/library/windows/desktop/aa383803%28v=vs.85%29.aspx)")]
    [ValidateRange(0,8)]
    [Int32[]]$ProductVersionID=@(0,1,2,3,4,5,6,7,8),

    [Parameter(
        Position=4,
        HelpMessage="Hostname or IP-Address of the server where the rds cals are stored (Default=localhost)")]
    [String]$ComputerName=$env:COMPUTERNAME,

    [Parameter(HelpMessage="Displays individual rows for different typs of KeyPacks")]
    [Switch]$DisplayDetailedPacks
)

Begin{

}

Process{
    # Get all license key packs from WMI
    try{
        # If you are using PowerShell 4 or higher, you can use Get-CimInstance instead of Get-WmiObject      
        $TSLicenseKeyPacks = Get-WmiObject -Class Win32_TSLicenseKeyPack -ComputerName $ComputerName -ErrorAction Stop
    } catch {
        Write-Host -Object "$($_.Exception.Message)" -NoNewline
        exit 3
    }

    [Int64]$TotalLicenses = 0
    [Int64]$AvailableLicenses = 0
    [Int64]$IssuedLicenses = 0
    
    # Go through each license key pack
    foreach($TSLicenseKeyPack in $TSLicenseKeyPacks)
    {
        # Check only license key packs, which you have selected with "-KeyPackTypes" and "-ProductVersionID" (Everything is checked by default)
        if(($KeyPackTypes -contains $TSLicenseKeyPack.KeyPackType) -and ($ProductVersionID -contains $TSLicenseKeyPack.ProductVersionID))
        {
            $TotalLicenses += $TSLicenseKeyPack.TotalLicenses
            $AvailableLicenses += $TSLicenseKeyPack.AvailableLicenses
            $IssuedLicenses += $TSLicenseKeyPack.IssuedLicenses
        }
    }

    # Create the detailed Pack info, if needed.
    if ($DisplayDetailedPacks)
    {
        $DetailedKeyPacksTemp = $TSLicenseKeyPacks|group ProductVersion, TypeAndModel|Select Name, `
                                        @{l='ProductVersion';e={$_.group[0].ProductVersion}}, `
                                        @{l='ProductVersionID';e={$_.group[0].ProductVersionID}}, `
                                        @{l='KeyPackType';e={$_.group[0].KeyPackType}}, `
                                        @{l='TypeAndModel';e={$_.group[0].TypeAndModel}}, `
                                        @{l='Issued';e={($_.group|Measure-Object -Sum IssuedLicenses).Sum}}, `
                                        @{l='Total';e={($_.group|Measure-Object -Sum TotalLicenses).Sum}}|Select *, @{l="Usage";e={[math]::ceiling($_.Issued/$_.Total*100)}}|Sort Name
        $DetailedKeyPacksOutput = "`n"
        ForEach($TSLicenseKeyPackGroups in $DetailedKeyPacksTemp)
        {
            if(($KeyPackTypes -contains $TSLicenseKeyPackGroups.KeyPackType) -and ($ProductVersionID -contains $TSLicenseKeyPackGroups.ProductVersionID))
            {
                $DetailedKeyPacksOutput += [String]::Format("{0}: has issued {1} licenses from a total of {2} licenses, for a usage of {3}%.`n", $TSLicenseKeyPackGroups.Name,  $TSLicenseKeyPackGroups.Issued, $TSLicenseKeyPackGroups.Total, [Math]::ceiling($TSLicenseKeyPackGroups.Issued/$TSLicenseKeyPackGroups.Total*100))
            }
        }
    }
     
    $Message = ([String]::Format("{0} rds device cals available from {1} ({2}% usage)", ($TotalLicenses - $IssuedLicenses), $TotalLicenses, [Math]::Round((($IssuedLicenses / $TotalLicenses) * 100), 2))).Replace(',','.')

    # return critical OR warning OR ok
    if(($TotalLicenses - $IssuedLicenses) -le $Critical)
    {
        Write-Host -Object "CRITICAL - $Message"
        if ($DisplayDetailedPacks)
        {
            $DetailedKeyPacksOutput
        }
        exit 2
    }
    elseif(($TotalLicenses - $IssuedLicenses) -le $Warning)
    {
        Write-Host -Object "WARNING - $Message"        
        if ($DisplayDetailedPacks)
        {
            $DetailedKeyPacksOutput
        }
        exit 1
    }
    else
    {
        Write-Host -Object "OK - $Message"
        if ($DisplayDetailedPacks)
        {
            $DetailedKeyPacksOutput
        }
        exit 0
    }     
}

End{

}

