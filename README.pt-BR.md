<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**A barra de menus que vale a pena manter na era da IA.**

Veja a pressão das cotas rapidamente e volte ao agent.

[English](README.md) · [中文](README.zh.md) · [Español](README.es.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="Estrelas no GitHub"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Licença MIT"></a>
<img src="https://img.shields.io/github/v/release/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Versão mais recente">

<br />
<br />

<img src="dev_docs/assets/readme-hero-20260724.jpg" width="860" alt="Popover do Kaji na barra de menus" />

</div>

## O que é

Um app de barra de menus para macOS que acompanha **cotas de AI coding** (Claude Code / Cursor / Codex e outros). Os anéis na barra mostram uso e horários de renovação para você perceber a pressão antes de uma execução parar no meio.

Sem dashboard. Sem ícone no Dock. Módulos opcionais para foco e pausas, carga do sistema e metas diárias — desligados até você ativá-los nos Ajustes.

`Kaji` vem do japonês `舵 / かじ` — leme.

## Instalação

```sh
curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
```

Requer macOS 13+ (Apple Silicon), `git` e `swift`. Clona a tag da versão mais recente, compila localmente, remove a quarentena e instala em `/Applications`.

As Releases não incluem `.app.zip` — downloads sem assinatura feitos pelo navegador são bloqueados pelo Gatekeeper. Como alternativa, execute `./scripts/build-local.sh` em um clone.

## Módulos

| Módulo | Padrão | O que oferece |
| --- | --- | --- |
| **Quota** | ligado | Uso de 5h / 7d, renovação, tendência de tokens, estimativa de custo e provedores |
| **Work / Break** | desligado | Timer de foco, contagem regressiva na barra e sobreposição de pausa |
| **System** | desligado | CPU / memória / disco, processos principais e Auto Reclaim conservador |
| **Goals** | desligado | Metas diárias + mapa de calor |
| **Pet** | ponte | Navi opcional via `~/Library/Application Support/Kaji/pet-state.json` |

Tema: somente **Mono** (preto / branco / cinza, claro e escuro).

## Compilação

```sh
swift test
./scripts/build-local.sh
```

## Links

- [Versão mais recente](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md) — notas para contributors / agents
- [dev_docs/](dev_docs/README.md) — specs internas

## Licença

MIT. Consulte [LICENSE](LICENSE).
