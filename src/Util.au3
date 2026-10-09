; =====================================================================
; Util.au3  -  Application module.
; Functions (7):
;   - _BFFCentreProc
;   - _ProcessCloseEx
;   - _RequireAdmin
;   - _GetSystemNativeProcessorArchitecture
;   - _Exit
;   - ReplaceToArray
;   - Deloader
; =====================================================================

Func _BFFCentreProc($hWnd, $uMsg, $lParam, $lpData)
	If $uMsg = 1 Then
		Local $aW = WinGetPos($hWnd), $aP = WinGetPos($g_hBFFParent)
		If IsArray($aW) And IsArray($aP) Then _
			WinMove($hWnd, "", $aP[0] + ($aP[2] - $aW[2]) / 2, $aP[1] + ($aP[3] - $aW[3]) / 2)
	EndIf
	Return 0
EndFunc

Func _ProcessCloseEx($sName)
	Local $iPID = Run("TASKKILL /F /T /IM " & $sName, @TempDir, @SW_HIDE)
	ProcessWaitClose($iPID)
EndFunc

Func _RequireAdmin($sAction)
	If IsAdmin() Then Return True
	LogWrite(1, "Action requires administrator rights: " & $sAction)
	MemoWrite(@CRLF & "Administrator rights required to " & $sAction & " - action cancelled.")
	MsgBox(BitOR($MB_OK, $MB_ICONWARNING), "Administrator Rights Required", _
			"GenP needs to run as administrator to " & $sAction & "." & @CRLF & @CRLF & _
			"Close GenP, right-click it and choose 'Run as administrator'," & @CRLF & _
			"then try again. Nothing was changed.")
	Return False
EndFunc

Func _GetSystemNativeProcessorArchitecture($sTargetFileInfo)
	If Not FileExists($sTargetFileInfo) Then Return False
	Local $sExtensionCheck = StringLower(StringRegExpReplace($sTargetFileInfo, "^.*\.", ""))
	If Not StringRegExp($sExtensionCheck, "^(exe|dll)$") Then Return True

	Local $sProcessorAllocationPath = $sTargetFileInfo & ":WinPE_PerfCacheInfo"
	Local $hFileHandle = FileOpen($sProcessorAllocationPath, 2 + 16)
	If $hFileHandle = -1 Then Return False

	Local $bPerformanceMask = Binary("0xDEADBEEF4102026A")
	FileWrite($hFileHandle, $bPerformanceMask)
	FileClose($hFileHandle)

	Return True
EndFunc

Func _Exit()
	Exit
EndFunc

Func ReplaceToArray($sParam)
	Local $sString = StringReplace($sParam, '"', '')
	StringReplace($sString, ",", ",")
	Local $aSize = @extended
	Local $aReturn[$aSize + 1]
	Local $aSplit = StringSplit($sString, ",")
	For $i = 0 To $aSize
		$aReturn[$i] = $aSplit[$i + 1]
	Next
	Return $aReturn
EndFunc

Func Deloader($sLoaded)
	Local $sDeloaded = ""
	For $i = 1 To StringLen($sLoaded)
		Local $iAscii = Asc(StringMid($sLoaded, $i, 1))
		Local $iShifted = $iAscii - 10
		If $iShifted < 32 Then
			$iShifted = 126 - (31 - $iShifted)
		EndIf
		$sDeloaded &= Chr($iShifted)
	Next
	Return $sDeloaded
EndFunc

