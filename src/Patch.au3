; =====================================================================
; Patch.au3  -  Application module.
; Functions (34):
;   - _DefaultPatternsCount
;   - _CheckPatchStatesVersion
;   - RecursiveFileSearch
;   - _StoreFileInMaster
;   - _RunFinalCleanCheck
;   - _FinalCheck_RemoveBaks
;   - _UXPPatchedState
;   - _VerifyListedFiles
;   - MyGlobalPatternSearch
;   - ExecuteSearchPatterns
;   - MyRegExpGlobalPatternSearch
;   - MyGlobalPatternPatch
;   - _PatchLargeFileWithPatterns
;   - RestoreFile
;   - _QueueStateWrite
;   - _VerifyBackupAgainstLedger
;   - _RestoreManifestJsonIfBackupExists
;   - _FlushStateQueue
;   - _ReconcilePatchStates
;   - _WipeAdobeLicenseCaches
;   - _CleanOOBEDirectorySafely
;   - _ClearLicenseCachesLight
;   - _BuildAdobeWebViewTokens
;   - _TargetFolderReady
;   - _CreateInitialPatchStates
;   - _CleanOrphanBaks
;   - _PatchAdobeUXPComponent
;   - _AutoUnpackIfRuntimeInstaller
;   - _PatchStatesSetupDone
;   - _AppsBar_Dispatch
;   - FindRuntimeInstallerFiles
;   - UnpackRuntimeInstallers
;   - RuntimeDllSelectionGUI
;   - _FinalisePatchRun
; =====================================================================

Func _DefaultPatternsCount()
	Local $sVals = StringReplace(IniRead($sINIPath, "DefaultPatterns", "Values", ""), '"', "")
	$sVals = StringStripWS($sVals, 3)
	If $sVals = "" Then Return 0
	Local $a = StringSplit($sVals, ",")
	Return $a[0]
EndFunc

Func _CheckPatchStatesVersion()
	If Not FileExists($patchStatesINI) Then
		Return
	EndIf

	Local $sPriorVersion = IniRead($patchStatesINI, "Info", "GenPVersion", "")

	If $sPriorVersion = "" Then
		$sPriorVersion = "Unknown (pre-4.0.2)"
	EndIf

	Local $iCurrent = _VersionToNumber($g_Version)
	Local $iPrior = _VersionToNumber($sPriorVersion)

	If $iPrior < $iCurrent Then
		Local $iResult = MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING, $MB_SYSTEMMODAL), _
				"Version Upgrade Required", _
				"Your patch_states.ini is incompatible" & @CRLF & _
				"Current GenP " & $g_Version & " / Config " & $ConfigVerVar & @CRLF & _
				"For proper operation, you MUST:" & @CRLF & _
				"1. Delete patch_states.ini" & @CRLF & _
				"2. Rerun GenP to create a fresh baseline" & @CRLF & @CRLF & _
				"Continuing without this step may cause black screens." & @CRLF & @CRLF & _
				"Delete patch_states.ini now and exit? (Recommended)")

		If $iResult = $IDYES Then
			If FileDelete($patchStatesINI) Then
				IniWrite($sINIPath, "Options", "CreatedNew",        "0")
				IniWrite($sINIPath, "Options", "CreatedNewDate",    "")
				IniWrite($sINIPath, "Options", "ReconcileUsed",     "0")
				IniWrite($sINIPath, "Options", "ReconcileUsedDate", "")
				MsgBox($MB_OK, "Cleanup Complete", _
						"patch_states.ini has been deleted." & @CRLF & @CRLF & _
						"Close and run it again to create fresh baseline.")
				Exit
			Else
				MsgBox($MB_ICONERROR, "Error", "Could not delete patch_states.ini. Check file permissions.")
			EndIf
		Else
			MsgBox($MB_ICONWARNING, "Proceeding at Own Risk", _
					"If you experience issues, delete patch_states.ini and rerun.")
		EndIf
	EndIf
EndFunc

Func RecursiveFileSearch($INSTARTDIR, $DEPTH, $FileCount)
	Local $RecursiveFileSearch_MaxDeep = 8
	If $DEPTH > $RecursiveFileSearch_MaxDeep Then Return

	If $DEPTH = 0 Then _EnsureCcxStartPinned()

	Local $STARTDIR = $INSTARTDIR & "\"
	$FileSearchedCount += 1

	Local $HSEARCH = FileFindFirstFile($STARTDIR & "*.*")
	If @error Then Return

	Local $NEXT, $IPATH, $isDir

	While $fInterrupt = 0
		$NEXT = FileFindNextFile($HSEARCH)
		$FileSearchedCount += 1

		If @error Then ExitLoop
		$isDir = StringInStr(FileGetAttrib($STARTDIR & $NEXT), "D")

		If $isDir Then
			If StringInStr($NEXT, "(Prerelease)") Then ContinueLoop
			If StringRegExp($NEXT, "(?i)^com\.adobe\.ccx\.start-.*\.orig$") Then ContinueLoop
			Local $targetDepth
			$targetDepth = RecursiveFileSearch($STARTDIR & $NEXT, $DEPTH + 1, $FileCount)
		Else
			$IPATH = $STARTDIR & $NEXT
			Local $FileNameCropped, $PathToCheck
			If (IsArray($TargetFileList)) Then
				For $FileTarget In $TargetFileList
					$PathToCheck = ""
					If StringInStr($FileTarget, "|") Then
						Local $aFT = StringSplit($FileTarget, "|", $STR_ENTIRESPLIT)
						$PathToCheck = $aFT[2]
						$FileTarget = $aFT[1]
					ElseIf StringInStr($FileTarget, "$") Then
						Local $aFT = StringSplit($FileTarget, "$", $STR_ENTIRESPLIT)
						$PathToCheck = $aFT[2]
						$FileTarget = $aFT[1]
					EndIf
					Local $sBasenameLC = StringLower(StringRegExpReplace($IPATH, "^.*\\", ""))
					If $sBasenameLC = StringLower($FileTarget) Then
						If Not StringInStr($IPATH, ".bak") And Not StringInStr(StringLower($IPATH), "wintrust") Then
							If (StringInStr($IPATH, "Adobe") Or StringInStr($IPATH, "Acrobat")) Or $bOnlyAFolders = 0 Then
								Local $bPathMatches = True
								If $PathToCheck <> "" Then
									If StringInStr($PathToCheck, "*") Then
										Local $sRegex = StringReplace($PathToCheck, "\", "\\")
										$sRegex = StringReplace($sRegex, ".", "\.")
										$sRegex = StringReplace($sRegex, "*", "[^\\]*")
										$bPathMatches = (StringRegExp($IPATH, "(?i)" & $sRegex) = 1)
									Else
										$bPathMatches = (StringInStr($IPATH, $PathToCheck) > 0)
									EndIf
								EndIf
								If $bPathMatches Then
									_StoreFileInMaster($IPATH)
								EndIf
							ElseIf StringInStr($IPATH, ".bak") Then
								_ArrayAdd($FilesToRestore, $IPATH)
							EndIf
						EndIf
					EndIf
				Next
			EndIf
		EndIf
	WEnd

	If 1 = Random(0, 10, 1) Then
		MemoWrite(@CRLF & "Searching in " & $FileCount & " files" & @TAB & @TAB & "Found : " & UBound($g_aAllFiles) & @CRLF & _
				"---" & @CRLF & _
				"Level: " & $DEPTH & " Time elapsed : " & Round(TimerDiff($timestamp) / 1000, 0) & " second(s)" & @TAB & @TAB & "Excluded because of *.bak: " & UBound($FilesToRestore) & @CRLF & _
				"---" & @CRLF & _
				$INSTARTDIR _
				)
		ProgressWrite($ProgressFileCountScale * $FileSearchedCount)
		_ShowStatusScreen("scanning", $INSTARTDIR)
		_SubProgressWrite(Mod($g_dotCounter * 5, 101))
	EndIf

	FileClose($HSEARCH)
EndFunc

Func _StoreFileInMaster($sPath)
	If StringInStr($sPath, "(Prerelease)") Then Return
	Local $sFileName = StringRegExpReplace($sPath, "^.*\\", "")
	Local $sFileNameLC = StringLower($sFileName)

	Local $sAuxFilesToSkip = "|dynamic-torqnative.dll|lec.dll|"
	If StringInStr($sAuxFilesToSkip, "|" & $sFileNameLC & "|") Then
		For $k = 0 To UBound($g_aAllFiles) - 1
			If $g_aAllFiles[$k][1] = $sFileName Then Return
		Next
	EndIf

	For $k = 0 To UBound($g_aAllFiles) - 1
		If $g_aAllFiles[$k][0] = $sPath Then Return
	Next

	Local $sPathLC = StringLower($sPath)

	Local $bIsACC = StringInStr($sPathLC, "\common files\adobe\") > 0

	Local $bIsBeta = (StringInStr($sPath, "(Beta)") > 0) Or (StringInStr($sPath, " Beta\") > 0) Or (StringInStr($sPathLC, "\adobe animate beta") > 0)

	Local $bReqGood1 = (StringInStr($g_sRequiresGood1Files, "|" & $sFileNameLC & "|") > 0)

	Local $bIsNGL = (StringRegExp($sFileNameLC, "^adobe_licensing_(wf|wf_helper|helper).*\.exe$") > 0) And (StringInStr($sPathLC, "\acrobat\") = 0) And (StringInStr($sPathLC, "acro") = 0)

	Local $iIdx = UBound($g_aAllFiles)
	ReDim $g_aAllFiles[$iIdx + 1][6]
	$g_aAllFiles[$iIdx][0] = $sPath
	$g_aAllFiles[$iIdx][1] = $sFileName
	$g_aAllFiles[$iIdx][2] = $bIsACC
	$g_aAllFiles[$iIdx][3] = $bIsBeta
	$g_aAllFiles[$iIdx][4] = $bReqGood1
	$g_aAllFiles[$iIdx][5] = $bIsNGL

	_ArrayAdd($FilesToPatch, $sPath)

	_BumpScanCounters($sPath)
EndFunc

Func _RunFinalCleanCheck()
	Local $sReport = ""

	Local $sWinDrive   = StringUpper(StringLeft(@WindowsDir, 2))
	Local $sMyDefDrive = StringUpper(StringLeft($MyDefPath, 2))
	Local $sExtraDrives = _PickExtraAdobeDrives($sWinDrive, $sMyDefDrive)

	Local $aFCCPos = WinGetPos($MyhGUI)
	Local $iFCCW = 380, $iFCCH = 76
	Local $hFCCStatus = GUICreate("Final Adobe Clean Check", $iFCCW, $iFCCH, _
			$aFCCPos[0] + ($aFCCPos[2] - $iFCCW) / 2, _
			$aFCCPos[1] + ($aFCCPos[3] - $iFCCH) / 2, _
			BitOR($WS_POPUP, $WS_CAPTION), $WS_EX_TOPMOST)
	Local $idStepLabel = GUICtrlCreateLabel("Starting...", 10, 12, $iFCCW - 20, 20)
	Local $idStepBar   = GUICtrlCreateProgress(10, 42, $iFCCW - 20, 16)
	GUISetState(@SW_DISABLE, $MyhGUI)
	GUISetState(@SW_SHOW, $hFCCStatus)

	GUICtrlSetData($idStepLabel, "Removing windows defender firewall rules...")
	GUICtrlSetData($idStepBar, 10)
	If CheckThirdPartyFirewall() Then
		$sReport &= "Firewall rules:   Third-party firewall active - remove Adobe rules manually." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  Firewall", _
				"A third-party firewall is active on this system." & @CRLF & @CRLF & _
				"GenP cannot automatically check or remove Adobe firewall rules." & @CRLF & @CRLF & _
				"Please open your firewall software, remove any Adobe outbound rules" & @CRLF & _
				"manually, then click OK to continue.")
	ElseIf _WinFirewallServiceReady() Then
		Local $sFWPS = 'powershell.exe -NoProfile -Command "' & _
			"$r = 0; " & _
			"Get-NetFirewallRule -Direction Outbound -ErrorAction SilentlyContinue | " & _
			"Where-Object { $_.DisplayName -like 'Adobe-Block*' -or $_.Group -eq 'GenP NGL Firewall' } | " & _
			"ForEach-Object { Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue; $r++ }; " & _
			"Write-Output $r"""
		Local $iPIDFW = Run(@ComSpec & " /c " & $sFWPS, "", @SW_HIDE, $STDOUT_CHILD)
		ProcessWaitClose($iPIDFW, 15000)
		Local $iFWRemoved = Int(StringStripWS(StdoutRead($iPIDFW), 3))
		If $iFWRemoved > 0 Then
			$sReport &= "Firewall rules:   " & $iFWRemoved & " GenP rule(s) removed." & @CRLF
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Firewall", _
					"Firewall rules: " & $iFWRemoved & " GenP Adobe rule(s) removed." & @CRLF & @CRLF & _
					"Click OK to continue.")
		Else
			$sReport &= "Firewall rules:   None found." & @CRLF
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Firewall", _
					"Firewall rules: none found  -  all clear." & @CRLF & @CRLF & _
					"Click OK to continue.")
		EndIf
	Else
		$sReport &= "Firewall rules:   Windows Firewall service unavailable - skipped." & @CRLF
	EndIf

#cs === [PROXY-REMOVED] Final-Clean-Check proxy/mitmproxy step ===
; WHY THIS IS OFF:
;   This block was the TEARDOWN half of the proxy feature. If mitmproxy was
;   installed it called _RemoveMitmproxy() (in the now-excised Proxy.au3) to stop
;   mitmdump, uninstall its certificate, and delete its files.
;   Removed for two reasons:
;     1) NECESSARY - _RemoveMitmproxy / _IsMitmproxyInstalled / _DisableWindowsProxy
;        no longer exist (Proxy.au3 is excluded from the build).
;     2) REDUNDANT - with the Proxy tab gone there is no longer any way to INSTALL
;        the proxy, so Final Clean Check has nothing to tear down.
;   EDGE CASE: a proxy installed by an EARLIER GenP build is no longer cleaned up
;   by this build - the user would have to remove mitmdump + its certificate manually.
	GUICtrlSetData($idStepLabel, "Checking proxy and mitmproxy...")
	GUICtrlSetData($idStepBar, 20)
	Local $bMitmInstalled = _IsMitmproxyInstalled()
	If $bMitmInstalled Then
		_RemoveMitmproxy()
		$sReport &= "Proxy/mitmproxy:  Stopped, certificate removed, files deleted." & @CRLF
	ElseIf _IsWindowsProxyOn() Then
		_DisableWindowsProxy()
		RunWait(@ComSpec & " /c netsh winhttp reset proxy", "", @SW_HIDE)
		$sReport &= "Proxy:            Windows proxy disabled." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Proxy", _
				"Proxy: Windows system proxy has been disabled." & @CRLF & @CRLF & _
				"Click OK to continue.")
	Else
		$sReport &= "Proxy/mitmproxy:  Not configured." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Proxy", _
				"Proxy / mitmproxy: not configured  -  all clear." & @CRLF & @CRLF & _
				"Click OK to continue.")
	EndIf
#ce === [PROXY-REMOVED] end Final-Clean-Check proxy step ===

	GUICtrlSetData($idStepLabel, "Removing scheduled tasks and log files...")
	GUICtrlSetData($idStepBar, 33)
	Local $sTaskReport = ""
	; NOTE [SCHEDULE-HOSTS-REMOVED]: this stays LIVE even though the Schedule-updates
	;   button/dialog were removed. _IsHostsAutoUpdateInstalled checks the real Windows
	;   Task Scheduler, so a task installed by an EARLIER/official GenP build (or before
	;   the button was removed) can still exist on this machine - and Final Clean Check's
	;   whole job is to remove it. It returns "not installed" harmlessly when none exists.
	;   DO NOT wrap this: removing a feature's CREATION path (the button) does not make its
	;   CLEANUP path pointless. (Contrast: the proxy cleanup above HAD to go, because
	;   _RemoveMitmproxy lived in the excised Proxy.au3 - a different, forced reason.)
	If _IsHostsAutoUpdateInstalled() Then
		_RemoveHostsAutoUpdate(True)
		$sTaskReport &= "UpdateHostsFile task removed"
	EndIf
	If _IsGudeCleanupInstalled() Then
		_RemoveGudeCleanup()
		$sTaskReport &= ($sTaskReport <> "" ? ", " : "") & "Gude Log Cleanup task removed"
	EndIf
	If FileExists($g_sHAU_LOG_TARGET) Then FileDelete($g_sHAU_LOG_TARGET)
	If FileExists($g_sGUDE_LOG_TARGET) Then FileDelete($g_sGUDE_LOG_TARGET)
	$sReport &= "Scheduled tasks:  " & ($sTaskReport <> "" ? $sTaskReport & "." : "No GenP tasks found.") & @CRLF
	MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Scheduled Tasks", _
			"Scheduled tasks:" & @CRLF & @CRLF & _
			($sTaskReport <> "" ? $sTaskReport & "." : "No GenP tasks found  -  all clear.") & @CRLF & @CRLF & _
			"Click OK to continue.")

	GUICtrlSetData($idStepLabel, "Cleaning hosts file...")
	GUICtrlSetData($idStepBar, 46)
	Local $sHostsPath = @WindowsDir & "\System32\drivers\etc\hosts"
	Local $sHMarker   = "# START - Adobe Blocklist"
	FileSetAttrib($sHostsPath, "-R")
	Local $sHostsContent = FileRead($sHostsPath)
	Local $sHostsMsg = ""
	If Not @error And StringInStr($sHostsContent, $sHMarker) Then
		$sHostsContent = StringRegExpReplace($sHostsContent, "(?s)# START - Adobe Blocklist.*?# END - Adobe Blocklist", "")
		Local $hHF = FileOpen($sHostsPath, 2)
		FileWrite($hHF, $sHostsContent)
		FileClose($hHF)
		$sHostsMsg = "GenP blocklist entries removed."
	Else
		$sHostsMsg = "No GenP entries found."
	EndIf
	$sHostsContent = FileRead($sHostsPath)
	Local $aHLines = StringSplit($sHostsContent, @LF, 1)
	Local $bHasAdobeLines = False
	For $iHL = 1 To $aHLines[0]
		Local $sHL = StringStripWS($aHLines[$iHL], 3)
		If $sHL = "" Or StringLeft($sHL, 1) = "#" Then ContinueLoop
		If StringInStr(StringLower($sHL), "adobe") Then
			$bHasAdobeLines = True
			ExitLoop
		EndIf
	Next
	Local $sEtcDir = @WindowsDir & "\System32\drivers\etc\"
	If $bHasAdobeLines Then
		Local $sHostsPlain = $sEtcDir & "hosts.plain"
		If FileExists($sHostsPlain) Then
			$sHostsMsg &= "  Additional Adobe entries found  -  please replace manually (see below)."
			MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  Hosts File", _
					"Adobe entries were still found in your hosts file." & @CRLF & @CRLF & _
					"Your original backup (hosts.plain) exists. Please replace your" & @CRLF & _
					"hosts file with either:" & @CRLF & @CRLF & _
					"  1) Your backup file at:" & @CRLF & _
					"     C:\Windows\System32\drivers\etc\hosts.plain" & @CRLF & @CRLF & _
					"  2) A clean default containing only:" & @CRLF & _
					"     127.0.0.1 localhost" & @CRLF & _
					"     ::1 localhost" & @CRLF & @CRLF & _
					"Then click OK to continue.")
		Else
			Local $hHF2 = FileOpen($sHostsPath, 2)
			FileWrite($hHF2, "127.0.0.1 localhost" & @CRLF & "::1 localhost" & @CRLF)
			FileClose($hHF2)
			$sHostsMsg &= "  Additional Adobe entries found  -  replaced with clean default."
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Hosts File", _
					"Adobe entries were found in your hosts file." & @CRLF & @CRLF & _
					"Your hosts file has been replaced with a clean default." & @CRLF & @CRLF & _
					"Click OK to confirm and continue.")
		EndIf
	Else
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Hosts File", _
				"Hosts file is clean." & @CRLF & @CRLF & _
				$sHostsMsg & @CRLF & @CRLF & _
				"Click OK to continue.")
		If FileExists($sEtcDir & "hosts.plain") Then
			MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  Hosts File", _
					"A hosts.plain backup was found from GenP's UpdateHosts feature." & @CRLF & @CRLF & _
					"Your hosts file looks clean, but this backup still exists. Please either:" & @CRLF & @CRLF & _
					"  1) Restore from it if you want your original hosts file back" & @CRLF & _
					"  2) Or delete it if your current hosts file is already correct" & @CRLF & @CRLF & _
					"Location: " & $sEtcDir & "hosts.plain" & @CRLF & @CRLF & _
					"Click OK once done.")
		EndIf
	EndIf
	Local $sEtcBaks = ""
	Local $hEtcBak = FileFindFirstFile($sEtcDir & "*.bak")
	If $hEtcBak <> -1 Then
		While True
			Local $sEtcBakName = FileFindNextFile($hEtcBak)
			If @error Then ExitLoop
			$sEtcBaks &= "  - " & $sEtcDir & $sEtcBakName & @CRLF
		WEnd
		FileClose($hEtcBak)
	EndIf
	If $sEtcBaks <> "" Then
		$sReport &= "Hosts .bak files: Stray backup(s) found (remove manually):" & @CRLF & $sEtcBaks
		MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  Hosts Backups", _
				"Stray backup file(s) found in your hosts directory." & @CRLF & @CRLF & _
				"Please delete these manually, then click OK to continue:" & @CRLF & @CRLF & _
				$sEtcBaks)
	EndIf
	FileSetAttrib($sHostsPath, "+R")
	$sReport &= "Hosts file:       " & $sHostsMsg & @CRLF

	GUICtrlSetData($idStepLabel, "Removing leftover .bak files...")
	GUICtrlSetData($idStepBar, 58)
	Local $iBakTotal = _FinalCheck_RemoveBaks($MyDefPath)
	Local $sBakStd64 = EnvGet("ProgramFiles")       & "\Adobe"
	Local $sBakStd32 = EnvGet("ProgramFiles(x86)") & "\Adobe"
	If FileExists($sBakStd64) And StringLower($sBakStd64) <> StringLower($MyDefPath) Then $iBakTotal += _FinalCheck_RemoveBaks($sBakStd64)
	If FileExists($sBakStd32) And StringLower($sBakStd32) <> StringLower($MyDefPath) Then $iBakTotal += _FinalCheck_RemoveBaks($sBakStd32)
	Local $sACC32 = EnvGet("ProgramFiles(x86)") & "\Common Files\Adobe"
	Local $sACC64 = EnvGet("ProgramFiles")      & "\Common Files\Adobe"
	If FileExists($sACC32) Then $iBakTotal += _FinalCheck_RemoveBaks($sACC32)
	If FileExists($sACC64) Then $iBakTotal += _FinalCheck_RemoveBaks($sACC64)
	If $sMyDefDrive <> $sWinDrive Then
		Local $sMyPF64  = $sMyDefDrive & "\Program Files\Adobe"
		Local $sMyPF32  = $sMyDefDrive & "\Program Files (x86)\Adobe"
		Local $sMyACC64 = $sMyDefDrive & "\Program Files\Common Files\Adobe"
		Local $sMyACC32 = $sMyDefDrive & "\Program Files (x86)\Common Files\Adobe"
		If FileExists($sMyPF64)  And StringLower($sMyPF64)  <> StringLower($MyDefPath) Then $iBakTotal += _FinalCheck_RemoveBaks($sMyPF64)
		If FileExists($sMyPF32)  And StringLower($sMyPF32)  <> StringLower($MyDefPath) Then $iBakTotal += _FinalCheck_RemoveBaks($sMyPF32)
		If FileExists($sMyACC64) Then $iBakTotal += _FinalCheck_RemoveBaks($sMyACC64)
		If FileExists($sMyACC32) Then $iBakTotal += _FinalCheck_RemoveBaks($sMyACC32)
	EndIf
	If $sExtraDrives <> "" Then
		Local $aDriveList = StringSplit(StringReplace(StringReplace($sExtraDrives, " ", ""), ":", ""), ",", 1)
		For $k = 1 To $aDriveList[0]
			Local $sDL = StringUpper(StringLeft(StringStripWS($aDriveList[$k], 3), 1))
			If $sDL = "" Or $sDL = StringLeft($sWinDrive, 1) Or $sDL = StringLeft($sMyDefDrive, 1) Then ContinueLoop
			Local $sExPF64  = $sDL & ":\Program Files\Adobe"
			Local $sExPF32  = $sDL & ":\Program Files (x86)\Adobe"
			Local $sExACC64 = $sDL & ":\Program Files\Common Files\Adobe"
			Local $sExACC32 = $sDL & ":\Program Files (x86)\Common Files\Adobe"
			If FileExists($sExPF64)  Then $iBakTotal += _FinalCheck_RemoveBaks($sExPF64)
			If FileExists($sExPF32)  Then $iBakTotal += _FinalCheck_RemoveBaks($sExPF32)
			If FileExists($sExACC64) Then $iBakTotal += _FinalCheck_RemoveBaks($sExACC64)
			If FileExists($sExACC32) Then $iBakTotal += _FinalCheck_RemoveBaks($sExACC32)
		Next
	EndIf
	$sReport &= ".bak files:       " & $iBakTotal & " backup file(s) deleted." & @CRLF
	MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Backup Files", _
			".bak backup files: " & ($iBakTotal > 0 ? $iBakTotal & " file(s) removed." : "None found  -  all clear.") & @CRLF & @CRLF & _
			"Click OK to continue.")

	GUICtrlSetData($idStepLabel, "Checking remaining adobe folders...")
	GUICtrlSetData($idStepBar, 68)
	Local $sRemaining = ""
	Local $hDF = FileFindFirstFile($MyDefPath & "\*")
	If $hDF <> -1 Then
		While True
			Local $sDFEntry = FileFindNextFile($hDF)
			If @error Then ExitLoop
			If StringInStr(FileGetAttrib($MyDefPath & "\" & $sDFEntry), "D") Then
				$sRemaining &= "  - " & $sDFEntry & @CRLF
			EndIf
		WEnd
		FileClose($hDF)
	EndIf
	If $sRemaining <> "" Then
		$sReport &= "Adobe folders:    Still present (uninstall via CC or Control Panel):" & @CRLF & $sRemaining
		MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  Adobe Folders", _
				"The following Adobe installation folders are still present." & @CRLF & _
				"Please uninstall via Creative Cloud or Control Panel, or delete manually." & @CRLF & _
				"Click OK once cleared to continue:" & @CRLF & @CRLF & _
				$sRemaining)
	Else
		$sReport &= "Adobe folders:    None found in set path." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Adobe Folders", _
				"Adobe installation folders: all clear." & @CRLF & @CRLF & _
				"Click OK to continue.")
	EndIf

	GUICtrlSetData($idStepLabel, "Checking AppData and Temp for Adobe folders...")
	GUICtrlSetData($idStepBar, 78)
	Local $sUserFolders = ""
	Local $sAppData   = EnvGet("APPDATA")
	Local $sLocalApp  = EnvGet("LOCALAPPDATA")
	Local $sTempDir   = EnvGet("TEMP")
	If $sAppData  = "" Then $sAppData  = @AppDataDir
	If $sLocalApp = "" Then $sLocalApp = @LocalAppDataDir
	If $sTempDir  = "" Then $sTempDir  = @TempDir
	If FileExists($sAppData  & "\Adobe") Then $sUserFolders &= "  - %AppData%\Adobe" & @CRLF
	If FileExists($sLocalApp & "\Adobe") Then $sUserFolders &= "  - %LocalAppData%\Adobe" & @CRLF
	If FileExists($sTempDir  & "\Adobe") Then $sUserFolders &= "  - %Temp%\Adobe" & @CRLF
	If $sUserFolders <> "" Then
		$sReport &= "AppData folders:  Still present (clear manually):" & @CRLF & $sUserFolders
		MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  AppData Folders", _
				"The following Adobe folders were found in user directories." & @CRLF & _
				"Please delete these manually, then click OK to continue:" & @CRLF & @CRLF & _
				$sUserFolders)
	Else
		$sReport &= "AppData folders:  No Adobe folders found." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  AppData Folders", _
				"AppData and Temp Adobe folders: all clear." & @CRLF & @CRLF & _
				"Click OK to continue.")
	EndIf

	GUICtrlSetData($idStepLabel, "Restoring wintrust registry keys...")
	GUICtrlSetData($idStepBar, 87)
	Local $iIFEO    = RegRead($g_sWT_IFEO, "DevOverrideEnable")
	Local $iIFEOErr  = @error
	Local $iSxS     = RegRead($g_sWT_SxS, "DevOverrideEnable")
	Local $iSxSErr   = @error
	Local $iWT64    = RegRead($g_sWT_WT64, "EnableCertPaddingCheck")
	Local $iWT64Err  = @error
	Local $iWT32    = RegRead($g_sWT_WT32, "EnableCertPaddingCheck")
	Local $iWT32Err  = @error
	Local $bWTNeedsRestore = ($iIFEOErr = 0 And $iIFEO = 1) _
			Or ($iSxSErr = 0 And $iSxS = 1) _
			Or ($iWT64Err = 0 And $iWT64 = 0) _
			Or ($iWT32Err = 0 And $iWT32 = 0)
	If $bWTNeedsRestore Then
		Local $iWTFixed = 0
		RegWrite($g_sWT_IFEO, "DevOverrideEnable", "REG_DWORD", 0)
		If @error = 0 Then $iWTFixed += 1
		RegWrite($g_sWT_SxS, "DevOverrideEnable", "REG_DWORD", 0)
		If @error = 0 Then $iWTFixed += 1
		RegWrite($g_sWT_WT64, "EnableCertPaddingCheck", "REG_DWORD", 1)
		If @error = 0 Then $iWTFixed += 1
		RegWrite($g_sWT_WT32, "EnableCertPaddingCheck", "REG_DWORD", 1)
		If @error = 0 Then $iWTFixed += 1
		Local $sWTMsg = ""
		If $iWTFixed = 4 Then
			$sWTMsg = "Fully restored (DevOverride cleared, CertPadding re-enabled)."
		Else
			$sWTMsg = "Could not be restored - disable your antivirus and run Final Adobe Clean Check again."
		EndIf
		$sReport &= "WinTrust keys:    " & $sWTMsg & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  WinTrust", _
				"WinTrust registry keys:" & @CRLF & @CRLF & _
				$sWTMsg & @CRLF & @CRLF & _
				"Click OK to confirm and continue.")
	Else
		$sReport &= "WinTrust keys:    Already at secure defaults." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  WinTrust", _
				"WinTrust registry keys: already at secure defaults." & @CRLF & @CRLF & _
				"Click OK to continue.")
	EndIf

	GUICtrlSetData($idStepLabel, "Checking registry for Adobe entries...")
	GUICtrlSetData($idStepBar, 96)
	Local $sRegKeys = ""
	RegEnumKey("HKLM\SOFTWARE\Adobe", 1)
	If @error <> 1 Then $sRegKeys &= "  - HKLM\SOFTWARE\Adobe" & @CRLF
	RegEnumKey("HKLM\SOFTWARE\WOW6432Node\Adobe", 1)
	If @error <> 1 Then $sRegKeys &= "  - HKLM\SOFTWARE\WOW6432Node\Adobe" & @CRLF
	RegEnumKey("HKCU\SOFTWARE\Adobe", 1)
	If @error <> 1 Then $sRegKeys &= "  - HKCU\SOFTWARE\Adobe" & @CRLF
	If $sRegKeys <> "" Then
		$sReport &= "Registry:         Adobe entries still present (clear via Registry Editor):" & @CRLF & $sRegKeys
		MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION), "Final Adobe Clean Check  -  Registry", _
				"Adobe entries were found in the registry." & @CRLF & _
				"Please open Registry Editor (regedit), remove the following keys," & @CRLF & _
				"then click OK to continue:" & @CRLF & @CRLF & _
				$sRegKeys)
	Else
		$sReport &= "Registry:         No Adobe entries found." & @CRLF
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check  -  Registry", _
				"Registry: no Adobe entries found  -  all clear." & @CRLF & @CRLF & _
				"Click OK to continue.")
	EndIf

	GUICtrlSetData($idStepLabel, "Restoring CCX Start home to Adobe defaults...")
	_RestoreCcxStart()
	$sReport &= "CCX Start home:   restored to Adobe defaults (pinned copy removed, .orig cleared)." & @CRLF

	GUICtrlSetData($idStepLabel, "Wiping Adobe license caches (full reset)...")
	_WipeAdobeLicenseCaches()
	$sReport &= "License caches:   wiped (SLStore / SLCache / NGL / caps / OOBE - full reset)." & @CRLF

	GUICtrlSetData($idStepLabel, "Complete.")
	GUICtrlSetData($idStepBar, 100)
	Sleep(400)
	GUISetState(@SW_ENABLE, $MyhGUI)
	GUIDelete($hFCCStatus)
	LogWrite(1, "Final Clean Check completed.")
	MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Final Adobe Clean Check", $sReport)
	If $bWTNeedsRestore Then ShowRebootPopup()
EndFunc

Func _FinalCheck_RemoveBaks($sRoot)
	If Not FileExists($sRoot) Then Return 0
	Local $iCount = 0
	Local $hF = FileFindFirstFile($sRoot & "\*.bak")
	If $hF <> -1 Then
		While True
			Local $sBakName = FileFindNextFile($hF)
			If @error Then ExitLoop
			If Not StringInStr(FileGetAttrib($sRoot & "\" & $sBakName), "D") Then
				If FileDelete($sRoot & "\" & $sBakName) Then $iCount += 1
			EndIf
		WEnd
		FileClose($hF)
	EndIf
	Local $hD = FileFindFirstFile($sRoot & "\*")
	If $hD <> -1 Then
		While True
			Local $sDName = FileFindNextFile($hD)
			If @error Then ExitLoop
			Local $sDPath = $sRoot & "\" & $sDName
			If StringInStr(FileGetAttrib($sDPath), "D") Then
				$iCount += _FinalCheck_RemoveBaks($sDPath)
			EndIf
		WEnd
		FileClose($hD)
	EndIf
	Return $iCount
EndFunc

Func _UXPPatchedState($sFilePath)
	Local $sFileName = StringLower(StringRegExpReplace($sFilePath, "^.*\\", ""))
	Local $bIsPremierePath = (StringInStr($sFilePath, "Premiere Pro") > 0)
	Local $bIsJs = StringRegExp($sFileName, "(?i)\.js$")
	Local $bIsJson = StringRegExp($sFileName, "(?i)\.json$")
	If Not ($bIsJs Or $bIsJson) Then Return -1
	If $sFileName = "manifest.json" Then Return -1
	If $bIsPremierePath And $bIsJs Then Return -1

	Local $hFile = FileOpen($sFilePath, 16)
	If $hFile = -1 Then Return -1
	Local $bData = FileRead($hFile)
	FileClose($hFile)
	If BinaryLen($bData) = 0 Then Return -1
	Local $sData = BinaryToString($bData, 1)

	If $bIsJson And $bIsPremierePath Then
		If StringInStr($sData, '"version": "99.') Then Return 1
		If StringRegExp($sData, '(?i)"version"\s*:\s*"\d+\.') Then Return 0
		Return -1
	EndIf

	If $bIsJs Then
		If StringInStr($sData, "XelationshipProfile") _
				Or StringInStr($sData, "https://0.0.0.0") _
				Or StringInStr($sData, "invokeUpgradePlan(){return;") _
				Or StringInStr($sData, "get chicletData(){return null;") Then Return 1
		If StringInStr($sData, "RelationshipProfile") _
				Or StringInStr($sData, "workflow.licenses.adobe.com") _
				Or StringInStr($sData, "invokeUpgradePlan(){") _
				Or StringInStr($sData, "get chicletData(){") Then Return 0
		Return -1
	EndIf
	Return -1
EndFunc

Func _VerifyListedFiles($bSilent = False)
	Local $iCount = _GUICtrlListView_GetItemCount($idListview)
	If $iCount = 0 Then
		If Not $bSilent Then MemoWrite(@CRLF & "Nothing to verify.")
		Return
	EndIf

	If Not $bSilent Then
		ToggleLog(0)
		MemoWrite(@CRLF & "Verifying " & $iCount & " file(s) against patch_states.ini...")
	EndIf
	LogWrite(1, "Verify pass starting on " & $iCount & " file(s).")

	Local $mPatched = ObjCreate("Scripting.Dictionary")
	Local $mOriginal = ObjCreate("Scripting.Dictionary")
	Local $aSecP = IniReadSection($patchStatesINI, "MD5_Patched")
	Local $aSecO = IniReadSection($patchStatesINI, "MD5_Original")
	If IsArray($aSecP) Then
		For $k = 1 To $aSecP[0][0]
			$mPatched.Item(StringLower($aSecP[$k][0])) = StringLower($aSecP[$k][1])
		Next
	EndIf
	If IsArray($aSecO) Then
		For $k = 1 To $aSecO[0][0]
			$mOriginal.Item(StringLower($aSecO[$k][0])) = StringLower($aSecO[$k][1])
		Next
	EndIf

	Local $bWeStartedCrypt = False
	If Not $g_bCryptActive Then
		_Crypt_Startup()
		$g_bCryptActive = True
		$bWeStartedCrypt = True
	EndIf
	ProgressWrite(0)
	_SubProgressWrite(0)

	Local $iDone = 0, $iPatched = 0, $iUnpatched = 0, $iModified = 0, $iUnknown = 0, $iMissing = 0

	For $i = 0 To $iCount - 1
		Local $sPath = _GUICtrlListView_GetItemText($idListview, $i, 1)
		Local $sDisplayStatus = "Unpatched"

		If Not FileExists($sPath) Then
			$iMissing += 1
		Else
			Local $iUxp = _UXPPatchedState($sPath)
			If $iUxp = 1 Then
				$sDisplayStatus = "Patched"
				$iPatched += 1
			ElseIf $iUxp = 0 Then
				$sDisplayStatus = "Unpatched"
				$iUnpatched += 1
			Else
				If Not $bSilent Then _GUICtrlListView_SetItemText($idListview, $i, "Verifying...", 2)
				_SubProgressWrite(50)
				Local $sMD5 = StringLower(StringTrimLeft(String(_Crypt_HashFile($sPath, $CALG_MD5)), 2))
				Local $sKey = StringLower($sPath)

				If $mPatched.Exists($sKey) And $mPatched.Item($sKey) = $sMD5 Then
					$sDisplayStatus = "Patched"
					$iPatched += 1
				ElseIf $mOriginal.Exists($sKey) And $mOriginal.Item($sKey) = $sMD5 Then
					$sDisplayStatus = "Unpatched"
					$iUnpatched += 1
				ElseIf $mPatched.Exists($sKey) Or $mOriginal.Exists($sKey) Then
					$iModified += 1
				Else
					$iUnknown += 1
				EndIf
			EndIf
		EndIf

		_GUICtrlListView_SetItemText($idListview, $i, $sDisplayStatus, 2)
		$iDone += 1
		ProgressWrite(Round($iDone / $iCount * 100))
		_SubProgressWrite(100)
	Next

	If $bWeStartedCrypt Then
		_Crypt_Shutdown()
		$g_bCryptActive = False
	EndIf

	ProgressWrite(0)
	_SubProgressWrite(0)

	Local $iUnpatchedSum = $iUnpatched + $iModified
	Local $sSummary = "Verify complete: " & $iPatched & " Patched, " & $iUnpatchedSum & " Unpatched, " & _
			$iUnknown & " Unknown, " & $iMissing & " Missing."
	If Not $bSilent Then MemoWrite(@CRLF & $sSummary)
	LogWrite(1, $sSummary)
	If Not $bSilent Then ToggleLog(1)
EndFunc

Func MyGlobalPatternSearch($MyFileToParse)
	$aInHexArray = $aNullArray
	$aOutHexGlobalArray = $aNullArray
	ReDim $g_aHitPatternsThisFile[0]
	$g_bUxpHandledFile = False
	_SubProgressWrite(0)
	$MyRegExpGlobalPatternSearchCount = 0
	$Count = 15
	Local $sFileName = StringRegExpReplace($MyFileToParse, "^.*\\", "")
	If StringLower($sFileName) = "lightroom.exe" Then
		If StringInStr($MyFileToParse, "Lightroom Classic") Then
			$sFileName = "lightroom_classic.exe"
		ElseIf StringInStr($MyFileToParse, "Lightroom CC") Then
			$sFileName = "lightroom_cc.exe"
		EndIf
	EndIf

	Local $sLowerPathToVerify = StringLower($MyFileToParse)
	Local $sLowerBaseName = StringLower($sFileName)

	If StringInStr($sLowerPathToVerify, "adobe premiere pro") > 0 Then
		If $sLowerBaseName = "lec.dll" Or $sLowerBaseName = "dynamic-torqnative.dll" Or StringRight($sLowerBaseName, 3) = ".js" Or (StringRight($sLowerBaseName, 5) = ".json" And $sLowerBaseName <> "manifest.json") Then
			$g_bUxpHandledFile = True
			Return
		EndIf
	Else
		If $sLowerBaseName = "manifest.json" Then
			$g_bUxpHandledFile = True
			Return
		EndIf
	EndIf

	Local $sExt = StringRegExpReplace($sFileName, "^.*\.", "")
	Local $sLogSuffix = " - using Default/Custom Patterns"
	MemoWrite(@CRLF & $MyFileToParse & @CRLF & "---" & @CRLF & "Preparing to Analyze" & @CRLF & "---" & @CRLF & "*****")
	LogWrite(1, "Checking File: " & $sFileName & $sLogSuffix)
	If StringLower($sFileName) = "runtimeinstaller.dll" Then
		If Not _AutoUnpackIfRuntimeInstaller($MyFileToParse) Then
			MemoWrite(@CRLF & $MyFileToParse & @CRLF & "---" & @CRLF & "Auto-unpack failed, skipping file." & @CRLF)
			Return
		EndIf
	EndIf
	If StringRegExp(StringLower($sExt), "^(js|json)$") Then
		Local $iUxpResult = _PatchAdobeUXPComponent($MyFileToParse)
		If $iUxpResult = 1 Then
			LogWrite(1, $MyFileToParse)
			LogWrite(1, "File patched by GenP " & $g_Version & " + config " & $ConfigVerVar)
			If $bEnableMD5 = 1 And $g_bCryptActive Then
				Local $sUxpMD5 = StringTrimLeft(String(_Crypt_HashFile($MyFileToParse, $CALG_MD5)), 2)
				LogWrite(1, "MD5 Checksum: " & $sUxpMD5 & @CRLF)
			EndIf
			$g_bUxpHandledFile = True
			Return
		ElseIf $iUxpResult = 2 Then
			LogWrite(1, $MyFileToParse)
			LogWrite(1, "File already patched by GenP" & @CRLF)
			$g_bUxpHandledFile = True
			Return
		EndIf
	EndIf
	If $sExt = "exe" Then
		_ProcessCloseEx("""" & $sFileName & """")
	EndIf
	If $sFileName = "Adobe Desktop Service.exe" Then
		_ProcessCloseEx("""Creative Cloud.exe""")
		Sleep(100)
	EndIf
	If $sFileName = "AppsPanelBL.dll" Then
		_ProcessCloseEx("""Creative Cloud.exe""")
		_ProcessCloseEx("""Adobe Desktop Service.exe""")
		Sleep(100)
	EndIf
	If $sFileName = "AppsPanelIL.dll" Then
		_ProcessCloseEx("""Creative Cloud.exe""")
		_ProcessCloseEx("""Adobe Desktop Service.exe""")
		Sleep(100)
	EndIf
	If $sFileName = "HDPIM.dll" Then
		_ProcessCloseEx("""Creative Cloud.exe""")
		_ProcessCloseEx("""Adobe Desktop Service.exe""")
		Sleep(100)
	EndIf
	If StringInStr($sSpecialFiles, $sFileName) Then
		ExecuteSearchPatterns($sFileName, 0, $MyFileToParse)
	Else
		ExecuteSearchPatterns($sFileName, 1, $MyFileToParse)
	EndIf
	Sleep(100)
EndFunc

Func ExecuteSearchPatterns($FileName, $DefaultPatterns, $MyFileToParse)

	Local $aPatterns, $sPattern, $sData, $aArray, $sSearch, $sReplace, $iPatternLength

	If $DefaultPatterns = 0 Then
		Local $sRelPathE = StringMid($MyFileToParse, StringLen($MyDefPath) + 2)
		Local $sPathKeyE = $FileName & "|" & $sRelPathE
		$aPatterns = IniReadArray($sINIPath, "CustomPatterns", $sPathKeyE, "")
		If $aPatterns[0] = "" Then
			Local $sPFRelE = StringRegExpReplace($MyFileToParse, "(?i)^[A-Z]:\\Program Files( \(x86\))?\\", "")
			If $sPFRelE <> $MyFileToParse Then
				$aPatterns = IniReadArray($sINIPath, "CustomPatterns", $FileName & "|" & $sPFRelE, "")
			EndIf
		EndIf
		If $aPatterns[0] = "" Then
			$aPatterns = IniReadArray($sINIPath, "CustomPatterns", $FileName, "")
		EndIf
	Else
		$aPatterns = IniReadArray($sINIPath, "DefaultPatterns", "Values", "")
	EndIf

	For $i = 0 To UBound($aPatterns) - 1
		$sPattern = StringStripWS($aPatterns[$i], 3)
		If $bEnableGood1 = 0 And StringLower($sPattern) = "good1" Then
			ContinueLoop
		EndIf
		$sData = IniRead($sINIPath, "Patches", $sPattern, "")
		If StringInStr($sData, "|") Then
			$aArray = StringSplit($sData, "|")
			If UBound($aArray) = 3 Then

				$sSearch = StringReplace($aArray[1], '"', '')
				$sReplace = StringReplace($aArray[2], '"', '')

				$iPatternLength = StringLen($sSearch)
				If $iPatternLength <> StringLen($sReplace) Or Mod($iPatternLength, 2) <> 0 Then
					MsgBox($MB_SYSTEMMODAL, "Error", "Pattern Error in config.ini:" & $sPattern & @CRLF & $sSearch & @CRLF & $sReplace)
					Exit
				EndIf

				MyRegExpGlobalPatternSearch($MyFileToParse, $sSearch, $sReplace, $sPattern)

			EndIf
		EndIf
	Next
EndFunc

Func MyRegExpGlobalPatternSearch($FileToParse, $PatternToSearch, $PatternToReplace, $PatternName)
	Local $hFileOpen = FileOpen($FileToParse, $FO_READ + $FO_BINARY)

	Local $sExtLower = StringLower(StringRegExpReplace($FileToParse, "^.*\.", ""))
	Local $bSkipPECheck = ($sExtLower = "js" Or $sExtLower = "json" Or $sExtLower = "rpln")

	If Not $bSkipPECheck Then
		FileSetPos($hFileOpen, 60, 0)

		$sz_type = FileRead($hFileOpen, 4)
		FileSetPos($hFileOpen, Number($sz_type) + 4, 0)

		$sz_type = FileRead($hFileOpen, 2)
	Else
		$sz_type = "0x0000"
	EndIf

	If $sz_type = "0x4C01" And StringInStr($FileToParse, "Acrobat", 2) > 0 Then

		MemoWrite(@CRLF & $FileToParse & @CRLF & "---" & @CRLF & "File is 32-bit. Aborting..." & @CRLF & "---")
		FileClose($hFileOpen)
		Sleep(100)
		$bFoundAcro32 = True

	ElseIf $sz_type = "0x64AA" Then
		MemoWrite(@CRLF & $FileToParse & @CRLF & "---" & @CRLF & "File is ARM. Aborting..." & @CRLF & "---")
		FileClose($hFileOpen)
		Sleep(100)
		$bFoundGenericARM = True

	Else

		FileSetPos($hFileOpen, 0, 0)

		Local $sFileRead = FileRead($hFileOpen)

		Local $GeneQuestionMark, $AnyNumOfBytes, $OutStringForRegExp
		For $i = 256 To 1 Step -2
			$GeneQuestionMark = _StringRepeat("??", $i / 2)
			$AnyNumOfBytes = "(.{" & $i & "})"
			$OutStringForRegExp = StringReplace($PatternToSearch, $GeneQuestionMark, $AnyNumOfBytes)
			$PatternToSearch = $OutStringForRegExp
		Next

		Local $sSearchPattern = $OutStringForRegExp
		Local $aReplacePattern = $PatternToReplace
		Local $sWildcardSearchPattern = "", $sWildcardReplacePattern = "", $sFinalReplacePattern = ""
		Local $aInHexTempArray[0]
		Local $sSearchCharacter = "", $sReplaceCharacter = ""

		$aInHexTempArray = $aNullArray
		$aInHexTempArray = StringRegExp($sFileRead, $sSearchPattern, $STR_REGEXPARRAYGLOBALFULLMATCH, 1)
		For $i = 0 To UBound($aInHexTempArray) - 1

			$aInHexArray = $aNullArray
			$sSearchCharacter = ""
			$sReplaceCharacter = ""
			$sWildcardSearchPattern = ""
			$sWildcardReplacePattern = ""
			$sFinalReplacePattern = ""


			$aInHexArray = $aInHexTempArray[$i]

			If @error = 0 Then
				$sWildcardSearchPattern = $aInHexArray[0]
				$sWildcardReplacePattern = $aReplacePattern

				If StringInStr($sWildcardReplacePattern, "?") Then
					For $j = 1 To StringLen($sWildcardReplacePattern) + 1
						$sSearchCharacter = StringMid($sWildcardSearchPattern, $j, 1)
						$sReplaceCharacter = StringMid($sWildcardReplacePattern, $j, 1)

						If $sReplaceCharacter <> "?" Then
							$sFinalReplacePattern &= $sReplaceCharacter
						Else
							$sFinalReplacePattern &= $sSearchCharacter
						EndIf

					Next
				Else
					$sFinalReplacePattern = $sWildcardReplacePattern
				EndIf

				_ArrayAdd($aOutHexGlobalArray, $sWildcardSearchPattern)
				_ArrayAdd($aOutHexGlobalArray, $sFinalReplacePattern)

				ConsoleWrite($PatternName & "---" & @TAB & $sWildcardSearchPattern & "	" & @CRLF)
				ConsoleWrite($PatternName & "R" & "-" & @TAB & $sFinalReplacePattern & "	" & @CRLF)
				MemoWrite(@CRLF & $FileToParse & @CRLF & "---" & @CRLF & $PatternName & @CRLF & "---" & @CRLF & $sWildcardSearchPattern & @CRLF & $sFinalReplacePattern)

				If _ArraySearch($g_aHitPatternsThisFile, $PatternName) = -1 Then
					_ArrayAdd($g_aHitPatternsThisFile, $PatternName)
				EndIf

			Else
				ConsoleWrite($PatternName & "---" & @TAB & "No" & "	" & @CRLF)
				MemoWrite(@CRLF & $FileToParse & @CRLF & "---" & @CRLF & $PatternName & "---" & "No")
			EndIf
			$MyRegExpGlobalPatternSearchCount += 1

		Next
		FileClose($hFileOpen)
		$sFileRead = ""
		_SubProgressWrite(Round($MyRegExpGlobalPatternSearchCount / $Count * 50))
		Sleep(100)

	EndIf

EndFunc

Func MyGlobalPatternPatch($MyFileToPatch, $MyArrayToPatch)
	_SubProgressWrite(50)
	Local $iRows = UBound($MyArrayToPatch)
	If $iRows > 0 Then
		MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyFileToPatch & @CRLF & "---" & @CRLF & "medication :)")
		Local $iPrePatchSize = FileGetSize($MyFileToPatch)
		Local $hFileOpen = FileOpen($MyFileToPatch, $FO_READ + $FO_BINARY)
		Local $sFileRead = FileRead($hFileOpen)
		Local $sStringOut = $sFileRead

		Local $sMD5Orig = ""
		If $bEnableMD5 = 1 And $g_bCryptActive Then
			$sMD5Orig = StringTrimLeft(String(_Crypt_HashData($sFileRead, $CALG_MD5)), 2)
		EndIf

		For $i = 0 To $iRows - 1 Step 2
			$sStringOut = StringReplace($sFileRead, $MyArrayToPatch[$i], $MyArrayToPatch[$i + 1], 0, 1)
			$sFileRead = $sStringOut
			_SubProgressWrite(50 + Round(($i + 2) / $iRows * 50))
		Next

		FileClose($hFileOpen)

		Local $sBak = $MyFileToPatch & ".bak"
		If FileExists($sBak) Then
			Local $sBakMD5 = ""
			If $bEnableMD5 = 1 And $g_bCryptActive Then
				$sBakMD5 = StringTrimLeft(String(_Crypt_HashFile($sBak, $CALG_MD5)), 2)
			EndIf
			If $sBakMD5 <> "" And $sBakMD5 <> $sMD5Orig Then
				If Not FileMove($MyFileToPatch, $sBak, $FC_OVERWRITE) Then
					LogWrite(1, $MyFileToPatch)
					LogWrite(1, "Patch ABORTED - could not refresh .bak (file in use?). File left unpatched.")
					MemoWrite(@CRLF & "Patch ABORTED - backup could not be created" & @CRLF & "---" & @CRLF & $MyFileToPatch)
					Return
				EndIf
				FileSetTime($sBak, "", $FT_MODIFIED)
			Else
				FileDelete($MyFileToPatch)
			EndIf
		Else
			If Not FileMove($MyFileToPatch, $sBak) Then
				LogWrite(1, $MyFileToPatch)
				LogWrite(1, "Patch ABORTED - could not create .bak (file in use?). File left unpatched.")
				MemoWrite(@CRLF & "Patch ABORTED - backup could not be created" & @CRLF & "---" & @CRLF & $MyFileToPatch)
				Return
			EndIf
			FileSetTime($sBak, "", $FT_MODIFIED)
		EndIf

		If Not FileExists($sBak) Then
			LogWrite(1, $MyFileToPatch)
			LogWrite(1, "Patch ABORTED - backup missing after creation step. File left unpatched.")
			MemoWrite(@CRLF & "Patch ABORTED - backup missing" & @CRLF & "---" & @CRLF & $MyFileToPatch)
			Return
		EndIf

		Local $hFileOpen1 = FileOpen($MyFileToPatch, $FO_OVERWRITE + $FO_BINARY)
		Local $bPatchedData = Binary($sStringOut)
		FileWrite($hFileOpen1, $bPatchedData)
		FileClose($hFileOpen1)
		_SubProgressWrite(100)
		Sleep(100)

		If UBound($g_aHitPatternsThisFile) > 0 Then
		EndIf
		LogWrite(1, "File patched by GenP " & $g_Version & " + config " & $ConfigVerVar)

		_GetSystemNativeProcessorArchitecture($MyFileToPatch)

		Local $sMD5Patched = ""
		If $bEnableMD5 = 1 And $g_bCryptActive Then
			$sMD5Patched = StringTrimLeft(String(_Crypt_HashFile($MyFileToPatch, $CALG_MD5)), 2)
			LogWrite(1, "MD5 Checksum: " & $sMD5Patched & @CRLF)
		EndIf

		_QueueStateWrite($MyFileToPatch, _GetAppGroupName($MyFileToPatch), $sMD5Orig, $sMD5Patched, "Patched")

	Else
		If Not $g_bUxpHandledFile Then
			MemoWrite(@CRLF & "No patterns were found" & @CRLF & "---" & @CRLF & "or" & @CRLF & "---" & @CRLF & "file is already patched.")
			Sleep(100)
			LogWrite(1, "No patterns were found or file already patched." & @CRLF)

			Local $sBakCheck = $MyFileToPatch & ".bak"
			If $bEnableMD5 = 1 And $g_bCryptActive And FileExists($sBakCheck) Then
				Local $sBakMD5Now = StringTrimLeft(String(_Crypt_HashFile($sBakCheck, $CALG_MD5)), 2)
				Local $sLiveMD5Now = StringTrimLeft(String(_Crypt_HashFile($MyFileToPatch, $CALG_MD5)), 2)
				If $sBakMD5Now <> "" And $sLiveMD5Now <> "" And $sBakMD5Now <> $sLiveMD5Now Then
					_QueueStateWrite($MyFileToPatch, _GetAppGroupName($MyFileToPatch), $sBakMD5Now, $sLiveMD5Now, "Patched")
				EndIf
			EndIf
		EndIf
	EndIf
EndFunc

Func _PatchLargeFileWithPatterns($sFilePath)
	Local $LFP_CHUNK = 50 * 1024 * 1024
	Local $LFP_OVERLAP = 256

	Local $sFileName = StringRegExpReplace($sFilePath, "^.*\\", "")

	Local $sLowerPathToVerify = StringLower($sFilePath)
	Local $sLowerBaseName = StringLower($sFileName)

	If StringInStr($sLowerPathToVerify, "adobe premiere pro") > 0 Then
		If $sLowerBaseName = "lec.dll" Or $sLowerBaseName = "dynamic-torqnative.dll" Or StringRight($sLowerBaseName, 3) = ".js" Or (StringRight($sLowerBaseName, 5) = ".json" And $sLowerBaseName <> "manifest.json") Then
			Return 0
		EndIf
	Else
		If $sLowerBaseName = "manifest.json" Then
			Return 0
		EndIf
	EndIf

	LogWrite(1, "Checking File: " & $sFileName & " - using Default/Custom Patterns")
	MemoWrite(@CRLF & $sFilePath & @CRLF & "---" & @CRLF & "Preparing to Analyze" & @CRLF & "---" & @CRLF & "*****")

	Local $sExtLC = StringLower(StringRegExpReplace($sFileName, "^.*\.", ""))
	If $sExtLC = "exe" Then _ProcessCloseEx('"' & $sFileName & '"')

	Local $aPatNames
	If StringInStr($sSpecialFiles, $sFileName) Then
		Local $sRelPath = StringMid($sFilePath, StringLen($MyDefPath) + 2)
		Local $sPathKey = $sFileName & "|" & $sRelPath
		$aPatNames = IniReadArray($sINIPath, "CustomPatterns", $sPathKey, "")
		If $aPatNames[0] = "" Then
			Local $sPFRel = StringRegExpReplace($sFilePath, "(?i)^[A-Z]:\\Program Files( \(x86\))?\\", "")
			If $sPFRel <> $sFilePath Then
				$aPatNames = IniReadArray($sINIPath, "CustomPatterns", $sFileName & "|" & $sPFRel, "")
			EndIf
		EndIf
		If $aPatNames[0] = "" Then
			$aPatNames = IniReadArray($sINIPath, "CustomPatterns", $sFileName, "")
		EndIf
	Else
		$aPatNames = IniReadArray($sINIPath, "DefaultPatterns", "Values", "")
	EndIf

	Local $aPats[0][3]
	Local $aRegex[0]
	For $i = 0 To UBound($aPatNames) - 1
		Local $sName = StringStripWS($aPatNames[$i], 3)
		If $sName = "" Then ContinueLoop
		Local $sData = IniRead($sINIPath, "Patches", $sName, "")
		If Not StringInStr($sData, "|") Then ContinueLoop
		Local $aSplit = StringSplit($sData, "|")
		If UBound($aSplit) <> 3 Then ContinueLoop
		Local $sSearch = StringReplace($aSplit[1], '"', '')
		Local $sReplace = StringReplace($aSplit[2], '"', '')
		If StringLen($sSearch) <> StringLen($sReplace) Or Mod(StringLen($sSearch), 2) <> 0 Then
			MsgBox($MB_SYSTEMMODAL, "Error", "Large-file pattern length mismatch: " & $sName & @CRLF & $sSearch & @CRLF & $sReplace)
			Return -1
		EndIf
		Local $iN = UBound($aPats)
		ReDim $aPats[$iN + 1][3]
		$aPats[$iN][0] = $sName
		$aPats[$iN][1] = $sSearch
		$aPats[$iN][2] = $sReplace
		Local $sRgx = $sSearch
		For $iLen = 256 To 2 Step -2
			$sRgx = StringReplace($sRgx, _StringRepeat("??", $iLen / 2), "(.{" & $iLen & "})")
		Next
		ReDim $aRegex[$iN + 1]
		$aRegex[$iN] = $sRgx
	Next

	If UBound($aPats) = 0 Then
		LogWrite(1, "No patterns resolved for this file - skipping.")
		Return 0
	EndIf

	Local $sBak = $sFilePath & ".bak"
	If FileExists($sBak) Then
		If FileGetSize($sBak) <> FileGetSize($sFilePath) Then
			FileDelete($sBak)
			If Not FileMove($sFilePath, $sBak) Then
				LogWrite(1, "Failed to refresh .bak after size mismatch.")
				Return -1
			EndIf
		EndIf
	Else
		If Not FileMove($sFilePath, $sBak) Then
			LogWrite(1, "Failed to create .bak (file in use?).")
			Return -1
		EndIf
	EndIf

	Local $iFileSize = FileGetSize($sBak)
	If $iFileSize <= 0 Then
		LogWrite(1, ".bak has zero size - aborting.")
		Return -1
	EndIf

	Local $hSrc = FileOpen($sBak, $FO_READ + $FO_BINARY)
	If $hSrc = -1 Then
		LogWrite(1, "Failed to open .bak for scanning.")
		FileCopy($sBak, $sFilePath, 1)
		Return -1
	EndIf

	Local $aReps[0][2]
	Local $aHitCounts[UBound($aPats)]
	For $i = 0 To UBound($aHitCounts) - 1
		$aHitCounts[$i] = 0
	Next

	Local $iSrcPos = 0
	Local $iLastPct = -1

	While $iSrcPos < $iFileSize
		FileSetPos($hSrc, $iSrcPos, 0)
		Local $bChunk = FileRead($hSrc, $LFP_CHUNK + $LFP_OVERLAP)
		Local $iChunkBytes = BinaryLen($bChunk)
		If $iChunkBytes = 0 Then ExitLoop

		Local $sHex = Hex($bChunk)
		Local $bIsLastChunk = ($iSrcPos + $iChunkBytes >= $iFileSize)
		Local $iCutoff = $LFP_CHUNK
		If $bIsLastChunk Then $iCutoff = $iChunkBytes

		For $iP = 0 To UBound($aPats) - 1
			Local $sRgx = $aRegex[$iP]
			Local $sReplaceTpl = $aPats[$iP][2]
			Local $iCharOff = 1
			While 1
				Local $aMatch = StringRegExp($sHex, $sRgx, 2, $iCharOff)
				If @error Then ExitLoop
				Local $iMatchEnd = @extended
				Local $sFullHit = $aMatch[0]
				Local $iLenHit = StringLen($sFullHit)
				Local $iMatchStart = $iMatchEnd - $iLenHit
				Local $iByteOffsetInChunk = ($iMatchStart - 1) / 2

				If $iByteOffsetInChunk >= $iCutoff Then
					$iCharOff = $iMatchEnd
					ContinueLoop
				EndIf

				Local $sFinalRep = $sReplaceTpl
				If StringInStr($sReplaceTpl, "?") Then
					$sFinalRep = ""
					For $j = 1 To StringLen($sReplaceTpl)
						Local $cR = StringMid($sReplaceTpl, $j, 1)
						If $cR = "?" Then
							$sFinalRep &= StringMid($sFullHit, $j, 1)
						Else
							$sFinalRep &= $cR
						EndIf
					Next
				EndIf

				Local $iAbsOff = $iSrcPos + $iByteOffsetInChunk
				Local $iN = UBound($aReps)
				ReDim $aReps[$iN + 1][2]
				$aReps[$iN][0] = $iAbsOff
				$aReps[$iN][1] = Binary("0x" & $sFinalRep)
				$aHitCounts[$iP] += 1

				$iCharOff = $iMatchEnd
			WEnd
		Next

		If $bIsLastChunk Then ExitLoop
		$iSrcPos += $LFP_CHUNK

		Local $iPct = Int(($iSrcPos / $iFileSize) * 50)
		If $iPct <> $iLastPct Then
			_SubProgressWrite($iPct)
			$iLastPct = $iPct
		EndIf
	WEnd
	FileClose($hSrc)

	Local $iTotal = UBound($aReps)
	For $i = 0 To UBound($aPats) - 1
		If $aHitCounts[$i] > 0 Then
			MemoWrite(@CRLF & $aPats[$i][0] & " - " & $aHitCounts[$i] & " hit(s)")
		EndIf
	Next

	If $iTotal = 0 Then
		LogWrite(1, "No patterns were found or file already patched." & @CRLF)
		FileCopy($sBak, $sFilePath, 1)
		Return 0
	EndIf

	$hSrc = FileOpen($sBak, $FO_READ + $FO_BINARY)
	Local $hDst = FileOpen($sFilePath, $FO_OVERWRITE + $FO_BINARY)
	If $hSrc = -1 Or $hDst = -1 Then
		If $hSrc <> -1 Then FileClose($hSrc)
		If $hDst <> -1 Then FileClose($hDst)
		LogWrite(1, "Failed to open files for write phase. Restoring from .bak.")
		FileCopy($sBak, $sFilePath, 1)
		Return -1
	EndIf

	Local $iWritePos = 0
	Local $iRepIdx = 0
	$iLastPct = -1

	While $iWritePos < $iFileSize
		Local $iThisRead = $LFP_CHUNK
		Local $iScan = $iRepIdx
		While $iScan < UBound($aReps) And $aReps[$iScan][0] < $iWritePos + $iThisRead
			Local $iRepEnd = $aReps[$iScan][0] + BinaryLen($aReps[$iScan][1])
			If $iRepEnd > $iWritePos + $iThisRead Then $iThisRead = $iRepEnd - $iWritePos
			$iScan += 1
		WEnd

		Local $bChunk = FileRead($hSrc, $iThisRead)
		Local $iActual = BinaryLen($bChunk)
		If $iActual = 0 Then ExitLoop

		While $iRepIdx < UBound($aReps) And $aReps[$iRepIdx][0] < $iWritePos + $iActual
			Local $iLocal = $aReps[$iRepIdx][0] - $iWritePos
			Local $bRep = $aReps[$iRepIdx][1]
			Local $iRepLen = BinaryLen($bRep)

			Local $bBefore = Binary("")
			If $iLocal > 0 Then $bBefore = BinaryMid($bChunk, 1, $iLocal)
			Local $bAfter = BinaryMid($bChunk, $iLocal + $iRepLen + 1)
			$bChunk = $bBefore & $bRep & $bAfter
			$iRepIdx += 1
		WEnd

		FileWrite($hDst, $bChunk)
		$iWritePos += $iActual

		Local $iPct = 50 + Int(($iWritePos / $iFileSize) * 50)
		If $iPct <> $iLastPct Then
			_SubProgressWrite($iPct)
			$iLastPct = $iPct
		EndIf
	WEnd
	FileClose($hSrc)
	FileClose($hDst)

	LogWrite(1, $sFilePath)
	Local $sHitNames = ""
	For $i = 0 To UBound($aPats) - 1
		If $aHitCounts[$i] > 0 Then
			If $sHitNames <> "" Then $sHitNames &= ", "
			$sHitNames &= $aPats[$i][0]
		EndIf
	Next
	If $sHitNames <> "" Then
	EndIf
	LogWrite(1, "File patched by GenP " & $g_Version & " + config " & $ConfigVerVar)

	Local $sMD5Orig = ""
	Local $sMD5Patched = ""
	If $bEnableMD5 = 1 And $g_bCryptActive Then
		$sMD5Orig = StringTrimLeft(String(_Crypt_HashFile($sBak, $CALG_MD5)), 2)
		$sMD5Patched = StringTrimLeft(String(_Crypt_HashFile($sFilePath, $CALG_MD5)), 2)
		LogWrite(1, "MD5 Checksum: " & $sMD5Patched & @CRLF)
	EndIf

	_QueueStateWrite($sFilePath, _GetAppGroupName($sFilePath), $sMD5Orig, $sMD5Patched, "Patched")
	Return $iTotal
EndFunc

Func RestoreFile($MyFileToDelete)
	If FileExists($MyFileToDelete & ".bak") Then
		_VerifyBackupAgainstLedger($MyFileToDelete, $MyFileToDelete & ".bak")
		Local $sFileName = StringRegExpReplace($MyFileToDelete, "^.*\\", "")
		If StringLower($sFileName) = "appspanelbl.dll" Or StringLower($sFileName) = "adobe desktop service.exe" Then
			_ProcessCloseEx("""Creative Cloud.exe""")
			_ProcessCloseEx("""Adobe Desktop Service.exe""")
			Sleep(100)
		EndIf
		If Not FileMove($MyFileToDelete & ".bak", $MyFileToDelete, $FC_OVERWRITE) Then
			LogWrite(1, $MyFileToDelete)
			LogWrite(1, "Restore FAILED - could not move .bak over target (file in use?). Backup preserved.")
			MemoWrite(@CRLF & "Restore FAILED - backup preserved" & @CRLF & "---" & @CRLF & $MyFileToDelete)
			Return -1
		EndIf
		Sleep(100)
		MemoWrite(@CRLF & "File restored" & @CRLF & "---" & @CRLF & $MyFileToDelete)
		LogWrite(1, $MyFileToDelete)
		LogWrite(1, "File restored.")

		Local $sMD5 = ""
		If $bEnableMD5 = 1 And $g_bCryptActive Then
			$sMD5 = StringTrimLeft(String(_Crypt_HashFile($MyFileToDelete, $CALG_MD5)), 2)
		EndIf
		_QueueStateWrite($MyFileToDelete, _GetAppGroupName($MyFileToDelete), $sMD5, "", "Unpatched")
		Return True
	Else
		Sleep(100)
		MemoWrite(@CRLF & "No backup file found" & @CRLF & "---" & @CRLF & $MyFileToDelete)
		LogWrite(1, $MyFileToDelete)
		LogWrite(1, "No backup file found.")
		Return False
	EndIf
EndFunc

Func _QueueStateWrite($sPath, $sApp, $sMD5Orig, $sMD5Patched, $sStatus)
	Local $iIdx = UBound($g_aStateQueue)
	ReDim $g_aStateQueue[$iIdx + 1][5]
	$g_aStateQueue[$iIdx][0] = $sPath
	$g_aStateQueue[$iIdx][1] = $sApp
	$g_aStateQueue[$iIdx][2] = $sMD5Orig
	$g_aStateQueue[$iIdx][3] = $sMD5Patched
	$g_aStateQueue[$iIdx][4] = $sStatus

	If $sApp <> "" And $sStatus = "Patched" Then
		If Not $g_mAppPrimaryExe.Exists($sApp) Then
			If StringRight(StringLower($sPath), 4) = ".exe" Then
				$g_mAppPrimaryExe.Item($sApp) = $sPath
			EndIf
		Else
			If StringRight(StringLower($sPath), 4) = ".exe" Then
				Local $sCurrentExe = StringLower(StringRegExpReplace($g_mAppPrimaryExe.Item($sApp), "^.*\\", ""))
				Local $sNewExe = StringLower(StringRegExpReplace($sPath, "^.*\\", ""))
				If StringInStr(StringLower($sApp), StringTrimRight($sNewExe, 4)) And _
						Not StringInStr(StringLower($sApp), StringTrimRight($sCurrentExe, 4)) Then
					$g_mAppPrimaryExe.Item($sApp) = $sPath
				EndIf
			EndIf
		EndIf

		If Not $g_mWinTrustQueue.Exists($sApp) Then
			Local $sFolder = StringRegExpReplace($sPath, "\\[^\\]+$", "")
			If FileExists($sFolder & "\wintrust.dll") Then
				$g_mWinTrustQueue.Item($sApp) = "1"
			Else
				$g_mWinTrustQueue.Item($sApp) = "0"
			EndIf
		ElseIf $g_mWinTrustQueue.Item($sApp) = "0" Then
			Local $sFolder = StringRegExpReplace($sPath, "\\[^\\]+$", "")
			If FileExists($sFolder & "\wintrust.dll") Then
				$g_mWinTrustQueue.Item($sApp) = "1"
			EndIf
		EndIf
	EndIf
EndFunc

Func _VerifyBackupAgainstLedger($sLivePath, $sBakPath)
	If Not $g_bCryptActive Then Return -1
	If Not FileExists($sBakPath) Then Return -1
	Local $sRecordedMD5 = IniRead($patchStatesINI, "MD5_Original", $sLivePath, "")
	If $sRecordedMD5 = "" Then Return -1
	Local $sBakMD5 = StringTrimLeft(String(_Crypt_HashFile($sBakPath, $CALG_MD5)), 2)
	If $sBakMD5 = $sRecordedMD5 Then Return 1
	LogWrite(1, ".bak MD5 mismatch vs ledger for: " & $sLivePath)
	LogWrite(1, "    recorded original MD5: " & $sRecordedMD5)
	LogWrite(1, "    actual   .bak     MD5: " & $sBakMD5)
	If $bEnableMD5 = 1 And $g_bCryptActive Then
		LogWrite(1, "MD5 Checksum: " & $sBakMD5 & @CRLF)
	EndIf
	Return 0
EndFunc

Func _RestoreManifestJsonIfBackupExists($sFilePath)
	Local $sBak = $sFilePath & ".bak"
	If Not FileExists($sBak) Then Return 0

	Local $sFileName = StringRegExpReplace($sFilePath, "^.*\\", "")

	_VerifyBackupAgainstLedger($sFilePath, $sBak)

	If FileExists($sFilePath) Then
		FileSetAttrib($sFilePath, "-RHS")
		FileDelete($sFilePath)
	EndIf

	If Not FileMove($sBak, $sFilePath, $FC_OVERWRITE) Then
		LogWrite(1, "manifest.json restore FAILED (file in use?): " & $sFilePath)
		Return -1
	EndIf

	Local $sMD5 = ""
	If $g_bCryptActive Then
		$sMD5 = StringTrimLeft(String(_Crypt_HashFile($sFilePath, $CALG_MD5)), 2)
	EndIf
	_QueueStateWrite($sFilePath, "", $sMD5, "", "Unpatched")
	LogWrite(1, "manifest.json restored: " & $sFileName)
	Return 3
EndFunc

Func _FlushStateQueue()
	Local $iN = UBound($g_aStateQueue)
	If $iN = 0 And $g_mAppPrimaryExe.Count = 0 Then Return

	Local $aSecStatus = IniReadSection($patchStatesINI, "Patch_Status")
	Local $aSecOrig = IniReadSection($patchStatesINI, "MD5_Original")
	Local $aSecPatch = IniReadSection($patchStatesINI, "MD5_Patched")
	Local $aSecAppFiles = IniReadSection($patchStatesINI, "App_File")
	Local $aSecAppVer = IniReadSection($patchStatesINI, "App_Version")
	Local $aSecWinTrust = IniReadSection($patchStatesINI, "WinTrust_Local")

	Local $mStatus = ObjCreate("Scripting.Dictionary")
	Local $mOrig = ObjCreate("Scripting.Dictionary")
	Local $mPatch = ObjCreate("Scripting.Dictionary")
	Local $mAppFiles = ObjCreate("Scripting.Dictionary")
	Local $mAppVer = ObjCreate("Scripting.Dictionary")
	Local $mWT = ObjCreate("Scripting.Dictionary")

	If IsArray($aSecStatus) Then
		For $k = 1 To $aSecStatus[0][0]
			$mStatus.Item($aSecStatus[$k][0]) = $aSecStatus[$k][1]
		Next
	EndIf
	If IsArray($aSecOrig) Then
		For $k = 1 To $aSecOrig[0][0]
			$mOrig.Item($aSecOrig[$k][0]) = $aSecOrig[$k][1]
		Next
	EndIf
	If IsArray($aSecPatch) Then
		For $k = 1 To $aSecPatch[0][0]
			$mPatch.Item($aSecPatch[$k][0]) = $aSecPatch[$k][1]
		Next
	EndIf
	If IsArray($aSecAppFiles) Then
		For $k = 1 To $aSecAppFiles[0][0]
			Local $sKey = $aSecAppFiles[$k][0]
			Local $sVal = $aSecAppFiles[$k][1]
			If StringInStr($sKey, "\") Or StringRegExp($sKey, "^[A-Za-z]:") Then
				If Not $mAppFiles.Exists($sVal) Then
					$mAppFiles.Item($sVal) = $sKey
				ElseIf Not StringInStr(";" & $mAppFiles.Item($sVal) & ";", ";" & $sKey & ";") Then
					$mAppFiles.Item($sVal) = $mAppFiles.Item($sVal) & ";" & $sKey
				EndIf
			Else
				If Not $mAppFiles.Exists($sKey) Then
					$mAppFiles.Item($sKey) = $sVal
				Else
					Local $sExisting = $mAppFiles.Item($sKey)
					Local $aNewPaths = StringSplit($sVal, ";", 2)
					For $sP In $aNewPaths
						If $sP = "" Then ContinueLoop
						If Not StringInStr(";" & $sExisting & ";", ";" & $sP & ";") Then
							$sExisting = $sExisting & ";" & $sP
						EndIf
					Next
					$mAppFiles.Item($sKey) = $sExisting
				EndIf
			EndIf
		Next
	EndIf
	If IsArray($aSecAppVer) Then
		For $k = 1 To $aSecAppVer[0][0]
			$mAppVer.Item($aSecAppVer[$k][0]) = $aSecAppVer[$k][1]
		Next
	EndIf
	If IsArray($aSecWinTrust) Then
		For $k = 1 To $aSecWinTrust[0][0]
			$mWT.Item($aSecWinTrust[$k][0]) = $aSecWinTrust[$k][1]
		Next
	EndIf

	For $i = 0 To $iN - 1
		Local $sPath = $g_aStateQueue[$i][0]
		Local $sApp = $g_aStateQueue[$i][1]
		$mStatus.Item($sPath) = $g_aStateQueue[$i][4]
		If $g_aStateQueue[$i][2] <> "" Then $mOrig.Item($sPath) = $g_aStateQueue[$i][2]
		If $g_aStateQueue[$i][3] <> "" Then $mPatch.Item($sPath) = $g_aStateQueue[$i][3]
		If $sApp <> "" Then
			If Not $mAppFiles.Exists($sApp) Then
				$mAppFiles.Item($sApp) = $sPath
			ElseIf Not StringInStr(";" & $mAppFiles.Item($sApp) & ";", ";" & $sPath & ";") Then
				$mAppFiles.Item($sApp) = $mAppFiles.Item($sApp) & ";" & $sPath
			EndIf
		EndIf
	Next

	For $sApp In $mAppFiles.Keys()
		Local $sExe = ""

		Local $sFirstFile = $mAppFiles.Item($sApp)
		Local $iSepIdx = StringInStr($sFirstFile, ";")
		If $iSepIdx > 0 Then $sFirstFile = StringLeft($sFirstFile, $iSepIdx - 1)
		Local $sAppRoot = StringRegExpReplace($sFirstFile, "(?i)^(.+\\Adobe\\[^\\]+\\).*$", "$1")
		If $sAppRoot = $sFirstFile Then $sAppRoot = ""

		If $sAppRoot <> "" Then
			$sExe = _FindLauncherExe($sAppRoot, $sApp)
		EndIf

		If $sExe = "" Or Not FileExists($sExe) Then
			If $g_mAppPrimaryExe.Exists($sApp) Then
				$sExe = $g_mAppPrimaryExe.Item($sApp)
			EndIf
		EndIf

		If $sExe = "" Or Not FileExists($sExe) Then ContinueLoop

		Local $sVer = FileGetVersion($sExe)
		If @error Or $sVer = "" Then
			$sVer = FileGetVersion($sExe, $FV_PRODUCTVERSION)
		EndIf
		If $sVer = "" Then $sVer = "unknown"
		$mAppVer.Item($sApp) = "v" & $sVer
	Next

	For $sApp In $g_mWinTrustQueue.Keys()
		$mWT.Item($sApp) = $g_mWinTrustQueue.Item($sApp)
	Next

	_WriteSectionFromMap("Patch_Status", $mStatus)
	_WriteSectionFromMap("MD5_Original", $mOrig)
	_WriteSectionFromMap("MD5_Patched", $mPatch)
	_WriteSectionFromMap("App_File", $mAppFiles)
	_WriteSectionFromMap("App_Version", $mAppVer)
	_WriteSectionFromMap("WinTrust_Local", $mWT)

	IniWrite($patchStatesINI, "Info", "GenPVersion", $g_Version)
	IniWrite($patchStatesINI, "Info", "ConfigVersion", $ConfigVerVar)
	IniWrite($patchStatesINI, "Info", "LastRun", @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC)
	_RecordDevOverrideStateToLedger()

	_MaintainInisAlphebeticalWithSpacing($patchStatesINI)

	ReDim $g_aStateQueue[0][5]
	$g_mAppPrimaryExe.RemoveAll()
	$g_mWinTrustQueue.RemoveAll()
	$g_mAppVersionQueue.RemoveAll()
EndFunc

Func _ReconcilePatchStates()
	Local $aResult[4] = [0, 0, 0, 0]

	If Not FileExists($patchStatesINI) Then
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Reconcile", "No patch_states.ini present - nothing to reconcile.")
		Return $aResult
	EndIf

	Local $hStateProbe = FileOpen($patchStatesINI, 1)
	If $hStateProbe = -1 Then
		LogWrite(1, "Reconcile aborted - patch_states.ini is not writable: " & $patchStatesINI)
		MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Cannot Reconcile", _
				"patch_states.ini cannot be written:" & @CRLF & @CRLF & $patchStatesINI & @CRLF & @CRLF & _
				"It may be read-only or open in another program. Fix that and try again." & @CRLF & _
				"No changes were made.")
		Return $aResult
	EndIf
	FileClose($hStateProbe)

	_LockOptionsUIForScan()

	ToggleLog(0)
	MemoWrite(@CRLF & "Reconciling patch_states.ini against current install...")
	LogWrite(1, "Reconcile: scanning " & $MyDefPath)

	Local $aOrigSec = IniReadSection($patchStatesINI, "MD5_Original")
	Local $aPatchSec = IniReadSection($patchStatesINI, "MD5_Patched")
	Local $aStatSec = IniReadSection($patchStatesINI, "Patch_Status")
	Local $mOrig = ObjCreate("Scripting.Dictionary")
	Local $mPatch = ObjCreate("Scripting.Dictionary")
	Local $mStatus = ObjCreate("Scripting.Dictionary")
	If IsArray($aOrigSec) Then
		For $k = 1 To $aOrigSec[0][0]
			$mOrig.Item($aOrigSec[$k][0]) = $aOrigSec[$k][1]
		Next
	EndIf
	If IsArray($aPatchSec) Then
		For $k = 1 To $aPatchSec[0][0]
			$mPatch.Item($aPatchSec[$k][0]) = $aPatchSec[$k][1]
		Next
	EndIf
	If IsArray($aStatSec) Then
		For $k = 1 To $aStatSec[0][0]
			$mStatus.Item($aStatSec[$k][0]) = $aStatSec[$k][1]
		Next
	EndIf
	$aResult[3] = $mStatus.Count

	Local $mIniSeen = ObjCreate("Scripting.Dictionary")

	_ResetScanCounters()
	$g_aAllFiles = $aNullArray
	ReDim $g_aAllFiles[0][6]
	$FileSearchedCount = 0
	If $bFindACC = 1 Then
		Local $aACCDirs[2]
		$aACCDirs[0] = EnvGet('ProgramFiles(x86)') & "\Common Files\Adobe"
		$aACCDirs[1] = EnvGet('ProgramFiles') & "\Common Files\Adobe"
		For $sAccDir In $aACCDirs
			If FileExists($sAccDir) Then RecursiveFileSearch($sAccDir, 0, 0)
		Next
	EndIf
	RecursiveFileSearch($MyDefPath, 0, 0)

	Local $iTotal = UBound($g_aAllFiles, 1)
	If $iTotal = 0 Then
		LogWrite(1, "Reconcile: no eligible files found in " & $MyDefPath & ".")
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Reconcile", "No eligible files found in " & $MyDefPath & "." & @CRLF & "Reconcile aborted.")
		_UnlockOptionsUIAfterScan()
		Return $aResult
	EndIf

	LogWrite(1, "Reconcile: " & $iTotal & " file(s) found on disk; " & $aResult[3] & " entries in ini.")

	Local $bWeStartedCrypt = False
	If Not $g_bCryptActive Then
		_Crypt_Startup()
		$g_bCryptActive = True
		$bWeStartedCrypt = True
	EndIf

	Local $mRemovePaths = ObjCreate("Scripting.Dictionary")
	Local $mStatusChanges = ObjCreate("Scripting.Dictionary")
	Local $mNewEntries = ObjCreate("Scripting.Dictionary")

	For $i = 0 To $iTotal - 1
		Local $sPath = $g_aAllFiles[$i][0]
		If Not FileExists($sPath) Then ContinueLoop

		If Mod($i, 10) = 0 Then
			ProgressWrite(Round(($i + 1) / $iTotal * 100))
			_ShowStatusScreen("patching", "Reconciling: " & StringRegExpReplace($sPath, "^.*\\", ""))
		EndIf

		Local $sCurMD5 = StringLower(StringTrimLeft(String(_Crypt_HashFile($sPath, $CALG_MD5)), 2))
		If $sCurMD5 = "" Then ContinueLoop

		If $mStatus.Exists($sPath) Then
			$mIniSeen.Item($sPath) = 1
			Local $sStat = $mStatus.Item($sPath)
			Local $sP = $mPatch.Exists($sPath) ? StringLower($mPatch.Item($sPath)) : ""
			Local $sO = $mOrig.Exists($sPath) ? StringLower($mOrig.Item($sPath)) : ""

			If $sStat = "Patched" Then
				If $sP <> "" And $sCurMD5 = $sP Then
					$aResult[2] += 1
				ElseIf $sO <> "" And $sCurMD5 = $sO Then
					$mStatusChanges.Item($sPath) = "Unpatched"
					$aResult[1] += 1
					LogWrite(1, "drift Patched->Unpatched - " & $sPath)
				Else
					$mRemovePaths.Item($sPath) = 1
					$aResult[1] += 1
					LogWrite(1, "external modification - " & $sPath)
				EndIf
			Else
				If $sO <> "" And $sCurMD5 = $sO Then
					$aResult[2] += 1
				ElseIf $sP <> "" And $sCurMD5 = $sP Then
					$mStatusChanges.Item($sPath) = "Patched"
					$aResult[1] += 1
					LogWrite(1, "drift Unpatched->Patched - " & $sPath)
				Else
					$mRemovePaths.Item($sPath) = 1
					$aResult[1] += 1
					LogWrite(1, "external modification - " & $sPath)
				EndIf
			EndIf
		Else
			$mNewEntries.Item($sPath) = $sCurMD5
		EndIf
	Next

	For $sINIPath In $mStatus.Keys()
		If Not $mIniSeen.Exists($sINIPath) Then
			$mRemovePaths.Item($sINIPath) = 1
			$aResult[0] += 1
			LogWrite(1, "Missing - " & $sINIPath)
		EndIf
	Next

	If $bWeStartedCrypt Then
		_Crypt_Shutdown()
		$g_bCryptActive = False
	EndIf

	Local $iNew = $mNewEntries.Count
	If $mRemovePaths.Count > 0 Or $mStatusChanges.Count > 0 Or $iNew > 0 Then
		Local $aSections[5] = ["Patch_Status", "MD5_Original", "MD5_Patched", "App_File", "WinTrust_Local"]
		For $sSec In $aSections
			For $sPath In $mRemovePaths.Keys()
				IniDelete($patchStatesINI, $sSec, $sPath)
			Next
		Next
		For $sPath In $mStatusChanges.Keys()
			IniWrite($patchStatesINI, "Patch_Status", $sPath, $mStatusChanges.Item($sPath))
		Next
		For $sPath In $mNewEntries.Keys()
			IniWrite($patchStatesINI, "Patch_Status", $sPath, "Unpatched")
			IniWrite($patchStatesINI, "MD5_Original", $sPath, $mNewEntries.Item($sPath))
		Next

		_MaintainInisAlphebeticalWithSpacing($patchStatesINI)
	EndIf

	ProgressWrite(0)
	_ShowStatusScreen("complete", $MyDefPath)
	Sleep(1500)
	$g_bStatusScreenReady = False

	Local $sSummary = "Reconcile complete." & @CRLF & @CRLF & _
			"Files scanned on disk:    " & $iTotal & @CRLF & _
			"Entries in ini:           " & $aResult[3] & @CRLF & _
			"Confirmed accurate:       " & $aResult[2] & @CRLF & _
			"Drift corrected:          " & $aResult[1] & @CRLF & _
			"Missing (removed):        " & $aResult[0] & @CRLF & _
			"New files added:          " & $iNew & @CRLF & @CRLF & _
			"Please review the Main tab to confirm the results match your" & @CRLF & _
			"expectations. If anything looks off, use Patch or Restore as" & @CRLF & _
			"needed to bring the install back into the state you want."
	Local $sSetupTS = @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC
	IniWrite($patchStatesINI, "Info", "ReconcileUsed",    "1")
	IniWrite($patchStatesINI, "Info", "ReconcileUsedDate", $sSetupTS)
	IniWrite($patchStatesINI, "Info", "CreatedNew",       "0")
	IniWrite($patchStatesINI, "Info", "CreatedNewDate",   "")
	IniWrite($sINIPath, "Options", "ReconcileUsed",    "1")
	IniWrite($sINIPath, "Options", "ReconcileUsedDate", $sSetupTS)
	IniWrite($sINIPath, "Options", "CreatedNew",       "0")
	IniWrite($sINIPath, "Options", "CreatedNewDate",   "")

	LogWrite(1, "Reconcile complete: " & $aResult[2] & " accurate, " & $aResult[1] & " drift, " & $aResult[0] & " missing, " & $iNew & " new.")
	MemoWrite(@CRLF & $sSummary)
	MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Reconcile Complete", $sSummary)

	If $idOptionsReminder > 0 Then
		GUICtrlSetData($idOptionsReminder, "Changes will not take effect until saved")
		GUICtrlSetState($idOptionsReminder, $GUI_HIDE)
	EndIf
	If $idBtnSaveOptions > 0 Then GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)

	$g_bSearchCompleted = True
	$fFilesListed = 1
	GUICtrlSetState($idListview, $GUI_ENABLE)
	FillListViewWithFiles()
	_VerifyListedFiles(True)
	Local $iKeptR = _ApplyModifiedFilter()

	_GUICtrlTab_SetCurFocus($hTab, 0)
	$g_bIsPatching = False
	_RestorePostOpUI()

	If $iKeptR = 0 Then
		$g_bInModifiedMode = False
		$fFilesListed = 0
		$g_bSearchCompleted = False
		ReDim $g_aAllFiles[0][6]
		$g_mCheckedState.RemoveAll()
		FillListViewWithInfo()
		UpdateUIState()
		MemoWrite(@CRLF & "Reconcile: no files needed any action - everything confirmed accurate.")
	Else
		UpdateUIState()
		MemoWrite(@CRLF & $iKeptR & " file(s) flagged after Reconcile. Review the listview, then click Patch (or Restore) as appropriate.")
	EndIf

	Return $aResult
EndFunc

Func _WipeAdobeLicenseCaches()
	If _PromptStopAdobeProcessesForOp("wiped") = 0 Then
		LogWrite(1, "Cache wipe aborted by user at Adobe-process prompt.")
		Return -1
	EndIf

	Local $sProgramData = EnvGet("ProgramData")
	If $sProgramData = "" Then $sProgramData = @HomeDrive & "\ProgramData"
	Local $sCommonFiles = EnvGet("CommonProgramFiles")
	If $sCommonFiles = "" Then $sCommonFiles = @ProgramFilesDir & "\Common Files"

	Local $aPaths[21]
	$aPaths[0] = @LocalAppDataDir & "\Adobe\OOBE"
	$aPaths[1] = @LocalAppDataDir & "\Adobe\IdentityCC"
	$aPaths[2] = @LocalAppDataDir & "\Adobe\licflags"
	$aPaths[3] = @LocalAppDataDir & "\Adobe\webview2"
	$aPaths[4] = @AppDataDir & "\Adobe\NGL"
	$aPaths[5] = @AppDataDir & "\Adobe\OOBE"
	$aPaths[6] = @AppDataDir & "\Adobe\CCX Welcome"
	$aPaths[7] = @LocalAppDataDir & "\Adobe\.adobelicnotificationV2"
	$aPaths[8] = @LocalAppDataDir & "\Adobe\.adobefeatureflagnotification"
	$aPaths[9] = @LocalAppDataDir & "\Adobe\.adobestatusnotification"
	$aPaths[10] = @LocalAppDataDir & "\Adobe\UXP"
	$aPaths[11] = @LocalAppDataDir & "\Adobe\CEP\cache"
	$aPaths[12] = @AppDataDir & "\Adobe\UXP\PluginsStorage"
	$aPaths[13] = $sCommonFiles & "\Adobe\SLCache"
	$aPaths[14] = $sProgramData & "\Adobe\SLStore"
	$aPaths[15] = $sProgramData & "\Adobe\IdentityNGL"
	$aPaths[16] = @LocalAppDataDir & "\Temp\NGL"
	$aPaths[17] = @LocalAppDataDir & "\Adobe\AcroCef\Cache"
	$aPaths[18] = @LocalAppDataDir & "\Microsoft\WebView2\EBWebView\Adobe"
	$aPaths[19] = @CommonFilesDir & "\Adobe\Workflow\ResourcePacks"
	$aPaths[20] = (EnvGet("CommonProgramFiles(x86)") <> "" ? EnvGet("CommonProgramFiles(x86)") : @HomeDrive & "\Program Files (x86)\Common Files") & "\Adobe\caps"

	LogWrite(1, "Wiping Adobe license caches (full reset)...")
	MemoWrite(@CRLF & "Wiping Adobe license caches:")
	Local $iWiped = 0, $iFailed = 0
	For $i = 0 To UBound($aPaths) - 1
		Local $sPath = $aPaths[$i]
		If Not FileExists($sPath) Then
			ContinueLoop
		EndIf

		Local $iResultStatus = 0
		If StringInStr(FileGetAttrib($sPath), "D") Then
			If DirRemove($sPath, 1) Then $iResultStatus = 1
		Else
			If FileDelete($sPath) Then $iResultStatus = 1
		EndIf

		If $iResultStatus = 1 Then
			$iWiped += 1
		Else
			LogWrite(1, "Failed to wipe (file in use? close Adobe apps first): " & $sPath)
			MemoWrite("Failed: " & $sPath & " (in use?)")
			$iFailed += 1
		EndIf
	Next

	LogWrite(1, "Scanning for localised Adobe application WebView sandbox environments...")
	Local $aAdobeTokens = _BuildAdobeWebViewTokens()
	Local $HSEARCH = FileFindFirstFile(@LocalAppDataDir & "\*")
	If $HSEARCH <> -1 Then
		While 1
			Local $sFolder = FileFindNextFile($HSEARCH)
			If @error Then ExitLoop

			Local $sCurrentDir = @LocalAppDataDir & "\" & $sFolder
			If Not StringInStr(FileGetAttrib($sCurrentDir), "D") Then ContinueLoop

			Local $bIsAdobe = False
			For $sTok In $aAdobeTokens
				If StringInStr($sFolder, $sTok) Then
					$bIsAdobe = True
					ExitLoop
				EndIf
			Next
			If Not $bIsAdobe Then ContinueLoop

			Local $sTargetWebView = $sCurrentDir & "\EBWebView"
			If FileExists($sTargetWebView) Then
				If DirRemove($sTargetWebView, 1) Then
					$iWiped += 1
				Else
					LogWrite(1, "Failed to wipe App WebView (locked): " & $sTargetWebView)
					MemoWrite("Failed: " & $sFolder & " WebView cache")
					$iFailed += 1
				EndIf
			EndIf
		WEnd
		FileClose($HSEARCH)
	EndIf

	LogWrite(1, "Clearing residual Adobe identifiers from Windows Credential Manager...")
	RunWait(@ComSpec & ' /c cmdkey /delete:Adobe_Enterprise_User_Identity', "", @SW_HIDE)
	RunWait(@ComSpec & ' /c cmdkey /delete:Adobe_User_Identity', "", @SW_HIDE)
	RunWait(@ComSpec & ' /c cmdkey /delete:Adobe_Licensing_Storage', "", @SW_HIDE)
	RunWait("ipconfig /flushdns", "", @SW_HIDE)
	MemoWrite("Cleared: Windows Credential Vault Adobe tokens.")

	If $iFailed > 0 Then
		LogWrite(1, "Cache wipe finished: " & $iWiped & " removed, " & $iFailed & " still locked.")
		Local $iLocked = MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING, $MB_DEFBUTTON2), "Some Caches Still Locked", _
				$iWiped & " item(s) removed, but " & $iFailed & " still in use" & @CRLF & _
				"and could not be cleared (see the Log)." & @CRLF & @CRLF & _
				"For a clean reset, close all Adobe apps and" & @CRLF & _
				"Creative Cloud, then run the process again." & @CRLF & @CRLF & _
				"Stop now so you can close them?" & @CRLF & @CRLF & _
				"Yes = stop (nothing patched yet)." & @CRLF & _
				"No = continue anyway (locked items left as-is).")
		If $iLocked = $IDYES Then
			LogWrite(1, "Create new patch_states.ini: stopped at user request to close Adobe apps and retry.")
			Return -1
		EndIf
		LogWrite(1, "Continuing despite " & $iFailed & " locked cache item(s) (user confirmed).")
	Else
		LogWrite(1, "Cache wipe finished cleanly: " & $iWiped & " item(s) removed, none locked.")
	EndIf

	Return $iWiped
EndFunc

Func _CleanOOBEDirectorySafely($sOOBEPath)
	Local $HSEARCH = FileFindFirstFile($sOOBEPath & "\*")
	If $HSEARCH = -1 Then Return True
	Local $bAllCleared = True

	While 1
		Local $sFile = FileFindNextFile($HSEARCH)
		If @error Then ExitLoop

		If StringInStr($sFile, "AppDefs") Or StringInStr($sFile, "OOBE.db") Or StringInStr($sFile, "ServiceConfig") _
				Or $sFile = "opm.db" Or $sFile = "com.adobe.accc.apps" _
				Or StringInStr($sFile, ".prefs") Then
			ContinueLoop
		EndIf

		Local $sFullPath = $sOOBEPath & "\" & $sFile
		If StringInStr(FileGetAttrib($sFullPath), "D") Then
			If Not DirRemove($sFullPath, 1) Then $bAllCleared = False
		Else
			If Not FileDelete($sFullPath) Then $bAllCleared = False
		EndIf
	WEnd
	FileClose($HSEARCH)
	Return $bAllCleared
EndFunc

Func _ClearLicenseCachesLight()
	Local $aLight[7]
	$aLight[0] = @LocalAppDataDir & "\Adobe\OOBE"
	$aLight[1] = @AppDataDir & "\Adobe\OOBE"
	$aLight[2] = @AppDataDir & "\Adobe\NGL"
	$aLight[3] = @LocalAppDataDir & "\Adobe\.adobelicnotificationV2"
	$aLight[4] = @LocalAppDataDir & "\Adobe\.adobefeatureflagnotification"
	$aLight[5] = @LocalAppDataDir & "\Adobe\.adobestatusnotification"
	$aLight[6] = @LocalAppDataDir & "\Temp\NGL"

	LogWrite(1, "Light license-cache clear (per-user only) after patch...")
	Local $iWiped = 0, $iFailed = 0, $iFiltered = 0
	For $i = 0 To UBound($aLight) - 1
		Local $sPath = $aLight[$i]
		If Not FileExists($sPath) Then
			ContinueLoop
		EndIf

		Local $iResultStatus = 0
		If StringInStr(FileGetAttrib($sPath), "D") Then
			If StringInStr($sPath, "\Adobe\OOBE") Then
				If _CleanOOBEDirectorySafely($sPath) Then
					$iResultStatus = 2
				EndIf
			Else
				If DirRemove($sPath, 1) Then $iResultStatus = 1
			EndIf
		Else
			If FileDelete($sPath) Then $iResultStatus = 1
		EndIf

		If $iResultStatus = 1 Then
			$iWiped += 1
		ElseIf $iResultStatus = 2 Then
			$iFiltered += 1
		Else
			$iFailed += 1
		EndIf
	Next

	LogWrite(1, "Light license-cache clear done: " & $iWiped & " cleared, " & $iFiltered & " preserved, " & $iFailed & " skipped/locked.")
	MemoWrite("Light license-cache clear done: " & $iWiped & " cleared, " & $iFiltered & " preserved, " & $iFailed & " skipped/locked.")
	Return $iWiped
EndFunc

Func _BuildAdobeWebViewTokens()
	Local $aBase[26] = [ _
			"Adobe", "Photoshop", "Lightroom", "Illustrator", "InDesign", "Premiere", _
			"AfterEffects", "After Effects", "Animate", "Audition", "Bridge", "Acrobat", _
			"Substance", "Dreamweaver", "Character Animator", "CharacterAnimator", _
			"Dimension", "Media Encoder", "MediaEncoder", "Firefly", "Fresco", "Distiller", _
			"Creative Cloud", "CreativeCloud", "CCX", "Elements"]

	Local $mTok = ObjCreate("Scripting.Dictionary")
	For $sB In $aBase
		If Not $mTok.Exists(StringLower($sB)) Then $mTok.Item(StringLower($sB)) = 1
	Next

	Local $sDeny = "|public|registration|objectmodel|containerbl|appspanelbl|hdpim|" & _
			"nglplugin|runtimeinstaller|sweetpeasupport|dvaappsupport|afterfxlib|" & _
			"acrotray|acrodistdll|acrocef|euclid|dynamic|adobecollabsync|application|" & _
			"jpeg|auui|objectmodel|"

	Local $aSec = IniReadSection($sINIPath, "CustomPatterns")
	If IsArray($aSec) Then
		For $k = 1 To $aSec[0][0]
			Local $sName = StringLower($aSec[$k][0])
			Local $iDot = StringInStr($sName, ".")
			If $iDot > 0 Then $sName = StringLeft($sName, $iDot - 1)
			$sName = StringRegExpReplace($sName, "\(beta\)", "")
			$sName = StringStripWS($sName, 3)
			If StringLeft($sName, 6) = "adobe " Then $sName = StringTrimLeft($sName, 6)
			Local $aM = StringRegExp($sName, "^([a-z]+)", 1)
			If @error Then ContinueLoop
			Local $sTok = $aM[0]
			If StringLen($sTok) < 5 Then ContinueLoop
			If StringInStr($sDeny, "|" & $sTok & "|") Then ContinueLoop
			If Not $mTok.Exists($sTok) Then $mTok.Item($sTok) = 1
		Next
	EndIf

	Local $aOut[$mTok.Count]
	Local $j = 0
	For $sKey In $mTok.Keys
		$aOut[$j] = $sKey
		$j += 1
	Next
	Return $aOut
EndFunc

Func _TargetFolderReady($sPath)
	If $sPath = "" Or Not FileExists($sPath) Or Not StringInStr(FileGetAttrib($sPath), "D") Then
		Return "The Adobe target folder could not be found:" & @CRLF & @CRLF & $sPath & @CRLF & @CRLF & _
				"If it is on an external or secondary drive, make sure that the" & @CRLF & _
				"drive is connected, then try again. No changes were made."
	EndIf
	Local $sProbe = $sPath & "\.genp_write_test.tmp"
	Local $hProbe = FileOpen($sProbe, 2)
	If $hProbe = -1 Then
		Return "GenP cannot write to the Adobe target folder:" & @CRLF & @CRLF & $sPath & @CRLF & @CRLF & _
				"Try running GenP as administrator. No changes were made."
	EndIf
	FileClose($hProbe)
	FileDelete($sProbe)
	Return ""
EndFunc

Func _CreateInitialPatchStates()
	If FileExists($patchStatesINI) Then
		MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Cannot Create", "patch_states.ini already exists. Use Reconcile instead.")
		Return
	EndIf

	LogWrite(1, "Create new patch_states.ini: stopping all Adobe processes before restore...")
	Local $iSurvived = _StopAllAdobeProcesses()
	If $iSurvived > 0 Then
		Local $aStillUp = ProcessList()
		Local $sSurvivorList = ""
		For $j = 1 To $aStillUp[0][0]
			If _IsAdobeProcess(StringLower($aStillUp[$j][0])) Then $sSurvivorList &= "  - " & $aStillUp[$j][0] & @CRLF
		Next
		LogWrite(1, "Create new patch_states.ini: " & $iSurvived & " Adobe process(es) could not be stopped.")
		MsgBox(BitOR($MB_OK, $MB_ICONWARNING, $MB_SYSTEMMODAL), "Processes Still Running", _
				$iSurvived & " Adobe process(es) could not be stopped:" & @CRLF & @CRLF & _
				$sSurvivorList & @CRLF & _
				"Continuing -- any locked files will be skipped and reported back.")
	EndIf

	_LockOptionsUIForScan()
	ToggleLog(0)
	MemoWrite(@CRLF & "Building initial patch_states.ini - scanning files...")
	LogWrite(1, "Create new patch_states.ini: scanning " & $MyDefPath)

	_ResetScanCounters()
	$g_aAllFiles = $aNullArray
	ReDim $g_aAllFiles[0][6]
	$FileSearchedCount = 0
	If $bFindACC = 1 Then
		Local $aACCDirs[2]
		$aACCDirs[0] = EnvGet('ProgramFiles(x86)') & "\Common Files\Adobe"
		$aACCDirs[1] = EnvGet('ProgramFiles') & "\Common Files\Adobe"
		For $sAccDir In $aACCDirs
			If FileExists($sAccDir) Then RecursiveFileSearch($sAccDir, 0, 0)
		Next
	EndIf
	RecursiveFileSearch($MyDefPath, 0, 0)

	If UBound($g_aAllFiles, 1) = 0 Then
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Create New", "No eligible files found in " & $MyDefPath & "." & @CRLF & "patch_states.ini was not created.")
		LogWrite(1, "Create new patch_states.ini: aborted - no eligible files in " & $MyDefPath & ".")
		_UnlockOptionsUIAfterScan()
		Return
	EndIf

	Local $iTotal = UBound($g_aAllFiles, 1)
	LogWrite(1, "Create new patch_states.ini: found " & $iTotal & " eligible file(s).")

	MemoWrite(@CRLF & "Phase 1 of 2: restoring patched files to originals (" & $iTotal & " found)...")
	LogWrite(1, "Create new patch_states.ini: beginning restore phase...")
	Local $iRestored = 0, $iRestoreFailed = 0, $iRestoreStale = 0

	Local $bWeStartedCrypt = False
	If Not $g_bCryptActive Then
		_Crypt_Startup()
		$g_bCryptActive = True
		$bWeStartedCrypt = True
	EndIf

	For $i = 0 To $iTotal - 1
		Local $sPath = $g_aAllFiles[$i][0]
		Local $sBakR = $sPath & ".bak"
		If Not FileExists($sBakR) Then ContinueLoop

		Local $sFileNameR = StringLower(StringRegExpReplace($sPath, "^.*\\", ""))
		If $sFileNameR = "appspanelbl.dll" Or $sFileNameR = "adobe desktop service.exe" Then
			_ProcessCloseEx("""Creative Cloud.exe""")
			_ProcessCloseEx("""Adobe Desktop Service.exe""")
			Sleep(100)
		EndIf

		Local $sStaleWhy = ""
		Local $sExtLC = StringLower(StringRegExpReplace($sPath, "^.*\.", ""))
		If FileExists($sPath) And $sExtLC <> "js" And $sExtLC <> "json" Then
			Local $sVerBak = FileGetVersion($sBakR)
			If @error Or $sVerBak = "" Then $sVerBak = FileGetVersion($sBakR, $FV_PRODUCTVERSION)
			Local $sVerLive = FileGetVersion($sPath)
			If @error Or $sVerLive = "" Then $sVerLive = FileGetVersion($sPath, $FV_PRODUCTVERSION)
			If $sVerBak <> "" And $sVerLive <> "" And $sVerBak <> $sVerLive Then
				$sStaleWhy = "version " & $sVerBak & " -> " & $sVerLive
			EndIf

			If $sStaleWhy = "" And FileGetSize($sBakR) <> FileGetSize($sPath) Then
				$sStaleWhy = "size mismatch"
			EndIf

			If $sStaleWhy = "" Then
				Local $sRecOrig  = IniRead($patchStatesINI, "MD5_Original", $sPath, "")
				Local $sRecPatch = IniRead($patchStatesINI, "MD5_Patched",  $sPath, "")
				If $sRecOrig <> "" Or $sRecPatch <> "" Then
					Local $sLiveNow = StringLower(StringTrimLeft(String(_Crypt_HashFile($sPath, $CALG_MD5)), 2))
					If $sLiveNow <> "" And $sLiveNow <> $sRecOrig And $sLiveNow <> $sRecPatch Then
						$sStaleWhy = "MD5 matches neither recorded original nor patched"
					EndIf
				EndIf
			EndIf
		EndIf

		If $sStaleWhy <> "" Then
			FileDelete($sBakR)
			$iRestoreStale += 1
			LogWrite(1, "Restore skipped - stale .bak from a previous app version (" & $sStaleWhy & "), removed: " & $sPath)
			ContinueLoop
		EndIf
		If FileMove($sBakR, $sPath, $FC_OVERWRITE) Then
			$iRestored += 1
		Else
			$iRestoreFailed += 1
			LogWrite(1, "Restore failed (file in use?): " & $sPath)
		EndIf

		If Mod($i, 10) = 0 Then
			ProgressWrite(Round(($i + 1) / $iTotal * 50))
		EndIf
	Next

	LogWrite(1, "Restore phase: " & $iRestored & " restored, " & $iRestoreStale & " stale skipped, " & $iRestoreFailed & " failed.")
	MemoWrite("Restore complete: " & $iRestored & " file(s) returned to original state.")

	Local $mStatus   = ObjCreate("Scripting.Dictionary")
	Local $mOrig     = ObjCreate("Scripting.Dictionary")
	Local $mPatched  = ObjCreate("Scripting.Dictionary")
	Local $mAppFiles = ObjCreate("Scripting.Dictionary")
	Local $mAppVer   = ObjCreate("Scripting.Dictionary")
	Local $mWT       = ObjCreate("Scripting.Dictionary")
	Local $mPrimaryExe = ObjCreate("Scripting.Dictionary")

	Local $iPatchedCount = 0, $iUnpatchedCount = 0
	MemoWrite(@CRLF & "Phase 2 of 2: hashing " & $iTotal & " file(s)...")
	ProgressWrite(50)
	_SubProgressWrite(0)

	For $i = 0 To $iTotal - 1
		Local $sPath = $g_aAllFiles[$i][0]
		If Not FileExists($sPath) Then ContinueLoop

		Local $sApp = _GetAppGroupName($sPath)
		Local $sFileName = StringRegExpReplace($sPath, "^.*\\", "")

		If $mAppFiles.Exists($sApp) Then
			$mAppFiles.Item($sApp) = $mAppFiles.Item($sApp) & ";" & $sPath
		Else
			$mAppFiles.Item($sApp) = $sPath
		EndIf

		If StringRight($sFileName, 4) = ".exe" Then
			If Not $mPrimaryExe.Exists($sApp) Then
				$mPrimaryExe.Item($sApp) = $sPath
			Else
				If StringInStr($sFileName, StringLeft($sApp, 6)) Then
					$mPrimaryExe.Item($sApp) = $sPath
				EndIf
			EndIf
		EndIf

		Local $sBakPath = $sPath & ".bak"

		If FileExists($sBakPath) Then
			Local $sOrigMD5 = StringLower(StringTrimLeft(String(_Crypt_HashFile($sBakPath, $CALG_MD5)), 2))
			Local $sLiveMD5 = StringLower(StringTrimLeft(String(_Crypt_HashFile($sPath,    $CALG_MD5)), 2))
			If $sOrigMD5 = $sLiveMD5 Then
				$mStatus.Item($sPath) = "Unpatched"
				$mOrig.Item($sPath)   = $sOrigMD5
				$iUnpatchedCount += 1
			Else
				$mStatus.Item($sPath)  = "Patched"
				$mOrig.Item($sPath)    = $sOrigMD5
				$mPatched.Item($sPath) = $sLiveMD5
				$iPatchedCount += 1
			EndIf
		Else
			Local $sLiveMD5 = StringLower(StringTrimLeft(String(_Crypt_HashFile($sPath, $CALG_MD5)), 2))
			$mStatus.Item($sPath) = "Unpatched"
			$mOrig.Item($sPath)   = $sLiveMD5
			$iUnpatchedCount += 1
			$sLiveMD5 = ""
		EndIf

		If Mod($i, 10) = 0 Then
			ProgressWrite(50 + Round(($i + 1) / $iTotal * 50))
			_ShowStatusScreen("patching", "Hashing: " & $sFileName)
		EndIf
	Next

	For $sApp In $mAppFiles.Keys()
		Local $sExe = ""

		Local $sFirstFile = $mAppFiles.Item($sApp)
		Local $iSepIdx = StringInStr($sFirstFile, ";")
		If $iSepIdx > 0 Then $sFirstFile = StringLeft($sFirstFile, $iSepIdx - 1)
		Local $sAppRootForExe = StringRegExpReplace($sFirstFile, "(?i)^(.+\\Adobe\\[^\\]+\\).*$", "$1")
		If $sAppRootForExe <> $sFirstFile And FileExists($sAppRootForExe) Then
			$sExe = _FindLauncherExe($sAppRootForExe, $sApp)
		EndIf

		If $sExe = "" Or Not FileExists($sExe) Then
			If $mPrimaryExe.Exists($sApp) Then
				$sExe = $mPrimaryExe.Item($sApp)
			EndIf
		EndIf

		If $sExe <> "" And FileExists($sExe) Then
			Local $sVer = FileGetVersion($sExe)
			If @error Or $sVer = "" Then $sVer = FileGetVersion($sExe, $FV_PRODUCTVERSION)
			If $sVer = "" Then $sVer = "unknown"
			$mAppVer.Item($sApp) = "v" & $sVer
		Else
			$mAppVer.Item($sApp) = "vunknown"
		EndIf
	Next

	For $sApp In $mAppFiles.Keys()
		Local $sFirstFile = $mAppFiles.Item($sApp)
		Local $iSepIdx = StringInStr($sFirstFile, ";")
		If $iSepIdx > 0 Then $sFirstFile = StringLeft($sFirstFile, $iSepIdx - 1)
		Local $sAppRoot = StringRegExpReplace($sFirstFile, "(?i)^(.+\\Adobe\\[^\\]+\\).*$", "$1")
		If $sAppRoot <> $sFirstFile And FileExists($sAppRoot) Then
			$mWT.Item($sApp) = _HasWinTrustDll($sAppRoot) ? "1" : "0"
		Else
			$mWT.Item($sApp) = "0"
		EndIf
	Next

	If $bWeStartedCrypt Then
		_Crypt_Shutdown()
		$g_bCryptActive = False
	EndIf

	_WriteSectionFromMap("Patch_Status", $mStatus)
	_WriteSectionFromMap("MD5_Original", $mOrig)
	_WriteSectionFromMap("MD5_Patched", $mPatched)
	_WriteSectionFromMap("App_File", $mAppFiles)
	_WriteSectionFromMap("App_Version", $mAppVer)
	_WriteSectionFromMap("WinTrust_Local", $mWT)

	IniWrite($patchStatesINI, "Info", "GenPVersion", $g_Version)
	IniWrite($patchStatesINI, "Info", "ConfigVersion", $ConfigVerVar)
	IniWrite($patchStatesINI, "Info", "Created", _NowCalc())
	IniWrite($patchStatesINI, "Info", "Origin", "create-new")

	Local $sSetupTS = @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC
	IniWrite($patchStatesINI, "Info", "CreatedNew",       "1")
	IniWrite($patchStatesINI, "Info", "CreatedNewDate",   $sSetupTS)
	IniWrite($patchStatesINI, "Info", "ReconcileUsed",    "0")
	IniWrite($patchStatesINI, "Info", "ReconcileUsedDate", "")
	IniWrite($sINIPath, "Options", "CreatedNew",       "1")
	IniWrite($sINIPath, "Options", "CreatedNewDate",   $sSetupTS)
	IniWrite($sINIPath, "Options", "ReconcileUsed",    "0")
	IniWrite($sINIPath, "Options", "ReconcileUsedDate", "")

	RegWrite("HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Adobe\Licensing\UserSpecificLicensing", "Enabled", "REG_SZ", "0")
	_RecordDevOverrideStateToLedger()
	_MaintainInisAlphebeticalWithSpacing($patchStatesINI)

	ProgressWrite(0)
	_SubProgressWrite(0)
	If $g_idOptionsProgress > 0 Then
		GUICtrlSendMsg($g_idOptionsProgress, 0x040A, 0, 0)
		GUICtrlSetState($g_idOptionsProgress, $GUI_HIDE)
	EndIf
	_ShowStatusScreen("complete", $MyDefPath)
	Sleep(1500)
	$g_bStatusScreenReady = False

	Local $sSummary = "patch_states.ini built - auto-patch starting." & @CRLF & @CRLF & _
			"App groups:        " & $mAppFiles.Count & @CRLF & _
			"Files found:       " & $iTotal & @CRLF & _
			"Restored:          " & $iRestored & @CRLF & _
			($iRestoreFailed > 0 ? "Restore failed:    " & $iRestoreFailed & " (file(s) in use, detected as patched)" & @CRLF : "") & _
			@CRLF & "Switching to Main tab - auto-patch begins shortly."

	LogWrite(1, "Create new patch_states.ini complete: " & $iTotal & " indexed (" & $iPatchedCount & " patched, " & $iUnpatchedCount & " unpatched).")
	MemoWrite(@CRLF & $sSummary)
	_MonoInfoBox("patch_states.ini created", $sSummary, 15)

	If $idOptionsReminder > 0 Then
		GUICtrlSetData($idOptionsReminder, "Changes will not take effect until saved")
		GUICtrlSetState($idOptionsReminder, $GUI_HIDE)
	EndIf
	If $idBtnSaveOptions > 0 Then GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)

	$g_bSearchCompleted = True
	$fFilesListed = 1
	GUICtrlSetState($idListview, $GUI_ENABLE)
	FillListViewWithFiles()
	_SyncWinTrustFromDisk()
	_VerifyListedFiles(True)
	Local $iKept = _ApplyModifiedFilter()

	_GUICtrlTab_SetCurFocus($hTab, 0)

	If $iKept = 0 Then
		$g_bIsPatching = False
		_ShowEmptyModifiedNotice()
		_RestorePostOpUI()
		UpdateUIState()
	Else
		UpdateUIState()
		MemoWrite(@CRLF & $iKept & " file(s) ready - auto-patching to finalise the install...")
		$g_bAutoPatchPending = True
	EndIf
EndFunc

Func _CleanOrphanBaks(ByRef $aRestoredPaths)
	Local $iRemoved = 0
	If UBound($aRestoredPaths) > 0 Then
		Local $mDirs = ObjCreate("Scripting.Dictionary")
		For $i = 0 To UBound($aRestoredPaths) - 1
			Local $sPath = $aRestoredPaths[$i]
			Local $iSlash = StringInStr($sPath, "\", 0, -1)
			If $iSlash > 0 Then
				Local $sDir = StringLeft($sPath, $iSlash - 1)
				If Not $mDirs.Exists($sDir) Then $mDirs.Item($sDir) = 1
			EndIf
		Next

		For $sDir In $mDirs.Keys
			Local $hFind = FileFindFirstFile($sDir & "\*.bak")
			If $hFind = -1 Then ContinueLoop
			While 1
				Local $sName = FileFindNextFile($hFind)
				If @error Then ExitLoop
				Local $sBak = $sDir & "\" & $sName
				If StringInStr(FileGetAttrib($sBak), "D") Then ContinueLoop

				Local $sSibling = StringTrimRight($sBak, 4)
				If FileExists($sSibling) Then ContinueLoop

				If FileDelete($sBak) Then
					$iRemoved += 1
					LogWrite(1, "Removed orphaned backup (no sibling file present): " & $sBak)
				EndIf
			WEnd
			FileClose($hFind)
		Next
	EndIf

	Local $iKept = 0
	Local $aKeptNames[0]
	Local $iCount = _GUICtrlListView_GetItemCount($g_idListview)
	For $i = 0 To $iCount - 1
		Local $sStatus = _GUICtrlListView_GetItemText($g_idListview, $i, 2)
		If $sStatus <> "Patched" Then ContinueLoop
		Local $sPath = _GUICtrlListView_GetItemText($g_idListview, $i, 1)
		If $sPath = "" Then ContinueLoop
		Local $sName = StringLower(StringRegExpReplace($sPath, "^.*\\", ""))
		If $sName = "manifest.json" Then ContinueLoop
		Local $sBak = $sPath & ".bak"
		If Not FileExists($sBak) Then ContinueLoop
		$iKept += 1
		ReDim $aKeptNames[$iKept]
		$aKeptNames[$iKept - 1] = $sBak
	Next

	If $iRemoved > 0 Then
		LogWrite(1, "Cleaned " & $iRemoved & " orphaned .bak file(s) from restored folder(s).")
	EndIf
	If $iKept > 0 Then
		LogWrite(1, "Preserved " & $iKept & " .bak file(s) for files still patched:")
		MemoWrite(@CRLF & "Preserved " & $iKept & " backup(s) for files still in use:")
		For $i = 0 To UBound($aKeptNames) - 1
			LogWrite(1, "  - " & $aKeptNames[$i])
			MemoWrite("  - " & $aKeptNames[$i])
		Next
	EndIf
	Return $iRemoved
EndFunc

Func _PatchAdobeUXPComponent($sFilePath)
	Local $sFileName = StringLower(StringRegExpReplace($sFilePath, "^.*\\", ""))
	Local $bIsPremierePath = (StringInStr($sFilePath, "Premiere Pro") > 0)
	If $sFileName = "manifest.json" Then
		If Not $bIsPremierePath Then
			Return _RestoreManifestJsonIfBackupExists($sFilePath)
		EndIf
	EndIf
	If $bIsPremierePath And StringRight($sFileName, 3) = ".js" Then Return 0
	Local $hFile = FileOpen($sFilePath, 16)
	If $hFile = -1 Then Return 0
	Local $bData = FileRead($hFile)
	FileClose($hFile)
	If BinaryLen($bData) = 0 Then Return 0
	Local $bIsJs = StringRegExp($sFileName, "(?i)\.js$")
	Local $bIsJson = StringRegExp($sFileName, "(?i)\.json$")
	Local $sData = BinaryToString($bData, 1)
	Local $iApplied = 0
	Local $iAlready = 0
	Local $iTotal = 0
	If $bIsJson And $bIsPremierePath Then
		$iTotal += 1
		Local $sBefore = $sData
		$sData = StringRegExpReplace($sData, '(?i)"version"\s*:\s*"(\d+)\.([^"]+)"', '"version": "99.$2"')
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, '"version": "99.') Then
			$iAlready += 1
		EndIf
	EndIf
	If $bIsJs Then
		Local $sBefore
		$iTotal += 1
		$sBefore = $sData
		$sData = StringReplace($sData, "RelationshipProfile", "XelationshipProfile")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "XelationshipProfile") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringRegExpReplace($sData, "get chicletData\(\)\{(?!return null;)", "get chicletData(){return null;")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "get chicletData(){return null;") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringRegExpReplace($sData, "get teamTrialChicletData\(\)\{(?!return null;)", "get teamTrialChicletData(){return null;")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "get teamTrialChicletData(){return null;") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringRegExpReplace($sData, "invokeUpgradePlan\(\)\s*\{(?!\s*return;)", "invokeUpgradePlan(){return;")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "invokeUpgradePlan(){return;") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringRegExpReplace($sData, "https://workflow(-stage)?\.licenses\.adobe\.com", "https://0.0.0.0")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "https://0.0.0.0") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringReplace($sData, "ENTITLEMENT_STATUS:{TRIAL:""TRIAL"",SUBSCRIPTION:""SUBSCRIPTION""", "ENTITLEMENT_STATUS:{TRIAL:""SUBSCRIPTION"",SUBSCRIPTION:""SUBSCRIPTION""")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "ENTITLEMENT_STATUS:{TRIAL:""SUBSCRIPTION""") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringReplace($sData, "setEntitlementStatus(t){e.entitlementStatus=t,", "setEntitlementStatus(t){e.entitlementStatus=""SUBSCRIPTION"",")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "setEntitlementStatus(t){e.entitlementStatus=""SUBSCRIPTION"",") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringRegExpReplace($sData, "(appEntitlementStatus:[^']*?)'DENIED'", "$1'SUBSCRIPTION'")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringRegExp($sData, "appEntitlementStatus:[^']*?'SUBSCRIPTION'") Then
			$iAlready += 1
		EndIf
		$iTotal += 1
		$sBefore = $sData
		$sData = StringReplace($sData, "return profile ? profile.appEntitlementStatus : ''", "return profile ? 'SUBSCRIPTION' : ''")
		If $sData <> $sBefore Then
			$iApplied += 1
		ElseIf StringInStr($sData, "return profile ? 'SUBSCRIPTION' : ''") Then
			$iAlready += 1
		EndIf
	EndIf
	If $iTotal > 0 Then
		Local $iNotApplicable = $iTotal - $iApplied - $iAlready
	EndIf
	If $iApplied = 0 Then
		If $iAlready > 0 Then Return 2
		Return 0
	EndIf
	FileSetAttrib($sFilePath, "-RHS")
	Local $sBak = $sFilePath & ".bak"
	If FileExists($sBak) Then
		Local $iBakVerdict = _VerifyBackupAgainstLedger($sFilePath, $sBak)
		If $iBakVerdict = 1 Then
			FileDelete($sFilePath)
		Else
			If $iBakVerdict = 0 Then
				LogWrite(1, ".bak hash mismatched ledger; replacing .bak: " & $sFileName)
			EndIf
			FileDelete($sBak)
			FileMove($sFilePath, $sBak)
		EndIf
	Else
		FileMove($sFilePath, $sBak)
	EndIf
	Local $hWrite = FileOpen($sFilePath, 18)
	If $hWrite = -1 Then
		LogWrite(1, "UXP patch write failed (access denied?): " & $sFileName)
		If FileExists($sFilePath) Then FileDelete($sFilePath)
		If Not FileMove($sBak, $sFilePath, $FC_OVERWRITE) Then
			LogWrite(1, "Rollback also failed; original preserved at: " & $sBak)
		EndIf
		Return 0
	EndIf
	FileWrite($hWrite, Binary($sData))
	FileClose($hWrite)
	Local $sMD5Orig = "", $sMD5New = ""
	If $g_bCryptActive Then
		$sMD5Orig = StringTrimLeft(String(_Crypt_HashFile($sBak, $CALG_MD5)), 2)
		$sMD5New = StringTrimLeft(String(_Crypt_HashFile($sFilePath, $CALG_MD5)), 2)
	EndIf
	_QueueStateWrite($sFilePath, "", $sMD5Orig, $sMD5New, "Patched")
	Return 1
EndFunc

Func _AutoUnpackIfRuntimeInstaller($sFilePath)
	Local $bIsAE = StringRegExp($sFilePath, "(?i)\\Adobe After Effects [^\\]+\\")
	Local $bIsPPro = StringRegExp($sFilePath, "(?i)\\Adobe Premiere Pro [^\\]+\\")
	If Not ($bIsAE Or $bIsPPro) Then Return True

	Local $aRootMatch = StringRegExp($sFilePath, "(?i)^(.*?\\Adobe (?:After Effects|Premiere Pro)[^\\]*\\)", 1)
	If IsArray($aRootMatch) Then
		Local $sRoot = $aRootMatch[0]
		Local $sExe = ""
		If $bIsAE Then
			If FileExists($sRoot & "Support Files\AfterFX.exe") Then
				$sExe = $sRoot & "Support Files\AfterFX.exe"
			ElseIf FileExists($sRoot & "AfterFX.exe") Then
				$sExe = $sRoot & "AfterFX.exe"
			ElseIf FileExists($sRoot & "Support Files\AfterFX (Beta).exe") Then
				$sExe = $sRoot & "Support Files\AfterFX (Beta).exe"
			ElseIf FileExists($sRoot & "AfterFX (Beta).exe") Then
				$sExe = $sRoot & "AfterFX (Beta).exe"
			EndIf
		Else
			If FileExists($sRoot & "Adobe Premiere Pro.exe") Then
				$sExe = $sRoot & "Adobe Premiere Pro.exe"
			ElseIf FileExists($sRoot & "Adobe Premiere Pro (Beta).exe") Then
				$sExe = $sRoot & "Adobe Premiere Pro (Beta).exe"
			EndIf
		EndIf
		If $sExe <> "" Then
			Local $aVer = _GetAfterFXVersion($sExe)
			Local $sExeNameOnly = StringRegExpReplace($sExe, "^.*\\", "")
			LogWrite(1, "Auto-unpack version check: " & $sExeNameOnly & " = v" & $aVer[0] & "." & $aVer[1])
			If ($aVer[0] = 26 And $aVer[1] >= 3) Or $aVer[0] > 26 Then
				LogWrite(1, "Auto-unpack skipped: app v" & $aVer[0] & "." & $aVer[1] & " - not required for v26.3+")
				Return True
			EndIf
		Else
			LogWrite(1, "Auto-unpack version check: could not locate app exe in " & $sRoot & " - defaulting to unpack")
		EndIf
	EndIf

	If Not FileExists($sFilePath) Then
		Return False
	EndIf

	If Not IsUPXPacked($sFilePath) Then
		LogWrite(1, "Auto-unpacked failed - file already unpacked; moving on to patching")
		Return True
	EndIf

	Local $upxPath = @ScriptDir & "\upx.exe"
	If Not FileExists($upxPath) Then
		FileInstall("upx.exe", $upxPath, 1)
		If Not FileExists($upxPath) Then
			LogWrite(1, "Auto-unpack failed: upx.exe could not be extracted.")
			Return False
		EndIf
	EndIf

	If Not PatchUPXHeader($sFilePath) Then
		LogWrite(1, "Auto-unpack failed: UPX header patch step failed.")
		Return False
	EndIf

	Local $iResult = RunWait('"' & $upxPath & '" -d "' & $sFilePath & '"', "", @SW_HIDE)

	If $iResult = 0 Then
		If FileExists($sFilePath & ".bak") Then FileDelete($sFilePath & ".bak")
		LogWrite(1, "Auto-unpack succeeded - file unpacked; moving on to patching")
		Return True
	ElseIf $iResult = 2 Then
		If FileExists($sFilePath & ".bak") Then FileDelete($sFilePath & ".bak")
		LogWrite(1, "Auto-unpacked failed - file already unpacked; moving on to patching")
		Return True
	Else
		LogWrite(1, "Critical Error - UPX failed with code " & $iResult)
		If FileExists($sFilePath & ".bak") Then
			FileCopy($sFilePath & ".bak", $sFilePath, 1)
			FileDelete($sFilePath & ".bak")
		EndIf
		Return False
	EndIf
EndFunc

Func _PatchStatesSetupDone()
	Return _CreateNewWasRun() Or _ReconcileWasRun()
EndFunc

Func _AppsBar_Dispatch($idMsg)
	If $idMsg = 0 Then Return False

	If $idMsg = $GUI_EVENT_CLOSE And $g_hAppsBar <> 0 And WinActive($g_hAppsBar) Then
		GUISetState(@SW_HIDE, $g_hAppsBar)
		Return True
	EndIf

	If $idMsg = $g_idAppsBarMinBtn Then
		GUISetState(@SW_MINIMIZE, $MyhGUI)
		If $g_hAppsBar <> 0 Then GUISetState(@SW_SHOWNOACTIVATE, $g_hAppsBar)
		Return True
	EndIf

	If $idMsg = $g_idAppsBarConfigBtn Then
		_ShowToolbarConfigDialog()
		Return True
	EndIf

	For $i = 0 To UBound($g_aAppsBarBtns) - 1
		If $idMsg = $g_aAppsBarBtns[$i][0] Then
			Local $sExe = $g_aAppsBarBtns[$i][1]
			If FileExists($sExe) Then
				_LaunchApp($sExe)
				MemoWrite(@CRLF & "Launched: " & StringRegExpReplace($sExe, "^.*\\", ""))
				LogWrite(1, "AppsBar: launched -> " & $sExe)
			Else
				MemoWrite(@CRLF & "App exe not found (rescan may help): " & $sExe)
				LogWrite(1, "AppsBar: exe missing -> " & $sExe)
			EndIf
			Return True
		EndIf
	Next
	Return False
EndFunc

Func FindRuntimeInstallerFiles()
	If Not FileExists($MyDefPath) Or Not StringInStr(FileGetAttrib($MyDefPath), "D") Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("Error: Invalid Path: " & $MyDefPath)
		LogWrite(1, "Error: Invalid Path: " & $MyDefPath)
		Local $empty[0]
		ToggleLog(1)
		Return $empty
	EndIf

	Local $tRuntimePaths = IniReadSection($sINIPath, "RuntimeInstallers")
	Local $dllPaths[0]

	If @error Or $tRuntimePaths[0][0] = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		Local $sWhy = _ConfigHealthProblem()
		If $sWhy = "" Then $sWhy = "The [RuntimeInstallers] section is missing or empty in config.ini."
		MemoWrite("Runtime installers: " & $sWhy)
		LogWrite(1, "Runtime installers: " & StringReplace($sWhy, @CRLF, " "))
		Local $empty[0]
		ToggleLog(1)
		Return $empty
	EndIf

	ReDim $dllPaths[$tRuntimePaths[0][0]]
	For $i = 1 To $tRuntimePaths[0][0]
		Local $relativePath = StringReplace($tRuntimePaths[$i][1], '"', "")
		If StringLeft($relativePath, 1) = "\" Then $relativePath = StringTrimLeft($relativePath, 1)
		$dllPaths[$i - 1] = StringRegExpReplace($MyDefPath & "\" & $relativePath, "\\\\+", "\\")
	Next

	Local $foundFiles[0]
	For $basePath In $dllPaths
		If StringStripWS($basePath, 3) = "" Then ContinueLoop
		Local $pathParts = StringSplit($basePath, "\", 1)
		Local $searchDir = ""
		For $i = 1 To $pathParts[0] - 1
			If StringInStr($pathParts[$i], "*") Then
				$searchDir = StringTrimRight($searchDir, 1)
				Local $searchPattern = StringReplace($pathParts[$i], "*", "*")
				Local $subPath = StringMid($basePath, StringInStr($basePath, $pathParts[$i]) + StringLen($pathParts[$i]))
				Local $HSEARCH = FileFindFirstFile($searchDir & "\" & $searchPattern)
				If $HSEARCH = -1 Then
					ContinueLoop
				EndIf
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
				$searchDir &= $pathParts[$i] & "\"
			EndIf
		Next

		If Not StringInStr($basePath, "*") Then
			If FileExists($basePath) And StringStripWS($basePath, 3) <> "" Then
				_ArrayAdd($foundFiles, $basePath)
			EndIf
		EndIf
	Next

	If UBound($foundFiles) > 0 Then
		$foundFiles = _ArrayUnique($foundFiles, 0, 0, 0, 0)
	EndIf

	Return $foundFiles
EndFunc

Func UnpackRuntimeInstallers()
	MemoWrite("Scanning for RuntimeInstaller.dll files...")
	Local $foundFiles = FindRuntimeInstallerFiles()

	If UBound($foundFiles) = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("No file(s) found at: " & $MyDefPath)
		LogWrite(1, "No file(s) found at: " & $MyDefPath)
		ToggleLog(1)
		Return
	EndIf

	Local $selectedFiles = RuntimeDllSelectionGUI($foundFiles, "Unpack")

	If Not IsArray($selectedFiles) Or UBound($selectedFiles) = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("No RuntimeInstaller.dll files selected to unpack.")
		LogWrite(1, "No files selected to unpack.")
		ToggleLog(1)
		Return
	EndIf

	Local $upxPath = @ScriptDir & "\upx.exe"
	If Not FileExists($upxPath) Then
		FileInstall("upx.exe", $upxPath, 1)
		If Not FileExists($upxPath) Then
			_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
			MemoWrite("Error: Failed to extract upx.exe to " & $upxPath)
			LogWrite(1, "Error: Failed to extract upx.exe.")
			ToggleLog(1)
			Return
		EndIf
	EndIf

	MemoWrite("Unpacking " & UBound($selectedFiles) & " file(s)...")
	LogWrite(1, "Unpacking " & UBound($selectedFiles) & " file(s):")
	Local $successCount = 0

	For $file In $selectedFiles
		$file = StringStripWS($file, 3)
		If $file = "" Or Not FileExists($file) Then
			MemoWrite("Skipping invalid or missing file: " & $file)
			LogWrite(1, "Skipping invalid or missing file: " & $file)
			ContinueLoop
		EndIf

		LogWrite(1, "Processing: " & $file)

		If Not IsUPXPacked($file) Then
			MemoWrite("Skipped: " & $file & " is not a UPX-packed file.")
			LogWrite(1, "Skipped: " & $file & " is not a UPX-packed file.")
			ContinueLoop
		EndIf

		If Not PatchUPXHeader($file) Then
			MemoWrite("Failed to patch UPX headers for: " & $file)
			LogWrite(1, "Failed to patch UPX headers for: " & $file)
			ContinueLoop
		EndIf

		Local $iResult = RunWait('"' & $upxPath & '" -d "' & $file & '"', "", @SW_HIDE)
		If $iResult = 0 Then
			MemoWrite("Successfully unpacked: " & $file)
			LogWrite(1, "Successfully unpacked: " & $file)
			$successCount += 1
			Local $sBackupPath = $file & ".bak"
			If FileExists($sBackupPath) Then
				FileDelete($sBackupPath)
			EndIf
		Else
			MemoWrite("Failed to unpack: " & $file & " (UPX error code: " & $iResult & ")")
			LogWrite(1, "Failed to unpack: " & $file & " (UPX error code: " & $iResult & ")")
			Local $sBackupPath = $file & ".bak"
			If FileExists($sBackupPath) Then
				FileCopy($sBackupPath, $file, 1)
				FileDelete($sBackupPath)
				MemoWrite("Restored original file from backup: " & $file)
				LogWrite(1, "Restored original file from backup: " & $file)
			EndIf
		EndIf
	Next

	If FileExists($upxPath) Then
		If FileDelete($upxPath) Then
			MemoWrite("Deleted upx.exe from " & $upxPath & ".")
		Else
			MemoWrite("Warning: Failed to delete upx.exe from " & $upxPath & ".")
			LogWrite(1, "Warning: Failed to delete upx.exe from " & $upxPath & ".")
		EndIf
	EndIf

	MemoWrite("Unpack completed. Successfully unpacked " & $successCount & " file(s).")
	LogWrite(1, "Unpack process completed.")

	If $successCount > 0 Then
		LogWrite(1, $successCount & " file(s) successfully unpacked and can now be patched.")
	EndIf

	ToggleLog(1)
EndFunc

Func RuntimeDllSelectionGUI($foundFiles, $operation)
	If Not FileExists($MyDefPath) Or Not StringInStr(FileGetAttrib($MyDefPath), "D") Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("Error: Invalid Path: " & $MyDefPath)
		LogWrite(1, "Error: Invalid Path: " & $MyDefPath)
		ToggleLog(1)
		Return ""
	EndIf
	If UBound($foundFiles) = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("No RuntimeInstaller.dll files found to unpack.")
		LogWrite(1, "No RuntimeInstaller.dll files found to unpack.")
		ToggleLog(1)
		Return ""
	EndIf

	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 500) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 400) / 2
	Local $hGUI = GUICreate("Unpack RuntimeInstaller", 500, 400, $iPopupX, $iPopupY)
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
		Local $fileClean = StringRegExpReplace($file, "\\\\+", "\\")
		Local $fileParts = StringSplit($fileClean, "\", 1)
		Local $appName = "Unknown"
		If $fileParts[0] >= $defPathDepth + 1 Then
			$appName = $fileParts[$defPathDepth + 1]
		Else
			LogWrite(1, "Warning: Short path used in config, using Unknown for: " & $fileClean)
		EndIf
		If Not $appNodes.Exists($appName) Then
			Local $hAppNode = GUICtrlCreateTreeViewItem($appName, $hTreeView)
			$appNodes($appName) = $hAppNode
			_GUICtrlTreeView_SetChecked($hTreeView, $hAppNode, False)
		EndIf
		Local $hItem = GUICtrlCreateTreeViewItem($fileClean, $appNodes($appName))
		_GUICtrlTreeView_SetChecked($hTreeView, $hItem, False)
	Next

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
				MemoWrite("RuntimeInstaller unpacking cancelled.")
				LogWrite(1, "RuntimeInstaller unpacking cancelled.")
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
				Local $selectedFiles[0]
				Local $hItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
				While $hItem <> 0
					Local $itemText = _GUICtrlTreeView_GetText($hTreeView, $hItem)
					Local $isChecked = _GUICtrlTreeView_GetChecked($hTreeView, $hItem)
					If $isChecked And StringInStr($itemText, "RuntimeInstaller.dll") Then
						_ArrayAdd($selectedFiles, $itemText)
					EndIf
					$hItem = _GUICtrlTreeView_GetNext($hTreeView, $hItem)
				WEnd
				GUIDelete($hGUI)
				If UBound($selectedFiles) = 0 Then
					_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
					MemoWrite("No RuntimeInstaller.dll files selected to unpack.")
					LogWrite(1, "No RuntimeInstaller.dll files selected to unpack.")
					ToggleLog(1)
					Return ""
				EndIf
				_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
				Return $selectedFiles
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

Func _FinalisePatchRun()
	_RefreshLog()
	_ReloadAdobeNow()
	_SuppressCCTutorials()
	_LogBetaRunNotice()
	_LogLightroomCloudNotice()
	_RefreshLog()
EndFunc

