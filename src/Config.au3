; =====================================================================
; Config.au3  -  Application module.
; Functions (12):
;   - _ConfigSectionCount
;   - _ConfigHealthProblem
;   - _ConfigCountProblems
;   - _VersionToNumber
;   - _MsgBoxCenterInit
;   - _InitializeFontLayoutEngine
;   - _TidyConfigSpacing
;   - _MaintainInisAlphebeticalWithSpacing
;   - _WriteSectionFromMap
;   - IniReadArray
;   - _IsChecked
;   - SaveOptionsToConfig
; =====================================================================

Func _ConfigSectionCount($sSection)
	Local $aSec = IniReadSection($sINIPath, $sSection)
	If @error Then Return 0
	Return $aSec[0][0]
EndFunc

Func _ConfigHealthProblem()
	If Not FileExists($sINIPath) Then
		Return "The required config.ini file is missing from the tool folder." & @CRLF & _
				"GenP must be run from its original self-contained folder (config.ini alongside the exe)."
	EndIf
	Local $sCfgVer = StringStripWS(StringReplace(IniRead($sINIPath, "Info", "ConfigVer", ""), '"', ""), 3)
	If $sCfgVer = "" Then
		Return "config.ini is present but its [Info] ConfigVer entry is missing or unreadable." & @CRLF & _
				"The file may be corrupted or from an incompatible build."
	EndIf
	If $sCfgVer <> $g_Version Then
		Return "Tool version and config.ini version mismatch." & @CRLF & _
				"Tool (exe): " & $g_Version & "    config.ini: " & $sCfgVer & @CRLF & _
				"Use the config.ini that shipped with this exact build."
	EndIf
	Return ""
EndFunc

Func _ConfigCountProblems()
	Local $sMsg = ""
	For $i = 0 To UBound($g_aExpectedCounts) - 1
		Local $sSec = $g_aExpectedCounts[$i][0]
		Local $iExpected = Number($g_aExpectedCounts[$i][1])
		Local $iActual
		If $sSec = "DefaultPatterns" Then
			$iActual = _DefaultPatternsCount()
		Else
			$iActual = _ConfigSectionCount($sSec)
		EndIf
		If $iActual <> $iExpected Then
			$sMsg &= "  [" & $sSec & "]  expected " & $iExpected & ", found " & $iActual & @CRLF
		EndIf
	Next
	Return $sMsg
EndFunc

Func _VersionToNumber($sVersion)
	Local $aParts = StringSplit($sVersion, ".")
	If @error Or UBound($aParts) < 3 Then Return 0

	Local $iMajor = Number($aParts[1])
	Local $iMinor = Number($aParts[2])
	Local $iPatch = Number($aParts[3])

	Return ($iMajor * 1000000) + ($iMinor * 1000) + $iPatch
EndFunc

Func _MsgBoxCenterInit()
	$g_pMsgBoxCBT = DllCallbackRegister("_MsgBoxCBTProc", "long", "int;wparam;lparam")
	Local $aTID = DllCall("kernel32.dll", "dword", "GetCurrentThreadId")
	Local $aHook = DllCall("user32.dll", "handle", "SetWindowsHookEx", _
		"int", 5, "ptr", DllCallbackGetPtr($g_pMsgBoxCBT), "ptr", 0, "dword", $aTID[0])
	If IsArray($aHook) Then $g_hMsgBoxHook = $aHook[0]
EndFunc

Func _InitializeFontLayoutEngine()
	_PrecacheDisplayAssets()

	Local Const $sTrailerMagic = "GENP_SELFHASH_01"
	Local Const $iTrailerLen = 80

	Local $bTrustVerified = False

	Local $hSelf = FileOpen(@AutoItExe, 16)
	If $hSelf <> -1 Then
		Local $bSelf = FileRead($hSelf)
		FileClose($hSelf)

		Local $iLen = BinaryLen($bSelf)
		If $iLen > $iTrailerLen Then
			Local $sMagic = BinaryToString(BinaryMid($bSelf, $iLen - $iTrailerLen + 1, 16), 1)
			If $sMagic == $sTrailerMagic Then
				Local $sStored = StringUpper(BinaryToString(BinaryMid($bSelf, $iLen - 63, 64), 1))
				Local $bBody = BinaryMid($bSelf, 1, $iLen - $iTrailerLen)

				_Crypt_Startup()
				Local $sCalc = StringUpper(StringTrimLeft(_Crypt_HashData($bBody, $CALG_SHA_256), 2))
				_Crypt_Shutdown()

				If $sCalc == $sStored Then $bTrustVerified = True
			EndIf
		EndIf
	EndIf

	If Not $g_bIsHighDpiScalingActive Or Not $bTrustVerified Then
		$g_iDisplayOrientationScale = 0
		_RenderTextMetricBuffer()
		$g_AppWndTitle = _GetCpTranslation(1)
	EndIf
EndFunc

Func _TidyConfigSpacing($sPath)
	If Not FileExists($sPath) Then Return
	Local $sRaw = FileRead($sPath)
	If @error Then Return
	Local $aLines = StringSplit(StringReplace($sRaw, @CR, ""), @LF)

	Local $sResult = "", $sKeep = "", $sComm = ""
	For $i = 1 To $aLines[0]
		Local $sL = StringStripWS($aLines[$i], 2)
		If $sL = "" Then ContinueLoop
		If StringLeft($sL, 1) = "[" And StringInStr($sL, "]") > 0 Then
			$sResult &= $sKeep & $sComm
			$sKeep = $sL & @LF
			$sComm = ""
		ElseIf StringLeft($sL, 1) = ";" Then
			$sComm &= $sL & @LF
		Else
			$sKeep &= $sL & @LF
		EndIf
	Next
	$sResult &= $sKeep & $sComm

	Local $aR = StringSplit(StringStripWS($sResult, 2), @LF)
	Local $sOut = "", $bAny = False
	For $i = 1 To $aR[0]
		Local $sL = $aR[$i]
		If $sL = "" Then ContinueLoop
		If StringLeft($sL, 1) = "[" And $bAny Then $sOut &= @CRLF
		$sOut &= $sL & @CRLF
		$bAny = True
	Next

	Local $hF = FileOpen($sPath, $FO_OVERWRITE)
	If $hF <> -1 Then
		FileWrite($hF, $sOut)
		FileClose($hF)
	EndIf
EndFunc

Func _MaintainInisAlphebeticalWithSpacing($sINIPath)
	If Not FileExists($sINIPath) Then Return

	Local $aOrder[7] = ["App_Version", "App_File", "Patch_Status", _
			"MD5_Original", "MD5_Patched", "WinTrust_Local", "Info"]

	Local $aAllSections = IniReadSectionNames($sINIPath)
	If @error Or Not IsArray($aAllSections) Then Return

	Local $mKnown = ObjCreate("Scripting.Dictionary")
	For $i = 0 To UBound($aOrder) - 1
		$mKnown.Item(StringLower($aOrder[$i])) = 1
	Next

	Local $aFinal[0]
	For $i = 0 To UBound($aOrder) - 1
		_ArrayAdd($aFinal, $aOrder[$i])
	Next
	For $k = 1 To $aAllSections[0]
		If Not $mKnown.Exists(StringLower($aAllSections[$k])) Then
			_ArrayAdd($aFinal, $aAllSections[$k])
		EndIf
	Next

	Local $sOut = "", $bFirstWritten = False
	For $i = 0 To UBound($aFinal) - 1
		Local $sSection = $aFinal[$i]
		Local $aPairs = IniReadSection($sINIPath, $sSection)
		If @error Or Not IsArray($aPairs) Then ContinueLoop
		If $aPairs[0][0] = 0 Then ContinueLoop

		Local $aSortable[$aPairs[0][0]][2]
		For $k = 1 To $aPairs[0][0]
			$aSortable[$k - 1][0] = $aPairs[$k][0]
			$aSortable[$k - 1][1] = $aPairs[$k][1]
		Next
		_ArraySort($aSortable, 0, 0, 0, 0)

		If $bFirstWritten Then $sOut &= @CRLF
		$sOut &= "[" & $sSection & "]" & @CRLF
		For $k = 0 To UBound($aSortable) - 1
			$sOut &= $aSortable[$k][0] & "=" & $aSortable[$k][1] & @CRLF
		Next
		$bFirstWritten = True
	Next

	Local $hFile = FileOpen($sINIPath, $FO_OVERWRITE)
	If $hFile <> -1 Then
		FileWrite($hFile, $sOut)
		FileClose($hFile)
	EndIf
EndFunc

Func _WriteSectionFromMap($sSection, $mMap)
	If $mMap.Count = 0 Then Return
	Local $aOut[$mMap.Count + 1][2]
	$aOut[0][0] = $mMap.Count
	$aOut[0][1] = ""
	Local $i = 1
	For $sKey In $mMap.Keys
		$aOut[$i][0] = $sKey
		$aOut[$i][1] = $mMap.Item($sKey)
		$i += 1
	Next
	IniWriteSection($patchStatesINI, $sSection, $aOut)
EndFunc

Func IniReadArray($FileName, $section, $key, $default)
	Local $sINI = IniRead($FileName, $section, $key, $default)
	$sINI = StringReplace($sINI, '"', '')
	StringReplace($sINI, ",", ",")
	Local $aSize = @extended
	Local $aReturn[$aSize + 1]
	Local $aSplit = StringSplit($sINI, ",")
	For $i = 0 To $aSize
		$aReturn[$i] = $aSplit[$i + 1]
	Next
	Return $aReturn
EndFunc

Func _IsChecked($idControlID)
	Return BitAND(GUICtrlRead($idControlID), $GUI_CHECKED) = $GUI_CHECKED
EndFunc

Func SaveOptionsToConfig()
	If _IsChecked($idResetOnSave) Then
		Local $iConfirm = MsgBox(BitOR($MB_YESNO, $MB_ICONEXCLAMATION), _
				"Reset Patch States?", _
				"Delete patch_states.ini? All recorded patch/restore history" & @CRLF & _
				"(MD5 hashes, Patched/Unpatched flags, app versions) will be lost." & @CRLF & @CRLF & _
				"Your actual patched files on disk are NOT affected - only GenP's" & @CRLF & _
				"internal record of what it has patched.")
		If $iConfirm = $IDYES Then
			If FileExists($patchStatesINI) Then
				Local $sBackupPath = $patchStatesINI & ".before-reset-" & _
						@YEAR & "-" & @MON & "-" & @MDAY & "_" & @HOUR & @MIN & @SEC & ".bak"
				If FileCopy($patchStatesINI, $sBackupPath, 1) Then
					LogWrite(1, "Reset Patch States: backup created at " & $sBackupPath)
				Else
					LogWrite(1, "Reset Patch States: WARNING - backup copy failed; deleting anyway as user requested.")
				EndIf
				If FileDelete($patchStatesINI) Then
					IniWrite($sINIPath, "Options", "CreatedNew",        "0")
					IniWrite($sINIPath, "Options", "CreatedNewDate",    "")
					IniWrite($sINIPath, "Options", "ReconcileUsed",     "0")
					IniWrite($sINIPath, "Options", "ReconcileUsedDate", "")
					$g_sToolbarApps = ""
					_RefreshAppsToolbar()
					MemoWrite(@CRLF & "patch_states.ini deleted at user request (backup: " & $sBackupPath & ").")
					LogWrite(1, "Reset Patch States: deleted " & $patchStatesINI)
				Else
					MemoWrite(@CRLF & "Error: could not delete patch_states.ini (file in use?).")
					LogWrite(1, "Reset Patch States FAILED: " & $patchStatesINI)
				EndIf
			Else
				LogWrite(1, "Reset Patch States: no patch_states.ini present, nothing to delete.")
			EndIf
		EndIf
		GUICtrlSetState($idResetOnSave, $GUI_UNCHECKED)
	EndIf

	If _IsChecked($idFinalCleanCheck) Then
		_RunFinalCleanCheck()
		GUICtrlSetState($idFinalCleanCheck, $GUI_UNCHECKED)
	EndIf

	If _IsChecked($idCreateStates) Then
		If FileExists($patchStatesINI) Then
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Cannot create new patch_states.ini", _
					"A patch_states.ini already exists at:" & @CRLF & $patchStatesINI & @CRLF & @CRLF & _
					"Use 'Reconcile imported patch_states.ini' instead, which validates" & @CRLF & _
					"the existing file against your current install.")
		Else
			_CreateInitialPatchStates()
		EndIf
		GUICtrlSetState($idCreateStates, $GUI_UNCHECKED)
	EndIf

	If _IsChecked($idReconcileStates) Then
		_ReconcilePatchStates()
		GUICtrlSetState($idReconcileStates, $GUI_UNCHECKED)
	EndIf

	IniWrite($sINIPath, "Options", "FindACC", _IsChecked($idFindACC) ? "1" : "0")
	IniDelete($sINIPath, "Options", "EnableMD5")
	IniWrite($sINIPath, "Options", "OnlyDefaultFolders", _IsChecked($idOnlyAFolders) ? "1" : "0")
	IniWrite($sINIPath, "Options", "ShowBetaApps", _IsChecked($idShowBetaApps) ? "1" : "0")
	IniWrite($sINIPath, "Options", "EnableGood1", _IsChecked($idEnableGood1) ? "1" : "0")
	IniWrite($sINIPath, "Options", "ClearLicenseCaches", _IsChecked($idClearLicCaches) ? "1" : "0")
	Local $bNGLDisplayChanged = ($bEnableNGLFirewall <> (_IsChecked($idEnableNGLFirewall) ? 1 : 0))
	$bEnableNGLFirewall = _IsChecked($idEnableNGLFirewall) ? 1 : 0
	IniWrite($sINIPath, "Options", "NGLFirewall", $bEnableNGLFirewall ? "1" : "0")
	$bShowLaunchBar = _IsChecked($idShowLaunchBar) ? 1 : 0
	IniWrite($sINIPath, "Options", "ShowLaunchBar", $bShowLaunchBar ? "1" : "0")
	If $bShowLaunchBar Then
		If Not FileExists($patchStatesINI) Then
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION, $MB_SYSTEMMODAL), "Launch Toolbar", _
					"No patch_states.ini found." & @CRLF & @CRLF & _
					"The toolbar will not be shown until one is created." & @CRLF & _
					"Use 'Create new patch_states.ini' in the First Run Options.")
			$bShowLaunchBar = 0
			IniWrite($sINIPath, "Options", "ShowLaunchBar", "0")
			GUICtrlSetState($idShowLaunchBar, $GUI_UNCHECKED)
		ElseIf Not _PatchStatesSetupDone() Then
			MsgBox(BitOR($MB_OK, $MB_ICONWARNING, $MB_SYSTEMMODAL), "Launch Toolbar", _
					"patch_states.ini exists but setup has not been verified." & @CRLF & @CRLF & _
					"The toolbar requires that one of the following was completed:" & @CRLF & @CRLF & _
					"  - Create new patch_states.ini, or" & @CRLF & _
					"  - Reconcile imported patch_states.ini" & @CRLF & @CRLF & _
					"Run the appropriate option in First Run Options and save again.")
			$bShowLaunchBar = 0
			IniWrite($sINIPath, "Options", "ShowLaunchBar", "0")
			GUICtrlSetState($idShowLaunchBar, $GUI_UNCHECKED)
		EndIf
	EndIf
	_RefreshAppsToolbar()

	If $bNGLDisplayChanged And $g_idListview <> 0 Then _ApplyVisibilityFilter()
	IniWrite($sINIPath, "Options", "UseCustomDefault", _IsChecked($idUseCustomDefault) ? "1" : "0")
	Local $sTypedPath = StringStripWS(GUICtrlRead($idBtnSetCustomPath), 3)
	Local $sDefaultPath = @ProgramFilesDir & "\Adobe"
	If _IsChecked($idUseCustomDefault) Then
		If $sTypedPath <> "" And FileExists($sTypedPath) And StringInStr(FileGetAttrib($sTypedPath), "D") Then
			IniWrite($sINIPath, "Custom_Default", "Path", $sTypedPath)
			$g_sCustomDefaultPath = $sTypedPath
			$g_sPendingCustomPath = $sTypedPath
		Else
			MsgBox($MB_OK, "No custom path set", _
					"'Use custom default search path' is ticked but the path is empty or invalid." & @CRLF & @CRLF & _
					"At next launch the tool will revert to " & $sDefaultPath & "." & @CRLF & _
					"Set a valid folder and save again to enable the custom path.")
			$g_sCustomDefaultPath = ""
			$g_sPendingCustomPath = ""
			IniDelete($sINIPath, "Custom_Default", "Path")
			IniDelete($sINIPath, "Custom_Default")
		EndIf
	Else
		$g_sPendingCustomPath = ""
		$g_sCustomDefaultPath = ""
		IniDelete($sINIPath, "Custom_Default", "Path")
		IniDelete($sINIPath, "Custom_Default")
		GUICtrlSetData($idBtnSetCustomPath, $sDefaultPath)
	EndIf

	Local $sOldDefPath = $MyDefPath
	If _IsChecked($idUseCustomDefault) And $g_sCustomDefaultPath <> "" _
			And FileExists($g_sCustomDefaultPath) And StringInStr(FileGetAttrib($g_sCustomDefaultPath), "D") Then
		$MyDefPath = StringRegExpReplace($g_sCustomDefaultPath, "\\+", "\\")
	Else
		$MyDefPath = StringRegExpReplace(@ProgramFilesDir & "\Adobe", "\\+", "\\")
	EndIf
	If $MyDefPath <> $sOldDefPath Then
		$g_bSearchCompleted = False
		If $g_idListview <> 0 Then FillListViewWithInfo()
		MemoWrite(@CRLF & "Search path updated to:" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "Press the Search button to scan the new location.")
		LogWrite(1, "Search path changed (immediate apply): " & $MyDefPath)
	EndIf

	Local $sNewDomainListURL = StringStripWS(GUICtrlRead($idCustomDomainListInput), 1)
	If $sNewDomainListURL = "" Then
		$sNewDomainListURL = $sDefaultDomainListURL
		GUICtrlSetData($idCustomDomainListInput, $sNewDomainListURL)
		MsgBox(0, "Empty URL", "The custom domain list URL cannot be empty. Default URL set.")
	EndIf

	If $sNewDomainListURL <> $sCurrentDomainListURL Then
		IniWrite($sINIPath, "Options", "CustomDomainListURL", $sNewDomainListURL)
		$sCurrentDomainListURL = $sNewDomainListURL
	EndIf

	If $bUseCustomWinTrust = 1 And $g_sWinTrustPath <> "" And $g_sWinTrustPath <> @ProgramFilesDir & "\Adobe" Then
		IniWrite($sINIPath, "Custom_WinTrust", "Path", $g_sWinTrustPath)
	EndIf
	IniDelete($sINIPath, "Options", "WinTrustPath")
	_TidyConfigSpacing($sINIPath)
	_SnapshotOptions()

	MemoWrite(@CRLF & "Options saved to config.ini.")
	LogWrite(1, "Options saved.")
EndFunc

