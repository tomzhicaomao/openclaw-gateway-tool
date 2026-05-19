#!/usr/bin/env bats
# TDD 测试: toggle-openclaw.sh
# 通过 mock 系统命令测试脚本行为

setup() {
  export TEST_TMPDIR=$(mktemp -d)
  export MOCK_BINDIR="$TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_BINDIR"

  # Mock launchctl
  cat > "$MOCK_BINDIR/launchctl" <<'MOCK'
#!/bin/bash
echo "launchctl $@" >> "$TEST_TMPDIR/launchctl.log"
if [ "$1" = "print" ]; then
  echo "state = running"
  echo "disabled = false"
fi
exit 0
MOCK
  chmod +x "$MOCK_BINDIR/launchctl"

  # Mock lsof - simulate port in use
  cat > "$MOCK_BINDIR/lsof" <<'MOCK'
#!/bin/bash
# lsof -ti :PORT  (used in disable_service)
if [ "$1" = "-ti" ]; then
  echo "12345"
  exit 0
fi
# lsof -i :PORT -P -n (used in get_service_status)
echo "node 12345 thomas 15u IPv4 0xabc 0t0 TCP 127.0.0.1 (LISTEN)"
exit 0
MOCK
  chmod +x "$MOCK_BINDIR/lsof"

  export ORIGINAL_PATH="$PATH"
  export PATH="$MOCK_BINDIR:$PATH"
  export SCRIPT="$HOME/bin/toggle-openclaw.sh"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  rm -rf "$TEST_TMPDIR"
}

# ============================================================
# status 命令
# ============================================================

@test "status: 服务运行时显示服务名称和端口" {
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Main Gateway"
  echo "$output" | grep -q "Rescue Gateway"
}

@test "status: 不输出错误信息" {
  run "$SCRIPT" status
  ! echo "$output" | grep -qi "错误\|error"
}

@test "status: 进程不在运行时显示已停止" {
  # lsof returns nothing
  cat > "$MOCK_BINDIR/lsof" <<'MOCK'
#!/bin/bash
exit 1
MOCK
  # launchctl says not running
  cat > "$MOCK_BINDIR/launchctl" <<'MOCK'
#!/bin/bash
echo "launchctl $@" >> "$TEST_TMPDIR/launchctl.log"
echo "state = not running"
echo "disabled = true"
exit 1
MOCK

  run "$SCRIPT" status
  echo "$output" | grep -q "已停止"
}

# ============================================================
# on 命令 - 开启服务
# ============================================================

@test "on: 退出码为 0" {
  run "$SCRIPT" on
  [ "$status" -eq 0 ]
}

@test "on: 调用 launchctl enable 和 bootstrap" {
  run "$SCRIPT" on
  grep -q "enable" "$TEST_TMPDIR/launchctl.log"
  grep -q "bootstrap" "$TEST_TMPDIR/launchctl.log"
}

# ============================================================
# off 命令 - 关闭服务
# ============================================================

@test "off: 退出码为 0" {
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
}

@test "off: 调用 launchctl bootout 和 disable" {
  # Use stateful mock: after first lsof call, kill silently fails (bash builtin)
  # lsof always returns PID since kill is builtin, so script outputs warning
  run "$SCRIPT" off
  # Verify launchctl was called correctly
  grep -q "bootout" "$TEST_TMPDIR/launchctl.log"
  grep -q "disable" "$TEST_TMPDIR/launchctl.log"
}

@test "off: 对两个 gateway 都执行 bootout" {
  run "$SCRIPT" off
  # Count bootout lines
  local count
  count=$(grep -c "bootout" "$TEST_TMPDIR/launchctl.log" || true)
  [ "$count" -ge 2 ]
}

# ============================================================
# 无效参数处理
# ============================================================

@test "无效参数: 退出码为 1" {
  run "$SCRIPT" invalid-arg-xyz
  [ "$status" -eq 1 ]
}

@test "无效参数: 输出用法信息" {
  run "$SCRIPT" invalid-arg-xyz
  echo "$output" | grep -q "用法\|usage"
}
