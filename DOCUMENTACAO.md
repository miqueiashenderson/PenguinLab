# PenguinLab — Documentação Técnica

Referência completa do projeto PenguinLab: decisões de arquitetura, funcionamento interno de cada script, modelo de segurança, problemas conhecidos e materiais de estudo. Para o passo a passo de implantação, consulte o **IMPLANTACAO.md**; para a visão geral, o **README.md**.

---

## 1. Visão geral

O PenguinLab é um sistema de provisionamento para laboratórios de informática escolares. Ele aplica três camadas de restrição em cada máquina, sobre uma instalação padrão e não modificada do Linux Mint (ou Ubuntu):

| Camada | O que faz |
|---|---|
| **DNS filtrado** | Cloudflare for Families (`1.1.1.3` / `1.0.0.3`) via `systemd-resolved`, com DNS-over-TLS (`opportunistic`) |
| **Firefox restrito** | Políticas empresariais: extensões bloqueadas, navegação privada desabilitada, DNS-over-HTTPS travado, ferramentas de desenvolvedor bloqueadas, telemetria desativada |
| **Usuário sem privilégios** | Usuário `aluno` com shell bash normal, mas sem sudo, sem ações administrativas via polkit, com login SSH remoto bloqueado e auto-login no LightDM |

---

## 2. Decisões de arquitetura

### Por que não gerar uma ISO?

A abordagem anterior (live-build + squashfs + GRUB/isolinux) era frágil demais: problemas com kernel panic no boot, pacotes essenciais removidos pelo `autoremove` e complexidade desproporcional ao escopo. A substituição por um script de provisionamento foi motivada por:

- **Simplicidade:** roda sobre uma instalação padrão, sem build customizado.
- **Idempotência:** pode ser executado várias vezes sem duplicar configurações.
- **Atualização fácil:** para mudar a configuração, basta rodar o script de novo.
- **Escala:** o Ansible aplica o mesmo script em 14 máquinas em paralelo.

### Por que `DNSOverTLS=opportunistic` e não `yes`?

`opportunistic` tenta usar DNS-over-TLS e, se a rede bloquear a porta 853 (alguns firewalls/proxies de escola), degrada para DNS comum em vez de quebrar a resolução. A filtragem de conteúdo continua valendo nos dois casos (ela é feita na camada de DNS, independente do TLS).

### Por que polkit em formato JS?

O Ubuntu 24.04+ não instala `polkitd-pkla` por padrão — arquivos `.pkla` são **silenciosamente ignorados**. O formato moderno de regras (`/etc/polkit-1/rules.d/*.rules`, JavaScript) é o suportado atualmente e é o que o script usa.

---

## 3. Estrutura de arquivos

```
PenguinLab/
|-- provision-penguinlab.sh    # Script principal (idempotente, roda como root)
|-- ansible/
|   |-- playbook.yml           # Aplica o script via SSH nas máquinas
|   |-- inventory.ini          # Inventário (14 máquinas de exemplo)
|   |-- bootstrap-ssh.sh       # Descobre IPs e prepara o SSH em lote
|   |-- check-status.sh        # Verifica o estado de provisão remotamente
|   |-- specs.yml              # Coleta especificações (CPU/RAM/disco) por máquina
|   |-- collect-specs.sh       # Executa o specs.yml e formata a saída em tabela
|   '-- ansible.cfg            # forks=14, timeout, host_key_checking
|-- README.md                  # Visão geral
|-- IMPLANTACAO.md             # Guia prático (com e sem rede)
'-- DOCUMENTACAO.md            # Este arquivo
```

---

## 4. O `provision-penguinlab.sh` em detalhe

### 4.1 Execução e pré-requisitos

- Deve ser executado como **root** (`sudo bash provision-penguinlab.sh`); a função `check_root` aborta caso contrário.
- Usa `set -euo pipefail`: qualquer erro interrompe a execução com mensagem clara.
- Grava o log em `/var/log/penguinlab-provision.log` (append a cada execução).
- É **idempotente** — reprovisionar não duplica configurações.

### 4.2 Funções

| Função | O que faz |
|---|---|
| `check_root()` | Verifica se o script roda como root; aborta com instrução caso contrário |
| `init_log()` | Cria o diretório e abre o log com um cabeçalho datado |
| `setup_dns()` | Ativa o `systemd-resolved` (se necessário), escreve `/etc/systemd/resolved.conf` com os DNS filtrados e `DNSOverTLS=opportunistic` (fazendo backup do original em `resolved.conf.penguinlab.bak`), garante que `/etc/resolv.conf` aponte para o stub do systemd-resolved, e impede o NetworkManager de sobrescrever o DNS via `/etc/NetworkManager/conf.d/99-penguinlab-dns.conf` |
| `setup_firefox()` | Verifica se o Firefox existe (e se é snap), e escreve `/etc/firefox/policies/policies.json` com todas as restrições |
| `setup_user()` | Cria o usuário `aluno` (idempotente), **aplica a senha em toda execução**, garante o shell bash, remove dos grupos `sudo`/`admin`/`wheel`, bloqueia sudo via `/etc/sudoers.d/penguinlab-aluno` (validado com `visudo`) e aplica regras polkit JS |
| `setup_ssh_restriction()` | Escreve `/etc/ssh/sshd_config.d/90-penguinlab-no-ssh-aluno.conf` com `DenyUsers aluno`, valida com `sshd -t` e recarrega o serviço |
| `setup_autologin()` | Configura o auto-login do `aluno` em `/etc/lightdm/lightdm.conf` (seção `[Seat:*]`) e adiciona o usuário ao grupo `autologin` (quando o grupo existe) |
| `setup_hostname()` | Se `PENGUINLAB_HOSTNAME` estiver definido, define o hostname da máquina via `hostnamectl` e ajusta `/etc/hosts` (remove a entrada antiga `127.0.1.1` e adiciona a nova). Com valor vazio (padrão), mantém o hostname atual |
| `summary()` | Imprime o resumo final do que foi aplicado |
| `main()` | Orquestra: `check_root` -> `init_log` -> `setup_hostname` -> `setup_dns` -> `setup_firefox` -> `setup_user` -> `setup_ssh_restriction` -> `setup_autologin` -> `summary` |

### 4.3 Variáveis de configuração

| Variável | Padrão | Descrição |
|---|---|---|
| `LOGFILE` | `/var/log/penguinlab-provision.log` | Caminho do log |
| `USUARIO` | `aluno` | Nome do usuário limitado |
| `SENHA_ALUNO` | `PENGUINLAB_PASSWORD` (ou `aluno`) | Senha do usuário limitado |
| `HOSTNAME_PENGUINLAB` | `PENGUINLAB_HOSTNAME` (vazio) | Hostname padrão a aplicar; vazio = manter o atual |
| `DNS_PRIMARIO` | `1.1.1.3` | Cloudflare for Families (primário) |
| `DNS_SECUNDARIO` | `1.0.0.3` | Cloudflare for Families (secundário) |
| `HOMEPAGE` | `https://www.google.com.br` | Homepage travada no Firefox |

**Aviso de senha padrão:** se `PENGUINLAB_PASSWORD` não for definida, o script usa `aluno` como senha e imprime um aviso bem visível — comportamento esperado neste projeto, que adota senha uniforme `aluno` para facilitar o uso pelas crianças (a conta não tem privilégios; ver seção 8).

### 4.4 Arquivos criados/alterados em cada máquina

| Arquivo | Camada |
|---|---|
| `/etc/systemd/resolved.conf` (+ `.penguinlab.bak`) | DNS |
| `/etc/NetworkManager/conf.d/99-penguinlab-dns.conf` | DNS |
| `/etc/firefox/policies/policies.json` | Firefox |
| `/etc/sudoers.d/penguinlab-aluno` | Usuário |
| `/etc/polkit-1/rules.d/90-penguinlab-restrict.rules` | Usuário |
| `/etc/ssh/sshd_config.d/90-penguinlab-no-ssh-aluno.conf` | SSH |
| `/etc/lightdm/lightdm.conf` | Auto-login |
| `/etc/hostname` e `/etc/hosts` | Identificação (hostname padrão `penguinlab-XX`) |

---

## 5. Ansible

### 5.1 `playbook.yml`

Quatro tarefas, todas com `become: true` (executam como root):

1. **Copiar o script** -> `provision-penguinlab.sh` para `/tmp/` (modo 0755).
2. **Executar** -> `/tmp/provision-penguinlab.sh` com `PENGUINLAB_PASSWORD` (senha do aluno) e `PENGUINLAB_HOSTNAME` (o **nome do host no inventário**, ex.: `penguinlab-05`) no ambiente da tarefa — o script define o hostname da máquina conforme esse valor.
3. **Exibir resultado** -> imprime a saída do script no terminal do notebook (via `debug`).
4. **Remover o temporário** -> apaga `/tmp/provision-penguinlab.sh`.

Resultado: cada máquina fica identificada como `penguinlab-01`…`penguinlab-14` — o nome aparece na própria máquina (prompt do terminal, `hostname`, telas de login) e casa com o IP do inventário.

A última tarefa (reiniciar as máquinas) está comentada por padrão — o reinício fica sob controle do administrador.

> **Atenção ao mapeamento IP:** o hostname é derivado do nome do host no inventário — se o IP mudar (DHCP), o nome continua o mesmo, mas o IP que você usa para alcançá-lo muda. Configure **reserva DHCP** ou IP estático para o mapeamento nome ↔ IP permanecer correto.

### 5.2 `inventory.ini`

- Grupo `[penguinlab]` com 14 hosts de exemplo (`penguinlab-01`…`penguinlab-14`, IPs `192.168.0.21`–`192.168.0.34`).
- `[all:vars]` -> `ansible_user=professor` (a conta administrativa — **nunca** `aluno`).
- Os IPs de exemplo devem ser substituídos pelos reais do laboratório.
- Os nomes dos hosts NO inventário viram os hostnames das máquinas após o playbook (tarefa 5 acima) — revise os nomes antes de provisionar.

### 5.3 `ansible.cfg`

```ini
[defaults]
forks = 14            # provisão das 14 máquinas em paralelo
host_key_checking = False
timeout = 15
```

### 5.4 `specs.yml`

Playbook **somente leitura** (não altera nada nas máquinas) que coleta as especificações de todas as máquinas via *facts* do Ansible e escreve um CSV no notebook:

- **Fonte dos dados:** facts automáticos (`ansible_distribution`, `ansible_processor`, `ansible_processor_cores/vcpus`, `ansible_memtotal_mb`) + `lsblk -d -b` somado para o disco total.
- **Saída:** `/tmp/penguinlab-specs.csv` na máquina de controle, com uma linha por máquina: `nome;ip;hostname_real;sistema;cpu;nucleos;threads;ram_mb;disco_gb`.
- **Uso:** `ansible-playbook -i inventory.ini specs.yml` ou, mais prático, `./collect-specs.sh` (seção 6.3).

O CSV é gerado por um único template (`run_once: true` + `delegate_to: localhost`) sobre os hosts do lote — assim funciona também com `--limit` para uma máquina isolada.

---

## 6. Scripts auxiliares

### 6.1 `bootstrap-ssh.sh`

Prepara as máquinas após a instalação manual do sistema. Executado no notebook (máquina de controle).

- **Descoberta:** opção `--descobrir <faixa>` varre uma sub-rede `/24` testando a porta 22 via TCP (`echo >/dev/tcp/<ip>/22`), com até 50 conexões concorrentes. Alternativamente, os IPs podem ser passados diretamente como argumentos.
- **Checagem de SSH:** antes de qualquer comando remoto, testa a porta 22 de cada host. Se fechada (comum em instalações novas, onde o `sshd` vem desativado), imprime a orientação completa (`sudo apt install -y openssh-server && sudo systemctl enable --now ssh`), **pula a máquina e continua o lote**.
- **Preparação:** garante `openssh-server` e `python3` (esforço máximo, sem falha fatal), copia a chave pública do notebook para a conta `professor` (via `ssh-copy-id`) e valida o login sem senha.
- **Chave:** gera automaticamente `~/.ssh/id_ed25519` se ainda não existir.
- **Configuração:** `USUARIO_ADMIN` (padrão `professor`, via `PENGUINLAB_ADMIN`), log em `bootstrap-ssh.log`.
- **Resultado gravado:** os IPs com bootstrap completo (SSH sem senha validado) são **acumulados** em `hosts-ok.txt` na pasta `ansible/` (uma IP por linha, sem duplicatas entre execuções) — serve de base para montar o `inventory.ini`. O arquivo é específico do laboratório e não vai para o repositório (gitignored).

### 6.2 `check-status.sh`

Verifica remotamente se cada máquina está provisionada. Usa o `inventory.ini` (extraindo `ansible_host`) ou IPs passados como argumentos.

Checagens por máquina:
1. Conexão SSH e existência do usuário `aluno`.
2. `aluno` fora dos grupos `sudo`/`admin`/`wheel`.
3. Sudo bloqueado para `aluno` (procura "not allowed"/`!ALL`).
4. DNS filtrado presente em `/etc/systemd/resolved.conf`.
5. `policies.json` do Firefox presente.
6. Regras polkit presentes.
7. Auto-login do `aluno` configurado no LightDM.
8. Bloqueio de SSH remoto do `aluno` presente.

Saída com `[OK]`/`[FALHA]` por checagem e resumo final (`X/Y maquinas totalmente OK`).

### 6.3 `collect-specs.sh`

Wrapper do `specs.yml`: roda a coleta e formata o CSV em colunas alinhadas com `column -t -s ';'`. Uso:

```bash
./collect-specs.sh                          # todas as máquinas do inventário
./collect-specs.sh --limit penguinlab-01    # uma máquina apenas
```

Saída exemplo:

```
nome           ip            hostname_real  sistema              cpu                        nucleos  threads  ram_mb  disco_gb
penguinlab-01  192.168.0.21  penguinlab-01  LinuxMint 21.3       Intel(R) Core(TM) i3-...  2        4        7885    238.5
```

Útil para preencher a tabela de catalogação do laboratório (seção 3.3 do IMPLANTACAO.md) sem ir máquina por máquina.

---

## 7. Modelo de segurança

### O que o `aluno` pode fazer

- Usar o desktop normalmente (navegador restrito, aplicativos comuns, terminal **livre** — o shell não é restrito).
- Salvar arquivos na própria home (`/home/aluno`).

### O que o `aluno` não pode fazer

| Ação | Mecanismo de bloqueio |
|---|---|
| `sudo` / virar root | `/etc/sudoers.d/penguinlab-aluno` (`aluno ALL=(ALL) !ALL`) |
| Instalar pacotes | Regra polkit (prefixo `org.freedesktop.packagekit.`) |
| Alterar rede/Wi-Fi | Regra polkit (prefixo `org.freedesktop.NetworkManager.`) |
| Montar discos/pendrives | Regra polkit (prefixo `org.freedesktop.udisks2.`) |
| Gerenciar serviços systemd | Regra polkit (prefixo `org.freedesktop.systemd1.`) |
| Login SSH remoto | `DenyUsers aluno` no sshd |

### A conta `professor`

Não é alterada pelo provisionamento (apenas perde o auto-login, se existisse). Mantém sudo e acesso total. É a conta usada pelo Ansible — por isso a senha dela deve ser forte e **nunca** igual à do `aluno`.

### Auto-login

O `aluno` entra automaticamente ao ligar a máquina. Como consequência, a senha do `aluno` só é usada no desbloqueio de tela (se o bloqueio estiver ativado) e em logouts manuais.

---

## 8. Política de senhas (decisões registradas)

| Conta | Senha | Justificativa |
|---|---|---|
| `aluno` | `aluno`, uniforme em todas as máquinas | Facilidade para crianças digitarem no desbloqueio de tela. Risco aceitável: a conta é totalmente sem privilégios, sem SSH remoto, e o DNS/navegador continuam filtrados |
| `professor` | Forte, igual em todas as máquinas | É a conta com sudo; uma única senha forte é mais simples de gerenciar. Deve ser guardada com cuidado |

- A senha do `aluno` é aplicada em **toda** execução do script (não só na criação do usuário), portanto reprovisionar com outro valor a atualiza.
- O `PENGUINLAB_PASSWORD` precisa ser passado ao script via ambiente; no Ansible, o playbook o propaga via `environment:`; no pendrive, deve ser passado junto do `sudo` (`sudo PENGUINLAB_PASSWORD='...' bash ...`), pois o `sudo` limpa variáveis de ambiente por padrão.

---

## 9. Rede: cenários e implicações técnicas

- **Mesmo roteador (wifi e cabo na mesma sub-rede):** o notebook no wifi alcança as máquinas cabeadas normalmente; o `--descobrir` e o Ansible funcionam sem ajustes.
- **Sub-redes separadas (ou VLANs com firewall):** o notebook não alcança as máquinas — nem o `--descobrir` (ele varre uma única faixa `/24`), nem o SSH. Soluções: plugar o notebook no cabo, usar um travel router em modo bridge, ou adotar o provisionamento por pendrive.
- **Porta 853 (DNS-over-TLS):** se a rede da escola bloquear a porta 853, o DNS muda (via `opportunistic`) para DNS comum — a filtragem de conteúdo continua, pois é feita na camada de resolução.
- **AP isolation / guest networks:** em redes com isolamento de cliente, mesmo na mesma faixa o tráfego entre dispositivos pode ser bloqueado; nesse caso, o notebook deve entrar na rede via cabo/travel router.

---

## 10. Problemas encontrados e corrigidos

| Problema | Severidade | O que acontecia | Correção |
|---|---|---|---|
| Self-lockout no Ansible | Crítico | `ansible_user=aluno` + `!ALL` no sudo travava o Ansible após a primeira execução | Documentar `ansible_user=professor` como obrigatório |
| `polkit` `.pkla` ignorado | Crítico | Ubuntu 24.04 não tem `polkitd-pkla`; regras `.pkla` eram ignoradas silenciosamente | Migrar para regras JS em `/etc/polkit-1/rules.d/` |
| Chaves JSON duplicadas | Moderado | `DisableSystemAddonUpdate`, `DisableTelemetry` etc. duplicados no `policies.json` | Reorganizar e remover duplicatas |
| Log sobrescrito | Menor | `init_log()` usava `>` (sobrescrevia) | Trocar para `>>` (append) |
| Chave SSH sobrescrita no bootstrap | Crítico | `ssh-keygen` respondia "y" ao prompt de sobrescrita, invalidando acessos existentes | Gerar chave apenas se ainda não existir |
| Checagem de grupos admin nunca rodava | Alto | Condição externa morta no `check-status.sh` | Remover o `if` externo |
| Doc de autologin desatualizada | Moderado | Doc citava `slick-greeter.conf`; script usa `lightdm.conf` | Alinhar documentação ao código |
| SSH remoto do `aluno` liberado | Alto (segurança) | `aluno` podia autenticar via SSH remotamente | Nova função `setup_ssh_restriction()` com `DenyUsers` |
| Senha padrão previsível | Moderado (segurança) | Todas usavam `aluno`/`aluno` se `PENGUINLAB_PASSWORD` não definida | Aviso visível + documentação exigindo senha adequada em produção |
| `resolved.conf` sobrescrito sem backup | Baixo | Configuração DNS original perdida permanentemente | Backup automático antes de sobrescrever |
| Detecção de polkit falha (`dpkg -l`) | Baixo | `dpkg -l` retornava 0 mesmo com pacote removido | Trocar para `dpkg -s` com checagem de status |
| Senha do `aluno` não atualizada em re-execução | Moderado | `chpasswd` rodava apenas na criação do usuário | Aplicar `chpasswd` em toda execução do `setup_user` |
| Bootstrap cego quando `sshd` inativo | Alto (fluxo) | Instalação nova não ativa `sshd`; bootstrap falhava de forma genérica ou nem achava a máquina | Checar a porta 22 com orientação explícita (`apt`/`systemctl`) e pular a máquina |

---

## 11. Limitações conhecidas

- **Bypass de DNS via outros navegadores/AppImages:** o filtro de DNS e as políticas do Firefox **não** impedem que o `aluno` baixe um AppImage de outro navegador com DNS-over-HTTPS embutido, contornando a filtragem na camada de rede. A mitigação completa (firewall bloqueando endpoints/portas de DoH conhecidos) está **fora do escopo**.
- **Firefox via snap (Ubuntu 24.04+):** o sandboxing do snap pode fazer com que o `policies.json` em `/etc/firefox/policies/` seja ignorado. O script detecta e avisa. Solução: trocar para o `.deb` (`sudo snap remove firefox && sudo apt install firefox`) — o Linux Mint já vem com o Firefox `.deb`, por isso é a distribuição recomendada.
- **Sem reset de sessão:** não há limpeza automática de `/home/aluno` ao religar — os arquivos do aluno persistem.
- **polkit ausente:** se `polkitd` não estiver instalado, o script avisa e segue (as restrições polkit não são aplicadas nessa máquina, sem erro fatal).
- **Shell do aluno é livre:** o provisionamento não restringe o terminal. Para crianças muito pequenas, uma limitação adicional seria uma evolução futura.

---

## 12. Verificação e diagnóstico

- **Em lote (com rede):** `ansible/check-status.sh` — 8 checagens por máquina com resumo final.
- **Manual:** tabela da seção 7 do **IMPLANTACAO.md** (DNS, Firefox, sudo, SSH, polkit, auto-login).
- **Logs:** `/var/log/penguinlab-provision.log` em cada máquina; `bootstrap-ssh.log` no notebook.
- **Problema comum:** máquina não aparece no `--descobrir` -> quase sempre é o `sshd` desativado (execute o passo 3.2 do IMPLANTACAO e rode o bootstrap de novo).

---

## 13. Referências de estudo

### Linux / Systemd
- systemd-resolved — https://www.freedesktop.org/software/systemd/man/systemd-resolved.html
- NetworkManager + systemd-resolved — https://developer.gnome.org/NetworkManager/stable/nm-dns.html

### Shell Scripting (Bash)
- Advanced Bash-Scripting Guide — https://tldp.org/LDP/abs/html/
- Bash Reference Manual — https://www.gnu.org/software/bash/manual/bash.html

### Políticas Firefox Enterprise
- Enterprise Policy documentation — https://mozilla-policy.readthedocs.io/en/latest/
- policies.json reference — https://mozilla-policy.readthedocs.io/en/latest/policies_json/

### polkit (PolicyKit)
- polkit documentation — https://www.freedesktop.org/wiki/Software/polkit/
- polkit rules (formato JS) — https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html

### Ansible
- Documentação oficial — https://docs.ansible.com/ansible/latest/index.html
- Playbooks — https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html
- Inventário — https://docs.ansible.com/ansible/latest/inventory_guide/index.html
- Escalação de privilégios (become) — https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html

### Linux Mint / LightDM / Slick Greeter
- LightDM — https://wiki.lightdm.org/
- Slick Greeter — https://github.com/linuxmint/slick-greeter

### Redes e DNS
- Cloudflare for Families — https://developers.cloudflare.com/1.1.1.1/
- DNS-over-TLS — https://developers.cloudflare.com/1.1.1.1/dns-over-tls/
- RFC 8484 — DNS Queries over HTTPS — https://datatracker.ietf.org/doc/html/rfc8484

---

*Documentação técnica do PenguinLab. Toda decisão de design, problema encontrado e correção aplicada está registrada neste arquivo.*