#!/bin/bash
# 命令行验证解析器逻辑（无 XCTest 环境下的替代方案）
set -e
cd "$(dirname "$0")"
swiftc \
    Sources/WeChatTodo/TodoItem.swift \
    Sources/WeChatTodo/TodoStore.swift \
    Sources/WeChatTodo/OCRService.swift \
    Sources/WeChatTodo/RequirementParser.swift \
    Tests/RunTests/main.swift \
    -o .build/run-tests \
    -framework AppKit -framework Vision
.build/run-tests
