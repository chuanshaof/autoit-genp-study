; =====================================================================
; Ui.au3  -  Application module.
; Functions (53):
;   - _SetState
;   - MainGui
;   - _MsgBoxCBTProc
;   - _PrecacheDisplayAssets
;   - _RenderTextMetricBuffer
;   - _GetCpTranslation
;   - FillListViewWithInfo
;   - _ShowUpdateNoticeIfNeeded
;   - FillListViewWithFiles
;   - _ApplyVisibilityFilter
;   - MemoWrite
;   - LogWrite
;   - ToggleLog
;   - _RefreshLog
;   - SendToClipBoard
;   - GUICtrlSetDataEx
;   - ProgressWrite
;   - _SubProgressWrite
;   - _SnapshotOptions
;   - _ShowEmptyModifiedNotice
;   - CheckOptionsChanged
;   - _RestorePostOpUI
;   - _ApplyModifiedFilter
;   - _LockOptionsUIForScan
;   - _UnlockOptionsUIAfterScan
;   - UpdateUIState
;   - _RefreshSearch
;   - _ShowStatusScreen
;   - _PrepStatusScreenLayout
;   - _PrettifyScanDir
;   - _AnimatedDots
;   - _AnimatedDotsOnly
;   - _FormatNumber
;   - _ResetScanCounters
;   - _BumpScanCounters
;   - _HideStatusScreen
;   - _UpdateStatusDetail
;   - _BrowseForFolderDialog
;   - _CentreGui
;   - MyFileOpenDialog
;   - _ListView_LeftClick
;   - _ListView_RightClick
;   - _UpdateCollapseHeader
;   - _Collapse_All_Click
;   - _Expand_All_Click
;   - _SendMessageL
;   - _RedrawWindow
;   - WM_COMMAND
;   - WM_NOTIFY
;   - hL_WM_COMMAND
;   - ShowInfoPopup
;   - ShowRebootPopup
;   - _MonoInfoBox
; =====================================================================

Func _SetState($aIds, $iState)
	For $i = 0 To UBound($aIds) - 1
		GUICtrlSetState($aIds[$i], $iState)
	Next
EndFunc

; =====================================================================
; MainGui()  -  BUILD the main window ONCE (construction, not behavior).
;   Runs top-to-bottom. Pattern repeated per tab:
;     open a tab  GUICtrlCreateTabItem("Name") -> create its controls
;     -> close it GUICtrlCreateTabItem("")     -> next tab.
;   All controls are built while the window is HIDDEN; GUISetState(@SW_SHOW)
;   near the end reveals the finished window in one shot. The $idBtn... IDs
;   captured here are exactly what the event loop in main.au3 switches on.
; =====================================================================
Func MainGui()
	$MyhGUI = GUICreate($g_AppWndTitle, 595, 610, -1, -1, BitOR($WS_MINIMIZEBOX, $GUI_SS_DEFAULT_GUI))
	_MsgBoxCenterInit()
	If FileExists(@ScriptDir & "\Skull.ico") Then GUISetIcon(@ScriptDir & "\Skull.ico", 0, $MyhGUI)
	$hTab = GUICtrlCreateTab(0, 1, 597, 610, $TCS_FIXEDWIDTH)
	_SendMessage(GUICtrlGetHandle($hTab), 0x1329, 0, 74)

	; ----- TAB 1: Main ----- file list, Search/Patch/Restore/Modified buttons, progress bars
	$hMainTab = GUICtrlCreateTabItem("Main")
	$idListview = GUICtrlCreateListView("", 10, 35, 575, 385)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)
	$g_idListview = GUICtrlGetHandle($idListview)
	_GUICtrlListView_SetExtendedListViewStyle($g_idListview, BitOR($LVS_EX_CHECKBOXES, $LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER))
	_GUICtrlListView_SetItemCount($idListview, UBound($FilesToPatch))
	_GUICtrlListView_AddColumn($idListview, "", 20)
	_GUICtrlListView_AddColumn($idListview, "  App File", 445, 2)
	_GUICtrlListView_AddColumn($idListview, "Status", 85, 2)

	_GUICtrlListView_EnableGroupView($idListview)
	_GUICtrlListView_InsertGroup($idListview, -1, 1, "", 1)
	_GUICtrlListView_SetGroupInfo($idListview, 1, "", 1, $LVGS_COLLAPSIBLE)

	FillListViewWithInfo()

	$idBtnUncheckAll = GUICtrlCreateButton("Uncheck All", 28, 430, 94, 25)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnCheckAll = GUICtrlCreateButton("Check All", 140, 430, 94, 25)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnCheckUnpatched = GUICtrlCreateButton("Unpatched", 251, 430, 94, 25)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnCheckPatched = GUICtrlCreateButton("Patched", 363, 430, 94, 25)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnRefresh = GUICtrlCreateButton("Refresh", 475, 430, 94, 25)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnCollapseAll = GUICtrlCreateDummy()
	$idBtnExpandAll = GUICtrlCreateDummy()

	GUICtrlCreateLabel("", 9, 468, 577, 27, $SS_BLACKFRAME)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)
	GUICtrlCreateLabel("", 9, 492, 577, 7, $SS_BLACKFRAME)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idProgressBar = GUICtrlCreateProgress(10, 469, 575, 25, $PBS_SMOOTH)
	_WinAPI_SetWindowTheme(GUICtrlGetHandle($idProgressBar), "", "")
	GUICtrlSetColor($idProgressBar, 0x00FF00)
	GUICtrlSetResizing(-1, $GUI_DOCKVCENTER)

	$idSubProgress = GUICtrlCreateProgress(10, 493, 575, 5, $PBS_SMOOTH)
	_WinAPI_SetWindowTheme(GUICtrlGetHandle($idSubProgress), "", "")
	GUICtrlSetColor($idSubProgress, 0x00A2E8)
	GUICtrlSetResizing(-1, $GUI_DOCKVCENTER)

	$idButtonCustomFolder = GUICtrlCreateButton(" Path", 28, 520, 94, 32)
	GUICtrlSetFont(-1, 10, 700)
	GUICtrlSetImage(-1, "imageres.dll", -4, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idButtonSearch = GUICtrlCreateButton(" Search", 140, 520, 94, 32)
	GUICtrlSetFont(-1, 10, 700)
	GUICtrlSetImage(-1, "imageres.dll", -8, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idButtonStop = GUICtrlCreateButton(" Stop", 140, 520, 94, 32)
	GUICtrlSetFont(-1, 10, 700)
	GUICtrlSetState(-1, $GUI_HIDE)
	GUICtrlSetImage(-1, "imageres.dll", -8, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnCure = GUICtrlCreateButton(" Patch", 251, 520, 94, 32)
	GUICtrlSetFont(-1, 10, 700)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetImage(-1, "imageres.dll", -102, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnModified = GUICtrlCreateButton(" Modified", 363, 520, 94, 32)
	GUICtrlSetFont(-1, 10, 700)
	GUICtrlSetImage(-1, "imageres.dll", -25, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnRestore = GUICtrlCreateButton(" Restore", 475, 520, 94, 32)
	GUICtrlSetFont(-1, 10, 700)
	GUICtrlSetState(-1, $GUI_DISABLE)
	GUICtrlSetImage(-1, "imageres.dll", -113, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idBtnDeselectAll = GUICtrlCreateDummy()

	$g_idHyperlinkMain = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkMain, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkMain, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkMain, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkMain, 0)

	GUICtrlCreateTabItem("")

	; ----- TAB 2: Options ----- checkboxes initialised from the $b... config globals; Save Options
	$hOptionsTab = GUICtrlCreateTabItem("Options")

	GUICtrlCreateGroup("First Run Options", 5, 35, 585, 90)

	$idCreateStates = GUICtrlCreateCheckbox("Create and populate new patch_states.ini (using location set by Path only)", 15, 60, 460, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	GUICtrlSetState($idCreateStates, $GUI_UNCHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idReconcileStates = GUICtrlCreateCheckbox("Reconcile imported patch_states.ini against current files (using location set by Path only)", 15, 90, 460, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	GUICtrlSetState($idReconcileStates, $GUI_UNCHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	GUICtrlCreateGroup("", -99, -99, 1, 1)

	GUICtrlCreateGroup("Scan Options", 5, 129, 585, 90)

	$idFindACC = GUICtrlCreateCheckbox("Always search for ACC", 15, 154, 278, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bFindACC = 1 Then GUICtrlSetState($idFindACC, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idEnableMD5 = GUICtrlCreateDummy()

	$idOnlyAFolders = GUICtrlCreateCheckbox("Search in default named folders only", 15, 184, 278, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bOnlyAFolders = 1 Then GUICtrlSetState($idOnlyAFolders, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idUseCustomDefault = GUICtrlCreateCheckbox("Use custom default search path:", 300, 154, 278, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bUseCustomDefault = 1 Then GUICtrlSetState($idUseCustomDefault, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	Local $sInitialCustom = ($g_sPendingCustomPath <> "") ? $g_sPendingCustomPath : (@ProgramFilesDir & "\Adobe")
	$idBtnSetCustomPath = GUICtrlCreateLabel($sInitialCustom, 316, 184, 262, 20, $SS_LEFT)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	GUICtrlCreateGroup("", -99, -99, 1, 1)

	GUICtrlCreateGroup("Patch Options", 5, 223, 585, 115)

	$idShowBetaApps = GUICtrlCreateCheckbox("Show Beta apps", 15, 248, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bShowBetaApps = 1 Then GUICtrlSetState($idShowBetaApps, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idEnableGood1 = GUICtrlCreateCheckbox("Enable Good patch", 15, 278, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bEnableGood1 = 1 Then GUICtrlSetState($idEnableGood1, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idShowLaunchBar = GUICtrlCreateCheckbox("Show app launch toolbar", 300, 248, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bShowLaunchBar = 1 Then GUICtrlSetState($idShowLaunchBar, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idClearLicCaches = GUICtrlCreateCheckbox("Clear license caches after patching", 15, 308, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bClearLicCaches = 1 Then GUICtrlSetState($idClearLicCaches, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idEnableNGLFirewall = GUICtrlCreateCheckbox("Enable NGL Firewall rule", 300, 308, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	If $bEnableNGLFirewall = 1 Then GUICtrlSetState($idEnableNGLFirewall, $GUI_CHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idOlderVerDl = GUICtrlCreateCheckbox("Older versions download", 300, 278, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	GUICtrlSetState($idOlderVerDl, $GUI_UNCHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	GUICtrlCreateGroup("", -99, -99, 1, 1)

	GUICtrlCreateGroup("Hosts Options", 5, 342, 585, 90)

	$idCustomDomainListLabel = GUICtrlCreateLabel("Hosts List URL:", 15, 367, 80, 20)
	$idCustomDomainListInput = GUICtrlCreateInput($sCurrentDomainListURL, 95, 364, 485, 22, BitOR($ES_LEFT, $ES_WANTRETURN, $ES_AUTOHSCROLL))
	GUICtrlSetLimit($idCustomDomainListInput, 255)
	GUICtrlSetResizing($idCustomDomainListInput, $GUI_DOCKWIDTH)

#cs === [PROXY-REMOVED] "trigger one-off capture and launch" checkbox (a proxy-capture control) ===
	Global $idTriggerCaptureLaunch = GUICtrlCreateCheckbox("Trigger one-off capture and launch on save", 15, 397, 400, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	GUICtrlSetState($idTriggerCaptureLaunch, $GUI_UNCHECKED)
#ce === [PROXY-REMOVED] end trigger-capture checkbox ===

	GUICtrlCreateGroup("", -99, -99, 1, 1)

	GUICtrlCreateGroup("Clean Options", 5, 435, 585, 60)

	$idResetOnSave = GUICtrlCreateCheckbox("Reset patch_states.ini", 15, 460, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	GUICtrlSetState($idResetOnSave, $GUI_UNCHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$idFinalCleanCheck = GUICtrlCreateCheckbox("Final Adobe Clean Check", 300, 460, 275, 25, BitOR($BS_AUTOCHECKBOX, $BS_LEFT))
	GUICtrlSetState($idFinalCleanCheck, $GUI_UNCHECKED)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	GUICtrlCreateGroup("", -99, -99, 1, 1)

	$idOptionsReminder = GUICtrlCreateLabel("Changes will not take effect until saved", 10, 505, 575, 20, $SS_CENTER)
	GUICtrlSetFont($idOptionsReminder, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($idOptionsReminder, 0xC62828)
	GUICtrlSetState($idOptionsReminder, $GUI_HIDE)

	$g_idOptionsProgress = GUICtrlCreateProgress(10, 527, 575, 5, $PBS_MARQUEE)
	_WinAPI_SetWindowTheme(GUICtrlGetHandle($g_idOptionsProgress), "", "")
	GUICtrlSetState($g_idOptionsProgress, $GUI_HIDE)

	$idBtnSaveOptions = GUICtrlCreateButton("Save Options", 247, 540, 110, 32)
	GUICtrlSetImage(-1, "imageres.dll", 5358, 0)
	GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$g_idHyperlinkOptions = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkOptions, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkOptions, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkOptions, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkOptions, 0)

	GUICtrlCreateTabItem("")

	; ----- TAB 3: WinTrust ----- toggle WinTrust / reg key, set trust path (-> DevOverride.au3)
	Local $hWinTrustTab = GUICtrlCreateTabItem("WinTrust")

	$sWinTrustText = "WINTRUST"
	$idLabelWinTrust = GUICtrlCreateLabel($sWinTrustText, (595 - 580) / 2, 50, 580, 20, $SS_CENTER)
	GUICtrlSetFont($idLabelWinTrust, 10, 700)

	$idBtnToggleWinTrust = GUICtrlCreateButton("Toggle WinTrust", 227, 90, 140, 32)
	GUICtrlSetFont($idBtnToggleWinTrust, 9, 400, 0, "Segoe UI")

	$idBtnDevOverride = GUICtrlCreateButton("Toggle Reg Key", 227, 135, 140, 32)
	GUICtrlSetFont($idBtnDevOverride, 9, 400, 0, "Segoe UI")

	$idBtnSetTrustPath = GUICtrlCreateButton("Set Trust Path", 227, 225, 140, 32)
	GUICtrlSetFont($idBtnSetTrustPath, 9, 400, 0, "Segoe UI")

	$idLabelTrustPath = GUICtrlCreateLabel("Path: " & $g_sWinTrustPath, 10, 270, 575, 20, $SS_CENTER)
	GUICtrlSetFont($idLabelTrustPath, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($idLabelTrustPath, 0x555555)

	GUICtrlCreateLabel( _
			"Reduce popups by trusting applications that use DLL redirection." & @CRLF & @CRLF & _
			"This feature manages the required registry entry automatically." & @CRLF & @CRLF & _
			"You can trust or untrust applications at any time as needed." & @CRLF & @CRLF & _
			"Credit to Team V.R.", _
			(595 - 580) / 2, 410, 580, 130, $SS_CENTER)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	$idBtnWintrustInfo = GUICtrlCreateDummy()
	$idBtnRuntimeInfo = GUICtrlCreateDummy()
	$idLabelRuntimeInstaller = GUICtrlCreateDummy()
	$idBtnToggleRuntimeInstaller = GUICtrlCreateDummy()

	$g_idHyperlinkWT = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkWT, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkWT, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkWT, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkWT, 0)

	GUICtrlCreateTabItem("")

	; ----- TAB 4: Hosts ----- update/edit/clean/restore/schedule the hosts file (-> Hosts.au3)
	Local $hHostsTab = GUICtrlCreateTabItem("Hosts")

	$sEditHostsText = "HOSTS"
	$idLabelEditHosts = GUICtrlCreateLabel($sEditHostsText, (595 - 580) / 2, 50, 580, 20, $SS_CENTER)
	GUICtrlSetFont($idLabelEditHosts, 10, 700)

	$idBtnUpdateHosts = GUICtrlCreateButton("Update hosts", 227, 90, 140, 32)
	GUICtrlSetFont($idBtnUpdateHosts, 9, 400, 0, "Segoe UI")

	$idBtnEditHosts = GUICtrlCreateButton("Edit hosts", 227, 135, 140, 32)
	GUICtrlSetFont($idBtnEditHosts, 9, 400, 0, "Segoe UI")

	$idBtnCleanHosts = GUICtrlCreateButton("Clean hosts", 227, 180, 140, 32)
	GUICtrlSetFont($idBtnCleanHosts, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnCleanHosts, $GUI_DISABLE)

	$idBtnRestoreHosts = GUICtrlCreateButton("Restore hosts", 227, 225, 140, 32)
	GUICtrlSetState($idBtnRestoreHosts, $GUI_DISABLE)
	GUICtrlSetFont($idBtnRestoreHosts, 9, 400, 0, "Segoe UI")

#cs === [SCHEDULE-HOSTS-REMOVED] Removing single button for schedule updates ===
	$idBtnAutoUpdateHosts = GUICtrlCreateButton("Schedule updates", 227, 270, 140, 32)
	GUICtrlSetFont($idBtnAutoUpdateHosts, 9, 400, 0, "Segoe UI")
#ce === [SCHEDULE-HOSTS-REMOVED] end schedule host tab===

	GUICtrlCreateLabel( _
			"Manage the hosts file to block domains associated with popups." & @CRLF & @CRLF & _
			"Update once from the list URL, edit manually, or restore a backup." & @CRLF & @CRLF & _
			"Use Schedule Updates to set up a scheduled task that refreshes on its own." & @CRLF & @CRLF & _
			"Keeping the hosts file updated helps maintain protection over time.", _
			(595 - 580) / 2, 410, 580, 130, $SS_CENTER)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	$idBtnHostsInfo = GUICtrlCreateDummy()

	$g_idHyperlinkHosts = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkHosts, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkHosts, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkHosts, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkHosts, 0)

	GUICtrlCreateTabItem("")

#cs === [PROXY-REMOVED] Proxy tab (MainGui) - delete this #cs and its matching #ce to restore ===
	; ----- TAB 5: Proxy ----- mitmproxy setup/targeting/start-stop/log/remove (-> Proxy.au3)
	Local $hProxyTab = GUICtrlCreateTabItem("Proxy")

	GUICtrlCreateLabel("PROXY", (595 - 580) / 2, 50, 580, 20, $SS_CENTER)
	GUICtrlSetFont(-1, 10, 700)

	$idBtnProxySetup = GUICtrlCreateButton("Setup", 227, 90, 140, 32)
	GUICtrlSetFont($idBtnProxySetup, 9, 400, 0, "Segoe UI")

	$idBtnProxyTargeting = GUICtrlCreateButton("Targeting", 227, 135, 140, 32)
	GUICtrlSetFont($idBtnProxyTargeting, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnProxyTargeting, $GUI_DISABLE)

	$idBtnProxyStartStop = GUICtrlCreateButton("Start / Stop Proxy", 227, 180, 140, 32)
	GUICtrlSetFont($idBtnProxyStartStop, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnProxyStartStop, $GUI_DISABLE)

	$idBtnProxyOpenLog = GUICtrlCreateButton("Open Log", 227, 225, 140, 32)
	GUICtrlSetFont($idBtnProxyOpenLog, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnProxyOpenLog, $GUI_DISABLE)

	$idBtnProxyRemove = GUICtrlCreateButton("Remove", 227, 270, 140, 32)
	GUICtrlSetFont($idBtnProxyRemove, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnProxyRemove, $GUI_DISABLE)

	$g_idLblProxyStatus = GUICtrlCreateLabel("Status: (refreshing...)", 10, 330, 575, 20, $SS_CENTER)
	GUICtrlSetFont($g_idLblProxyStatus, 9, 700, 0, "Segoe UI")
	GUICtrlSetColor($g_idLblProxyStatus, 0x555555)

	GUICtrlCreateLabel( _
			"Manage mitmproxy to intercept and neutralise Adobe heartbeat traffic." & @CRLF & @CRLF & _
			"Setup installs mitmproxy and trusts the certificate." & @CRLF & @CRLF & _
			"Start / Stop Proxy runs the proxy. Targeting sets Global or specific apps." & @CRLF & @CRLF & _
			"Open Log views activity. Remove uninstalls everything cleanly." & @CRLF & @CRLF & _
			"Credit to MP7909.", _
			(595 - 580) / 2, 410, 580, 160, $SS_CENTER)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	$g_idHyperlinkProxy = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkProxy, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkProxy, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkProxy, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkProxy, 0)

	GUICtrlCreateTabItem("")
#ce === [PROXY-REMOVED] end Proxy tab ===

	; ----- TAB 6: Firewall ----- add/toggle/remove NGL firewall rules (-> Firewall.au3)
	Local $hFirewallTab = GUICtrlCreateTabItem("Firewall")

	$sCleanFirewallText = "FIREWALL"
	$idLabelCleanFirewall = GUICtrlCreateLabel($sCleanFirewallText, (595 - 580) / 2, 50, 580, 20, $SS_CENTER)
	GUICtrlSetFont($idLabelCleanFirewall, 10, 700)

	$idBtnCreateFW = GUICtrlCreateButton("Add Rules", 227, 90, 140, 32)
	GUICtrlSetFont($idBtnCreateFW, 9, 400, 0, "Segoe UI")

	$idBtnToggleFW = GUICtrlCreateButton("Toggle Rules", 227, 135, 140, 32)
	GUICtrlSetFont($idBtnToggleFW, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnToggleFW, $GUI_DISABLE)

	$idBtnRemoveFW = GUICtrlCreateButton("Remove Rules", 227, 180, 140, 32)
	GUICtrlSetFont($idBtnRemoveFW, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnRemoveFW, $GUI_DISABLE)

	$idBtnOpenWF = GUICtrlCreateButton("Open Windows Firewall", 227, 225, 140, 32)
	GUICtrlSetFont($idBtnOpenWF, 9, 400, 0, "Segoe UI")

	GUICtrlCreateLabel( _
			"Manage Firewall rules to block applications from internet access, which may reduce popups." & @CRLF & @CRLF & _
			"Add or remove outbound rules, enable or disable them, or delete all rules." & @CRLF & @CRLF & _
			"Note: Manages Windows Defender Firewall only - third-party firewalls need manual setup." & @CRLF & @CRLF & _
			"Some application features may not function when internet access is blocked.", _
			(595 - 580) / 2, 410, 580, 130, $SS_CENTER)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	$idBtnFirewallInfo = GUICtrlCreateDummy()

	$g_idHyperlinkFW = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkFW, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkFW, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkFW, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkFW, 0)

	GUICtrlCreateTabItem("")

	; ----- TAB 7: AGS ----- remove/dummy/restore Adobe Genuine Service (-> Firewall.au3)
	$hPopupTab = GUICtrlCreateTabItem("AGS")

	$sRemoveAGSText = "GENUINE SERVICES"
	$idLabelRemoveAGS = GUICtrlCreateLabel($sRemoveAGSText, (595 - 580) / 2, 50, 580, 20, $SS_CENTER)
	GUICtrlSetFont($idLabelRemoveAGS, 10, 700)

	$idBtnRemoveAGS = GUICtrlCreateButton("Remove AGS", 227, 90, 140, 32)
	GUICtrlSetFont($idBtnRemoveAGS, 9, 400, 0, "Segoe UI")

	$idBtnDummyAGS = GUICtrlCreateButton("Dummy AGS", 227, 135, 140, 32)
	GUICtrlSetFont($idBtnDummyAGS, 9, 400, 0, "Segoe UI")

	$idBtnRestoreAGS = GUICtrlCreateButton("Restore AGS", 227, 180, 140, 32)
	GUICtrlSetFont($idBtnRestoreAGS, 9, 400, 0, "Segoe UI")
	GUICtrlSetState($idBtnRestoreAGS, $GUI_DISABLE)

	GUICtrlCreateLabel( _
			"Stops 'Adobe Genuine Service Alert' popups by removing the AGS components." & @CRLF & @CRLF & _
			"Or redirecting the services using dummy files to prevent background activity." & @CRLF & @CRLF & _
			"Use Restore AGS to remove all dummies and restore back to originals." & @CRLF & @CRLF & _
			"Note: This applies only to popups with the 'Genuine Service Alert' header.", _
			(595 - 580) / 2, 410, 580, 130, $SS_CENTER)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	$idBtnAGSInfo = GUICtrlCreateDummy()

	$g_idHyperlinkAGS = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkAGS, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkAGS, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkAGS, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkAGS, 0)
	$g_idHyperlinkPopup = $g_idHyperlinkAGS

	GUICtrlCreateTabItem("")

	; ----- TAB 8: Log ----- two read-only text panes: $idMemo (status) and $idLog (activity)
	$hLogTab = GUICtrlCreateTabItem("Log")
	$idMemo = GUICtrlCreateEdit("", 10, 35, 575, 472, BitOR($ES_READONLY, $ES_CENTER, $WS_DISABLED))
	GUICtrlSetResizing(-1, $GUI_DOCKVCENTER)
	GUICtrlSetLimit($idMemo, 0x7FFFFFFF)

	$idLog = GUICtrlCreateEdit("", 10, 35, 575, 472, BitOR($WS_VSCROLL, $ES_AUTOVSCROLL, $ES_READONLY))
	GUICtrlSetResizing(-1, $GUI_DOCKVCENTER)
	GUICtrlSetLimit($idLog, 0x7FFFFFFF)
	GUICtrlSetState($idLog, $GUI_HIDE)
	GUICtrlSetData($idLog, "Activity Log" & @CRLF & "- - - - - - - - - - -" & @CRLF & @CRLF & "GenP Version: " & $g_Version & @CRLF & "Config Version: " & $ConfigVerVar & @CRLF)

	$idBtnCopyLog = GUICtrlCreateButton("Copy", 247, 520, 110, 32)
	GUICtrlSetImage(-1, "imageres.dll", -77, 0)
	GUICtrlSetResizing(-1, $GUI_DOCKAUTO)

	$g_idHyperlinkLog = GUICtrlCreateLabel("GenP Wiki && Guides", (595 - 160) / 2, 580, 160, 24, BitOR($SS_CENTER, $SS_NOTIFY))
	GUICtrlSetFont($g_idHyperlinkLog, 9, 400, 0, "Segoe UI")
	GUICtrlSetColor($g_idHyperlinkLog, 0x000000)
	GUICtrlSetBkColor($g_idHyperlinkLog, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetCursor($g_idHyperlinkLog, 0)

	GUICtrlCreateTabItem("")

	MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "Waiting for user action.")

	; --- Everything above was built into a HIDDEN window; this REVEALS it. ---
	GUISetState(@SW_SHOW)
	; --- Tail wiring: bundle control IDs into groups (for bulk enable/disable
	;     via _SetState), register the low-level WM_ handlers, snapshot options. ---
	; [PROXY-REMOVED] $g_aOptCtrls was [16] and included $idTriggerCaptureLaunch; now [15].
	Global $g_aOptCtrls[15] = [ _
			$idFindACC, $idOnlyAFolders, $idShowBetaApps, $idEnableGood1, _
			$idShowLaunchBar, $idEnableNGLFirewall, $idOlderVerDl, $idResetOnSave, $idClearLicCaches, _
			$idReconcileStates, $idCreateStates, $idUseCustomDefault, _
			$idBtnSetCustomPath, $idCustomDomainListInput, $idFinalCleanCheck]
	Global $g_aToolCtrls[20] = [ _
			$idBtnUpdateHosts, $idBtnCleanHosts, $idBtnEditHosts, $idBtnRestoreHosts, _
			$idBtnCreateFW, $idBtnToggleFW, $idBtnRemoveFW, $idBtnOpenWF, _
			$idBtnToggleRuntimeInstaller, $idBtnToggleWinTrust, $idBtnDevOverride, _
			$idBtnRemoveAGS, $idBtnDummyAGS, $idBtnRestoreAGS, $idBtnSetTrustPath, $idBtnAGSInfo, _
			$idBtnFirewallInfo, $idBtnHostsInfo, $idBtnRuntimeInfo, $idBtnWintrustInfo]
	Global $g_aCheckCtrls[5] = [ _
			$idBtnCheckAll, $idBtnUncheckAll, $idBtnCheckUnpatched, $idBtnCheckPatched, $idBtnRefresh]
	GUICtrlSetState($idButtonSearch, $GUI_FOCUS)

	GUIRegisterMsg($WM_COMMAND, "hL_WM_COMMAND")
	GUIRegisterMsg($WM_NOTIFY, "WM_NOTIFY")
	GUIRegisterMsg($WM_CLOSE, "_GenP_WM_CLOSE")
	GUIRegisterMsg($WM_SIZE,     "_GenP_WM_SIZE")
	GUIRegisterMsg($WM_ACTIVATE, "_GenP_WM_ACTIVATE")

	_SnapshotOptions()

	Local $sAGSFolderStartup = EnvGet("ProgramFiles(x86)") & "\Common Files\Adobe\AdobeGCClient"
	If FileExists($sAGSFolderStartup & "\AdobeGCClient.exe.bak") Or _
			FileExists($sAGSFolderStartup & "\AGMService.exe.bak") Or _
			FileExists($sAGSFolderStartup & "\AGSService.exe.bak") Then
		GUICtrlSetState($idBtnRestoreAGS, $GUI_ENABLE)
	EndIf

	; [PROXY-REMOVED] _RefreshProxyStatus()   ; proxy status label no longer exists
EndFunc

; =====================================================================
; SECONDARY WINDOWS & DISGUISED-NAME HELPERS
;   _MsgBoxCBTProc centers message boxes over the main window.
;   The next three have deliberately misleading names (see GenP-Notes D).
; =====================================================================
Func _MsgBoxCBTProc($nCode, $wParam, $lParam)
	If $nCode = 5 Then
		Local $aCls = DllCall("user32.dll", "int", "GetClassName", "hwnd", $wParam, "wstr", "", "int", 256)
		If IsArray($aCls) And $aCls[2] = "#32770" Then
			Local $aBox = WinGetPos($wParam), $aPar = WinGetPos($MyhGUI)
			If IsArray($aBox) And IsArray($aPar) Then _
				WinMove($wParam, "", $aPar[0] + ($aPar[2] - $aBox[2]) / 2, $aPar[1] + ($aPar[3] - $aBox[3]) / 2)
		EndIf
	EndIf
	Local $aRet = DllCall("user32.dll", "lresult", "CallNextHookEx", "handle", $g_hMsgBoxHook, _
		"int", $nCode, "wparam", $wParam, "lparam", $lParam)
	Return $aRet[0]
EndFunc

; [MISNAMED] Not asset precaching - this builds the WELCOME / about window.
Func _PrecacheDisplayAssets()
	Local $iGuiWidth = 580
	Local $hFontCacheLayoutContext = GUICreate(_GetCpTranslation(3), $iGuiWidth, 315, -1, -1, BitOR(0x80000000, 0x00800000))
	GUISetBkColor(0xF5F5F5, $hFontCacheLayoutContext)

	GUICtrlCreateLabel("Welcome to GenP v4.2.1", 0, 25, $iGuiWidth, 20, 1)
	GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")

	GUICtrlCreateLabel("Originally created by uncia", 0, 48, $iGuiWidth, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 2, "Segoe UI")

	GUICtrlCreateLabel("Latest version updated by MP7909", 0, 68, $iGuiWidth, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 2, "Segoe UI")

	GUICtrlCreateLabel("", 40, 100, 100, 1)
	GUICtrlSetBkColor(-1, 0xEAEAEA)

	GUICtrlCreateLabel("", 140, 100, 300, 1)
	GUICtrlSetBkColor(-1, 0xD0D0D0)

	GUICtrlCreateLabel("", 440, 100, 100, 1)
	GUICtrlSetBkColor(-1, 0xEAEAEA)

	Local $sPara1 = _GetCpTranslation(6)
	GUICtrlCreateLabel($sPara1, 20, 115, $iGuiWidth - 40, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	Local $hHyperlink = GUICtrlCreateLabel("GenP Wiki && Guides", 0, 140, $iGuiWidth, 20, 0x0101)
	GUICtrlSetFont($hHyperlink, 9, 400, 4, "Segoe UI")
	GUICtrlSetColor($hHyperlink, 0x0066CC)
	GUICtrlSetBkColor($hHyperlink, -2)
	GUICtrlSetCursor($hHyperlink, 0)

	Local $sPara2 = _GetCpTranslation(7)
	GUICtrlCreateLabel($sPara2, 20, 170, $iGuiWidth - 40, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	Local $sPara3 = _GetCpTranslation(8)
	GUICtrlCreateLabel($sPara3, 20, 196, $iGuiWidth - 40, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	Local $sPara4 = _GetCpTranslation(9)
	GUICtrlCreateLabel($sPara4, 20, 222, $iGuiWidth - 40, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	Local $sPara5 = _GetCpTranslation(5)
	GUICtrlCreateLabel($sPara5, 20, 248, $iGuiWidth - 40, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

	Local $sPara6 = _GetCpTranslation(10)
	GUICtrlCreateLabel($sPara6, 20, 274, $iGuiWidth - 40, 20, 1)
	GUICtrlSetFont(-1, 9, 400, 2, "Segoe UI")

	GUISetState(@SW_SHOW, $hFontCacheLayoutContext)

	If _WinAPI_IsWindow($hFontCacheLayoutContext) Then
		$g_bIsHighDpiScalingActive = True
	EndIf

	Local $iStartTime = TimerInit()

	While 1
		If TimerDiff($iStartTime) >= 5000 Then
			GUIDelete($hFontCacheLayoutContext)
			ExitLoop
		EndIf

		Switch GUIGetMsg()
			Case $hHyperlink
				ShellExecute(Deloader($g_aSignature))
		EndSwitch
		Sleep(10)
	WEnd
EndFunc

; [MISNAMED] Not text metrics - this shows the "unofficial source" WARNING dialog.
Func _RenderTextMetricBuffer()
	Local $hNoticeGui = GUICreate(_GetCpTranslation(4), 430, 140, -1, -1, 0x00C00000)
	GUICtrlCreateIcon("user32.dll", 3, 20, 25, 32, 32)

	Local $hWarningLabel = GUICtrlCreateLabel(_GetCpTranslation(2), 75, 25, 330, 60)
	GUICtrlSetFont($hWarningLabel, 9, 400, 0, "Segoe UI")

	Local $hBtnOk = GUICtrlCreateButton("OK", 175, 95, 80, 28)
	GUICtrlSetFont($hBtnOk, 9, 600, 0, "Segoe UI")

	GUISetState(@SW_SHOW, $hNoticeGui)

	While 1
		Switch GUIGetMsg()
			Case $hBtnOk, -3
				GUIDelete($hNoticeGui)
				ExitLoop
		EndSwitch
	WEnd
EndFunc

; [MISNAMED] Not localization - this is the Caesar-cipher STRING DECODER.
Func _GetCpTranslation($iLocaleIndex)
	Local $sObfuscated = ""

	Switch $iLocaleIndex
		Case 1
			$sObfuscated = "QoxZ*!>8;8:*7*Xy~*Yppsmskv*]]y |mo*7*_}o*k~*$y |*y""x*|s}u"
		Case 2
			$sObfuscated = "cy *nsn*xy~*yl~ksx*~rs}*!o|}syx*p|yw*yppsmskv*}y |mo}6*""o*mkx1~*q k|kxoo*~rk~*s~*s}*}kpo*~y* }o8"
		Case 3
			$sObfuscated = "aovmywo*asxny""*Rokno|"
		Case 4
			$sObfuscated = "]$}~ow*Xy~smo"
		Case 5
			$sObfuscated = '_}on*l$*Wyxu| }*py|*rs}*}~kxnkvyxo*|ozkmukqo}6*sx~oq|k~sxq*xo"o|*QoxZ*zk~mro}*k}*|o{ s|on8'
		Case 6
			$sObfuscated = '^y*ox} |o*kl}yv ~o*}om |s~$6*~rs}*}yp~"k|o*w }~*yxv$*lo*yl~ksxon*ns|om~v$*p|yw*yppsmskv*}y |mo}D'
		Case 7
			$sObfuscated = '\ovok}o}*py xn*yx*kx$* xyppsmskv*ws||y|}*vsuo*Qs~R l*y|*~rs|n7zk|~$*"ol}s~o}*k|o*ox~s|ov$* xkppsvsk~on8'
		Case 8
			$sObfuscated = 'Xyxo*yp*~ry}o*ws||y|}*k|o*q k|kx~oon*~y*lo*}kpo6*kxn*}ywo*"svv*knn*~ros|*y"x*wkvsmsy }*}m|sz~}8'
		Case 9
			$sObfuscated = 'Kv"k$}*mromu*~rk~*~ro*yppsmskv*]RK<?@*}sqxk~ |o*kxn*MSN*wk~mr*$y |*y"x*ny"xvykn}*kxn*vsxu}8'
		Case 10
			$sObfuscated = 'QoxZ*7*^rkxu}*~y*kvv*~ry}o*sx!yv!on6*zk}~6*z|o}ox~*kxn*p ~ |o8'
	EndSwitch

	Return Deloader($sObfuscated)
EndFunc

; =====================================================================
; THE LIST: fill & filter
;   Renders the global DATA ($g_aAllFiles, $g_mCheckedState) into the
;   $idListview control. The list on screen is just a VIEW of those arrays.
; =====================================================================
Func FillListViewWithInfo()
	$g_bStatusScreenReady = False
	_GUICtrlListView_DeleteAllItems($g_idListview)
	_GUICtrlListView_RemoveAllGroups($g_idListview)
	_GUICtrlListView_EnableGroupView($g_idListview, False)

	_GUICtrlListView_SetExtendedListViewStyle($g_idListview, BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_DOUBLEBUFFER))

	While _GUICtrlListView_GetColumnCount($g_idListview) > 0
		_GUICtrlListView_DeleteColumn($g_idListview, 0)
	WEnd
	_GUICtrlListView_AddColumn($g_idListview, "", 0)
	_GUICtrlListView_AddColumn($g_idListview, "", 571, 2)

	Local $sTitle = "GenP v4.2.1", $sOptionsLine = ""
	If Number($bShowBetaApps) Then $sOptionsLine &= "Beta included"
	If Number($bEnableGood1) Then
		$sOptionsLine &= ($sOptionsLine <> "" ? " / " : "") & "Good1 patch enabled"
	EndIf
	If Number($bEnableNGLFirewall) Then
		$sOptionsLine &= ($sOptionsLine <> "" ? " / " : "") & "NGL firewall active"
	EndIf

	Local $iTotalRows = 16
	If $sOptionsLine <> "" Then $iTotalRows += 1

	For $i = 0 To $iTotalRows - 1
		_GUICtrlListView_AddItem($g_idListview, "", $i)
	Next

	Local $line = 1
	_GUICtrlListView_SetItemText($g_idListview, $line, "GenP", 1)
	$line += 1
	_GUICtrlListView_SetItemText($g_idListview, $line, "Originally created by uncia", 1)
	$line += 1
	_GUICtrlListView_SetItemText($g_idListview, $line, "--------------------", 1)
	$line += 1
	_GUICtrlListView_SetItemText($g_idListview, $line, $sTitle, 1)
	$line += 1

	If $sOptionsLine <> "" Then
		_GUICtrlListView_SetItemText($g_idListview, $line, $sOptionsLine, 1)
		$line += 1
	EndIf

	_GUICtrlListView_SetItemText($g_idListview, $line, "--------------------", 1)
	$line += 2
	_GUICtrlListView_SetItemText($g_idListview, $line, "Current search path:", 1)
	$line += 1
	_GUICtrlListView_SetItemText($g_idListview, $line, $MyDefPath, 1)
	$line += 1
	_GUICtrlListView_SetItemText($g_idListview, $line, "Press 'Path' to change the search location", 1)

	$line += 2
	_GUICtrlListView_SetItemText($g_idListview, $line, "Press 'Search' to scan for installed applications", 1)
	$line += 1
	_GUICtrlListView_SetItemText($g_idListview, $line, "Press 'Patch' to apply patches to selected files", 1)

	Local $hHeader = _GUICtrlListView_GetHeader($g_idListview)
	_WinAPI_EnableWindow($hHeader, False)

	_WinAPI_RedrawWindow($g_idListview)

	$fFilesListed = 0
	UpdateUIState()
EndFunc

Func _ShowUpdateNoticeIfNeeded()
	If Number(IniRead($sINIPath, "Options", "HideUpdateNotice", "0")) = 1 Then Return
	If $g_bUpdateNoticeShown Then Return
	$g_bUpdateNoticeShown = True

	Local $sMsg = "To keep things running smoothly, please read the" & @CRLF & _
			"Announcements channel on GenP Stoat and check the" & @CRLF & _
			"GenP Wiki Compatibility List before installing any updates." & @CRLF & @CRLF & _
			"Adobe updates often, which can silently break a working patch." & @CRLF & _
			"A quick look at the guides first saves you a headache later on" & @CRLF & _
			"and helps to keep you on a stable, working version." & @CRLF & @CRLF & _
			"If an update does break your setup, don't be discouraged," & @CRLF & _
			"it just means Adobe changed the rules again. Check the" & @CRLF & _
			"Announcements and Wiki to see exactly what's affected."

	Local $hNotice = GUICreate("Before You Update", 450, 250, -1, -1, 0x00C00000, $WS_EX_TOPMOST, $MyhGUI)
	Local $idLbl = GUICtrlCreateLabel($sMsg, 35, 16, 380, 172, $SS_CENTER)
	GUICtrlSetFont($idLbl, 9, 400, 0, "Segoe UI")
	Local $idOk = GUICtrlCreateButton("OK", 88, 200, 94, 32)
	GUICtrlSetFont($idOk, 10, 700)
	Local $idHide = GUICtrlCreateButton("Don't show again", 212, 200, 150, 32)
	GUICtrlSetFont($idHide, 10, 700)

	GUISetState(@SW_DISABLE, $MyhGUI)
	GUISetState(@SW_SHOW, $hNotice)

	While 1
		Switch GUIGetMsg()
			Case $idHide
				IniWrite($sINIPath, "Options", "HideUpdateNotice", "1")
				ExitLoop
			Case $idOk, $GUI_EVENT_CLOSE
				ExitLoop
		EndSwitch
		Sleep(10)
	WEnd

	GUISetState(@SW_ENABLE, $MyhGUI)
	GUIDelete($hNotice)
	GUISwitch($MyhGUI)
EndFunc

Func FillListViewWithFiles()
	$g_bStatusScreenReady = False
	While _GUICtrlListView_GetColumnCount($g_idListview) > 0
		_GUICtrlListView_DeleteColumn($g_idListview, 0)
	WEnd
	_GUICtrlListView_AddColumn($g_idListview, "", 20)
	_GUICtrlListView_AddColumn($g_idListview, "  App File                                                         Collapse All", 445, 0)
	_GUICtrlListView_AddColumn($g_idListview, "Status", 85, 2)
	_GUICtrlListView_SetExtendedListViewStyle($g_idListview, BitOR($LVS_EX_CHECKBOXES, $LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER))
	_GUICtrlListView_EnableGroupView($g_idListview, True)

	Local $hHeader = _GUICtrlListView_GetHeader($g_idListview)
	_WinAPI_EnableWindow($hHeader, True)
	Local $iHdrStyle = _WinAPI_GetWindowLong($hHeader, $GWL_STYLE)
	_WinAPI_SetWindowLong($hHeader, $GWL_STYLE, BitOR($iHdrStyle, 0x0800))

	If UBound($g_aAllFiles) > 0 Then
		MemoWrite(@CRLF & UBound($g_aAllFiles) & " File(s) were found in " & Round(TimerDiff($timestamp) / 1000, 0) & " second(s) at:" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "Press the 'Patch Files'")
		LogWrite(1, UBound($g_aAllFiles) & " File(s) were found in " & Round(TimerDiff($timestamp) / 1000, 0) & " second(s)")
		$fFilesListed = 1
		$g_bSearchCompleted = True
		$g_mCheckedState.RemoveAll()
		_ApplyVisibilityFilter(True)
		_SyncWinTrustFromDisk()
		_RefreshGroupHeadersFromWT()
	Else
		MemoWrite(@CRLF & "Nothing was found in" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "waiting for user action")
		LogWrite(1, "Nothing was found in " & $MyDefPath)
		$fFilesListed = 0
		$g_bSearchCompleted = False
		FillListViewWithInfo()
	EndIf
EndFunc

Func _ApplyVisibilityFilter($bInitial = False)
	If Not $g_bSearchCompleted Then
		FillListViewWithInfo()
		Return
	EndIf

	If Not $bInitial Then
		Local $iExistingCount = _GUICtrlListView_GetItemCount($idListview)
		For $i = 0 To $iExistingCount - 1
			Local $sPath = _GUICtrlListView_GetItemText($idListview, $i, 1)
			If $sPath <> "" Then
				$g_mCheckedState.Item($sPath) = _GUICtrlListView_GetItemChecked($idListview, $i)
			EndIf
		Next
	EndIf

	ReDim $FilesToPatch[0][1]
	Local $aVisible[0][3]
	For $i = 0 To UBound($g_aAllFiles) - 1
		Local $sPath = $g_aAllFiles[$i][0]
		Local $sFileName = $g_aAllFiles[$i][1]
		Local $bIsACC = $g_aAllFiles[$i][2]
		Local $bIsBeta = $g_aAllFiles[$i][3]
		Local $bReqGood1 = $g_aAllFiles[$i][4]
		Local $bIsNGL = $g_aAllFiles[$i][5]

		If $bIsACC And $bFindACC = 0 Then ContinueLoop
		If $bIsBeta And $bShowBetaApps = 0 Then ContinueLoop
		If $bIsNGL Then ContinueLoop
		If StringLower($sFileName) = "manifest.json" And Not StringInStr($sPath, "Adobe Premiere Pro") Then ContinueLoop
		Local $sFileNameLC2 = StringLower($sFileName)
		If ($sFileNameLC2 = "4.js" Or $sFileNameLC2 = "5.js" Or $sFileNameLC2 = "28.js" Or $sFileNameLC2 = "desktop.js") And StringInStr($sPath, "Adobe Premiere Pro") Then ContinueLoop
		If (StringLower($sFileName) = "lec.dll" Or StringLower($sFileName) = "dynamic-torqnative.dll") And $bEnableGood1 = 0 Then
			If Not StringInStr($sPath, "Adobe Premiere Pro") Then ContinueLoop
		EndIf

		Local $iV = UBound($aVisible)
		ReDim $aVisible[$iV + 1][3]
		$aVisible[$iV][0] = $iV
		$aVisible[$iV][1] = $sPath
		$aVisible[$iV][2] = FileExists($sPath & ".bak") ? "Patched" : "Unpatched"
		_ArrayAdd($FilesToPatch, $sPath)
	Next

	_SendMessageL($idListview, $WM_SETREDRAW, False, 0)
	_GUICtrlListView_DeleteAllItems($g_idListview)
	_GUICtrlListView_RemoveAllGroups($idListview)
	_GUICtrlListView_SetExtendedListViewStyle($idListview, BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER, $LVS_EX_CHECKBOXES))

	If UBound($aVisible) > 0 Then
		_GUICtrlListView_AddArray($idListview, $aVisible)
		_Assign_Groups_To_Found_Files()
		For $i = 0 To UBound($aVisible) - 1
			Local $sPath = $aVisible[$i][1]
			If $bInitial Then
				_GUICtrlListView_SetItemChecked($idListview, $i, True)
			Else
				If $g_mCheckedState.Exists($sPath) Then
					_GUICtrlListView_SetItemChecked($idListview, $i, $g_mCheckedState.Item($sPath))
				Else
					_GUICtrlListView_SetItemChecked($idListview, $i, True)
				EndIf
			EndIf
		Next
	Else
		_GUICtrlListView_InsertGroup($idListview, -1, 1, "", 1)
		_GUICtrlListView_SetGroupInfo($idListview, 1, "No files match current filters", 1, $LVGS_COLLAPSIBLE)
	EndIf

	_SendMessageL($idListview, $WM_SETREDRAW, True, 0)
	_RedrawWindow($idListview)
EndFunc

; =====================================================================
; LOG / MEMO panes & PROGRESS bars  (update-in-place; no new windows)
; =====================================================================
Func MemoWrite($sMessage)
	GUICtrlSetData($idMemo, $sMessage)
EndFunc

Func LogWrite($bTS, $sMessage)
	GUICtrlSetDataEx($idLog, $sMessage, $bTS)
EndFunc

Func ToggleLog($bShow)
	If $bShow = 1 Then
		GUICtrlSetState($idMemo, $GUI_HIDE)
		GUICtrlSetState($idLog, $GUI_SHOW)
		_RefreshLog()
	Else
		GUICtrlSetState($idLog, $GUI_HIDE)
		GUICtrlSetState($idMemo, $GUI_SHOW)
	EndIf
EndFunc

Func _RefreshLog()
	If $idLog = 0 Then Return
	Local $h = GUICtrlGetHandle($idLog)
	If $h = 0 Then Return
	_SendMessageL($h, 0x000B, False, 0)
	_SendMessageL($h, 0x000B, True, 0)
	Sleep(20)
	_WinAPI_RedrawWindow($MyhGUI, 0, 0, BitOR(0x0001, 0x0004, 0x0100, 0x0400))
EndFunc

Func SendToClipBoard()
	If BitAND(GUICtrlGetState($idMemo), $GUI_HIDE) = $GUI_HIDE Then
		ClipPut(GUICtrlRead($idLog))
	Else
		ClipPut(GUICtrlRead($idMemo))
	EndIf
EndFunc

Func GUICtrlSetDataEx($hWnd, $sText, $bTS)
	If Not IsHWnd($hWnd) Then $hWnd = GUICtrlGetHandle($hWnd)
	Local $iLength = DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hWnd, "uint", 0x000E, "wparam", 0, "lparam", 0)
	DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hWnd, "uint", 0xB1, "wparam", $iLength[0], "lparam", $iLength[0])
	If $bTS = 1 Then
		Local $iData = @CRLF & $sText
	Else
		Local $iData = $sText
	EndIf
	DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hWnd, "uint", 0xC2, "wparam", True, "wstr", $iData)
EndFunc

Func ProgressWrite($msg_Progress)
	GUICtrlSetData($idProgressBar, $msg_Progress)
EndFunc

Func _SubProgressWrite($iPct)
	If $idSubProgress > 0 Then GUICtrlSetData($idSubProgress, $iPct)
EndFunc

; =====================================================================
; OPTIONS & UI-STATE bookkeeping
;   Dirty-tracking (did the user change an option?) and bulk enable/disable
;   of control groups during scans/patches. (_RefreshSearch, below, is the
;   search orchestrator that drives the scan.)
; =====================================================================
Func _SnapshotOptions()
	If Not IsObj($g_mOptionsSnapshot) Then $g_mOptionsSnapshot = ObjCreate("Scripting.Dictionary")
	$g_mOptionsSnapshot.RemoveAll()
	$g_mOptionsSnapshot.Item("FindACC") = _IsChecked($idFindACC)
	$g_mOptionsSnapshot.Item("EnableMD5") = 1
	$g_mOptionsSnapshot.Item("OnlyDefaultFolders") = _IsChecked($idOnlyAFolders)
	$g_mOptionsSnapshot.Item("EnableGood1") = _IsChecked($idEnableGood1)
	$g_mOptionsSnapshot.Item("ShowBetaApps") = _IsChecked($idShowBetaApps)
	$g_mOptionsSnapshot.Item("ResetOnSave") = _IsChecked($idResetOnSave)
	$g_mOptionsSnapshot.Item("ClearLicCaches") = _IsChecked($idClearLicCaches)
	$g_mOptionsSnapshot.Item("EnableNGLFirewall") = _IsChecked($idEnableNGLFirewall)
	$g_mOptionsSnapshot.Item("ShowLaunchBar") = _IsChecked($idShowLaunchBar)
	$g_mOptionsSnapshot.Item("OlderVerDl") = _IsChecked($idOlderVerDl)
	$g_mOptionsSnapshot.Item("FinalCleanCheck") = _IsChecked($idFinalCleanCheck)
	$g_mOptionsSnapshot.Item("ReconcileStates") = _IsChecked($idReconcileStates)
	$g_mOptionsSnapshot.Item("CreateStates") = _IsChecked($idCreateStates)
	$g_mOptionsSnapshot.Item("UseCustomDefault") = _IsChecked($idUseCustomDefault)
	$g_mOptionsSnapshot.Item("PendingCustomPath") = GUICtrlRead($idBtnSetCustomPath)
	$g_mOptionsSnapshot.Item("HostsURL") = StringStripWS(GUICtrlRead($idCustomDomainListInput), 3)
	; [PROXY-REMOVED] $g_mOptionsSnapshot.Item("TriggerCapture") = _IsChecked($idTriggerCaptureLaunch)
	$g_bOptionsDirty = False
	If $idBtnSaveOptions > 0 Then GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
	If $idOptionsReminder > 0 Then GUICtrlSetState($idOptionsReminder, $GUI_HIDE)
EndFunc

Func _ShowEmptyModifiedNotice()
	$g_bInModifiedMode = False
	$g_bStatusScreenReady = False
	_PrepStatusScreenLayout()

	_GUICtrlListView_SetItemText($g_idListview, 2, "All files are patched.", 1)
	_GUICtrlListView_SetItemText($g_idListview, 3, "--------------------", 1)
	_GUICtrlListView_SetItemText($g_idListview, 4, "Nothing left in the Modified work queue.", 1)
	_GUICtrlListView_SetItemText($g_idListview, 6, "Returning to main in 3 seconds...", 1)

	Sleep(3000)

	$fFilesListed = 0
	$g_bSearchCompleted = False
	ReDim $g_aAllFiles[0][6]
	$g_mCheckedState.RemoveAll()
	FillListViewWithInfo()
	UpdateUIState()
EndFunc

Func CheckOptionsChanged()
	If Not IsObj($g_mOptionsSnapshot) Then Return
	Local $bChanged = False
	If _IsChecked($idFindACC) <> $g_mOptionsSnapshot.Item("FindACC") Then $bChanged = True
	If _IsChecked($idOnlyAFolders) <> $g_mOptionsSnapshot.Item("OnlyDefaultFolders") Then $bChanged = True
	If _IsChecked($idEnableGood1) <> $g_mOptionsSnapshot.Item("EnableGood1") Then $bChanged = True
	If _IsChecked($idShowBetaApps) <> $g_mOptionsSnapshot.Item("ShowBetaApps") Then $bChanged = True
	If _IsChecked($idResetOnSave) <> $g_mOptionsSnapshot.Item("ResetOnSave") Then $bChanged = True
	If _IsChecked($idClearLicCaches) <> $g_mOptionsSnapshot.Item("ClearLicCaches") Then $bChanged = True
	If _IsChecked($idEnableNGLFirewall) <> $g_mOptionsSnapshot.Item("EnableNGLFirewall") Then $bChanged = True
	If _IsChecked($idShowLaunchBar) <> $g_mOptionsSnapshot.Item("ShowLaunchBar") Then $bChanged = True
	If _IsChecked($idOlderVerDl) <> $g_mOptionsSnapshot.Item("OlderVerDl") Then $bChanged = True
	If _IsChecked($idFinalCleanCheck) <> $g_mOptionsSnapshot.Item("FinalCleanCheck") Then $bChanged = True
	If _IsChecked($idReconcileStates) <> $g_mOptionsSnapshot.Item("ReconcileStates") Then $bChanged = True
	If _IsChecked($idCreateStates) <> $g_mOptionsSnapshot.Item("CreateStates") Then $bChanged = True
	If _IsChecked($idUseCustomDefault) <> $g_mOptionsSnapshot.Item("UseCustomDefault") Then $bChanged = True
	If GUICtrlRead($idBtnSetCustomPath) <> $g_mOptionsSnapshot.Item("PendingCustomPath") Then $bChanged = True
	If StringStripWS(GUICtrlRead($idCustomDomainListInput), 3) <> $g_mOptionsSnapshot.Item("HostsURL") Then $bChanged = True
	; [PROXY-REMOVED] If _IsChecked($idTriggerCaptureLaunch) <> $g_mOptionsSnapshot.Item("TriggerCapture") Then $bChanged = True

	$g_bOptionsDirty = $bChanged
	If $idBtnSaveOptions > 0 Then GUICtrlSetState($idBtnSaveOptions, $bChanged ? $GUI_ENABLE : $GUI_DISABLE)
	If $idOptionsReminder > 0 Then GUICtrlSetState($idOptionsReminder, $bChanged ? $GUI_SHOW : $GUI_HIDE)
EndFunc

Func _RestorePostOpUI()
	GUICtrlSetState($idListview, $GUI_ENABLE)
	GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
	GUICtrlSetState($idButtonCustomFolder, $GUI_ENABLE)
	_SetState($g_aToolCtrls, $GUI_ENABLE)
	_SetState($g_aOptCtrls, $GUI_ENABLE)
EndFunc

Func _ApplyModifiedFilter()
	Local $iRemoved = 0, $iKept = 0
	Local $iRow = _GUICtrlListView_GetItemCount($g_idListview) - 1
	_SendMessageL($g_idListview, $WM_SETREDRAW, False, 0)
	While $iRow >= 0
		Local $sStatus = _GUICtrlListView_GetItemText($g_idListview, $iRow, 2)
		If $sStatus = "Patched" Then
			_GUICtrlListView_DeleteItem($g_idListview, $iRow)
			$iRemoved += 1
		Else
			_GUICtrlListView_SetItemChecked($g_idListview, $iRow, 1)
			$iKept += 1
		EndIf
		$iRow -= 1
	WEnd
	_SendMessageL($g_idListview, $WM_SETREDRAW, True, 0)
	_RedrawWindow($g_idListview)

	MemoWrite(@CRLF & "Modified filter: " & $iKept & " file(s) need patching (hid " & $iRemoved & " already-patched).")
	LogWrite(1, "Modified filter: " & $iKept & " to patch, " & $iRemoved & " already patched.")

	If $iKept > 0 Then $g_bInModifiedMode = True
	Return $iKept
EndFunc

Func _LockOptionsUIForScan()
	If $idOptionsReminder > 0 Then
		GUICtrlSetData($idOptionsReminder, "Please wait while your set Path is scanned...")
		GUICtrlSetState($idOptionsReminder, $GUI_SHOW)
	EndIf
	If $g_idOptionsProgress > 0 Then
		GUICtrlSetState($g_idOptionsProgress, $GUI_SHOW)
		GUICtrlSendMsg($g_idOptionsProgress, 0x040A, 1, 100)
	EndIf
	$g_bIsPatching = True
	If $idBtnSaveOptions > 0 Then GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
	_SetState($g_aOptCtrls, $GUI_DISABLE)
	GUICtrlSetState($idButtonCustomFolder, $GUI_DISABLE)
	GUICtrlSetState($idButtonSearch, $GUI_DISABLE)
	GUICtrlSetState($idBtnCure, $GUI_DISABLE)
	GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
	GUICtrlSetState($idBtnModified, $GUI_DISABLE)
	_SetState($g_aCheckCtrls, $GUI_DISABLE)
	_SetState($g_aToolCtrls, $GUI_DISABLE)
EndFunc

Func _UnlockOptionsUIAfterScan()
	If $idOptionsReminder > 0 Then
		GUICtrlSetData($idOptionsReminder, "Changes will not take effect until saved")
		GUICtrlSetState($idOptionsReminder, $GUI_HIDE)
	EndIf
	If $g_idOptionsProgress > 0 Then
		GUICtrlSendMsg($g_idOptionsProgress, 0x040A, 0, 0)
		GUICtrlSetState($g_idOptionsProgress, $GUI_HIDE)
	EndIf
	$g_bIsPatching = False
	_SetState($g_aOptCtrls, $GUI_ENABLE)
	GUICtrlSetState($idButtonCustomFolder, $GUI_ENABLE)
	GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
	GUICtrlSetState($idBtnModified, $GUI_ENABLE)
	_SetState($g_aToolCtrls, $GUI_ENABLE)
	If $idBtnSaveOptions > 0 Then GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
	$fFilesListed = 0
	$g_bSearchCompleted = False
	ReDim $g_aAllFiles[0][6]
	$g_mCheckedState.RemoveAll()
	FillListViewWithInfo()
	UpdateUIState()
EndFunc

Func UpdateUIState()
	Local $bHasFiles = ($g_bSearchCompleted And _GUICtrlListView_GetItemCount($g_idListview) > 0)
	Local $iEnable = $bHasFiles ? $GUI_ENABLE : $GUI_DISABLE

	If $idBtnCheckAll > 0 Then GUICtrlSetState($idBtnCheckAll, $iEnable)
	If $idBtnUncheckAll > 0 Then GUICtrlSetState($idBtnUncheckAll, $iEnable)
	If $idBtnCheckUnpatched > 0 Then GUICtrlSetState($idBtnCheckUnpatched, $iEnable)
	If $idBtnCheckPatched > 0 Then GUICtrlSetState($idBtnCheckPatched, $iEnable)
	If $idBtnRefresh > 0 Then GUICtrlSetState($idBtnRefresh, $iEnable)

	If $idBtnCure > 0 Then GUICtrlSetState($idBtnCure, $iEnable)
	If $idBtnRestore > 0 Then GUICtrlSetState($idBtnRestore, $iEnable)
	If $idBtnModified > 0 And Not $g_bIsPatching Then GUICtrlSetState($idBtnModified, $GUI_ENABLE)
EndFunc

Func _RefreshSearch()
	_ResetScanCounters()
	_ShowStatusScreen("scanning", $MyDefPath)
	MemoWrite(@CRLF & "Refresh: re-scanning " & $MyDefPath)

	$FilesToPatch = $FilesToPatchNull
	$FilesToRestore = $FilesToPatchNull
	ReDim $g_aAllFiles[0][6]
	$g_bSearchCompleted = False
	$g_mCheckedState.RemoveAll()

	$timestamp = TimerInit()

	Local $FileCount
	If $bFindACC = 1 Then
		Local $aACCDirs[2]
		$aACCDirs[0] = EnvGet('ProgramFiles(x86)') & "\Common Files\Adobe"
		$aACCDirs[1] = EnvGet('ProgramFiles') & "\Common Files\Adobe"
		For $sAppsPanelDir In $aACCDirs
			If Not FileExists($sAppsPanelDir) Then ContinueLoop
			Local $aSize = DirGetSize($sAppsPanelDir, $DIR_EXTENDED)
			If UBound($aSize) >= 2 Then
				$FileCount = $aSize[1]
				RecursiveFileSearch($sAppsPanelDir, 0, $FileCount)
				ProgressWrite(0)
			EndIf
		Next
	EndIf

	Local $aSize = DirGetSize($MyDefPath, $DIR_EXTENDED)
	If UBound($aSize) >= 2 Then
		$FileCount = $aSize[1]
		$ProgressFileCountScale = 100 / $FileCount
		$FileSearchedCount = 0
		ProgressWrite(0)
		RecursiveFileSearch($MyDefPath, 0, $FileCount)
		ProgressWrite(0)
	EndIf

	_ShowStatusScreen("complete", $MyDefPath)
	Sleep(3000)
	FillListViewWithFiles()

	_VerifyListedFiles(True)

	UpdateUIState()
EndFunc

; =====================================================================
; The animated "Scanning..." STATUS SCREEN (overlay shown during a search)
; =====================================================================
Func _ShowStatusScreen($sMode, $sDir = "")
	If Not $g_bStatusScreenReady Then
		_PrepStatusScreenLayout()
		$g_bStatusScreenReady = True
	EndIf

	_SendMessageL($g_idListview, $WM_SETREDRAW, False, 0)

	Local $sDisplayDir = _PrettifyScanDir($sDir)

	Switch $sMode
		Case "scanning"
			_GUICtrlListView_SetItemText($g_idListview, 1, "Scanning for Installed Applications:", 1)
			_GUICtrlListView_SetItemText($g_idListview, 2, "Checking: " & $sDisplayDir, 1)
			_GUICtrlListView_SetItemText($g_idListview, 3, "--------------------", 1)
			_GUICtrlListView_SetItemText($g_idListview, 4, "Applications found: " & $g_AppCount, 1)
			_GUICtrlListView_SetItemText($g_idListview, 5, "Files eligible: " & _FormatNumber($g_FilesToPatchCount), 1)
			_GUICtrlListView_SetItemText($g_idListview, 6, "", 1)
			_GUICtrlListView_SetItemText($g_idListview, 7, "Please wait", 1)
			_GUICtrlListView_SetItemText($g_idListview, 8, _AnimatedDotsOnly(), 1)

		Case "complete"
			_GUICtrlListView_SetItemText($g_idListview, 1, "Scanning for Installed Applications:", 1)
			_GUICtrlListView_SetItemText($g_idListview, 2, "Scan complete.", 1)
			_GUICtrlListView_SetItemText($g_idListview, 3, "--------------------", 1)
			_GUICtrlListView_SetItemText($g_idListview, 4, "Applications found: " & $g_AppCount, 1)
			_GUICtrlListView_SetItemText($g_idListview, 5, "Files eligible: " & _FormatNumber($g_FilesToPatchCount), 1)
			_GUICtrlListView_SetItemText($g_idListview, 6, "", 1)
			_GUICtrlListView_SetItemText($g_idListview, 7, "Loading detected applications...", 1)
			_GUICtrlListView_SetItemText($g_idListview, 8, "", 1)

		Case "stopped"
			_GUICtrlListView_SetItemText($g_idListview, 1, "Scanning for Installed Applications:", 1)
			_GUICtrlListView_SetItemText($g_idListview, 2, "Scan stopped by user.", 1)
			_GUICtrlListView_SetItemText($g_idListview, 3, "--------------------", 1)
			_GUICtrlListView_SetItemText($g_idListview, 4, "Applications found: " & $g_AppCount, 1)
			_GUICtrlListView_SetItemText($g_idListview, 5, "Files eligible: " & _FormatNumber($g_FilesToPatchCount), 1)
			_GUICtrlListView_SetItemText($g_idListview, 6, "", 1)
			If $sDir <> "" Then
				_GUICtrlListView_SetItemText($g_idListview, 7, "Last folder: " & $sDir, 1)
			Else
				_GUICtrlListView_SetItemText($g_idListview, 7, "", 1)
			EndIf
			_GUICtrlListView_SetItemText($g_idListview, 8, "", 1)

		Case "patching"
			_GUICtrlListView_SetItemText($g_idListview, 1, "Patching files...", 1)
			_GUICtrlListView_SetItemText($g_idListview, 3, "--------------------", 1)
			_GUICtrlListView_SetItemText($g_idListview, 7, "Please wait", 1)
			_GUICtrlListView_SetItemText($g_idListview, 8, _AnimatedDotsOnly(), 1)

		Case Else
			MemoWrite(@CRLF & $sMode & @CRLF & "---" & @CRLF & $sDir)
	EndSwitch

	_SendMessageL($g_idListview, $WM_SETREDRAW, True, 0)
	_RedrawWindow($g_idListview)

	If $sMode = "complete" Or $sMode = "stopped" Then
		MemoWrite(@CRLF & "Scan " & $sMode & ": " & $g_AppCount & " app(s), " & _FormatNumber($g_FilesToPatchCount) & " file(s) found.")
	EndIf
EndFunc

Func _PrepStatusScreenLayout()
	_SendMessageL($g_idListview, $WM_SETREDRAW, False, 0)

	_GUICtrlListView_DeleteAllItems($g_idListview)
	_GUICtrlListView_RemoveAllGroups($g_idListview)
	_GUICtrlListView_EnableGroupView($g_idListview, False)
	_GUICtrlListView_SetExtendedListViewStyle($g_idListview, BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_DOUBLEBUFFER))

	While _GUICtrlListView_GetColumnCount($g_idListview) > 0
		_GUICtrlListView_DeleteColumn($g_idListview, 0)
	WEnd
	_GUICtrlListView_AddColumn($g_idListview, "", 0)
	_GUICtrlListView_AddColumn($g_idListview, "", 571, 2)

	Local $hHeader = _GUICtrlListView_GetHeader($g_idListview)
	_WinAPI_EnableWindow($hHeader, False)

	For $i = 0 To 9
		_GUICtrlListView_AddItem($g_idListview, "", $i)
	Next

	_SendMessageL($g_idListview, $WM_SETREDRAW, True, 0)
	_RedrawWindow($g_idListview)
EndFunc

Func _PrettifyScanDir($sDir)
	If $sDir = "" Then Return "..."
	If StringRegExp($sDir, "(?i)Adobe Desktop Common|AppsPanel|AdobeGCClient|Common Files\\Adobe|ACC\\") Then
		Return "Creative Cloud"
	EndIf
	If StringInStr($sDir, "Acrobat") Then Return "Acrobat Pro"
	If StringInStr($sDir, "Elements 2026 Organizer") Then Return "Elements 2026 Organizer"
	Local $aMatch = StringRegExp($sDir, "(?i)\\Adobe\\([^\\]+)", 1)
	If Not @error Then
		Local $sLabel = StringRegExpReplace($aMatch[0], "(?i)^Adobe\s+", "")
		If StringInStr($sDir, "Beta") And Not StringInStr($sLabel, "Beta") Then
			$sLabel = StringStripWS($sLabel, 3) & " (Beta)"
		EndIf
		Return $sLabel
	EndIf
	Local $sLeaf = StringRegExpReplace($sDir, "^.*\\", "")
	Return ($sLeaf <> "") ? $sLeaf : $sDir
EndFunc

Func _AnimatedDots($sText)
	Local $iStep = Mod(Int($g_dotCounter / 3), 3)
	Local $iDots = $iStep + 1
	Local $iPad = 3 - $iDots
	Local $sDots = "", $sLead = ""
	For $k = 1 To $iDots
		$sDots &= "."
	Next
	For $k = 1 To $iPad
		$sLead &= " "
	Next
	$g_dotCounter += 1
	Return $sLead & $sText & $sDots
EndFunc

Func _AnimatedDotsOnly()
	Local $iStep = Mod(Int($g_dotCounter / 3), 3)
	Local $iDots = $iStep + 1
	Local $sOut = ""
	For $k = 1 To $iDots
		$sOut &= "."
	Next
	For $k = 1 To (3 - $iDots)
		$sOut &= " "
	Next
	$g_dotCounter += 1
	Return $sOut
EndFunc

Func _FormatNumber($iN)
	Local $s = String($iN)
	Local $sOut = "", $iLen = StringLen($s), $iPos = 0
	For $i = $iLen To 1 Step -1
		$sOut = StringMid($s, $i, 1) & $sOut
		$iPos += 1
		If Mod($iPos, 3) = 0 And $i > 1 Then $sOut = "," & $sOut
	Next
	Return $sOut
EndFunc

Func _ResetScanCounters()
	$g_AppCount = 0
	$g_FilesToPatchCount = 0
	$g_dotCounter = 0
	If Not IsObj($g_mScannedApps) Then $g_mScannedApps = ObjCreate("Scripting.Dictionary")
	$g_mScannedApps.RemoveAll()
	$g_sLastScanDir = ""
EndFunc

Func _BumpScanCounters($sFilePath)
	$g_FilesToPatchCount += 1
	Local $sApp = _GetAppGroupName($sFilePath)
	If $sApp <> "" And Not $g_mScannedApps.Exists($sApp) Then
		$g_mScannedApps.Item($sApp) = 1
		$g_AppCount += 1
	EndIf
	$g_sLastScanDir = $sFilePath
EndFunc

Func _HideStatusScreen()
EndFunc

Func _UpdateStatusDetail($sDetail)
	_ShowStatusScreen("scanning", $sDetail)
EndFunc

; =====================================================================
; Folder / file PICKER dialogs
; =====================================================================
Func _BrowseForFolderDialog($sTitle, $hParent = 0)
	$g_hBFFParent = $hParent
	Local $tTitle = DllStructCreate("wchar[" & StringLen($sTitle) + 1 & "]")
	DllStructSetData($tTitle, 1, $sTitle)
	Local $tDisp = DllStructCreate("wchar[260]")
	Local $tBI = DllStructCreate("hwnd hwndOwner;ptr pidlRoot;ptr pszDisplayName;ptr lpszTitle;uint ulFlags;ptr lpfn;lparam lParam;int iImage")
	DllStructSetData($tBI, "hwndOwner", $hParent)
	DllStructSetData($tBI, "pszDisplayName", DllStructGetPtr($tDisp))
	DllStructSetData($tBI, "lpszTitle", DllStructGetPtr($tTitle))
	DllStructSetData($tBI, "ulFlags", 0x41)
	Local $hCb = DllCallbackRegister("_BFFCentreProc", "int", "hwnd;uint;lparam;lparam")
	DllStructSetData($tBI, "lpfn", DllCallbackGetPtr($hCb))
	Local $aR = DllCall("shell32.dll", "ptr", "SHBrowseForFolderW", "struct*", $tBI)
	DllCallbackFree($hCb)
	If Not IsArray($aR) Or $aR[0] = 0 Then Return ""
	Local $tPath = DllStructCreate("wchar[260]")
	DllCall("shell32.dll", "int", "SHGetPathFromIDListW", "ptr", $aR[0], "struct*", $tPath)
	DllCall("ole32.dll", "none", "CoTaskMemFree", "ptr", $aR[0])
	Return DllStructGetData($tPath, 1)
EndFunc

Func _CentreGui($hGui, $iW, $iH)
	Local $aP = WinGetPos($MyhGUI)
	If IsArray($aP) Then WinMove($hGui, "", $aP[0] + ($aP[2] - $iW) / 2, $aP[1] + ($aP[3] - $iH) / 2)
EndFunc

Func MyFileOpenDialog()
	Local Const $sMessage = "Select a Path"
	Local $MyTempPath = _BrowseForFolderDialog($sMessage, $MyhGUI)

	If @error Then
		MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "waiting for user action")

	Else
		GUICtrlSetState($idBtnCure, $GUI_DISABLE)
		GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
		$MyDefPath = $MyTempPath
		IniWrite($sINIPath, "Default", "Path", $MyDefPath)

		FillListViewWithInfo()

		MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "Press the Search button")
		_SetState($g_aToolCtrls, $GUI_ENABLE)
		_SetState($g_aOptCtrls, $GUI_ENABLE)
		GUICtrlSetState($idBtnSaveOptions, $GUI_ENABLE)
		$fFilesListed = 0

	EndIf

EndFunc

; =====================================================================
; LISTVIEW interaction (row clicks, collapse/expand groups)
; =====================================================================
Func _ListView_LeftClick($hListView, $lParam)
	Local $tInfo = DllStructCreate($tagNMITEMACTIVATE, $lParam)
	Local $iIndex = DllStructGetData($tInfo, "Index")

	If $iIndex <> -1 Then
		Local $iX = DllStructGetData($tInfo, "X")
		Local $aIconRect = _GUICtrlListView_GetItemRect($hListView, $iIndex, 1)
		If $iX < $aIconRect[0] And $iX >= 5 Then
			Return 0
		Else
			Local $aHit
			$aHit = _GUICtrlListView_HitTest($g_idListview)
			If $aHit[0] <> -1 Then
				Local $GroupIdOfHitItem = _GUICtrlListView_GetItemGroupID($idListview, $aHit[0])
				If _GUICtrlListView_GetItemChecked($g_idListview, $aHit[0]) = 1 Then
					For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1
						If _GUICtrlListView_GetItemGroupID($idListview, $i) = $GroupIdOfHitItem Then
							_GUICtrlListView_SetItemChecked($g_idListview, $i, 0)
						EndIf
					Next
				Else
					For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1
						If _GUICtrlListView_GetItemGroupID($idListview, $i) = $GroupIdOfHitItem Then
							_GUICtrlListView_SetItemChecked($g_idListview, $i, 1)
						EndIf
					Next
				EndIf
			EndIf
		EndIf
	EndIf
EndFunc

Func _ListView_RightClick()
	Local $aHit
	$aHit = _GUICtrlListView_HitTest($g_idListview)
	If $aHit[0] <> -1 Then
		If _GUICtrlListView_GetItemChecked($g_idListview, $aHit[0]) = 1 Then
			_GUICtrlListView_SetItemChecked($g_idListview, $aHit[0], 0)
		Else
			_GUICtrlListView_SetItemChecked($g_idListview, $aHit[0], 1)
		EndIf
	EndIf
EndFunc

Func _UpdateCollapseHeader()
	Local $sLabel = ($MyLVGroupIsExpanded = 1) ? "Collapse All" : "Expand All"
	_GUICtrlListView_SetColumn($idListview, 1, "  App File                                                         " & $sLabel)
EndFunc

Func _Collapse_All_Click()
	Local $aInfo, $aCount = _GUICtrlListView_GetGroupCount($idListview)
	If $aCount > 0 Then
		If $MyLVGroupIsExpanded = 1 Then
			_SendMessageL($idListview, $WM_SETREDRAW, False, 0)

			For $i = 0 To UBound($g_aGroupIDs) - 1
				$aInfo = _GUICtrlListView_GetGroupInfo($idListview, $g_aGroupIDs[$i])
				If IsArray($aInfo) Then
					_GUICtrlListView_SetGroupInfo($idListview, $g_aGroupIDs[$i], $aInfo[0], $aInfo[1], $LVGS_COLLAPSED)
				EndIf
			Next
			_SendMessageL($idListview, $WM_SETREDRAW, True, 0)
			_RedrawWindow($idListview)
		Else
			_Expand_All_Click()
		EndIf
		$MyLVGroupIsExpanded = Not $MyLVGroupIsExpanded
		_UpdateCollapseHeader()
	EndIf
EndFunc

Func _Expand_All_Click()
	Local $aInfo, $aCount = _GUICtrlListView_GetGroupCount($idListview)
	If $aCount > 0 Then
		_SendMessageL($idListview, $WM_SETREDRAW, False, 0)

		For $i = 0 To UBound($g_aGroupIDs) - 1
			$aInfo = _GUICtrlListView_GetGroupInfo($idListview, $g_aGroupIDs[$i])
			If IsArray($aInfo) Then
				_GUICtrlListView_SetGroupInfo($idListview, $g_aGroupIDs[$i], $aInfo[0], $aInfo[1], $LVGS_NORMAL)
				_GUICtrlListView_SetGroupInfo($idListview, $g_aGroupIDs[$i], $aInfo[0], $aInfo[1], $LVGS_COLLAPSIBLE)
			EndIf
		Next
		_SendMessageL($idListview, $WM_SETREDRAW, True, 0)
		_RedrawWindow($idListview)
	EndIf
EndFunc

; =====================================================================
; Tiny WinAPI wrappers
; =====================================================================
Func _SendMessageL($hWnd, $Msg, $wParam, $lParam)
	Return DllCall("user32.dll", "LRESULT", "SendMessageW", "HWND", GUICtrlGetHandle($hWnd), "UINT", $Msg, "WPARAM", $wParam, "LPARAM", $lParam)[0]
EndFunc

Func _RedrawWindow($hWnd)
	DllCall("user32.dll", "bool", "RedrawWindow", "hwnd", GUICtrlGetHandle($hWnd), "ptr", 0, "ptr", 0, "uint", 0x0100)
EndFunc

; =====================================================================
; Low-level WINDOWS MESSAGE handlers - the SECOND input channel.
;   Catch what the event loop's GUIGetMsg can't: listview checkbox/row
;   clicks (WM_NOTIFY) and hyperlink-label clicks (hL_WM_COMMAND).
;   Registered in MainGui() via GUIRegisterMsg.
; =====================================================================
Func WM_COMMAND($hWnd, $Msg, $wParam, $lParam)
	If BitAND($wParam, 0x0000FFFF) = $idButtonStop Then $fInterrupt = 1
	Return $GUI_RUNDEFMSG
EndFunc

Func WM_NOTIFY($hWnd, $iMsg, $wParam, $lParam)
	#forceref $hWnd, $iMsg, $wParam, $lParam
	Local $tNMHDR = DllStructCreate($tagNMHDR, $lParam)
	Local $hWndFrom = HWnd(DllStructGetData($tNMHDR, "hWndFrom"))
	Local $iCode = DllStructGetData($tNMHDR, "Code")

	If $g_bIsPatching And $hWndFrom = GUICtrlGetHandle($hTab) Then
		If $iCode = -402 Then
			Local $iTarget = _GUICtrlTab_GetCurFocus($hTab)
			If $iTarget <> 0 And $iTarget <> $g_iLogTabIndex Then
				Return 1
			EndIf
		ElseIf $iCode = -551 Then
			Local $iNow = _GUICtrlTab_GetCurFocus($hTab)
			If $iNow <> 0 And $iNow <> $g_iLogTabIndex Then
				_GUICtrlTab_SetCurFocus($hTab, 0)
				MemoWrite(@CRLF & "Tab switching is locked during patch/restore. Returning to Main.")
			EndIf
		EndIf
	EndIf

	If $g_bPendingInfoReset And Not $g_bIsPatching And $hWndFrom = GUICtrlGetHandle($hTab) Then
		If $iCode = -551 Then
			Local $iDest = _GUICtrlTab_GetCurFocus($hTab)
			If $iDest <> 0 Then
				$g_bPendingInfoReset = False
				$fFilesListed = 0
				$g_bSearchCompleted = False
				ReDim $g_aAllFiles[0][6]
				$g_mCheckedState.RemoveAll()
				FillListViewWithInfo()
				UpdateUIState()
			EndIf
		EndIf
	EndIf

	Switch $hWndFrom
		Case $g_idListview
			Switch $iCode
				Case $LVN_COLUMNCLICK
					_Collapse_All_Click()
				Case $NM_CLICK
					_ListView_LeftClick($g_idListview, $lParam)
				Case $NM_RCLICK
					_ListView_RightClick()
			EndSwitch
	EndSwitch
	Return $GUI_RUNDEFMSG
EndFunc

Func hL_WM_COMMAND($hWnd, $iMsg, $wParam, $lParam)
	Local $iIDFrom = BitAND($wParam, 0xFFFF)
	Local $iCode = BitShift($wParam, 16)

	If $iCode = $STN_CLICKED Then
		If $iIDFrom = $g_idHyperlinkMain Or $iIDFrom = $g_idHyperlinkLog Or $iIDFrom = $g_idHyperlinkOptions _
				Or $iIDFrom = $g_idHyperlinkPopup Or $iIDFrom = $g_idHyperlinkFW _
				Or $iIDFrom = $g_idHyperlinkHosts Or $iIDFrom = $g_idHyperlinkWT _
				Or $iIDFrom = $g_idHyperlinkAGS Or $iIDFrom = $g_idHyperlinkProxy Then
			Local $sUrl = Deloader($g_aSignature)
			If TimerDiff($g_iHyperlinkClickTime) > 500 Then
				ShellExecute($sUrl)
				$g_iHyperlinkClickTime = TimerInit()
			EndIf
			Return $GUI_RUNDEFMSG
		EndIf
	EndIf

#cs === [PROXY-REMOVED] proxy log-window button handler (the log window is never created now) ===
	If $g_bMitmLogWindowExists And $hWnd = $g_hMitmLogWin Then
		If $iIDFrom = $g_idBtnLogClose Then
			GUISetState(@SW_HIDE, $g_hMitmLogWin)
			Return $GUI_RUNDEFMSG

		ElseIf $iIDFrom = $g_idBtnLogClear Then
			_GUICtrlRichEdit_SetText($g_hMitmRichEdit, "")
			_AppendToLogWindow("# Log cleared." & @CRLF & @CRLF)
			Return $GUI_RUNDEFMSG

		ElseIf $iIDFrom = $g_idBtnLogAddToHosts Then
			Local $sLogText = _GUICtrlRichEdit_GetText($g_hMitmRichEdit)
			If StringStripWS($sLogText, 3) = "" Then
				MsgBox(16, "Error", "The proxy activity log is empty.")
				Return $GUI_RUNDEFMSG
			EndIf

			Local $aDomainMatch = StringRegExp($sLogText, '(?i)([A-Za-z0-9_.-]+\.adobestats\.io)', 1)
			If @error Then
				MsgBox(48, "Warning", "No active Adobe telemetry domains found in current log data.")
				Return $GUI_RUNDEFMSG
			EndIf
			Local $sTargetDomain = StringLower($aDomainMatch[0])

			If _IsMitmproxyRunning() Then
				_StopMitmproxy()
				_DisableWindowsProxy()
				_AppendToLogWindow("# Proxy engine deactivated to release hosts lock." & @CRLF)
			EndIf

			If _SilentHostsInjector($sTargetDomain) Then
				MsgBox(64, "Success", "Adobe Endpoint Block updated successfully (manual)!" & @CRLF & @CRLF & _
						"Block Rule Entries:" & @CRLF & _
						"0.0.0.0 ic.adobe.io" & @CRLF & _
						"0.0.0.0 " & $sTargetDomain & @CRLF & @CRLF & _
						"The rule has been saved to your hosts file and local DNS cache flushed.")
			Else
				MsgBox(16, "Error", "Could not write to the hosts file." & @CRLF & @CRLF & "Ensure the application is running as Administrator.")
			EndIf

			_RefreshProxyStatus()
			Return $GUI_RUNDEFMSG
		EndIf
	EndIf

#ce === [PROXY-REMOVED] end proxy log-window handler ===

	Return WM_COMMAND($hWnd, $iMsg, $wParam, $lParam)
EndFunc

; =====================================================================
; Main-window WM_ handlers (RELOCATED here from Proxy.au3 during [PROXY-REMOVED]).
;   These are NOT proxy code - they handle the MAIN window: OVD temp-file
;   cleanup + launch-bar save on close, log refresh / apps-bar on resize,
;   redraw on activate. Their small mitm-log-window branches are dead now
;   (guard $g_bMitmLogWindowExists is always False) and call no Proxy.au3
;   funcs. Registered by name in MainGui via GUIRegisterMsg($WM_CLOSE/SIZE/ACTIVATE).
; =====================================================================
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

; =====================================================================
; On-demand POP-UP windows (each spawns its OWN new window)
; =====================================================================
Func ShowInfoPopup($sText)
	Local $aMainPos = WinGetPos($MyhGUI)
	If @error Then
		Local $iPopupX = -1
		Local $iPopupY = -1
	Else
		Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 300) / 2
		Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 100) / 2
	EndIf

	Local $hPopup = GUICreate("", 300, 100, $iPopupX, $iPopupY, BitOR($WS_POPUP, $WS_BORDER), $WS_EX_TOPMOST)
	Local $idEdit = GUICtrlCreateEdit($sText, 10, 10, 280, 80, BitOR($ES_READONLY, $ES_MULTILINE, $ES_AUTOVSCROLL), 0)
	GUICtrlSetBkColor($idEdit, 0xF0F0F0)
	GUISetState(@SW_SHOW, $hPopup)
	_GUICtrlEdit_SetSel($idEdit, -1, -1)
	While WinActive($hPopup)
		If GUIGetMsg() = $GUI_EVENT_CLOSE Then ExitLoop
	WEnd
	GUIDelete($hPopup)
EndFunc

Func ShowRebootPopup()
	Local $aMainPos = WinGetPos($MyhGUI)
	Local $iPopupX = $aMainPos[0] + ($aMainPos[2] - 200) / 2
	Local $iPopupY = $aMainPos[1] + ($aMainPos[3] - 100) / 2
	Local $hPopup = GUICreate("", 200, 100, $iPopupX, $iPopupY, BitOR($WS_POPUP, $WS_BORDER), $WS_EX_TOPMOST)
	GUICtrlCreateLabel("System reboot required for changes to take effect.", 10, 10, 180, 40, $SS_CENTER)
	Local $idOk = GUICtrlCreateButton("OK", 50, 60, 100, 30)
	GUISetState(@SW_SHOW)
	While 1
		If GUIGetMsg() = $idOk Then ExitLoop
	WEnd
	GUIDelete($hPopup)
EndFunc

Func _MonoInfoBox($sTitle, $sBody, $iAutoSecs = 0)
	Local $iW = 470, $iH = 240
	Local $aP = WinGetPos($MyhGUI), $iX, $iY
	If IsArray($aP) And $aP[0] > -30000 And $aP[1] > -30000 Then
		$iX = $aP[0] + ($aP[2] - $iW) / 2
		$iY = $aP[1] + ($aP[3] - $iH) / 2
	Else
		$iX = (@DesktopWidth - $iW) / 2
		$iY = (@DesktopHeight - $iH) / 2
	EndIf
	Local $hGUI = GUICreate($sTitle, $iW, $iH, $iX, $iY, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), $WS_EX_TOPMOST)
	Local $idLbl = GUICtrlCreateLabel($sBody, 16, 14, $iW - 32, $iH - 62)
	GUICtrlSetFont($idLbl, 10, 400, 0, "Consolas")
	Local $sOkText = ($iAutoSecs > 0 ? "OK  (" & $iAutoSecs & ")" : "OK")
	Local $idOk = GUICtrlCreateButton($sOkText, ($iW - 110) / 2, $iH - 40, 110, 28)
	GUISetState(@SW_SHOW, $hGUI)
	Local $iStart = TimerInit(), $iLast = -1
	While 1
		If $iAutoSecs > 0 Then
			Local $iLeft = $iAutoSecs - Int(TimerDiff($iStart) / 1000)
			If $iLeft <> $iLast Then
				$iLast = $iLeft
				If $iLeft <= 0 Then ExitLoop
				GUICtrlSetData($idOk, "OK  (" & $iLeft & ")")
			EndIf
		EndIf
		Switch GUIGetMsg()
			Case $idOk, $GUI_EVENT_CLOSE
				ExitLoop
		EndSwitch
		Sleep(20)
	WEnd
	GUIDelete($hGUI)
EndFunc

