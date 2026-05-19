#!/bin/bash
# toggle-openclaw.sh - 切换 OpenClaw Gateway 开机启动/后台运行
# 使用方式: 直接运行，在菜单中选择功能

set -euo pipefail

HOME_DIR="$HOME"
MAIN_PLIST_LABEL="ai.openclaw.gateway"
MAIN_PLIST_FILE="$HOME_DIR/Library/LaunchAgents/$MAIN_PLIST_LABEL.plist"
MAIN_PORT="18789"

RESCUE_PLIST_LABEL="ai.openclaw.rescue-gateway"
RESCUE_PLIST_FILE="$HOME_DIR/Library/LaunchAgents/$RESCUE_PLIST_LABEL.plist"
RESCUE_PORT="19001"

GUI_UID="gui/$(id -u)"

# ============================================================
# 工具函数
# ============================================================

get_service_status() {
  local label="$1"
  local port="$2"
  local name="$3"

  # 检查 launchd 状态
  local launchd_info
  launchd_info=$(launchctl print "$GUI_UID/$label" 2>/dev/null || true)

  local loaded=false
  local running=false
  local disabled=false

  if echo "$launchd_info" | grep -q "state = running"; then
    loaded=true
    running=true
  elif echo "$launchd_info" | grep -q "state = waiting"; then
    loaded=true
  fi

  if echo "$launchd_info" | grep -q "disabled = true"; then
    disabled=true
  fi

  # 额外检查进程是否在监听端口
  local port_active=false
  if lsof -i :"$port" -P -n 2>/dev/null | grep -q LISTEN; then
    port_active=true
  fi

  # 输出状态
  if $running; then
    echo "[运行中] $name (端口 $port)"
  elif $loaded; then
    echo "[已加载但未运行] $name (端口 $port) - KeepAlive 等待中"
  elif $port_active; then
    echo "[端口活跃但未受 launchd 管理] $name (端口 $port)"
  else
    echo "[已停止] $name (端口 $port)"
  fi

  if $disabled; then
    echo "         → 开机启动已禁用"
  fi
}

enable_service() {
  local label="$1"
  local plist_file="$2"
  local port="$3"
  local name="$4"

  echo "▶ 开启 $name..."

  # 启用（解除 disable 状态）
  launchctl enable "$GUI_UID/$label" 2>/dev/null || true

  # 加载 plist
  if [ -f "$plist_file" ]; then
    launchctl bootstrap "$GUI_UID" "$plist_file" 2>/dev/null || {
      # 可能已经 bootstrap 过，先 bootout 再重试
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
  local label="$1"
  local plist_file="$2"
  local port="$3"
  local name="$4"

  echo "⏹ 关闭 $name..."

  # 卸载 launchd 任务（停止进程 + 取消 launchd 管理）
  if [ -f "$plist_file" ]; then
    launchctl bootout "$GUI_UID" "$plist_file" 2>/dev/null || true
  fi

  # 禁用（阻止下次登录时自动加载）
  launchctl disable "$GUI_UID/$label" 2>/dev/null || true

  # 杀死仍在该端口监听的进程（可能由其他方式启动）
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    kill "$pids" 2>/dev/null || true
    sleep 1
    # 强制杀
    local remaining
    remaining=$(lsof -ti :"$port" 2>/dev/null || true)
    if [ -n "$remaining" ]; then
      kill -9 "$remaining" 2>/dev/null || true
    fi
  fi

  # 验证
  sleep 0.5
  if lsof -i :"$port" -P -n 2>/dev/null | grep -q LISTEN; then
    echo "  ⚠ $name (端口 $port) 仍在运行，可能需要手动处理"
  else
    echo "  ✓ $name 已停止，开机启动已取消"
  fi
}

# ============================================================
# 主菜单
# ============================================================

show_menu() {
  echo ""
  echo "=========================================="
  echo "  OpenClaw Gateway 服务切换工具"
  echo "=========================================="
  echo ""
  echo "  当前状态:"
  echo "  ────────────────────────────────────────"
  get_service_status "$MAIN_PLIST_LABEL" "$MAIN_PORT" "Main Gateway"
  echo ""
  get_service_status "$RESCUE_PLIST_LABEL" "$RESCUE_PORT" "Rescue Gateway"
  echo "  ────────────────────────────────────────"
  echo ""
  echo "  请选择操作:"
  echo ""
  echo "    1) 开启全部 (开机启动 + 启动服务)"
  echo "    2) 关闭全部 (取消开机启动 + 停止服务)"
  echo "    3) 仅开启 Main Gateway (18789)"
  echo "    4) 仅关闭 Main Gateway (18789)"
  echo "    5) 仅开启 Rescue Gateway (19001)"
  echo "    6) 仅关闭 Rescue Gateway (19001)"
  echo "    7) 刷新状态"
  echo "    8) 退出"
  echo ""
  read -r -p "  请输入选项 (1-8): " choice

  case "$choice" in
    1)
      echo ""
      enable_service "$MAIN_PLIST_LABEL" "$MAIN_PLIST_FILE" "$MAIN_PORT" "Main Gateway"
      echo ""
      enable_service "$RESCUE_PLIST_LABEL" "$RESCUE_PLIST_FILE" "$RESCUE_PORT" "Rescue Gateway"
      echo ""
      echo "所有服务已开启 ✓"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      ;;
    2)
      echo ""
      disable_service "$MAIN_PLIST_LABEL" "$MAIN_PLIST_FILE" "$MAIN_PORT" "Main Gateway"
      echo ""
      disable_service "$RESCUE_PLIST_LABEL" "$RESCUE_PLIST_FILE" "$RESCUE_PORT" "Rescue Gateway"
      echo ""
      echo "所有服务已关闭 ✓"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      ;;
    3)
      echo ""
      enable_service "$MAIN_PLIST_LABEL" "$MAIN_PLIST_FILE" "$MAIN_PORT" "Main Gateway"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      ;;
    4)
      echo ""
      disable_service "$MAIN_PLIST_LABEL" "$MAIN_PLIST_FILE" "$MAIN_PORT" "Main Gateway"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      ;;
    5)
      echo ""
      enable_service "$RESCUE_PLIST_LABEL" "$RESCUE_PLIST_FILE" "$RESCUE_PORT" "Rescue Gateway"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      ;;
    6)
      echo ""
      disable_service "$RESCUE_PLIST_LABEL" "$RESCUE_PLIST_FILE" "$RESCUE_PORT" "Rescue Gateway"
      echo ""
      read -r -p "按回车返回菜单..."
      show_menu
      ;;
    7)
      show_menu
      ;;
    8)
      echo ""
      echo "退出."
      exit 0
      ;;
    *)
      echo ""
      echo "无效选项，请重新选择"
      sleep 1
      show_menu
      ;;
  esac
}

# ============================================================
# 入口 - 也支持命令行参数
# ============================================================

case "${1:-}" in
  on|enable|start)
    enable_service "$MAIN_PLIST_LABEL" "$MAIN_PLIST_FILE" "$MAIN_PORT" "Main Gateway"
    enable_service "$RESCUE_PLIST_LABEL" "$RESCUE_PLIST_FILE" "$RESCUE_PORT" "Rescue Gateway"
    echo ""
    echo "所有服务已开启 ✓"
    exit 0
    ;;
  off|disable|stop)
    disable_service "$MAIN_PLIST_LABEL" "$MAIN_PLIST_FILE" "$MAIN_PORT" "Main Gateway"
    disable_service "$RESCUE_PLIST_LABEL" "$RESCUE_PLIST_FILE" "$RESCUE_PORT" "Rescue Gateway"
    echo ""
    echo "所有服务已关闭 ✓"
    exit 0
    ;;
  status)
    get_service_status "$MAIN_PLIST_LABEL" "$MAIN_PORT" "Main Gateway"
    get_service_status "$RESCUE_PLIST_LABEL" "$RESCUE_PORT" "Rescue Gateway"
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
