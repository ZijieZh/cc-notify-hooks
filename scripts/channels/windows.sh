#!/usr/bin/env bash
# Windows 原生通知（PowerShell + System.Windows.Forms.NotifyIcon 气泡提示）
# 支持 Windows 10 / Windows 11，零依赖

send_windows() {
    local title="$1" body="$2" config="$3"
    local sound

    sound=$(echo "$config" | jq -r '.sound // empty')

    # 转义单引号（PowerShell 中双写单引号表示转义）
    local safe_title safe_body
    safe_title=$(printf '%s' "$title" | sed "s/'/''/g")
    safe_body=$(printf '%s' "$body" | sed "s/'/''/g")
    # 换行符替换为空格，避免破坏命令行
    safe_body=$(printf '%s' "$safe_body" | tr '\n' ' ')

    # 构建 PowerShell 命令
    local ps_cmd
    ps_cmd="Add-Type -AssemblyName System.Windows.Forms; "
    ps_cmd="${ps_cmd}Add-Type -AssemblyName System.Drawing; "
    ps_cmd="${ps_cmd}\$notify = New-Object System.Windows.Forms.NotifyIcon; "
    ps_cmd="${ps_cmd}\$notify.Icon = [System.Drawing.SystemIcons]::Information; "
    ps_cmd="${ps_cmd}\$notify.BalloonTipTitle = '${safe_title}'; "
    ps_cmd="${ps_cmd}\$notify.BalloonTipText = '${safe_body}'; "
    ps_cmd="${ps_cmd}\$notify.Visible = \$true; "

    if [ -n "$sound" ]; then
        ps_cmd="${ps_cmd}[System.Media.SystemSounds]::${sound}.Play(); "
    fi

    ps_cmd="${ps_cmd}\$notify.ShowBalloonTip(5000); "
    ps_cmd="${ps_cmd}Start-Sleep -Milliseconds 5500; "
    ps_cmd="${ps_cmd}\$notify.Dispose()"

    powershell.exe -NoProfile -NonInteractive -Command "$ps_cmd" >/dev/null 2>&1 || true
}
