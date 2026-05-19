#!/bin/bash
# toggle-openclaw.sh - 切换 OpenClaw 服务开机启动/后台运行
# 支持: Main Gateway, Rescue Gateway, Node Host

set -euo pipefail

HOME_DIR="$HOME"
GUI_UID="gui/$(id -u)"

# 服务定义: 显示名称|plist 标签|端口(可为空)|进程名(用于 kill)
SERVICES=(
  "Main Gateway|ai.openclaw.gateway|18789|openclaw-gateway"
  "Rescue Gateway|ai.openclaw.rescue-gateway|19001|openclaw-gateway"
  "Node Host|ai.openclaw.node||openclaw-node"
)

# ============================================================
# 工具函数
# ============================================================

get_service_status() {
  local label="$1" port="$2" name="$3" proc_name="$4"

  local launchd_info
  launchd_info=$(launchctl print "$GUI_UID/$label" 2>/dev/null || true)

  local loaded=false running=false disabled=false

  if echo "$launchd_info" | grep -q "state = running"; then
    loaded=true; running=true
  elif echo "$launchd_info" | grep -q "state = waiting"; then
    loaded=true
  fi

  if echo "$launchd_info" | grep -q "disabled = true"; then
    disabled=true
  fi

  # 额外检查端口监听或进程存在
  local port_active=false
  if [ -n "$port" ]; then
    if lsof -i :"$port" -P -n 2>/dev/null | grep -q LISTEN; then
      port_active=true
    fi
  fi
  local proc_active=false
  if [ -n "$proc_name" ]; then
    if pgrep -x "$proc_name" >/dev/null 2>&1; then
      proc_active=true
    fi
  fi

  local suffix=""
  [ -n "$port" ] && suffix=" (端口 $port)"

  if $running; then
    echo "[运行中] $name$suffix"
  elif $loaded; then
    echo "[已加载但未运行] $name$suffix - KeepAlive 等待中"
  elif $port_active || $proc_active; then
    echo "[进程活跃但未受 launchd 管理] $name$suffix"
  else
    echo "[已停止] $name$suffix"
  fi

  if $disabled; then
    echo "         → 开机启动已禁用"
  fi
}

enable_service() {
  local label="$1" plist_file="$2" port="$3" name="$4" proc_name="$5"

  echo "▶ 开启 $name..."
  launchctl enable "$GUI_UID/$label" 2>/dev/null || true

  if [ -f "$plist_file" ]; then
    launchctl bootstrap "$GUI_UID" "$plist_file" 2>/dev/null || {
      launchctl bootout "$GUI_UID" "$plist_file" 2>/dev/null || true
      launchctl bootstrap "$GUI_UID" "$plist_file" 2>/dev/null || true
    }
    echo "  ✓ $name 已启动，开机启动已设置"
  else
    echo "  ✗ 错误: $plist_file 不存在"
    return 1
  fi
}

disable_service() {
  local label="$1" plist_file="$2" port="$3" name="$4" proc_name="$5"

  echo "⏹ 关闭 $name..."

  # 卸载 launchd 任务
  if [ -f "$plist_file" ]; then
    launchctl bootout "$GUI_UID" "$plist_file" 2>/dev/null || true
  fi
  launchctl disable "$GUI_UID/$label" 2>/dev/null || true

  # Kill 进程 — 优先按端口，否则按进程名
  local killed=false
  if [ -n "$port" ]; then
    local pids
    pids=$(lsof -ti :"$port" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      kill "$pids" 2>/dev/null || true
      sleep 1
      local remaining
      remaining=$(lsof -ti :"$port" 2>/dev/null || true)
      if [ -n "$remaining" ]; then
        kill -9 "$remaining" 2>/dev/null || true
      fi
      killed=true
    fi
  fi
  if [ -n "$proc_name" ]; then
    local pids
    pids=$(pgrep -x "$proc_name" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      kill "$pids" 2>/dev/null || true
      sleep 1
      local remaining
      remaining=$(pgrep -x "$proc_name" 2>/dev/null || true)
      if [ -n "$remaining" ]; then
        kill -9 "$remaining" 2>/dev/null || true
      fi
      killed=true
    fi
  fi

  # 验证
  sleep 0.5
  local still_alive=false
  if [ -n "$port" ] && lsof -i :"$port" -P -n 2>/dev/null | grep -q LISTEN; then
    still_alive=true
  fi
  if [ -n "$proc_name" ] && pgrep -x "$proc_name" >/dev/null 2>&1; then
    still_alive=true
  fi

  if $still_alive; then
    echo "  ⚠ $name 仍在运行，可能需要手动处理"
  else
    local suffix=""
    [ -n "$port" ] && suffix=" (端口 $port)"
    echo "  ✓ $name$suffix 已停止，开机启动已取消"
  fi
}

# ============================================================
# 主菜单
# ============================================================

show_menu() {
  echo ""
  echo "=========================================="
  echo "  OpenClaw 服务切换工具"
  echo "=========================================="
  echo ""
  echo "  当前状态:"
  echo "  ────────────────────────────────────────"
  for i in "${!SERVICES[@]}"; do
    IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
    get_service_status "$label" "$port" "$name" "$proc"
    echo ""
  done
  echo "  ────────────────────────────────────────"
  echo ""
  echo "  请选择操作:"
  echo ""
  echo "    1) 开启全部"
  echo "    2) 关闭全部"
  local refresh_idx=$(( ${#SERVICES[@]} * 2 + 3 ))
  local exit_idx=$(( refresh_idx + 1 ))

  for i in "${!SERVICES[@]}"; do
    IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
    local suffix=""
    [ -n "$port" ] && suffix=" ($port)"
    local enable_idx=$((i * 2 + 3))
    local disable_idx=$((i * 2 + 4))
    echo "    $enable_idx) 仅开启 $name$suffix"
    echo "    $disable_idx) 仅关闭 $name$suffix"
  done
  echo "    $refresh_idx) 刷新状态"
  echo "    $exit_idx) 退出"
  echo ""
  read -r -p "  请输入选项 (1-$exit_idx): " choice

  # 开启全部
  if [ "$choice" = "1" ]; then
    echo ""
    for i in "${!SERVICES[@]}"; do
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      plist_file="$HOME_DIR/Library/LaunchAgents/$label.plist"
      enable_service "$label" "$plist_file" "$port" "$name" "$proc"
      echo ""
    done
    echo "所有服务已开启 ✓"
    read -r -p "按回车返回菜单..."
    show_menu
    return
  fi

  # 关闭全部
  if [ "$choice" = "2" ]; then
    echo ""
    for i in "${!SERVICES[@]}"; do
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      plist_file="$HOME_DIR/Library/LaunchAgents/$label.plist"
      disable_service "$label" "$plist_file" "$port" "$name" "$proc"
      echo ""
    done
    echo "所有服务已关闭 ✓"
    read -r -p "按回车返回菜单..."
    show_menu
    return
  fi

  # 单个服务操作
  for i in "${!SERVICES[@]}"; do
    local enable_idx=$((i * 2 + 3))
    local disable_idx=$((i * 2 + 4))
    if [ "$choice" = "$enable_idx" ]; then
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      plist_file="$HOME_DIR/Library/LaunchAgents/$label.plist"
      enable_service "$label" "$plist_file" "$port" "$name" "$proc"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      return
    elif [ "$choice" = "$disable_idx" ]; then
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      plist_file="$HOME_DIR/Library/LaunchAgents/$label.plist"
      disable_service "$label" "$plist_file" "$port" "$name" "$proc"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      return
    fi
  done

  # 刷新或退出
  if [ "$choice" = "$refresh_idx" ]; then
    show_menu
  elif [ "$choice" = "$exit_idx" ]; then
    echo ""; echo "退出."; exit 0
  else
    echo ""; echo "无效选项，请重新选择"; sleep 1
    show_menu
  fi
}

# ============================================================
# 入口
# ============================================================

case "${1:-}" in
  on|enable|start)
    for i in "${!SERVICES[@]}"; do
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      plist_file="$HOME_DIR/Library/LaunchAgents/$label.plist"
      enable_service "$label" "$plist_file" "$port" "$name" "$proc"
      echo ""
    done
    echo "所有服务已开启 ✓"
    exit 0
    ;;
  off|disable|stop)
    for i in "${!SERVICES[@]}"; do
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      plist_file="$HOME_DIR/Library/LaunchAgents/$label.plist"
      disable_service "$label" "$plist_file" "$port" "$name" "$proc"
      echo ""
    done
    echo "所有服务已关闭 ✓"
    exit 0
    ;;
  status)
    for i in "${!SERVICES[@]}"; do
      IFS='|' read -r name label port proc <<< "${SERVICES[$i]}"
      get_service_status "$label" "$port" "$name" "$proc"
    done
    exit 0
    ;;
  ""|menu)
    show_menu
    ;;
  *)
    echo "用法: $0 {on|off|status|menu}"
    echo "  或直接运行进入交互菜单"
    exit 1
    ;;
esac
