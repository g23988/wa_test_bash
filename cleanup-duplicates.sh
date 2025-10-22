#!/bin/bash

# 清理重複和不必要的文件

set -euo pipefail

echo "清理重複文件..."

# 備份重要的獨立腳本到 scripts/legacy/ 目錄
mkdir -p scripts/legacy

# 移動獨立的分析腳本到 legacy 目錄
echo "移動獨立分析腳本到 legacy 目錄..."
if [[ -f "scripts/analyze-compute-cost.sh" ]]; then
    mv scripts/analyze-compute-cost.sh scripts/legacy/
fi
if [[ -f "scripts/analyze-database-cost.sh" ]]; then
    mv scripts/analyze-database-cost.sh scripts/legacy/
fi
if [[ -f "scripts/analyze-network-cost.sh" ]]; then
    mv scripts/analyze-network-cost.sh scripts/legacy/
fi
if [[ -f "scripts/analyze-monitoring-cost.sh" ]]; then
    mv scripts/analyze-monitoring-cost.sh scripts/legacy/
fi
if [[ -f "scripts/analyze-datatransfer-cost.sh" ]]; then
    mv scripts/analyze-datatransfer-cost.sh scripts/legacy/
fi

# 移動區域管理腳本到 legacy 目錄
echo "移動區域管理腳本到 legacy 目錄..."
if [[ -f "scripts/set-region.sh" ]]; then
    mv scripts/set-region.sh scripts/legacy/
fi
if [[ -f "scripts/quick-region.sh" ]]; then
    mv scripts/quick-region.sh scripts/legacy/
fi

# 移動故障排除腳本到 legacy 目錄
echo "移動故障排除腳本到 legacy 目錄..."
if [[ -f "scripts/troubleshoot.sh" ]]; then
    mv scripts/troubleshoot.sh scripts/legacy/
fi

# 創建 legacy 目錄的說明文件
cat > scripts/legacy/README.md << 'EOF'
# Legacy Scripts

這個目錄包含被統一工具 `wa-tool.sh` 整合的獨立腳本。

這些腳本仍然可以獨立使用，但建議使用統一工具：

## 替代方案

| 舊腳本 | 新命令 |
|--------|--------|
| `analyze-compute-cost.sh` | `./wa-tool.sh analyze compute` |
| `analyze-database-cost.sh` | `./wa-tool.sh analyze database` |
| `analyze-network-cost.sh` | `./wa-tool.sh analyze network` |
| `analyze-monitoring-cost.sh` | `./wa-tool.sh analyze monitoring` |
| `analyze-datatransfer-cost.sh` | `./wa-tool.sh analyze datatransfer` |
| `set-region.sh` | `./wa-tool.sh region set` |
| `quick-region.sh` | `./wa-tool.sh region quick <code>` |
| `troubleshoot.sh` | `./wa-tool.sh check system` |

## 使用獨立腳本

如果需要使用這些獨立腳本：

```bash
# 設定權限
chmod +x scripts/legacy/*.sh

# 使用範例
./scripts/legacy/analyze-compute-cost.sh reports/cost-optimization_detailed_*.jsonl
```
EOF

echo "清理完成！"
echo
echo "變更摘要:"
echo "- 獨立分析腳本移動到 scripts/legacy/"
echo "- 區域管理腳本移動到 scripts/legacy/"
echo "- 故障排除腳本移動到 scripts/legacy/"
echo "- 所有功能現在通過 wa-tool.sh 統一管理"
echo
echo "建議使用:"
echo "  ./wa-tool.sh help    # 查看所有可用命令"