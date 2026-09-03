#!/bin/bash
# PenguinLab - Check Status
# Verifica remotamente se cada maquina esta provisionada conforme o esperado.
# Deve ser executado a partir do notebook/PC de controle do professor.
#
# Uso:
#   ./check-status.sh                          (usa o inventory.ini)
#   ./check-status.sh <ip> [ip2 ...]           (hosts diretos)
#
# Verifica por maquina:
#   - Usuario 'aluno' criado
#   - 'aluno' fora do grupo sudo/admin
#   - sudo bloqueado para 'aluno'
#   - DNS filtrado ativo (1.1.1.3 / 1.0.0.3)
#   - policies.json do Firefox presente
#   - regras polkit presentes
#   - auto-login do 'aluno' configurado

set -uo pipefail

# ============================================================
# CONFIGURACAO
# ============================================================
USUARIO_ADMIN="${PENGUINLAB_ADMIN:-professor}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes"
CORINGA="\033[0;36m"; VERMELHO='\033[0;31m'; VERDE='\033[0;32m'; AMARELO='\033[1;33m'; NORMAL='\033[0m'

ok()  { echo -e "  ${VERDE}[OK]${NORMAL} $*"; }
falha() { echo -e "  ${VERMELHO}[FALHA]${NORMAL} $*"; }
aviso() { echo -e "  ${AMARELO}[!]${NORMAL} $*"; }

# ============================================================
# VERIFICAR UMA MAQUINA
# ============================================================
verificar_maquina() {
    local host="$1"
    local host_ok=true
    echo ""
    echo -e "${CORINGA}===== $host =====${NORMAL}"

    local cmd=""
    local res=""

    # 1. Conexao e usuario aluno
    res=$(ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" 'id aluno 2>/dev/null; echo "separator"; groups aluno 2>/dev/null; echo "separator"; sudo -l -U aluno 2>&1' 2>/dev/null)

    if [ -z "$res" ]; then
        falha "Sem resposta SSH — host inacessivel ou credencial errada."
        host_ok=false
        return 1
    fi

    # 2. Usuario aluno existe
    if echo "$res" | grep -q "uid="; then
        ok "Usuario 'aluno' existe."
    else
        falha "Usuario 'aluno' NAO existe."
        host_ok=false
    fi

    # 3. Aluno fora dos grupos admin
    if echo "$res" | grep -qE "\b(sudo|admin|wheel)\b"; then
        falha "'aluno' esta em grupo admin (sudo/admin/wheel)."
        host_ok=false
    else
        ok "'aluno' nao esta em grupos admin."
    fi

    # 4. Sudo bloqueado
    if echo "$res" | grep -qi "not allowed\|nao permitido\|!ALL"; then
        ok "sudo bloqueado para 'aluno'."
    else
        falha "sudo pode NAO estar bloqueado para 'aluno'."
        host_ok=false
    fi

    # 5. DNS filtrado (comando sem sudo via ssh separado para checar resolv.conf ativo)
    res=$(ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        'grep -oE "DNS=[0-9.]+ [0-9.]+" /etc/systemd/resolved.conf 2>/dev/null' 2>/dev/null)
    if echo "$res" | grep -q "1.1.1.3.*1.0.0.3"; then
        ok "DNS filtrado configurado (Cloudflare for Families)."
    else
        aviso "DNS filtrado nao encontrado em /etc/systemd/resolved.conf."
        host_ok=false
    fi

    # 6. policies.json do Firefox
    res=$(ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        'test -f /etc/firefox/policies/policies.json && echo PRESENTE || echo AUSENTE' 2>/dev/null)
    if [ "$res" = "PRESENTE" ]; then
        ok "Firefox policies.json presente."
    else
        aviso "Firefox policies.json NAO encontrado."
        host_ok=false
    fi

    # 7. Regras polkit
    res=$(ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        'test -f /etc/polkit-1/rules.d/90-penguinlab-restrict.rules && echo PRESENTE || echo AUSENTE' 2>/dev/null)
    if [ "$res" = "PRESENTE" ]; then
        ok "Regras polkit presentes."
    else
        aviso "Regras polkit NAO encontradas."
        host_ok=false
    fi

    # 8. Auto-login do aluno
    res=$(ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        'grep -q "^autologin-user=aluno" /etc/lightdm/lightdm.conf 2>/dev/null && echo CONFIGURADO || echo AUSENTE' 2>/dev/null)
    if [ "$res" = "CONFIGURADO" ]; then
        ok "Auto-login do 'aluno' configurado."
    else
        aviso "Auto-login do 'aluno' NAO configurado."
        host_ok=false
    fi

    # 9. Login SSH do aluno bloqueado
    res=$(ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        'test -f /etc/ssh/sshd_config.d/90-penguinlab-no-ssh-aluno.conf && echo CONFIGURADO || echo AUSENTE' 2>/dev/null)
    if [ "$res" = "CONFIGURADO" ]; then
        ok "Login SSH do 'aluno' bloqueado."
    else
        aviso "Login SSH do 'aluno' NAO bloqueado."
        host_ok=false
    fi

    if [ "$host_ok" = "true" ]; then
        return 0
    fi
    return 1
}

# ============================================================
# EXTRAIR HOSTS DO INVENTORY.INI
# ============================================================
hosts_do_inventory() {
    local inv="inventory.ini"
    [ -f "$inv" ] || inv="$(dirname "$0")/inventory.ini"
    if [ -f "$inv" ]; then
        grep -oE 'ansible_host=[0-9.]+' "$inv" | sed 's/ansible_host=//'
    fi
}

# ============================================================
# MAIN
# ============================================================
main() {
    echo "============================================"
    echo "  PenguinLab - Check Status"
    echo "  $(date)"
    echo "============================================"

    local -a hosts=()

    if [ "$#" -gt 0 ]; then
        hosts=("$@")
    else
        hosts=($(hosts_do_inventory))
    fi

    if [ ${#hosts[@]} -eq 0 ]; then
        echo "Nenhum host informado e inventory.ini vazio."
        echo "Uso: $0 [<ip> ...]"
        exit 1
    fi

    echo "Verificando ${#hosts[@]} maquina(s) como '${USUARIO_ADMIN}'."
    local passa=0; local total=0

    for h in "${hosts[@]}"; do
        total=$((total + 1))
        if verificar_maquina "$h"; then
            passa=$((passa + 1))
        fi
    done

    echo ""
    echo "Resumo: $passa/$total maquinas totalmente OK."
    echo "Verificacao concluida."
}

main "$@"
