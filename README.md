# PenguinLab

O PenguinLab é um sistema de provisionamento para laboratórios de informática escolares (voltado a crianças), com foco em segurança e controle de acesso. Ele transforma uma instalação padrão de Linux Mint (ou Ubuntu) em uma máquina segura para uso por alunos, aplicando três camadas de configuração:

| Camada | O que faz |
|---|---|
| **DNS filtrado** | Usa Cloudflare for Families (`1.1.1.3` / `1.0.0.3`) via `systemd-resolved`, com DNS-over-TLS, bloqueando malware e conteúdo adulto na camada de rede — vale para qualquer navegador ou aplicativo |
| **Firefox restrito** | Aplica políticas empresariais que bloqueiam extensões, navegação privada, `about:config`, ferramentas de desenvolvedor e telemetria, e desabilita o DNS-over-HTTPS do navegador (para que ele use o DNS filtrado do sistema) |
| **Usuário sem privilégios** | Cria o usuário `aluno`, com shell bash normal, mas sem sudo, sem instalar pacotes, sem gerenciar rede, discos ou serviços, e sem login SSH remoto |

## Por que provisionar em vez de gerar uma ISO?

O projeto anterior tentava gerar uma ISO personalizada com live-build. A abordagem se mostrou frágil: problemas com squashfs, kernel panic no boot e complexidade desproporcional ao escopo. A decisão foi abandonar a construção de ISO e usar um **script de provisionamento idempotente** sobre uma instalação padrão e não modificada do sistema. Isso simplifica a manutenção — para atualizar uma máquina, basta executar o script novamente.

## Estrutura do repositório

```
PenguinLab/
|-- provision-penguinlab.sh   # Script principal (idempotente, roda como root)
|-- ansible/
|   |-- playbook.yml          # Aplica o script via SSH em várias máquinas
|   |-- inventory.ini         # Inventário com 14 máquinas de exemplo
|   |-- bootstrap-ssh.sh      # Descobre máquinas na rede e prepara o SSH em lote
|   |-- check-status.sh       # Verifica se as máquinas estão provisionadas
|   '-- ansible.cfg           # Configuração do Ansible (14 execuções em paralelo)
|-- README.md                 # Este arquivo (visão geral)
|-- IMPLANTACAO.md            # Guia prático passo a passo (com ou sem rede)
'-- DOCUMENTACAO.md           # Referência técnica completa
```

## Como funciona, na prática

1. **Instale o Linux Mint** em cada máquina do laboratório (instalação padrão) e crie a conta administrativa **`professor`**.
2. **Ative o OpenSSH server** em cada máquina (ele não vem ativo por padrão).
3. Escolha um dos dois caminhos de aplicação:

- **Com rede (Ansible)** — recomendado quando o notebook e as máquinas estão na mesma rede: provisiona as 14 em paralelo, em poucos minutos.
- **Sem rede (pendrive)** — funciona de qualquer forma: copie o script para um pendrive e execute manualmente em cada máquina.

O passo a passo completo dos dois caminhos está no **IMPLANTACAO.md**. Abaixo, um resumo de cada um.

### Caminho A — com rede (Ansible)

Na máquina de controle (notebook do professor), dentro da pasta `ansible/`:

```bash
# 1. Instale o Ansible (uma vez)
sudo apt install ansible

# 2. Descubra as máquinas e prepare o SSH (pede a senha do professor uma vez por máquina)
./bootstrap-ssh.sh --descobrir 192.168.0        # troque pela faixa da sua rede

# 3. Edite ansible/inventory.ini com os IPs reais encontrados

# 4. Defina a senha do usuário aluno (o padrão é "aluno"; use outra se preferir)
export PENGUINLAB_PASSWORD='aluno'

# 5. Teste em uma única máquina
ansible-playbook -i inventory.ini playbook.yml --limit penguinlab-01 \
  -e "penguinlab_password=$PENGUINLAB_PASSWORD"

# 6. Aplique em todas as máquinas
ansible-playbook -i inventory.ini playbook.yml \
  -e "penguinlab_password=$PENGUINLAB_PASSWORD"

# 7. Verifique (após reiniciar as máquinas)
./check-status.sh
```

> O playbook **não reinicia** as máquinas por padrão — reinicie manualmente depois (ou descomente a tarefa de reboot no fim do `playbook.yml`).

### Caminho B — sem rede (pendrive)

1. Copie `provision-penguinlab.sh` para a raiz de um pendrive.
2. Em cada máquina, logue como `professor`, monte o pendrive e execute:

```bash
cd /media/professor/<NOME_DO_PENDRIVE>/
sudo bash provision-penguinlab.sh
```

3. Reinicie a máquina e confira rapidamente (veja o checklist na seção Verificação).

## Política de senhas do laboratório

| Conta | Senha | Observação |
|---|---|---|
| `aluno` | `aluno` (uniforme em todas as máquinas) | Existe para facilitar o uso pelas crianças; com o **autologin**, essa senha só é usada no desbloqueio de tela. Como a conta não tem privilégio nenhum, o risco é baixo |
| `professor` | **Forte** e igual em todas as máquinas | É a conta com sudo; se vazar, compromete o laboratório inteiro |

- A senha do `aluno` é aplicada em **toda** execução do script — reprovisionar com outro valor atualiza a senha.
- **Nunca** use a mesma senha para `aluno` e `professor`.
- **Nunca** chame a conta de administração de `aluno` — o próprio script bloqueia o sudo dela.

## Verificação pós-deploy

| Verificação | Comando / local | Esperado |
|---|---|---|
| DNS filtrado | `resolvectl status` | `1.1.1.3` e `1.0.0.3` como DNS |
| DNS-over-TLS | `resolvectl status` | `DNSOverTLS: opportunistic` |
| NetworkManager | `grep dns /etc/NetworkManager/conf.d/99-penguinlab-dns.conf` | `dns=systemd-resolved` |
| Firefox restrito | `about:policies` (no navegador) | Restrições listadas |
| Firefox sem DoH próprio | `about:policies` -> `DNSOverHTTPS` | `Enabled: false, Locked: true` |
| `aluno` sem sudo | `sudo -l -U aluno` | "not allowed" / nenhum privilégio |
| `aluno` sem SSH remoto | `ssh aluno@<ip>` (de outra máquina) | Conexão recusada |
| Auto-login do `aluno` | `/etc/lightdm/lightdm.conf` | `autologin-user=aluno` |

Com rede, o `ansible/check-status.sh` faz todas essas verificações em lote.

## Desfazer o provisionamento (rollback)

O procedimento completo está no **IMPLANTACAO.md** (seção Rollback). Em resumo: remova o bloqueio de sudo, as regras polkit, a restrição de SSH, restaure o DNS a partir do backup e remova as políticas do Firefox.

## Avisos e limitações conhecidas

- **Firefox via snap (Ubuntu 24.04+):** o sandboxing do snap pode fazer com que o `policies.json` seja ignorado. Use o Firefox `.deb` (o Linux Mint já vem assim) — veja o guia.
- **Limitação conhecida:** o filtro de DNS não impede que um aluno baixe um AppImage de outro navegador com DNS-over-HTTPS embutido. A mitigação completa (firewall bloqueando endpoints de DoH) está fora do escopo.
- **Sem "reset de sessão":** o que o aluno salvar na home dele (`/home/aluno`) persiste — não há limpeza automática ao religar a máquina.

## Licença

Projeto interno para uso em laboratórios educacionais.