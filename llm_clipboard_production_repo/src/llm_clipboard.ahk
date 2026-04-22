#Requires AutoHotkey v2.0
#SingleInstance Force

global isRunning := false

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

^!1::{
    RunProfile("rewrite")
}

^!2::{
    RunProfile("summarize")
}

^!3::{
    RunProfile("bullets")
}

^!4::{
    RunProfile("privacify")
}

TrayTip("LLM Clipboard", "Ready: Ctrl+Alt+1/2/3/4", 2)
