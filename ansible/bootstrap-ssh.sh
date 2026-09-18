#!/bin/bash
# PenguinLab - Bootstrap SSH para varias maquinas
# Auxilia na preparacao das maquinas apos a instalacao manual do Mint:
#   1. Descobre as maquinas na rede (opcional)
#   2. Garante openssh-server e python3 em cada maquina (via SSH)
#   3. Copia a chave publica SSH do notebook para a conta admin de cada maquina
#   4. Valida a conexao
#
# Deve ser executado a partir do notebook/PC de controle do professor.
#
# Uso:
#   ./bootstrap-ssh.sh
#   ./bootstrap-ssh.sh <ip1> [ip2 ...]        (ja com os IPs)
#   ./bootstrap-ssh.sh --descobrir <rede>     (ex: 192.168.0)
#
# Pre-requisitos manuais em cada maquina:
#   - Linux Mint instalado
#   - Conta admin criada (ex: professor) - NUNCA "aluno"
#   - Senha da conta admin definida

set -euo pipefail

# ============================================================
# CONFIGURACAO
# ============================================================
USUARIO_ADMIN="${PENGUINLAB_ADMIN:-professor}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=no"
LOG="bootstrap-ssh.log"

# Cores (desabilitadas fora de terminal interativo)
if [ -t 1 ]; then
    VERMELHO='\033[0;31m'; VERDE='\033[0;32m'; AMARELO='\033[1;33m'; NORMAL='\033[0m'
else
    VERMELHO=''; VERDE=''; AMARELO=''; NORMAL=''
fi

log()   { echo -e "${VERDE}[+]${NORMAL} $*" | tee -a "$LOG"; }
aviso() { echo -e "${AMARELO}[!]${NORMAL} $*" | tee -a "$LOG"; }
erro()  { echo -e "${VERMELHO}[*]${NORMAL} $*" | tee -a "$LOG"; }

# ============================================================
# PREPARAR UMA MAQUINA
# ============================================================
preparar_maquina() {
    local host="$1"

    echo ""
    log "=== Processando $host ==="

    # 0. O sshd precisa estar ATIVO: o bootstrap usa SSH como transporte.
    #    Em instalacao nova do Mint/Ubuntu o sshd vem DESATIVADO por padrao.
    if ! timeout 2 bash -c "echo >/dev/tcp/${host}/22" 2>/dev/null; then
        aviso "$host: porta 22 fechada — host inacessivel OU OpenSSH server nao ativo."
        aviso "$host:   Em instalacao nova do Mint/Ubuntu o sshd vem desativado por padrao."
        aviso "$host:   Ative-o manualmente nesta maquina (uma vez):"
        aviso "$host:     sudo apt install -y openssh-server"
        aviso "$host:     sudo systemctl enable --now ssh"
        aviso "$host:   Depois rode este bootstrap novamente."
        return 1
    fi
    log "$host: porta 22 aberta (sshd ativo)."

    # 1. Garantir openssh-server e python3 (python3 e exigido pelo Ansible)
    if ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        "command -v sshd >/dev/null 2>&1 || sudo apt-get install -y openssh-server >/dev/null 2>&1; :"; then
        log "$host: openssh-server garantido."
    else
        aviso "$host: nao foi possivel garantir openssh-server (host pode estar off ou senha errada?)."
    fi

    if ssh ${SSH_OPTS} "${USUARIO_ADMIN}@${host}" \
        "command -v python3 >/dev/null 2>&1 || sudo apt-get install -y python3 >/dev/null 2>&1; :"; then
        log "$host: python3 disponivel."
    else
        aviso "$host: nao foi possivel garantir python3."
    fi

    # 2. Copiar chave publica (se existir uma; senha pedida interativamente)
    key_file=""
    for f in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
        [ -f "$f" ] && key_file="$f" && break
    done

    if [ -n "$key_file" ]; then
        log "$host: copiando chave publica ($key_file)..."
        ssh-copy-id ${SSH_OPTS} -i "$key_file" "${USUARIO_ADMIN}@${host}" >/dev/null 2>&1 \
            && log "$host: chave copiada com sucesso." \
            || aviso "$host: falha ao copiar chave (verifique a senha)."
    else
        aviso "$host: nenhuma chave publica encontrada em ~/.ssh. Execute 'ssh-keygen' primeiro."
    fi

    # 3. Validar conexao sem senha
    if ssh ${SSH_OPTS} -o BatchMode=yes "${USUARIO_ADMIN}@${host}" "echo ok" >/dev/null 2>&1; then
        log "$host: conexao SSH sem senha OK."
    else
        aviso "$host: conexao sem senha FALHOU."
    fi
}

# ============================================================
# DESCOBRIR HOSTS NA REDE
# ============================================================
descobrir_hosts() {
    local rede="$1"
    local tmpfile
    tmpfile=$(mktemp)

    echo "Procurando hosts com porta 22 aberta em ${rede}.0/24 ..."
    for i in $(seq 1 254); do
        (
            ip="${rede}.${i}"
            if timeout 1 bash -c "echo >/dev/tcp/${ip}/22" 2>/dev/null; then
                echo "$ip" >> "$tmpfile"
            fi
        ) &
        # limitar concorrencia
        (( $(jobs -r -p | wc -l) >= 50 )) && wait -n
    done
    wait

    local hosts=()
    if [ -s "$tmpfile" ]; then
        mapfile -t hosts < <(sort -t. -k4 -n "$tmpfile")
        for h in "${hosts[@]}"; do aviso "Encontrado: $h"; done
        aviso "Nota: so aparecem hosts com a porta 22 aberta. Maquinas sem o"
        aviso "OpenSSH server ativo nao aparecem — ative-o nelas com:"
        aviso "  sudo apt install -y openssh-server && sudo systemctl enable --now ssh"
    fi
    rm -f "$tmpfile"

    if [ ${#hosts[@]} -eq 0 ]; then
        erro "Nenhum host encontrado na rede ${rede}.0/24."
        exit 1
    fi
    echo "${hosts[@]}"
}

# ============================================================
# MAIN
# ============================================================
main() {
    echo "============================================"
    echo "  PenguinLab - Bootstrap SSH"
    echo "  $(date)"
    echo "============================================"

    # Chave SSH existe?
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
        log "Nova chave SSH gerada em ~/.ssh/id_ed25519."
    fi
    [ -f ~/.ssh/id_ed25519.pub ] || [ -f ~/.ssh/id_rsa.pub ] \
        || aviso "Nenhuma chave publica. Gere uma com: ssh-keygen -t ed25519"

    local -a hosts=()

    if [ "${1:-}" == "--descobrir" ]; then
        hosts=($(descobrir_hosts "$2"))
    else
        hosts=("$@")
    fi

    if [ ${#hosts[@]} -eq 0 ]; then
        erro "Nenhuma maquina informada."
        echo "Uso: $0 [--descobrir <rede> | <ip1> <ip2> ...]"
        exit 1
    fi

    log "Processando ${#hosts[@]} maquina(s) para o usuario '${USUARIO_ADMIN}'."
    log "Log: $LOG"

    for host in "${hosts[@]}"; do
        preparar_maquina "$host" || aviso "Pulando $host (falha na preparacao)."
    done

    echo ""
    log "Bootstrap concluido."
    log "Agora edite o inventory.ini com os IPs e rode o playbook:"
    log "  ansible-playbook -i inventory.ini playbook.yml"
}

main "$@"
