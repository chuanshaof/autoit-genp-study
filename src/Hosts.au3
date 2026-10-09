; =====================================================================
; Hosts.au3  -  Application module.
; Functions (20):
;   - RemoveHostsEntries
;   - ScanDNSCache
;   - _RunGetOutput
;   - _IsHostsAutoUpdateInstalled
;   - _GetHostsAutoUpdateMethod
;   - _SetupHostsAutoUpdate
;   - _RemoveHostsAutoUpdate
;   - _RunHostsAutoUpdateNow
;   - _IsGudeCleanupInstalled
;   - _SetupGudeCleanup
;   - _RemoveGudeCleanup
;   - _GudeCleanupDriveSelectGUI
;   - _ShowGudeSetupPrompt
;   - _ShowGudeRemovePrompt
;   - _ShowHostsAutoUpdateDialog
;   - _RefreshAutoUpdateDialogStatus
;   - _SilentHostsInjector
;   - UpdateHostsFile
;   - EditHosts
;   - RestoreHosts
; =====================================================================

Func RemoveHostsEntries()
	If Not _RequireAdmin("modify the Windows hosts file") Then Return
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	Local $sHostsPath = @WindowsDir & "\System32\drivers\etc\hosts"
	Local $sTempHosts = @TempDir & "\temp_hosts_remove.tmp"
	Local $sMarkerStart = "# START - Adobe Blocklist"
	Local $sMarkerEnd = "# END - Adobe Blocklist"

	FileSetAttrib($sHostsPath, "-R")

	Local $sHostsContent = FileRead($sHostsPath)
	If @error Then
		MemoWrite("Error reading hosts file." & @CRLF)
		FileSetAttrib($sHostsPath, "+R")
		Return False
	EndIf

	If Not StringInStr($sHostsContent, $sMarkerStart) Or Not StringInStr($sHostsContent, $sMarkerEnd) Then
		LogWrite(1, "No entries to remove." & @CRLF)
		FileSetAttrib($sHostsPath, "+R")
		ToggleLog(1)
		Return True
	EndIf

	$sHostsContent = StringRegExpReplace($sHostsContent, "(?s)" & $sMarkerStart & ".*?" & $sMarkerEnd, "")

	Local $hTempFile = FileOpen($sTempHosts, 2)
	If $hTempFile = -1 Then
		MemoWrite("Error creating temp hosts file for removal." & @CRLF)
		FileSetAttrib($sHostsPath, "+R")
		Return False
	EndIf
	FileWrite($hTempFile, $sHostsContent)
	FileClose($hTempFile)

	If Not FileCopy($sTempHosts, $sHostsPath, 1) Then
		MemoWrite("Error writing updated hosts file." & @CRLF)
		MemoWrite("Attempting to copy from: " & $sTempHosts & " to: " & $sHostsPath & @CRLF)
		FileDelete($sTempHosts)
		FileSetAttrib($sHostsPath, "+R")
		Return False
	EndIf
	FileDelete($sTempHosts)

	FileSetAttrib($sHostsPath, "+R")
	LogWrite(1, "Hosts file cleaned of existing entries." & @CRLF)
	ToggleLog(1)
	Return True
EndFunc

Func ScanDNSCache(ByRef $sHostsContent)
	Local $sMarkerStart = "# START - Adobe Blocklist"
	Local $sMarkerEnd = "# END - Adobe Blocklist"

	Local $sBlockSection = StringRegExp($sHostsContent, "(?s)" & $sMarkerStart & "(.*?)" & $sMarkerEnd, 1)
	If @error Or UBound($sBlockSection) = 0 Then
		MemoWrite("Error parsing blocklist from hosts content." & @CRLF)
		Return 0
	EndIf
	Local $aCurrentDomains = StringSplit(StringStripWS($sBlockSection[0], 8), @CRLF, 2)
	Local $aHostsDomains[0]
	For $i = 0 To UBound($aCurrentDomains) - 1
		Local $sLine = StringStripWS($aCurrentDomains[$i], 3)
		If StringRegExp($sLine, "^\d+\.\d+\.\d+\.\d+\s+(.+)$") Then
			_ArrayAdd($aHostsDomains, StringRegExpReplace($sLine, "^\d+\.\d+\.\d+\.\d+\s+(.+)$", "$1"))
		EndIf
	Next
	_ArraySort($aHostsDomains)
	_ArrayUnique($aHostsDomains)

	Local $sTempDNS = @TempDir & "\dns_cache.txt"
	Local $iPID = Run(@ComSpec & " /c ipconfig /displaydns > " & $sTempDNS, "", @SW_HIDE)
	Local $iTimeout = 5000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: ipconfig /displaydns timed out after " & $iTimeout & "ms." & @CRLF)
	EndIf

	Local $sDNSCache = FileRead($sTempDNS)
	If @error Then
		MemoWrite("Error reading DNS cache." & @CRLF)
		FileDelete($sTempDNS)
		Return 0
	EndIf
	FileDelete($sTempDNS)

	Local $aDNSDomains = StringRegExp($sDNSCache, "Record Name[^\n]*?\n\s*:\s*([^\n]*(?:adobestats\.io|ic\.adobe\.io)[^\n]*)", 3)
	If UBound($aDNSDomains) = 0 Then
		Return 0
	EndIf
	_ArraySort($aDNSDomains)
	_ArrayUnique($aDNSDomains)

	Local $aNewDomains[0]
	For $i = 0 To UBound($aDNSDomains) - 1
		Local $sDomain = StringStripWS($aDNSDomains[$i], 3)
		If _ArraySearch($aHostsDomains, $sDomain) = -1 Then
			_ArrayAdd($aNewDomains, $sDomain)
		EndIf
	Next

	If UBound($aNewDomains) = 0 Then
		Return 0
	EndIf

	Local $sPrompt = "Found " & UBound($aNewDomains) & " new domain(s) in DNS cache:" & @CRLF & _
			_ArrayToString($aNewDomains, @CRLF) & @CRLF & "Add to hosts file?"
	Local $iResponse = MsgBox($MB_YESNO + $MB_ICONQUESTION, "New Domains Detected", $sPrompt)
	If $iResponse = $IDNO Then
		MemoWrite("User declined to add new DNS domains." & @CRLF)
		Return 0
	EndIf

	Return $aNewDomains
EndFunc

Func _RunGetOutput($sCmd)
	Local $iPID = Run(@ComSpec & ' /c ' & $sCmd, "", @SW_HIDE, _
			BitOR($STDOUT_CHILD, $STDERR_CHILD))
	If @error Or $iPID = 0 Then Return SetError(1, 0, "")
	Local $sOutput = ""
	While ProcessExists($iPID)
		$sOutput &= StdoutRead($iPID)
		$sOutput &= StderrRead($iPID)
		Sleep(50)
	WEnd
	$sOutput &= StdoutRead($iPID)
	$sOutput &= StderrRead($iPID)
	Return $sOutput
EndFunc

Func _IsHostsAutoUpdateInstalled()
	Local $iExit = RunWait(@ComSpec & ' /c schtasks /query /tn "' & $g_sHAU_TASK_NAME & '" >nul 2>&1', "", @SW_HIDE)
	Return ($iExit = 0)
EndFunc

Func _GetHostsAutoUpdateMethod()
	If Not _IsHostsAutoUpdateInstalled() Then Return $g_iHAU_METHOD_NONE
	Local $sXml = _RunGetOutput('schtasks /query /tn "' & $g_sHAU_TASK_NAME & '" /xml')
	If StringInStr($sXml, "UpdateHostsFile.ps1") Then Return $g_iHAU_METHOD_ADVANCED
	If StringInStr($sXml, "-updatehosts") Then Return $g_iHAU_METHOD_BASIC
	Return $g_iHAU_METHOD_NONE
EndFunc

Func _SetupHostsAutoUpdate($iMethod, $sDailyTime = "00:00")
	If Not IsAdmin() Then Return SetError(1, 0, False)

	Local $sGenPExePath = @ScriptFullPath

	If $iMethod = $g_iHAU_METHOD_BASIC Then
		If StringInStr($sGenPExePath, "\Users\") Or _
				StringInStr($sGenPExePath, "\Desktop\") Or _
				StringInStr($sGenPExePath, "\Documents\") Or _
				StringInStr($sGenPExePath, "\Downloads\") Then
			Local $iAns = MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING), _
					"Hosts Auto-Update Setup", _
					"GenP appears to be in a user-specific folder:" & @CRLF & _
					$sGenPExePath & @CRLF & @CRLF & _
					"The scheduled task runs as SYSTEM, which usually cannot reach" & @CRLF & _
					"user folders. The task will be created but will likely fail when" & @CRLF & _
					"it tries to run." & @CRLF & @CRLF & _
					"Recommended: move GenP to a root folder like C:\GenP\ first." & @CRLF & @CRLF & _
					"Proceed anyway?")
			If $iAns <> $IDYES Then Return SetError(2, 0, False)
		EndIf
	EndIf


	If $iMethod = $g_iHAU_METHOD_ADVANCED Then
		Local $bDeployed = FileInstall("resources\UpdateHostsFile.ps1", $g_sHAU_PS1_TARGET, 1)
		If Not $bDeployed Or Not FileExists($g_sHAU_PS1_TARGET) Then
			Return SetError(4, 0, False)
		EndIf

		Local $sPs1Content = FileRead($g_sHAU_PS1_TARGET)
		$sPs1Content = StringReplace($sPs1Content, "__GENP_PATH__", $sGenPExePath)
		Local $hPs1 = FileOpen($g_sHAU_PS1_TARGET, 2)
		If $hPs1 = -1 Then Return SetError(4, 0, False)
		FileWrite($hPs1, $sPs1Content)
		FileClose($hPs1)
	EndIf

	Local $sCmd
	If $iMethod = $g_iHAU_METHOD_BASIC Then
		Local $sTaskRun = '\"' & $sGenPExePath & '\" -updatehosts'
		$sCmd = 'schtasks /create /F /TN "' & $g_sHAU_TASK_NAME & '" ' & _
				'/TR "' & $sTaskRun & '" ' & _
				'/SC DAILY /ST ' & $sDailyTime & ' ' & _
				'/RU SYSTEM /RL HIGHEST'
	Else
		Local $sTaskRun = 'powershell.exe -ExecutionPolicy Bypass -File \"' & _
				$g_sHAU_PS1_TARGET & '\"'
		$sCmd = 'schtasks /create /F /TN "' & $g_sHAU_TASK_NAME & '" ' & _
				'/TR "' & $sTaskRun & '" ' & _
				'/SC HOURLY /MO 3 ' & _
				'/RU SYSTEM /RL HIGHEST'
	EndIf

	RunWait(@ComSpec & ' /c schtasks /delete /F /TN "' & $g_sHAU_TASK_NAME & '" >nul 2>&1', "", @SW_HIDE)

	Local $iExit = RunWait(@ComSpec & ' /c ' & $sCmd, "", @SW_HIDE)
	If $iExit <> 0 Then Return SetError(3, $iExit, False)

	If Not _IsHostsAutoUpdateInstalled() Then Return SetError(5, 0, False)

	RunWait(@ComSpec & ' /c schtasks /run /TN "' & $g_sHAU_TASK_NAME & '"', "", @SW_HIDE)

	Return True
EndFunc

Func _RemoveHostsAutoUpdate($bAlsoRemoveAdvancedFiles = True)
	If Not _IsHostsAutoUpdateInstalled() Then
		If $bAlsoRemoveAdvancedFiles Then
			If FileExists($g_sHAU_PS1_TARGET) Then FileDelete($g_sHAU_PS1_TARGET)
			If FileExists($g_sHAU_LOG_TARGET) Then FileDelete($g_sHAU_LOG_TARGET)
		EndIf
		Return True
	EndIf

	If Not IsAdmin() Then Return SetError(1, 0, False)

	Local $iExit = RunWait(@ComSpec & ' /c schtasks /delete /F /TN "' & $g_sHAU_TASK_NAME & '"', "", @SW_HIDE)
	If $iExit <> 0 Then Return SetError(2, $iExit, False)

	If _IsHostsAutoUpdateInstalled() Then Return SetError(3, 0, False)

	If $bAlsoRemoveAdvancedFiles Then
		If FileExists($g_sHAU_PS1_TARGET) Then FileDelete($g_sHAU_PS1_TARGET)
		If FileExists($g_sHAU_LOG_TARGET) Then FileDelete($g_sHAU_LOG_TARGET)
	EndIf
	Return True
EndFunc

Func _RunHostsAutoUpdateNow()
	If Not _IsHostsAutoUpdateInstalled() Then Return False
	Local $iExit = RunWait(@ComSpec & ' /c schtasks /run /TN "' & $g_sHAU_TASK_NAME & '"', "", @SW_HIDE)
	Return ($iExit = 0)
EndFunc

Func _IsGudeCleanupInstalled()
	Local $iExit = RunWait(@ComSpec & ' /c schtasks /query /TN "' & $g_sGUDE_TASK_NAME & '" >nul 2>&1', "", @SW_HIDE)
	Return ($iExit = 0)
EndFunc

Func _SetupGudeCleanup($sDrives)
	If Not IsAdmin() Then Return SetError(1, 0, False)
	If Not FileExists($g_sGUDE_DIR) Then DirCreate($g_sGUDE_DIR)

	RunWait(@ComSpec & ' /c schtasks /delete /F /TN "' & $g_sGUDE_TASK_NAME & '" >nul 2>&1', "", @SW_HIDE)

	Local $bDeployed = FileInstall("resources\RemoveGudeLogs.ps1", $g_sGUDE_PS1_TARGET, 1)
	If Not $bDeployed Or Not FileExists($g_sGUDE_PS1_TARGET) Then Return SetError(2, 0, False)
	Local $sContent = FileRead($g_sGUDE_PS1_TARGET)
	$sContent = StringReplace($sContent, "__DRIVES__", $sDrives)
	Local $hFile = FileOpen($g_sGUDE_PS1_TARGET, 2)
	If $hFile = -1 Then Return SetError(3, 0, False)
	FileWrite($hFile, $sContent)
	FileClose($hFile)
	IniWrite($sINIPath, "Options", "GudeCleanupDrives", $sDrives)

	Local $sRun = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' & $g_sGUDE_PS1_TARGET & '"'

	Local $sCmd = 'schtasks /create /F /TN "' & $g_sGUDE_TASK_NAME & '" ' & _
			'/TR "' & $sRun & '" ' & _
			'/SC HOURLY /MO 3 ' & _
			'/RU SYSTEM /RL HIGHEST'
	Local $iExit = RunWait(@ComSpec & ' /c ' & $sCmd, "", @SW_HIDE)
	If $iExit <> 0 Then Return SetError(4, $iExit, False)

	Local $sPatch = '$t = Get-ScheduledTask -TaskName ''' & $g_sGUDE_TASK_NAME & '''; ' & _
			'$t.Settings.StartWhenAvailable = $true; ' & _
			'Set-ScheduledTask -TaskName ''' & $g_sGUDE_TASK_NAME & ''' -Settings $t.Settings'
	RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' & $sPatch & '"', "", @SW_HIDE)

	RunWait(@ComSpec & ' /c schtasks /run /TN "' & $g_sGUDE_TASK_NAME & '"', "", @SW_HIDE)

	Return True
EndFunc

Func _RemoveGudeCleanup()
	RunWait(@ComSpec & ' /c schtasks /delete /F /TN "' & $g_sGUDE_TASK_NAME & '" >nul 2>&1', "", @SW_HIDE)
	If FileExists($g_sGUDE_DIR) Then DirRemove($g_sGUDE_DIR, 1)
	IniDelete($sINIPath, "Options", "GudeCleanupDrives")
	Return True
EndFunc

Func _GudeCleanupDriveSelectGUI()
	Local $aAllDrives = DriveGetDrive("Fixed")
	If @error Or Not IsArray($aAllDrives) Or $aAllDrives[0] = 0 Then Return ""

	Local $sPathDrive = StringUpper(StringLeft($MyDefPath, 1))
	Local $iCount = $aAllDrives[0]
	Local $iW = 320, $iH = 74 + ($iCount * 28) + 50
	Local $aPos = WinGetPos($MyhGUI)
	Local $hGUI = GUICreate("Gude Log Cleanup", $iW, $iH, _
			$aPos[0] + ($aPos[2] - $iW) / 2, $aPos[1] + ($aPos[3] - $iH) / 2, _
			BitOR($WS_POPUP, $WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
	GUISetFont(9, 400, 0, "Segoe UI", $hGUI)
	GUISetIcon(@ScriptDir & "\Skull.ico", 0, $hGUI)

	GUICtrlCreateLabel("Select drives to scan for gude log files:", 12, 12, $iW - 24, 18)

	Local $aCheckboxes[$iCount]
	Local $iY = 36
	For $i = 1 To $iCount
		Local $sDL = StringUpper(StringLeft($aAllDrives[$i], 1))
		Local $sLbl = $sDL & ":"
		Local $sDriveLabel = DriveGetLabel($sDL & ":\")
		If $sDriveLabel <> "" Then $sLbl &= "  (" & $sDriveLabel & ")"
		$aCheckboxes[$i - 1] = GUICtrlCreateCheckbox($sLbl, 20, $iY, $iW - 40, 24)
		If $sDL = "C" Or $sDL = $sPathDrive Then
			GUICtrlSetState($aCheckboxes[$i - 1], $GUI_CHECKED)
		EndIf
		$iY += 28
	Next

	Local $idBtnOK     = GUICtrlCreateButton("Set Up", 40,  $iY + 8, 90, 28)
	Local $idBtnCancel = GUICtrlCreateButton("Skip",   190, $iY + 8, 90, 28)

	GUISetState(@SW_DISABLE, $MyhGUI)
	GUISetState(@SW_SHOW, $hGUI)

	Local $sResult = ""
	While True
		Local $nMsg = GUIGetMsg()
		Switch $nMsg
			Case $GUI_EVENT_CLOSE, $idBtnCancel
				ExitLoop
			Case $idBtnOK
				For $i = 0 To $iCount - 1
					If GUICtrlRead($aCheckboxes[$i]) = $GUI_CHECKED Then
						Local $sDrive = StringUpper(StringLeft($aAllDrives[$i + 1], 1))
						$sResult &= ($sResult = "" ? "" : ",") & $sDrive
					EndIf
				Next
				ExitLoop
		EndSwitch
	WEnd

	GUISetState(@SW_ENABLE, $MyhGUI)
	GUIDelete($hGUI)
	Return $sResult
EndFunc

Func _ShowGudeSetupPrompt()
	Local $iAns = MsgBox(BitOR($MB_YESNOCANCEL, $MB_ICONQUESTION, $MB_SYSTEMMODAL), _
			"Gude Log Cleanup", _
			"For some users the Good patch can cause Adobe to generate" & @CRLF & _
			"gude-YYYY-MM-DD.log files in Adobe folders each time the" & @CRLF & _
			"patched app is opened. These are harmless side effects" & @CRLF & _
			"and can be removed automatically." & @CRLF & @CRLF & _
			"GenP can add a scheduled task to remove them every 3 hours" & @CRLF & _
			"and at each Windows login." & @CRLF & @CRLF & _
			"Yes - select drives and set up the task" & @CRLF & _
			"No - skip (won't be asked again)" & @CRLF & _
			"Cancel - remind me next time")
	Select
		Case $iAns = $IDYES
			Local $sDrives = _GudeCleanupDriveSelectGUI()
			If $sDrives <> "" Then
				If _SetupGudeCleanup($sDrives) Then
					MemoWrite(@CRLF & "Gude Log Cleanup scheduled task set up for drive(s): " & $sDrives & ".")
					MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Gude Log Cleanup", _
							"Scheduled task added successfully." & @CRLF & @CRLF & _
							"Drive(s) selected: " & $sDrives & @CRLF & _
							"The task will run every 3 hours and at each Windows login.")
				Else
					MemoWrite(@CRLF & "Error: could not set up Gude Log Cleanup task (code " & @error & ").")
					MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Gude Log Cleanup", _
							"Failed to add the scheduled task (error code " & @error & ")." & @CRLF & @CRLF & _
							"Check that GenP is running as Administrator.")
				EndIf
			EndIf
		Case $iAns = $IDNO
			IniWrite($sINIPath, "Options", "GudeDismissed", "1")
	EndSelect
EndFunc

Func _ShowGudeRemovePrompt()
	Local $iAns = MsgBox(BitOR($MB_YESNOCANCEL, $MB_ICONQUESTION, $MB_SYSTEMMODAL), _
			"Gude Log Cleanup", _
			"The Gude Log Cleanup scheduled task is still active." & @CRLF & @CRLF & _
			"Since you have disabled the Good patch, would you" & @CRLF & _
			"like to remove the Gude Log Cleanup task as well?" & @CRLF & @CRLF & _
			"Yes - remove the scheduled task" & @CRLF & _
			"No - keep it running (won't be asked again)" & @CRLF & _
			"Cancel - remind me next time")
	Select
		Case $iAns = $IDYES
			_RemoveGudeCleanup()
			MemoWrite(@CRLF & "Gude Log Cleanup scheduled task removed.")
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Gude Log Cleanup", _
					"Scheduled task removed successfully.")
		Case $iAns = $IDNO
			IniWrite($sINIPath, "Options", "GudeDismissedRemove", "1")
	EndSelect
EndFunc

Func _ShowHostsAutoUpdateDialog()
	Local $iW = 520
	Local $iH = 400
	Local $hParent = WinGetHandle("[ACTIVE]")
	Local $hDlg = GUICreate("Hosts Schedule Updates", $iW, $iH, -1, -1, _
			BitOR($WS_CAPTION, $WS_POPUPWINDOW, $WS_SYSMENU), -1, $hParent)
	GUISetIcon(@ScriptDir & "\Skull.ico", 0, $hDlg)
	GUISetFont(9, 400, 0, "Segoe UI", $hDlg)

	GUICtrlCreateLabel("Status:", 15, 15, 50, 18)
	Local $idLblStatus = GUICtrlCreateLabel("(checking...)", 70, 15, 430, 18)
	GUICtrlSetFont($idLblStatus, 9, 700)

	GUICtrlCreateGroup("Method", 15, 45, 490, 175)
	Local $idRadioBasic = GUICtrlCreateRadio("Basic - daily refresh, simple", 30, 70, 460, 22)
	GUICtrlCreateLabel( _
			"Runs GenP.exe -updatehosts once a day. No backup, no recovery." & @CRLF & _
			"Same effect as clicking the Update Hosts button at the scheduled time.", _
			50, 92, 450, 32)
	Local $idRadioAdvanced = GUICtrlCreateRadio("Advanced - 3-hourly with backup, recovery, custom-entry merge", 30, 130, 460, 22)
	GUICtrlCreateLabel( _
			"Runs every 3 hours via PowerShell script. Backs up hosts before each" & @CRLF & _
			"update, verifies the new list, reverts on failure, logs everything." & @CRLF & _
			"Merges entries from hosts.plain (if present) so custom entries survive.", _
			50, 152, 450, 60)
	GUICtrlCreateGroup("", -99, -99, 1, 1)
	GUICtrlSetState($idRadioBasic, $GUI_CHECKED)

	GUICtrlCreateLabel( _
			"Advanced method only: to preserve your own (non-Adobe) hosts entries," & @CRLF & _
			"create the file " & @WindowsDir & "\System32\drivers\etc\hosts.plain" & @CRLF & _
			"with those entries. The script merges them on each run.", _
			15, 230, 490, 50)

	Local $idBtnSetup = GUICtrlCreateButton("Setup", 15, 290, 110, 32)
	Local $idBtnRunNow = GUICtrlCreateButton("Run Now", 135, 290, 110, 32)
	Local $idBtnRemove = GUICtrlCreateButton("Remove", 255, 290, 110, 32)
	Local $idBtnClose = GUICtrlCreateButton("Close", 395, 290, 110, 32)

	_RefreshAutoUpdateDialogStatus($idLblStatus, $idBtnRunNow, $idBtnRemove)

	GUISetState(@SW_SHOW, $hDlg)

	Local $bExit = False
	Local $iMsg
	Local $iMethod
	Local $bOk
	Local $iErr
	Local $sMsg
	Local $sSuccessMsg

	While Not $bExit
		$iMsg = GUIGetMsg()
		Switch $iMsg
			Case $GUI_EVENT_CLOSE, $idBtnClose
				$bExit = True

			Case $idBtnSetup
				If BitAND(GUICtrlRead($idRadioAdvanced), $GUI_CHECKED) = $GUI_CHECKED Then
					$iMethod = $g_iHAU_METHOD_ADVANCED
				Else
					$iMethod = $g_iHAU_METHOD_BASIC
				EndIf

				$bOk = _SetupHostsAutoUpdate($iMethod, "00:00")
				If $bOk Then
					If $iMethod = $g_iHAU_METHOD_BASIC Then
						$sSuccessMsg = "Will refresh daily at 00:00."
					Else
						$sSuccessMsg = "Will refresh every 3 hours."
					EndIf
					MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Setup complete", _
							"Scheduled task created." & @CRLF & @CRLF & $sSuccessMsg)
				Else
					$iErr = @error
					$sMsg = "Setup failed."
					Switch $iErr
						Case 1
							$sMsg = "GenP must be running as Administrator."
						Case 2
							$sMsg = "Setup cancelled - GenP path is in a user folder."
						Case 3
							$sMsg = "schtasks command failed (exit code " & @extended & ")."
						Case 4
							$sMsg = "Advanced method: failed to deploy UpdateHostsFile.ps1." & @CRLF & _
									"Check that the file was bundled into the GenP build."
						Case 5
							$sMsg = "Task creation reported success but task is not visible." & @CRLF & _
									"Check Task Scheduler manually."
					EndSwitch
					MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Setup failed", $sMsg)
				EndIf
				_RefreshAutoUpdateDialogStatus($idLblStatus, $idBtnRunNow, $idBtnRemove)

			Case $idBtnRunNow
				If _RunHostsAutoUpdateNow() Then
					Local $iLogBefore = 0
					If FileExists($g_sHAU_LOG_TARGET) Then $iLogBefore = FileGetTime($g_sHAU_LOG_TARGET, 1, 1)
					Local $hRunTimer = TimerInit()
					Local $bChanged = False
					While TimerDiff($hRunTimer) < 8000
						If FileExists($g_sHAU_LOG_TARGET) Then
							Local $iLogAfter = FileGetTime($g_sHAU_LOG_TARGET, 1, 1)
							If $iLogAfter > $iLogBefore Then
								$bChanged = True
								ExitLoop
							EndIf
						EndIf
						Sleep(400)
					WEnd
					If $bChanged Then
						Local $sLastLine = ""
						Local $hLog = FileOpen($g_sHAU_LOG_TARGET, 0)
						If $hLog <> -1 Then
							Local $sAll = FileRead($hLog)
							FileClose($hLog)
							Local $aLines = StringSplit(StringStripCR($sAll), @LF)
							For $i = $aLines[0] To 1 Step -1
								If StringStripWS($aLines[$i], 3) <> "" Then
									$sLastLine = StringStripWS($aLines[$i], 1 + 2)
									ExitLoop
								EndIf
							Next
						EndIf
						MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Run Now", _
								"Task completed." & @CRLF & @CRLF & _
								"Last log line:" & @CRLF & $sLastLine)
					Else
						MsgBox(BitOR($MB_OK, $MB_ICONWARNING), "Run Now", _
								"Task triggered but no log update detected in 8 seconds." & @CRLF & _
								"It may still be running - check the log file in a moment:" & @CRLF & _
								$g_sHAU_LOG_TARGET)
					EndIf
				Else
					MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Run Now", _
							"Could not trigger the task. Is it installed and are you Admin?")
				EndIf

			Case $idBtnRemove
				If MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING), "Remove", _
						"Remove the scheduled task?" & @CRLF & _
						"(Advanced method: also removes UpdateHostsFile.ps1 and its log.)") = $IDYES Then
					If _RemoveHostsAutoUpdate(True) Then
						MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Removed", "Scheduled task removed.")
					Else
						MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Remove", "Removal failed (@error=" & @error & ").")
					EndIf
					_RefreshAutoUpdateDialogStatus($idLblStatus, $idBtnRunNow, $idBtnRemove)
				EndIf
		EndSwitch
	WEnd

	GUIDelete($hDlg)
EndFunc

Func _RefreshAutoUpdateDialogStatus($idLbl, $idBtnRunNow, $idBtnRemove)
	Local $iMethod = _GetHostsAutoUpdateMethod()
	Switch $iMethod
		Case $g_iHAU_METHOD_BASIC
			GUICtrlSetData($idLbl, "Basic method installed (daily)")
			GUICtrlSetColor($idLbl, 0x008000)
			GUICtrlSetState($idBtnRunNow, $GUI_ENABLE)
			GUICtrlSetState($idBtnRemove, $GUI_ENABLE)
		Case $g_iHAU_METHOD_ADVANCED
			GUICtrlSetData($idLbl, "Advanced method installed (every 3 hours)")
			GUICtrlSetColor($idLbl, 0x008000)
			GUICtrlSetState($idBtnRunNow, $GUI_ENABLE)
			GUICtrlSetState($idBtnRemove, $GUI_ENABLE)
		Case Else
			GUICtrlSetData($idLbl, "Not installed")
			GUICtrlSetColor($idLbl, 0x808080)
			GUICtrlSetState($idBtnRunNow, $GUI_DISABLE)
			GUICtrlSetState($idBtnRemove, $GUI_DISABLE)
	EndSwitch
EndFunc

Func _SilentHostsInjector($sDomain)
	$sDomain = StringLower(StringStripWS($sDomain, 3))
	If $sDomain = "" Then Return SetError(2, 0, False)

	Local $sHostsPath = @WindowsDir & "\System32\drivers\etc\hosts"
	Local $sStartMark = "# START - Adobe Endpoint Block"
	Local $sEndMark = "# END - Adobe Endpoint Block"
	Local $sStartEsc = StringRegExpReplace($sStartMark, "([.*+?^${}()|[\]\\])", "\\$1")
	Local $sEndEsc = StringRegExpReplace($sEndMark, "([.*+?^${}()|[\]\\])", "\\$1")
	Local $sCleanText = ""

	If FileExists($sHostsPath) Then
		Local $sHostsContent = FileRead($sHostsPath)

		Local $aBlockCheck = StringRegExp($sHostsContent, "(?s)" & $sStartEsc & "(.*?)" & $sEndEsc, 1)
		If Not @error Then
			If StringInStr($aBlockCheck[0], $sDomain) Then Return True
		EndIf

		$sCleanText = StringRegExpReplace($sHostsContent, "(?s)\r?\n?" & $sStartEsc & ".*?" & $sEndEsc & "\r?\n?", "")
		$sCleanText = StringStripWS($sCleanText, 2)
	EndIf

	Local $sUtcTimestamp = @YEAR & "-" & @MON & "-" & @MDAY & " " & StringFormat("%02d:%02d", @HOUR, @MIN) & " UTC"
	Local $sNewBlock = @CRLF & @CRLF & _
			$sStartMark & @CRLF & _
			"# Last update: " & $sUtcTimestamp & @CRLF & _
			"0.0.0.0 ic.adobe.io" & @CRLF & _
			"0.0.0.0 " & $sDomain & @CRLF & _
			$sEndMark & @CRLF

	Local $hFile = FileOpen($sHostsPath, 2)
	If $hFile = -1 Then
		$g_bHostsInjectInProgress = True
		_AppendToLogWindow("# ERROR: Could not write hosts file (run as Administrator). Target: " & $sDomain & @CRLF)
		$g_bHostsInjectInProgress = False
		Return SetError(1, 0, False)
	EndIf

	FileWrite($hFile, $sCleanText & $sNewBlock)
	FileClose($hFile)
	RunWait("ipconfig /flushdns", "", @SW_HIDE)

	$g_bHostsInjectInProgress = True
	_AppendToLogWindow("# Adobe Endpoint Block written -> 0.0.0.0 ic.adobe.io + 0.0.0.0 " & $sDomain & "  (DNS cache flushed)" & @CRLF)
	$g_bHostsInjectInProgress = False

	Return True
EndFunc

Func UpdateHostsFile()
	If Not _RequireAdmin("modify the Windows hosts file") Then Return
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	RemoveHostsEntries()
	GUICtrlSetState($idBtnUpdateHosts, $GUI_DISABLE)
	MemoWrite(@CRLF & "Starting hosts file update..." & @CRLF)

	Local $sHostsPath = @WindowsDir & "\System32\drivers\etc\hosts"
	Local $sBackupPath = $sHostsPath & ".bak"
	Local $sMarkerStart = "# START - Adobe Blocklist"
	Local $sMarkerEnd = "# END - Adobe Blocklist"
	Local $sDomainListURL = $sCurrentDomainListURL
	Local $sTempFileDownload, $sDomainList, $sHostsContent, $hFile

	FileSetAttrib($sHostsPath, "-R")

	If Not FileExists($sBackupPath) Then
		If Not FileCopy($sHostsPath, $sBackupPath, 1) Then
			MemoWrite("Error creating hosts backup." & @CRLF)
			GUICtrlSetState($idBtnUpdateHosts, $GUI_ENABLE)
			FileSetAttrib($sHostsPath, "+R")
			Return
		EndIf
		MemoWrite("Hosts file backed up." & @CRLF)
	EndIf

	$sTempFileDownload = _TempFile(@TempDir & "\domain_list")
	Local $iInetResult = InetGet($sDomainListURL, $sTempFileDownload, 1)
	If @error Or $iInetResult = 0 Then
		MemoWrite("Download Error: " & @error & ", InetGet Result: " & $iInetResult & @CRLF)
		MemoWrite("Remote domain list unreachable - hosts file unchanged." & @CRLF)
		MemoWrite("Check your network connection and try again when available." & @CRLF)
		LogWrite(1, "Hosts list download failed (remote unreachable). No changes applied.")
		FileDelete($sTempFileDownload)
		GUICtrlSetState($idBtnUpdateHosts, $GUI_ENABLE)
		FileSetAttrib($sHostsPath, "+R")
		Return
	EndIf
	$sDomainList = FileRead($sTempFileDownload)
	FileDelete($sTempFileDownload)
	MemoWrite("Downloaded remote list:" & @CRLF & $sDomainList & @CRLF)

	$sHostsContent = FileRead($sHostsPath)
	If @error Then
		MemoWrite("Error reading hosts file." & @CRLF)
		GUICtrlSetState($idBtnUpdateHosts, $GUI_ENABLE)
		FileSetAttrib($sHostsPath, "+R")
		Return
	EndIf
	$sHostsContent = StringStripWS($sHostsContent, 2)

	Local $sNewContent = $sMarkerStart & @CRLF & $sDomainList & @CRLF & $sMarkerEnd
	If StringLen($sHostsContent) > 0 Then
		$sHostsContent &= @CRLF & $sNewContent
	Else
		$sHostsContent = $sNewContent
	EndIf

	MemoWrite(@CRLF & "Scanning DNS cache for additional (sub)domains..." & @CRLF)
	Local $aDNSDomainsAdded = ScanDNSCache($sHostsContent)
	If IsArray($aDNSDomainsAdded) And UBound($aDNSDomainsAdded) > 0 Then
		Local $sDNSEntries = ""
		For $i = 0 To UBound($aDNSDomainsAdded) - 1
			$sDNSEntries &= "0.0.0.0 " & $aDNSDomainsAdded[$i] & @CRLF
		Next
		$sHostsContent = StringRegExpReplace($sHostsContent, "(?s)(" & $sMarkerStart & ".*?)(" & $sMarkerEnd & ")", "$1" & $sDNSEntries & "$2")
		MemoWrite("Added from DNS cache:" & @CRLF & _ArrayToString($aDNSDomainsAdded, @CRLF) & @CRLF)
		LogWrite(1, "Added from DNS cache: " & _ArrayToString($aDNSDomainsAdded, ", ") & @CRLF)
	Else
		MemoWrite("No new domains found in DNS cache." & @CRLF)
	EndIf

	$hFile = FileOpen($sHostsPath, 2)
	If $hFile = -1 Then
		Local $iLastError = _WinAPI_GetLastError()
		MemoWrite("Error opening hosts file for writing: Last Error = " & $iLastError & @CRLF)
		GUICtrlSetState($idBtnUpdateHosts, $GUI_ENABLE)
		FileSetAttrib($sHostsPath, "+R")
		Return
	EndIf
	FileWrite($hFile, $sHostsContent)
	FileClose($hFile)

	FileSetAttrib($sHostsPath, "+R")
	LogWrite(1, "Hosts file updated successfully." & @CRLF)
	ToggleLog(1)
	GUICtrlSetState($idBtnUpdateHosts, $GUI_ENABLE)
EndFunc

Func EditHosts()
	Local $sHostsPath = @WindowsDir & "\System32\drivers\etc\hosts"
	Local $sBackupPath = @WindowsDir & "\System32\drivers\etc\hosts.bak"

	FileSetAttrib($sHostsPath, "-R")

	If Not FileExists($sBackupPath) Then
		FileCopy($sHostsPath, $sBackupPath)
	EndIf

	Local $iPID = Run("notepad.exe " & $sHostsPath)
	If $iPID = 0 Then
		MemoWrite("Error launching Notepad." & @CRLF)
		FileSetAttrib($sHostsPath, "+R")
		Return
	EndIf

	Local $iTimeout = 300000
	Local $iWaitResult = ProcessWaitClose($iPID, $iTimeout)
	If $iWaitResult = 0 Then
		ProcessClose($iPID)
		MemoWrite("Warning: Notepad timed out after " & $iTimeout / 1000 & " seconds." & @CRLF)
	EndIf

	FileSetAttrib($sHostsPath, "+R")
EndFunc

Func RestoreHosts()
	If Not _RequireAdmin("restore the Windows hosts file") Then Return
	_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
	MemoWrite(@CRLF & "Restoring the hosts file from backup..." & @CRLF & "---" & @CRLF & "Please wait..." & @CRLF)
	Local $sHostsPath = @WindowsDir & "\System32\drivers\etc\hosts"
	Local $sBackupPath = @WindowsDir & "\System32\drivers\etc\hosts.bak"

	If FileExists($sBackupPath) Then
		FileSetAttrib($sHostsPath, "-R")
		If FileCopy($sBackupPath, $sHostsPath, 1) Then
			FileSetAttrib($sHostsPath, "+R")
			FileDelete($sBackupPath)
			LogWrite(1, "Restoring the hosts file from backup: Success!" & @CRLF)
		Else
			MemoWrite("Error restoring hosts file from backup." & @CRLF)
			FileSetAttrib($sHostsPath, "+R")
			LogWrite(1, "Restoring the hosts file from backup: Failed." & @CRLF)
		EndIf
	Else
		LogWrite(1, "Restoring the hosts file from backup: No backup file found." & @CRLF)
	EndIf
	ToggleLog(1)
EndFunc

