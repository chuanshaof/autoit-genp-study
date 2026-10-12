; =====================================================================
; main.au3 - GenP ENTRY POINT (compiles to GenP.exe / GenP-v4.2.1.exe).
;   There is NO main.exe and NO main() function. AutoIt begins at the
;   first runnable line (AutoItSetOption, further down) and runs
;   top-to-bottom until it parks in the MAIN EVENT LOOP near the bottom.
;   The banners below mark the startup phases, in the order they run.
;   Companion deep-dives: notes\GenP-Notes.md + notes\AutoIt-Notes.md.
; =====================================================================

; --- Runtime directives: #RequireAdmin forces a UAC elevation prompt at
;     launch (deny = program won't run); #NoTrayIcon hides the tray icon. ---
#NoTrayIcon
#RequireAdmin

; --- Build-time directives (AutoIt3Wrapper): read by the COMPILER only,
;     ignored at runtime. They set exe name, icon, version, Au3Stripper. ---
#Region
#AutoIt3Wrapper_Icon=Skull.ico
#AutoIt3Wrapper_Outfile_x64=GenP-v4.2.1.exe
#AutoIt3Wrapper_Res_Comment=GenP
#AutoIt3Wrapper_Res_CompanyName=GenP
#AutoIt3Wrapper_Res_Description=GenP
#AutoIt3Wrapper_Res_Fileversion=4.2.1
#AutoIt3Wrapper_Res_LegalCopyright=GenP 2026
#AutoIt3Wrapper_Res_LegalTradeMarks=GenP 2026
#AutoIt3Wrapper_Res_ProductName=GenP
#AutoIt3Wrapper_Res_ProductVersion=4.2.1
#AutoIt3Wrapper_Res_Field=ID|GenP-%date%-%time%
#AutoIt3Wrapper_Run_Au3Stripper=y
#AutoIt3Wrapper_Run_Tidy=n
#AutoIt3Wrapper_UseUpx=n
#AutoIt3Wrapper_UseX64=y
#EndRegion

; --- Standard library (26 UDFs). The compiler PASTES these in at build
;     time; they are not read from disk at runtime, and live outside this
;     project (in the AutoIt install's Include\ folder). ---
#include <Array.au3>
#include <ButtonConstants.au3>
#include <Crypt.au3>
#include <Date.au3>
#include <EditConstants.au3>
#include <File.au3>
#include <GUIConstantsEx.au3>
#include <GuiEdit.au3>
#include <GuiRichEdit.au3>
#include <GuiListView.au3>
#include <GUITab.au3>
#include <GuiTreeView.au3>
#include <Inet.au3>
#include <ListBoxConstants.au3>
#include <Misc.au3>
#include <MsgBoxConstants.au3>
#include <Process.au3>
#include <ProgressConstants.au3>
#include <StaticConstants.au3>
#include <String.au3>
#include <TreeViewConstants.au3>
#include <WindowsConstants.au3>
#include <WinAPI.au3>
#include <WinAPIProc.au3>
#include <WinAPISysWin.au3>
#include <WinAPITheme.au3>

; =====================================================================
; GLOBAL DECLARATIONS  (AutoItSetOption below is the first runnable line)
;   WARNING: at the top level, `Global $x = SomeCall()` EXECUTES SomeCall()
;   right now, in sequence - this is NOT an inert wall of declarations.
;   ObjCreate(), _Singleton(), IniRead() etc. all run as they're reached,
;   so the ORDER of these lines matters. (See AutoIt-Notes "run code".)
; =====================================================================
AutoItSetOption("GUICloseOnESC", 0)

Global $g_Version = "4.2.1"
Global $g_AppWndTitle = "GenP v" & $g_Version
Global $g_AppVersion = "GenP" & @CRLF & "Originally created by uncia"

Global $patchStatesINI = @ScriptDir & "\patch_states.ini"
Global $g_aStateQueue[0][5]
Global $g_bCryptActive = False
Global $g_mAppVersionQueue = ObjCreate("Scripting.Dictionary")
Global $g_mWinTrustQueue = ObjCreate("Scripting.Dictionary")
Global $g_mAppPrimaryExe = ObjCreate("Scripting.Dictionary")
Global $idSubProgress = -1
Global $idShowBetaApps = -1
Global $idEnableGood1 = -1
Global $idEnableNGLFirewall = -1
Global $idShowLaunchBar = -1
Global $idOlderVerDl = -1
Global $idFinalCleanCheck = -1
Global $idLabelRuntimeAuto = -1

Global $g_aAllFiles[0][6]
Global $g_hAppsBar = 0
Global $g_aAppsBarBtns[0][2]
Global $g_bAppsBarBuilt = False
Global $g_idAppsBarMinBtn    = -1
Global $g_idAppsBarConfigBtn = -1
Global $g_mCheckedState = ObjCreate("Scripting.Dictionary")
Global $g_bSearchCompleted = False
Global $g_bUpdateNoticeShown = False
Global $g_idOptionsProgress = -1
Global $g_sRequiresGood1Files = "|"

Global Const $g_iLogTabIndex = 7

Global $g_idStatusTitle = -1, $g_idStatusDetail = -1
Global $g_sCurrentSearchPath = ""

; --- Single-instance guard: if another GenP is already running, Exit now. ---
If _Singleton($g_AppWndTitle, 1) = 0 Then
	Exit
EndIf

Global $MyLVGroupIsExpanded = True
Global $g_aGroupIDs[0]
Global $fInterrupt = 0
Global $FilesToPatch[0][1], $FilesToPatchNull[0][1]
Global $FilesToRestore[0][1], $fFilesListed = 0
Global $MyhGUI, $hTab, $hMainTab, $hLogTab, $idMsg, $idListview, $g_idListview, $idButtonSearch, $idButtonStop
Global $g_hMsgBoxHook = 0, $g_pMsgBoxCBT = 0
Global $idButtonCustomFolder, $idBtnCure, $idBtnDeselectAll, $ListViewSelectFlag = 1
Global $idBtnModified = 0
Global $idBtnUpdateHosts, $idMemo, $timestamp, $idLog, $idBtnRestore, $idBtnCopyLog, $idFindACC
Global $idEnableMD5, $idOnlyAFolders, $idBtnSaveOptions, $idCustomDomainListLabel, $idCustomDomainListInput
Global $hPopupTab, $idBtnRemoveAGS, $idBtnCleanHosts, $idBtnEditHosts, $idLabelEditHosts, $sEditHostsText, $idBtnRestoreHosts, $idBtnAutoUpdateHosts

Global $g_aToolCtrls, $g_aOptCtrls, $g_aCheckCtrls, $idTriggerCaptureLaunch
Global $idBtnProxySetup, $idBtnProxyTargeting, $idBtnProxyStartStop, $idBtnProxyOpenLog, $idBtnProxyRemove
Global $g_idLblProxyStatus = 0

; --- Feature path CONSTANTS. KEY POINT (answers "is @AppDataCommonDir
;     permanent / only a compile-time thing?"): @-macros like
;     @AppDataCommonDir / @TempDir are resolved at RUNTIME, on the machine
;     running the exe - NOT baked in at build time. @AppDataCommonDir is
;     that PC's common AppData, normally C:\ProgramData (so, effectively
;     permanent, and portable across machines). These lines are PURE
;     string-building: they DEFINE paths, they do NOT create any folder.
;     The folder is made later, on demand (e.g. DirCreate in src\Proxy.au3
;     only when the Proxy feature is actually used). ---
#Au3Stripper_Ignore_Variables=$g_sMITM_DIR,$g_sMITM_EXE,$g_sMITM_SCRIPT,$g_sMITM_LOG,$g_sMITM_PORT,$g_sMITM_PROXY,$g_sMITM_CERT_NAME,$g_iMitmproxyPID,$g_sOVD_DIR,$g_sOVD_EXE
Global Const $g_sMITM_DIR = @AppDataCommonDir & "\GenP\mitmproxy"
Global Const $g_sMITM_EXE = $g_sMITM_DIR & "\mitmdump.exe"
Global Const $g_sMITM_SCRIPT = $g_sMITM_DIR & "\mitmproxy_genuine_fullguard.py"
Global Const $g_sOVD_DIR = @TempDir & "\GenP_OVD"
Global Const $g_sOVD_EXE = $g_sOVD_DIR & "\main.exe"
Global Const $g_sMITM_LOG = $g_sMITM_DIR & "\mitmdump.log"
Global $g_sMITM_PORT = "8080"
Global $g_sMITM_PROXY = "127.0.0.1:8080"
Global Const $g_sMITM_CERT_NAME = "mitmproxy"
Global $g_iMitmproxyPID = 0
Global $g_sLastCertError = ""
Global $g_hMitmLogWin = 0
Global $g_hMitmRichEdit = 0
Global $g_idBtnLogClose = 0
Global $g_idBtnLogClear = 0
Global $g_idBtnLogAddToHosts = 0
Global $g_idLblLogStatus = 0
Global $g_bMitmLogWindowExists = False
Global $g_bHostsInjectInProgress = False
Global $g_iMitmAppendCounter = 0
Global Const $g_iMitmLogCharCap = 500000

#Au3Stripper_Ignore_Variables=$g_sHAU_TASK_NAME,$g_sHAU_PS1_TARGET,$g_sHAU_LOG_TARGET,$g_iHAU_METHOD_NONE,$g_iHAU_METHOD_BASIC,$g_iHAU_METHOD_ADVANCED
Global Const $g_sHAU_TASK_NAME = "UpdateHostsFile"
Global Const $g_sHAU_PS1_TARGET = @WindowsDir & "\System32\drivers\etc\UpdateHostsFile.ps1"
Global Const $g_sHAU_LOG_TARGET = @WindowsDir & "\System32\drivers\etc\UpdateHostsFile.log"
Global Const $g_iHAU_METHOD_NONE = 0
Global Const $g_iHAU_METHOD_BASIC = 1
Global Const $g_iHAU_METHOD_ADVANCED = 2

#Au3Stripper_Ignore_Variables=$g_sGUDE_DIR,$g_sGUDE_TASK_NAME,$g_sGUDE_PS1_TARGET,$g_sGUDE_LOG_TARGET
Global Const $g_sGUDE_DIR        = @AppDataCommonDir & "\GenP\gude"
Global Const $g_sGUDE_TASK_NAME  = "GenP Gude Log Cleanup"
Global Const $g_sGUDE_PS1_TARGET = $g_sGUDE_DIR & "\RemoveGudeLogs.ps1"
Global Const $g_sGUDE_LOG_TARGET = $g_sGUDE_DIR & "\RemoveGudeLogs.log"

Global $sRemoveAGSText, $idLabelRemoveAGS, $sCleanFirewallText, $idLabelCleanFirewall, $idBtnOpenWF, $idBtnCreateFW, $idBtnRemoveFW, $idBtnToggleFW
Global $sRuntimeInstallerText, $idLabelRuntimeInstaller, $idBtnToggleRuntimeInstaller, $sWinTrustText, $idLabelWinTrust, $idBtnToggleWinTrust, $idBtnDevOverride
Global $idBtnAGSInfo, $idBtnFirewallInfo, $idBtnHostsInfo, $idBtnRuntimeInfo, $idBtnWintrustInfo

#Au3Stripper_Ignore_Variables=$g_aHitPatternsThisFile
Global $g_aHitPatternsThisFile[0]
Global $g_idHyperlinkMain, $g_idHyperlinkOptions, $g_idHyperlinkPopup, $g_idHyperlinkLog
Global $g_idHyperlinkFW = 0, $g_idHyperlinkHosts = 0, $g_idHyperlinkWT = 0, $g_idHyperlinkAGS = 0, $g_idHyperlinkProxy = 0

Global $idBtnCollapseAll = 0, $idBtnExpandAll = 0
Global $idBtnCheckAll = 0, $idBtnUncheckAll = 0
Global $idBtnCheckUnpatched = 0, $idBtnCheckPatched = 0, $idBtnRefresh = 0

Global $g_bBetaPatchedThisRun = False
Global $g_bLightroomCloudThisRun = False

Global $idResetOnSave = 0
Global $idClearLicCaches = 0
Global $idReconcileStates = 0
Global $idCreateStates = 0
Global $idUseCustomDefault = 0
Global $idBtnSetCustomPath = 0
Global $idOptionsReminder = 0
Global $g_mOptionsSnapshot = 0
Global $g_bOptionsDirty = False
Global $g_iOptionsPollTick = 0
Global $g_bIsPatching = False
Global $g_bUxpHandledFile = False
Global $g_bPendingInfoReset = False
Global $g_bInModifiedMode = False
Global $g_bAutoPatchPending = False
Global $g_bAutoPatchRun = False
Global $g_hBFFParent = 0
Global $g_AppCount = 0
Global $g_FilesToPatchCount = 0
Global $g_dotCounter = 0
Global $g_mScannedApps = 0
Global $g_mBlockedParents = 0
Global $g_mBlockedAppPaths = 0
Global $g_sLastScanDir = ""
Global $g_bStatusScreenReady = False
Global $g_bIsHighDpiScalingActive = False
Global $g_bFirstFileLogGap = True
Global $idBtnDummyAGS = 0
Global $idBtnRestoreAGS = 0
Global $idBtnSetTrustPath = 0
Global $idLabelTrustPath = 0
Global $g_sWinTrustPath
Global Const $g_sWT_IFEO = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
Global Const $g_sWT_SxS = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide"
Global Const $g_sWT_WT64 = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography\Wintrust\Config"
Global Const $g_sWT_WT32 = "HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config"

; =====================================================================
; CONFIG.INI: ensure it exists, then LOAD + VALIDATE it.
;   This is the program's DATA: target file names, byte-patterns, options.
;   IniRead COPIES values from the on-disk .ini into in-memory variables
;   (the file stays on disk; a few keys get written back below). It's plain
;   text, not bytecode - .ini (not .txt) so the built-in IniRead/IniWrite
;   can parse [Section]/key=value for free. Order matters (these run).
; =====================================================================
Global $sINIPath = @ScriptDir & "\config.ini"
If Not FileExists($sINIPath) Then
	FileInstall("config.ini", @ScriptDir & "\config.ini")
EndIf
Global $ConfigVerVar = IniRead($sINIPath, "Info", "ConfigVer", "????")

Global $g_aExpectedCounts[6][2] = [ _
		["TargetFiles", 80], _
		["RuntimeInstallers", 2], _
		["FirewallTrust", 36], _
		["DefaultPatterns", 1], _
		["CustomPatterns", 58], _
		["Patches", 153]]

Local $sCfgProblem = _ConfigHealthProblem()
If $sCfgProblem <> "" Then
	MsgBox(BitOR($MB_OK, $MB_ICONERROR, $MB_SYSTEMMODAL), "GenP - Config Problem", $sCfgProblem)
	If Not FileExists($sINIPath) Then Exit
Else
	Local $sCountProblem = _ConfigCountProblems()
	If $sCountProblem <> "" Then
		MsgBox(BitOR($MB_OK, $MB_ICONWARNING, $MB_SYSTEMMODAL), "GenP - Config Incomplete", _
				"config.ini version matches (" & $g_Version & "), but the sections do not" & @CRLF & _
				"contain the expected number of entries for this build:" & @CRLF & @CRLF & _
				$sCountProblem & @CRLF & _
				"The config may be truncated or hand-edited." & @CRLF & _
				"Patching, firewall and hosts results could be incomplete." & @CRLF & _
				"Replace config.ini with the one shipped for " & $g_Version & ".")
	EndIf
EndIf

Global $bUseCustomDefault = Number(IniRead($sINIPath, "Options", "UseCustomDefault", "0"))
Global $g_sCustomDefaultPath = StringRegExpReplace(IniRead($sINIPath, "Custom_Default", "Path", ""), "\\\\+", "\\")
Global $g_sPendingCustomPath = $g_sCustomDefaultPath

Global $bUseCustomWinTrust = Number(IniRead($sINIPath, "Options", "UseCustomWinTrust", "0"))
Global $g_sCustomWinTrustPath = StringRegExpReplace(IniRead($sINIPath, "Custom_WinTrust", "Path", ""), "\\\\+", "\\")
If $bUseCustomWinTrust = 1 And $g_sCustomWinTrustPath <> "" And FileExists($g_sCustomWinTrustPath) Then
	$g_sWinTrustPath = $g_sCustomWinTrustPath
Else
	$g_sWinTrustPath = @ProgramFilesDir & "\Adobe"
EndIf
$g_sWinTrustPath = StringRegExpReplace($g_sWinTrustPath, "\\\\+", "\\")
IniDelete($sINIPath, "Options", "WinTrustPath")

Global $MyDefPath
If $bUseCustomDefault = 1 And $g_sCustomDefaultPath <> "" And FileExists($g_sCustomDefaultPath) Then
	$MyDefPath = $g_sCustomDefaultPath
Else
	$MyDefPath = @ProgramFilesDir & "\Adobe"
EndIf
$MyDefPath = StringRegExpReplace($MyDefPath, "\\\\+", "\\")

IniWrite($sINIPath, "Default", "Path", @ProgramFilesDir & "\Adobe")

If Not FileExists($MyDefPath) Or Not StringInStr(FileGetAttrib($MyDefPath), "D") Then
	$MyDefPath = StringRegExpReplace(@ProgramFilesDir & "\Adobe", "\\\\+", "\\")
EndIf

Global $MyRegExpGlobalPatternSearchCount = 0, $Count = 0, $idProgressBar
Global $aOutHexGlobalArray[0], $aNullArray[0], $aInHexArray[0]
Global $MyFileToParse = "", $MyFileToParsSweatPea = "", $MyFileToParseEaclient = ""
Global $sz_type, $bFoundAcro32 = False, $bFoundGenericARM = False, $aSpecialFiles, $sSpecialFiles = "|"
Global $ProgressFileCountScale, $FileSearchedCount

Global $bFindACC = IniRead($sINIPath, "Options", "FindACC", "1")
Global $bEnableMD5 = 1
Global $bOnlyAFolders = IniRead($sINIPath, "Options", "OnlyDefaultFolders", "1")
Global $bShowBetaApps = IniRead($sINIPath, "Options", "ShowBetaApps", "1")
Global $bEnableGood1 = IniRead($sINIPath, "Options", "EnableGood1", "1")
Global $bClearLicCaches = IniRead($sINIPath, "Options", "ClearLicenseCaches", "1")
Global $bShowLaunchBar = Number(IniRead($sINIPath, "Options", "ShowLaunchBar", "0"))
Global $g_iAppsBarX = Number(IniRead($sINIPath, "Options", "LaunchBarX", "-1"))
Global $g_iAppsBarY    = Number(IniRead($sINIPath, "Options", "LaunchBarY", "-1"))
Global $g_sToolbarApps = IniRead($patchStatesINI, "Info", "ToolbarApps", "")
Global $bEnableNGLFirewall = IniRead($sINIPath, "Options", "NGLFirewall", "0")

Global $g_aNGLRelativePaths[9] = [ _
		"Common Files\Adobe\Adobe Desktop Common\NGL\adobe_licensing_wf.exe", _
		"Common Files\Adobe\Adobe Desktop Common\NGL\adobe_licensing_wf_helper.exe", _
		"Common Files\Adobe\Adobe Desktop Common\LCC\adobe_licensing_helper.exe", _
		"Adobe\Adobe Substance 3D Modeler\ngl\mangl\NGLWF_CCD\adobe_licensing_wf.exe", _
		"Adobe\Adobe Substance 3D Modeler\ngl\mangl\NGLWF_CCD\adobe_licensing_wf_helper.exe", _
		"Adobe\Adobe Substance 3D Modeler\ngl\mangl\LCC\adobe_licensing_helper.exe", _
		"Adobe\Adobe Substance 3D Modeler Beta\ngl\mangl\NGLWF_CCD\adobe_licensing_wf.exe", _
		"Adobe\Adobe Substance 3D Modeler Beta\ngl\mangl\NGLWF_CCD\adobe_licensing_wf_helper.exe", _
		"Adobe\Adobe Substance 3D Modeler Beta\ngl\mangl\LCC\adobe_licensing_helper.exe" _
		]
Global $g_sEdition = IniRead($sINIPath, "Options", "Edition", "GenP")

Global $g_sThirdPartyFirewall = ""
Global $fwc = ""
Global $SelectedApps = []

Global $sDefaultDomainListURL = "https://a.dove.isdumb.one/list.txt"
Global $sCurrentDomainListURL = IniRead($sINIPath, "Options", "CustomDomainListURL", $sDefaultDomainListURL)
Global $g_iDisplayOrientationScale = 1
Global $g_iHyperlinkClickTime = 0
Global Const $STN_CLICKED = 0

Local $tTargetFileList = IniReadSection($sINIPath, "TargetFiles")
Global $TargetFileList[0]
If Not @error Then
	ReDim $TargetFileList[$tTargetFileList[0][0]]
	For $i = 1 To $tTargetFileList[0][0]
		$TargetFileList[$i - 1] = StringReplace($tTargetFileList[$i][1], '"', "")
	Next
EndIf

$aSpecialFiles = IniReadSection($sINIPath, "CustomPatterns")
For $i = 1 To UBound($aSpecialFiles) - 1
	$sSpecialFiles = $sSpecialFiles & $aSpecialFiles[$i][0] & "|"
	Local $sPatternList = StringLower(StringReplace(StringReplace($aSpecialFiles[$i][1], '"', ''), ' ', ''))
	If StringInStr($sPatternList, "good1") > 0 Then
		$g_sRequiresGood1Files = $g_sRequiresGood1Files & StringLower($aSpecialFiles[$i][0]) & "|"
	EndIf
Next
Global $g_aSignature = "r~~z}D99""sus8nl%o|:8myw9qoxz7q sno}9"

; --- Hidden CLI mode: launched as `GenP.exe -updatehosts` it does that one
;     job and exits, with NO GUI. This is the entry the scheduled hosts
;     auto-update task calls. A normal double-click skips this block. ---
If $CmdLine[0] = 1 And $CmdLine[1] = "-updatehosts" Then
	UpdateHostsFile()
	Exit
EndIf

; --- Self-hash INTEGRITY CHECK (deliberately misnamed - it has nothing to
;     do with fonts). Reads the exe's own last 80 bytes; if the official
;     self-hash trailer is missing/wrong it shows the "not from official
;     sources" warning. Cosmetic; see GenP-Notes section D. ---
_InitializeFontLayoutEngine()


_CheckPatchStatesVersion()

; =====================================================================
; BUILD THE GUI
;   GUIRegisterMsg routes raw Windows WM_COMMAND messages to a handler.
;   MainGui() (in src\Ui.au3) builds the whole window and fills in every
;   $idBtn... control-ID global that the event loop below switches on.
; =====================================================================
GUIRegisterMsg($WM_COMMAND, "WM_COMMAND")

MainGui()

; --- Post-build startup: enable/disable buttons to match the CURRENT system
;     state (is hosts.bak present? is mitmproxy installed? is the hosts file
;     already edited?) and show one-time notices. Runs once, before the loop. ---
Local $bHostsbakExists = False
If FileExists(@WindowsDir & "\System32\drivers\etc\hosts.bak") Then
	GUICtrlSetState($idBtnRestoreHosts, $GUI_ENABLE)
	$bHostsbakExists = True
EndIf

#cs === [PROXY-REMOVED] startup enable block - delete this #cs and its matching #ce to restore ===
If _IsMitmproxyInstalled() Then
	GUICtrlSetState($idBtnProxyTargeting, $GUI_ENABLE)
	GUICtrlSetState($idBtnProxyStartStop, $GUI_ENABLE)
	GUICtrlSetState($idBtnProxyOpenLog, $GUI_ENABLE)
	GUICtrlSetState($idBtnProxyRemove, $GUI_ENABLE)
EndIf
#ce === [PROXY-REMOVED] end startup enable block ===

If StringInStr(FileRead(@WindowsDir & "\System32\drivers\etc\hosts"), "# START - Adobe Blocklist") Then
	GUICtrlSetState($idBtnCleanHosts, $GUI_ENABLE)
EndIf

_ShowUpdateNoticeIfNeeded()

If $bShowLaunchBar Then _RefreshAppsToolbar()

; =====================================================================
; MAIN EVENT LOOP ("the listener") - the program lives here until closed.
;   Top of each pass does periodic polling (window title, hosts.bak,
;   options-changed). GUIGetMsg() returns the clicked control's ID, and
;   the big Select/Case dispatches it. Most cases are 1-3 lines calling
;   into src\; but the heavy ones (SEARCH / PATCH / RESTORE / MODIFIED)
;   are written INLINE below - that is why this loop is so long. Each is
;   tagged with an [INLINE HANDLER] banner.
; =====================================================================
While 1

	If $g_iDisplayOrientationScale <> 1 And WinGetTitle($MyhGUI) <> $g_AppWndTitle Then
		WinSetTitle($MyhGUI, "", $g_AppWndTitle)
	EndIf

	Local $bHostsbakExistsNow
	If FileExists(@WindowsDir & "\System32\drivers\etc\hosts.bak") Then
		$bHostsbakExistsNow = True
	Else
		$bHostsbakExistsNow = False
	EndIf

	If $bHostsbakExistsNow <> $bHostsbakExists Then
		If $bHostsbakExistsNow Then
			GUICtrlSetState($idBtnRestoreHosts, $GUI_ENABLE)
		Else
			GUICtrlSetState($idBtnRestoreHosts, $GUI_DISABLE)
		EndIf
		$bHostsbakExists = $bHostsbakExistsNow
	EndIf

	$g_iOptionsPollTick += 1
	If $g_iOptionsPollTick >= 50 And Not $g_bIsPatching Then
		$g_iOptionsPollTick = 0
		CheckOptionsChanged()
	EndIf

	$idMsg = GUIGetMsg()
	If _AppsBar_Dispatch($idMsg) Then ContinueLoop

	If $g_bAutoPatchPending Then
		$g_bAutoPatchPending = False
		$g_bAutoPatchRun = True
		$idMsg = $idBtnCure
	EndIf

	Select
		Case $idMsg = $GUI_EVENT_CLOSE
			GUIDelete($MyhGUI)
			_Exit()
		Case $idMsg = $GUI_EVENT_RESIZED
			ContinueCase
		Case $idMsg = $GUI_EVENT_RESTORE
			ContinueCase
		Case $idMsg = $GUI_EVENT_MAXIMIZE
			Local $iWidth
			Local $aGui = WinGetPos($MyhGUI)
			Local $aRect = _GUICtrlListView_GetViewRect($g_idListview)
			If ($aRect[2] > $aGui[2]) Then
				$iWidth = $aGui[2] - 75
			Else
				$iWidth = $aRect[2] - 25
			EndIf
			GUICtrlSendMsg($idListview, $LVM_SETCOLUMNWIDTH, 1, $iWidth)

		Case $idMsg = $idButtonStop
			$ListViewSelectFlag = 0
			$fInterrupt = 1
			_ShowStatusScreen("stopped", $g_sLastScanDir)
			Sleep(1500)
			ReDim $g_aAllFiles[0][6]
			$g_bSearchCompleted = False
			$g_mCheckedState.RemoveAll()
			_ResetScanCounters()
			FillListViewWithInfo()
			MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "Waiting for user action.")
			GUICtrlSetState($idButtonStop, $GUI_HIDE)
			GUICtrlSetState($idButtonSearch, $GUI_SHOW)
			GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			_SetState($g_aToolCtrls, $GUI_ENABLE)
			_SetState($g_aOptCtrls, $GUI_ENABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_ENABLE)

		; --- [INLINE HANDLER] SEARCH: scan the Adobe folder(s) for the
		;     [TargetFiles] names (RecursiveFileSearch), then fill the listview. ---
		Case $idMsg = $idButtonSearch
			$fInterrupt = 0
			$g_bIsPatching = True
			GUICtrlSetData($idLog, "Activity Log" & @CRLF & "- - - - - - - - - - -" & @CRLF & @CRLF & "GenP Version: " & $g_Version & @CRLF & "Config Version: " & $ConfigVerVar & @CRLF)
			GUICtrlSetState($idButtonSearch, $GUI_HIDE)
			GUICtrlSetState($idButtonStop, $GUI_SHOW)
			ToggleLog(0)
			GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
			GUICtrlSetState($idListview, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idBtnModified, $GUI_DISABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_DISABLE)
			_SetState($g_aCheckCtrls, $GUI_DISABLE)
			_SetState($g_aToolCtrls, $GUI_DISABLE)
			_SetState($g_aOptCtrls, $GUI_DISABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
			_ResetScanCounters()
			$g_bFirstFileLogGap = True
			_ShowStatusScreen("scanning", $MyDefPath)

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

			$aSize = DirGetSize($MyDefPath, $DIR_EXTENDED)
			If UBound($aSize) >= 2 Then
				$FileCount = $aSize[1]
				$ProgressFileCountScale = 100 / $FileCount
				$FileSearchedCount = 0
				ProgressWrite(0)
				RecursiveFileSearch($MyDefPath, 0, $FileCount)
				Sleep(100)
				ProgressWrite(0)
			EndIf

			If $fInterrupt = 0 Then
				_ShowStatusScreen("complete", $MyDefPath)
				_SubProgressWrite(0)
				Sleep(3000)
			EndIf

			FillListViewWithFiles()

			_VerifyListedFiles(True)

			UpdateUIState()

			If _GUICtrlListView_GetItemCount($idListview) > 0 Then

				$ListViewSelectFlag = 1
				GUICtrlSetState($idButtonSearch, $GUI_DISABLE)
				GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
				GUICtrlSetState($idBtnCure, $GUI_ENABLE)

				If UBound($FilesToRestore) > 0 Then
					GUICtrlSetState($idBtnRestore, $GUI_ENABLE)
				EndIf
			Else
				$ListViewSelectFlag = 0
				FillListViewWithInfo()
				GUICtrlSetState($idBtnCure, $GUI_DISABLE)
				GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
				GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
			EndIf

			_Expand_All_Click()

			GUICtrlSetState($idBtnDeselectAll, $GUI_ENABLE)
			GUICtrlSetState($idListview, $GUI_ENABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_ENABLE)
			GUICtrlSetState($idButtonSearch, $GUI_SHOW)
			GUICtrlSetState($idButtonStop, $GUI_HIDE)
			_SetState($g_aToolCtrls, $GUI_ENABLE)
			_SetState($g_aOptCtrls, $GUI_ENABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_ENABLE)
			$g_bIsPatching = False

		Case $idMsg = $idButtonCustomFolder
			ToggleLog(0)
			MyFileOpenDialog()
			_Expand_All_Click()
			If $fFilesListed = 0 Then
				GUICtrlSetState($idBtnCure, $GUI_DISABLE)
				GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
				GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
			Else
				GUICtrlSetState($idButtonSearch, $GUI_DISABLE)
				GUICtrlSetState($idBtnDeselectAll, $GUI_ENABLE)
				GUICtrlSetState($idBtnCure, $GUI_ENABLE)
			EndIf

		Case $idMsg = $idBtnCheckAll
			ToggleLog(0)
			For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1
				_GUICtrlListView_SetItemChecked($idListview, $i, 1)
			Next
			$ListViewSelectFlag = 1

		Case $idMsg = $idBtnUncheckAll
			ToggleLog(0)
			For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1
				_GUICtrlListView_SetItemChecked($idListview, $i, 0)
			Next
			$ListViewSelectFlag = 0

		Case $idMsg = $idBtnCheckUnpatched
			ToggleLog(0)
			Local $iCt = _GUICtrlListView_GetItemCount($idListview)
			Local $iChecked = 0
			For $i = 0 To $iCt - 1
				Local $sStatus = _GUICtrlListView_GetItemText($idListview, $i, 2)
				If $sStatus <> "Patched" Then
					_GUICtrlListView_SetItemChecked($idListview, $i, 1)
					$iChecked += 1
				Else
					_GUICtrlListView_SetItemChecked($idListview, $i, 0)
				EndIf
			Next
			MemoWrite(@CRLF & "Checked " & $iChecked & " non-patched file(s) of " & $iCt & " listed.")
			$ListViewSelectFlag = ($iChecked > 0) ? 1 : 0

		Case $idMsg = $idBtnCheckPatched
			Local $iCt = _GUICtrlListView_GetItemCount($idListview)
			Local $iChecked = 0
			For $i = 0 To $iCt - 1
				Local $sStatus = _GUICtrlListView_GetItemText($idListview, $i, 2)
				If $sStatus = "Patched" Then
					_GUICtrlListView_SetItemChecked($idListview, $i, 1)
					$iChecked += 1
				Else
					_GUICtrlListView_SetItemChecked($idListview, $i, 0)
				EndIf
			Next
			MemoWrite(@CRLF & "Checked " & $iChecked & " patched file(s) of " & $iCt & " listed.")
			$ListViewSelectFlag = ($iChecked > 0) ? 1 : 0

		Case $idMsg = $idBtnRefresh
			ToggleLog(0)
			$fInterrupt = 0
			_RefreshSearch()

		; --- [INLINE HANDLER] PATCH / CURE: the core action, and the biggest
		;     block in this file. Runs gate checks (target folder, config,
		;     stop-Adobe prompt, Elements-2026 grouping, NGL firewall), then for
		;     each CHECKED file applies the config byte-patterns via
		;     MyGlobalPatternSearch / MyGlobalPatternPatch, keeping a .bak. ---
		Case $idMsg = $idBtnCure
			Local $sCureTgtWhy = _TargetFolderReady($MyDefPath)
			If $sCureTgtWhy <> "" Then
				MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Cannot Patch - Target Folder", $sCureTgtWhy)
				LogWrite(1, "Patch aborted - target folder not ready: " & $MyDefPath)
				ContinueLoop
			EndIf
			Local $sCureCfgWhy = _ConfigHealthProblem()
			If $sCureCfgWhy <> "" Then
				Local $iCureGo = MsgBox(BitOR($MB_YESNO, $MB_DEFBUTTON2, $MB_ICONWARNING, $MB_SYSTEMMODAL), _
						"GenP - Patch With Unverified Config?", _
						$sCureCfgWhy & @CRLF & @CRLF & _
						"Patching now may apply an incomplete or wrong pattern set, which can" & @CRLF & _
						"leave Adobe apps unbootable (black screens). Continue patching anyway?")
				If $iCureGo <> $IDYES Then
					MemoWrite(@CRLF & "Patch cancelled: config.ini failed verification." & @CRLF)
					LogWrite(1, "Patch aborted by config gate: " & StringReplace($sCureCfgWhy, @CRLF, " "))
					ContinueLoop
				EndIf
				LogWrite(1, "Patch proceeding despite config gate (user confirmed).")
			EndIf
			If _PromptStopAdobeProcessesForOp("patched") = 0 Then
				LogWrite(1, "Patch aborted by user at Adobe-process prompt.")
				ContinueLoop
			EndIf
			Local $bPSE2026 = False, $bPRE2026 = False, $bORG2026 = False
			Local $aOrgItems[0], $aPseItems[0], $aPreItems[0]
			Local $iCountAll = _GUICtrlListView_GetItemCount($idListview)
			For $i = 0 To $iCountAll - 1
				If Not _GUICtrlListView_GetItemChecked($idListview, $i) Then ContinueLoop
				Local $sPath = _GUICtrlListView_GetItemText($idListview, $i, 1)
				Local $sGrp = _GetAppGroupName($sPath)
				If $sGrp = "Elements 2026 Organizer" Then
					$bORG2026 = True
					_ArrayAdd($aOrgItems, $i)
				ElseIf $sGrp = "Photoshop Elements 2026" Then
					$bPSE2026 = True
					_ArrayAdd($aPseItems, $i)
				ElseIf $sGrp = "Premiere Elements 2026" Then
					$bPRE2026 = True
					_ArrayAdd($aPreItems, $i)
				EndIf
			Next
			If $g_bAutoPatchRun Then
				LogWrite(1, "Auto-patch (create-states): Elements 2026 'patch together' prompt skipped." & @CRLF & "All installed items already queued and ready to patch.")
			ElseIf ($bPSE2026 Or $bPRE2026 Or $bORG2026) And Not ($bPSE2026 And $bPRE2026 And $bORG2026) Then
				Local $bHasPSE = False, $bHasPRE = False, $bHasORG = False
				For $i = 0 To $iCountAll - 1
					Local $sPath = _GUICtrlListView_GetItemText($idListview, $i, 1)
					Local $sGrp = _GetAppGroupName($sPath)
					If $sGrp = "Photoshop Elements 2026" Then $bHasPSE = True
					If $sGrp = "Premiere Elements 2026" Then $bHasPRE = True
					If $sGrp = "Elements 2026 Organizer" Then $bHasORG = True
				Next
				Local $sMissing = ""
				If $bHasPSE And Not $bPSE2026 Then $sMissing &= "  - Photoshop Elements 2026" & @CRLF
				If $bHasPRE And Not $bPRE2026 Then $sMissing &= "  - Premiere Elements 2026" & @CRLF
				If $bHasORG And Not $bORG2026 Then $sMissing &= "  - Elements 2026 Organizer" & @CRLF
				Local $iAns = MsgBox($MB_YESNOCANCEL, _
						"Elements 2026 - patch together?", _
						"Photoshop Elements, Premiere Elements and the Organizer" & @CRLF & _
						"share components and should be patched as a single unit." & @CRLF & @CRLF & _
						"These items are unchecked:" & @CRLF & $sMissing & @CRLF & _
						"Yes = auto-check them and continue" & @CRLF & _
						"No  = continue anyway (not recommended)" & @CRLF & _
						"Cancel = abort patch")
				If $iAns = $IDCANCEL Then
					$g_bIsPatching = False
					ContinueLoop
				ElseIf $iAns = $IDYES Then
					For $i = 0 To $iCountAll - 1
						Local $sPath = _GUICtrlListView_GetItemText($idListview, $i, 1)
						Local $sGrp = _GetAppGroupName($sPath)
						If ($sGrp = "Photoshop Elements 2026" And $bHasPSE) Or _
								($sGrp = "Premiere Elements 2026" And $bHasPRE) Or _
								($sGrp = "Elements 2026 Organizer" And $bHasORG) Then
							_GUICtrlListView_SetItemChecked($idListview, $i, 1)
						EndIf
					Next
					MemoWrite(@CRLF & "Auto-checked missing Elements 2026 items for consistent patch.")
				EndIf
			EndIf

			Local $bAppsSelected = False
			For $i = 0 To $iCountAll - 1
				If _GUICtrlListView_GetItemChecked($idListview, $i) Then
					$bAppsSelected = True
					ExitLoop
				EndIf
			Next

			If $bAppsSelected And $bEnableNGLFirewall = 1 Then
				If _EnableNGLFirewallRules(False) = -99 Then
					MemoWrite(@CRLF & "Patch cancelled - add your third-party firewall rules, then patch again.")
					ContinueLoop
				EndIf
			EndIf

			$g_bAutoPatchRun = False

			ToggleLog(0)
			$g_bIsPatching = True
			$g_bBetaPatchedThisRun = False
			$g_bLightroomCloudThisRun = False
			_SetState($g_aOptCtrls, $GUI_DISABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
			_SetState($g_aCheckCtrls, $GUI_DISABLE)
			GUICtrlSetState($idListview, $GUI_DISABLE)
			GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
			GUICtrlSetState($idButtonSearch, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_DISABLE)
			_SetState($g_aToolCtrls, $GUI_DISABLE)
			_SetState($g_aOptCtrls, $GUI_DISABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
			_Expand_All_Click()

			Local $ItemFromList
			Local $iTotalChecked = 0, $iDone = 0
			Local $iFirstChecked = -1
			For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1
				If _GUICtrlListView_GetItemChecked($idListview, $i) = True Then
					$iTotalChecked += 1
					If $iFirstChecked = -1 Then $iFirstChecked = $i
				EndIf
			Next

			If $iFirstChecked >= 0 Then
				_GUICtrlListView_EnsureVisible($idListview, $iFirstChecked, 0)
			EndIf

			ProgressWrite(0)
			_SubProgressWrite(0)
			If $bEnableMD5 = 1 Then
				_Crypt_Startup()
				$g_bCryptActive = True
			EndIf

			For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1

				If _GUICtrlListView_GetItemChecked($idListview, $i) = True Then

					_GUICtrlListView_SetItemSelected($idListview, $i)
					$ItemFromList = _GUICtrlListView_GetItemText($idListview, $i, 1)

					_GUICtrlListView_SetItemText($idListview, $i, "Patching...", 2)

					_GUICtrlListView_EnsureVisible($idListview, $i, 0)

					If $g_bFirstFileLogGap Then
						LogWrite(1, "")
						$g_bFirstFileLogGap = False
					EndIf

					If _PathIsBeta($ItemFromList) Then
						$g_bBetaPatchedThisRun = True
						LogWrite(1, "Beta app detected. This may break with any update, no support provided.")
					EndIf

					If _PathIsLightroomCloud($ItemFromList) Then
						$g_bLightroomCloudThisRun = True
						LogWrite(1, "Lightroom (cloud) detected. Patched installs are unreliable - use Lightroom Classic for full compatibility.")
					EndIf

					If FileGetSize($ItemFromList) > 200 * 1024 * 1024 Then
						_PatchLargeFileWithPatterns($ItemFromList)
					Else
						MyGlobalPatternSearch($ItemFromList)
						If Not $g_bUxpHandledFile Then
							MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $ItemFromList & @CRLF & "---" & @CRLF & "medication :)")
							LogWrite(1, $ItemFromList)
						EndIf

						MyGlobalPatternPatch($ItemFromList, $aOutHexGlobalArray)
					EndIf

					If FileExists($ItemFromList & ".bak") Then
						_GUICtrlListView_SetItemText($idListview, $i, "Patched", 2)
					Else
						_GUICtrlListView_SetItemText($idListview, $i, "Unchanged", 2)
					EndIf

					$iDone += 1
					If $iTotalChecked > 0 Then ProgressWrite(Round($iDone / $iTotalChecked * 100))

					Sleep(50)

				EndIf

				_GUICtrlListView_SetItemChecked($idListview, $i, False)
			Next

			If $g_bCryptActive Then
				_Crypt_Shutdown()
				$g_bCryptActive = False
			EndIf

			_FlushStateQueue()
			_RefreshAppsToolbar()

			If $idClearLicCaches <> 0 And _IsChecked($idClearLicCaches) Then _ClearLicenseCachesLight()

			ProgressWrite(0)
			_SubProgressWrite(0)

			$g_bIsPatching = False
			_SetState($g_aOptCtrls, $GUI_ENABLE)
			CheckOptionsChanged()

			If $g_bInModifiedMode Then
				_VerifyListedFiles(True)

				Local $iStillTodo = 0
				Local $iRow = _GUICtrlListView_GetItemCount($g_idListview) - 1
				_SendMessageL($g_idListview, $WM_SETREDRAW, False, 0)
				While $iRow >= 0
					Local $sStatusMod = _GUICtrlListView_GetItemText($g_idListview, $iRow, 2)
					If $sStatusMod = "Patched" Then
						_GUICtrlListView_DeleteItem($g_idListview, $iRow)
					Else
						$iStillTodo += 1
					EndIf
					$iRow -= 1
				WEnd
				_SendMessageL($g_idListview, $WM_SETREDRAW, True, 0)
				_RedrawWindow($g_idListview)

				If $iStillTodo = 0 Then
					MemoWrite(@CRLF & "Modified work queue is now empty.")
					LogWrite(1, "Modified work queue drained - all files patched.")

					If $bEnableNGLFirewall = 1 Then
						MemoWrite(@CRLF & "Notice: NGL Firewall isolation rule is active; network channels are locked down.")
						MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Network Isolation Active", _
								"The NGL Firewall rule is successfully monitoring active modules." & @CRLF & @CRLF & _
								"A full system restart is not strictly mandatory for the firewall rules, " & @CRLF & _
								"but closing and reopening your applications is recommended to apply states.")
					EndIf
					_ShowEmptyModifiedNotice()
					$g_bIsPatching = False
					$g_bPendingInfoReset = False
					_RestorePostOpUI()
					UpdateUIState()
					ToggleLog(1)
					_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
					MemoWrite(@CRLF & "Patching complete." & @CRLF & "You can carry on.")
				Else
					MemoWrite(@CRLF & "Unpatched: " & $iStillTodo & " file(s) still need patching (click Patch again).")
					LogWrite(1, "Unpatched: " & $iStillTodo & " file(s) remain after patch run.")
					$g_bIsPatching = False
					$g_bPendingInfoReset = True
					_RestorePostOpUI()
					UpdateUIState()
					ToggleLog(1)
					GUICtrlSetState($hLogTab, $GUI_SHOW)
					_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
					MemoWrite(@CRLF & "Patching complete." & @CRLF & "You can carry on.")

					_FinalisePatchRun()
					ContinueLoop
				EndIf
			EndIf

			$g_bPendingInfoReset = True

			UpdateUIState()

			MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "waiting for user action")
			GUICtrlSetState($idListview, $GUI_ENABLE)
			GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_ENABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			_SetState($g_aToolCtrls, $GUI_ENABLE)
			_SetState($g_aOptCtrls, $GUI_ENABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_ENABLE)
			FillListViewWithInfo()

			If $bFoundAcro32 = True Then
				MsgBox($MB_SYSTEMMODAL, "Information", "GenP does not patch the x32 bit version of Acrobat." & @CRLF & @CRLF & "Please use the x64 bit version of Acrobat.")
				LogWrite(1, "GenP does not patch the x32 bit version of Acrobat. Please use the x64 bit version of Acrobat.")
			EndIf
			If $bFoundGenericARM = True Then
				MsgBox($MB_SYSTEMMODAL, "Information", "This GenP build does not support ARM binaries, only x64.")
				LogWrite(1, "This GenP build does not support ARM binaries, only x64.")
			EndIf

			ToggleLog(1)
			GUICtrlSetState($hLogTab, $GUI_SHOW)
			_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)
			MemoWrite(@CRLF & "Patching complete." & @CRLF & "You can carry on.")

			_FinalisePatchRun()

		; --- [INLINE HANDLER] MODIFIED: rescan + verify, then filter the list
		;     down to files that still differ from baseline (the "what still
		;     needs patching" view). Patching from here drains that queue. ---
		Case $idMsg = $idBtnModified
			$fInterrupt = 0
			$g_bIsPatching = True
			GUICtrlSetData($idLog, "Activity Log" & @CRLF & "- - - - - - - - - - -" & @CRLF & @CRLF & "GenP Version: " & $g_Version & @CRLF & "Config Version: " & $ConfigVerVar & @CRLF)
			GUICtrlSetState($idButtonSearch, $GUI_HIDE)
			GUICtrlSetState($idButtonStop, $GUI_SHOW)
			ToggleLog(0)
			GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
			GUICtrlSetState($idListview, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idBtnModified, $GUI_DISABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_DISABLE)
			_SetState($g_aCheckCtrls, $GUI_DISABLE)
			_SetState($g_aToolCtrls, $GUI_DISABLE)
			_SetState($g_aOptCtrls, $GUI_DISABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)

			MemoWrite(@CRLF & "Modified workflow: scanning + verifying...")
			_RefreshSearch()

			GUICtrlSetState($idButtonStop, $GUI_HIDE)
			GUICtrlSetState($idButtonSearch, $GUI_SHOW)
			GUICtrlSetState($idListview, $GUI_ENABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_ENABLE)
			_SetState($g_aToolCtrls, $GUI_ENABLE)
			_SetState($g_aOptCtrls, $GUI_ENABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_ENABLE)

			Local $iKept = _ApplyModifiedFilter()

			If $iKept = 0 Then
				$g_bIsPatching = False
				_ShowEmptyModifiedNotice()
			Else
				UpdateUIState()
			EndIf

		; --- [INLINE HANDLER] RESTORE: for each checked file, put back its .bak
		;     backup (RestoreFile), undoing a patch; reports files still in use. ---
		Case $idMsg = $idBtnRestore
			Local $sRestTgtWhy = _TargetFolderReady($MyDefPath)
			If $sRestTgtWhy <> "" Then
				MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Cannot Restore - Target Folder", $sRestTgtWhy)
				LogWrite(1, "Restore aborted - target folder not ready: " & $MyDefPath)
				ContinueLoop
			EndIf

			If _PromptStopAdobeProcessesForOp("restored") = 0 Then
				LogWrite(1, "Restore aborted by user at Adobe-process prompt.")
				ContinueLoop
			EndIf

			GUICtrlSetData($idLog, "Activity Log" & @CRLF & "- - - - - - - - - - -" & @CRLF & @CRLF & "GenP Version: " & $g_Version & "" & @CRLF & "Config Version: " & $ConfigVerVar & "" & @CRLF)
			ToggleLog(0)
			$g_bIsPatching = True

			_SetState($g_aOptCtrls, $GUI_DISABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_DISABLE)
			_SetState($g_aCheckCtrls, $GUI_DISABLE)
			GUICtrlSetState($idListview, $GUI_DISABLE)
			GUICtrlSetState($idBtnDeselectAll, $GUI_DISABLE)
			GUICtrlSetState($idButtonSearch, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_DISABLE)
			_SetState($g_aToolCtrls, $GUI_DISABLE)
			_Expand_All_Click()

			Local $ItemFromList
			Local $iTotalChecked = 0, $iDone = 0
			Local $aRestoredPaths[0]
			Local $aUnrestoredInUse[0]
			Local $iFirstChecked = -1
			For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1
				If _GUICtrlListView_GetItemChecked($idListview, $i) = True Then
					$iTotalChecked += 1
					If $iFirstChecked = -1 Then $iFirstChecked = $i
				EndIf
			Next

			If $iFirstChecked >= 0 Then
				_GUICtrlListView_EnsureVisible($idListview, $iFirstChecked, 0)
			EndIf

			ProgressWrite(0)
			_SubProgressWrite(0)
			If $bEnableMD5 = 1 Then
				_Crypt_Startup()
				$g_bCryptActive = True
			EndIf

			For $i = 0 To _GUICtrlListView_GetItemCount($idListview) - 1

				If _GUICtrlListView_GetItemChecked($idListview, $i) = True Then

					_GUICtrlListView_SetItemSelected($idListview, $i)

					$ItemFromList = _GUICtrlListView_GetItemText($idListview, $i, 1)
					_ArrayAdd($aRestoredPaths, $ItemFromList)

					_GUICtrlListView_SetItemText($idListview, $i, "Restoring...", 2)
					_SubProgressWrite(50)

					_GUICtrlListView_EnsureVisible($idListview, $i, 0)

					Local $bOk = RestoreFile($ItemFromList)

					If $bOk = 1 Then
						_GUICtrlListView_SetItemText($idListview, $i, "Unpatched", 2)
					ElseIf $bOk = -1 Then
						_GUICtrlListView_SetItemText($idListview, $i, "In use", 2)
						_ArrayAdd($aUnrestoredInUse, $ItemFromList)
					Else
						_GUICtrlListView_SetItemText($idListview, $i, "No backup", 2)
					EndIf

					_SubProgressWrite(100)
					$iDone += 1
					If $iTotalChecked > 0 Then ProgressWrite(Round($iDone / $iTotalChecked * 100))

					MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $ItemFromList & @CRLF & "---" & @CRLF & "restoring :)")
					Sleep(50)

				EndIf

				_GUICtrlListView_SetItemChecked($idListview, $i, False)
			Next

			If $g_bCryptActive Then
				_Crypt_Shutdown()
				$g_bCryptActive = False
			EndIf

			_CleanOrphanBaks($aRestoredPaths)

			_FlushStateQueue()
			_RefreshAppsToolbar()

			If UBound($aUnrestoredInUse) > 0 Then
				Local $sUnrestMsg = UBound($aUnrestoredInUse) & " file(s) could not be restored because they were still in use:" & @CRLF & @CRLF
				For $iU = 0 To UBound($aUnrestoredInUse) - 1
					$sUnrestMsg &= "  - " & $aUnrestoredInUse[$iU] & @CRLF
				Next
				$sUnrestMsg &= @CRLF & "Their backups (.bak) have been preserved. Close any open" & @CRLF & "Adobe apps and run Restore again to finish."
				LogWrite(1, "Restore finished with " & UBound($aUnrestoredInUse) & " file(s) left unrestored (in use).")
				MsgBox(BitOR($MB_OK, $MB_ICONEXCLAMATION, $MB_SYSTEMMODAL), "Some Files Not Restored", $sUnrestMsg)
			EndIf

			ProgressWrite(0)
			_SubProgressWrite(0)

			$g_bIsPatching = False

			_SetState($g_aOptCtrls, $GUI_ENABLE)
			CheckOptionsChanged()

			$g_bPendingInfoReset = True

			UpdateUIState()

			MemoWrite(@CRLF & "Path" & @CRLF & "---" & @CRLF & $MyDefPath & @CRLF & "---" & @CRLF & "waiting for user action")

			GUICtrlSetState($idListview, $GUI_ENABLE)
			GUICtrlSetState($idButtonCustomFolder, $GUI_ENABLE)
			GUICtrlSetState($idBtnRestore, $GUI_DISABLE)
			GUICtrlSetState($idBtnCure, $GUI_DISABLE)
			GUICtrlSetState($idButtonSearch, $GUI_ENABLE)
			_SetState($g_aToolCtrls, $GUI_ENABLE)
			GUICtrlSetState($idBtnSaveOptions, $GUI_ENABLE)
			FillListViewWithInfo()

			ToggleLog(1)
			_GUICtrlTab_SetCurFocus($hTab, $g_iLogTabIndex)

		Case $idMsg = $idBtnCopyLog
			SendToClipBoard()

		Case $idMsg = $idFindACC
			If _IsChecked($idFindACC) Then
				$bFindACC = 1
			Else
				$bFindACC = 0
			EndIf
			_ApplyVisibilityFilter()
			CheckOptionsChanged()

		Case $idMsg = $idOnlyAFolders
			If _IsChecked($idOnlyAFolders) Then
				$bOnlyAFolders = 1
			Else
				$bOnlyAFolders = 0
			EndIf
			If Not $g_bSearchCompleted Then FillListViewWithInfo()
			CheckOptionsChanged()

		Case $idMsg = $idShowBetaApps
			If _IsChecked($idShowBetaApps) Then
				$bShowBetaApps = 1
			Else
				$bShowBetaApps = 0
			EndIf
			_ApplyVisibilityFilter()
			CheckOptionsChanged()

		Case $idMsg = $idEnableGood1
			If _IsChecked($idEnableGood1) Then
				$bEnableGood1 = 1
			Else
				$bEnableGood1 = 0
			EndIf
			_ApplyVisibilityFilter()
			CheckOptionsChanged()

		Case $idMsg = $idResetOnSave
			CheckOptionsChanged()

		Case $idMsg = $idFinalCleanCheck
			CheckOptionsChanged()

		Case $idMsg = $idEnableNGLFirewall
			If _IsChecked($idEnableNGLFirewall) Then
				$bEnableNGLFirewall = 1
			Else
				$bEnableNGLFirewall = 0
			EndIf
			CheckOptionsChanged()

		Case $idMsg = $idClearLicCaches
			If Not _IsChecked($idClearLicCaches) Then
				Local $iKeepLic = MsgBox(BitOR($MB_YESNO, $MB_ICONQUESTION, $MB_DEFBUTTON1, $MB_SYSTEMMODAL), _
						"Clear License Caches  -  Recommended", _
						"Clearing licence caches after patching is recommended and is on by default." & @CRLF & @CRLF & _
						"Leaving it on clears stale licence state so apps don't show licence errors" & @CRLF & _
						"straight after patching." & @CRLF & @CRLF & _
						"Keep it enabled?" & @CRLF & @CRLF & _
						"Yes = keep it on (recommended)." & @CRLF & _
						"No = turn it off.")
				If $iKeepLic <> $IDNO Then GUICtrlSetState($idClearLicCaches, $GUI_CHECKED)
			EndIf
			CheckOptionsChanged()

		Case $idMsg = $idShowLaunchBar
			CheckOptionsChanged()

#cs === [OVD-REMOVED] "Older versions download" option case ===
		Case $idMsg = $idOlderVerDl
			CheckOptionsChanged()
#ce === [OVD-REMOVED] end option case ===

		Case $idMsg = $idReconcileStates
			If _IsChecked($idReconcileStates) Then GUICtrlSetState($idCreateStates, $GUI_UNCHECKED)
			CheckOptionsChanged()

		Case $idMsg = $idCreateStates
			If _IsChecked($idCreateStates) Then GUICtrlSetState($idReconcileStates, $GUI_UNCHECKED)
			CheckOptionsChanged()

		Case $idMsg = $idUseCustomDefault
			If _IsChecked($idUseCustomDefault) Then
				Local $sPickedPath = _BrowseForFolderDialog("Select the folder to open to on launch", $MyhGUI)
				If $sPickedPath <> "" Then
					GUICtrlSetData($idBtnSetCustomPath, StringRegExpReplace($sPickedPath, "\\\\+", "\\\\"))
				EndIf
			EndIf
			CheckOptionsChanged()

#cs === [PROXY-REMOVED] "trigger capture" option case ===
		Case $idMsg = $idTriggerCaptureLaunch
			CheckOptionsChanged()
#ce === [PROXY-REMOVED] end "trigger capture" case ===

		Case $idMsg = $idBtnSaveOptions
			; [PROXY-REMOVED] Local $bShouldTrigger    = _IsChecked($idTriggerCaptureLaunch)
			; [OVD-REMOVED] Local $bLaunchOlderVerDl = _IsChecked($idOlderVerDl)
			SaveOptionsToConfig()

#cs === [OVD-REMOVED] Older-versions-download launch block: extracts the bundled main.exe to %TEMP%\GenP_OVD, configures it via env vars (GENP_INSTALL_DIR / GENP_DOWNLOADS_DIR), and runs it in a console. ===
			If $bLaunchOlderVerDl Then
				GUICtrlSetState($idOlderVerDl, $GUI_UNCHECKED)
				_SnapshotOptions()
				DirRemove($g_sOVD_DIR, 1)
				DirCreate($g_sOVD_DIR)
				FileInstall("resources\mitmproxy\main.exe", $g_sOVD_EXE, 1)
				If Not FileExists($g_sOVD_EXE) Then
					MemoWrite(@CRLF & "Error: could not extract GenP - Adobe Older Versions Downloader (main.exe).")
				Else
					Local $sInstallDir = "C:\Program Files\Adobe"
					Local $iInstChoice = MsgBox(BitOR($MB_YESNOCANCEL, $MB_ICONQUESTION), _
							"Install Location", _
							"Install downloaded versions to the default location?" & @CRLF & @CRLF & _
							$sInstallDir & @CRLF & @CRLF & _
							"Yes  = default (recommended)" & @CRLF & _
							"No   = choose another location (e.g. another drive)" & @CRLF & _
							"Cancel = don't download")
					If $iInstChoice = $IDCANCEL Then
						MemoWrite(@CRLF & "Older versions download cancelled.")
					Else
						If $iInstChoice = $IDNO Then
							Local $sPick = _BrowseForFolderDialog("Choose the Adobe install location", $MyhGUI)
							If $sPick <> "" Then $sInstallDir = $sPick
						EndIf
						EnvSet("GENP_INSTALL_DIR", $sInstallDir)
						MemoWrite(@CRLF & "Install location: " & $sInstallDir)

						Local $sOvdDest = @ScriptDir & "\Adobe Downloads"
						EnvSet("GENP_DOWNLOADS_DIR", $sOvdDest)
						MemoWrite(@CRLF & "Launching GenP - Adobe Older Versions Downloader by MP7909.")
						MemoWrite("Downloads will be saved to: " & $sOvdDest)
						Local $iPID = Run('cmd.exe /k "title GenP - Adobe Older Versions Downloader & color 0F & mode con cols=100 & .\main.exe"', $g_sOVD_DIR, @SW_SHOW)
						If $iPID = 0 Then
							MemoWrite("Error: could not open console for main.exe (code " & @error & ").")
						Else
							Local $sIconPath = @ScriptDir & "\Skull.ico"
							If FileExists($sIconPath) Then
								Local $hCon = WinWait("GenP - Adobe Older Versions Downloader", "", 2)
								If $hCon Then
									Local $aIcon = DllCall("user32.dll", "handle", "LoadImageW", _
											"handle", 0, "wstr", $sIconPath, "uint", 1, "int", 0, "int", 0, "uint", 0x10)
									If Not @error And IsArray($aIcon) And $aIcon[0] Then
										DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hCon, "uint", 0x80, "wparam", 1, "lparam", $aIcon[0])
										DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hCon, "uint", 0x80, "wparam", 0, "lparam", $aIcon[0])
									EndIf
								EndIf
							EndIf
						EndIf
					EndIf
				EndIf
			EndIf
#ce === [OVD-REMOVED] end Older-versions-download launch block ===

#cs === [PROXY-REMOVED] Save-Options "trigger one-off capture" block ===
			If $bShouldTrigger Then
				_TriggerOneOffCaptureAndLaunch()
				GUICtrlSetState($idTriggerCaptureLaunch, $GUI_UNCHECKED)
				_SnapshotOptions()
			EndIf
#ce === [PROXY-REMOVED] end Save-Options trigger block ===

			If Number($bEnableGood1) Then
				If Not _IsGudeCleanupInstalled() And IniRead($sINIPath, "Options", "GudeDismissed", "0") <> "1" Then
					_ShowGudeSetupPrompt()
				EndIf
			Else
				If _IsGudeCleanupInstalled() And IniRead($sINIPath, "Options", "GudeDismissedRemove", "0") <> "1" Then
					_ShowGudeRemovePrompt()
				EndIf
			EndIf

		Case $idMsg = $idBtnRemoveAGS
			RemoveAGS()

		Case $idMsg = $idBtnDummyAGS
			InstallAGSDummy()

			MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION, $MB_SYSTEMMODAL), _
					"Restart Required", _
					"Dummy AGS components have been installed." & @CRLF & @CRLF & _
					"A device restart is required so the changes take effect." & @CRLF & _
					"GenP will now restart your device. Please save any open work" & @CRLF & _
					"in other applications before continuing.")

			LogWrite(1, "Dummy AGS install - restart enforced.")
			Shutdown(BitOR(2, 16))
			Exit

		Case $idMsg = $idBtnRestoreAGS
			RestoreAGSDummy()

		Case $idMsg = $idBtnSetTrustPath
			Local $sSelected = _BrowseForFolderDialog("Select the Adobe installation folder for WinTrust", $MyhGUI)
			If $sSelected = "" Then ContinueLoop
			$g_sWinTrustPath = $sSelected
			$g_sCustomWinTrustPath = $sSelected
			$bUseCustomWinTrust = 1
			GUICtrlSetData($idLabelTrustPath, "Path: " & $g_sWinTrustPath)
			IniWrite($sINIPath, "Custom_WinTrust", "Path", $g_sWinTrustPath)
			IniWrite($sINIPath, "Options", "UseCustomWinTrust", "1")
			IniDelete($sINIPath, "Options", "WinTrustPath")
			MemoWrite(@CRLF & "WinTrust path set to: " & $g_sWinTrustPath)
			LogWrite(1, "WinTrust path changed to: " & $g_sWinTrustPath)
			_TidyConfigSpacing($sINIPath)

		Case $idMsg = $idBtnUpdateHosts
			ToggleLog(0)
			UpdateHostsFile()
			GUICtrlSetState($idBtnCleanHosts, $GUI_ENABLE)

		Case $idMsg = $idBtnCleanHosts
			RemoveHostsEntries()

		Case $idMsg = $idBtnEditHosts
			EditHosts()
			GUICtrlSetState($idBtnCleanHosts, $GUI_ENABLE)

		Case $idMsg = $idBtnRestoreHosts
			RestoreHosts()
			
#cs === [SCHEDULE-HOSTS-REMOVED] ===
		Case $idMsg = $idBtnAutoUpdateHosts
			_ShowHostsAutoUpdateDialog()
#ce === [SCHEDULE-HOSTS-REMOVED] ===

#cs === [PROXY-REMOVED] event-loop cases - delete this #cs and its matching #ce to restore ===
		Case $idMsg = $idBtnProxySetup
			Local $bOk = _SetupMitmproxy()
			If $bOk Then
				GUICtrlSetState($idBtnProxyTargeting, $GUI_ENABLE)
				GUICtrlSetState($idBtnProxyStartStop, $GUI_ENABLE)
				GUICtrlSetState($idBtnProxyOpenLog, $GUI_ENABLE)
				GUICtrlSetState($idBtnProxyRemove, $GUI_ENABLE)
				MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Setup complete", _
						"mitmproxy installed and certificate trusted." & @CRLF & @CRLF & _
						"Next steps:" & @CRLF & _
						"  - Targeting (optional) to pick Global or specific apps" & @CRLF & _
						"  - Start / Stop Proxy to run it and route Windows traffic through it")
			Else
				Local $sErrMsg = "Setup failed."
				Switch @error
					Case 1
						$sErrMsg = "GenP must be running as Administrator."
					Case 2
						$sErrMsg = "Could not deploy mitmdump.exe." & @CRLF & _
								"Verify resources\mitmproxy\mitmdump.exe is in the build tree."
					Case 3
						$sErrMsg = "Could not deploy the rewrite script." & @CRLF & _
								"Verify resources\mitmproxy\mitmproxy_genuine_fullguard.py is in the build tree."
					Case 4
						$sErrMsg = "mitmdump didn't generate a certificate in 8 seconds." & @CRLF & _
								"This usually means the standalone binary couldn't unpack to %TEMP%." & @CRLF & _
								"Try running mitmdump.exe manually once, then click Setup again."
					Case 5
						$sErrMsg = "certutil failed to install the cert (exit " & @extended & ")." & @CRLF & _
								"Check that you're running GenP as Administrator."
				EndSwitch
				MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Setup failed", $sErrMsg)
			EndIf
			_RefreshProxyStatus()

		Case $idMsg = $idBtnProxyTargeting
			_ShowProxyTargetingDialog()

		Case $idMsg = $idBtnProxyStartStop
			If _IsMitmproxyRunning() Or _IsWindowsProxyOn() Then
				_DisableWindowsProxy()
				_StopMitmproxy()
				MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Proxy stopped", _
					"mitmdump stopped / Windows system proxy disabled.")
			Else
				Local $bOk = _StartMitmproxy()
				If $bOk Then
					_EnableWindowsProxy()
					Local $sPMode = IniRead($sINIPath, "Options", "ProxyMode", "Global")
					MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Proxy started", _
						"mitmdump is listening on " & $g_sMITM_PROXY & " and the Windows proxy is enabled." & @CRLF & @CRLF & _
						"Mode: " & (StringLower($sPMode) = "target" ? "Targeted apps" : "Global (recommended)") & ".")
				Else
					Local $sErrMsg2 = "Start failed."
					Switch @error
						Case 1
							$sErrMsg2 = "mitmproxy is not installed. Click Setup first."
						Case 2, 3
							$sErrMsg2 = "mitmdump didn't start cleanly." & @CRLF & _
								"Likely cause: the standalone binary couldn't unpack to %TEMP%." & @CRLF & _
								"Check Task Manager for old mitmdump processes."
						Case 4
							$sErrMsg2 = "All proxy ports 8080-8089 are busy on this machine." & @CRLF & _
								"Close whatever's holding them (other proxies, dev tools) and retry."
					EndSwitch
					MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Start failed", $sErrMsg2)
				EndIf
			EndIf
			_RefreshProxyStatus()

		Case $idMsg = $idBtnProxyOpenLog
			_OpenMitmproxyLogWindow()

		Case $idMsg = $idBtnProxyRemove
			If MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING), "Remove mitmproxy", _
					"This will:" & @CRLF & _
					"  - Stop mitmdump if running" & @CRLF & _
					"  - Disable Windows system proxy" & @CRLF & _
					"  - Uninstall the trusted certificate" & @CRLF & _
					"  - Delete " & $g_sMITM_DIR & @CRLF & @CRLF & _
					"Your %USERPROFILE%\.mitmproxy\ folder (cert source files)" & @CRLF & _
					"is preserved so a future Setup is faster. Continue?") = $IDYES Then
				If _RemoveMitmproxy() Then
					GUICtrlSetState($idBtnProxyTargeting, $GUI_DISABLE)
					GUICtrlSetState($idBtnProxyStartStop, $GUI_DISABLE)
					GUICtrlSetState($idBtnProxyOpenLog, $GUI_DISABLE)
					GUICtrlSetState($idBtnProxyRemove, $GUI_DISABLE)
					MsgBox(BitOR($MB_OK, $MB_ICONINFORMATION), "Removed", "mitmproxy uninstalled.")
				Else
					MsgBox(BitOR($MB_OK, $MB_ICONERROR), "Remove failed", _
						"Removal partially failed (@error=" & @error & "). Check the GenP log.")
				EndIf
			EndIf
			_RefreshProxyStatus()
#ce === [PROXY-REMOVED] end event-loop cases ===

		Case $idMsg = $idBtnCreateFW
			MsgBox(64, "Firewall Rules", "Adobe applications will be scanned and rules applied." & @CRLF & "Windows Firewall users will be prompted to select apps." & @CRLF & "Third-party users check the Log tab for paths to add.")
			ToggleLog(0)
			CreateFirewallRules()
			GUICtrlSetState($idBtnToggleFW, $GUI_ENABLE)
			GUICtrlSetState($idBtnRemoveFW, $GUI_ENABLE)

		Case $idMsg = $idBtnToggleFW
			ToggleLog(0)
			ShowToggleRulesGUI()

		Case $idMsg = $idBtnRemoveFW
			ToggleLog(0)
			RemoveFirewallRules()
			GUICtrlSetState($idBtnToggleFW, $GUI_DISABLE)
			GUICtrlSetState($idBtnRemoveFW, $GUI_DISABLE)

		Case $idMsg = $idBtnOpenWF
			OpenWF()

		Case $idMsg = $idBtnToggleRuntimeInstaller

		Case $idMsg = $idBtnToggleWinTrust
			ToggleLog(0)
			ManageWinTrust()

		Case $idMsg = $idBtnDevOverride
			ToggleLog(0)
			ManageDevOverride()

		Case $idMsg = $idBtnAGSInfo

		Case $idMsg = $idBtnFirewallInfo

		Case $idMsg = $idBtnHostsInfo

		Case $idMsg = $idBtnWintrustInfo

	EndSelect
WEnd


; ===== Application modules (this program's own functions) =====
; (included after the top-level code so global declarations are seen first;
;  AutoIt resolves all function definitions regardless of position.)
#include "src\Config.au3"
#include "src\Ui.au3"
#include "src\AdobeApps.au3"
#include "src\Patch.au3"
#include "src\Firewall.au3"
#include "src\Hosts.au3"
; [PROXY-REMOVED] #include "src\Proxy.au3"   ; entire proxy module excluded from the build
#include "src\DevOverride.au3"
#include "src\Util.au3"
