<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
## Suppress PSScriptAnalyzer errors for not using declared variables during AppVeyor build
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Suppresses AppVeyor errors on informational variables below")]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch { Write-Error "Failed to set the execution policy to Bypass for this process." }

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Autodesk'
	[string]$appName = 'Revit'
	[string]$appVersion = '2020'
	[string]$appArch = 'x64'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '6/18/2019'
	[string]$appScriptAuthor = 'Steve Patterson'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.6.9'
	[string]$deployAppScriptDate = '02/12/2017'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'acad' -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>
		## Uninstall AutoCAD 2019
		If (Test-Path -LiteralPath (Join-Path -Path $envSystemDrive -ChildPath "$envProgramFiles\Autodesk\AutoCAD 2019\acad.exe") -PathType 'Leaf') {
			Write-Log -Message 'AutoCAD 2019 Products will be uninstalled.' -Source $deployAppScriptFriendlyName
		# Uninstall Autodesk Material Library 2019
		 Execute-MSI -Action Uninstall -Path '{8F69EE2C-DC34-4746-9B47-7511147BD4B0}'
		# Uninstall Autodesk Material Library Base Resolution Image Library 2019
		 Execute-MSI -Action Uninstall -Path '{3AAA4C1B-51DA-487D-81A3-4234DBB9A8F9}'


		# Uninstall AutoCAD 2019
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2001-0000-0102-CF3F3A09B77D}'
		# Uninstall AutoCAD 2019 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2001-0409-1102-CF3F3A09B77D}'
		# Uninstall ACA & MEP 2019 Object Enabler
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2004-0000-5102-CF3F3A09B77D}'
		# Uninstall ACAD Private (2019)
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2001-0000-3102-CF3F3A09B77D}'
		# Uninstall AutoCAD 2019 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2001-0409-2102-CF3F3A09B77D}'
		# Uninstall AutoCAD Performance Feedback Tool 1.3.0
		Execute-MSI -Action Uninstall -Path '{448BC38C-2654-48CD-BB43-F59A37854A3E}'
		# Uninstall License Service (x64) - 7.1.4
		Execute-MSI -Action Uninstall -Path '{F53D6D10-7A75-4A39-8C53-A3D855C7C50A}'

		# Uninstall Autodesk Civil 3D 2019
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2000-0000-0102-CF3F3A09B77D}'
		# Uninstall Autodesk Civil 3D 2019 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2000-0409-1102-CF3F3A09B77D}'
		# Uninstall AutoCAD Architecture 2019 Shared
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2004-0000-4102-CF3F3A09B77D}'
		# Uninstall AutoCAD Architecture 2019 Language Shared - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2004-0409-4102-CF3F3A09B77D}'
		# Uninstall Autodesk AutoCAD Map 3D 2019 Core
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2002-0000-0102-CF3F3A09B77D}'
		# Uninstall Autodesk AutoCAD Map 3D 2019 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2002-0409-1102-CF3F3A09B77D}'
		# Uninstall Autodesk Vehicle Tracking 2019 (64 bit) Core
		Execute-MSI -Action Uninstall -Path '{F0089F74-0ED1-47CA-BEC0-53F1ACAEC68A}'
		# Uninstall Autodesk Civil 3D 2019 Private Pack
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2000-0000-3102-CF3F3A09B77D}'
		# Uninstall Autodesk Civil 3D 2019 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2000-0409-2102-CF3F3A09B77D}'
		# Uninstall Autodesk Rail Module Layout 2019
		Execute-MSI -Action Uninstall -Path '{F0D81F9D-6F82-43B9-ABF5-33947F5437DA}'
		# Uninstall Autodesk Storm and Sanitary Analysis 2019 x64 Plug-in
		Execute-MSI -Action Uninstall -Path '{58E36D07-2322-0000-8518-C854F44898ED}'
		# Uninstall Autodesk Subassembly Composer 2019
		Execute-MSI -Action Uninstall -Path '{33CFED50-0FAD-442A-84FA-4D26DB59E332}'

		# Uninstall AutoCAD Electrical 2019
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2007-0000-0102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2019 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2007-0409-1102-CF3F3A09B77D}'
		# Uninstall ACADE Private
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2007-0000-3102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2019 Content Pack
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2007-0000-5102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2019 Content Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2007-0409-6102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2019 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2007-0409-2102-CF3F3A09B77D}'

		# Uninstall AutoCAD Mechanical 2019
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2005-0000-0102-CF3F3A09B77D}'
		# Uninstall AutoCAD Mechanical 2019 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2005-0409-1102-CF3F3A09B77D}'
		# Uninstall ACM Private
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2005-0000-3102-CF3F3A09B77D}'
		# Uninstall AutoCAD Mechanical 2018 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-2005-0409-2102-CF3F3A09B77D}'

		# Uninstall Revit 2019
		Execute-MSI -Action Uninstall -Path '{7346B4A0-1900-0510-0000-705C0D862004}'
		# Uninstall Revit Content Libraries 2019
		Execute-MSI -Action Uninstall -Path '{941030D0-1900-0410-0000-818BB38A95FC}'
		# Uninstall Autodesk Collaboration for Revit 2019
		Execute-MSI -Action Uninstall -Path '{AA384BE4-1901-0010-0000-97E7D7D00B17}'
		# Uninstall Personal Accelerator for Revit
		Execute-MSI -Action Uninstall -Path '{7C317DB0-F399-4024-A289-92CF4B6FB256}'
		# Uninstall Batch Print for Autodesk Revit 2019
		Execute-MSI -Action Uninstall -Path '{82AF00E4-1901-0010-0000-FCE0F87063F9}'
		# Uninstall eTransmit for Autodesk Revit 2019
		Execute-MSI -Action Uninstall -Path '{4477F08B-1901-0010-0000-9A09D834DFF5}'
		# Uninstall Autodesk Revit Model Review 2019
		Execute-MSI -Action Uninstall -Path '{715812E8-1901-0010-0000-BBB894911B46}'
		# Uninstall Worksharing Monitor for Autodesk Revit 2019
		Execute-MSI -Action Uninstall -Path '{5063E738-1901-0010-0000-7B7B9AB0B696}'
		# Uninstall Autodesk Material Library Low Resolution Image Library 2019
		Execute-MSI -Action Uninstall -Path '{77F779B8-3262-4014-97E9-36D6933A1904}'
		# Uninstall Autodesk Advanced Material Library Base Resolution Image Library 2019
		Execute-MSI -Action Uninstall -Path '{105181A1-013C-4EE7-A368-999FD7ED950A}'
		# Uninstall Autodesk Advanced Material Library Low Resolution Image Library 2019
		Execute-MSI -Action Uninstall -Path '{ACC0DD09-7E20-4792-87D5-BDBE40206584}'
		# Uninstall IronPython 2.7.3
		Execute-MSI -Action Uninstall -Path '{1EBADAEA-1A0F-40E3-848C-0DD8C5E5A10D}'
		# Uninstall Dynamo Core 1.3.3
		Execute-MSI -Action Uninstall -Path '{F1AA809A-3D47-4FB9-8854-93E070C66A20}'
		# Uninstall Dynamo Revit 1.3.3
		Execute-MSI -Action Uninstall -Path '{DE076F37-60CA-4BDC-A5A3-B300DEA4358C}'
		# Uninstall FormIt Converter for Revit 2019
		Execute-MSI -Action Uninstall -Path '{5E47699C-B0DE-443F-92AE-1D1334499D5E}'
		# Uninstall Autodesk Revit 2019 MEP Fabrication Configuration - Imperial
		Execute-MSI -Action Uninstall -Path '{7B1D0D58-E2A9-400B-9663-86FD56CB44B9}'
		# Uninstall Autodesk Revit 2019 MEP Fabrication Configuration - Metric
		Execute-MSI -Action Uninstall -Path '{8E6AEB11-ECE7-475A-BB7D-1D6719B2F8BA}'
		# Uninstall Autodesk Material Library Medium Resolution Image Library 2019
		Execute-MSI -Action Uninstall -Path '{2E819775-E94C-42CC-9C5D-ABB2ADABC7C2}'
		# Uninstall Autodesk Advanced Material Library Medium Resolution Image Library 2019
		Execute-MSI -Action Uninstall -Path '{078698AF-8BB1-4631-86D0-D91FEE147256}'
}


		## Uninstall AutoCAD 2018
		If (Test-Path -LiteralPath (Join-Path -Path $envSystemDrive -ChildPath "$envProgramFiles\Autodesk\AutoCAD 2018\acad.exe") -PathType 'Leaf') {
			Write-Log -Message 'AutoCAD Products will be uninstalled.' -Source $deployAppScriptFriendlyName
			#Uninstall all AutoCAD 2018 Products
			# Uninstall Autodesk Material Library 2018
			Execute-MSI -Action Uninstall -Path '{7847611E-92E9-4917-B395-71C91D523104}'
			# Uninstall Autodesk Material Library Base Resolution Image Library 2018
			Execute-MSI -Action Uninstall -Path '{FCDED119-A969-4E48-8A32-D21AD6B03253}'
			# Uninstall Autodesk Advanced Material Library Image Library 2018
			Execute-MSI -Action Uninstall -Path '{177AD7F6-9C77-4E50-BA53-B7259C5F282D}'

			# Uninstall AutoCAD 2018
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1001-0000-0102-CF3F3A09B77D}'
			# Uninstall AutoCAD 2018 Language Pack - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1001-0409-1102-CF3F3A09B77D}'
			# Uninstall ACA & MEP 2018 Object Enabler
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1004-0000-5102-CF3F3A09B77D}'
			# Uninstall ACAD Private
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1001-0000-3102-CF3F3A09B77D}'
			# Uninstall AutoCAD 2018 - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1001-0409-2102-CF3F3A09B77D}'

			# Uninstall Autodesk AutoCAD Civil 3D 2018
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1000-0000-0102-CF3F3A09B77D}'
			# Uninstall Autodesk AutoCAD Civil 3D 2018 Language Pack - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1000-0409-1102-CF3F3A09B77D}'
			# Uninstall AutoCAD Architecture 2018 Shared
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1004-0000-4102-CF3F3A09B77D}'
			# Uninstall AutoCAD Architecture 2018 Language Shared - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1004-0409-4102-CF3F3A09B77D}'
			# Uninstall Autodesk AutoCAD Map 3D 2018 Core
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1002-0000-0102-CF3F3A09B77D}'
			# Uninstall Autodesk AutoCAD Map 3D 2018 Language Pack - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1002-0409-1102-CF3F3A09B77D}'
			# Uninstall Autodesk Vehicle Tracking 2018 (64 bit) Core
			Execute-MSI -Action Uninstall -Path '{9BB641F3-24B1-427E-A850-1C02157219EC}'
			# Uninstall Autodesk AutoCAD Civil 3D 2018 Private Pack
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1000-0000-3102-CF3F3A09B77D}'
			# Uninstall Autodesk AutoCAD Civil 3D 2018 - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1000-0409-2102-CF3F3A09B77D}'

			# Uninstall AutoCAD Electrical 2018
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1007-0000-0102-CF3F3A09B77D}'
			# Uninstall AutoCAD Electrical 2018 Language Pack - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1007-0409-1102-CF3F3A09B77D}'
			# Uninstall ACADE Private
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1007-0000-3102-CF3F3A09B77D}'
			# Uninstall AutoCAD Electrical 2018 Content Pack
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1007-0000-5102-CF3F3A09B77D}'
			# Uninstall AutoCAD Electrical 2018 Content Language Pack - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1007-0409-6102-CF3F3A09B77D}'
			# Uninstall AutoCAD Electrical 2018 - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1007-0409-2102-CF3F3A09B77D}'

			# Uninstall AutoCAD Mechanical 2018
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1005-0000-0102-CF3F3A09B77D}'
			# Uninstall AutoCAD Mechanical 2018 Language Pack - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1005-0409-1102-CF3F3A09B77D}'
			# Uninstall ACM Private
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1005-0000-3102-CF3F3A09B77D}'
			# Uninstall AutoCAD Mechanical 2018 - English
			Execute-MSI -Action Uninstall -Path '{28B89EEF-1005-0409-2102-CF3F3A09B77D}'

			# Uninstall Revit 2018
			Execute-MSI -Action Uninstall -Path '{7346B4A0-1800-0510-0000-705C0D862004}'
			# Uninstall Autodesk Collaboration for Revit 2018
			Execute-MSI -Action Uninstall -Path '{AA384BE4-1800-0010-0000-97E7D7D00B17}'
			# Uninstall Personal Accelerator for Revit
			Execute-MSI -Action Uninstall -Path '{7C317DB0-F399-4024-A289-92CF4B6FB256}'
			# Uninstall Batch Print for Autodesk Revit 2018
			Execute-MSI -Action Uninstall -Path '{82AF00E4-1800-0010-0000-FCE0F87063F9}'
			# Uninstall eTransmit for Autodesk Revit 2018
			Execute-MSI -Action Uninstall -Path '{4477F08B-1800-0010-0000-9A09D834DFF5}'
			# Uninstall Autodesk Revit Model Review 2018
			Execute-MSI -Action Uninstall -Path '{715812E8-1800-0010-0000-BBB894911B46}'
			# Uninstall Worksharing Monitor for Autodesk Revit 2018
			Execute-MSI -Action Uninstall -Path '{5063E738-1800-0010-0000-7B7B9AB0B696}'
			# Uninstall Dynamo Revit 1.2.2
			Execute-MSI -Action Uninstall -Path '{0FF47E28-76A5-44BA-8EEF-58824252F528}'
		}

		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>

				# Install AutoCAD 2020
		#Execute-Process -Path "$dirFiles\Img\Setup.exe" -Parameters '/W /Q /I AutoCAD2020.ini' -WindowStyle 'Hidden' -PassThru
				# Install AutoCAD Civil 3D 2020
		#Execute-Process -Path "$dirFiles\Img\Setup.exe" -Parameters '/W /Q /I Civil3D2020.ini' -WindowStyle 'Hidden' -PassThru
				# Install AutoCAD Electrical 2020
		#Execute-Process -Path "$dirFiles\Img\Setup.exe" -Parameters '/W /Q /I AutoCAD2020Electrical.ini' -WindowStyle 'Hidden' -PassThru
				# Install AutoCAD Mechanical 2020
		#Execute-Process -Path "$dirFiles\Img\Setup.exe" -Parameters '/W /Q /I AutoCAD2020Mechanical.ini' -WindowStyle 'Hidden' -PassThru
				# Install Revit 2020
		Execute-Process -Path "$dirFiles\Img\Setup.exe" -Parameters '/W /Q /I Revit2020.ini' -WindowStyle 'Hidden' -PassThru


		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		## Display a message at the end of the install
		If (-not $useDefaultMsi) {Show-InstallationPrompt -Message ‘'$appVendor' '$appName' '$appVersion' has been Sucessfully Installed.’ -ButtonRightText ‘OK’ -Icon Information -NoWait}
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'acad' -CloseAppsCountdown 60

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>

		# Shared Components
		# Uninstall Autodesk Material Library 2020
		Execute-MSI -Action Uninstall -Path '{B9312A51-41B5-479D-9F72-E7448A2D89AF}'
		# Uninstall Autodesk Material Library Base Resolution Image Library 2020
		Execute-MSI -Action Uninstall -Path '{0E976988-E753-4C81-BD96-434CE305B176}'
		# Uninstall Autodesk Save to Web and Mobile
		Execute-MSI -Action Uninstall -Path '{26FB18F7-B553-430D-94F6-C2389A91235F}'
		# Uninstall Autodesk Single Sign On Component
		Execute-MSI -Action Uninstall -Path '{E3807FC8-DD0A-4D6D-89E9-EAADE00C845C}'


		# Uninstall AutoCAD 2020
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3001-0000-0102-CF3F3A09B77D}'
		# Uninstall AutoCAD 2020 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3001-0409-1102-CF3F3A09B77D}'
		# Uninstall ACA & MEP 2020 Object Enabler
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3004-0000-5102-CF3F3A09B77D}'
		# Uninstall ACAD Private (2020)
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3001-0000-3102-CF3F3A09B77D}'
		# Uninstall AutoCAD 2020 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3001-0409-2102-CF3F3A09B77D}'
		# Uninstall Autodesk Genuine Service
		# Execute-MSI -Action Uninstall -Path '{317D67F2-9027-4E85-9ED1-ADF4D765AE02}'
        # Genuine Service is not uninstalling if it has been installed in the past 24 hours. Testing different Uninstall method below
        # Execute-Process -Path "$envProgramFilesX86\Common Files\Autodesk Shared\AdskLicensing\uninstall.exe" -Parameters '/silent' -WindowStyle 'Hidden'

		# Uninstall Autodesk Civil 3D 2020
	  Execute-MSI -Action Uninstall -Path '{28B89EEF-3000-0000-0102-CF3F3A09B77D}'
		# Uninstall Autodesk Civil 3D 2020 Language Pack - English
	  Execute-MSI -Action Uninstall -Path '{28B89EEF-3000-0409-1102-CF3F3A09B77D}'
		# Uninstall AutoCAD Architecture 2020 Shared
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3004-0000-4102-CF3F3A09B77D}'
		# Uninstall AutoCAD Architecture 2020 Language Shared - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3004-0409-4102-CF3F3A09B77D}'
		# Uninstall Autodesk AutoCAD Map 3D 2020 Core
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3002-0000-0102-CF3F3A09B77D}'
		# Uninstall Autodesk AutoCAD Map 3D 2020 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3002-0409-1102-CF3F3A09B77D}'
		# Uninstall Autodesk Vehicle Tracking 2020 (64 bit) Core
		Execute-MSI -Action Uninstall -Path '{2C12D147-23A0-4C6B-8E1D-F29C04C2F80E}'
		# Uninstall Autodesk Civil 3D 2020 Private Pack
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3000-0000-3102-CF3F3A09B77D}'
		# Uninstall Autodesk Civil 3D 2020 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3000-0409-2102-CF3F3A09B77D}'
		# Uninstall Autodesk Storm and Sanitary Analysis 2020 x64 Plug-in
		Execute-MSI -Action Uninstall -Path '{58E36D07-2422-0000-8518-C854F44898ED}'
		# Uninstall Autodesk Subassembly Composer 2020
		Execute-MSI -Action Uninstall -Path '{33CFED50-3000-442A-84FA-4D26DB59E332}'

		# Uninstall AutoCAD Electrical 2020
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3007-0000-0102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2020 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3007-0409-1102-CF3F3A09B77D}'
		# Uninstall ACADE Private
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3007-0000-3102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2020 Content Pack
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3007-0000-5102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2020 Content Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3007-0409-6102-CF3F3A09B77D}'
		# Uninstall AutoCAD Electrical 2020 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3007-0409-2102-CF3F3A09B77D}'

		# Uninstall AutoCAD Mechanical 2020
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3005-0000-0102-CF3F3A09B77D}'
		# Uninstall AutoCAD Mechanical 2020 Language Pack - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3005-0409-1102-CF3F3A09B77D}'
		# Uninstall ACM Private
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3005-0000-3102-CF3F3A09B77D}'
		# Uninstall AutoCAD Mechanical 2020 - English
		Execute-MSI -Action Uninstall -Path '{28B89EEF-3005-0409-2102-CF3F3A09B77D}'

		# Uninstall Revit 2020
		Execute-MSI -Action Uninstall -Path '{7346B4A0-2000-0510-0000-705C0D862004}'
		# Uninstall Revit Content Libraries 2020
		Execute-MSI -Action Uninstall -Path '{941030D0-2000-0410-0000-818BB38A95FC}'
		# Uninstall Autodesk Cloud Models for Revit 2020
		Execute-MSI -Action Uninstall -Path '{AA384BE4-2001-0010-0000-97E7D7D00B17}'
		# Uninstall Personal Accelerator for Revit
		Execute-MSI -Action Uninstall -Path '{533DE806-7EC5-4A73-841B-007110126A75}'
		# Uninstall Batch Print for Autodesk Revit 2020
		Execute-MSI -Action Uninstall -Path '{82AF00E4-2001-0010-0000-FCE0F87063F9}'
		# Uninstall eTransmit for Autodesk Revit 2020
		Execute-MSI -Action Uninstall -Path '{4477F08B-2001-0010-0000-9A09D834DFF5}'
		# Uninstall Autodesk Revit Model Review 2020
		Execute-MSI -Action Uninstall -Path '{715812E8-2001-0010-0000-BBB894911B46}'
		# Uninstall Worksharing Monitor for Autodesk Revit 2020
		Execute-MSI -Action Uninstall -Path '{5063E738-2001-0010-0000-7B7B9AB0B696}'
		# Uninstall Autodesk Material Library Low Resolution Image Library 2020
		Execute-MSI -Action Uninstall -Path '{77F779B8-3262-4014-97E9-36D6933A1904}'
		# Uninstall Autodesk Advanced Material Library Base Resolution Image Library 2020
		Execute-MSI -Action Uninstall -Path '{FF27FA47-6E0F-4654-A435-19916B297565}'
		# Uninstall Autodesk Advanced Material Library Low Resolution Image Library 2020
		Execute-MSI -Action Uninstall -Path '{042B92EF-929A-40B1-9578-DA8363208D02}'
		# Uninstall FormIt Converter for Revit 2020
		Execute-MSI -Action Uninstall -Path '{7A22DBAA-79A6-4C7B-98FA-9157A97EF6DA}'
		# Uninstall Autodesk Revit 2020 Revit MEP Imperial Content
		Execute-MSI -Action Uninstall -Path '{38AEB114-D437-4695-B390-6D03723F32E0}'
		# Uninstall Autodesk Revit 2020 Revit MEP Metric Content
		Execute-MSI -Action Uninstall -Path '{6504036D-FF6D-41E0-B3FE-3193E9BC2047}'
		# Uninstall Autodesk Material Library Medium Resolution Image Library 2020
		Execute-MSI -Action Uninstall -Path '{B52B3C0C-F56D-44CB-AC81-F86BCBB7550F}'
		# Uninstall Autodesk Advanced Material Library Medium Resolution Image Library 2020
		Execute-MSI -Action Uninstall -Path '{0F682C15-79B0-4E6F-A2F4-56BC8CD43F1F}'



		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>


	}

	##*===============================================
	##* END SCRIPT BODY
	##*===============================================


	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}

# SIG # Begin signature block
# MIIOaQYJKoZIhvcNAQcCoIIOWjCCDlYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUOkwL5NyXQ9fGZ2yYz46L39/l
# Pe6ggguhMIIFrjCCBJagAwIBAgIQBwNx0Q95WkBxmSuUB2Kb4jANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzELMAkGA1UECBMCTUkxEjAQBgNVBAcTCUFubiBB
# cmJvcjESMBAGA1UEChMJSW50ZXJuZXQyMREwDwYDVQQLEwhJbkNvbW1vbjElMCMG
# A1UEAxMcSW5Db21tb24gUlNBIENvZGUgU2lnbmluZyBDQTAeFw0xODA2MjEwMDAw
# MDBaFw0yMTA2MjAyMzU5NTlaMIG5MQswCQYDVQQGEwJVUzEOMAwGA1UEEQwFODAy
# MDQxCzAJBgNVBAgMAkNPMQ8wDQYDVQQHDAZEZW52ZXIxGDAWBgNVBAkMDzEyMDEg
# NXRoIFN0cmVldDEwMC4GA1UECgwnTWV0cm9wb2xpdGFuIFN0YXRlIFVuaXZlcnNp
# dHkgb2YgRGVudmVyMTAwLgYDVQQDDCdNZXRyb3BvbGl0YW4gU3RhdGUgVW5pdmVy
# c2l0eSBvZiBEZW52ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL
# V4koxA42DQSGF7D5xRh8Gar0uZYETUmkI7MsYC7BiOsiywwqWmMtwgcDdaJ+EJ2M
# xEKbB1fkyf9yutWb6gMYUegJ8PE41Y2gd5D3bSiYxFJYIlzStJw0cjFWrGcnlwC0
# eUk0n9UsaDLfByA3dCkwfMoTBOnsxXRc8AeR3tv48jrMH2LDfp+JNkPVHGlbVoAs
# 1rmt/Wp8Db2uzOBroDzuWZBel5Kxs0R6V3LVfxZOi5qj2OrEZuOZ0nJwtSkNzTf7
# emQR85gLYG2WuNaOfgLzXZL/U1RektzgxqX96ilvJIxbfNiy2HWYtFdO5Z/kvwbQ
# JRlDzr6npuBJGzLWeTNzAgMBAAGjggHsMIIB6DAfBgNVHSMEGDAWgBSuNSMX//8G
# PZxQ4IwkZTMecBCIojAdBgNVHQ4EFgQUpemIbrz5SKX18ziKvmP5pAxjmw8wDgYD
# VR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwMw
# EQYJYIZIAYb4QgEBBAQDAgQQMGYGA1UdIARfMF0wWwYMKwYBBAGuIwEEAwIBMEsw
# SQYIKwYBBQUHAgEWPWh0dHBzOi8vd3d3LmluY29tbW9uLm9yZy9jZXJ0L3JlcG9z
# aXRvcnkvY3BzX2NvZGVfc2lnbmluZy5wZGYwSQYDVR0fBEIwQDA+oDygOoY4aHR0
# cDovL2NybC5pbmNvbW1vbi1yc2Eub3JnL0luQ29tbW9uUlNBQ29kZVNpZ25pbmdD
# QS5jcmwwfgYIKwYBBQUHAQEEcjBwMEQGCCsGAQUFBzAChjhodHRwOi8vY3J0Lmlu
# Y29tbW9uLXJzYS5vcmcvSW5Db21tb25SU0FDb2RlU2lnbmluZ0NBLmNydDAoBggr
# BgEFBQcwAYYcaHR0cDovL29jc3AuaW5jb21tb24tcnNhLm9yZzAtBgNVHREEJjAk
# gSJpdHNzeXN0ZW1lbmdpbmVlcmluZ0Btc3VkZW52ZXIuZWR1MA0GCSqGSIb3DQEB
# CwUAA4IBAQCHNj1auwWplgLo8gkDx7Bgg2zN4tTmOZ67gP3zrWyepib0/VCWOPut
# YK3By81e6KdctJ0YVeOfU6ynxyjuNrkcmaXZx2jqAtPNHH4P9BMBSUct22AdL5FT
# /E3lJL1IW7XD1aHyNT/8IfWU9omFQnqzjgKor8VqofA7fvKEm40hoTxVsrtOG/FH
# M2yv/e7l3YCtMzXFwyVIzCq+gm3r3y0C30IhT4s2no/tn70f42RwL8TvVtq4Xejc
# OoBbNqtz+AhStPsgJBQi5PvcLKfkbEb0ZL3ViafmpzbwCjslXwo+rM+XUDwCGCMi
# 4cvc3t7WlSpvfQ0EGVf8DfwEzw37SxptMIIF6zCCA9OgAwIBAgIQZeHi49XeUEWF
# 8yYkgAXi1DANBgkqhkiG9w0BAQ0FADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Ck5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVUaGUg
# VVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBSU0EgQ2VydGlm
# aWNhdGlvbiBBdXRob3JpdHkwHhcNMTQwOTE5MDAwMDAwWhcNMjQwOTE4MjM1OTU5
# WjB8MQswCQYDVQQGEwJVUzELMAkGA1UECBMCTUkxEjAQBgNVBAcTCUFubiBBcmJv
# cjESMBAGA1UEChMJSW50ZXJuZXQyMREwDwYDVQQLEwhJbkNvbW1vbjElMCMGA1UE
# AxMcSW5Db21tb24gUlNBIENvZGUgU2lnbmluZyBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAMCgL4seertqdaz4PtyjujkiyvOjduS/fTAn5rrTmDJW
# I1wGhpcNgOjtooE16wv2Xn6pPmhz/Z3UZ3nOqupotxnbHHY6WYddXpnHobK4qYRz
# DMyrh0YcasfvOSW+p93aLDVwNh0iLiA73eMcDj80n+V9/lWAWwZ8gleEVfM4+/IM
# Nqm5XrLFgUcjfRKBoMABKD4D+TiXo60C8gJo/dUBq/XVUU1Q0xciRuVzGOA65Dd3
# UciefVKKT4DcJrnATMr8UfoQCRF6VypzxOAhKmzCVL0cPoP4W6ks8frbeM/ZiZpt
# o/8Npz9+TFYj1gm+4aUdiwfFv+PfWKrvpK+CywX4CgkCAwEAAaOCAVowggFWMB8G
# A1UdIwQYMBaAFFN5v1qqK0rPVIDh2JvAnfKyA2bLMB0GA1UdDgQWBBSuNSMX//8G
# PZxQ4IwkZTMecBCIojAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIB
# ADATBgNVHSUEDDAKBggrBgEFBQcDAzARBgNVHSAECjAIMAYGBFUdIAAwUAYDVR0f
# BEkwRzBFoEOgQYY/aHR0cDovL2NybC51c2VydHJ1c3QuY29tL1VTRVJUcnVzdFJT
# QUNlcnRpZmljYXRpb25BdXRob3JpdHkuY3JsMHYGCCsGAQUFBwEBBGowaDA/Bggr
# BgEFBQcwAoYzaHR0cDovL2NydC51c2VydHJ1c3QuY29tL1VTRVJUcnVzdFJTQUFk
# ZFRydXN0Q0EuY3J0MCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3Qu
# Y29tMA0GCSqGSIb3DQEBDQUAA4ICAQBGLLZ/ak4lZr2caqaq0J69D65ONfzwOCfB
# x50EyYI024bhE/fBlo0wRBPSNe1591dck6YSV22reZfBJmTfyVzLwzaibZMjoduq
# MAJr6rjAhdaSokFsrgw5ZcUfTBAqesReMJx9THLOFnizq0D8vguZFhOYIP+yunPR
# tVTcC5Jf6aPTkT5Y8SinhYT4Pfk4tycxyMVuy3cpY333HForjRUedfwSRwGSKlA8
# Ny7K3WFs4IOMdOrYDLzhH9JyE3paRU8albzLSYZzn2W6XV2UOaNU7KcX0xFTkALK
# dOR1DQl8oc55VS69CWjZDO3nYJOfc5nU20hnTKvGbbrulcq4rzpTEj1pmsuTI78E
# 87jaK28Ab9Ay/u3MmQaezWGaLvg6BndZRWTdI1OSLECoJt/tNKZ5yeu3K3RcH8//
# G6tzIU4ijlhG9OBU9zmVafo872goR1i0PIGwjkYApWmatR92qiOyXkZFhBBKek7+
# FgFbK/4uy6F1O9oDm/AgMzxasCOBMXHa8adCODl2xAh5Q6lOLEyJ6sJTMKH5sXju
# LveNfeqiKiUJfvEspJdOlZLajLsfOCMN2UCx9PCfC2iflg1MnHODo2OtSOxRsQg5
# G0kH956V3kRZtCAZ/Bolvk0Q5OidlyRS1hLVWZoW6BZQS6FJah1AirtEDoVP/gBD
# qp2PfI9s0TGCAjIwggIuAgEBMIGQMHwxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJN
# STESMBAGA1UEBxMJQW5uIEFyYm9yMRIwEAYDVQQKEwlJbnRlcm5ldDIxETAPBgNV
# BAsTCEluQ29tbW9uMSUwIwYDVQQDExxJbkNvbW1vbiBSU0EgQ29kZSBTaWduaW5n
# IENBAhAHA3HRD3laQHGZK5QHYpviMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEM
# MQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQ/3LZ/G9TtwJHP
# ukbzLnJtCya9uDANBgkqhkiG9w0BAQEFAASCAQClRidPACZpNF0NjIXwOqgQiaJY
# RBuOivxwLm/YHlukmIhs3b2MqYd0l/I8w97pbYLjkIO6GO1e6f4r5DCoQppXu0NQ
# yCpuK4wRgO9m02wR5JX3TtPQmKDqPrzdrlRKYLLYYc+VRaKrMtHrcVAm5lXi8BSC
# 13BXRZlGrTN+5eZgdqlFkbybnV/5sWg+wdrpILErvOxRn6nxvZxCEoEGNjf2libY
# AgqI7jAEZolrwVoREso0BB+IeBoiFcgxQ+oCPvv7hCuF4YM3cw6G2fGqGenG3TF/
# PViMe0iAoeyXN4ZwLle6/c0trQZr7VD8o7wYMFftpe6UHardhYPSf4CYLpul
# SIG # End signature block
