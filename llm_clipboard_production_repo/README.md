# LLM Clipboard Paste (Windows)

Transform copied text locally on Windows using Ollama, AutoHotkey v2, and PowerShell.

Copy text, press a hotkey, wait for the beep, then paste the transformed result.

## Features

- Fully local processing
- No API keys
- One-click installer
- Bundled portable Node.js runtime for the manager UI
- Startup support
- Editable prompt files
- Local manager UI for model, hotkey, prompt, brand, example, test, and log settings
- Model download and selection from the UI
- Deterministic + optional local-model privacify mode for sensitive data
- Editable Privacify examples with 200 seeded examples
- Audible beep when output is ready
- Debug logging for troubleshooting

## Default Hotkeys

- **Ctrl + Alt + 1** -> Rewrite
- **Ctrl + Alt + 2** -> Summarize
- **Ctrl + Alt + 3** -> Bullet points
- **Ctrl + Alt + 4** -> Privacify

## Install

The end-user installation guide is available in [docs/user-guide](docs/user-guide/).

### Download and install

1. Open [github.com/pruthvishp/privacify](https://github.com/pruthvishp/privacify).
2. Click **Code**, then **Download ZIP**.
3. Extract the ZIP and open the `llm_clipboard_production_repo` folder.
4. Double-click `Install Privacify.cmd`, review the setup summary, and type `Y` to agree. Type `N` to cancel before any changes are made. Leave the installer window open until it reports completion. The first install downloads the required local runtimes and model, so it can take several minutes.

After installation, use the **Privacify Manager** desktop shortcut for settings. Copy sensitive text, press **Ctrl + Alt + 4**, wait for the tray notification and ready beep, then paste the redacted result.

### PowerShell alternative

From the `llm_clipboard_production_repo` folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -StartAtLogin
```

The installer defaults to `qwen2.5:3b` and pulls it with Ollama. You can choose another model:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Model "gemma2:2b"
```

For privacify-only installs, you can skip Ollama setup:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipOllama
```

The installer also downloads a portable Node.js runtime into the app folder so users do not need to install Node manually. To install without the UI runtime:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipManagerUi
```

## What the installer does

- Installs Ollama
- Installs AutoHotkey v2
- Downloads bundled portable Node.js for the manager UI
- Pulls the default model (`qwen2.5:3b`)
- Copies app files to `%USERPROFILE%\LLMClipboardPaste`
- Copies the manager UI and seeded Privacify examples
- Creates a desktop shortcut named **Privacify Manager**
- Opens the manager UI at `http://127.0.0.1:8787/`
- Optionally registers startup at login
- Launches the hotkey app

## Usage

1. Copy text
2. Press one of the hotkeys
3. Wait for the tray notification and beep that confirm the result is ready
4. Paste

For Privacify:

1. Copy text that may contain private data
2. Press **Ctrl + Alt + 4**
3. Wait for the "Ready to paste" tray notification
4. Paste the redacted text

## Manager UI

The installer copies the manager UI to:

```text
%USERPROFILE%\LLMClipboardPaste\privacify_manager.js
```

The installer starts the UI automatically and creates a desktop shortcut named **Privacify Manager**.

You can also start it manually with:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\LLMClipboardPaste\Start Privacify Manager.ps1"
```

Then open:

```text
http://127.0.0.1:8787/
```

The UI includes:

- **Overview**: select an installed or recommended local Ollama model, pull a different compatible model, set the Ollama URL, trim output, and control the Privacify model toggle
- **Image & Brand**: app name, accent color, and tray/brand image path
- **Hotkeys**: edit profile hotkeys and restart AutoHotkey
- **Prompts**: edit rewrite, summarize, bullets, and Privacify prompts
- **Examples**: manage Privacify input/output examples
- **Test**: run a Privacify test without using the hotkey
- **Logs**: view recent debug log entries

### Test and improve results

Use the **Test** tab to paste representative text, run Privacify, and compare the output with the result you expect. Start with synthetic data when possible.

When a result needs a different redaction style, open **Examples**, add an input/output pair that shows the desired result, and select **Save examples**. Then rerun the same case in **Test**. These examples are injected as runtime prompt context for the local model; they do not train or fine-tune the model. Add examples gradually and keep the most relevant ones enabled, because more context can increase latency.

## Models

Privacify uses Ollama. The default install model is:

```text
qwen2.5:3b
```

The manager UI shows installed models and recommended models. To add a model:

1. Open the **Overview** tab
2. Type or choose a model name, such as `gemma2:2b`
3. Click **Pull selected model**
4. Save settings

Recommended small local models:

```text
qwen2.5:3b
gemma2:2b
llama3.2:3b
phi3
```

You can still edit `%USERPROFILE%\LLMClipboardPaste\config.json` directly if needed.

## Privacify Examples

Privacify ships with 200 seeded examples in:

```text
%USERPROFILE%\LLMClipboardPaste\privacify_examples.json
```

Examples are not training data and do not fine-tune the model. They are runtime context. On each Privacify run, the worker reads the examples file and injects enabled examples into the prompt before the clipboard text.

The **Examples** tab lets you:

- enable or disable example injection
- set how many enabled examples are used per run
- edit the examples JSON directly
- add new input/output example pairs

Example:

```json
{
  "enabled": true,
  "category": "finance",
  "input": "He is paid 12342342$ per month.",
  "output": "He is paid [AMOUNT] per month."
}
```

The default config stores 200 examples and injects the first 60 enabled examples per run. More examples give the local model more style guidance but increase prompt size and latency.

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
    |-- privacify_examples.json
    |-- privacify_manager.js
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
  "model": "qwen2.5:3b",
  "ollama_url": "http://127.0.0.1:11434/api/generate",
  "trim_output": true,
  "privacify_use_model": true,
  "privacify_examples_enabled": true,
  "privacify_examples_limit": 60,
  "privacify_examples_file": "%USERPROFILE%\\LLMClipboardPaste\\privacify_examples.json"
}
```

`privacify_use_model` controls whether Privacify calls the local Ollama model after deterministic redaction. When enabled, the flow is:

```text
clipboard text
-> deterministic redaction
-> local model with enabled examples
-> deterministic cleanup
-> clipboard result
```

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
- More examples may improve style matching but can increase latency
- On the current local setup, model-assisted redaction can take about 45-60 seconds, depending on the selected model, machine resources, input size, and number of enabled examples
- You can switch to a different Ollama model in the UI or by editing `config.json`
- The installer defaults to `qwen2.5:3b`

## License

Add your preferred license here.
