function Reset-LabVMDisk {
<#
    .SYNOPSIS
        Removes and resets lab VM disk file (VHDX) configuration.
#>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','')]
    param (
        ## VM/node display name
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.String] $Name,

        ## Media Id
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $Media,

        ## VM/node name
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.String] $NodeName = $Name,

        ## Custom Master VHDX
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Boolean] $OwnMasterVHDX = $false,

        ## Lab DSC configuration data
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Collections.Hashtable]
        [Microsoft.PowerShell.DesiredStateConfiguration.ArgumentToConfigurationDataTransformationAttribute()]
        $ConfigurationData
    )
    process {

        #$null = $PSBoundParameters.Remove('NodeName');
        #$null = $PSBoundParameters.Remove('OwnMasterVHDX');
        #Write-Debug -Message "custom master: $OwnMasterVHDX"

        Remove-LabVMSnapshot -Name $Name;
        Remove-LabVMDisk @PSBoundParameters;
        Set-LabVMDisk @PSBoundParameters;

    } #end process
}
