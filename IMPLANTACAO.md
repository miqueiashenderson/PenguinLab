# PenguinLab — Guia Prático de Implantação

Passo a passo completo para colocar o PenguinLab em funcionamento num laboratório de informática escolar (a partir de máquinas com instalação padrão do Linux Mint/Ubuntu).

---

## 1. Visão Geral do Fluxo

```
 ┌────────────────────────────────────────────────────────────────────┐
 │         MÁQUINA DE CONTROLE (notebook/PC do professor)            │
 │  - roda os comandos Ansible, bootstrap e check-status              │
 └───────────────────────────┬────────────────────────────────────────┘
                             │ SSH (porta 22)
         ┌───────────────────┼───────────────────────┐
         ▼                   ▼                       ▼
   ┌──────────┐        ┌──────────┐             ┌──────────┐
   │ Máquina 1│        │ Máquina 2│    ...      │ Máquina N│
   └──────────┘        └──────────┘             └──────────┘
```

**Papéis:**
- **Máquina de controle** — sou notebook/PC do professor. É onde **Ansible** fica instalado e de onde partem todos os comandos.
- **Máquinas do laboratório (hosts)** — as máquinas dos alunos. Precisam apenas de **openssh-server** e **python3**. **NÃO** instalar Ansible nelas.

---

## 2. Pré-requisitos

### Em cada máquina do laboratório (manual, uma vez)
1. Instalar o **Linux Mint** ou **Ubuntu** (instalação padrão, sem customização).
2. Durante ou após a instalação, criar a conta de administração **`professor`** (pode ser outro nome).
   - ⚠️ **NUNCA** chamar essa conta de `aluno` — o provisionamento bloqueia sudo dela e você se tranca.

### Na máquina de controle (notebook)
1. Sistema Linux com **Ansible** e **openssh-client**.
2. (Opcional, automático no bootstrap) uma chave SSH.

---

## 3. Preparando a Máquina de Controle

```bash
# Instalar Ansible
sudo apt install ansible

# Garantir chave SSH (cria se não existir)
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# Clonar/copiar o repositório PenguinLab
git clone <url-do-seu-repositorio> PennyLab   # ou copie a pasta
cd PennyLab/ansible
```

> Todos os próximos comandos são executados a partir da pasta `ansible/` da máquina de controle.

### Definir a senha do `aluno` (obrigatório em produção)

Por padrão o script usa a senha fraca e previsível `aluno`. **Em produção, defina sempre uma senha forte** exportando a variável antes do `ansible-playbook`:

```bash
export PENGUINLAB_PASSWORD='senha-forte-aqui'
ansible-playbook -i inventory.ini playbook.yml -e "penguinlab_password=$PENGUINLAB_PASSWORD"
```

> O playbook propaga `PENGUINLAB_PASSWORD` via `environment:` na task de execução do script, portanto a senha definida aqui é aplicada de fato na máquina remota. Se a variável não for definida, o script imprime um aviso bem visível antes de continuar com a senha padrão.

---

## 4. Catalogando as Máquinas (descobrir IPs)

Depois que as máquinas estiverem ligadas na rede do laboratório, descubra quais têm a porta SSH (22) aberta:

```bash
./bootstrap-ssh.sh --descobrir 192.168.0
```

Ou, se você já souber os IPs, passe-os diretamente:

```bash
./bootstrap-ssh.sh 192.168.0.21 192.168.0.22 192.168.0.23
```

**O que o bootstrap faz em cada máquina (por SSH, pedindo a senha do `professor` na primeira vez):**
- Garante que **openssh-server** está instalado e ativo.
- Garante que **python3** está instalado (exigido pelo Ansible).
- Copia sua **chave pública SSH** para a conta `professor` (login sem senha a partir daí).
- Valida a conexão.

> Para máquinas que seriam adicionadas depois, basta rodar o bootstrap de novo com os novos IPs. Ele é idempotente.

---

## 5. Preencher o Inventário

Edite `ansible/inventory.ini` com os IPs reais encontrados:

```ini
[penguinlab]
penguinlab-01 ansible_host=192.168.0.21
penguinlab-02 ansible_host=192.168.0.22
# ... demais máquinas (adicionar quantas precisar)

[all:vars]
ansible_user=professor
```

- Para **mais de 14 máquinas**: basta adicionar/remover linhas. O número não está fixo no software.
- `ansible_user` deve ser **`professor`** (a conta admin), **nunca** `aluno`.

---

## 6. Testar em UMA Máquina

Sempre teste em uma única máquina antes de liberar para o laboratório inteiro:

```bash
ansible-playbook -i inventory.ini playbook.yml --limit penguinlab-01 \
  -e "penguinlab_password=$PENGUINLAB_PASSWORD"
```

Verifique o resultado manualmente (veja o checklist completo na seção 8).

---

## 7. Aplicar em TODAS as Máquinas

```bash
ansible-playbook -i inventory.ini playbook.yml \
  -e "penguinlab_password=$PENGUINLAB_PASSWORD"
```

O playbook:
1. Copia `provision-penguinlab.sh` para cada máquina.
2. Executa como root (aplica DNS filtrado, políticas do Firefox, usuário `aluno` restrito e **auto-login** do `aluno`).
3. Remove o script temporário.

> **Reinício:** o playbook **não** reinicia por padrão. Para reiniciar automaticamente, descomente a última tarefa em `playbook.yml` (recomendado somente após testar numa máquina isolada).

---

## 8. Verificação Pós-Deploy (Checklist)

Use o script de verificação remota, que confere as máquinas pelo inventário (ou por IPs):

```bash
./check-status.sh                      # usa o inventory.ini
# ou
./check-status.sh 192.168.0.21 192.168.0.22
```

**O que ele confere por máquina:**
- Usuário `aluno` criado e fora dos grupos admin.
- Sudo bloqueado para `aluno`.
- Login SSH remoto do `aluno` bloqueado.
- DNS filtrado configurado (Cloudflare for Families).
- `policies.json` do Firefox presente.
- Regras polkit presentes.
- Auto-login do `aluno` configurado.

Checagens manuais adicionais (se necessário):

| Verificação | Comando (na máquina) | Esperado |
|---|---|---|
| DNS ativo | `resolvectl status` | `1.1.1.3` / `1.0.0.3` |
| DNS sobre TLS | `resolvectl status` | `DNSOverTLS: yes/opportunistic` |
| Firefox policies | `about:policies` no Firefox | restrições ativas |
| Aluno sem sudo | `sudo -l` (como `aluno`) | `not allowed` |
| Aluno nao loga via SSH | `ssh aluno@<ip-da-maquina>` (a partir de outra maquina) | Conexao recusada |
| Aluno não instala pacotes | `pkexec apt install hello` (como `aluno`) | falha / pede admin |

---

## 9. Considerações Importantes

### Firefox via Snap (Ubuntu 24.04+ / alguns Mint)
O Firefox pode vir como **snap**, e o sandboxing pode ignorar o `policies.json`. Troque para a versão `.deb`:

```bash
sudo snap remove firefox
sudo apt install firefox
```

### Rede do laboratório e DNS
O DNS filtrado usa a porta 853 (DNS-over-TLS). Se a rede da escola tiver firewall/proxy bloqueando essa porta, a filtragem degrada. **Teste em uma máquina primeiro.**

### O `aluno` tem terminal livre
O provisionamento não restringe o shell. Se as crianças forem pequenas, considere limitar mais (tarefa futura).

---

## 10. Adicionando Nova Máquina Depois (manutenção)

1. Instale o Mint e crie o `professor`.
2. `./bootstrap-ssh.sh 192.168.0.NN`
3. Adicione a linha no `inventory.ini`.
4. `ansible-playbook -i inventory.ini playbook.yml --limit penguinlab-NN -e "penguinlab_password=$PENGUINLAB_PASSWORD"`

> **Importante:** `$PENGUINLAB_PASSWORD` precisa ser a mesma variável/senha usada no provisionamento original das demais máquinas, para não deixar máquinas com senhas diferentes entre si.

---

## 11. Revertendo (Rollback)

Se precisar desfazer o provisionamento numa máquina:

```bash
# 1. Remover bloqueio de sudo
rm -f /etc/sudoers.d/penguinlab-aluno
visudo -c

# 2. Remover restrições polkit
rm -f /etc/polkit-1/rules.d/90-penguinlab-restrict.rules
systemctl restart polkit

# 3. Remover bloqueio de SSH do aluno
rm -f /etc/ssh/sshd_config.d/90-penguinlab-no-ssh-aluno.conf
sshd -t && (systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true)

# 4. Restaurar DNS padrão
rm -f /etc/NetworkManager/conf.d/99-penguinlab-dns.conf
if [ -f /etc/systemd/resolved.conf.penguinlab.bak ]; then
    mv /etc/systemd/resolved.conf.penguinlab.bak /etc/systemd/resolved.conf
else
    rm -f /etc/systemd/resolved.conf
fi
systemctl restart systemd-resolved NetworkManager

# 5. Remover policies do Firefox
rm -f /etc/firefox/policies/policies.json

# 6. Remover usuário aluno (opcional, remove home também)
userdel -r aluno 2>/dev/null || true
```

---

## 12. Fluxo Resumido (Referência Rápida)

```bash
# 1. Na máquina de controle
sudo apt install ansible
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
export PENGUINLAB_PASSWORD='senha-forte-aqui'

# 2. Na pasta ansible/
./bootstrap-ssh.sh --descobrir 192.168.0      # descobre + prepara SSH
# edite inventory.ini com os IPs

# 3. Teste
ansible-playbook -i inventory.ini playbook.yml --limit penguinlab-01 \
  -e "penguinlab_password=$PENGUINLAB_PASSWORD"

# 4. Aplicar a todas
ansible-playbook -i inventory.ini playbook.yml \
  -e "penguinlab_password=$PENGUINLAB_PASSWORD"

# 5. Verificar
./check-status.sh
```
