#!/bin/bash
# PenguinLab - Coleta de especificacoes em lote
# Executa o specs.yml (facts do Ansible) e mostra o resultado em tabela.
# Deve ser executado no notebook/PC de controle, a partir da pasta ansible/.
#
# Uso:
#   ./collect-specs.sh                          (todas as maquinas do inventory.ini)
#   ./collect-specs.sh --limit penguinlab-01    (uma maquina apenas)

set -euo pipefail
cd "$(dirname "$0")"

ARQUIVO_CSV="/tmp/penguinlab-specs.csv"

echo "Coletando especificacoes das maquinas (isso le alguns segundos por maquina)..."
ansible-playbook -i inventory.ini specs.yml "$@"

echo ""
echo "============================================"
echo "  PenguinLab - Especificacoes das maquinas"
echo "============================================"
if [ -f "$ARQUIVO_CSV" ]; then
    column -t -s ';' "$ARQUIVO_CSV"
else
    echo "Arquivo $ARQUIVO_CSV nao encontrado — a coleta falhou?"
    exit 1
fi