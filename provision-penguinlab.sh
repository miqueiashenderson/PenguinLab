#!/bin/bash
# PenguinLab - Script de Provisionamento
# Configura DNS filtrado, Firefox restrito e usuario sem privilegios administrativos.
# Deve ser executado como root em cada maquina do laboratorio.
#
# Uso: sudo ./provision-penguinlab.sh

set -euo pipefail

# ============================================================
# CONFIGURACAO
# ============================================================
LOGFILE="/var/log/penguinlab-provision.log"
USUARIO="aluno"
SENHA_ALUNO="${PENGUINLAB_PASSWORD:-aluno}"
DNS_PRIMARIO="1.1.1.3"
DNS_SECUNDARIO="1.0.0.3"
HOMEPAGE="https://www.google.com.br"

# Cores (desabilitadas se nao for terminal interativo)
if [ -t 1 ]; then
    VERMELHO='\033[0;31m'
    VERDE='\033[0;32m'
    AMARELO='\033[1;33m'
    NORMAL='\033[0m'
else
    VERMELHO=''; VERDE=''; AMARELO=''; NORMAL=''
fi

log()   { echo -e "${VERDE}[+]${NORMAL} $*" | tee -a "$LOGFILE"; }
aviso() { echo -e "${AMARELO}[!]${NORMAL} $*" | tee -a "$LOGFILE"; }
erro()  { echo -e "${VERMELHO}[*]${NORMAL} $*" | tee -a "$LOGFILE"; }

# ============================================================
# VERIFICACOES INICIAIS
# ============================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        erro "Este script deve ser executado como root."
        erro "Uso: sudo $0"
        exit 1
    fi
}

init_log() {
    mkdir -p "$(dirname "$LOGFILE")"
    echo "=== PenguinLab Provision - $(date) ===" >> "$LOGFILE"
    log "Log iniciado em $LOGFILE"
}

# ============================================================
# DNS FILTRADO (Cloudflare for Families via systemd-resolved)
# ============================================================
setup_dns() {
    log "--- Configurando DNS filtrado ---"

    # Verificar se systemd-resolved esta ativo
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        log "systemd-resolved esta ativo."
    else
        aviso "systemd-resolved nao esta ativo. Tentando ativar..."
        if systemctl enable --now systemd-resolved 2>/dev/null; then
            log "systemd-resolved ativado com sucesso."
        else
            aviso "Nao foi possivel ativar systemd-resolved."
            aviso "Configure manualmente os DNSs $DNS_PRIMARIO e $DNS_SECUNDARIO no seu gerenciador de rede."
            return 1
        fi
    fi

    # Configurar /etc/systemd/resolved.conf
    if [ ! -f /etc/systemd/resolved.conf.penguinlab.bak ]; then
        cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.penguinlab.bak 2>/dev/null || true
        log "Backup de resolved.conf original salvo em resolved.conf.penguinlab.bak."
    fi

    cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=${DNS_PRIMARIO} ${DNS_SECUNDARIO}
FallbackDNS=
DNSSEC=no
DNSOverTLS=opportunistic
EOF
    log "Arquivo /etc/systemd/resolved configurado com DNSOverTLS=opportunistic."

    # Garantir que /etc/resolv.conf aponte para o stub do systemd-resolved
    if [ -L /etc/resolv.conf ]; then
        CURRENT_TARGET=$(readlink -f /etc/resolv.conf 2>/dev/null || true)
        if [[ "$CURRENT_TARGET" != *"systemd"* ]]; then
            ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
            log "/etc/resolv.conf redirecionado para o stub do systemd-resolved."
        else
            log "/etc/resolv.conf ja aponta para o systemd-resolved."
        fi
    else
        aviso "/etc/resolv.conf nao e um symlink. Verifique manualmente a configuracao de DNS."
    fi

    # Impedir que o NetworkManager sobrescreva o DNS
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-penguinlab-dns.conf << 'EOF'
[main]
dns=systemd-resolved
EOF
    log "NetworkManager configurado para nao sobrescrever DNS (dns=systemd-resolved)."

    # Reiniciar systemd-resolved para aplicar
    systemctl restart systemd-resolved 2>/dev/null || true
    log "DNS filtrado configurado: $DNS_PRIMARIO / $DNS_SECUNDARIO (Cloudflare for Families)"
}

# ============================================================
# POLITICA RESTRITIVA DO FIREFOX
# ============================================================
setup_firefox() {
    log "--- Configurando politicas do Firefox ---"

    # Verificar se Firefox esta instalado
    if ! command -v firefox &>/dev/null && ! snap list firefox &>/dev/null 2>&1; then
        aviso "Firefox nao detectado neste sistema. Pulando configuracao."
        return 0
    fi

    # Verificar se Firefox e snap (Ubuntu 24.04+)
    if snap list firefox &>/dev/null 2>&1; then
        aviso "================================================================"
        aviso "AVISO IMPORTANTE: O Firefox foi detectado via SNAP."
        aviso "O policies.json em /etc/firefox/policies pode NAO ser"
        aviso "respeitado corretamente devido ao sandboxing do snap."
        aviso ""
        aviso "Recomendacao: trocar para a versao .deb/apt do Firefox."
        aviso "  sudo snap remove firefox"
        aviso "  sudo apt install firefox"
        aviso "================================================================"
    fi

    # Criar diretorio de politicas
    mkdir -p /etc/firefox/policies

    # Gerar policies.json
    cat > /etc/firefox/policies/policies.json << POLICIES
{
  "policies": {
    "Homepage": {
      "URL": "${HOMEPAGE}",
      "Locked": true
    },
    "DNSOverHTTPS": {
      "Enabled": false,
      "Locked": true
    },
    "BlockAboutConfig": true,
    "BlockAboutProfiles": true,
    "BlockAboutAddons": true,
    "DisableDeveloperTools": true,
    "DisablePrivateBrowsing": true,
    "DisableProfileChooser": true,
    "DisableProfileImport": true,
    "DisableTelemetry": true,
    "DisableFirefoxAccounts": true,
    "DisableFirefoxStudies": true,
    "DisableFirefoxScreenshots": true,
    "DisablePocket": true,
    "DisablePocketNewtabContent": true,
    "DisableSystemAddonUpdate": true,
    "DisableDefaultBrowserAgent": true,
    "DisableFeedbackCommands": true,
    "DisableFormHistory": true,
    "DisableMasterPasswordCreation": true,
    "DisablePasswordReveal": true,
    "DisablePromptOnExternalSoftware": true,
    "DisableResearch": true,
    "DisableSafetyTools": true,
    "DisableShareActivities": true,
    "DisableSetDesktopBackground": true,
    "DisableToolbarCustomization": true,
    "DisableTranslate": true,
    "DontCheckDefaultBrowser": true,
    "NoDefaultBookmarks": true,
    "OfferToSaveLogins": false,
    "PasswordManagerEnabled": false,
    "Proxy": {
      "Mode": "system"
    },
    "SearchBar": "unified",
    "ExtensionSettings": {
      "*": {
        "installation_mode": "blocked",
        "blocked_install_message": "A instalacao de extensoes esta desabilitada neste computador."
      }
    },
    "InstallAddonsPermission": {
      "Default": false
    }
  }
}
POLICIES

    log "Politicas do Firefox configuradas em /etc/firefox/policies/policies.json"
    log "  - Extensoes bloqueadas"
    log "  - Navegacao privada desabilitada"
    log "  - about:config, about:addons, about:profiles bloqueados"
    log "  - Developer tools desabilitadas"
    log "  - DNS-over-HTTPS desabilitado e travado"
    log "  - Telemetria, Pocket, Firefox Accounts desabilitados"
    log "  - Homepage fixa e travada: $HOMEPAGE"
}

# ============================================================
# USUARIO ALUNO SEM PRIVILEGIOS ADMINISTRATIVOS
# ============================================================
setup_user() {
    log "--- Configurando usuario $USUARIO ---"

    if [ "$SENHA_ALUNO" == "aluno" ]; then
        aviso "================================================================"
        aviso "ATENCAO: usando a senha PADRAO ('aluno') para o usuario aluno."
        aviso "Defina PENGUINLAB_PASSWORD antes de rodar em producao."
        aviso "================================================================"
    fi

    # Criar usuario (idempotente)
    if id "$USUARIO" &>/dev/null; then
        log "Usuario $USUARIO ja existe."
    else
        useradd -m -s /bin/bash "$USUARIO"
        echo "$USUARIO:$SENHA_ALUNO" | chpasswd
        log "Usuario $USUARIO criado com sucesso."
    fi

    # Garantir que o shell e bash (pode ter sido alterado)
    usermod -s /bin/bash "$USUARIO"
    log "Shell do usuario $USUARIO definido como /bin/bash."

    # Remover de grupos administrativos
    for grupo in sudo admin wheel; do
        if groups "$USUARIO" 2>/dev/null | grep -qw "$grupo"; then
            gpasswd -d "$USUARIO" "$grupo" 2>/dev/null || true
            log "Usuario $USUARIO removido do grupo $grupo."
        fi
    done

    # Bloquear sudo via /etc/sudoers.d/
    cat > /etc/sudoers.d/penguinlab-aluno << SUDOERS
# PenguinLab: bloquear sudo para o usuario $USUARIO
$USUARIO ALL=(ALL) !ALL
SUDOERS
    chmod 440 /etc/sudoers.d/penguinlab-aluno

    # Validar o arquivo sudoers com visudo
    if visudo -c -f /etc/sudoers.d/penguinlab-aluno 2>/dev/null; then
        log "Arquivo /etc/sudoers.d/penguinlab-aluno validado com sucesso."
    else
        erro "Falha na validacao do sudoers! Removendo arquivo perigoso."
        rm -f /etc/sudoers.d/penguinlab-aluno
        return 1
    fi

    # Configurar polkit para bloquear acoes administrativas (formato JS rules)
    if ! dpkg -s polkitd 2>/dev/null | grep -q "^Status: install ok installed"; then
        aviso "polkitd nao instalado. Regras polkit nao aplicadas."
    else
        mkdir -p /etc/polkit-1/rules.d

        cat > /etc/polkit-1/rules.d/90-penguinlab-restrict.rules << RULES
// PenguinLab: bloqueia acoes administrativas para o usuario $USUARIO
polkit.addRule(function(action, subject) {
    if (subject.user == "$USUARIO") {
        if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 ||
            action.id.indexOf("org.freedesktop.packagekit.") == 0 ||
            action.id.indexOf("org.freedesktop.udisks2.") == 0 ||
            action.id.indexOf("org.freedesktop.systemd1.") == 0) {
            return polkit.Result.NO;
        }
    }
});
RULES

        systemctl restart polkit 2>/dev/null || true
        log "Politicas polkit configuradas para o usuario $USUARIO (formato JS rules)."
        log "  - Configuracao de rede bloqueada"
        log "  - Instalacao de pacotes bloqueada"
        log "  - Montagem de discos bloqueada"
        log "  - Gerenciamento de servicos systemd bloqueado"
    fi
}

# ============================================================
# RESTRICAO DE LOGIN SSH PARA O ALUNO
# ============================================================
setup_ssh_restriction() {
    log "--- Restringindo acesso SSH do usuario $USUARIO ---"

    if ! command -v sshd &>/dev/null; then
        aviso "sshd nao encontrado. Restricao de SSH nao aplicada."
        return 0
    fi

    local drop_in="/etc/ssh/sshd_config.d/90-penguinlab-no-ssh-aluno.conf"
    cat > "$drop_in" << EOF
# PenguinLab: impede login SSH remoto para o usuario $USUARIO
DenyUsers $USUARIO
EOF

    if sshd -t 2>/dev/null; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        log "Login SSH bloqueado para '$USUARIO' ($drop_in)."
    else
        erro "Configuracao SSH invalida! Removendo arquivo."
        rm -f "$drop_in"
        return 1
    fi
}

# ============================================================
# AUTO-LOGIN DO ALUNO (LightDM / Slick Greeter)
# ============================================================
setup_autologin() {
    log "--- Configurando auto-login do usuario $USUARIO ---"

    # Arquivo principal do LightDM. No Mint/Ubuntu desktop e /etc/lightdm/lightdm.conf.
    local conf="/etc/lightdm/lightdm.conf"

    if [ ! -f "$conf" ]; then
        aviso "LightDM nao encontrado ($conf). Auto-login nao configurado."
        return 0
    fi

    # Garantir que o grupo autologin existe e o aluno pertence a ele
    # (necessario em alguns sistemas para o LightDM liberar o autologin)
    if getent group autologin >/dev/null 2>&1; then
        usermod -a -G autologin "$USUARIO" 2>/dev/null || true
        log "Usuario $USUARIO adicionado ao grupo 'autologin'."
    fi

    # Remover chaves de autologin existentes (idempotencia: evita duplicatas)
    sed -i "/^autologin-user=/d; /^autologin-user-timeout=/d" "$conf" 2>/dev/null || true

    # Garantir a secao [Seat:*] com as chaves (cria a secao se nao existir)
    if grep -q "^\[Seat:\*\]" "$conf"; then
        sed -i "/^\[Seat:\*\]/a autologin-user=$USUARIO\nautologin-user-timeout=0" "$conf" 2>/dev/null || true
    else
        printf '\n[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n' "$USUARIO" >> "$conf"
    fi

    log "Auto-login configurado: $USUARIO entra automaticamente na proxima inicializacao."
}

# ============================================================
# RESUMO FINAL
# ============================================================
summary() {
    log ""
    log "============================================"
    log "  PenguinLab - Provisionamento Concluido"
    log "============================================"
    log ""
    log "Configuracoes aplicadas:"
    log ""
    log "1. DNS Filtrado"
    log "   - DNSs: $DNS_PRIMARIO / $DNS_SECUNDARIO (Cloudflare for Families)"
    log "   - DNSOverTLS: opportunistic"
    log "   - NetworkManager: configurado para nao sobrescrever DNS"
    log ""
    log "2. Firefox Restrito"
    log "   - Politicas em /etc/firefox/policies/policies.json"
    log "   - Extensoes bloqueadas"
    log "   - Navegacao privada desabilitada"
    log "   - DNS-over-HTTPS desabilitado e travado"
    log "   - Telemetria e servicos online desabilitados"
    log "   - Homepage fixa: $HOMEPAGE"
    log ""
    log "3. Usuario $USUARIO"
    log "   - Shell: /bin/bash (terminal NAO restrito)"
    log "   - Grupos administrativos removidos"
    log "   - sudo bloqueado via /etc/sudoers.d/"
    log "   - Login SSH remoto bloqueado"
    log "   - Politicas polkit configuradas"
    log ""
    log "4. Auto-login"
    log "   - Usuario $USUARIO entra automaticamente ao ligar a maquina"
    log ""
    log "Log completo: $LOGFILE"
    log ""
    log "IMPORTANTE: Reinicie a maquina para garantir que todas"
    log "as configuracoes tenham efeito completo."
}

# ============================================================
# MAIN
# ============================================================
main() {
    echo ""
    echo "============================================"
    echo "  PenguinLab - Script de Provisionamento"
    echo "  $(date)"
    echo "============================================"
    echo ""

    check_root
    init_log

    setup_dns
    setup_firefox
    setup_user
    setup_ssh_restriction
    setup_autologin

    summary
}

main "$@"
