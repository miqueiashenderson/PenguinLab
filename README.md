# PenguinLab

Sistema de provisionamento para laboratorios de informatica escolares (criancas), com foco em seguranca e controle de acesso.

## O que faz

O PenguinLab aplica tres configuracoes essenciais em maqinas Ubuntu/Mint:

| Configuracao | O que faz |
|---|---|
| **DNS Filtrado** | Usa Cloudflare for Families (`1.1.1.3` / `1.0.0.3`) via `systemd-resolved` com DNS-over-TLS para bloquear malware e conteudo adulto na camada de DNS. |
| **Firefox Restrito** | Aplica politicas enterprise que bloqueiam extensoes, navegacao privada, `about:config`, developer tools, e desabilita DNS-over-HTTPS (para que o Firefox use o DNS filtrado do sistema). |
| **Usuario sem admin** | Cria o usuario `aluno` com shell normal (bash) mas sem privilegios administrativos — sem `sudo`, sem montagem de discos, sem instalacao de pacotes, sem gerenciamento de servicos. |

## Por que "provisionar" e nao "gerar ISO"?

O projeto anterior tentava gerar uma ISO customizada com live-build. A abordagem se mostrou fragil demais — problemas com squashfs, kernel panic no boot, e complexidade desproporcional ao escopo. A decisao foi abandonar a construcao de ISO e usar um **script de provisionamento** que roda em cima de uma instalacao padrao e nao modificada do Ubuntu ou Linux Mint. Isso simplifica drasticamente a manutencao e elimina problemas de boot.

## Estrutura do repositorio

```
PenguinLab/
├── provision-penguinlab.sh    # script principal, idempotente, roda com sudo
├── ansible/
│   ├── playbook.yml           # aplica o script via SSH nas maquinas do lab
│   └── inventory.ini          # inventario com 14 maquinas de exemplo
├── README.md
└── .gitignore
```

## Uso manual (uma maquina)

1. Copie o script para a maquina alvo (usando a conta admin, nao `aluno`):
   ```bash
   scp provision-penguinlab.sh professor@192.168.0.21:/tmp/
   ```

2. Conecte-se via SSH e execute como root:
   ```bash
   ssh professor@192.168.0.21
   sudo /tmp/provision-penguinlab.sh
   ```

3. Reinicie a maquina para garantir que todas as configuracoes tenham efeito:
   ```bash
   sudo reboot
   ```

O script e idempotente — pode ser executado varias vezes sem duplicar configuracoes.

## Conta de administracao (critico)

**NUNCA** use o usuario `aluno` para executar o script ou conectar via Ansible. O proprio script bloqueia sudo desse usuario — se voce usar `aluno` como `ansible_user`, o Ansible vai travar apos a primeira execucao (falta de permissao para `become`).

Use sempre a conta admin criada durante a instalacao do Ubuntu/Mint (ex: `professor`, `admin`, ou o primeiro usuario que voce criou quando instalou o sistema). Configure-a no `ansible/inventory.ini`:

```ini
[all:vars]
ansible_user=professor
```

## Uso via Ansible (14 maquinas)

### Pre-requisitos

1. Instale o Ansible na maquina de controle (professor):
   ```bash
   sudo apt install ansible
   ```

2. Configure o acesso SSH por chave publica em cada maquina do laboratorio:
   ```bash
   # Para cada maquina (exemplo com penguinlab-01):
   ssh-copy-id professor@192.168.0.21
   ```

3. Edite `ansible/inventory.ini` com os IPs reais das maquinas.

### Execucao

**Teste em uma unica maquina primeiro:**
```bash
cd ansible/
ansible-playbook -i inventory.ini playbook.yml --limit penguinlab-01
```

**Executar em todas as 14 maquinas:**
```bash
cd ansible/
ansible-playbook -i inventory.ini playbook.yml
```

### Reiniciar as maquinas (opcional)

Por padrao, o playbook **nao** reinicia as maquinas. Para habilitar o reinicio automatico, descomente a ultima tarefa em `ansible/playbook.yml`.

## Aviso: Firefox via snap

No Ubuntu 24.04+, o Firefox e instalado por padrao via **snap**. Devido ao sandboxing do snap, o arquivo `policies.json` em `/etc/firefox/policies/` pode nao ser respeitado corretamente. O script de provisionamento detecta isso e exibe um aviso.

Recomendacao: trocar para a versao `.deb`/apt tradicional do Firefox:
```bash
sudo snap remove firefox
sudo apt install firefox
```

## Pos-deploy — checklist de verificacao

Apos cada execucao do provisionamento, validar se tudo ficou correto antes de liberar a maquina para os alunos:

| Verificacao | Comando | Esperado |
|---|---|---|
| DNS ativo | `resolvectl status` | Lista `1.1.1.3` e `1.0.0.3` como DNS |
| DNSOverTLS | `resolvectl status` | `DNSOverTLS: yes` (ou `opportunistic`) |
| NetworkManager respeita resolved | `grep dns /etc/NetworkManager/conf.d/99-penguinlab-dns.conf` | `dns=systemd-resolved` |
| Firefox policies | Abrir `about:policies` no Firefox | Todas as restricoes visiveis |
| Firefox sem seu proprio DNS | `about:policies` → `DNSOverHTTPS` | `Enabled: false, Locked: true` |
| Usuario nao tem sudo | `sudo -l` (como `aluno`) | `not allowed` |
| polkit bloqueia NM | `pkexec nm-connection-editor` (como `aluno`) | Pede senha de admin ou falha |
| polkit bloqueia install | `pkexec apt install hello` (como `aluno`) | Falha / pede senha |
| Shell do aluno livre | `su - aluno` → `echo $SHELL` | `/bin/bash` |

### Rollback — desfazer provisao manualmente

Se precisar reverter o provicionamento em uma maquina:

```bash
# 1. Remover bloqueio de sudo
rm -f /etc/sudoers.d/penguinlab-aluno
visudo -c   # validar antes de continuar

# 2. Remover restricoes de polkit
rm -f /etc/polkit-1/rules.d/90-penguinlab-restrict.rules
systemctl restart polkit

# 3. Restaurar DNS padrao
rm -f /etc/NetworkManager/conf.d/99-penguinlab-dns.conf
rm -f /etc/systemd/resolved.conf
systemctl restart systemd-resolved NetworkManager

# 4. Remover policies do Firefox
rm -f /etc/firefox/policies/policies.json

# 5. Remover usuario aluno (opcional — remove home tbm)
userdel -r aluno 2>/dev/null || true
```

## Licenca

Este e um projeto interno para uso em laboratorios educacionais.
