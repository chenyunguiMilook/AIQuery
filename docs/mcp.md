# aiq-mcp (MCP Server)

`aiq-mcp` 是一个基于 MCP stdio transport 的本地 server，用来把已安装的 `aiq` CLI（查询 SQLite 索引）暴露为可调用的 tools。

## 前置条件

- 已在项目根目录生成索引数据库：`.ai/index.sqlite`（或旧版 `.aiq/index.sqlite`）
- 已安装 CLI：
  - `make install`（安装 `aiq` 到 `/usr/local/bin/aiq`）
  - `make install-mcp`（安装 `aiq-mcp` 到 `/usr/local/bin/aiq-mcp`）

## Tools

### 1) `query_type`

- 入参：
  - `name` (string, 必填)：类型名（精确匹配）
  - `membersLimit` (integer, 可选)：包含 top N 成员方法声明（0 禁用）
- 行为：内部执行 `aiq type <name> [--members-limit N]`
- 返回：JSON 数组（文本形式），数组元素与 `aiq` 输出的每行 JSON 对象一致

### 2) `query_method`

- 入参：
  - `name` (string, 必填)：方法名（精确匹配）
- 行为：内部执行 `aiq method <name>`
- 返回：JSON 数组（文本形式）

## Claude Desktop 配置示例（macOS）

将以下片段合并到 Claude Desktop 的 MCP 配置中（路径通常在 `~/Library/Application Support/Claude/claude_desktop_config.json`，以 Claude 实际版本为准）：

```json
{
  "mcpServers": {
    "aiq": {
      "command": "/usr/local/bin/aiq-mcp",
      "args": []
    }
  }
}
```

> 运行时请确保 Claude 的“工作目录”是你的项目根目录（包含 `.ai/index.sqlite`）。

## VS Code 配置示例（如你的 MCP 客户端支持 stdio command）

如果你使用的 VS Code / Copilot 集成支持 MCP server 配置（stdio command 方式），配置思路同上：

- command: `/usr/local/bin/aiq-mcp`
- args: `[]`
- cwd: 设为项目根目录（确保能找到 `.ai/index.sqlite`）

## 手动本地运行

你可以直接跑：

```bash
aiq-mcp
```

它会通过 stdin/stdout 等待 MCP JSON-RPC 请求（适合用 MCP client 做集成测试）。

## 本地冒烟测试（推荐）

在你要查询的“项目根目录”（包含 `.ai/index.sqlite`）下执行：

```bash
cd /Users/chenyungui/Documents/vectorShop/VectorShop

# 先确认 aiq 能查到结果（应输出 JSONL）
aiq type Bezier3Segment --members-limit 1 | head -n 2

# 再跑 MCP 端到端测试：initialize -> tools/list -> tools/call(query_type)
python3 /Users/chenyungui/Documents/vectorShop/AIQuery/scripts/mcp_smoke_test.py "$PWD" Bezier3Segment
```
