; =====================================================================
; AdobeApps.au3  -  Application module.
; Functions (31):
;   - _CcxExtDir                 (kept - used by _RestoreCcxStart cleanup)
;   - _CcxFolderVer              [CCX-REMOVED]
;   - _CcxVerCmp                 [CCX-REMOVED]
;   - _CcxRestoreFolderBaks      [CCX-REMOVED]
;   - _EnsureCcxStartPinned      [CCX-REMOVED]
;   - _RestoreCcxStart           (kept - CCX cleanup, used by Final Clean Check; needs no zip)
;   - _PickExtraAdobeDrives
;   - _PathIsBeta
;   - _PathIsLightroomCloud
;   - _LogBetaRunNotice
;   - _LogLightroomCloudNotice
;   - _IsAdobeProcess
;   - _StopAllAdobeProcesses
;   - _PromptStopAdobeProcessesForOp
;   - _GetAppGroupName
;   - _NormaliseAppGroupName
;   - _Assign_Groups_To_Found_Files
;   - _FindLauncherExe
;   - _LaunchApp
;   - _CreateNewWasRun
;   - _ReconcileWasRun
;   - _DiscoverAdobeApps
;   - _AppsBar_ResolveExe
;   - _AppsBar_AddApp
;   - _AppShortCode
;   - _BuildAppsToolbar
;   - _RefreshAppsToolbar
;   - _ShowAppsToolbar
;   - _ShowToolbarConfigDialog
;   - _ReloadAdobeNow
;   - _SuppressCCTutorials
; =====================================================================

Func _CcxExtDir()
	Return EnvGet("CommonProgramFiles") & "\Adobe\UXP\extensions"
EndFunc

#cs === [CCX-REMOVED] CCX Start version-pinning (creation path) + its exclusive helpers. Bundled resources\ccx-start-10.8.1.zip deleted. Cleanup _RestoreCcxStart() and _CcxExtDir() are kept below (used by Final Clean Check). ===
Func _CcxFolderVer($sName)
	Local $a = StringRegExp($sName, "^com\.adobe\.ccx\.start-([0-9]+(?:\.[0-9]+)*)$", 1)
	If @error Then Return ""
	Return $a[0]
EndFunc

Func _CcxVerCmp($sA, $sB)
	Local $aA = StringSplit($sA, ".", $STR_NOCOUNT)
	Local $aB = StringSplit($sB, ".", $STR_NOCOUNT)
	Local $iMax = (UBound($aA) > UBound($aB)) ? UBound($aA) : UBound($aB)
	For $i = 0 To $iMax - 1
		Local $nA = ($i < UBound($aA)) ? Number($aA[$i]) : 0
		Local $nB = ($i < UBound($aB)) ? Number($aB[$i]) : 0
		If $nA > $nB Then Return 1
		If $nA < $nB Then Return -1
	Next
	Return 0
EndFunc

Func _CcxRestoreFolderBaks($sFolder)
	Local $aBaks = _FileListToArrayRec($sFolder, "*.bak", $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_FULLPATH)
	If Not IsArray($aBaks) Then Return
	For $i = 1 To $aBaks[0]
		Local $sOrig = StringTrimRight($aBaks[$i], 4)
		FileCopy($aBaks[$i], $sOrig, $FC_OVERWRITE)
		FileDelete($aBaks[$i])
	Next
EndFunc

Func _EnsureCcxStartPinned()
	Local $sExt = _CcxExtDir()
	If Not FileExists($sExt) Then Return
	Local $sKG = IniRead($sINIPath, "Options", "CcxKnownGood", "10.8.1")

	Local $aDirs = _FileListToArray($sExt, "com.adobe.ccx.start-*", 2)
	If IsArray($aDirs) Then
		For $i = 1 To $aDirs[0]
			If StringRight($aDirs[$i], 5) = ".orig" Then ContinueLoop
			Local $sVer = _CcxFolderVer($aDirs[$i])
			If $sVer = "" Then ContinueLoop
			If _CcxVerCmp($sVer, $sKG) > 0 Then
				Local $sSrc = $sExt & "\" & $aDirs[$i]
				Local $sDst = $sSrc & ".orig"
				_CcxRestoreFolderBaks($sSrc)
				If FileExists($sDst) Then DirRemove($sDst, 1)
				DirMove($sSrc, $sDst, $FC_OVERWRITE)
				LogWrite(1, "CCX Start: neutralised newer extension " & $aDirs[$i])
			EndIf
		Next
	EndIf

	Local $aOrigs = _FileListToArray($sExt, "com.adobe.ccx.start-*.orig", 2)
	If IsArray($aOrigs) Then
		Local $sKeepVer = "", $sKeepName = ""
		For $i = 1 To $aOrigs[0]
			Local $sV = _CcxFolderVer(StringTrimRight($aOrigs[$i], 5))
			If $sV = "" Or _CcxVerCmp($sV, $sKG) <= 0 Then ContinueLoop
			If $sKeepVer = "" Or _CcxVerCmp($sV, $sKeepVer) > 0 Then
				$sKeepVer = $sV
				$sKeepName = $aOrigs[$i]
			EndIf
		Next
		For $i = 1 To $aOrigs[0]
			If $aOrigs[$i] = $sKeepName Then ContinueLoop
			Local $sV2 = _CcxFolderVer(StringTrimRight($aOrigs[$i], 5))
			If $sV2 = "" Or _CcxVerCmp($sV2, $sKG) <= 0 Then ContinueLoop
			DirRemove($sExt & "\" & $aOrigs[$i], 1)
			LogWrite(1, "CCX Start: removed older neutralised extension " & $aOrigs[$i])
		Next
	EndIf

	If Not FileExists($sExt & "\com.adobe.ccx.start-" & $sKG) Then
		Local $sTmp = @TempDir & "\ccx-start-" & $sKG & ".zip"
		FileInstall("resources\ccx-start-10.8.1.zip", $sTmp, 1)
		If FileExists($sTmp) Then
			Local $sPs = 'Expand-Archive -LiteralPath ''' & $sTmp & ''' -DestinationPath ''' & $sExt & ''' -Force'
			RunWait(@ComSpec & ' /c powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' & $sPs & '"', "", @SW_HIDE)
			FileDelete($sTmp)
			LogWrite(1, "CCX Start: extracted embedded known-good " & $sKG)
		EndIf
	EndIf

	Local $sKGOrig = $sExt & "\com.adobe.ccx.start-" & $sKG & ".orig"
	If FileExists($sKGOrig) Then
		DirRemove($sKGOrig, 1)
		LogWrite(1, "CCX Start: removed stray known-good .orig leftover " & $sKG & ".orig")
	EndIf
EndFunc
#ce === [CCX-REMOVED] end CCX Start version-pinning (creation) + helpers ===

Func _RestoreCcxStart()
	Local $sExt = _CcxExtDir()
	If Not FileExists($sExt) Then Return
	Local $sKG = IniRead($sINIPath, "Options", "CcxKnownGood", "10.8.1")

	Local $sKGDir = $sExt & "\com.adobe.ccx.start-" & $sKG
	If FileExists($sKGDir) Then
		DirRemove($sKGDir, 1)
		LogWrite(1, "CCX Start restore: removed pinned known-good " & $sKG)
	EndIf

	Local $aOrig = _FileListToArray($sExt, "com.adobe.ccx.start-*.orig", 2)
	If IsArray($aOrig) Then
		For $i = 1 To $aOrig[0]
			Local $sDst = $sExt & "\" & StringTrimRight($aOrig[$i], 5)
			If FileExists($sDst) Then
				LogWrite(1, "CCX Start restore: skip (active exists) " & $aOrig[$i])
			Else
				DirMove($sExt & "\" & $aOrig[$i], $sDst, $FC_OVERWRITE)
				LogWrite(1, "CCX Start restore: restored " & $aOrig[$i])
			EndIf
		Next
	EndIf
EndFunc

Func _PickExtraAdobeDrives($sWinDrv, $sMyDrv)
	Local $aDrives = DriveGetDrive("FIXED")
	If @error Or $aDrives[0] = 0 Then Return ""

	Local $aShow[0]
	For $i = 1 To $aDrives[0]
		Local $sDrv = StringUpper(StringLeft($aDrives[$i], 2))
		If StringLower($sDrv) <> StringLower($sWinDrv) And StringLower($sDrv) <> StringLower($sMyDrv) Then
			ReDim $aShow[UBound($aShow) + 1]
			$aShow[UBound($aShow) - 1] = $sDrv
		EndIf
	Next

	If UBound($aShow) = 0 Then Return ""

	Local $iH = 60 + UBound($aShow) * 30 + 44
	Local $aMainPos2 = WinGetPos($MyhGUI)
	Local $iPickX = $aMainPos2[0] + ($aMainPos2[2] - 280) / 2
	Local $iPickY = $aMainPos2[1] + ($aMainPos2[3] - $iH)  / 2
	Local $hPick = GUICreate("Additional Drive Scan", 280, $iH, $iPickX, $iPickY, _
			BitOR($WS_POPUP, $WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
	GUICtrlCreateLabel("Scan for leftover Adobe .bak files on:", 10, 12, 260, 18)
	GUICtrlCreateLabel("(Drives already covered are excluded)", 10, 30, 260, 16)
	GUICtrlSetFont(-1, 8, 400, 2, "Segoe UI")

	Local $aChk[UBound($aShow)]
	For $i = 0 To UBound($aShow) - 1
		Local $sLabel = $aShow[$i]
		Local $sVol = DriveGetLabel($aShow[$i] & "\")
		If $sVol <> "" Then $sLabel &= "  (" & $sVol & ")"
		$aChk[$i] = GUICtrlCreateCheckbox($sLabel, 20, 55 + $i * 30, 240, 25, $BS_AUTOCHECKBOX)
	Next

	Local $idOK   = GUICtrlCreateButton("OK",   55, 55 + UBound($aShow) * 30 + 8, 75, 28)
	Local $idSkip = GUICtrlCreateButton("Skip", 150, 55 + UBound($aShow) * 30 + 8, 75, 28)
	GUISetState(@SW_DISABLE, $MyhGUI)
	GUISetState(@SW_SHOW, $hPick)

	Local $sResult = ""
	While True
		Local $iMsg = GUIGetMsg()
		If $iMsg = $idOK Or $iMsg = $GUI_EVENT_CLOSE Then
			For $i = 0 To UBound($aShow) - 1
				If BitAND(GUICtrlRead($aChk[$i]), $GUI_CHECKED) Then
					$sResult &= ($sResult = "" ? "" : ",") & StringLeft($aShow[$i], 1)
				EndIf
			Next
			ExitLoop
		EndIf
		If $iMsg = $idSkip Then ExitLoop
	WEnd
	GUISetState(@SW_ENABLE, $MyhGUI)
	GUIDelete($hPick)
	Return $sResult
EndFunc

Func _PathIsBeta($sPath)
	Local $sPathLC = StringLower($sPath)
	Return (StringInStr($sPath, "(Beta)") > 0) Or (StringInStr($sPath, " Beta\") > 0) Or (StringInStr($sPathLC, "\adobe animate beta") > 0)
EndFunc

Func _PathIsLightroomCloud($sPath)
	Local $sPathLC = StringLower($sPath)
	If StringInStr($sPathLC, "lightroom classic") > 0 Then Return False
	Local $sName = StringLower(StringRegExpReplace($sPath, "^.*\\", ""))
	If $sName <> "lightroom.exe" Then Return False
	Return (StringInStr($sPathLC, "lightroom cc") > 0) Or (StringInStr($sPathLC, "\adobe lightroom\") > 0)
EndFunc

Func _LogBetaRunNotice()
	If Not $g_bBetaPatchedThisRun Then Return
	LogWrite(1, @CRLF & "======================" & @CRLF & _
			"BETA BUILDS INSTALLED" & @CRLF & _
			"======================" & @CRLF & @CRLF & _
			"Beta builds are experimental and can break at any time after updates or server-side changes." & @CRLF & @CRLF & _
			"No help, support, or community assistance will be provided for unstable experimental builds.")
	$g_bBetaPatchedThisRun = False
EndFunc

Func _LogLightroomCloudNotice()
	If Not $g_bLightroomCloudThisRun Then Return
	LogWrite(1, @CRLF & "========================" & @CRLF & _
			"LIGHTROOM CC INSTALLED" & @CRLF & _
			"========================" & @CRLF & @CRLF & _
			"The cloud-based Lightroom relies on Adobe's servers, so patched installs are often unreliable, some features may not work, and in some cases the app may not run at all." & @CRLF & @CRLF & _
			"GenP only patches locally, not on Adobe's servers, so this version may stop working without warning." & @CRLF & @CRLF & _
			"Recommended: use Lightroom Classic, a fully desktop-based app that is stable, predictable, and fully compatible.")
	$g_bLightroomCloudThisRun = False
EndFunc

Func _IsAdobeProcess($sNameLC, $iPID = 0)
	If StringInStr($sNameLC, "adobe") _
			Or StringInStr($sNameLC, "creative cloud") _
			Or StringInStr($sNameLC, "ccxprocess") _
			Or StringInStr($sNameLC, "coresync") _
			Or StringInStr($sNameLC, "armsvc") _
			Or StringInStr($sNameLC, "rdrcef") _
			Or StringInStr($sNameLC, "acrocef") _
			Or StringInStr($sNameLC, "acrobroker") _
			Or StringInStr($sNameLC, "acrobat") _
			Or StringInStr($sNameLC, "acrord32") _
			Or StringInStr($sNameLC, "acrotray") _
			Or StringInStr($sNameLC, "aasiapp") Then
		Return True
	EndIf

	If $iPID > 0 Then
		Local $sPath = StringLower(_WinAPI_GetProcessFileName($iPID))
		If $sPath <> "" _
				And (StringInStr($sPath, "\adobe\") Or StringInStr($sPath, "\common files\adobe")) Then
			Return True
		EndIf
	EndIf
	Return False
EndFunc

Func _StopAllAdobeProcesses()
	Local $aServices[12] = [ _
			"AGSService", "AGMService", "AdobeARMservice", "AdobeUpdateService", _
			"Adobe LM Service", "CCXProcess", "AdobeIPCBroker", "armsvc", "AASIapp", _
			"AdobeGenuineUpdater", "AdobeLicensingService", "ACCUpdateService" _
			]
	LogWrite(1, "Stopping Adobe services so they don't respawn processes...")
	For $i = 0 To UBound($aServices) - 1
		Run(@ComSpec & ' /c sc stop "' & $aServices[$i] & '" >nul 2>&1', "", @SW_HIDE)
	Next
	Local $aProcs = ProcessList()
	Local $iClosed = 0
	For $i = 1 To $aProcs[0][0]
		If _IsAdobeProcess(StringLower($aProcs[$i][0]), $aProcs[$i][1]) Then
			ProcessClose($aProcs[$i][1])
			$iClosed += 1
		EndIf
	Next
	LogWrite(1, "Sending graceful close command to " & $iClosed & " Adobe-related process(es).")
	Sleep(1500)
	$aProcs = ProcessList()
	Local $iForced = 0
	For $i = 1 To $aProcs[0][0]
		If _IsAdobeProcess(StringLower($aProcs[$i][0]), $aProcs[$i][1]) Then
			RunWait(@ComSpec & ' /c taskkill /F /T /PID ' & $aProcs[$i][1] & ' >nul 2>&1', "", @SW_HIDE)
			$iForced += 1
		EndIf
	Next
	If $iForced > 0 Then LogWrite(1, "Sending force-kill command to " & $iForced & " stubborn process(es).")
	Sleep(500)
	$aProcs = ProcessList()
	Local $iStillRunning = 0
	For $i = 1 To $aProcs[0][0]
		If _IsAdobeProcess(StringLower($aProcs[$i][0]), $aProcs[$i][1]) Then
			$iStillRunning += 1
		EndIf
	Next
	Return $iStillRunning
EndFunc

Func _PromptStopAdobeProcessesForOp($sOpName)
	Local $aProcs = ProcessList()
	Local $iAdobeCount = 0
	For $i = 1 To $aProcs[0][0]
		If _IsAdobeProcess(StringLower($aProcs[$i][0]), $aProcs[$i][1]) Then $iAdobeCount += 1
	Next
	If $iAdobeCount = 0 Then Return 1
	Local $iAns = MsgBox(BitOR($MB_YESNOCANCEL, $MB_ICONWARNING, $MB_SYSTEMMODAL), _
			"Adobe Processes Detected", _
			$iAdobeCount & " Adobe-related process(es) are running." & @CRLF & @CRLF & _
			"Open Adobe apps, running processes or services can lock" & @CRLF & _
			"files and stop them being " & $sOpName & "." & @CRLF & @CRLF & _
			"Yes: GenP will automatically stop all running Adobe processes" & @CRLF & _
			"          and services, and then continue." & @CRLF & _
			"No: Continue anyway (any files in use will be automatically" & @CRLF & _
			"          skipped and reported back to you)." & @CRLF & _
			"Cancel: Abort, and nothing will be changed.")
	If $iAns = $IDCANCEL Then
		LogWrite(1, "Operation cancelled by user at Adobe-process prompt (" & $iAdobeCount & " process(es) detected).")
		Return 0
	EndIf
	If $iAns = $IDYES Then
		LogWrite(1, "User chose auto-kill before " & $sOpName & " - stopping all Adobe processes and services...")
		Local $iSurvived = _StopAllAdobeProcesses()
		If $iSurvived = 0 Then
			LogWrite(1, "All Adobe processes stopped successfully. Proceeding.")
		Else
			LogWrite(1, $iSurvived & " Adobe process(es) survived shutdown - some files may remain locked.")
			MsgBox(BitOR($MB_OK, $MB_ICONWARNING), "Some processes survived", _
					$iSurvived & " Adobe process(es) could not be stopped." & @CRLF & @CRLF & _
					"Continuing - any locked files will be skipped and reported.")
		EndIf
	Else
		LogWrite(1, "User chose to continue " & $sOpName & " without stopping Adobe processes (in-use files will be skipped).")
	EndIf
	Return 1
EndFunc

Func _GetAppGroupName($sFilePath)
	Local $sLower = StringLower($sFilePath)

	If StringInStr($sLower, "\acrobat dc\") Or StringInStr($sLower, "\adobe acrobat\") Or _
			StringInStr($sLower, "acrotray") Or StringInStr($sLower, "acrodistdll") Or _
			StringInStr($sLower, "acrobat.dll") Or StringInStr($sLower, "_wf_acro") Or _
			StringInStr($sLower, "\acrocef\") Then
		Return "Acrobat"
	EndIf

	If StringInStr($sLower, "\elements 2026 organizer\") Or _
			StringInStr($sLower, "photoshopelementsorganizer") Then
		Return "Elements 2026 Organizer"
	EndIf

	If StringInStr($sLower, "com.adobe.ccx.start") Then
		If StringInStr($sLower, "\common files\adobe\uxp\extensions\") Or _
				StringInStr($sLower, "\adobe\acc\") Then
			Return "Creative Cloud"
		EndIf
	EndIf

	If StringInStr($sLower, "\common files\adobe\") Then
		If StringInStr($sLower, "appspanel") Or StringInStr($sLower, "containerbl") Or _
				StringInStr($sLower, "adobe desktop service") Or StringInStr($sLower, "hdpim") Or _
				(StringInStr($sLower, "adobe_licensing_wf") And Not StringInStr($sLower, "_acro")) Or _
				StringInStr($sLower, "adobecollabsync") Then
			Return "Creative Cloud"
		EndIf
	EndIf

	Local $iMark = StringInStr($sFilePath, "\Adobe\")
	If $iMark > 0 Then
		Local $sRest = StringMid($sFilePath, $iMark + 7)
		Local $iSlash = StringInStr($sRest, "\")
		Local $sAppFolder = ($iSlash > 0) ? StringLeft($sRest, $iSlash - 1) : $sRest
		If StringLeft($sAppFolder, 6) = "Adobe " Then $sAppFolder = StringTrimLeft($sAppFolder, 6)
		If $sAppFolder <> "" Then Return _NormaliseAppGroupName($sAppFolder, $sFilePath)
	EndIf

	Return "Other"
EndFunc

Func _NormaliseAppGroupName($sAppFolder, $sFilePath)
	If StringRegExp($sAppFolder, "\d{4}") Then Return $sAppFolder

	Local $sBase = $sAppFolder
	Local $bIsBeta = False
	Local $sExpSuffix = "(Beta)"
	If StringInStr($sBase, "(Beta)") Then
		$sBase = StringStripWS(StringReplace($sBase, "(Beta)", ""), 3)
		$bIsBeta = True
	ElseIf StringRegExp($sBase, "(?i)\sBeta$") Then
		$sBase = StringRegExpReplace($sBase, "(?i)\sBeta$", "")
		$bIsBeta = True
	EndIf
	If Not $bIsBeta Then Return $sAppFolder

	Local $iMark = StringInStr($sFilePath, "\Adobe\")
	If $iMark <= 0 Then Return $sAppFolder
	Local $sAdobeRoot = StringLeft($sFilePath, $iMark + 6)

	Local $sYear = ""
	Local $HSEARCH = FileFindFirstFile($sAdobeRoot & "*")
	If $HSEARCH <> -1 Then
		While 1
			Local $sSibling = FileFindNextFile($HSEARCH)
			If @error Then ExitLoop
			Local $sSib = $sSibling
			If StringLeft($sSib, 6) = "Adobe " Then $sSib = StringTrimLeft($sSib, 6)
			If StringLeft($sSib, StringLen($sBase)) = $sBase Then
				Local $aMatch = StringRegExp($sSib, "(\d{4})", 1)
				If Not @error Then
					$sYear = $aMatch[0]
					ExitLoop
				EndIf
			EndIf
		WEnd
		FileClose($HSEARCH)
	EndIf

	If $sYear = "" Then Return $sAppFolder
	Return $sBase & " " & $sYear & " " & $sExpSuffix
EndFunc

Func _Assign_Groups_To_Found_Files()
	Local $MyListItemCount = _GUICtrlListView_GetItemCount($idListview)
	Local $ItemFromList, $sGroupName
	Local $aGroups[0]
	Local $iGroupID = 1

	ReDim $g_aGroupIDs[0]

	Local $mCount = ObjCreate("Scripting.Dictionary")
	Local $mExe = ObjCreate("Scripting.Dictionary")
	Local $mWT = ObjCreate("Scripting.Dictionary")
	Local $mAppRoot = ObjCreate("Scripting.Dictionary")
	For $i = 0 To $MyListItemCount - 1
		$ItemFromList = _GUICtrlListView_GetItemText($idListview, $i, 1)
		$sGroupName = _GetAppGroupName($ItemFromList)
		If $sGroupName = "" Then $sGroupName = "Other"

		If $mCount.Exists($sGroupName) Then
			$mCount.Item($sGroupName) = $mCount.Item($sGroupName) + 1
		Else
			$mCount.Item($sGroupName) = 1
		EndIf

		If StringRight(StringLower($ItemFromList), 4) = ".exe" Then
			If Not $mExe.Exists($sGroupName) Then
				$mExe.Item($sGroupName) = $ItemFromList
			Else
				Local $sCur = StringLower(StringRegExpReplace($mExe.Item($sGroupName), "^.*\\", ""))
				Local $sNew = StringLower(StringRegExpReplace($ItemFromList, "^.*\\", ""))
				Local $sAppL = StringLower($sGroupName)
				If StringInStr($sAppL, StringTrimRight($sNew, 4)) And _
						Not StringInStr($sAppL, StringTrimRight($sCur, 4)) Then
					$mExe.Item($sGroupName) = $ItemFromList
				EndIf
			EndIf
		EndIf

		If Not $mWT.Exists($sGroupName) Then
			Local $sFolder = StringRegExpReplace($ItemFromList, "\\[^\\]+$", "")
			If FileExists($sFolder & "\wintrust.dll") Then $mWT.Item($sGroupName) = 1
		EndIf

		If Not $mAppRoot.Exists($sGroupName) Then
			Local $iMark = StringInStr($ItemFromList, "\Adobe\")
			If $iMark > 0 Then
				Local $sAfter = StringMid($ItemFromList, $iMark + 7)
				Local $iSlash = StringInStr($sAfter, "\")
				If $iSlash > 0 Then
					$mAppRoot.Item($sGroupName) = StringLeft($ItemFromList, $iMark + 6 + $iSlash)
				EndIf
			EndIf
		EndIf
	Next

	For $i = 0 To $MyListItemCount - 1
		$ItemFromList = _GUICtrlListView_GetItemText($idListview, $i, 1)
		$sGroupName = _GetAppGroupName($ItemFromList)
		If $sGroupName = "" Then $sGroupName = "Other"

		Local $iGroupIndex = _ArraySearch($aGroups, $sGroupName)
		If $iGroupIndex = -1 Then
			Local $sHeader = $sGroupName
			If $mWT.Exists($sGroupName) Then $sHeader = "[WT] " & $sHeader

			Local $sVerExe = ""
			If $mExe.Exists($sGroupName) Then $sVerExe = $mExe.Item($sGroupName)
			If $sVerExe = "" And $mAppRoot.Exists($sGroupName) Then
				$sVerExe = _FindLauncherExe($mAppRoot.Item($sGroupName), $sGroupName)
			EndIf
			If $sVerExe <> "" Then
				Local $sVer = FileGetVersion($sVerExe)
				If @error Or $sVer = "" Then $sVer = FileGetVersion($sVerExe, $FV_PRODUCTVERSION)
				If $sVer <> "" Then $sHeader &= " (v" & $sVer & ")"
			EndIf

			Local $iCount = $mCount.Item($sGroupName)
			$sHeader &= " (" & $iCount & " file" & (($iCount = 1) ? "" : "s") & ")"

			_ArrayAdd($aGroups, $sGroupName)
			_GUICtrlListView_InsertGroup($idListview, $i, $iGroupID, "", 1)
			_GUICtrlListView_SetItemGroupID($idListview, $i, $iGroupID)
			_GUICtrlListView_SetGroupInfo($idListview, $iGroupID, $sHeader, 1, $LVGS_COLLAPSIBLE)
			_ArrayAdd($g_aGroupIDs, $iGroupID)
			$iGroupID += 1
		Else
			_GUICtrlListView_SetItemGroupID($idListview, $i, $iGroupIndex + 1)
		EndIf
	Next
EndFunc

Func _FindLauncherExe($sAppRoot, $sGroupName)
	If Not FileExists($sAppRoot) Then Return ""

	Local $sBase = StringRegExpReplace($sGroupName, "\s*\d{4}", "")
	$sBase = StringRegExpReplace($sBase, "\s*\(Beta\)", "")
	$sBase = StringStripWS($sBase, 3)

	Local $aLaunchers[24][2] = [ _
			["Acrobat", "Acrobat.exe"], _
			["After Effects", "AfterFX.exe"], _
			["Animate", "Animate.exe"], _
			["Audition", "Adobe Audition.exe"], _
			["Bridge", "Adobe Bridge.exe"], _
			["Character Animator", "Character Animator.exe"], _
			["Dimension", "Adobe Dimension.exe"], _
			["Dreamweaver", "Dreamweaver.exe"], _
			["Elements 2026 Organizer", "PhotoshopElementsOrganizer.exe"], _
			["Illustrator", "Illustrator.exe"], _
			["InCopy", "InCopy.exe"], _
			["InDesign", "InDesign.exe"], _
			["Lightroom Classic", "Lightroom.exe"], _
			["Lightroom", "lightroom.exe"], _
			["Media Encoder", "Adobe Media Encoder.exe"], _
			["Photoshop Elements 2026", "PhotoshopElementsEditor.exe"], _
			["Photoshop", "Photoshop.exe"], _
			["Premiere Elements 2026", "PremiereElementsEditor.exe"], _
			["Premiere Pro", "Adobe Premiere Pro.exe"], _
			["Substance 3D Designer", "Adobe Substance 3D Designer.exe"], _
			["Substance 3D Modeler", "Adobe Substance 3D Modeler.exe"], _
			["Substance 3D Painter", "Adobe Substance 3D Painter.exe"], _
			["Substance 3D Sampler", "Adobe Substance 3D Sampler.exe"], _
			["Substance 3D Stager", "Adobe Substance 3D Stager.exe"] _
			]

	If $sBase = "Creative Cloud" Then
		Local $aCCCandidates[3]
		$aCCCandidates[0] = EnvGet("ProgramFiles(x86)") & "\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe"
		$aCCCandidates[1] = EnvGet("ProgramFiles") & "\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe"
		Local $sCCInstall = RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Adobe\Adobe Application Manager\ACC", "InstallLocation")
		If Not @error And $sCCInstall <> "" Then
			$aCCCandidates[2] = StringRegExpReplace($sCCInstall, "\\$", "") & "\ACC\Creative Cloud.exe"
		EndIf
		For $sCCExe In $aCCCandidates
			If $sCCExe <> "" And FileExists($sCCExe) Then Return $sCCExe
		Next
	EndIf

	Local $aRoots[3] = [$sAppRoot, $sAppRoot & "Support Files\", $sAppRoot & "Elements Home\"]

	If StringInStr($sBase, "Photoshop Elements") Or StringInStr($sBase, "Premiere Elements") Then
		Local $sStem = StringInStr($sBase, "Photoshop") ? "Adobe Photoshop Elements" : "Adobe Premiere Elements"
		Local $sHome = $sAppRoot & "Elements Home\"
		If FileExists($sHome) Then
			Local $hFind = FileFindFirstFile($sHome & $sStem & " *.exe")
			If $hFind <> -1 Then
				Local $sFound = FileFindNextFile($hFind)
				FileClose($hFind)
				If $sFound <> "" Then Return $sHome & $sFound
			EndIf
		EndIf
	EndIf

	For $i = 0 To UBound($aLaunchers) - 1
		If StringInStr($sBase, $aLaunchers[$i][0]) Then
			Local $sBetaName = StringRegExpReplace($aLaunchers[$i][1], "\.exe$", " (Beta).exe")
			For $sRoot In $aRoots
				If FileExists($sRoot & $aLaunchers[$i][1]) Then Return $sRoot & $aLaunchers[$i][1]
				If FileExists($sRoot & $sBetaName) Then Return $sRoot & $sBetaName
			Next
		EndIf
	Next

	For $sRoot In $aRoots
		If Not FileExists($sRoot) Then ContinueLoop
		Local $hFind = FileFindFirstFile($sRoot & "*.exe")
		If $hFind = -1 Then ContinueLoop
		While 1
			Local $sExe = FileFindNextFile($hFind)
			If @error Then ExitLoop
			If StringRegExp($sExe, "(?i)unins|setup|helper|worker|service|crashreporter|updater") Then ContinueLoop
			FileClose($hFind)
			Return $sRoot & $sExe
		WEnd
		FileClose($hFind)
	Next

	Return ""
EndFunc

Func _LaunchApp($sExe)
	If Not FileExists($sExe) Then Return 0

	EnvSet("DISABLE_AAM_AUTHENTICATION", "1")
	EnvSet("ADOBE_AAM_OVERRIDE",         "1")
	EnvSet("AAM_GLOBAL_STATUS",          "OFFLINE")
	EnvSet("AAM_ENV_PRODUCT_STATUS",     "LICENSED")

	Local $sDir = StringLeft($sExe, StringInStr($sExe, "\", 0, -1) - 1)
	Local $iPID = Run('"' & $sExe & '"', $sDir)

	EnvSet("DISABLE_AAM_AUTHENTICATION", "")
	EnvSet("ADOBE_AAM_OVERRIDE",         "")
	EnvSet("AAM_GLOBAL_STATUS",          "")
	EnvSet("AAM_ENV_PRODUCT_STATUS",     "")

	Return $iPID
EndFunc

Func _CreateNewWasRun()
	If Not FileExists($patchStatesINI) Or Not FileExists($sINIPath) Then Return False
	If IniRead($patchStatesINI, "Info",    "CreatedNew", "0") <> "1" Then Return False
	If IniRead($sINIPath,       "Options", "CreatedNew", "0") <> "1" Then Return False
	Local $sPsiDate = IniRead($patchStatesINI, "Info",    "CreatedNewDate", "")
	Local $sCfgDate = IniRead($sINIPath,       "Options", "CreatedNewDate", "")
	Return ($sPsiDate <> "" And $sPsiDate = $sCfgDate)
EndFunc

Func _ReconcileWasRun()
	If Not FileExists($patchStatesINI) Or Not FileExists($sINIPath) Then Return False
	If IniRead($patchStatesINI, "Info",    "ReconcileUsed", "0") <> "1" Then Return False
	If IniRead($sINIPath,       "Options", "ReconcileUsed", "0") <> "1" Then Return False
	Local $sPsiDate = IniRead($patchStatesINI, "Info",    "ReconcileUsedDate", "")
	Local $sCfgDate = IniRead($sINIPath,       "Options", "ReconcileUsedDate", "")
	Return ($sPsiDate <> "" And $sPsiDate = $sCfgDate)
EndFunc

Func _DiscoverAdobeApps()
	Local $aApps[0][2]
	Local $mSeen = ObjCreate("Scripting.Dictionary")

	If Not FileExists($patchStatesINI) Then
		LogWrite(1, "AppsBar: patch_states.ini not found - run 'Create new patch_states.ini' first to enable the launch toolbar.")
		Return $aApps
	EndIf

	Local $aSec = IniReadSection($patchStatesINI, "App_File")
	If Not @error Then
		For $r = 1 To $aSec[0][0]
			Local $sGroup = $aSec[$r][0]
			Local $sList  = $aSec[$r][1]
			If $sGroup = "" Or $sGroup = "Other" Or $sGroup = "Creative Cloud" Then ContinueLoop
			If $mSeen.Exists($sGroup) Then ContinueLoop

			Local $sFirst = $sList
			Local $iSep = StringInStr($sFirst, ";")
			If $iSep > 0 Then $sFirst = StringLeft($sFirst, $iSep - 1)

			Local $sExe = _AppsBar_ResolveExe($sFirst, $sGroup)
			If $sExe = "" Then ContinueLoop

			$mSeen.Item($sGroup) = 1
			_AppsBar_AddApp($aApps, $sGroup, $sExe)
		Next
	EndIf

	Return $aApps
EndFunc

Func _AppsBar_ResolveExe($sFilePath, $sGroup)
	Local $sAppRoot = StringRegExpReplace($sFilePath, "(?i)^(.+\\Adobe\\[^\\]+\\).*$", "$1")
	If $sAppRoot = $sFilePath Then Return ""
	Local $sExe = _FindLauncherExe($sAppRoot, $sGroup)
	If $sExe = "" Or Not FileExists($sExe) Then Return ""
	Return $sExe
EndFunc

Func _AppsBar_AddApp(ByRef $aApps, $sGroup, $sExe)
	Local $iN = UBound($aApps)
	ReDim $aApps[$iN + 1][2]
	$aApps[$iN][0] = $sGroup
	$aApps[$iN][1] = $sExe
EndFunc

Func _AppShortCode($sGroup)
	If StringInStr($sGroup, "Photoshop Elements")    Then Return "PSE"
	If StringInStr($sGroup, "Premiere Elements")     Then Return "PRE"
	If StringInStr($sGroup, "Photoshop")             Then Return "Ps"
	If StringInStr($sGroup, "Illustrator")           Then Return "Ai"
	If StringInStr($sGroup, "After Effects")         Then Return "Ae"
	If StringInStr($sGroup, "Premiere")              Then Return "Pr"
	If StringInStr($sGroup, "InDesign")              Then Return "Id"
	If StringInStr($sGroup, "Acrobat")               Then Return "Ac"
	If StringInStr($sGroup, "Animate")               Then Return "An"
	If StringInStr($sGroup, "Audition")              Then Return "Au"
	If StringInStr($sGroup, "Bridge")                Then Return "Br"
	If StringInStr($sGroup, "Character Animator")    Then Return "Ch"
	If StringInStr($sGroup, "Dreamweaver")           Then Return "Dw"
	If StringInStr($sGroup, "Dimension")             Then Return "Dn"
	If StringInStr($sGroup, "Fresco")                Then Return "Fr"
	If StringInStr($sGroup, "InCopy")                Then Return "Ic"
	If StringInStr($sGroup, "Lightroom Classic")     Then Return "Lrc"
	If StringInStr($sGroup, "Lightroom")             Then Return "Lr"
	If StringInStr($sGroup, "Media Encoder")         Then Return "Me"
	If StringInStr($sGroup, "Prelude")               Then Return "Pl"
	If StringInStr($sGroup, "Rush")                  Then Return "Ru"
	If StringInStr($sGroup, "Substance 3D Painter")  Then Return "Sb"
	If StringInStr($sGroup, "Substance 3D Designer") Then Return "Sd"
	If StringInStr($sGroup, "Substance 3D Sampler")  Then Return "Ss"
	If StringInStr($sGroup, "Substance 3D Stager")   Then Return "St"
	If StringInStr($sGroup, "Substance 3D Modeler")  Then Return "Mo"
	If StringInStr($sGroup, "XD")                    Then Return "Xd"
	Local $a = StringSplit(StringStripWS($sGroup, 3), " ", 1)
	If $a[0] >= 2 Then Return StringLeft($a[1], 1) & StringLeft($a[2], 1)
	Return StringLeft($sGroup, 2)
EndFunc

Func _BuildAppsToolbar()
	If $g_hAppsBar <> 0 Then
		Local $aBarPos = WinGetPos($g_hAppsBar)
		If IsArray($aBarPos) Then
			$g_iAppsBarX = $aBarPos[0]
			$g_iAppsBarY = $aBarPos[1]
		EndIf
		GUIDelete($g_hAppsBar)
		$g_hAppsBar = 0
	EndIf
	ReDim $g_aAppsBarBtns[0][2]
	$g_bAppsBarBuilt    = False
	$g_idAppsBarMinBtn    = -1
	$g_idAppsBarConfigBtn = -1
	If Not $bShowLaunchBar Then Return
	If Not FileExists($patchStatesINI) Then Return

	Local $aAllApps  = _DiscoverAdobeApps()
	Local $aApps[0][2]
	If $g_sToolbarApps <> "" Then
		Local $iAllCount = UBound($aAllApps)
		For $i = 0 To $iAllCount - 1
			If StringInStr("|" & $g_sToolbarApps & "|", "|" & $aAllApps[$i][0] & "|") Then
				_AppsBar_AddApp($aApps, $aAllApps[$i][0], $aAllApps[$i][1])
			EndIf
		Next
	EndIf
	Local $iCount = UBound($aApps)

	Local $iPad = 8, $iBtnW = 48, $iBtnH = 44, $iGap = 4, $iCols = 4, $iHdr = 22
	Local $iMinBtnH = 20
	Local $iW = $iPad * 2 + $iCols * ($iBtnW + $iGap) - $iGap
	Local $iContentW = $iW - $iPad * 2
	Local $iBtnFW = Int(($iContentW - $iGap) / 2)

	Local $iX = 100, $iY = 100
	If $g_iAppsBarX >= 0 And $g_iAppsBarY >= 0 Then
		$iX = $g_iAppsBarX
		$iY = $g_iAppsBarY
	Else
		Local $aMain = WinGetPos($MyhGUI)
		If IsArray($aMain) Then
			$iX = $aMain[0] + $aMain[2] + 8
			$iY = $aMain[1]
		EndIf
	EndIf

	If $iCount = 0 Then
		Local $iBlankH = 34
		Local $iH = $iPad * 2 + $iHdr + $iBlankH + $iGap + $iMinBtnH

		$g_hAppsBar = GUICreate("GenP v" & $g_Version & " Toolbar", $iW, $iH, $iX, $iY, _
				BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), 0)
		If FileExists(@ScriptDir & "\Skull.ico") Then GUISetIcon(@ScriptDir & "\Skull.ico", 0, $g_hAppsBar)
		GUICtrlCreateLabel("App Launch Toolbar", $iPad, $iPad, $iW - $iPad * 2, 16)
		GUICtrlSetFont(-1, 7, 600, 0, "Segoe UI")

		Local $sHint
		If $g_sToolbarApps = "" Then
			$sHint = "No apps selected. Click Configure" & @CRLF & "to choose up to 10 apps."
		Else
			$sHint = "No configured apps found. Click" & @CRLF & "Configure to update your selection."
		EndIf
		GUICtrlCreateLabel($sHint, $iPad, $iPad + $iHdr, $iW - $iPad * 2, $iBlankH)
		GUICtrlSetFont(-1, 7, 400, 0, "Segoe UI")

		Local $iFooterY = $iPad + $iHdr + $iBlankH + $iGap
		$g_idAppsBarMinBtn    = GUICtrlCreateButton("Minimise GenP", $iPad, $iFooterY, $iBtnFW, $iMinBtnH)
		GUICtrlSetFont($g_idAppsBarMinBtn, 7, 400, 0, "Segoe UI")
		$g_idAppsBarConfigBtn = GUICtrlCreateButton("Configure", $iPad + $iBtnFW + $iGap, $iFooterY, $iContentW - $iBtnFW - $iGap, $iMinBtnH)
		GUICtrlSetFont($g_idAppsBarConfigBtn, 7, 400, 0, "Segoe UI")

		GUISetState(@SW_SHOWNOACTIVATE, $g_hAppsBar)
		$g_bAppsBarBuilt = True
		LogWrite(1, "AppsBar: blank state   " & ($g_sToolbarApps = "" ? "not yet configured." : "configured apps not found."))
		Return
	EndIf

	Local $iRows = Int(($iCount + $iCols - 1) / $iCols)
	Local $iH = $iPad * 2 + $iHdr + $iRows * ($iBtnH + $iGap) + $iGap + $iMinBtnH

	$g_hAppsBar = GUICreate("GenP v" & $g_Version & " Toolbar", $iW, $iH, $iX, $iY, _
			BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), 0)
	If FileExists(@ScriptDir & "\Skull.ico") Then GUISetIcon(@ScriptDir & "\Skull.ico", 0, $g_hAppsBar)
	GUICtrlCreateLabel("Open app (CC checks bypassed):", $iPad, $iPad, $iW - $iPad * 2, 16)
	GUICtrlSetFont(-1, 7, 600, 0, "Segoe UI")

	Local $iRow = 0, $iCol = 0
	For $i = 0 To $iCount - 1
		Local $iXpos = $iPad + $iCol * ($iBtnW + $iGap)
		Local $iYpos = $iPad + $iHdr + $iRow * ($iBtnH + $iGap)
		Local $idBtn = GUICtrlCreateButton(_AppShortCode($aApps[$i][0]), $iXpos, $iYpos, $iBtnW, $iBtnH)
		GUICtrlSetFont($idBtn, 10, 800, 0, "Segoe UI")
		GUICtrlSetImage($idBtn, $aApps[$i][1], 0, 1)
		Local $iN = UBound($g_aAppsBarBtns)
		ReDim $g_aAppsBarBtns[$iN + 1][2]
		$g_aAppsBarBtns[$iN][0] = $idBtn
		$g_aAppsBarBtns[$iN][1] = $aApps[$i][1]
		$iCol += 1
		If $iCol >= $iCols Then
			$iCol = 0
			$iRow += 1
		EndIf
	Next

	Local $iFooterY = $iPad + $iHdr + $iRows * ($iBtnH + $iGap) + $iGap
	$g_idAppsBarMinBtn    = GUICtrlCreateButton("Minimise GenP", $iPad, $iFooterY, $iBtnFW, $iMinBtnH)
	GUICtrlSetFont($g_idAppsBarMinBtn, 7, 400, 0, "Segoe UI")
	$g_idAppsBarConfigBtn = GUICtrlCreateButton("Configure", $iPad + $iBtnFW + $iGap, $iFooterY, $iContentW - $iBtnFW - $iGap, $iMinBtnH)
	GUICtrlSetFont($g_idAppsBarConfigBtn, 7, 400, 0, "Segoe UI")

	GUISetState(@SW_SHOWNOACTIVATE, $g_hAppsBar)
	$g_bAppsBarBuilt = True
	LogWrite(1, "AppsBar: " & $iCount & " app button(s) built.")
EndFunc

Func _RefreshAppsToolbar()
	_BuildAppsToolbar()
EndFunc

Func _ShowAppsToolbar()
	If $g_hAppsBar = 0 Then
		_BuildAppsToolbar()
	Else
		GUISetState(@SW_SHOWNOACTIVATE, $g_hAppsBar)
	EndIf
EndFunc

Func _ShowToolbarConfigDialog()
	Local $aAllApps = _DiscoverAdobeApps()
	Local $iAllCount = UBound($aAllApps)

	If $iAllCount = 0 Then
		MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION, $MB_SYSTEMMODAL), "Configure Toolbar", _
				"No patched apps found in patch_states.ini." & @CRLF & @CRLF & _
				"Patch some apps first, then configure the toolbar.")
		Return
	EndIf

	_ArraySort($aAllApps, 0, 0, 0, 0, True)

	Local $iDW = 256, $iListH = 220
	Local $iDH = 48 + $iListH + 10 + 26 + 10

	Local $hDlg = GUICreate("Configure Toolbar", $iDW, $iDH, -1, -1, _
			BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), $WS_EX_TOPMOST, $MyhGUI)
	If FileExists(@ScriptDir & "\Skull.ico") Then GUISetIcon(@ScriptDir & "\Skull.ico", 0, $hDlg)
	_CentreGui($hDlg, $iDW, $iDH)

	GUICtrlCreateLabel("Select up to 10 apps to show on the toolbar:", 10, 10, $iDW - 20, 30)
	GUICtrlSetFont(-1, 7, 600, 0, "Segoe UI")

	Local $idLV = GUICtrlCreateListView("", 10, 44, $iDW - 20, $iListH, _
			BitOR($LVS_REPORT, $LVS_NOCOLUMNHEADER, $LVS_SHOWSELALWAYS))
	Local $hLV = GUICtrlGetHandle($idLV)
	_GUICtrlListView_SetExtendedListViewStyle($hLV, BitOR($LVS_EX_CHECKBOXES, $LVS_EX_FULLROWSELECT))
	_GUICtrlListView_AddColumn($hLV, "", $iDW - 42)

	For $i = 0 To $iAllCount - 1
		_GUICtrlListView_AddItem($hLV, $aAllApps[$i][0])
		If StringInStr("|" & $g_sToolbarApps & "|", "|" & $aAllApps[$i][0] & "|") Then
			_GUICtrlListView_SetItemChecked($hLV, $i, True)
		EndIf
	Next

	Local $iBtnY = 44 + $iListH + 10
	Local $iBW = Int(($iDW - 30) / 2)
	Local $idOK     = GUICtrlCreateButton("OK",     10,         $iBtnY, $iBW, 26)
	Local $idCancel = GUICtrlCreateButton("Cancel", 20 + $iBW,  $iBtnY, $iBW, 26)

	GUISetState(@SW_SHOW, $hDlg)

	While True
		Local $aDlgMsg = GUIGetMsg(1)
		Local $iDlgMsg = $aDlgMsg[0]

		If ($iDlgMsg = $GUI_EVENT_CLOSE And $aDlgMsg[1] = $hDlg) Or $iDlgMsg = $idCancel Then
			ExitLoop
		EndIf

		If $iDlgMsg = $idOK Then
			Local $aCheckedNames[0]
			For $i = 0 To $iAllCount - 1
				If _GUICtrlListView_GetItemChecked($hLV, $i) Then
					Local $n = UBound($aCheckedNames)
					ReDim $aCheckedNames[$n + 1]
					$aCheckedNames[$n] = $aAllApps[$i][0]
				EndIf
			Next
			Local $iChecked = UBound($aCheckedNames)

			If $iChecked = 0 Then
				MsgBox(BitOR($MB_OK, $MB_ICONWARNING, $MB_SYSTEMMODAL), "Configure Toolbar", _
						"Please select at least one app, or click Cancel to close without changes.")
				ContinueLoop
			EndIf

			If $iChecked > 10 Then
				MsgBox(BitOR($MB_OK, $MB_ICONWARNING, $MB_SYSTEMMODAL), "Configure Toolbar", _
						"You have selected " & $iChecked & " apps. Maximum is 10." & @CRLF & @CRLF & _
						"Please deselect " & ($iChecked - 10) & " app(s) and try again.")
				ContinueLoop
			EndIf

			$g_sToolbarApps = _ArrayToString($aCheckedNames, "|")
			IniWrite($patchStatesINI, "Info", "ToolbarApps", $g_sToolbarApps)
			GUIDelete($hDlg)
			_RefreshAppsToolbar()
			Return
		EndIf
	WEnd

	GUIDelete($hDlg)
EndFunc

Func _ReloadAdobeNow()
	LogWrite(1, @CRLF & "Reloading Adobe - stopping the Adobe process/service tree so patched files reload...")
	Local $iSurvived = _StopAllAdobeProcesses()
	If $iSurvived = 0 Then
		LogWrite(1, "Adobe reloaded cleanly. Patched files will load next time Creative Cloud is opened.")
	Else
		LogWrite(1, $iSurvived & " Adobe process(es) survived - if the Install/Open state misbehaves, a full restart will clear it.")
	EndIf
EndFunc

Func _SuppressCCTutorials()
	Local $sOOBE = @LocalAppDataDir & "\Adobe\OOBE"
	If Not FileExists($sOOBE) Then Return
	Local $aFiles = _FileListToArray($sOOBE, "*.prefs", 1)
	If Not IsArray($aFiles) Then Return
	Local $iChanged = 0
	For $i = 1 To $aFiles[0]
		Local $sPath = $sOOBE & "\" & $aFiles[$i]
		Local $sContent = FileRead($sPath)
		If @error Or Not StringInStr($sContent, 'statusLight">0<') Then ContinueLoop
		Local $sNew = StringReplace($sContent, 'statusLight">0<', 'statusLight">1<')
		If $sNew <> $sContent Then
			Local $hF = FileOpen($sPath, 2)
			If $hF <> -1 Then
				FileWrite($hF, $sNew)
				FileClose($hF)
				$iChanged += 1
			EndIf
		EndIf
	Next
	If $iChanged > 0 Then LogWrite(1, "CC onboarding: marked tutorials as seen in " & $iChanged & " prefs file(s).")
EndFunc

