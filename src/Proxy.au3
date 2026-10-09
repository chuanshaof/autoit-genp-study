; =====================================================================
; Proxy.au3  -  Application module.
; Functions (26):
;   - _IsMitmproxyInstalled
;   - _IsMitmproxyRunning
;   - _IsMitmproxyCertTrusted
;   - _IsWindowsProxyOn
;   - _SetupMitmproxy
;   - _FindFreeMitmproxyPort
;   - _StartMitmproxy
;   - _StopMitmproxy
;   - _EnableWindowsProxy
;   - _DisableWindowsProxy
;   - _BroadcastInternetSettingsChange
;   - _RemoveMitmproxy
;   - _ShowProxyTargetingDialog
;   - _ProxyScanPathApps
;   - _GetMitmproxyStatusText
;   - _RefreshProxyStatus
;   - _CreateMitmproxyLogWindow
;   - _OpenMitmproxyLogWindow
;   - _RefreshLogWindowStatus
;   - _StyleLogRange
;   - _AppendToLogWindow
;   - _PollMitmproxyLog
;   - _GenP_WM_CLOSE
;   - _GenP_WM_SIZE
;   - _GenP_WM_ACTIVATE
;   - _TriggerOneOffCaptureAndLaunch
; =====================================================================

Func _IsMitmproxyInstalled()
	Return FileExists($g_sMITM_EXE) And FileExists($g_sMITM_SCRIPT)
EndFunc

Func _IsMitmproxyRunning()
	If $g_iMitmproxyPID <> 0 And ProcessExists($g_iMitmproxyPID) Then Return True
	Local $iPID = ProcessExists("mitmdump.exe")
	If $iPID > 0 Then
		$g_iMitmproxyPID = $iPID
		Return True
	EndIf
	$g_iMitmproxyPID = 0
	Return False
EndFunc

Func _IsMitmproxyCertTrusted()
	Local $iExit = RunWait(@ComSpec & ' /c certutil -store Root mitmproxy >nul 2>&1', "", @SW_HIDE)
	Return ($iExit = 0)
EndFunc

Func _IsWindowsProxyOn()
	Local $iEnabled = RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings", "ProxyEnable")
	If @error Then Return False
	Return ($iEnabled = 1)
EndFunc

Func _SetupMitmproxy()
	If Not IsAdmin() Then Return SetError(1, 0, False)

	Local $bWasRunning = _IsMitmproxyRunning()
	If $bWasRunning Then
		_StopMitmproxy()
		Sleep(500)
	EndIf

	If Not FileExists($g_sMITM_DIR) Then DirCreate($g_sMITM_DIR)

	If Not FileExists($g_sMITM_EXE) Then
		Local $bDeployed = FileInstall("resources\mitmproxy\mitmdump.exe", $g_sMITM_EXE, 1)
		If Not $bDeployed Or Not FileExists($g_sMITM_EXE) Then Return SetError(2, 0, False)
	EndIf

	Local $bScriptDeployed = FileInstall("resources\mitmproxy\mitmproxy_genuine_fullguard.py", $g_sMITM_SCRIPT, 1)
	If Not $bScriptDeployed Or Not FileExists($g_sMITM_SCRIPT) Then Return SetError(3, 0, False)

	Local $sCertPath = @UserProfileDir & "\.mitmproxy\mitmproxy-ca-cert.cer"
	If Not FileExists($sCertPath) Then
		EnvSet("PYTHONUNBUFFERED", "1")
		Local $iGenPID = Run('"' & $g_sMITM_EXE & '" --listen-port 0 --set termlog_verbosity=warn', $g_sMITM_DIR, @SW_HIDE)
		Local $hTimeout = TimerInit()
		While TimerDiff($hTimeout) < 20000
			If FileExists($sCertPath) Then ExitLoop
			Sleep(200)
		WEnd
		If $iGenPID > 0 Then ProcessClose($iGenPID)
		ProcessClose("mitmdump.exe")
		If Not FileExists($sCertPath) Then Return SetError(4, 0, False)
	EndIf

	If Not _IsMitmproxyCertTrusted() Then
		Local $sTmpLog = @TempDir & "\genp_certutil.log"
		FileDelete($sTmpLog)
		Local $iExit = RunWait(@ComSpec & ' /c certutil -addstore -f Root "' & $sCertPath & '" > "' & $sTmpLog & '" 2>&1', "", @SW_HIDE)
		$g_sLastCertError = ""
		If FileExists($sTmpLog) Then
			$g_sLastCertError = FileRead($sTmpLog)
			FileDelete($sTmpLog)
		EndIf
		If Not _IsMitmproxyCertTrusted() Then Return SetError(5, $iExit, False)
	EndIf

	If $bWasRunning Then _StartMitmproxy()

	Return True
EndFunc

Func _FindFreeMitmproxyPort()
	TCPStartup()
	Local $iFoundPort = 0
	For $iPort = 8080 To 8089
		Local $iListen = TCPListen("127.0.0.1", $iPort)
		If $iListen <> -1 Then
			TCPCloseSocket($iListen)
			$iFoundPort = $iPort
			ExitLoop
		EndIf
	Next
	TCPShutdown()
	Return $iFoundPort
EndFunc

Func _StartMitmproxy()
	If _IsMitmproxyRunning() Then Return True
	If Not _IsMitmproxyInstalled() Then Return SetError(1, 0, False)

	Local $iPort = _FindFreeMitmproxyPort()
	If $iPort = 0 Then Return SetError(4, 0, False)
	$g_sMITM_PORT = String($iPort)
	$g_sMITM_PROXY = "127.0.0.1:" & $g_sMITM_PORT

	EnvSet("PYTHONUNBUFFERED", "1")
	EnvSet("GENP_PROXYMODE", IniRead($sINIPath, "Options", "ProxyMode", "Global"))
	EnvSet("GENP_PROXYAPPS", IniRead($sINIPath, "Options", "ProxyApps", "Global"))

	Local $sCmd = '"' & $g_sMITM_EXE & '" -s "' & $g_sMITM_SCRIPT & '"' & _
			' --listen-port ' & $g_sMITM_PORT & _
			' --quiet' & _
			' --set connection_strategy=lazy' & _
			' --set console_eventlog_verbosity=error' & _
			' --set termlog_verbosity=error'
	$g_iMitmproxyPID = Run($sCmd, $g_sMITM_DIR, @SW_HIDE, BitOR($STDOUT_CHILD, $STDERR_CHILD))
	If $g_iMitmproxyPID = 0 Then Return SetError(2, 0, False)

	Sleep(1500)
	If Not ProcessExists($g_iMitmproxyPID) Then
		$g_iMitmproxyPID = 0
		Return SetError(3, 0, False)
	EndIf

	If _IsWindowsProxyOn() Then _EnableWindowsProxy()

	AdlibRegister("_PollMitmproxyLog", 250)
	_RefreshLogWindowStatus()
	Return True
EndFunc

Func _StopMitmproxy()
	If $g_iMitmproxyPID <> 0 And ProcessExists($g_iMitmproxyPID) Then
		If $g_bMitmLogWindowExists Then
			_AppendToLogWindow(StdoutRead($g_iMitmproxyPID))
			_AppendToLogWindow(StderrRead($g_iMitmproxyPID))
		EndIf
		ProcessClose($g_iMitmproxyPID)
	EndIf
	ProcessClose("mitmdump.exe")
	$g_iMitmproxyPID = 0
	AdlibUnRegister("_PollMitmproxyLog")
	If $g_bMitmLogWindowExists Then
		_AppendToLogWindow(@CRLF & "# mitmdump stopped." & @CRLF & @CRLF)
		_RefreshLogWindowStatus()
	EndIf
	Return True
EndFunc

Func _EnableWindowsProxy()
	RegWrite("HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings", "ProxyEnable", "REG_DWORD", 1)
	RegWrite("HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings", "ProxyServer", "REG_SZ", $g_sMITM_PROXY)
	_BroadcastInternetSettingsChange()
	RunWait(@ComSpec & ' /c netsh winhttp set proxy "' & $g_sMITM_PROXY & '"', "", @SW_HIDE)
	Return True
EndFunc

Func _DisableWindowsProxy()
	RegWrite("HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings", "ProxyEnable", "REG_DWORD", 0)
	_BroadcastInternetSettingsChange()
	RunWait(@ComSpec & ' /c netsh winhttp reset proxy', "", @SW_HIDE)
	Return True
EndFunc

Func _BroadcastInternetSettingsChange()
	Local $hWinINet = DllOpen("wininet.dll")
	If $hWinINet <> -1 Then
		DllCall($hWinINet, "int", "InternetSetOptionW", "ptr", 0, "dword", 39, "ptr", 0, "dword", 0)
		DllCall($hWinINet, "int", "InternetSetOptionW", "ptr", 0, "dword", 37, "ptr", 0, "dword", 0)
		DllClose($hWinINet)
	EndIf
EndFunc

Func _RemoveMitmproxy()
	If Not IsAdmin() Then Return SetError(1, 0, False)

	_StopMitmproxy()
	Sleep(300)

	If _IsWindowsProxyOn() Then _DisableWindowsProxy()
	RunWait(@ComSpec & ' /c netsh winhttp reset proxy', "", @SW_HIDE)

	RunWait(@ComSpec & ' /c certutil -delstore Root mitmproxy', "", @SW_HIDE)

	_RemoveGudeCleanup()

	If FileExists($g_sMITM_DIR) Then DirRemove($g_sMITM_DIR, 1)
	Local $sGenPDataDir = @AppDataCommonDir & "\GenP"
	If FileExists($sGenPDataDir) Then DirRemove($sGenPDataDir, 1)

	Return True
EndFunc

Func _ShowProxyTargetingDialog()
	Local $aApps = _DiscoverAdobeApps()
	If UBound($aApps) = 0 Then $aApps = _ProxyScanPathApps()
	Local $iAppCount = UBound($aApps)

	Local $sCurMode = IniRead($sINIPath, "Options", "ProxyMode", "Global")
	Local $sCurApps = IniRead($sINIPath, "Options", "ProxyApps", "Global")
	Local $bTargeted = (StringLower(StringStripWS($sCurMode, 3)) = "target")

	Local $iDW = 300, $iListH = 190
	Local $iDH = 56 + $iListH + 14 + 26 + 12
	Local $hDlg = GUICreate("Proxy Targeting", $iDW, $iDH, -1, -1, _
		BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), $WS_EX_TOPMOST, $MyhGUI)
	If FileExists(@ScriptDir & "\Skull.ico") Then GUISetIcon(@ScriptDir & "\Skull.ico", 0, $hDlg)
	_CentreGui($hDlg, $iDW, $iDH)

	Local $idRadGen = GUICtrlCreateRadio("Global - all Adobe traffic (Recommended)", 12, 10, $iDW - 24, 18)
	Local $idRadTgt = GUICtrlCreateRadio("Targeted - only the apps ticked below (max 4)", 12, 30, $iDW - 24, 18)
	If $bTargeted Then
		GUICtrlSetState($idRadTgt, $GUI_CHECKED)
	Else
		GUICtrlSetState($idRadGen, $GUI_CHECKED)
	EndIf

	Local $idLV = GUICtrlCreateListView("", 12, 56, $iDW - 24, $iListH, _
		BitOR($LVS_REPORT, $LVS_NOCOLUMNHEADER, $LVS_SHOWSELALWAYS))
	Local $hLV = GUICtrlGetHandle($idLV)
	_GUICtrlListView_SetExtendedListViewStyle($hLV, BitOR($LVS_EX_CHECKBOXES, $LVS_EX_FULLROWSELECT))
	_GUICtrlListView_AddColumn($hLV, "", $iDW - 46)

	Local $sCurNorm = "," & StringLower(StringReplace($sCurApps, " ", "")) & ","
	For $i = 0 To $iAppCount - 1
		_GUICtrlListView_AddItem($hLV, $aApps[$i][0])
		If $bTargeted And StringInStr($sCurNorm, "," & StringLower(StringReplace($aApps[$i][0], " ", "")) & ",") Then _
			_GUICtrlListView_SetItemChecked($hLV, $i, True)
	Next
	If Not $bTargeted Then GUICtrlSetState($idLV, $GUI_DISABLE)
	If $iAppCount = 0 Then GUICtrlSetState($idRadTgt, $GUI_DISABLE)

	Local $iBtnY = 56 + $iListH + 14
	Local $iBW = Int(($iDW - 36) / 2)
	Local $idSave   = GUICtrlCreateButton("Save",   12,        $iBtnY, $iBW, 26)
	Local $idCancel = GUICtrlCreateButton("Cancel", 24 + $iBW, $iBtnY, $iBW, 26)

	GUISetState(@SW_SHOW, $hDlg)

	While True
		Local $aMsg = GUIGetMsg(1)
		Local $iM = $aMsg[0]
		If ($iM = $GUI_EVENT_CLOSE And $aMsg[1] = $hDlg) Or $iM = $idCancel Then ExitLoop
		If $iM = $idRadGen Then GUICtrlSetState($idLV, $GUI_DISABLE)
		If $iM = $idRadTgt Then GUICtrlSetState($idLV, $GUI_ENABLE)
		If $iM = $idSave Then
			Local $sMode = "Global", $sApps = "Global", $iN = 0
			If BitAND(GUICtrlRead($idRadTgt), $GUI_CHECKED) Then
				Local $sList = ""
				For $i = 0 To $iAppCount - 1
					If _GUICtrlListView_GetItemChecked($hLV, $i) Then
						$sList &= ($sList = "" ? "" : ", ") & $aApps[$i][0]
						$iN += 1
					EndIf
				Next
				If $iN >= 1 And $iN <= 4 Then
					$sMode = "Target"
					$sApps = $sList
				EndIf
			EndIf
			IniWrite($sINIPath, "Options", "ProxyMode", $sMode)
			IniWrite($sINIPath, "Options", "ProxyApps", $sApps)
			GUIDelete($hDlg)
			Local $sBody = "Saved." & @CRLF & @CRLF & _
				"Mode: " & ($sMode = "Target" ? "Targeted (" & $sApps & ")" : "Global (recommended)") & "."
			If $iN > 4 Then $sBody &= @CRLF & @CRLF & "(You ticked " & $iN & " apps; the maximum is 4, so Global is used.)"
			$sBody &= @CRLF & @CRLF & "If the proxy is running, use Start / Stop Proxy to restart it and apply the change."
			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION, $MB_SYSTEMMODAL), "Proxy Targeting", $sBody)
			Return
		EndIf
	WEnd
	GUIDelete($hDlg)
EndFunc

Func _ProxyScanPathApps()
	Local $aApps[0][2]
	If $MyDefPath = "" Or Not FileExists($MyDefPath) Then Return $aApps
	Local $aDirs = _FileListToArray($MyDefPath, "*", 2)
	If @error Or Not IsArray($aDirs) Then Return $aApps
	Local $mSeen = ObjCreate("Scripting.Dictionary")
	For $i = 1 To $aDirs[0]
		Local $sName = $aDirs[$i]
		$sName = StringRegExpReplace($sName, "(?i)^Adobe\s+", "")
		$sName = StringRegExpReplace($sName, "\s*\d{4}.*$", "")
		$sName = StringRegExpReplace($sName, "(?i)\s*\(Beta\).*$|\s*Beta$", "")
		$sName = StringStripWS($sName, 3)
		If $sName = "" Then ContinueLoop
		If $mSeen.Exists(StringLower($sName)) Then ContinueLoop
		$mSeen.Item(StringLower($sName)) = 1
		Local $iN = UBound($aApps)
		ReDim $aApps[$iN + 1][2]
		$aApps[$iN][0] = $sName
		$aApps[$iN][1] = ""
	Next
	Return $aApps
EndFunc

Func _GetMitmproxyStatusText()
	Local $sStatus
	If _IsMitmproxyInstalled() Then
		$sStatus = "Installed"
	Else
		$sStatus = "Not installed"
	EndIf
	If _IsMitmproxyRunning() Then
		$sStatus &= "  |  Running"
	Else
		$sStatus &= "  |  Stopped"
	EndIf
	If _IsMitmproxyCertTrusted() Then
		$sStatus &= "  |  Cert trusted"
	Else
		$sStatus &= "  |  Cert NOT trusted"
	EndIf
	If _IsWindowsProxyOn() Then
		$sStatus &= "  |  Proxy ON"
	Else
		$sStatus &= "  |  Proxy off"
	EndIf
	Return $sStatus
EndFunc

Func _RefreshProxyStatus()
	If $g_idLblProxyStatus = 0 Then Return
	GUICtrlSetData($g_idLblProxyStatus, "Status: " & _GetMitmproxyStatusText())
	If _IsMitmproxyInstalled() And _IsMitmproxyRunning() And _IsMitmproxyCertTrusted() And _IsWindowsProxyOn() Then
		GUICtrlSetColor($g_idLblProxyStatus, 0x008000)
	ElseIf _IsMitmproxyInstalled() Then
		GUICtrlSetColor($g_idLblProxyStatus, 0xB87333)
	Else
		GUICtrlSetColor($g_idLblProxyStatus, 0x808080)
	EndIf
EndFunc

Func _CreateMitmproxyLogWindow()
	If $g_bMitmLogWindowExists Then Return

	Local $iW = 900, $iH = 600
	Local $iBgColor = 0x1E1E1E

	$g_hMitmLogWin = GUICreate("GenP - Heartbeat Suppression Log", $iW, $iH, -1, -1, _
			BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS), $WS_EX_TOOLWINDOW)
	GUISetBkColor($iBgColor, $g_hMitmLogWin)

	If FileExists(@ScriptDir & "\Skull.ico") Then
		GUISetIcon(@ScriptDir & "\Skull.ico", 0, $g_hMitmLogWin)
	Else
		GUISetIcon(@ScriptFullPath, 0, $g_hMitmLogWin)
	EndIf

	GUICtrlCreateLabel("Status:", 10, 14, 50, 18)
	GUICtrlSetColor(-1, 0xFFFFFF)
	GUICtrlSetBkColor(-1, $iBgColor)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
	GUICtrlSetResizing(-1, BitOR($GUI_DOCKLEFT, $GUI_DOCKTOP, $GUI_DOCKSIZE))

	$g_idLblLogStatus = GUICtrlCreateLabel("(not started)", 65, 14, 250, 18)
	GUICtrlSetColor($g_idLblLogStatus, 0xF44747)
	GUICtrlSetBkColor($g_idLblLogStatus, $iBgColor)
	GUICtrlSetFont($g_idLblLogStatus, 9, 700, 0, "Segoe UI")
	GUICtrlSetResizing($g_idLblLogStatus, BitOR($GUI_DOCKLEFT, $GUI_DOCKTOP, $GUI_DOCKSIZE))

	$g_idBtnLogClear = GUICtrlCreateButton("Clear", $iW - 305, 8, 90, 28)
	GUICtrlSetFont($g_idBtnLogClear, 9, 400, 0, "Segoe UI")
	GUICtrlSetResizing($g_idBtnLogClear, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKSIZE))

	$g_idBtnLogAddToHosts = GUICtrlCreateButton("Add hosts", $iW - 205, 8, 90, 28)
	GUICtrlSetFont($g_idBtnLogAddToHosts, 9, 400, 0, "Segoe UI")
	GUICtrlSetResizing($g_idBtnLogAddToHosts, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKSIZE))

	$g_idBtnLogClose = GUICtrlCreateButton("Close", $iW - 105, 8, 90, 28)
	GUICtrlSetFont($g_idBtnLogClose, 9, 400, 0, "Segoe UI")
	GUICtrlSetResizing($g_idBtnLogClose, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKSIZE))

	$g_hMitmRichEdit = _GUICtrlRichEdit_Create($g_hMitmLogWin, "", _
			10, 46, $iW - 20, $iH - 60, _
			BitOR($ES_MULTILINE, $ES_READONLY, $ES_AUTOVSCROLL, $WS_VSCROLL))
	_GUICtrlRichEdit_SetBkColor($g_hMitmRichEdit, $iBgColor)
	_GUICtrlRichEdit_SetCharColor($g_hMitmRichEdit, 0xD4D4D4)
	_GUICtrlRichEdit_SetFont($g_hMitmRichEdit, 9, "Consolas")

	$g_bMitmLogWindowExists = True

	_AppendToLogWindow("# GenP Heartbeat Suppression - Live Log" & @CRLF)
	_AppendToLogWindow("# This window streams mitmdump's stdout/stderr in real time." & @CRLF)
	_AppendToLogWindow("# Output begins when you Start the Proxy." & @CRLF & @CRLF)
EndFunc

Func _OpenMitmproxyLogWindow()
	If $g_bMitmLogWindowExists Then
		Local $iState = WinGetState($g_hMitmLogWin)
		If BitAND($iState, 2) Then
			GUISetState(@SW_HIDE, $g_hMitmLogWin)
			Return
		EndIf
	Else
		_CreateMitmproxyLogWindow()
	EndIf
	GUISetState(@SW_SHOW, $g_hMitmLogWin)
	GUISwitch($MyhGUI)
	_RefreshLogWindowStatus()
EndFunc

Func _RefreshLogWindowStatus()
	If Not $g_bMitmLogWindowExists Then Return
	If _IsMitmproxyRunning() Then
		GUICtrlSetData($g_idLblLogStatus, "Running (PID " & $g_iMitmproxyPID & ")")
		GUICtrlSetColor($g_idLblLogStatus, 0x4EC9B0)
	Else
		GUICtrlSetData($g_idLblLogStatus, "Stopped")
		GUICtrlSetColor($g_idLblLogStatus, 0xF44747)
	EndIf
EndFunc

Func _StyleLogRange($iStart, $iEnd)
	If $iEnd <= $iStart Then Return
	_GUICtrlRichEdit_SetSel($g_hMitmRichEdit, $iStart, $iEnd)
	_GUICtrlRichEdit_SetCharColor($g_hMitmRichEdit, 0xD4D4D4)
	_GUICtrlRichEdit_SetFont($g_hMitmRichEdit, 9, "Consolas")
	_GUICtrlRichEdit_Deselect($g_hMitmRichEdit)
EndFunc

Func _AppendToLogWindow($sText)
	If Not $g_bMitmLogWindowExists Then Return
	If $sText = "" Then Return
	$sText = StringRegExpReplace($sText, "\x1B\[[0-9;]*[a-zA-Z]", "")

	If Not $g_bHostsInjectInProgress And StringInStr($sText, "adobestats.io") Then
		Local $aDomainMatch = StringRegExp($sText, '(?i)([A-Za-z0-9_.-]+\.adobestats\.io)', 1)
		If Not @error Then
			Local $sCapturedDomain = StringLower($aDomainMatch[0])
			_SilentHostsInjector($sCapturedDomain)
		EndIf
	EndIf

	Local $iStart = _GUICtrlRichEdit_GetTextLength($g_hMitmRichEdit)
	_GUICtrlRichEdit_AppendText($g_hMitmRichEdit, $sText)
	_StyleLogRange($iStart, _GUICtrlRichEdit_GetTextLength($g_hMitmRichEdit))

	$g_iMitmAppendCounter += 1
	If $g_iMitmAppendCounter >= 100 Then
		$g_iMitmAppendCounter = 0
		Local $iLen = _GUICtrlRichEdit_GetTextLength($g_hMitmRichEdit)
		If $iLen > $g_iMitmLogCharCap Then
			Local $sCurrent = _GUICtrlRichEdit_GetText($g_hMitmRichEdit)
			Local $iKeepFrom = Int($iLen * 0.2)
			Local $iNL = StringInStr($sCurrent, @LF, 0, 1, $iKeepFrom)
			If $iNL > 0 Then $iKeepFrom = $iNL + 1
			Local $sTrimmed = "# (older log lines trimmed - cap " & $g_iMitmLogCharCap & " chars)" & @CRLF & _
					StringMid($sCurrent, $iKeepFrom)
			_GUICtrlRichEdit_SetText($g_hMitmRichEdit, $sTrimmed)
			_StyleLogRange(0, _GUICtrlRichEdit_GetTextLength($g_hMitmRichEdit))
			_GUICtrlRichEdit_SetSel($g_hMitmRichEdit, -1, -1)
		EndIf
	EndIf
EndFunc

Func _PollMitmproxyLog()
	If $g_iMitmproxyPID = 0 Then Return
	If Not ProcessExists($g_iMitmproxyPID) Then
		If $g_bMitmLogWindowExists Then
			_AppendToLogWindow(StdoutRead($g_iMitmproxyPID))
			_AppendToLogWindow(StderrRead($g_iMitmproxyPID))
			_AppendToLogWindow(@CRLF & "# mitmdump process ended." & @CRLF)
			_RefreshLogWindowStatus()
		EndIf
		$g_iMitmproxyPID = 0
		AdlibUnRegister("_PollMitmproxyLog")
		Return
	EndIf
	Local $sOut = StdoutRead($g_iMitmproxyPID)
	If $sOut <> "" Then _AppendToLogWindow($sOut)
	Local $sErr = StderrRead($g_iMitmproxyPID)
	If $sErr <> "" Then _AppendToLogWindow($sErr)
EndFunc

Func _GenP_WM_CLOSE($hWnd, $iMsg, $wParam, $lParam)
	If $g_bMitmLogWindowExists And $hWnd = $g_hMitmLogWin Then
		GUISetState(@SW_HIDE, $g_hMitmLogWin)
		Return 0
	EndIf
	If FileExists($g_sOVD_EXE) Then FileDelete($g_sOVD_EXE)
	If FileExists($g_sOVD_DIR) Then DirRemove($g_sOVD_DIR, 1)
	If $g_hAppsBar <> 0 Then
		Local $aBarPos = WinGetPos($g_hAppsBar)
		If IsArray($aBarPos) Then
			IniWrite($sINIPath, "Options", "LaunchBarX", $aBarPos[0])
			IniWrite($sINIPath, "Options", "LaunchBarY", $aBarPos[1])
		EndIf
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc

Func _GenP_WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
	If $hWnd = $MyhGUI And $wParam = 0 Then
		_RefreshLog()
	EndIf
	If $hWnd = $MyhGUI And $wParam = 1 Then
		If $g_hAppsBar <> 0 Then GUISetState(@SW_SHOWNOACTIVATE, $g_hAppsBar)
	EndIf
	If $g_bMitmLogWindowExists And $hWnd = $g_hMitmLogWin Then
		Local $iNewW = BitAND($lParam, 0xFFFF)
		Local $iNewH = BitShift($lParam, 16)
		If $iNewW > 40 And $iNewH > 60 Then
			WinMove($g_hMitmRichEdit, "", 10, 46, $iNewW - 20, $iNewH - 60)
		EndIf
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc

Func _GenP_WM_ACTIVATE($hWnd, $iMsg, $wParam, $lParam)
	#forceref $iMsg, $lParam
	If $hWnd = $MyhGUI And BitAND($wParam, 0xFFFF) > 0 Then
		_WinAPI_RedrawWindow($hWnd, 0, 0, BitOR(0x0001, 0x0004, 0x0100, 0x0400))
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc

Func _TriggerOneOffCaptureAndLaunch()
	_AppendToLogWindow("# Initialising targeted application tracking sequence..." & @CRLF)

	Local $bProxyWasRunning = _IsMitmproxyRunning()
	If Not $bProxyWasRunning Then
		_StartMitmproxy()
		_EnableWindowsProxy()
		_RefreshProxyStatus()
		_AppendToLogWindow("# Local interception proxy activated." & @CRLF)
	EndIf

	Local $sAppExecutable = FileOpenDialog("Select the Adobe App Showing the Popup", @ProgramFilesDir & "\Adobe\", "Applications (*.exe)")
	If @error Then
		_AppendToLogWindow("# Capture sequence aborted by user." & @CRLF)
		If Not $bProxyWasRunning Then
			_StopMitmproxy()
			_DisableWindowsProxy()
			_RefreshProxyStatus()
		EndIf
		Return False
	EndIf

	Local $sAppName = StringRegExpReplace($sAppExecutable, '^.*\\', '')
	_AppendToLogWindow("# Spawning background sandbox instance: " & $sAppName & @CRLF)

	Local $sPreExistingPIDs = "|"
	Local $aPre = ProcessList($sAppName)
	If IsArray($aPre) Then
		For $iP = 1 To $aPre[0][0]
			$sPreExistingPIDs &= $aPre[$iP][1] & "|"
		Next
	EndIf

	Local $iAppPID = Run('"' & $sAppExecutable & '"', "", @SW_SHOWMINIMIZED)
	If @error Then
		_AppendToLogWindow("# Error: Failed to execute targeted process binary." & @CRLF)
		If Not $bProxyWasRunning Then
			_StopMitmproxy()
			_DisableWindowsProxy()
			_RefreshProxyStatus()
		EndIf
		Return False
	EndIf

	Local $hTimer = TimerInit()
	Local $bCaptured = False
	Local $sCapturedDomain = ""

	_AppendToLogWindow("# Catching dynamic domain from memory maps (exits on detection; max 45s)..." & @CRLF)

	While TimerDiff($hTimer) < 45000
		Sleep(400)

		_PollMitmproxyLog()

		Local $sLogText = _GUICtrlRichEdit_GetText($g_hMitmRichEdit)
		If StringStripWS($sLogText, 3) <> "" Then
			Local $aDomainMatch = StringRegExp($sLogText, '(?i)([A-Za-z0-9_.-]+\.adobestats\.io)', 1)
			If Not @error Then
				$sCapturedDomain = StringLower($aDomainMatch[0])
				_SilentHostsInjector($sCapturedDomain)
				$bCaptured = True
				ExitLoop
			EndIf
		EndIf
	WEnd

	Local $iClosed = 0
	Local $aPost = ProcessList($sAppName)
	If IsArray($aPost) Then
		For $iP = 1 To $aPost[0][0]
			Local $iThisPID = $aPost[$iP][1]
			If Not StringInStr($sPreExistingPIDs, "|" & $iThisPID & "|") Then
				If ProcessExists($iThisPID) Then
					ProcessClose($iThisPID)
					$iClosed += 1
				EndIf
			EndIf
		Next
	EndIf
	If ProcessExists($iAppPID) Then
		ProcessClose($iAppPID)
		$iClosed += 1
	EndIf
	_AppendToLogWindow("# Closed " & $iClosed & " launched instance(s) of " & $sAppName & " (pre-existing copies left running)." & @CRLF)

	If Not $bProxyWasRunning Then
		_AppendToLogWindow("# Cleaning environment: Shutting down capture engine..." & @CRLF)
		_StopMitmproxy()
		_DisableWindowsProxy()
		_RefreshProxyStatus()
		_AppendToLogWindow("# Environment restored to default system network maps cleanly." & @CRLF)
	Else
		_AppendToLogWindow("# Leaving existing proxy session running (it was active before this capture)." & @CRLF)
		_RefreshProxyStatus()
	EndIf

	If $bCaptured Then
		MsgBox(64, "Success", "Adobe Endpoint Block updated successfully via " & StringReplace($sAppName, ".exe", "") & "!" & @CRLF & @CRLF & _
				"Block Rule Entries:" & @CRLF & _
				"0.0.0.0 ic.adobe.io" & @CRLF & _
				"0.0.0.0 " & $sCapturedDomain & @CRLF & @CRLF & _
				"The rule has been saved to your hosts file and local DNS cache flushed.")
	Else
		_AppendToLogWindow("# Warning: Capture sequence timed out." & @CRLF)
		MsgBox(48, "Capture Failure", "Timed out trying to grab the background token from " & $sAppName & "." & @CRLF & _
				"Please run your Adobe app normally and click 'Add hosts'" & @CRLF & "manually from the log window instead.")
	EndIf
	Return $bCaptured
EndFunc

