# LLM Clipboard Paste (Windows)

Transform copied text locally on Windows using Ollama, AutoHotkey v2, and PowerShell.

Copy text, press a hotkey, wait for the beep, then paste the transformed result.

## Features

- Fully local processing
- No API keys
- One-click installer
- Startup support
- Editable prompt files
- Deterministic privacify mode for common sensitive data
- Audible beep when output is ready
- Debug logging for troubleshooting

## Default Hotkeys

- **Ctrl + Alt + 1** -> Rewrite
- **Ctrl + Alt + 2** -> Summarize
- **Ctrl + Alt + 3** -> Bullet points
- **Ctrl + Alt + 4** -> Privacify

## Install

From PowerShell in the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -StartAtLogin
```

## What the installer does

- Installs Ollama
- Installs AutoHotkey v2
- Pulls the default model (`phi3`)
- Copies app files to `%USERPROFILE%\LLMClipboardPaste`
- Optionally registers startup at login
- Launches the hotkey app

## Usage

1. Copy text
2. Press one of the hotkeys
3. Wait for the beep
4. Paste

## Do users need to reinstall after restart?

No.

- Installation is one time
- If installed with `-StartAtLogin`, it auto-starts after sign-in
- Otherwise, users can manually start:

```text
C:\Users\<your-user>\LLMClipboardPaste\llm_clipboard.ahk
```

## Project Structure

```text
.
|-- install.ps1
|-- README.md
`-- src/
    |-- llm_clipboard.ahk
    |-- llm_clipboard_worker.ps1
    `-- prompts/
        |-- rewrite.txt
        |-- summarize.txt
        |-- bullets.txt
        `-- privacify.txt
```

## Configuration

The installer writes config to:

```text
%USERPROFILE%\LLMClipboardPaste\config.json
```

Example:

```json
{
  "model": "phi3",
  "ollama_url": "http://127.0.0.1:11434/api/generate",
  "trim_output": true,
  "privacify_use_model": false
}
```

`privacify_use_model` defaults to `false`, so Ctrl+Alt+4 redacts common sensitive values without sending the text to Ollama. Set it to `true` if you also want the local model to rewrite the already-redacted text.

## Prompt Customization

Edit the files in:

```text
%USERPROFILE%\LLMClipboardPaste\prompts\
```

## Debug Log

Logs are written to:

```text
%USERPROFILE%\LLMClipboardPaste\llm_clipboard_debug.log
```

Useful when:
- no beep
- no output
- delays
- model timeout issues

## Notes

- Larger inputs may take longer
- You can switch to a different Ollama model by editing `config.json`
- The installer defaults to `phi3`

## License

Add your preferred license here.
