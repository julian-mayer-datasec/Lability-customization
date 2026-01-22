function Expand-LabImage {
    <#
    .SYNOPSIS
        Writes a .wim image to a mounted VHD/(X) file.
#>
    [CmdletBinding(DefaultParameterSetName = 'Index')]
    param (
        ## File path to WIM file or ISO file containing the WIM image
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.String] $MediaPath,

        ## WIM image index to apply
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'Index')]
        [System.Int32] $WimImageIndex,

        ## WIM image name to apply
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [System.String] $WimImageName,

        ## Mounted VHD(X) Operating System disk image
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNull()]
        [System.Object] $Vhd, # Microsoft.Vhd.PowerShell.VirtualHardDisk

        ## Disk image partition scheme
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateSet('MBR', 'GPT')]
        [System.String] $PartitionStyle,

        ## Optional Windows features to add to the image after expansion (ISO only)
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNull()]
        [System.String[]] $WindowsOptionalFeature,

        ## Optional Windows features source path
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [System.String] $SourcePath = '\sources\sxs',

        ## Relative source WIM file path (only used for ISOs)
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [System.String] $WimPath = '\sources\install.wim',

        ## Optional Windows packages to add to the image after expansion (primarily used for Nano Server)
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNull()]
        [System.String[]] $Package,

        ## Relative packages (.cab) file path (primarily used for Nano Server)
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [System.String] $PackagePath = '\packages',

        ## Package localization directory/extension (primarily used for Nano Server)
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [System.String] $PackageLocale = 'en-US',

        # Commands that shall be executed for .wim
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Collections.Hashtable[]]$Commands,

        # Switch for deleting Windows Defender
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Boolean]$DeleteDefender
    )
    process {

        ## Assume the media path is a literal path to a WIM file
        $windowsImagePath = $MediaPath;
        $mediaFileInfo = Get-Item -Path $MediaPath;

        try {

            if ($mediaFileInfo.Extension -eq '.ISO') {

                ## Disable BitLocker fixed drive write protection (if enabled)
                Disable-BitLockerFDV;

                ## Mount ISO
                Write-Verbose -Message ($localized.MountingDiskImage -f $MediaPath);
                $mountDiskImageParams = @{
                    ImagePath   = $MediaPath;
                    StorageType = 'ISO';
                    Access      = 'ReadOnly';
                    PassThru    = $true;
                    Verbose     = $true;
                    ErrorAction = 'Stop';
                }
                $iso = Storage\Mount-DiskImage @mountDiskImageParams;
                $iso = Storage\Get-DiskImage -ImagePath $iso.ImagePath;
                $isoDriveLetter = Storage\Get-Volume -DiskImage $iso | Select-Object -ExpandProperty DriveLetter;

                ## Update the media path to point to the mounted ISO
                $windowsImagePath = '{0}:{1}' -f $isoDriveLetter, $WimPath;
            }

            if ($PSCmdlet.ParameterSetName -eq 'Name') {

                ## Locate the image index
                $wimImageIndex = Get-WindowsImageByName -ImagePath $windowsImagePath -ImageName $WimImageName;
            }


            if ($PartitionStyle -eq 'MBR') {

                $partitionType = 'IFS';
            }
            elseif ($PartitionStyle -eq 'GPT') {

                $partitionType = 'Basic';
            }
            $vhdDriveLetter = Get-DiskImageDriveLetter -DiskImage $Vhd -PartitionType $partitionType;
            $expandWindowsImageParams = @{
                ImagePath   = $windowsImagePath;
                ApplyPath   = '{0}:\' -f $vhdDriveLetter;
                LogPath     = $logPath;
                Index       = $wimImageIndex;
                Verbose     = $false;
                ErrorAction = 'Stop';
            }

            if ($DeleteDefender -or $Commands) {
                #Prepare paths and mount .wim
                Write-Verbose -Message "----- Now preparing paths and mounting .WIM for Customization! -----"
                Write-Verbose -Message "VHD Mount letter: $vhdDriveLetter"
                Write-Verbose -Message "Mediapath: $MediaPath"
                Write-Verbose -Message "windowsImagePath: $windowsImagePath"
                $LabilityBasePath = Split-Path $MediaPath -Qualifier
                $WimTempPath = Join-Path $LabilityBasePath "wimtemp"

                if (-not (Test-Path $WimTempPath)) {
                    New-Item -ItemType Directory -Path $WimTempPath -Force
                }

                Write-Verbose -Message "Created path $WimTempPath"

                Write-Verbose -Message "Copying .wim file to temp path"
                #Copy .wim
                Copy-Item -Path $windowsImagePath -Destination $WimTempPath -Force

                # .wim needs an empty folder as destination mount path
                $wimMountPath = '{0}\Mount' -f $LabilityBasePath;
                if (-Not (Test-Path $wimMountPath)) {
                    New-Item -Path $wimMountPath -ItemType Directory | Out-Null
                }

                # Make modifications to the .wim file before applying the image
                Set-ItemProperty -Path "$WimTempPath\install.wim" -Name Attributes -Value 'Normal'
                Write-Verbose -Message "Mount .wim"
                Mount-WindowsImage -ImagePath "$WimTempPath\install.wim" -Index $wimImageIndex -Path $wimMountPath;

                if ($Commands) {
                    Write-Verbose -Message "--- Now executing Commands in .wim Image ---"
                    Invoke-WIMCommands -Path $wimMountPath -Commands $Commands
                    Write-Verbose -Message "Finished executing commands."
                }

                if ($DeleteDefender) {
                    # Remove Defender via file deletion
                    Write-Verbose -Message "--- Now try to remove Defender via file deletion method in .wim Image"
                    $paths = @(
                        "$wimMountPath\Program Files\Windows Defender",
                        "$wimMountPath\Program Files\Windows Defender Advanced Threat Protection",
                        "$wimMountPath\Program Files (x86)\Windows Defender",
                        "$wimMountPath\Program Files (x86)\Windows Defender Advanced Threat Protection",
                        "$wimMountPath\ProgramData\Microsoft\Windows Defender",
                        "$wimMountPath\ProgramData\Microsoft\Windows Defender Advanced Threat Protection",
                        "$wimMountPath\ProgramData\Microsoft\Windows Security Health"
                    )

                    # Create a SecurityIdentifier object for the local Administrators group
                    $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
                    # Translate SID to NTAccount (localized group name)
                    $adminAccount = $adminSid.Translate([System.Security.Principal.NTAccount])

                    foreach ($path in $paths) {
                        Write-Verbose "Taking ownership of: $path"

                        try {
                            # Set owner on the root folder
                            $acl = Get-Acl -Path $path
                            $acl.SetOwner($adminAccount)
                            Set-Acl -Path $path -AclObject $acl

                            # Recursively set owner on all child items
                            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                                try {
                                    $itemAcl = Get-Acl -Path $_.FullName
                                    $itemAcl.SetOwner($adminAccount)
                                    Set-Acl -Path $_.FullName -AclObject $itemAcl
                                }
                                catch {
                                    Write-Warning "Failed to set owner on $($_.FullName): $_"
                                }
                            }

                            # Now grant full control permissions recursively with icacls using SID
                            Write-Verbose "Granting full control to local Administrators group (SID): $path"
                            Start-Process -FilePath "icacls.exe" -ArgumentList "`"$path`" /grant *S-1-5-32-544:F /t" -Wait -NoNewWindow

                        }
                        catch {
                            Write-Warning "Failed to set owner on ${path}: $_"
                        }
                    }

                    foreach ($path in $paths) {
                        if (Test-Path $path) {
                            try {
                                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                                Write-Verbose  "Deleted: $path"
                            }
                            catch {
                                Write-Warning "Failed to delete: $path - $_"
                            }
                        }
                        else {
                            Write-Verbose  "Path not found: $path"
                        }
                    }

                }

                Write-Verbose -Message "Dismount and save .wim"
                #Dismount-WindowsImage -Path $wimMountPath -Save
                # Attempt to unmount and save changes safely
                try {
                    Write-Verbose "Attempting to unmount .wim at $wimMountPath and save changes..."
                    Dismount-WindowsImage -Path $wimMountPath -Save -ErrorAction Stop
                    Write-Verbose "Unmount successful."
                }
                catch {
                    Write-Warning "Failed to unmount normally. Attempting discard..."
                    try {
                        Dismount-WindowsImage -Path $wimMountPath -Discard -ErrorAction Stop
                        Write-Verbose "Unmount discarded successfully."
                    }
                    catch {
                        Write-Warning "Still unable to unmount. Running DISM cleanup..."
                        dism /cleanup-wim
                        Write-Verbose "! DISM cleanup completed. Try removing $wimMountPath manually if it still exists !"
                    }
                }

                # remove mount folder if empty
                if (Test-Path $wimMountPath) {
                    $items = Get-ChildItem $wimMountPath -Force
                    if (-Not $items) {
                        Remove-Item $wimMountPath -Force -Recurse
                        Write-Verbose "Mount folder removed."
                    }
                }


                $expandWindowsImageParams = @{
                    ImagePath   = "$WimTempPath\install.wim";
                    ApplyPath   = '{0}:\' -f $vhdDriveLetter;
                    LogPath     = $logPath;
                    Index       = $wimImageIndex;
                    Verbose     = $true;
                    ErrorAction = 'Stop';
                }
            }

            $logName = '{0}.log' -f [System.IO.Path]::GetFileNameWithoutExtension($Vhd.Path);
            $logPath = Join-Path -Path $env:TEMP -ChildPath $logName;
            Write-Verbose -Message ($localized.ApplyingWindowsImage -f $wimImageIndex, $Vhd.Path);

            [ref] $null = Expand-WindowsImage @expandWindowsImageParams;
            if ($DeleteDefender -or $Commands) {
                Remove-Item $WimTempPath -Force -Recurse
                Write-Verbose -Message "Removed .wim temp file and folder."
            }
            [ref] $null = Get-PSDrive;

            ## Add additional packages (.cab) files
            if ($Package) {

                ## Default to relative package folder path
                $addLabImageWindowsPackageParams = @{
                    PackagePath     = '{0}:{1}' -f $isoDriveLetter, $PackagePath;
                    DestinationPath = '{0}:\' -f $vhdDriveLetter;
                    LogPath         = $logPath;
                    Package         = $Package;
                    PackageLocale   = $PackageLocale;
                    ErrorAction     = 'Stop';
                }
                if (-not $PackagePath.StartsWith('\')) {

                    ## Use the specified/literal path
                    $addLabImageWindowsPackageParams['PackagePath'] = $PackagePath;
                }
                [ref] $null = Add-LabImageWindowsPackage @addLabImageWindowsPackageParams;

            } #end if Package

            ## Add additional features if required
            if ($WindowsOptionalFeature) {

                ## Default to ISO relative source folder path
                $addLabImageWindowsOptionalFeatureParams = @{
                    ImagePath              = '{0}:{1}' -f $isoDriveLetter, $SourcePath;
                    DestinationPath        = '{0}:\' -f $vhdDriveLetter;
                    LogPath                = $logPath;
                    WindowsOptionalFeature = $WindowsOptionalFeature;
                    ErrorAction            = 'Stop';
                }
                if ($mediaFileInfo.Extension -eq '.WIM') {

                    ## The Windows optional feature source path for .WIM files is a literal path
                    $addLabImageWindowsOptionalFeatureParams['ImagePath'] = $SourcePath;
                }
                [ref] $null = Add-LabImageWindowsOptionalFeature @addLabImageWindowsOptionalFeatureParams;
            } #end if WindowsOptionalFeature

        }
        catch {

            Write-Error -Message $_;

        } #end catch
        finally {

            if ($mediaFileInfo.Extension -eq '.ISO') {

                ## Always dismount ISO (#166)
                Write-Verbose -Message ($localized.DismountingDiskImage -f $MediaPath);
                $null = Storage\Dismount-DiskImage -ImagePath $MediaPath;
            }

            ## Enable BitLocker (if required)
            Assert-BitLockerFDV

        } #end finally

    } #end process
}
