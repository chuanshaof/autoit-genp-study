; =====================================================================
; Firewall.au3  -  Application module.
; Functions (21):
;   - _CollectNGLBinaries
;   - _WinFirewallServiceReady
;   - _GetExistingNGLRuleProgs
;   - RemoveAGS
;   - _FindAcrobatDCAGS
;   - InstallAGSDummy
;   - RestoreAGSDummy
;   - CheckThirdPartyFirewall
;   - FindApps
;   - RuleExists
;   - ShowFirewallStatus
;   - RemoveFirewallRules
;   - CreateFirewallRules
;   - _WriteListToNotepad
;   - _EnableNGLFirewallRules
;   - _InjectNglApps
;   - ShowAppSelectionGUI
;   - CheckParentCheckboxes
;   - ShowToggleRulesGUI
;   - EnableAllFWRules
;   - DisableAllFWRules
; =====================================================================

Func _CollectNGLBinaries()
	Local $aOut[0]
	Local $aDrives = DriveGetDrive("FIXED")
	If @error Then Return $aOut
	Local $aRel = $g_aNGLRelativePaths
	For $d = 1 To $aDrives[0]
		Local $sRoot = StringUpper($aDrives[$d])
		Local $aBase[3] = [$sRoot & "\Program Files\", $sRoot & "\Program Files (x86)\", $sRoot & "\"]
		For $b = 0 To 2
			For $p = 0 To UBound($aRel) - 1
				Local $sTarget = StringRegExpReplace($aBase[$b] & $aRel[$p], "\\\\+", "\\")
				If FileExists($sTarget) Then _ArrayAdd($aOut, $sTarget)
			Next
		Next
	Next
	Return $aOut
EndFunc

Func _WinFirewallServiceReady()
	Local $iPID = Run('powershell.exe -NoProfile -Command "(Get-Service -Name MpsSvc -ErrorAction SilentlyContinue).Status"', "", @SW_HIDE, $STDOUT_CHILD)
	ProcessWaitClose($iPID, 5000)
	Return StringInStr(StringStripWS(StdoutRead($iPID), 3), "Running") > 0
EndFunc

Func _GetExistingNGLRuleProgs($sGroup)
	Local $mDict = ObjCreate("Scripting.Dictionary")
	Local $sInner = "Get-NetFirewallRule -Group '" & $sGroup & "' -ErrorAction SilentlyContinue | Get-NetFirewallApplicationFilter | Select-Object -ExpandProperty Program"
	Local $iPID = Run('powershell.exe -NoProfile -Command "' & $sInner & '"', "", @SW_HIDE, $STDOUT_CHILD)
	ProcessWaitClose($iPID, 8000)
	Local $aLines = StringSplit(StringStripWS(StdoutRead($iPID), 3), @CRLF, 1)
	For $i = 1 To $aLines[0]
		Local $sL = StringStripWS($aLines[$i], 3)
		If $sL <> "" Then $mDict.Item(StringLower($sL)) = 1
	Next
	Return $mDict
EndFunc

Func RemoveAGS()
	If Not _RequireAdmin("remove AGS") Then Return
	GUICtrlSetState($idBtnRemoveAGS, $GUI_DISABLE)
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	MemoWrite(@CRLF & "Removing AGS from this Computer" & @CRLF & "---" & @CRLF & "Please wait...")

	Local $aServices = ["AGMService", "AGSService"]
	Local $ProgramFilesX86 = EnvGet("ProgramFiles(x86)")
	Local $PublicDir = EnvGet("PUBLIC")
	Local $WinDir = @WindowsDir
	Local $LocalAppData = EnvGet("LOCALAPPDATA")
	Local $AcrobatDCAGS = _FindAcrobatDCAGS()
	Local $aPaths[10] = [ _
			$ProgramFilesX86 & "\Common Files\Adobe\Adobe Desktop Common\AdobeGenuineClient\AGSService.exe", _
			$ProgramFilesX86 & "\Common Files\Adobe\AdobeGCClient", _
			$ProgramFilesX86 & "\Common Files\Adobe\OOBE\PDApp\AdobeGCClient", _
			$PublicDir & "\Documents\AdobeGCData", _
			$WinDir & "\System32\Tasks\AdobeGCInvoker-1.0", _
			$WinDir & "\System32\Tasks_Migrated\AdobeGCInvoker-1.0", _
			$ProgramFilesX86 & "\Adobe\Adobe Creative Cloud\Utils\AdobeGenuineValidator.exe", _
			$WinDir & "\Temp\adobegc.log", _
			$LocalAppData & "\Temp\adobegc.log", _
			$AcrobatDCAGS _
			]

	Local $iServiceSuccess = 0
	For $sService In $aServices
		Local $iExistCode = RunWait("sc query " & $sService, "", @SW_HIDE)
		If $iExistCode = 1060 Then
			LogWrite(1, "Service not found: " & $sService)
			ContinueLoop
		ElseIf $iExistCode <> 0 Then
			LogWrite(1, "Error checking service " & $sService & " (exit code: " & $iExistCode & ")")
			ContinueLoop
		EndIf
		LogWrite(1, "Service found: " & $sService)

		Local $iStopPID = Run("sc stop " & $sService, "", @SW_HIDE, $STDERR_CHILD)
		Local $iTimeout = 10000
		Local $iWaitResult = ProcessWaitClose($iStopPID, $iTimeout)
		If $iWaitResult = 0 Then
			ProcessClose($iStopPID)
			LogWrite(1, "Warning: Failed to stop " & $sService & " - timed out after " & $iTimeout & "ms")
		Else
			Local $iStopCode = @error ? 1 : 0
			If $iStopCode = 0 Or StringInStr(StderrRead($iStopPID), "1052") Then
				LogWrite(1, "Service stopped: " & $sService)
			Else
				LogWrite(1, "Failed to stop service " & $sService & " (possible error)")
			EndIf
		EndIf

		Local $iDeletePID = Run("sc delete " & $sService, "", @SW_HIDE, $STDERR_CHILD)
		$iWaitResult = ProcessWaitClose($iDeletePID, $iTimeout)
		If $iWaitResult = 0 Then
			ProcessClose($iDeletePID)
			LogWrite(1, "Warning: Failed to delete " & $sService & " - timed out after " & $iTimeout & "ms")
		Else
			Local $iDeleteCode = @error ? 1 : 0
			If $iDeleteCode = 0 Then
				LogWrite(1, "Service deleted: " & $sService)
				$iServiceSuccess += 1
			Else
				LogWrite(1, "Failed to delete service " & $sService & " (possible error)")
			EndIf
		EndIf
	Next

	Local $iFileSuccess = 0
	For $sPath In $aPaths
		If $sPath = "" Then ContinueLoop
		If FileExists($sPath) Then
			If StringInStr(FileGetAttrib($sPath), "D") Then
				If DirRemove($sPath, 1) Then
					LogWrite(1, "Deleted directory: " & $sPath)
					$iFileSuccess += 1
				Else
					LogWrite(1, "Failed to delete directory: " & $sPath)
				EndIf
			Else
				If FileDelete($sPath) Then
					LogWrite(1, "Deleted file: " & $sPath)
					$iFileSuccess += 1
				Else
					LogWrite(1, "Failed to delete file: " & $sPath)
				EndIf
			EndIf
		Else
			LogWrite(1, "File or folder not found: " & $sPath)
		EndIf
	Next

	LogWrite(1, "Initialising localised background sandbox and credential vault purge...")

	Local $sAcroCefCache = @LocalAppDataDir & "\Adobe\AcroCef\Cache"
	If FileExists($sAcroCefCache) Then
		If DirRemove($sAcroCefCache, 1) Then
			LogWrite(1, "Purged localised Acrobat sandbox cache directory context: " & $sAcroCefCache)
		Else
			LogWrite(1, "Warning: Acrobat web sandbox files locked or currently in use.")
		EndIf
	EndIf

	Local $sOobeCache = @LocalAppDataDir & "\Adobe\OOBE"
	If FileExists($sOobeCache) Then
		If DirRemove($sOobeCache, 1) Then
			LogWrite(1, "Purged local workstation user space workspace markers: " & $sOobeCache)
		EndIf
	EndIf

	RunWait("ipconfig /flushdns", "", @SW_HIDE)
	LogWrite(1, "Local computer network resolution table flushed cleanly.")

	MemoWrite("AGS removal completed. Successfully processed " & $iServiceSuccess & " of " & UBound($aServices) & " services and " & $iFileSuccess & " of " & UBound($aPaths) & " files.")
	LogWrite(1, "AGS removal completed. Services: " & $iServiceSuccess & "/" & UBound($aServices) & ", Files: " & $iFileSuccess & "/" & UBound($aPaths) & @CRLF)
	ToggleLog(1)
	GUICtrlSetState($idBtnRemoveAGS, $GUI_ENABLE)
EndFunc

Func _FindAcrobatDCAGS()
	Local $aCandidateRoots[4]
	$aCandidateRoots[0] = $MyDefPath & "\Acrobat DC\Acrobat"

	Local $sInstallPath = RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Adobe\Adobe Acrobat\DC\InstallPath", "")
	If Not @error And $sInstallPath <> "" Then
		$aCandidateRoots[1] = StringRegExpReplace($sInstallPath, "\\$", "")
	EndIf

	Local $sAcroExe = RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Acrobat.exe", "")
	If Not @error And $sAcroExe <> "" Then
		$aCandidateRoots[2] = StringRegExpReplace($sAcroExe, "\\[^\\]+$", "")
	EndIf

	$aCandidateRoots[3] = EnvGet("ProgramFiles") & "\Adobe\Acrobat DC\Acrobat"

	For $sRoot In $aCandidateRoots
		If $sRoot = "" Then ContinueLoop
		If FileExists($sRoot) Then Return $sRoot & "\GC\AGSService.exe"
	Next

	Return ""
EndFunc

Func InstallAGSDummy()
	If Not _RequireAdmin("install the AGS placeholder") Then Return
	Local $iFileSuccess = 0, $iRegSuccess = 0, $iConsentFileSuccess = 0, $iServiceSuccess = 0
	GUICtrlSetState($idBtnDummyAGS, $GUI_DISABLE)
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	MemoWrite(@CRLF & "Installing AGS Redirection (Dummy Mode)..." & @CRLF & "---" & @CRLF & "Please wait...")

	Local $ProgramFiles = EnvGet("ProgramFiles")
	Local $AGSFolder = EnvGet("ProgramFiles(x86)") & "\Common Files\Adobe\AdobeGCClient"
	Local $AcrobatDCAGS = _FindAcrobatDCAGS()
	Local $aFiles = ["AdobeGCClient.exe", "AGMService.exe", "AGSService.exe"]
	Local $aServices = ["AGMService", "AGSService"]
	Local $NotepadPath = @WindowsDir & "\System32\notepad.exe"
	Local $PublicConsentDir = EnvGet("PUBLIC") & "\Documents\AdobeGCInfo"
	Local $PublicConsentFile = $PublicConsentDir & "\ConsentRecord"

	For $sFile In $aFiles
		If ProcessExists($sFile) Then
			ProcessClose($sFile)
			ProcessWaitClose($sFile, 2000)
			LogWrite(1, "Terminated process: " & $sFile)
		EndIf
	Next

	For $sService In $aServices
		If RunWait("sc config " & $sService & " start= disabled", "", @SW_HIDE) = 0 Then
			LogWrite(1, "Service disabled: " & $sService)
			$iServiceSuccess += 1
		EndIf
	Next

	If Not FileExists($AGSFolder) Then DirCreate($AGSFolder)
	For $sFile In $aFiles
		Local $Dest = $AGSFolder & "\" & $sFile
		Local $sDest_bak = $Dest & ".bak"
		If FileExists($Dest) And Not FileExists($sDest_bak) Then
			If FileCopy($Dest, $sDest_bak, 0) Then
				LogWrite(1, "Backed up: " & $Dest)
			Else
				LogWrite(1, "Backup FAILED - skipping: " & $Dest)
				ContinueLoop
			EndIf
		EndIf
		FileSetAttrib($Dest, "-RASH")
		If FileCopy($NotepadPath, $Dest, 9) Then
			LogWrite(1, "Dummy created at AdobeGCClient path: " & $Dest)
			$iFileSuccess += 1
		EndIf
	Next

	If $AcrobatDCAGS <> "" Then
		If ProcessExists("AGSService.exe") Then
			ProcessClose("AGSService.exe")
			ProcessWaitClose("AGSService.exe", 2000)
		EndIf
		Local $sAcroParent = StringRegExpReplace($AcrobatDCAGS, "\\[^\\]+$", "")
		If Not FileExists($sAcroParent) Then DirCreate($sAcroParent)
		Local $sAcroBak = $AcrobatDCAGS & ".bak"
		If FileExists($AcrobatDCAGS) And Not FileExists($sAcroBak) Then
			If FileCopy($AcrobatDCAGS, $sAcroBak, 0) Then
				LogWrite(1, "Backed up Acrobat DC AGS: " & $AcrobatDCAGS)
			Else
				LogWrite(1, "Backup FAILED for Acrobat DC AGS - skipping: " & $AcrobatDCAGS)
				$AcrobatDCAGS = ""
			EndIf
		EndIf
		FileSetAttrib($AcrobatDCAGS, "-RASH")
		If FileCopy($NotepadPath, $AcrobatDCAGS, 9) Then
			LogWrite(1, "Dummy created at Acrobat DC path: " & $AcrobatDCAGS)
			$iFileSuccess += 1
		Else
			LogWrite(1, "Failed to dummy Acrobat DC AGSService.exe at: " & $AcrobatDCAGS)
		EndIf
	Else
		LogWrite(1, "Acrobat DC not detected on this system - skipping its AGSService.exe.")
	EndIf

	Local $RegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Adobe\Adobe Genuine Service\Consent\Retail"
	Local $sMultiString = "UserType: GreenZone" & @LF & "Consent: Consented | DateAndTime: 1757294112 | DontAskAgain: Yes | ConsentedButtonText: OK | Retries: 0 | Pending: No"
	If RegWrite($RegPath, "ConsentInfo", "REG_MULTI_SZ", $sMultiString) Then
		LogWrite(1, "Registry patched to GreenZone")
		$iRegSuccess = 1
	EndIf

	If Not FileExists($PublicConsentDir) Then DirCreate($PublicConsentDir)
	FileSetAttrib($PublicConsentFile, "-RASH")
	Local $hFile = FileOpen($PublicConsentFile, 2)
	If $hFile <> -1 Then
		FileWriteLine($hFile, "UserType: GreenZone | Source: 1757294112-CCD")
		FileWriteLine($hFile, "Consent: Consented | DateAndTime: 1757294112 | DontAskAgain: Yes | ConsentedButtonText: OK | Retries: 0 | Pending: No")
		FileClose($hFile)
		LogWrite(1, "ConsentRecord file patched")
		$iConsentFileSuccess = 1
	EndIf

	LogWrite(1, "Initialising localised background sandbox and credential vault purge...")

	Local $sAcroCefCache = @LocalAppDataDir & "\Adobe\AcroCef\Cache"
	If FileExists($sAcroCefCache) Then
		If DirRemove($sAcroCefCache, 1) Then
			LogWrite(1, "Purged localised Acrobat sandbox cache directory context: " & $sAcroCefCache)
		Else
			LogWrite(1, "Warning: Acrobat web sandbox files locked or currently in use.")
		EndIf
	EndIf

	Local $sOobeCache = @LocalAppDataDir & "\Adobe\OOBE"
	If FileExists($sOobeCache) Then
		If DirRemove($sOobeCache, 1) Then
			LogWrite(1, "Purged local workstation user space workspace markers: " & $sOobeCache)
		EndIf
	EndIf

	RunWait("ipconfig /flushdns", "", @SW_HIDE)
	LogWrite(1, "Local computer network resolution table flushed cleanly.")

	MemoWrite("AGS Redirection completed. Services Disabled: " & $iServiceSuccess & ", Dummies: " & $iFileSuccess & ", Registry: " & ($iRegSuccess ? "OK" : "Failed") & ", Consent File: " & ($iConsentFileSuccess ? "OK" : "Failed"))
	LogWrite(1, "AGS Dummy Mode completed. Files: " & $iFileSuccess & ", Reg: " & $iRegSuccess & ", File: " & $iConsentFileSuccess & @CRLF)

	ToggleLog(1)
	GUICtrlSetState($idBtnDummyAGS, $GUI_ENABLE)
	GUICtrlSetState($idBtnRestoreAGS, $GUI_ENABLE)
EndFunc

Func RestoreAGSDummy()
	If Not _RequireAdmin("restore the AGS files") Then Return
	GUICtrlSetState($idBtnRestoreAGS, $GUI_DISABLE)
	GUICtrlSetState($idBtnDummyAGS, $GUI_DISABLE)
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	MemoWrite(@CRLF & "Restore AGS - restoring original files from backup..." & @CRLF & "---" & @CRLF & "Please wait...")

	Local $AGSFolder = EnvGet("ProgramFiles(x86)") & "\Common Files\Adobe\AdobeGCClient"
	Local $AcrobatDCAGS = _FindAcrobatDCAGS()
	Local $aAGSFiles = ["AdobeGCClient.exe", "AGMService.exe", "AGSService.exe"]
	Local $aTargets
	For $sF In $aAGSFiles
		_ArrayAdd($aTargets, $AGSFolder & "\" & $sF)
	Next
	If $AcrobatDCAGS <> "" Then _ArrayAdd($aTargets, $AcrobatDCAGS)

	Local $bAnyBak = False
	For $i = 0 To UBound($aTargets) - 1
		If FileExists($aTargets[$i] & ".bak") Then
			$bAnyBak = True
			ExitLoop
		EndIf
	Next
	If Not $bAnyBak Then
		MemoWrite(@CRLF & "Restore AGS: No backup files found." & @CRLF & @CRLF & _
				"No backup files (.bak) found for AGS components." & @CRLF & _
				"To restore original files, use the Creative Cloud App Uninstaller Tool to repair Creative Cloud Desktop.")
		LogWrite(1, "Restore AGS: No .bak files found. Use CC App Uninstaller Tool to repair Creative Cloud Desktop." & @CRLF)
		ToggleLog(1)
		GUICtrlSetState($idBtnRestoreAGS, $GUI_DISABLE)
		GUICtrlSetState($idBtnDummyAGS, $GUI_ENABLE)
		Return
	EndIf

	Local $aProcs = ["AdobeGCClient.exe", "AGMService.exe", "AGSService.exe"]
	For $sProc In $aProcs
		If ProcessExists($sProc) Then
			ProcessClose($sProc)
			ProcessWaitClose($sProc, 2000)
			LogWrite(1, "Terminated process: " & $sProc)
		EndIf
	Next

	Local $iRestored = 0, $iSkipped = 0, $iFailed = 0
	For $i = 0 To UBound($aTargets) - 1
		Local $sTarget = $aTargets[$i]
		Local $sBackup = $sTarget & ".bak"
		If Not FileExists($sBackup) Then
			LogWrite(1, "No backup found - skipping: " & $sTarget)
			$iSkipped += 1
			ContinueLoop
		EndIf
		_VerifyBackupAgainstLedger($sTarget, $sBackup)
		FileSetAttrib($sTarget, "-RASH")
		If FileCopy($sBackup, $sTarget, 9) Then
			FileDelete($sBackup)
			LogWrite(1, "Restored: " & $sTarget)
			$iRestored += 1
		Else
			LogWrite(1, "Restore FAILED: " & $sTarget)
			$iFailed += 1
		EndIf
	Next

	LogWrite(1, "Initialising localised background sandbox and credential vault purge...")
	Local $sAcroCefCache = @LocalAppDataDir & "\Adobe\AcroCef\Cache"
	If FileExists($sAcroCefCache) Then
		If DirRemove($sAcroCefCache, 1) Then
			LogWrite(1, "Purged localised Acrobat sandbox cache directory context: " & $sAcroCefCache)
		Else
			LogWrite(1, "Warning: Acrobat web sandbox files locked or currently in use.")
		EndIf
	EndIf

	Local $sOobeCache = @LocalAppDataDir & "\Adobe\OOBE"
	If FileExists($sOobeCache) Then
		If DirRemove($sOobeCache, 1) Then
			LogWrite(1, "Purged local workstation user space workspace markers: " & $sOobeCache)
		EndIf
	EndIf

	RunWait("ipconfig /flushdns", "", @SW_HIDE)
	LogWrite(1, "Local computer network resolution table flushed cleanly.")

	Local $sSummary = "Restore AGS completed.  Restored: " & $iRestored & _
			"  Skipped (no .bak): " & $iSkipped & "  Failed: " & $iFailed
	MemoWrite($sSummary)
	LogWrite(1, $sSummary & @CRLF)
	ToggleLog(1)
	GUICtrlSetState($idBtnRestoreAGS, $GUI_DISABLE)
	GUICtrlSetState($idBtnDummyAGS, $GUI_ENABLE)
EndFunc

Func CheckThirdPartyFirewall()
	Local $sInner = "Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName FirewallProduct -ErrorAction SilentlyContinue | Where-Object { $_.displayName -and $_.displayName -notlike '*Windows*' } | Select-Object -ExpandProperty displayName"
	Local $iPID = Run('powershell.exe -NoProfile -Command "' & $sInner & '"', "", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	Local $iWaitResult = ProcessWaitClose($iPID, 6000)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Third-party firewall check timed out.")
	EndIf
	Local $sOutput = StringStripWS(StdoutRead($iPID), 3)

	If $sOutput = "" Then
		$g_sThirdPartyFirewall = ""
		MemoWrite("Windows Firewall is the active firewall.")
		Return False
	EndIf

	Local $aLines = StringSplit(StringReplace($sOutput, @CR, ""), @LF)
	Local $mSeen = ObjCreate("Scripting.Dictionary")
	Local $sNames = ""
	For $i = 1 To $aLines[0]
		Local $sN = StringStripWS($aLines[$i], 3)
		If $sN <> "" And Not $mSeen.Exists(StringLower($sN)) Then
			$mSeen.Item(StringLower($sN)) = 1
			$sNames &= ($sNames <> "" ? ", " : "") & $sN
		EndIf
	Next

	$g_sThirdPartyFirewall = ($sNames <> "" ? $sNames : "a third-party firewall")
	MemoWrite("Third-party firewall detected: " & $g_sThirdPartyFirewall)
	Return True
EndFunc

Func FindApps($bForLocalDLL = False, $sBasePathOverride = "")
	Local $sBase = ($sBasePathOverride <> "") ? $sBasePathOverride : $MyDefPath

	Local $tFirewallPaths = IniReadSection($sINIPath, "FirewallTrust")
	If @error Then
		Local $sWhy = _ConfigHealthProblem()
		If $sWhy = "" Then $sWhy = "The [FirewallTrust] section is missing or empty in config.ini."
		MemoWrite("Firewall: " & $sWhy)
		LogWrite(1, "Firewall: " & StringReplace($sWhy, @CRLF, " "))
		Local $empty[0]
		Return $empty
	EndIf

	Local $foundFiles[0]
	For $i = 1 To $tFirewallPaths[0][0]
		Local $relativePath = StringReplace($tFirewallPaths[$i][1], '"', "")
		If StringLeft($relativePath, 1) = "\" Then $relativePath = StringTrimLeft($relativePath, 1)
		Local $basePath = StringRegExpReplace($sBase & "\" & $relativePath, "\\\\+", "\\")
		If StringStripWS($basePath, 3) = "" Then ContinueLoop

		If $bForLocalDLL And (StringInStr($basePath, "AcroCEF.exe", 0) Or StringInStr($basePath, "Acrobat.exe", 0)) Then
			ContinueLoop
		EndIf

		If StringInStr($basePath, "*") Then
			Local $pathParts = StringSplit($basePath, "\", 1)
			Local $searchDir = ""
			For $j = 1 To $pathParts[0] - 1
				If StringInStr($pathParts[$j], "*") Then
					$searchDir = StringTrimRight($searchDir, 1)
					Local $searchPattern = StringReplace($pathParts[$j], "*", "*")
					Local $subPath = StringMid($basePath, StringInStr($basePath, $pathParts[$j]) + StringLen($pathParts[$j]))
					Local $HSEARCH = FileFindFirstFile($searchDir & "\" & $searchPattern)
					If $HSEARCH = -1 Then ContinueLoop
					While 1
						Local $folder = FileFindNextFile($HSEARCH)
						If @error Then ExitLoop
						Local $fullPath = $searchDir & "\" & $folder & $subPath
						$fullPath = StringRegExpReplace($fullPath, "\\\\+", "\\")
						If FileExists($fullPath) And StringStripWS($fullPath, 3) <> "" Then
							_ArrayAdd($foundFiles, $fullPath)
						EndIf
					WEnd
					FileClose($HSEARCH)
					ExitLoop
				Else
					$searchDir &= $pathParts[$j] & "\"
				EndIf
			Next
		Else
			If FileExists($basePath) And StringStripWS($basePath, 3) <> "" Then
				_ArrayAdd($foundFiles, $basePath)
			EndIf
		EndIf
	Next

	If UBound($foundFiles) > 0 Then
		$foundFiles = _ArrayUnique($foundFiles, 0, 0, 0, 0)
		Local $cleanedFiles[0]
		For $file In $foundFiles
			If StringStripWS($file, 3) <> "" And Not StringIsInt($file) Then
				_ArrayAdd($cleanedFiles, $file)
			EndIf
		Next
		$foundFiles = $cleanedFiles
	EndIf

	Return $foundFiles
EndFunc

Func RuleExists($ruleName)
	Local $sCmd = 'powershell.exe -Command "Get-NetFirewallRule -DisplayName ''Adobe-Block - ' & $ruleName & ''' | Measure-Object | Select-Object -ExpandProperty Count"'
	Local $iPID = Run(@ComSpec & " /c " & $sCmd, "", @SW_HIDE, $STDOUT_CHILD)
	Local $iTimeout = 5000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		LogWrite(1, "Warning: Rule check for '" & $ruleName & "' timed out after " & $iTimeout & "ms.")
	EndIf
	Local $sOutput = StdoutRead($iPID)
	Return Number(StringStripWS($sOutput, 3)) > 0
EndFunc

Func ShowFirewallStatus()
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	MemoWrite("Checking Windows Firewall status...")
	LogWrite(1, "Checking Windows Firewall status...")

	MemoWrite("Scanning firewall profiles...")
	Local $sProfileCmd = 'powershell.exe -Command "Get-NetFirewallProfile | Select-Object -Property Name,Enabled | Format-Table -HideTableHeaders"'
	Local $iPID = Run(@ComSpec & " /c " & $sProfileCmd, "", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	Local $sProfileOutput = ""
	Local $iTimeout = 5000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Firewall profile check timed out after " & $iTimeout & "ms.")
	EndIf
	$sProfileOutput = StdoutRead($iPID)

	Local $aProfiles = StringSplit(StringStripWS($sProfileOutput, 3), @CRLF, 1)
	Local $sProfileSummary = ""
	For $i = 1 To $aProfiles[0]
		Local $line = StringStripWS($aProfiles[$i], 3)
		If $line <> "" Then
			Local $aParts = StringRegExp($line, "^(\S+)\s+(\S+)$", 1)
			If @error = 0 Then
				Local $profileName = $aParts[0]
				Local $enabled = $aParts[1]
				$sProfileSummary &= $profileName & ": " & ($enabled = "True" ? "Enabled" : "Disabled") & @CRLF
			EndIf
		EndIf
	Next
	MemoWrite("Firewall Profiles:" & @CRLF & StringTrimRight($sProfileSummary, StringLen(@CRLF)))
	LogWrite(1, "Firewall Profiles - " & StringReplace(StringTrimRight($sProfileSummary, StringLen(@CRLF)), @CRLF, " | "))

	MemoWrite("Checking firewall service...")
	Local $sServiceCmd = 'powershell.exe -Command "Get-Service MpsSvc | Select-Object -Property Status,DisplayName | Format-List"'
	$iPID = Run(@ComSpec & " /c " & $sServiceCmd, "", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	Local $sServiceOutput = ""
	$iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Firewall service check timed out after " & $iTimeout & "ms.")
	EndIf
	$sServiceOutput = StdoutRead($iPID)

	Local $sServiceStatus = "Unknown"
	Local $aServiceLines = StringSplit(StringStripWS($sServiceOutput, 3), @CRLF, 1)
	For $line In $aServiceLines
		If StringInStr($line, "Status") Then
			Local $aStatus = StringSplit($line, ":", 1)
			If $aStatus[0] > 1 Then
				$sServiceStatus = StringStripWS($aStatus[2], 3)
			EndIf
			ExitLoop
		EndIf
	Next
	MemoWrite("Firewall Service (MpsSvc): " & $sServiceStatus)
	LogWrite(1, "Firewall Service (MpsSvc): " & $sServiceStatus)
EndFunc

Func RemoveFirewallRules()
	If Not _RequireAdmin("remove Windows Firewall rules") Then Return
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	MemoWrite("Starting firewall rule removal process...")
	LogWrite(1, "Starting firewall rule removal process.")

	If CheckThirdPartyFirewall() Then
		MemoWrite("Third-party firewall detected. Cannot remove rules.")
		LogWrite(1, "Third-party firewall detected" & ($g_sThirdPartyFirewall <> "" ? " (" & $g_sThirdPartyFirewall & ")" : "") & "." & @CRLF & "This option only supports Windows Firewall.")
		LogWrite(1, "Firewall rule removal process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf

	MemoWrite("Scanning for firewall rules...")
	Local $sCmd = 'powershell.exe -Command "Get-NetFirewallRule -Direction Outbound | Where-Object { $_.DisplayName -like ''Adobe-Block*'' } | Select-Object -Property DisplayName"'
	Local $iPID = Run(@ComSpec & " /c " & $sCmd, "", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	Local $sOutput = ""
	Local $iTimeout = 5000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Rule scan timed out after " & $iTimeout & "ms.")
	EndIf
	$sOutput = StdoutRead($iPID)

	Local $aRules = StringSplit(StringStripWS($sOutput, 3), @CRLF, 1)
	Local $iRuleCount = 0
	For $i = 1 To $aRules[0]
		If StringInStr($aRules[$i], "Adobe-Block") Then $iRuleCount += 1
	Next

	If $iRuleCount = 0 Then
		MemoWrite("No firewall rules found.")
		LogWrite(1, "No firewall rules found to remove.")
		LogWrite(1, "Firewall rule removal process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf

	MemoWrite("Removing " & $iRuleCount & " rule(s)...")
	LogWrite(1, "Removing " & $iRuleCount & " rule(s):")
	For $i = 1 To $aRules[0]
		If StringInStr($aRules[$i], "Adobe-Block") Then
			LogWrite(1, "- " & StringStripWS($aRules[$i], 3))
		EndIf
	Next

	Local $sRemoveCmd = 'powershell.exe -Command "Get-NetFirewallRule -Direction Outbound | Where-Object { $_.DisplayName -like ''Adobe-Block*'' } | Remove-NetFirewallRule"'
	Local $iPIDRemove = Run($sRemoveCmd, "", @SW_HIDE, $STDERR_CHILD)
	$iWaitResult = ProcessWaitClose($iPIDRemove, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPIDRemove)
		MemoWrite("Warning: Rule removal timed out after " & $iTimeout & "ms.")
		LogWrite(1, "Error: Rule removal timed out.")
	ElseIf @error Then
		MemoWrite("Error removing firewall rules.")
		LogWrite(1, "Error removing firewall rules.")
	Else
		MemoWrite("Firewall rules removed successfully.")
		LogWrite(1, "Firewall rules removed successfully.")
	EndIf

	LogWrite(1, "Firewall rule removal process completed." & @CRLF)
	ToggleLog(1)
EndFunc

Func CreateFirewallRules()
	If Not _RequireAdmin("create Windows Firewall rules") Then Return
	MemoWrite("Starting firewall rule creation process...")
	LogWrite(1, "Starting firewall rule creation process.")
	If CheckThirdPartyFirewall() Then
		MemoWrite("Third-party firewall detected - app list opened in Notepad.")
		Local $foundApps = FindApps()
		If UBound($foundApps) = 0 Then
			LogWrite(1, "No applications found to block.")
		Else
			Local $sAppList = ""
			For $app In $foundApps
				$sAppList &= $app & @CRLF
			Next
			Local $sAppFile = _WriteListToNotepad("Firewall_App_Paths.txt", _
					"GenP - Firewall block targets (Adobe apps)" & @CRLF & _
					"==========================================" & @CRLF & _
					"Add an OUTBOUND BLOCK rule for each app below in your third-party" & @CRLF & _
					"firewall (" & $g_sThirdPartyFirewall & "). Save or print this for reference.", _
					$sAppList)
			LogWrite(1, "Third-party firewall (" & $g_sThirdPartyFirewall & ") - " & UBound($foundApps) & " app(s) to block manually. List written to: " & $sAppFile)
		EndIf
		LogWrite(1, "Firewall rule creation process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf
	MemoWrite("Scanning for applications...")
	Local $foundApps = FindApps()
	Local $SelectedApps = ShowAppSelectionGUI($foundApps)
	If $SelectedApps = -1 Then
		Return
	ElseIf Not IsArray($SelectedApps) Then
		MemoWrite("Firewall rule selection cancelled by user.")
		LogWrite(1, "Firewall rule selection cancelled by user." & @CRLF)
		Return
	EndIf
	_InjectNglApps($SelectedApps)
	ShowFirewallStatus()
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	If UBound($SelectedApps) = 0 Then
		MemoWrite("No applications selected by the user.")
		LogWrite(1, "No applications selected.")
		LogWrite(1, "Firewall rule creation process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf
	MemoWrite("User selected " & UBound($SelectedApps) & " file(s).")
	Local $psCmdComposite = ""
	Local $rulesAdded = 0
	Local $addedApps[0]
	For $app In $SelectedApps
		$app = StringStripWS($app, 3)
		If $app = "" Then
			MemoWrite("Skipping empty or invalid selected path.")
			ContinueLoop
		EndIf
		If FileExists($app) Then
			Local $ruleName = $app
			If Not RuleExists($ruleName) Then
				Local $ruleCmd = "New-NetFirewallRule -DisplayName 'Adobe-Block - " & $ruleName & "' -Direction Outbound -Program '" & $app & "' -Action Block;"
				$psCmdComposite &= $ruleCmd
				MemoWrite("Adding firewall rule for: " & $app)
				_ArrayAdd($addedApps, $app)
				$rulesAdded += 1
			Else
				MemoWrite("Rule already exists for: " & $app & " - Skipping.")
			EndIf
		Else
			MemoWrite("File not found: " & $app)
			LogWrite(1, "File not found: " & $app)
		EndIf
	Next
	If $rulesAdded > 0 Then
		LogWrite(1, "Selected " & $rulesAdded & " files(s) for new firewall rule(s):")
		For $app In $addedApps
			LogWrite(1, "- " & $app)
		Next
		Local $iPID = Run('powershell.exe -Command "' & $psCmdComposite & '"', "", @SW_HIDE, $STDERR_CHILD)
		Local $iTimeout = 10000
		Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
		If $iWaitResult = 0 Then
			ProcessClose($iPID)
			MemoWrite("Warning: Rule creation timed out after " & $iTimeout & "ms.")
			LogWrite(1, "Error: Rule creation timed out.")
		ElseIf @error Then
			MemoWrite("Error applying firewall rules.")
			LogWrite(1, "Error applying firewall rules.")
		Else
			MemoWrite("Firewall rules applied successfully.")
			LogWrite(1, "Firewall rules applied successfully.")
		EndIf
	Else
		MemoWrite("No new firewall rules to add.")
		LogWrite(1, "No new firewall rules were added (all selected rules already exist).")
	EndIf
	LogWrite(1, "Firewall rule creation process completed." & @CRLF)
	ToggleLog(1)
EndFunc

Func _WriteListToNotepad($sFileName, $sHeader, $sListText)
	Local $sPath = @TempDir & "\" & $sFileName
	Local $hF = FileOpen($sPath, 2)
	If $hF = -1 Then Return ""
	FileWrite($hF, $sHeader & @CRLF & @CRLF & $sListText)
	FileClose($hF)
	ShellExecute("notepad.exe", '"' & $sPath & '"')
	Return $sPath
EndFunc

Func _EnableNGLFirewallRules($bFocusLogOnDone = True)
	Local Const $sGroup = "GenP NGL Firewall"

	Local $aTargets = _CollectNGLBinaries()
	If UBound($aTargets) = 0 Then
		LogWrite(1, "NGL firewall: no NGL binaries found on disk - nothing to block." & @CRLF)
		If $bFocusLogOnDone Then ToggleLog(1)
		Return 0
	EndIf

	If CheckThirdPartyFirewall() Then
		Local $sFileList = ""
		For $sP In $aTargets
			$sFileList &= $sP & @CRLF
		Next
		Local $sPathsFile = _WriteListToNotepad("NGL_Firewall_Paths.txt", _
				"GenP - NGL Firewall block targets" & @CRLF & _
				"=================================" & @CRLF & _
				"Add an OUTBOUND BLOCK rule for each file below in your third-party" & @CRLF & _
				"firewall (" & $g_sThirdPartyFirewall & "). Save or print this for reference.", _
				$sFileList)
		Local $iGo = MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING, $MB_SYSTEMMODAL), "Third-Party Firewall Detected", _
				"A third-party firewall (" & $g_sThirdPartyFirewall & ") is active," & @CRLF & _
				"GenP cannot add the NGL block rules automatically." & @CRLF & @CRLF & _
				"The list of files to block has opened in Notepad." & @CRLF & _
				"Add an Outbound Block rule for each one in" & @CRLF & _
				"your own firewall." & @CRLF & @CRLF & _
				"Continue patching now?" & @CRLF & @CRLF & _
				"Yes = continue (adding the rules is on you)." & @CRLF & _
				"No = cancel so you can add them, then patch again.")
		If $iGo = $IDNO Then
			LogWrite(1, "Patch cancelled by user at the third-party firewall gate.")
			Return -99
		EndIf
		LogWrite(1, "User continued past the third-party firewall gate.")
		If $bFocusLogOnDone Then ToggleLog(1)
		Return 0
	EndIf

	If Not _WinFirewallServiceReady() Then
		LogWrite(1, "Windows Firewall service is off/unavailable - NGL block rules were skipped.")
		MsgBox(BitOR($MB_OK, $MB_ICONWARNING, $MB_SYSTEMMODAL), "Windows Firewall Unavailable", _
				"The Windows Firewall service is turned off or unavailable," & @CRLF & "so GenP could not add the NGL block rules." & @CRLF & @CRLF & _
				"Your apps are still patched and will work, but NGL is not network-isolated." & @CRLF & _
				"Turn Windows Firewall back on and patch again if you want" & @CRLF & "the isolation. This is on you.")
		If $bFocusLogOnDone Then ToggleLog(1)
		Return 0
	EndIf

	Local $mExisting = _GetExistingNGLRuleProgs($sGroup)
	Local $sComposite = "", $iAdded = 0
	For $sExe In $aTargets
		If $mExisting.Exists(StringLower($sExe)) Then ContinueLoop
		Local $sFile = StringRegExpReplace($sExe, "^.*\\", "")
		$sComposite &= "New-NetFirewallRule -DisplayName 'GenP NGL Block - " & $sFile & "' -Group '" & $sGroup & "' -Direction Outbound -Program '" & $sExe & "' -Action Block -Profile Any -ErrorAction SilentlyContinue | Out-Null; "
		LogWrite(1, "NGL firewall: queuing outbound block for " & $sExe)
		$iAdded += 1
	Next

	If $iAdded = 0 Then
		LogWrite(1, "NGL firewall rules already in place - nothing to add." & @CRLF)
		If $bFocusLogOnDone Then ToggleLog(1)
		Return 0
	EndIf

	Local $iPID = Run('powershell.exe -NoProfile -Command "' & $sComposite & '"', "", @SW_HIDE, $STDERR_CHILD)
	ProcessWaitClose($iPID, 20000)
	LogWrite(1, "NGL firewall: added " & $iAdded & " outbound block rule(s) to group '" & $sGroup & "'." & @CRLF)
	MemoWrite("NGL firewall rules applied (" & $iAdded & " added).")
	If $bFocusLogOnDone Then ToggleLog(1)
	Return $iAdded
EndFunc

Func _InjectNglApps(ByRef $aFiles)
	If $bEnableNGLFirewall = 1 Then Return

	Local $sPFBase = EnvGet("ProgramFiles")
	If $sPFBase = "" Then $sPFBase = @HomeDrive & "\Program Files"
	Local $aStatic[2] = [ _
			$sPFBase & "\" & $g_aNGLRelativePaths[0], _
			$sPFBase & "\" & $g_aNGLRelativePaths[1]]
	For $sPath In $aStatic
		If FileExists($sPath) Then _ArrayAdd($aFiles, $sPath)
	Next
	If FileExists($MyDefPath) And StringInStr(FileGetAttrib($MyDefPath), "D") Then
		Local $sScanCmd = 'powershell.exe -NoProfile -Command "Get-ChildItem -Path \"' & $MyDefPath & '\" -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match \"^adobe_licensing_wf.*\.exe$\" -or $_.Name -match \"^adobe_licensing_helper.*\.exe$\" } | Select-Object -ExpandProperty FullName"'
		Local $iPID = Run(@ComSpec & " /c " & $sScanCmd, "", @SW_HIDE, $STDOUT_CHILD)
		ProcessWaitClose($iPID, 8000)
		Local $aFound = StringSplit(StringStripWS(StdoutRead($iPID), 3), @CRLF, 1)
		For $i = 1 To $aFound[0]
			Local $sF = StringStripWS($aFound[$i], 3)
			If $sF <> "" And FileExists($sF) Then _ArrayAdd($aFiles, $sF)
		Next
	EndIf
	If UBound($aFiles) > 0 Then
		$aFiles = _ArrayUnique($aFiles, 0, 0, 0, 0)
		Local $aClean[0]
		For $f In $aFiles
			If StringStripWS($f, 3) <> "" And Not StringIsInt($f) Then _ArrayAdd($aClean, $f)
		Next
		$aFiles = $aClean
	EndIf
EndFunc

Func ShowAppSelectionGUI($foundFiles)
	If Not FileExists($MyDefPath) Or Not StringInStr(FileGetAttrib($MyDefPath), "D") Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("Error: Invalid Path: " & $MyDefPath)
		LogWrite(1, "Error: Invalid Path: " & $MyDefPath)
		ToggleLog(1)
		Return ""
	EndIf
	If UBound($foundFiles) = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("No file(s) found at: " & $MyDefPath)
		LogWrite(1, "No file(s) found at: " & $MyDefPath)
		ToggleLog(1)
		Return -1
	EndIf

	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 500) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 400) / 2
	Local $hGUI = GUICreate("Select File(s) to Firewall", 500, 400, $iPopupX, $iPopupY)
	Local $hSelectAll = GUICtrlCreateCheckbox("Select All", 10, 10)
	Local $hTreeView = GUICtrlCreateTreeView(10, 40, 480, 300, BitOR($TVS_CHECKBOXES, $TVS_HASBUTTONS, $TVS_HASLINES, $TVS_LINESATROOT))
	Local $hOkButton = GUICtrlCreateButton("OK", 200, 350, 100, 30)
	GUISetState(@SW_SHOW)

	Local $defPathClean = StringStripWS($MyDefPath, 3)
	If StringRight($defPathClean, 1) = "\" Then
		$defPathClean = StringTrimRight($defPathClean, 1)
	EndIf
	Local $defPathParts = StringSplit($defPathClean, "\", 1)
	Local $defPathDepth = $defPathParts[0]

	Local $appNodes = ObjCreate("Scripting.Dictionary")
	For $file In $foundFiles
		Local $fileNoBak = StringRegExpReplace(StringReplace($file, ".bak", ""), "\\\\+", "\\")
		Local $fileParts = StringSplit($fileNoBak, "\", 1)
		Local $appName = "Unknown"
		If $fileParts[0] >= $defPathDepth + 1 Then
			$appName = $fileParts[$defPathDepth + 1]
		Else
			LogWrite(1, "Warning: Short path used in config, using Unknown for: " & $fileNoBak)
		EndIf

		If Not $appNodes.Exists($appName) Then
			Local $hAppNode = GUICtrlCreateTreeViewItem($appName, $hTreeView)
			$appNodes($appName) = $hAppNode
			_GUICtrlTreeView_SetChecked($hTreeView, $hAppNode, False)
		EndIf
		Local $hItem = GUICtrlCreateTreeViewItem($file, $appNodes($appName))
		_GUICtrlTreeView_SetChecked($hTreeView, $hItem, False)
	Next
	LogWrite(1, "Found " & UBound($foundFiles) & " file(s) across " & $appNodes.Count & " application(s).")

	Global $prevStates = ObjCreate("Scripting.Dictionary")
	Global $ghTreeView = $hTreeView
	Local $hItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
	While $hItem <> 0
		Local $itemText = _GUICtrlTreeView_GetText($hTreeView, $hItem)
		If _GUICtrlTreeView_GetChildCount($hTreeView, $hItem) > 0 Then
			$prevStates($itemText) = False
		EndIf
		$hItem = _GUICtrlTreeView_GetNext($hTreeView, $hItem)
	WEnd
	AdlibRegister("CheckParentCheckboxes", 100)

	Local $bPaused = False
	While 1
		Local $nMsg = GUIGetMsg()
		Switch $nMsg
			Case $GUI_EVENT_CLOSE
				AdlibUnRegister("CheckParentCheckboxes")
				GUIDelete($hGUI)
				Return ""
			Case $hSelectAll
				AdlibUnRegister("CheckParentCheckboxes")
				Local $checkedState = (GUICtrlRead($hSelectAll) = $GUI_CHECKED)
				Local $hItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
				While $hItem <> 0
					_GUICtrlTreeView_SetChecked($hTreeView, $hItem, $checkedState)
					Local $itemText = _GUICtrlTreeView_GetText($hTreeView, $hItem)
					If _GUICtrlTreeView_GetChildCount($hTreeView, $hItem) > 0 Then
						$prevStates($itemText) = $checkedState
					EndIf
					$hItem = _GUICtrlTreeView_GetNext($hTreeView, $hItem)
				WEnd
				AdlibRegister("CheckParentCheckboxes", 100)
			Case $hOkButton
				AdlibUnRegister("CheckParentCheckboxes")
				Local $SelectedApps[0]
				Local $hItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
				MemoWrite("Scanning for selected items...")
				While $hItem <> 0
					If _GUICtrlTreeView_GetChecked($hTreeView, $hItem) Then
						Local $itemText = _GUICtrlTreeView_GetText($hTreeView, $hItem)
						Local $childCount = _GUICtrlTreeView_GetChildCount($hTreeView, $hItem)
						If $childCount = -1 And StringStripWS($itemText, 3) <> "" Then
							_ArrayAdd($SelectedApps, $itemText)
						EndIf
					EndIf
					$hItem = _GUICtrlTreeView_GetNext($hTreeView, $hItem)
				WEnd
				_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
				MemoWrite("Selected " & UBound($SelectedApps) & " file(s) for firewall rules.")
				GUIDelete($hGUI)
				Return $SelectedApps
			Case $GUI_EVENT_PRIMARYDOWN
				Local $aCursor = GUIGetCursorInfo($hGUI)
				If IsArray($aCursor) And $aCursor[4] = $hTreeView Then
					If Not $bPaused Then
						AdlibUnRegister("CheckParentCheckboxes")
						$bPaused = True
					EndIf
				EndIf
			Case Else
				If $bPaused Then
					AdlibRegister("CheckParentCheckboxes", 100)
					$bPaused = False
				EndIf
		EndSwitch
	WEnd
EndFunc

Func CheckParentCheckboxes()
	Local $hItem = _GUICtrlTreeView_GetFirstItem($ghTreeView)
	While $hItem <> 0
		Local $itemText = _GUICtrlTreeView_GetText($ghTreeView, $hItem)
		Local $childCount = _GUICtrlTreeView_GetChildCount($ghTreeView, $hItem)
		If $childCount > 0 Then
			If IsObj($g_mBlockedParents) And $g_mBlockedParents.Exists($itemText) Then
				_GUICtrlTreeView_SetChecked($ghTreeView, $hItem, False)
				Local $hBC = _GUICtrlTreeView_GetFirstChild($ghTreeView, $hItem)
				While $hBC <> 0
					_GUICtrlTreeView_SetChecked($ghTreeView, $hBC, False)
					$hBC = _GUICtrlTreeView_GetNextChild($ghTreeView, $hBC)
				WEnd
				$prevStates($itemText) = False
				$hItem = _GUICtrlTreeView_GetNext($ghTreeView, $hItem)
				ContinueLoop
			EndIf

			Local $currentState = _GUICtrlTreeView_GetChecked($ghTreeView, $hItem)
			Local $prevState = $prevStates($itemText)
			If $currentState <> $prevState Then
				$prevStates($itemText) = $currentState
				Local $hChild = _GUICtrlTreeView_GetFirstChild($ghTreeView, $hItem)
				While $hChild <> 0
					_GUICtrlTreeView_SetChecked($ghTreeView, $hChild, $currentState)
					$hChild = _GUICtrlTreeView_GetNextChild($ghTreeView, $hChild)
				WEnd
			EndIf
		EndIf
		$hItem = _GUICtrlTreeView_GetNext($ghTreeView, $hItem)
	WEnd
EndFunc

Func ShowToggleRulesGUI()
	MemoWrite("Opening firewall rule toggle options...")

	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 300) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 150) / 2
	Local $hToggleGUI = GUICreate("Toggle Rules", 300, 150, $iPopupX, $iPopupY)
	Local $hEnableButton = GUICtrlCreateButton("Enable All", 50, 50, 100, 30)
	Local $hDisableButton = GUICtrlCreateButton("Disable All", 150, 50, 100, 30)
	Local $hCancelButton = GUICtrlCreateButton("Cancel", 100, 100, 100, 30)
	GUISetState(@SW_SHOW)

	While 1
		Switch GUIGetMsg()
			Case $GUI_EVENT_CLOSE, $hCancelButton
				MemoWrite("Toggle rules operation cancelled.")
				GUIDelete($hToggleGUI)
				Return
			Case $hEnableButton
				_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
				GUIDelete($hToggleGUI)
				EnableAllFWRules()
				Return
			Case $hDisableButton
				_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
				GUIDelete($hToggleGUI)
				DisableAllFWRules()
				Return
		EndSwitch
	WEnd
EndFunc

Func EnableAllFWRules()
	MemoWrite("Enabling all GenP firewall rules...")
	LogWrite(1, "Starting process to enable all GenP firewall rules.")

	If CheckThirdPartyFirewall() Then
		MemoWrite("Third-party firewall detected. Cannot modify rules.")
		LogWrite(1, "Third-party firewall detected" & ($g_sThirdPartyFirewall <> "" ? " (" & $g_sThirdPartyFirewall & ")" : "") & "." & @CRLF & "This option only supports Windows Firewall.")
		LogWrite(1, "Enable rules process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf

	Local $sCmd = 'powershell.exe -Command "Get-NetFirewallRule -Direction Outbound | Where-Object { $_.DisplayName -like ''Adobe-Block*'' } | Select-Object -Property DisplayName"'
	Local $iPID = Run(@ComSpec & " /c " & $sCmd, "", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	Local $sOutput = ""
	Local $iTimeout = 5000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Rule scan timed out after " & $iTimeout & "ms.")
	EndIf
	$sOutput = StdoutRead($iPID)

	Local $aRules = StringSplit(StringStripWS($sOutput, 3), @CRLF, 1)
	Local $iRuleCount = 0
	For $i = 1 To $aRules[0]
		If StringInStr($aRules[$i], "Adobe-Block") Then $iRuleCount += 1
	Next

	If $iRuleCount = 0 Then
		MemoWrite("No GenP firewall rules found to enable.")
		LogWrite(1, "No GenP firewall rules found.")
		LogWrite(1, "Enable rules process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf

	MemoWrite("Enabling " & $iRuleCount & " Adobe-Block rule(s)...")
	LogWrite(1, "Enabling " & $iRuleCount & " rule(s):")
	For $i = 1 To $aRules[0]
		If StringInStr($aRules[$i], "Adobe-Block") Then
			LogWrite(1, "- " & StringStripWS($aRules[$i], 3))
		EndIf
	Next

	Local $sEnableCmd = 'powershell.exe -Command "Get-NetFirewallRule -Direction Outbound | Where-Object { $_.DisplayName -like ''Adobe-Block*'' } | Enable-NetFirewallRule"'
	Local $iPIDEnable = Run($sEnableCmd, "", @SW_HIDE, $STDERR_CHILD)
	$iWaitResult = ProcessWaitClose($iPIDEnable, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPIDEnable)
		MemoWrite("Warning: Rule enabling timed out after " & $iTimeout & "ms.")
		LogWrite(1, "Error: Rule enabling timed out.")
	ElseIf @error Then
		MemoWrite("Error enabling firewall rules.")
		LogWrite(1, "Error enabling firewall rules.")
	Else
		MemoWrite("All GenP firewall rules enabled successfully.")
		LogWrite(1, "All GenP firewall rules enabled successfully.")
	EndIf

	LogWrite(1, "Enable rules process completed." & @CRLF)
	ToggleLog(1)
EndFunc

Func DisableAllFWRules()
	MemoWrite("Disabling all GenP firewall rules...")
	LogWrite(1, "Starting process to disable all GenP firewall rules.")

	If CheckThirdPartyFirewall() Then
		MemoWrite("Third-party firewall detected. Cannot modify rules.")
		LogWrite(1, "Third-party firewall detected" & ($g_sThirdPartyFirewall <> "" ? " (" & $g_sThirdPartyFirewall & ")" : "") & "." & @CRLF & "This option only supports Windows Firewall.")
		LogWrite(1, "Disable rules process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf

	Local $sCmd = 'powershell.exe -Command "Get-NetFirewallRule -Direction Outbound | Where-Object { $_.DisplayName -like ''Adobe-Block*'' } | Select-Object -Property DisplayName"'
	Local $iPID = Run(@ComSpec & " /c " & $sCmd, "", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	Local $sOutput = ""
	Local $iTimeout = 5000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Rule scan timed out after " & $iTimeout & "ms.")
	EndIf
	$sOutput = StdoutRead($iPID)

	Local $aRules = StringSplit(StringStripWS($sOutput, 3), @CRLF, 1)
	Local $iRuleCount = 0
	For $i = 1 To $aRules[0]
		If StringInStr($aRules[$i], "Adobe-Block") Then $iRuleCount += 1
	Next

	If $iRuleCount = 0 Then
		MemoWrite("No GenP firewall rules found to disable.")
		LogWrite(1, "No GenP firewall rules found.")
		LogWrite(1, "Disable rules process completed." & @CRLF)
		ToggleLog(1)
		Return
	EndIf

	MemoWrite("Disabling " & $iRuleCount & " Adobe-Block rule(s)...")
	LogWrite(1, "Disabling " & $iRuleCount & " rule(s):")
	For $i = 1 To $aRules[0]
		If StringInStr($aRules[$i], "Adobe-Block") Then
			LogWrite(1, "- " & StringStripWS($aRules[$i], 3))
		EndIf
	Next

	Local $sDisableCmd = 'powershell.exe -Command "Get-NetFirewallRule -Direction Outbound | Where-Object { $_.DisplayName -like ''Adobe-Block*'' } | Disable-NetFirewallRule"'
	Local $iPIDDisable = Run($sDisableCmd, "", @SW_HIDE, $STDERR_CHILD)
	$iWaitResult = ProcessWaitClose($iPIDDisable, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPIDDisable)
		MemoWrite("Warning: Rule disabling timed out after " & $iTimeout & "ms.")
		LogWrite(1, "Error: Rule disabling timed out.")
	ElseIf @error Then
		MemoWrite("Error disabling firewall rules.")
		LogWrite(1, "Error disabling firewall rules.")
	Else
		MemoWrite("All GenP firewall rules disabled successfully.")
		LogWrite(1, "All GenP firewall rules disabled successfully.")
	EndIf

	LogWrite(1, "Disable rules process completed." & @CRLF)
	ToggleLog(1)
EndFunc

