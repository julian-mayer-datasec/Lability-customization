function Resolve-LabVMGenerationDiskPath {
<#
    .SYNOPSIS
        Resolves the specified VM name's target VHD/X path.
#>
    [CmdletBinding()]
    param (
        ## VM/node name.
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [System.String] $Name,

        ## Media Id
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $Media,

        ## Custom Master VHDX
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Boolean] $OwnMasterVHDX = $false,

        ## Lab DSC configuration data
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Collections.Hashtable]
        [Microsoft.PowerShell.DesiredStateConfiguration.ArgumentToConfigurationDataTransformationAttribute()]
        $ConfigurationData
    )
    process {

        if ($OwnMasterVHDX) {
            #skip get lab image, dirty fix
            $vhdxName = "$($Media)_$($NodeName)"
            $hostDefaults = Get-ConfigurationData -Configuration Host;
            $vhdxBasePath = $hostDefaults.ParentVhdPath;
            $image =
            @{
                "Id" = $Media
                "ImagePath" = "${vhdxBasePath}\${vhdxName}.vhdx"
                "Generation" = "VHDX"
            }
        }
        else {
            $image = Get-LabImage -Id $Media -ConfigurationData $ConfigurationData;
        }

        $resolveLabVMDiskPathParams = @{
            Name            = $Name;
            Generation      = $image.Generation;
            EnvironmentName = $ConfigurationData.NonNodeData.$($labDefaults.ModuleName).EnvironmentName;
        }
        $vhdPath = Resolve-LabVMDiskPath @resolveLabVMDiskPathParams

        return $vhdPath;

    } #end process
}
