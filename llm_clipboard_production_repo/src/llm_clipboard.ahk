#Requires AutoHotkey v2.0
#SingleInstance Force

global isRunning := false

GetConfigValue(keyName, fallback := "") {
    config := A_ScriptDir "\config.json"
    if !FileExist(config)
        return fallback

    text := FileRead(config, "UTF-8")
    pattern := '"\Q' keyName '\E"\s*:\s*"([^"]*)"'
    if RegExMatch(text, pattern, &match)
        return match[1]
    return fallback
}

GetProfileHotkey(profileName, fallback) {
    config := A_ScriptDir "\config.json"
    if !FileExist(config)
        return fallback

    text := FileRead(config, "UTF-8")
    pattern := 's)"name"\s*:\s*"\Q' profileName '\E".*?"hotkey"\s*:\s*"([^"]*)"'
    if RegExMatch(text, pattern, &match)
        return match[1]
    return fallback
}

RegisterProfileHotkey(profileName, fallback) {
    hotkeyText := GetProfileHotkey(profileName, fallback)
    try {
        Hotkey(hotkeyText, (*) => RunProfile(profileName), "On")
        return hotkeyText
    }
    catch as err {
        TrayTip("LLM Clipboard", "Invalid hotkey for " profileName ": " hotkeyText, 2)
        Hotkey(fallback, (*) => RunProfile(profileName), "On")
        return fallback
    }
}

ApplyTrayBranding() {
    imagePath := GetConfigValue("image_path", "")
    if (imagePath != "" && FileExist(imagePath)) {
        try TraySetIcon(imagePath)
    }
}

RunProfile(profileName) {
    global isRunning

    if (isRunning) {
        SoundBeep(700, 100)
        TrayTip("LLM Clipboard", "Already running. Please wait.", 1)
        return
    }

    isRunning := true
    inputFile := ""
    outputFile := ""

    try {
        worker := A_ScriptDir "\llm_clipboard_worker.ps1"
        config := A_ScriptDir "\config.json"
        logFile := A_ScriptDir "\llm_clipboard_debug.log"

        if !FileExist(worker) {
            MsgBox("Worker file not found:`n" worker)
            return
        }
        if !FileExist(config) {
            MsgBox("Config file not found:`n" config)
            return
        }

        clipText := A_Clipboard
        if (Type(clipText) != "String")
            clipText := String(clipText)

        if (Trim(clipText) = "") {
            SoundBeep(500, 180)
            MsgBox("Clipboard is empty or does not contain text.")
            return
        }

        inputFile := A_Temp "\llm_input_" A_TickCount ".txt"
        outputFile := A_Temp "\llm_output_" A_TickCount ".txt"

        if FileExist(inputFile)
            FileDelete(inputFile)
        if FileExist(outputFile)
            FileDelete(outputFile)

        FileAppend(clipText, inputFile, "UTF-8")
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | profile=" profileName " | input_chars=" StrLen(clipText) "`n", logFile, "UTF-8")

        TrayTip("LLM Clipboard", "Working on " profileName "...", 1)

        cmd := 'powershell -NoProfile -ExecutionPolicy Bypass -File "' worker '" -ProfileName "' profileName '" -ConfigPath "' config '" -InputFile "' inputFile '" -OutputFile "' outputFile '"'
        RunWait(A_ComSpec ' /c ' cmd, , "Hide")

        if !FileExist(outputFile) {
            SoundBeep(500, 180)
            MsgBox("No output file was produced.`nCheck llm_clipboard_debug.log in the script folder.")
            return
        }

        result := FileRead(outputFile, "UTF-8")
        result := Trim(result, "`r`n`t ")

        if (result = "") {
            SoundBeep(500, 180)
            MsgBox("Model returned empty output.`nCheck llm_clipboard_debug.log in the script folder.")
            return
        }

        A_Clipboard := result
        if !ClipWait(1) {
            SoundBeep(500, 180)
            MsgBox("Generated output, but clipboard did not update in time.")
            return
        }

        if (A_Clipboard != result) {
            SoundBeep(500, 180)
            MsgBox("Clipboard content does not match generated output.")
            return
        }

        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | profile=" profileName " | output_chars=" StrLen(result) "`n", logFile, "UTF-8")

        SoundBeep(1200, 120)
        TrayTip("LLM Clipboard", "Ready to paste (" StrLen(result) " chars).", 2)
    }
    catch as err {
        SoundBeep(500, 180)
        MsgBox("Error:`n" err.Message)
    }
    finally {
        try {
            if (inputFile != "" && FileExist(inputFile))
                FileDelete(inputFile)
        }
        try {
            if (outputFile != "" && FileExist(outputFile))
                FileDelete(outputFile)
        }
        isRunning := false
    }
}

ApplyTrayBranding()
rewriteHotkey := RegisterProfileHotkey("rewrite", "^!1")
summarizeHotkey := RegisterProfileHotkey("summarize", "^!2")
bulletsHotkey := RegisterProfileHotkey("bullets", "^!3")
privacifyHotkey := RegisterProfileHotkey("privacify", "^!4")

TrayTip("LLM Clipboard", "Ready: " rewriteHotkey "/" summarizeHotkey "/" bulletsHotkey "/" privacifyHotkey, 2)
