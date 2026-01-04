# Android Setup - Enterprise Edition v5.1

Script PowerShell para configuração automática de dispositivos Android para uso com **Carlink**, **Android Auto** e centrais multimídia como o **Geely EX2**.

> **Novidade V4.1**: Fix automático do prompt "Iniciar Agora?" do Carlink via `PROJECT_MEDIA`!

![Android](https://img.shields.io/badge/Android-5.0+-green)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## 📋 Índice

- [Requisitos](#-requisitos)
- [Como Ativar o Modo Desenvolvedor](#-como-ativar-o-modo-desenvolvedor)
- [Instalação e Uso](#-instalação-e-uso)
- [Funcionalidades](#-funcionalidades)
- [Aviso para Xiaomi/Poco/Redmi](#-aviso-para-xiaomipocolredmi)
- [Riscos e Avisos](#-riscos-e-avisos)
- [Troubleshooting](#-troubleshooting)

---

## 🔧 Requisitos

| Item | Descrição |
|------|-----------|
| **Sistema Operacional** | Windows 10/11 |
| **Celular** | Android 5.0+ com Depuração USB ativa |
| **Cabo USB** | Cabo de dados (não apenas carregamento) |
| **Apps Recomendados** | [Taskbar](https://play.google.com/store/apps/details?id=com.farmerbb.taskbar), [SecondScreen](https://play.google.com/store/apps/details?id=com.farmerbb.secondscreen.free), [Shizuku](https://play.google.com/store/apps/details?id=moe.shizuku.privileged.api) (opcional) |

---

## 📱 Como Ativar o Modo Desenvolvedor

### Passo 1: Ativar Opções do Desenvolvedor

1. Vá em **Configurações** > **Sobre o telefone**
2. Toque **7 vezes** no **Número da versão** (ou "Versão MIUI" em Xiaomi)
3. Aparecerá: "Você agora é um desenvolvedor!"

### Passo 2: Ativar Depuração USB

1. Volte para **Configurações**
2. Acesse **Opções do desenvolvedor** (pode estar em Sistema > Avançado)
3. Ative **Depuração USB**

### Passo 3: (XIAOMI/POCO/REDMI APENAS) Ativar Depuração de Segurança

> ⚠️ **CRÍTICO para dispositivos Xiaomi!**

1. Em **Opções do desenvolvedor**
2. Ative **Depuração USB (Configurações de Segurança)**
3. Isso requer login na conta Mi e aceitar os termos

Sem isso, comandos como `wm density` e `settings put` retornarão "Permission Denied".

### Passo 4: Conectar ao PC

1. Conecte o cabo USB ao PC
2. Na notificação USB, selecione **Transferência de arquivos (MTP)**
3. Aceite o prompt **"Permitir depuração USB?"** na tela do celular
4. Marque **"Sempre permitir deste computador"**

---

## 🚀 Instalação e Uso

### Opção 1: Execução Direta

```powershell
# No PowerShell, navegue até a pasta do script
cd F:\Projects\SecondScreenAtive

# Execute o script
powershell -ExecutionPolicy Bypass -File .\setup_android.ps1
```

#### Step 2: The "Ultimate Connection" Flow
1.  **Option `A` (Auto-Install):** Downloads & installs Shizuku, Taskbar, SecondScreen, MacroDroid.
    *   *Opção A: Baixa e instala todos os apps necessários.*
2.  **Option `G` (Geely Optimize):** Sets DPI 280, enables Overlays, and sets Driver App permissions.
    *   *Opção G: Configura DPI 280 e permissões de Drivers.*
3.  **Manual Setup (One-Time):**
    *   Open **Shizuku** -> Start via Wireless Debugging.
    *   Open **SecondScreen** -> Create Profile "Geely EX2" (720p / DPI 280).
    *   Import `Geely_Auto_Connect.xml` into **MacroDroid**.

#### Step 3: Connect & Drive / Conectar e Dirigir
Plug your phone into your car. The automation takes over!
*   *Conecte no carro e a automação assume o comando!*

---

## 🧹 Clean Slate (Reset)

Mess up? Want to sell the phone? Use **Option `X`** in the Advanced Menu to verify/restore factory rendering settings without losing your data.
*   *Errou algo? Vai vender o celular? Use a **Opção X** para restaurar as configurações originais de visualização sem perder seus dados.*

---

## 🤝 Contributing / Contribua!

We want to make this the #1 suite for Carlink users worldwide!
Queremos tornar isso a suíte #1 para usuários Carlink no mundo todo!

*   **Ideas?** Open an [Issue](issues).
*   **Code?** Send a [Pull Request](pulls).
*   **Feedback?** Tell us how it works on your BYD, GWM, or other car models!

---

**Developed with ❤️ for the Geely Community.**
*Desenvolvido com ❤️ para a Comunidade Geely.*

Tags: `android` `adb` `carlink` `geely-ex2` `hyperos` `oneui` `desktop-mode` `debloat` `shizuku` `automation`

---

## ⚠️ Aviso para Xiaomi/Poco/Redmi

Dispositivos com **HyperOS** ou **MIUI** têm uma camada extra de segurança. Se você receber erros de "Permission Denied":

1. **Abra Opções do Desenvolvedor**
2. **Role até encontrar "Depuração USB (Configurações de Segurança)"**
3. **Ative essa opção** (requer login na conta Xiaomi)
4. **Aguarde 7 dias** (em alguns casos, a Xiaomi exige esse período)

---

## 🛡️ Riscos e Avisos

### 🟢 Risco Baixo (Totalmente Reversível)

| Função | Como Reverter |
|--------|---------------|
| DPI alterado | `adb shell wm density reset` |
| Modo Imersivo | `adb shell settings put global policy_control immersive.off=*` |
| Modo Noturno | Configurações > Tela > Tema |
| Animações | Configurações > Opções do desenvolvedor > Escalas |

### 🟡 Risco Médio (Reversível com Cuidado)

| Função | Descrição | Como Reverter |
|--------|-----------|---------------|
| **Debloat** | Apps são desativados apenas para seu usuário | Use "Restaurar Apps" no menu ou `adb shell cmd package install-existing [pacote]` |
| **Overscan** | Pode deixar tela esquisita | `adb shell wm overscan reset` |
| **Stop Logd** | Para logs do sistema | Reinicie o celular |

### 🔴 O que NÃO é feito (Segurança)

- ❌ **Não faz root**
- ❌ **Não desbloqueia bootloader**
- ❌ **Não remove apps de sistema permanentemente**
- ❌ **Não modifica partições do sistema**

Todos os comandos usam `--user 0`, que significa que afetam apenas o usuário atual. Os APKs originais permanecem no sistema.

---

## 🔧 Troubleshooting

### "Nenhum dispositivo detectado"

1. Troque o cabo USB (use um de dados, não só carregamento)
2. Troque de porta USB no PC
3. Verifique se "Depuração USB" está ativa
4. Verifique se o modo USB é "Transferência de arquivos"

### "Dispositivo não autorizado"

1. Olhe a tela do celular
2. Aceite o prompt "Permitir depuração USB?"
3. Marque "Sempre permitir deste computador"

### "Permission Denied" (Xiaomi)

1. Ative "Depuração USB (Configurações de Segurança)"
2. Pode exigir login na conta Xiaomi
3. Em alguns casos, aguarde 7 dias após ativar

### Apps somem no Carlink

Os apps podem estar sendo mortos pelo sistema. O script já adiciona à whitelist de bateria, mas você pode:

1. Configurações > Apps > Taskbar > Bateria > Sem restrições
2. Em Xiaomi: Configurações > Apps > Gerenciar apps > Taskbar > Economia de bateria > Sem restrições

### DPI muito alto/baixo

```powershell
# Restaurar DPI padrão
adb shell wm density reset
```

### Tela cortada no Carlink

Use a opção "Configurações de Tela > Ajustar Overscan" no menu avançado.

---

## 📁 Estrutura do Projeto

```
SecondScreenAtive/
├── setup_android.ps1    # Script principal
├── README.md            # Este arquivo
├── apks/                # Pasta para APKs (instalação em lote)
└── setup_log_*.txt      # Logs de execução
```

---

## 📝 Logs

O script cria automaticamente um arquivo de log com timestamp em:
```
F:\Projects\SecondScreenAtive\setup_log_YYYYMMDD_HHMMSS.txt
```

Use para diagnóstico em caso de problemas.

---

## 🤝 Contribuindo

1. Fork o repositório
2. Crie uma branch: `git checkout -b feature/nova-funcao`
3. Commit: `git commit -m 'Adiciona nova função'`
4. Push: `git push origin feature/nova-funcao`
5. Abra um Pull Request

---

## 📄 Licença

MIT License - Veja [LICENSE](LICENSE) para detalhes.

---

## 📞 Suporte

- **Problemas?** Abra uma [Issue](https://github.com/seu-usuario/SecondScreenAtive/issues)
- **Dúvidas?** Consulte a seção [Troubleshooting](#-troubleshooting)

---

**Desenvolvido para uso com Geely EX2 e centrais multimídia compatíveis com Carlink/Android Auto.**
