[CmdletBinding()]
param(
    [Parameter(Mandatory = $False)] [String] $MediaPath = "", 
    [Parameter(Mandatory = $False)] [String] $TaskSequenceID = "",
    [Parameter(Mandatory = $False)] [String] $DestinationPath = "",
    [Parameter(Mandatory = $False)] [String] $IntuneWinAppUtil = ".\IntuneWinAppUtil.exe"
)

# Create a temporary folder to hold everything
$buildFolder = "$($env:TEMP)\MDTIntune"
if (Test-Path $buildFolder) {
    # Clean up any previous run
    RmDir $buildFolder -Recurse -Force | Out-Null
}
MkDir $buildFolder -ErrorAction SilentlyContinue | Out-Null

# Create an INI file to filter the WIM
$exclusionList = @'
[ExclusionList]
\Content\Deploy\Boot
\Content\Deploy\Backup
'@
$exclusionList | Out-File -FilePath "$buildFolder\ExclusionList.ini"

# Capture a WIM into the folder from the media path
& dism.exe /capture-image /ImageFile:"$buildFolder\Media.wim" /CaptureDir:"$mediaPath" /Name:"MEDIA" /Compress:Max /ConfigFile:"$buildFolder\ExclusionList.ini" | Out-Null
Write-Host "Image captured to temporary folder."

# Add a PowerShell script into the same folder to run the task sequence
$runTS = @'
# Create a folder to mount the WIM
$mountDir = "$($env:TEMP)\MDTIntuneMount"
MkDir $mountDir -ErrorAction SilentlyContinue | Out-Null

# Mount the WIM in that folder
Mount-WindowsImage -ImagePath "$PSScriptRoot\Media.wim" -Index 1 -Path $mountDir -ReadOnly

# Start the task sequence and wait for it to finish
& wscript.exe "$mountDir\Content\Deploy\Scripts\LiteTouch.vbs" /DeployRoot:"$mountDir\Content\Deploy" /TaskSequenceID:TSID /SkipWizard:YES /SkipWelcome:YES /SkipFinalSummary:YES | Out-Host

# Unmount and clean up
Dismount-WindowsImage -Path $mountDir -Discard
RmDir $mountDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

# Create a tag file to show we are installed
"tag" | Out-File -FilePath "$($env:ProgramData)\MDTIntune.tag"

'@ -replace "TSID", $TaskSequenceID
$runTS | Out-File -FilePath "$buildFolder\MDTIntune.ps1"

# Capture the .intunewin file from that folder
& $IntuneWinAppUtil -c "$buildFolder" -s MDTIntune.ps1 -o "$destinationPath" -q | Out-Host
Write-Host "Created $destinationPath\MDTIntune.intunewin"

# Remove the build folder
#RmDir $buildFolder -Recurse -Force | Out-Null