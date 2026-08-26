# PenguinLab — Documentacao Completa

---

## 1. Resumo do Projeto

PenguinLab e um sistema de provisionamento para laboratorios de informatica escolares (criancas). Nao e mais uma construcao de ISO customizada — e um **script de provisionamento** que roda em cima de uma instalacao padrao e nao modificada do Ubuntu ou Linux Mint.

Aplicam-se tres camadas de restricao em cada maquina:

| Camada | O que faz |
|---|---|
| **DNS Filtrado** | Cloudflare for Families (1.1.1.3 / 1.0.0.3) via systemd-resolved com DNS-over-TLS |
| **Firefox Restrito** | Politicas enterprise: extensoes bloqueadas, navegacao privada desabilitada, DNS-over-HTTPS travado, developer tools bloqueados |
| **Usuario Sem Admin** | Usuario `aluno` com shell normal (bash) mas sem sudo, sem polkit admin, com restricoes deinstalacao de pacotes e gerenciamento de rede |

---

## 2. Decisoes de Arquitetura

### Por que nao ISO customizada?

A abordagem anterior (live-build + squashfs + GRUB/isolinux) era fragil demais — problemas com kernel panic no boot, autoremove removendo pacotes essenciais, complexidade desproporcional. Substituida por provisionamento em cima de um sistema ja instalado.

### Por que provisionar e nao imagem?

- Facil de reexecutar (idempotente)
- Facil de atualizar (rode o script de novo)
- Nao depende de build complexo (squashfs, ISO)
- Funciona sobre instalacoes padrao do Ubuntu/Mint
- Ansible permite aplicar em 14 maquinas simultaneamente

---

## 3. Estrutura de Arquivos

```
PenguinLab/
├── provision-penguinlab.sh    # Script principal, idempotente, roda com sudo
├── ansible/
│   ├── playbook.yml           # Aplica o script via SSH nas maquinas
│   └── inventory.ini          # Inventario de exemplo (14 maquinas)
├── README.md                   # Guia de uso
├── DOCUMENTACAO.md             # Este arquivo
├── .gitignore
└── .opencodeignore
```

### Funcoes do provision-penguinlab.sh

| Funcao | Descricao |
|---|---|
| `setup_dns()` | Configura Cloudflare for Families via systemd-resolved, DNS-over-TLS, impede NM de sobrescrever |
| `setup_firefox()` | Escreve /etc/firefox/policies/policies.json com restricoes enterprise |
| `setup_user()` | Cria/idempotente `aluno`, remove de sudo/admin, bloqueia sudo via sudoers.d, configura polkit JS rules |
| `summary()` | Exibe resumo do que foi aplicado |

### Configuracao (variaveis no topo do script)

- `USUARIO="aluno"` — nome do usuario limitado
- `SENHA_ALUNO` — overrideavel via `PENGUINLAB_PASSWORD=xxx`
- `DNS_PRIMARIO="1.1.1.3"`, `DNS_SECUNDARIO="1.0.0.3"` — Cloudflare for Families
- `HOMEPAGE="https://www.google.com.br"` — homepage travada no Firefox

---

## 4. Fluxo de Uso

### Uso Manual (uma maquina)

1. Copiar o script para a maquina alvo via SSH:
   ```bash
   scp provision-penguinlab.sh professor@192.168.0.21:/tmp/
   ```
2. Conectar e executar como root:
   ```bash
   ssh professor@192.168.0.21
   sudo /tmp/provision-penguinlab.sh
   ```
3. Reiniciar a maquina:
   ```bash
   sudo reboot
   ```

### Uso via Ansible (14 maquinas)

1. Instalar Ansible no notebook:
   ```bash
   sudo apt install ansible
   ```
2. Copiar chave SSH do notebook para cada maquina:
   ```bash
   ssh-copy-id professor@192.168.0.21
   # repetir para cada uma
   ```
3. Editar `ansible/inventory.ini` com os IPs reais
4. Testar em uma unica maquina:
   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --limit penguinlab-01
   ```
5. Rodar em todas:
   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
   ```
6. Reiniciar manualmente (o playbook nao reinicia por padrao).

### Pre-requisitos para o Ansible funcionar

- Chave SSH publica do notebook copiada para cada maquina (via `ssh-copy-id`)
- Conta `professor` (ou o nome que usar) com sudo em cada maquina
- Acesso a porta 22 de todas as maquinas pelo notebook
- Ansible instalado no notebook

---

## 5. Precaucoes e Avisos

### NUNCA usar `aluno` como conta do Ansible

O provision-script bloqueia explicitamente sudo do `aluno` (`USUARIO ALL=(ALL) !ALL`). Se o Ansible se conectar como `aluno`, depois da primeira execucao vai travar com permission denied. Sempre use uma conta admin separada (`professor` ou similar) no `inventory.ini`.

### Firefox via Snap

No Ubuntu 24.04+, o Firefox vem via snap por padrao. Devido ao sandboxing do snap, o `policies.json` em `/etc/firefox/policies/` pode nao ser respeitado. O script detecta isso e avisa. Solucao recomendada:
```bash
sudo snap remove firefox
sudo apt install firefox
```

### polkit

O provision-script usa o formato moderno JS rules (`/etc/polkit-1/rules.d/`). Se `polkitd` nao estiver instalado, o script exibe um aviso e nao aplica as restricoes polkit (mas continua sem erro fatal).

### DNSOverTLS=opportunistic

Usado em vez de `yes` para evitar falhas de resolucao em redes que nao suportam DNS-over-TLS (firewall bloqueando porta 853). Tenta, nao falha se nao funcionar.

---

## 6. Auto-Login e Dual Profile (aluno vs professor)

### Objetivo

Duas contas com comportamentos diferentes na tela de login (Slick Greeter + LightDM):

- **`aluno`** — entra automaticamente, sem tela de login, sem senha, shell bash normal, sem privilegios administrativos
- **`professor`** — login normal com senha, tem sudo, controle total

### Configuracao do LightDM / Slick Greeter

O Mint 22.x usa Slick Greeter como padrao. A configuracao de autologin vai em:

```
/etc/lightdm/slick-greeter.conf
```

Conteudo necesario para autologin do `aluno`:
```ini
[Greeter]
autologin-user=aluno
autologin-user-timeout=0
```

O `professor` nao recebe autologin — aparece na tela de login normal e precisa de senha.

### Relacao com o provision-script

O `provision-penguinlab.sh` atual nao configura o auto-login. A funcao `setup_user()` trata apenas de criar o usuario e restringir permissoes. O auto-login e uma configuracao separada que pode ser adicionada futuramente ao provision-script.

### Como configurar manualmente (para estudar)

1. Editar `/etc/lightdm/slick-greeter.conf`
2. Adicionar `autologin-user=aluno` e `autologin-user-timeout=0`
3. Reiniciar o LightDM: `sudo systemctl restart lightdm`

**Importante**: se o `aluno` nao existir no sistema, o LightDM vai falhar ao tentar autologin. Por isso o autologin do `aluno` deve ser configurado apos o `aluno` ser criado (pelo provision-script ou manualmente).

---

## 7. Problemas Encontrados e Corrigidos

| Problema | Severidade | O que acontecia | Correcao |
|---|---|---|---|
| Self-lockout Ansible | Critico | `ansible_user=aluno` + `!ALL` no sudo = Ansible trava apos primeira execucao | Mudar para `ansible_user=professor` |
| polkit .pkla ignorado | Critico | Ubuntu 24.04 nao tem `polkitd-pkla` instalado por padrao — arquivo `.pkla` eh silenciosamente ignorado | Trocar para JS rules em `/etc/polkit-1/rules.d/` |
| Chaves JSON duplicadas | Moderado | `DisableSystemAddonUpdate`, `DisableTelemetry` etc. duplicados no policies.json | Reorganizar e remover duplicatas |
| Log sobrescrito | Menor | `init_log()` usava `>` (sobrescreve) | Trocado para `>>` (append) |

---

## 8. Problemas Conhecidos do Projeto Original (antes da refatoracao)

Alem dos 4 acima, o projeto original tinha:

| Problema | Arquivo |
|---|---|
| build.sh — script de build ISO mista (Mint live-build) | `build.sh` |
| buildiso.sh — script alternativo de build ISO | `buildiso.sh` |
| build-docker.log — log de build Docker abandoned | `build-docker.log` |
| Veyon, e2guardian, AppArmor — fora de escopo | `config/includes.chroot/`, etc. |
| restricoes.sh — bloqueio de comandos no terminal do aluno | `config/includes.chroot/etc/profile.d/restricoes.sh` |
| Config de DNS no resolved.conf nao usava DNSOverTLS | `config/includes.chroot/etc/systemd/resolved.conf` |
| policies.json do Firefox incompleto (nao bloqueava DNS-over-HTTPS, nao tinha ExtensionSettings correta) | `config/includes.chroot/etc/firefox/policies/policies.json` |
| install-penguinlab.sh usava `useradd -G sudo` pro aluno (contradizia bloqueio de admin) | `scripts/install-penguinlab.sh` |

---

## 9. Roadmap Futuro (Nao Implementado Ainda)

- [ ] Auto-login do `aluno` no Slick Greeter
- [ ] Script `bootstrap-ssh.sh` (descobre IPs + copia chave SSH em lote)
- [ ] Secao pos-deploy / checklist de verificacao no README
- [ ] Rollback plan documentado
- [ ] Script `check-status.sh` para verificar status de provisao
- [ ] `ansible.cfg` com `forks = 14` para paralelismo total

---

## 10. Referencias de Estudo

### Linux / Systemd

- **systemd-resolved** — https://www.freedesktop.org/software/systemd/man/systemd-resolved.html
- **NetworkManager + systemd-resolved** — https://developer.gnome.org/NetworkManager/stable/nm-dns.html
- **Samba Krb5 / Kerberos + DNS** — https://web.mit.edu/kerberos/krb5-latest/doc/admin/conf_files.html

### Shell Scripting (Bash)

- **Advanced Bash-Scripting Guide** — https://tldp.org/LDP/abs/html/ (gratis, completo)
- **Bash Guide for Beginners** — https://tldp.org/LDP/Bash-Beginners-Guide/html/ (gratis)
- **Bash Reference Manual** — https://www.gnu.org/software/bash/manual/bash.html (oficial)

### Politicas Firefox Enterprise

- **Enterprise Policy documentation** — https://mozilla-policy.readthedocs.io/en/latest/
- **policies.json reference** — https://mozilla-policy.readthedocs.io/en/latest/policies_json/

### polkit (PolicyKit)

- **polkit documentation** — https://www.freedesktop.org/wiki/Software/polkit/
- **polkit rules (JS format)** — https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html
- **pam_pkcs11 / polkit local authority** — https://www.freedesktop.org/wiki/Software/polkit/

### Ansible

- **Ansible Documentation** — https://docs.ansible.com/ansible/latest/index.html
- **Ansible Playbook Guide** — https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html
- **Ansible Inventory** — https://docs.ansible.com/ansible/latest/inventory_guide/index.html
- **Ansible become / privilege escalation** — https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html

### Linux Mint / LightDM / Slick Greeter

- **LightDM documentation** — https://wiki.lightdm.org/
- **Slick Greeter configuration** — https://github.com/linuxmint/slick-greeter
- **Linux Mint Debian Edition (LMDE) install guide** — https://linuxmint.com/documentation.php

### Redes e DNS

- **Cloudflare for Families** — https://developers.cloudflare.com/1.1.1.1/
- **DNS-over-HTTPS (DoH)** — https://developers.cloudflare.com/1.1.1.1/dns-over-https/
- **DNS-over-TLS (DoT)** — https://developers.cloudflare.com/1.1.1.1/dns-over-tls/
- **RFC 8484 — DNS Queries over HTTPS** — https://datatracker.ietf.org/doc/html/rfc8484

### Livros Recomendados

| Livro | Foco | Nivel |
|---|---|---|
| *Linux Bible* (Christopher Negus) — Wiley | Linux geral, sysadmin, systemd | Iniciante-Intermediario |
| *UNIX and Linux System Administration Handbook* (Nemeth et al.) — Pearson | Sysadmin completo, redes, users, PAM | Intermediario-Avancado |
| *Linux Network Administrator's Guide* (O'Reilly) | Redes Linux, DNS, firewall | Intermediario |
| *Ansible: Up & Running* (Lorin Hochstein & René Moser) — O'Reilly | Ansible do básico ao provisionamento | Iniciante-Intermediario |
| *Testing with Ansible* (René Moser) | Testes e validação em Ansible | Intermediario |
| *The Linux Command Line* (William Shotts) — NoStarch.com | CLI, bash, fundamentos | Iniciante |

### Sites / Blogs

- https://www.howtogeek.com — Artigos práticos sobre Linux e redes
- https://www.digitalocean.com/community/tutorials — Tutoriais de sysadmin e Ansible
- https://ubuntu.com/server/docs — Documentação oficial do Ubuntu
- https://doc.ubuntu-br.org/ — Documentação Ubuntu em português

---

## 11. Fluxo Completo de Implantação (Resumo Visual)

```
No notebook:
  1. Copiar repo PenguinLab para notebook
  2. Editar ansible/inventory.ini com IPs reais
  3. Testar: ansible-playbook --limit penguinlab-01
  4. Executar: ansible-playbook (todas as 14)

Nas 14 maquinas (cada uma):
  Antes do provision:
    - Linux Mint instalado (instalacao padrao)
    - Usuario 'professor' criado (admin/sudo)
    - OpenSSH server instalado e ativo
    - Chave SSH do notebook copiada para 'professor'
    - Senha de 'professor' configurada ou chave auth

  Apos o provision:
    - DNS filtrado ativo (Cloudflare for Families)
    - Firefox com policies restritivas
    - Usuario 'aluno' criado (sem sudo, sem admin)
    - Auto-login do 'aluno' (configurar no slick-greeter.conf)
    - Reiniciar a maquina
```

---

*Documentacao gerada como parte da refatoracao do PenguinLab. Toda decisao de design, problema encontrado e correcao aplicada esta registrada aqui.*
