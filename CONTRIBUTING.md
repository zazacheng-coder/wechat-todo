# 贡献指南

欢迎参与「便签待办」的开发。请遵循以下约定，让协作更顺畅。

## 提交信息规范

使用 Conventional Commits 风格：

```
<type>(<scope>): <简短描述>
```

**type**（必填）：

| type | 用途 |
| --- | --- |
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `perf` | 性能优化 |
| `refactor` | 重构（不改行为） |
| `test` | 测试相关 |
| `docs` | 文档 |
| `chore` | 构建/依赖/杂项 |

**scope**（可选）：涉及的模块，如 `parser`、`panel`、`ocr`。

**示例**：

```text
feat(parser): 支持钉钉/飞书日期格式解析
fix(panel): 修复桌面面板切层级时的偶发崩溃
test: 补充群聊账号名识别用例
```

## 开发约定

- 解析器规则修改后，必须在 `Tests/RunTests/main.swift` 补充对应用例，并运行 `./tests.sh` 保持全绿
- UI 文案使用中文，与现有风格一致
- 改动不破坏 macOS 13+ 兼容性

## 提交流程

1. 从 `main` 拉出分支：`git checkout -b feat/xxx`
2. 提交遵循上面规范
3. 推送分支并创建 Pull Request，说明改动动机与验证方式
4. CI 全绿后合入 `main`

## 本地验证

```bash
./tests.sh   # 解析器单元测试
./build.sh   # 打包 dist/便签待办.app
```
