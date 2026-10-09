; =====================================================================
; DevOverride.au3  -  Application module.
; Functions (21):
;   - _RecordDevOverrideStateToLedger
;   - _SyncWinTrustFromDisk
;   - _HasWinTrustDll
;   - _ScanForWinTrust
;   - _WriteWinTrustImmediate
;   - _RefreshGroupHeadersFromWT
;   - IsUPXPacked
;   - PatchUPXHeader
;   - AddDevOverride
;   - RemoveDevOverride
;   - ManageWinTrust
;   - _GetAfterFXVersion
;   - _IsAEBlockedByVersion
;   - _EvaluateAEBlock
;   - FindTrustEXEs
;   - FindUntrustedEXEs
;   - TrustEXEs
;   - UntrustEXEs
;   - TrustSelectionGUI
;   - ManageDevOverride
;   - OpenWF
; =====================================================================

Func _RecordDevOverrideStateToLedger()
	Local $sRegKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
	Local $iRegVal = RegRead($sRegKey, "DevOverrideEnable")
	Local $sLedgerVal = (Not @error And $iRegVal = 1) ? "1" : "0"
	IniWrite($patchStatesINI, "Info", "DevOverrideEnable", $sLedgerVal)
EndFunc

Func _SyncWinTrustFromDisk()
	If Not IsObj($g_mWinTrustQueue) Then $g_mWinTrustQueue = ObjCreate("Scripting.Dictionary")
	$g_mWinTrustQueue.RemoveAll()

	Local $aExisting = IniReadSection($patchStatesINI, "WinTrust_Local")
	If Not @error And IsArray($aExisting) Then
		For $i = 1 To $aExisting[0][0]
			$g_mWinTrustQueue.Item($aExisting[$i][0]) = $aExisting[$i][1]
		Next
	EndIf

	Local $mRoots = ObjCreate("Scripting.Dictionary")
	Local $iCount = _GUICtrlListView_GetItemCount($idListview)
	For $i = 0 To $iCount - 1
		Local $sPath = _GUICtrlListView_GetItemText($idListview, $i, 1)
		Local $sApp = _GetAppGroupName($sPath)
		If $sApp = "" Then ContinueLoop

		If Not $mRoots.Exists($sApp) Then
			Local $iMark = StringInStr($sPath, "\Adobe\")
			If $iMark > 0 Then
				Local $sAfter = StringMid($sPath, $iMark + 7)
				Local $iSlash = StringInStr($sAfter, "\")
				If $iSlash > 0 Then $mRoots.Item($sApp) = StringLeft($sPath, $iMark + 6 + $iSlash)
			EndIf
		EndIf
	Next

	For $sApp In $mRoots.Keys()
		Local $bTrusted = _HasWinTrustDll($mRoots.Item($sApp))
		$g_mWinTrustQueue.Item($sApp) = $bTrusted ? "1" : "0"
	Next

	_WriteWinTrustImmediate()
EndFunc

Func _HasWinTrustDll($sAppRoot)
	If Not FileExists($sAppRoot) Then Return False

	If FileExists($sAppRoot & "wintrust.dll") Then Return True
	If FileExists($sAppRoot & "Support Files\wintrust.dll") Then Return True
	If FileExists($sAppRoot & "Support Files\Support Files\wintrust.dll") Then Return True
	If FileExists($sAppRoot & "Support Files\Contents\Windows\wintrust.dll") Then Return True

	Return _ScanForWinTrust($sAppRoot, 0, 4)
EndFunc

Func _ScanForWinTrust($sDir, $iDepth, $iMaxDepth)
	If $iDepth > $iMaxDepth Then Return False
	If FileExists($sDir & "wintrust.dll") Then Return True

	Local $hFind = FileFindFirstFile($sDir & "*")
	If $hFind = -1 Then Return False
	Local $bFound = False
	While 1
		Local $sName = FileFindNextFile($hFind)
		If @error Then ExitLoop
		If $sName = "." Or $sName = ".." Then ContinueLoop
		Local $sAttrib = FileGetAttrib($sDir & $sName)
		If Not StringInStr($sAttrib, "D") Then ContinueLoop
		If StringRegExp($sName, "(?i)^(Resources|Locales|Legal|Samples|Presets|Templates|Documentation|Help|ICC Profiles|ICU|Scripts|Configuration|Settings|data|docs|localization|locales)$") Then ContinueLoop
		If _ScanForWinTrust($sDir & $sName & "\", $iDepth + 1, $iMaxDepth) Then
			$bFound = True
			ExitLoop
		EndIf
	WEnd
	FileClose($hFind)
	Return $bFound
EndFunc

Func _WriteWinTrustImmediate()
	If Not IsObj($g_mWinTrustQueue) Or $g_mWinTrustQueue.Count = 0 Then Return
	_WriteSectionFromMap("WinTrust_Local", $g_mWinTrustQueue)
	_MaintainInisAlphebeticalWithSpacing($patchStatesINI)
EndFunc

Func _RefreshGroupHeadersFromWT()
	Local $iCount = _GUICtrlListView_GetGroupCount($idListview)
	If $iCount <= 0 Then Return
	For $iIdx = 0 To UBound($g_aGroupIDs) - 1
		Local $iGid = $g_aGroupIDs[$iIdx]
		Local $aInfo = _GUICtrlListView_GetGroupInfo($idListview, $iGid)
		If Not IsArray($aInfo) Then ContinueLoop
		Local $sHeader = $aInfo[0]
		If $sHeader = "" Then ContinueLoop

		Local $sStripped = StringRegExpReplace($sHeader, "^\[WT\]\s*", "")

		Local $sAppName = StringRegExpReplace($sStripped, "\s*\(v[^)]+\).*$", "")
		$sAppName = StringRegExpReplace($sAppName, "\s*\(\d+\s+file[s]?\)$", "")

		Local $sNewHeader = $sStripped
		If IsObj($g_mWinTrustQueue) And $g_mWinTrustQueue.Exists($sAppName) Then
			If $g_mWinTrustQueue.Item($sAppName) = "1" Then $sNewHeader = "[WT] " & $sStripped
		EndIf

		If $sNewHeader <> $sHeader Then
			_GUICtrlListView_SetGroupInfo($idListview, $iGid, $sNewHeader, $aInfo[1], $LVGS_COLLAPSIBLE)
		EndIf
	Next
EndFunc

Func IsUPXPacked($sFilePath)
	Local $hFile = FileOpen($sFilePath, 16)
	If $hFile = -1 Then
		LogWrite(1, "Error: Failed to open file for UPX check: " & $sFilePath)
		Return False
	EndIf

	Local $bData = FileRead($hFile)
	FileClose($hFile)
	If @error Then
		LogWrite(1, "Error: Failed to read file for UPX check: " & $sFilePath)
		Return False
	EndIf

	Local $sHexData = String($bData)
	If StringInStr($sHexData, "55505821") Or StringInStr($sHexData, "007465787400") Or StringInStr($sHexData, "746578743100") Then
		Return True
	EndIf

	Return False
EndFunc

Func PatchUPXHeader($sFilePath)
	Local Const $sUPX0 = "005550583000"
	Local Const $sUPX1 = "555058310000"

	Local $aCustomHeaders1 = ["007465787400"]
	Local $aCustomHeaders2 = ["746578743100"]

	Local $sBackupPath = $sFilePath & ".bak"
	If Not FileCopy($sFilePath, $sBackupPath, 1) Then
		MemoWrite("Error: Failed to create backup for: " & $sFilePath)
		LogWrite(1, "Error: Failed to create backup for: " & $sFilePath)
		Return False
	EndIf

	Local $hFile = FileOpen($sFilePath, 16)
	If $hFile = -1 Then
		MemoWrite("Error: Failed to open file for patching: " & $sFilePath)
		LogWrite(1, "Error: Failed to open file for patching: " & $sFilePath)
		Return False
	EndIf
	Local $bData = FileRead($hFile)
	FileClose($hFile)
	If @error Then
		MemoWrite("Error: Failed to read file for patching: " & $sFilePath)
		LogWrite(1, "Error: Failed to read file for patching: " & $sFilePath)
		Return False
	EndIf

	Local $sHexData = String($bData)
	Local $bModified = False

	For $sHeader In $aCustomHeaders1
		If StringInStr($sHexData, $sHeader) Then
			$sHexData = StringReplace($sHexData, $sHeader, $sUPX0)
			$bModified = True
			ExitLoop
		EndIf
	Next

	For $sHeader In $aCustomHeaders2
		If StringInStr($sHexData, $sHeader) Then
			$sHexData = StringReplace($sHexData, $sHeader, $sUPX1)
			$bModified = True
			ExitLoop
		EndIf
	Next

	If Not $bModified Then
		MemoWrite("No custom UPX headers found in: " & $sFilePath)
		FileDelete($sBackupPath)
		Return True
	EndIf

	Local $bModifiedData = Binary("0x" & StringMid($sHexData, 3))
	Local $hFileWrite = FileOpen($sFilePath, 18)
	If $hFileWrite = -1 Then
		MemoWrite("Error: Failed to open file for writing: " & $sFilePath)
		LogWrite(1, "Error: Failed to open file for writing: " & $sFilePath)
		FileCopy($sBackupPath, $sFilePath, 1)
		FileDelete($sBackupPath)
		Return False
	EndIf
	FileWrite($hFileWrite, $bModifiedData)
	FileClose($hFileWrite)
	If @error Then
		MemoWrite("Error: Failed to write patched data to: " & $sFilePath)
		LogWrite(1, "Error: Failed to write patched data to: " & $sFilePath)
		FileCopy($sBackupPath, $sFilePath, 1)
		FileDelete($sBackupPath)
		Return False
	EndIf

	MemoWrite("Successfully patched UPX headers in: " & $sFilePath)
	Return True
EndFunc

Func AddDevOverride()
	If Not IsAdmin() Then
		MemoWrite("Error: Administrator rights required to set WinTrust registry keys.")
		LogWrite(1, "Error: Administrator rights required for registry access.")
		Return False
	EndIf

	Local $iIFEO = RegRead($g_sWT_IFEO, "DevOverrideEnable")
	Local $iSxS = RegRead($g_sWT_SxS, "DevOverrideEnable")
	Local $iWT64 = RegRead($g_sWT_WT64, "EnableCertPaddingCheck")
	Local $iWT32 = RegRead($g_sWT_WT32, "EnableCertPaddingCheck")
	If $iIFEO = 1 And $iSxS = 1 And $iWT64 = 0 And $iWT32 = 0 Then
		MemoWrite("WinTrust override already fully enabled across all four keys.")
		LogWrite(1, "All four WinTrust keys already set correctly; no action.")
		IniWrite($patchStatesINI, "Info", "DevOverrideEnable", "1")
		Return True
	EndIf

	Local $iErr = 0, $iFailMask = 0
	If Not RegWrite($g_sWT_IFEO, "DevOverrideEnable", "REG_DWORD", 1) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 1)
	EndIf
	If Not RegWrite($g_sWT_SxS, "DevOverrideEnable", "REG_DWORD", 1) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 2)
	EndIf
	If Not RegWrite($g_sWT_WT64, "EnableCertPaddingCheck", "REG_DWORD", 0) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 4)
	EndIf
	If Not RegWrite($g_sWT_WT32, "EnableCertPaddingCheck", "REG_DWORD", 0) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 8)
	EndIf

	If $iErr > 0 Then
		Local $sFail = ""
		If BitAND($iFailMask, 1) Then $sFail &= "IFEO, "
		If BitAND($iFailMask, 2) Then $sFail &= "SxS, "
		If BitAND($iFailMask, 4) Then $sFail &= "Wintrust64, "
		If BitAND($iFailMask, 8) Then $sFail &= "Wintrust32, "
		$sFail = StringTrimRight($sFail, 2)
		MemoWrite("Error: Failed to write " & $iErr & " of 4 WinTrust keys: " & $sFail)
		LogWrite(1, "WinTrust enable: " & $iErr & " key(s) failed (" & $sFail & "). Check antivirus / permissions.")
		IniWrite($patchStatesINI, "Info", "DevOverrideEnable", "partial")
		Return False
	EndIf

	MemoWrite("Enabled WinTrust override (IFEO + SxS + Wintrust 64/32-bit cert padding check).")
	LogWrite(1, "All four WinTrust override keys set successfully.")
	IniWrite($patchStatesINI, "Info", "DevOverrideEnable", "1")
	ShowRebootPopup()
	Return True
EndFunc

Func RemoveDevOverride()
	If Not IsAdmin() Then
		MemoWrite("Error: Administrator rights required to remove WinTrust registry keys.")
		LogWrite(1, "Error: Administrator rights required for registry access.")
		Return False
	EndIf

	Local $iIFEO = RegRead($g_sWT_IFEO, "DevOverrideEnable")
	Local $iIFEOErr = @error
	Local $iSxS = RegRead($g_sWT_SxS, "DevOverrideEnable")
	Local $iSxSErr = @error
	Local $iWT64 = RegRead($g_sWT_WT64, "EnableCertPaddingCheck")
	Local $iWT64Err = @error
	Local $iWT32 = RegRead($g_sWT_WT32, "EnableCertPaddingCheck")
	Local $iWT32Err = @error

	If ($iIFEOErr <> 0 Or $iIFEO = 0) _
			And ($iSxSErr <> 0 Or $iSxS = 0) _
			And ($iWT64Err <> 0 Or $iWT64 = 1) _
			And ($iWT32Err <> 0 Or $iWT32 = 1) Then
		MemoWrite("WinTrust override already at default state; no action.")
		LogWrite(1, "All four WinTrust keys already restored or absent.")
		IniWrite($patchStatesINI, "Info", "DevOverrideEnable", "0")
		Return True
	EndIf

	Local $iErr = 0, $iFailMask = 0
	If Not RegWrite($g_sWT_IFEO, "DevOverrideEnable", "REG_DWORD", 0) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 1)
	EndIf
	If Not RegWrite($g_sWT_SxS, "DevOverrideEnable", "REG_DWORD", 0) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 2)
	EndIf
	If Not RegWrite($g_sWT_WT64, "EnableCertPaddingCheck", "REG_DWORD", 1) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 4)
	EndIf
	If Not RegWrite($g_sWT_WT32, "EnableCertPaddingCheck", "REG_DWORD", 1) Then
		$iErr += 1
		$iFailMask = BitOR($iFailMask, 8)
	EndIf

	If $iErr > 0 Then
		Local $sFail = ""
		If BitAND($iFailMask, 1) Then $sFail &= "IFEO, "
		If BitAND($iFailMask, 2) Then $sFail &= "SxS, "
		If BitAND($iFailMask, 4) Then $sFail &= "Wintrust64, "
		If BitAND($iFailMask, 8) Then $sFail &= "Wintrust32, "
		$sFail = StringTrimRight($sFail, 2)
		MemoWrite("Error: Failed to restore " & $iErr & " of 4 WinTrust keys: " & $sFail)
		LogWrite(1, "WinTrust restore: " & $iErr & " key(s) failed (" & $sFail & ").")
		IniWrite($patchStatesINI, "Info", "DevOverrideEnable", "partial")
		Return False
	EndIf

	MemoWrite("Disabled WinTrust override; restored default security across all four keys.")
	LogWrite(1, "All four WinTrust keys restored to default.")
	IniWrite($patchStatesINI, "Info", "DevOverrideEnable", "0")
	ShowRebootPopup()
	Return True
EndFunc

Func ManageWinTrust()
	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 300) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 150) / 2
	Local $hGUI = GUICreate("Manage WinTrust", 300, 150, $iPopupX, $iPopupY)
	Local $hTrustButton = GUICtrlCreateButton("Trust", 50, 50, 100, 30)
	Local $hUntrustButton = GUICtrlCreateButton("Untrust", 150, 50, 100, 30)
	Local $hCancelButton = GUICtrlCreateButton("Cancel", 100, 100, 100, 30)
	GUISetState(@SW_SHOW)

	While 1
		Switch GUIGetMsg()
			Case $GUI_EVENT_CLOSE, $hCancelButton
				MemoWrite("WinTrust management cancelled.")
				GUIDelete($hGUI)
				Return
			Case $hTrustButton
				GUIDelete($hGUI)
				TrustEXEs()
				Return
			Case $hUntrustButton
				GUIDelete($hGUI)
				UntrustEXEs()
				Return
		EndSwitch
	WEnd
EndFunc

Func _GetAfterFXVersion($sPathToExe)
	Local $aRet[2] = [0, 0]
	If Not FileExists($sPathToExe) Then Return $aRet
	Local $sVer = FileGetVersion($sPathToExe)
	If @error Or $sVer = "" Or StringRegExp($sVer, "^0\.0\.0\.0?") Then
		$sVer = FileGetVersion($sPathToExe, $FV_PRODUCTVERSION)
		If @error Then $sVer = ""
	EndIf
	If $sVer = "" Then Return $aRet
	Local $aParts = StringSplit($sVer, ".")
	If $aParts[0] >= 2 Then
		$aRet[0] = Number($aParts[1])
		$aRet[1] = Number($aParts[2])
	EndIf
	Return $aRet
EndFunc

Func _IsAEBlockedByVersion($iMajor, $iMinor)
	If $iMajor > 25 Then Return True
	If $iMajor = 25 And $iMinor >= 4 Then Return True
	Return False
EndFunc

Func _EvaluateAEBlock($hTreeView, $hParent, $sAppName)
	If Not StringInStr($sAppName, "After Effects") Then Return False

	Local $sAfterFXPath = ""
	Local $sAnyChildPath = ""
	Local $aChildPaths[0]
	Local $hChild = _GUICtrlTreeView_GetFirstChild($hTreeView, $hParent)
	While $hChild <> 0
		Local $sChildText = _GUICtrlTreeView_GetText($hTreeView, $hChild)
		_ArrayAdd($aChildPaths, $sChildText)
		If $sAnyChildPath = "" Then $sAnyChildPath = $sChildText
		If StringRegExp($sChildText, "(?i)\\AfterFX( \(Beta\))?\.exe$") Then
			$sAfterFXPath = $sChildText
		EndIf
		$hChild = _GUICtrlTreeView_GetNextChild($hTreeView, $hChild)
	WEnd

	If $sAfterFXPath = "" Then
		If $sAnyChildPath <> "" Then
			Local $aMatch = StringRegExp($sAnyChildPath, "(?i)^(.*?\\Adobe After Effects[^\\]*\\)", 1)
			If IsArray($aMatch) Then
				Local $sAERoot = $aMatch[0]
				If FileExists($sAERoot & "Support Files\AfterFX.exe") Then
					$sAfterFXPath = $sAERoot & "Support Files\AfterFX.exe"
				ElseIf FileExists($sAERoot & "AfterFX.exe") Then
					$sAfterFXPath = $sAERoot & "AfterFX.exe"
				ElseIf FileExists($sAERoot & "Support Files\AfterFX (Beta).exe") Then
					$sAfterFXPath = $sAERoot & "Support Files\AfterFX (Beta).exe"
				ElseIf FileExists($sAERoot & "AfterFX (Beta).exe") Then
					$sAfterFXPath = $sAERoot & "AfterFX (Beta).exe"
				EndIf
			EndIf
		EndIf
	EndIf

	Local $aVer[2] = [0, 0]
	If $sAfterFXPath <> "" Then
		$aVer = _GetAfterFXVersion($sAfterFXPath)
	EndIf

	If $aVer[0] = 0 And $aVer[1] = 0 Then
		Local $sIniVer = ""

		$sIniVer = IniRead($patchStatesINI, "App_Version", $sAppName, "")

		If $sIniVer = "" Then
			Local $sStripName = StringRegExpReplace($sAppName, "^(?i)Adobe\s+", "")
			$sIniVer = IniRead($patchStatesINI, "App_Version", $sStripName, "")

			If $sIniVer = "" Then
				Local $sCore = StringRegExpReplace($sStripName, "\s*\(Beta\)", "")
				Local $bIsBeta = StringInStr($sStripName, "(Beta)") > 0
				Local $aSec = IniReadSection($patchStatesINI, "App_Version")
				If IsArray($aSec) Then
					For $k = 1 To $aSec[0][0]
						Local $sKey = $aSec[$k][0]
						If StringRegExp($sKey, "(?i)^" & $sCore & "(\s+\d{4})?(\s*\(Beta\))?$") Then
							Local $bKeyIsBeta = StringInStr($sKey, "(Beta)") > 0
							If $bKeyIsBeta = $bIsBeta Then
								$sIniVer = $aSec[$k][1]
								ExitLoop
							EndIf
						EndIf
					Next
				EndIf
			EndIf
		EndIf

		If $sIniVer <> "" Then
			Local $sIniStripped = StringRegExpReplace($sIniVer, "^v", "")
			Local $aIniParts = StringSplit($sIniStripped, ".")
			If $aIniParts[0] >= 2 Then
				$aVer[0] = Number($aIniParts[1])
				$aVer[1] = Number($aIniParts[2])
				LogWrite(1, "WinTrust: AE version for '" & $sAppName & "' resolved via patch_states.ini fallback: v" & $aVer[0] & "." & $aVer[1])
			EndIf
		EndIf
	EndIf

	If $aVer[0] = 0 And $aVer[1] = 0 Then Return False
	If Not _IsAEBlockedByVersion($aVer[0], $aVer[1]) Then Return False

	Local $sNewLabel = $sAppName & "  (No WinTrust - v25.4+)"
	_GUICtrlTreeView_SetText($hTreeView, $hParent, $sNewLabel)
	If Not IsObj($g_mBlockedParents) Then $g_mBlockedParents = ObjCreate("Scripting.Dictionary")
	If Not IsObj($g_mBlockedAppPaths) Then $g_mBlockedAppPaths = ObjCreate("Scripting.Dictionary")
	$g_mBlockedParents.Item($sNewLabel) = True
	For $sPath In $aChildPaths
		$g_mBlockedAppPaths.Item(StringLower($sPath)) = True
	Next

	_GUICtrlTreeView_SetChecked($hTreeView, $hParent, False)
	$hChild = _GUICtrlTreeView_GetFirstChild($hTreeView, $hParent)
	While $hChild <> 0
		_GUICtrlTreeView_SetChecked($hTreeView, $hChild, False)
		$hChild = _GUICtrlTreeView_GetNextChild($hTreeView, $hChild)
	WEnd

	LogWrite(1, "WinTrust: blocked AE parent '" & $sAppName & "' (AfterFX.exe v" & $aVer[0] & "." & $aVer[1] & " - No WinTrust)")
	Return True
EndFunc

Func FindTrustEXEs()
	Local $foundApps = FindApps(True, $g_sWinTrustPath)
	Local $foundEXEs[0]

	For $app In $foundApps
		Local $appDir = StringLeft($app, StringInStr($app, "\", 0, -1) - 1)
		Local $appName = StringMid($app, StringInStr($app, "\", 0, -1) + 1)
		Local $localDir = $appDir & "\" & $appName & ".local"
		Local $dllPath = $localDir & "\wintrust.dll"
		If FileExists($dllPath) Then
			_ArrayAdd($foundEXEs, $app)
		EndIf
	Next

	Return $foundEXEs
EndFunc

Func FindUntrustedEXEs()
	Local $foundApps = FindApps(True, $g_sWinTrustPath)
	Local $foundEXEs[0]
	For $app In $foundApps
		Local $appDir = StringLeft($app, StringInStr($app, "\", 0, -1) - 1)
		Local $appName = StringMid($app, StringInStr($app, "\", 0, -1) + 1)
		Local $localDir = $appDir & "\" & $appName & ".local"
		Local $dllPath = $localDir & "\wintrust.dll"
		If Not FileExists($dllPath) Then
			_ArrayAdd($foundEXEs, $app)
		EndIf
	Next
	Return $foundEXEs
EndFunc

Func TrustEXEs()
	MemoWrite("Scanning for applications to trust...")
	Local $foundApps = FindUntrustedEXEs()

	If UBound($foundApps) = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("No untrusted applications found at: " & $g_sWinTrustPath & " - all eligible apps are already trusted.")
		LogWrite(1, "No untrusted applications found at: " & $g_sWinTrustPath)
		ToggleLog(1)
		Return
	EndIf

	Local $SelectedApps = TrustSelectionGUI($foundApps, "Trust")

	If Not IsArray($SelectedApps) Or UBound($SelectedApps) = 0 Then
		MemoWrite("No applications selected to trust.")
		LogWrite(1, "No applications selected to trust.")
		Return
	EndIf

	If Not AddDevOverride() Then
		MemoWrite("WinTrust operation aborted due to registry error.")
		Return
	EndIf

	Local $dllSourcePath = @ScriptDir & "\wintrust.dll"
	If Not FileExists($dllSourcePath) Or FileGetSize($dllSourcePath) <> 382712 Then
		FileInstall("wintrust.dll", $dllSourcePath, 1)
		If Not FileExists($dllSourcePath) Then
			MemoWrite("Error: Failed to extract wintrust.dll to " & $dllSourcePath)
			LogWrite(1, "Error: Failed to extract wintrust.dll.")
			Return
		EndIf
	EndIf

	If FileGetSize($dllSourcePath) <> 382712 Then
		MemoWrite("Error: wintrust.dll size mismatch (expected 382,712 bytes).")
		LogWrite(1, "Error: wintrust.dll size mismatch (expected 382,712 bytes).")
		FileDelete($dllSourcePath)
		Return
	EndIf

	MemoWrite("Trusting " & UBound($SelectedApps) & " application(s)...")
	LogWrite(1, "Trusting " & UBound($SelectedApps) & " application(s):")

	Local $successCount = 0
	For $app In $SelectedApps
		$app = StringStripWS($app, 3)
		If $app = "" Or Not FileExists($app) Then
			MemoWrite("Skipping invalid or missing file: " & $app)
			LogWrite(1, "Skipping invalid or missing file: " & $app)
			ContinueLoop
		EndIf
		If StringRegExp($app, "(?i)\\AfterFX( \(Beta\))?\.exe$") Then
			Local $aAEVer = _GetAfterFXVersion($app)
			If _IsAEBlockedByVersion($aAEVer[0], $aAEVer[1]) Then
				MemoWrite("Skipping " & $app & " - No WinTrust (After Effects v" & $aAEVer[0] & "." & $aAEVer[1] & "+ blocked from WinTrust).")
				LogWrite(1, "Skipping AE-blocked path: " & $app & " (v" & $aAEVer[0] & "." & $aAEVer[1] & ")")
				ContinueLoop
			EndIf
		EndIf

		Local $appDir = StringLeft($app, StringInStr($app, "\", 0, -1) - 1)
		Local $appName = StringMid($app, StringInStr($app, "\", 0, -1) + 1)
		Local $localDir = $appDir & "\" & $appName & ".local"
		Local $dllPath = $localDir & "\wintrust.dll"

		LogWrite(1, "- Processing: " & $app)

		If Not DirCreate($localDir) Then
			MemoWrite("Failed to create directory: " & $localDir)
			LogWrite(1, "Failed to create directory: " & $localDir)
			ContinueLoop
		EndIf

		If FileExists($dllPath) Then
			If FileGetSize($dllPath) = 382712 Then
				MemoWrite("wintrust.dll already exists at: " & $dllPath & " - Skipping.")
				LogWrite(1, "wintrust.dll already exists at: " & $dllPath & " - Skipping.")
				$successCount += 1
				Local $sAppGrp = _GetAppGroupName($app)
				If $sAppGrp <> "" Then $g_mWinTrustQueue.Item($sAppGrp) = "1"
			Else
				FileDelete($dllPath)
				If FileCopy($dllSourcePath, $dllPath, 1) And FileGetSize($dllPath) > 0 Then
					MemoWrite("Replaced wintrust.dll at: " & $dllPath)
					LogWrite(1, "Replaced wintrust.dll at: " & $dllPath)
					$successCount += 1
					Local $sAppGrp2 = _GetAppGroupName($app)
					If $sAppGrp2 <> "" Then $g_mWinTrustQueue.Item($sAppGrp2) = "1"
				Else
					MemoWrite("Failed to replace wintrust.dll to: " & $dllPath)
					LogWrite(1, "Failed to replace wintrust.dll to: " & $dllPath)
				EndIf
			EndIf
			ContinueLoop
		EndIf

		If FileCopy($dllSourcePath, $dllPath, 1) And FileGetSize($dllPath) > 0 Then
			MemoWrite("Successfully trusted: " & $appName)
			LogWrite(1, "Successfully trusted: " & $appName)
			$successCount += 1
			Local $sAppGrp3 = _GetAppGroupName($app)
			If $sAppGrp3 <> "" Then $g_mWinTrustQueue.Item($sAppGrp3) = "1"
		Else
			MemoWrite("Failed to trust: " & $appName)
			LogWrite(1, "Failed to trust: " & $appName)
		EndIf
	Next

	If FileExists($dllSourcePath) Then
		If FileDelete($dllSourcePath) Then
			MemoWrite("Deleted wintrust.dll from " & $dllSourcePath & ".")
		Else
			MemoWrite("Warning: Failed to delete wintrust.dll from " & $dllSourcePath & ".")
		EndIf
	EndIf

	MemoWrite("Trust completed. Successfully processed " & $successCount & " of " & UBound($SelectedApps) & " applications.")
	LogWrite(1, "Trust completed. Successfully processed " & $successCount & " of " & UBound($SelectedApps) & " applications.")
	_WriteWinTrustImmediate()
	_SyncWinTrustFromDisk()
	_RefreshGroupHeadersFromWT()
	ToggleLog(1)
EndFunc

Func UntrustEXEs()
	MemoWrite("Scanning for trusted applications...")
	Local $foundEXEs = FindTrustEXEs()
	If UBound($foundEXEs) = 0 Then
		MemoWrite("No trusted applications found to untrust.")
		LogWrite(1, "No trusted applications found to untrust.")
		Return
	EndIf
	Local $SelectedApps = TrustSelectionGUI($foundEXEs, "Untrust")
	If Not IsArray($SelectedApps) Or UBound($SelectedApps) = 0 Then
		MemoWrite("No applications selected to untrust.")
		LogWrite(1, "No applications selected to untrust.")
		Return
	EndIf
	MemoWrite("Untrusting " & UBound($SelectedApps) & " application(s)...")
	LogWrite(1, "Untrusting " & UBound($SelectedApps) & " application(s):")
	Local $successCount = 0
	For $app In $SelectedApps
		$app = StringStripWS($app, 3)
		If $app = "" Or Not FileExists($app) Then
			MemoWrite("Skipping invalid or missing file: " & $app)
			LogWrite(1, "Skipping invalid or missing file: " & $app)
			ContinueLoop
		EndIf
		Local $appDir = StringLeft($app, StringInStr($app, "\", 0, -1) - 1)
		Local $appName = StringMid($app, StringInStr($app, "\", 0, -1) + 1)
		Local $localDir = $appDir & "\" & $appName & ".local"
		Local $dllPath = $localDir & "\wintrust.dll"
		LogWrite(1, "- Processing: " & $app)
		If Not FileExists($dllPath) Then
			MemoWrite("No wintrust.dll found at: " & $dllPath & " - Skipping.")
			LogWrite(1, "No wintrust.dll found at: " & $dllPath & " - Skipping.")
			ContinueLoop
		EndIf
		If DirRemove($localDir, 1) Then
			MemoWrite("Successfully untrusted: " & $appName)
			LogWrite(1, "Successfully untrusted: " & $appName)
			$successCount += 1
			Local $sAppGrpU = _GetAppGroupName($app)
			If $sAppGrpU <> "" Then $g_mWinTrustQueue.Item($sAppGrpU) = "0"
		Else
			MemoWrite("Failed to untrust: " & $appName)
			LogWrite(1, "Failed to untrust: " & $appName)
		EndIf
	Next
	MemoWrite("Untrust completed. Successfully processed " & $successCount & " of " & UBound($SelectedApps) & " application(s).")
	LogWrite(1, "Untrust completed. Successfully processed " & $successCount & " of " & UBound($SelectedApps) & " application(s).")
	_WriteWinTrustImmediate()
	_SyncWinTrustFromDisk()
	_RefreshGroupHeadersFromWT()
	ToggleLog(1)
EndFunc

Func TrustSelectionGUI($foundFiles, $operation)
	If Not FileExists($g_sWinTrustPath) Or Not StringInStr(FileGetAttrib($g_sWinTrustPath), "D") Then
		MemoWrite("Error: Invalid WinTrust Path: " & $g_sWinTrustPath)
		LogWrite(1, "Error: Invalid WinTrust Path: " & $g_sWinTrustPath)
		Return ""
	EndIf
	If UBound($foundFiles) = 0 Then
		_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
		MemoWrite("No applications found to " & StringLower($operation) & " at: " & $g_sWinTrustPath)
		LogWrite(1, "No applications found to " & StringLower($operation) & " at: " & $g_sWinTrustPath)
		ToggleLog(1)
		Return ""
	EndIf
	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 500) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 400) / 2
	Local $hGUI = GUICreate($operation, 500, 400, $iPopupX, $iPopupY)
	Local $hSelectAll = GUICtrlCreateCheckbox("Select All", 10, 10)
	Local $hTreeView = GUICtrlCreateTreeView(10, 40, 480, 300, BitOR($TVS_CHECKBOXES, $TVS_HASBUTTONS, $TVS_HASLINES, $TVS_LINESATROOT))
	Local $hOkButton = GUICtrlCreateButton("OK", 200, 350, 100, 30)
	GUISetState(@SW_SHOW)
	$g_mBlockedParents = ObjCreate("Scripting.Dictionary")
	$g_mBlockedAppPaths = ObjCreate("Scripting.Dictionary")
	Local $defPathClean = StringStripWS($g_sWinTrustPath, 3)
	If StringRight($defPathClean, 1) = "\" Then
		$defPathClean = StringTrimRight($defPathClean, 1)
	EndIf
	Local $defPathParts = StringSplit($defPathClean, "\", 1)
	Local $defPathDepth = $defPathParts[0]
	Local $iShownCount = 0
	Local $appNodes = ObjCreate("Scripting.Dictionary")
	For $file In $foundFiles
		Local $fileClean = StringRegExpReplace($file, "\\\\+", "\\")
		Local $appDir = StringLeft($fileClean, StringInStr($fileClean, "\", 0, -1) - 1)
		Local $appNameOnly = StringMid($fileClean, StringInStr($fileClean, "\", 0, -1) + 1)
		Local $dllPath = $appDir & "\" & $appNameOnly & ".local\wintrust.dll"
		Local $isCurrentlyTrusted = FileExists($dllPath)
		If $operation = "Trust" And $isCurrentlyTrusted Then ContinueLoop
		If $operation = "Untrust" And Not $isCurrentlyTrusted Then ContinueLoop
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
	Local $hScanItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
	While $hScanItem <> 0
		If _GUICtrlTreeView_GetChildCount($hTreeView, $hScanItem) > 0 Then
			Local $sParentText = _GUICtrlTreeView_GetText($hTreeView, $hScanItem)
			_EvaluateAEBlock($hTreeView, $hScanItem, $sParentText)
		EndIf
		$hScanItem = _GUICtrlTreeView_GetNext($hTreeView, $hScanItem)
	WEnd
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
				MemoWrite(StringLeft($operation, 1) & StringLower(StringMid($operation, 2)) & " cancelled.")
				LogWrite(1, StringLeft($operation, 1) & StringLower(StringMid($operation, 2)) & " cancelled.")
				Return ""
			Case $hSelectAll
				AdlibUnRegister("CheckParentCheckboxes")
				Local $checkedState = (GUICtrlRead($hSelectAll) = $GUI_CHECKED)
				Local $hItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
				Local $sCurrentParent = ""
				While $hItem <> 0
					Local $itemText = _GUICtrlTreeView_GetText($hTreeView, $hItem)
					Local $bIsParent = (_GUICtrlTreeView_GetChildCount($hTreeView, $hItem) > 0)
					If $bIsParent Then $sCurrentParent = $itemText
					Local $bBlocked = False
					If IsObj($g_mBlockedParents) Then
						If $bIsParent And $g_mBlockedParents.Exists($itemText) Then $bBlocked = True
						If (Not $bIsParent) And $g_mBlockedParents.Exists($sCurrentParent) Then $bBlocked = True
					EndIf
					If $bBlocked Then
						_GUICtrlTreeView_SetChecked($hTreeView, $hItem, False)
					Else
						_GUICtrlTreeView_SetChecked($hTreeView, $hItem, $checkedState)
					EndIf
					If $bIsParent Then
						If $bBlocked Then
							$prevStates($itemText) = False
						Else
							$prevStates($itemText) = $checkedState
						EndIf
					EndIf
					$hItem = _GUICtrlTreeView_GetNext($hTreeView, $hItem)
				WEnd
				AdlibRegister("CheckParentCheckboxes", 100)
			Case $hOkButton
				AdlibUnRegister("CheckParentCheckboxes")
				Local $selectedFiles[0]
				Local $hItem = _GUICtrlTreeView_GetFirstItem($hTreeView)
				MemoWrite("Scanning for selected items...")
				While $hItem <> 0
					If _GUICtrlTreeView_GetChecked($hTreeView, $hItem) Then
						Local $itemText = _GUICtrlTreeView_GetText($hTreeView, $hItem)
						If StringInStr($itemText, ".exe") Then
							Local $bSkip = False
							If IsObj($g_mBlockedAppPaths) And $g_mBlockedAppPaths.Exists(StringLower($itemText)) Then
								$bSkip = True
								LogWrite(1, "WinTrust: skipping AE-blocked path: " & $itemText)
							EndIf
							If Not $bSkip Then _ArrayAdd($selectedFiles, $itemText)
						EndIf
					EndIf
					$hItem = _GUICtrlTreeView_GetNext($hTreeView, $hItem)
				WEnd
				_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
				GUIDelete($hGUI)
				If UBound($selectedFiles) = 0 Then
					MemoWrite("No files selected to " & StringLower($operation) & ".")
					LogWrite(1, "No files selected to " & StringLower($operation) & ".")
				EndIf
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

Func ManageDevOverride()
	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 380) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 200) / 2
	Local $hGUI = GUICreate("Manage WinTrust Override", 380, 200, $iPopupX, $iPopupY)
	Local $iIFEO    = RegRead($g_sWT_IFEO, "DevOverrideEnable")
	Local $iIFEOErr = @error
	Local $iSxS     = RegRead($g_sWT_SxS, "DevOverrideEnable")
	Local $iSxSErr  = @error
	Local $iWT64    = RegRead($g_sWT_WT64, "EnableCertPaddingCheck")
	Local $iWT64Err = @error
	Local $iWT32    = RegRead($g_sWT_WT32, "EnableCertPaddingCheck")
	Local $iWT32Err = @error
	Local $sIFEO, $sSxS, $sWT64, $sWT32
	If $iIFEOErr = 0 And $iIFEO = 1 Then
		$sIFEO = "[ON]"
	Else
		$sIFEO = "[off]"
	EndIf
	If $iSxSErr = 0 And $iSxS = 1 Then
		$sSxS = "[ON]"
	Else
		$sSxS = "[off]"
	EndIf
	If $iWT64Err = 0 And $iWT64 = 0 Then
		$sWT64 = "[ON]"
	Else
		$sWT64 = "[off]"
	EndIf
	If $iWT32Err = 0 And $iWT32 = 0 Then
		$sWT32 = "[ON]"
	Else
		$sWT32 = "[off]"
	EndIf
	Local $sOverallState
	If ($iIFEOErr = 0 And $iIFEO = 1) And ($iSxSErr = 0 And $iSxS = 1) _
			And ($iWT64Err = 0 And $iWT64 = 0) And ($iWT32Err = 0 And $iWT32 = 0) Then
		$sOverallState = "All four keys set - override fully active."
	ElseIf $iIFEOErr <> 0 And $iSxSErr <> 0 And $iWT64Err <> 0 And $iWT32Err <> 0 Then
		$sOverallState = "No keys set - override is disabled."
	Else
		$sOverallState = "Partial state - some keys set, others not."
	EndIf
	GUICtrlCreateLabel($sOverallState, 10, 10, 360, 20, $SS_CENTER)
	GUICtrlSetFont(-1, 9, 700)
	GUICtrlCreateLabel($sIFEO & "  IFEO\DevOverrideEnable", 20, 38, 340, 16)
	GUICtrlCreateLabel($sSxS  & "  SideBySide\DevOverrideEnable", 20, 56, 340, 16)
	GUICtrlCreateLabel($sWT64 & "  Wintrust\Config\EnableCertPaddingCheck (64-bit)", 20, 74, 340, 16)
	GUICtrlCreateLabel($sWT32 & "  Wow6432Node\...\EnableCertPaddingCheck (32-bit)", 20, 92, 340, 16)
	Local $hAddButton    = GUICtrlCreateButton("Enable All",  30,  125, 100, 30)
	Local $hRemoveButton = GUICtrlCreateButton("Restore All", 140, 125, 100, 30)
	Local $hCancelButton = GUICtrlCreateButton("Cancel",      250, 125, 100, 30)
	GUISetState(@SW_SHOW)
	While 1
		Switch GUIGetMsg()
			Case $GUI_EVENT_CLOSE, $hCancelButton
				MemoWrite("DevOverride registry management cancelled.")
				GUIDelete($hGUI)
				Return
			Case $hAddButton
				GUIDelete($hGUI)
				AddDevOverride()
				Return
			Case $hRemoveButton
				GUIDelete($hGUI)
				RemoveDevOverride()
				Return
		EndSwitch
	WEnd
EndFunc

Func OpenWF()
	Local $sWFPath = @SystemDir & "\wf.msc"
	Run("mmc.exe " & $sWFPath)
	ConsoleWrite("Opening Windows Firewall...")
EndFunc

