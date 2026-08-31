<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**A camada pessoal de estado e controle para um Mac nativo de IA.**

O que importa hoje, a um olhar de distância.

[English](README.md) · [中文](README.zh.md) · [Español](README.es.md)

<a href="https://github.com/MisterBrookT/kaji/stargazers"><img src="https://img.shields.io/github/stars/MisterBrookT/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="Estrelas no GitHub"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Licença MIT"></a>
<img src="https://img.shields.io/github/v/release/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Versão mais recente">

</div>

https://github.com/user-attachments/assets/a345bc3f-d74e-4092-8e8f-5730b154d39c

## O que é

O Kaji coloca na **barra de menus** os estados vivos que importam para você. Isso inclui cotas de IA, foco, metas e o seu Mac.

Por que a barra de menus? Porque ela permanece ao lado do que você já está fazendo: olhe para saber, passe o cursor para obter contexto e clique para agir. Sem trocar de app e sem uma notificação exigindo atenção.

O Kaji começa pequeno. Quota vem ligado. Os outros módulos são opcionais. Um só shell. Apenas os sinais que você escolhe manter por perto.

`Kaji` vem do japonês `舵 / かじ`. Significa leme.

[Leia a visão](dev_docs/product/vision.md).

## Instalação

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

Requer macOS 13+ (Apple Silicon), `git` e `swift`. Clona a tag da versão mais recente, compila localmente, remove a quarentena e instala em `/Applications`.

As Releases não incluem `.app.zip`. Downloads sem assinatura feitos pelo navegador são bloqueados pelo Gatekeeper. Como alternativa, execute `./scripts/build-local.sh` em um clone.

## Módulos

| Módulo | Padrão | O que oferece |
| --- | --- | --- |
| **Quota** | ligado | Uso de 5h / 7d, renovação, tendência de tokens, estimativa de custo e provedores |
| **Work / Break** | desligado | Timer de foco, contagem regressiva na barra e sobreposição de pausa |
| **System** | desligado | CPU / memória, categorias de disco e processos principais |
| **Goals** | desligado | Today / Week / Vision / Schedule, notas, etiquetas e mapa de calor |
| **Pet** | ponte | Navi opcional via `~/Library/Application Support/Kaji/pet-state.json` |

Tema: somente **Mono** (preto / branco / cinza, claro e escuro).

## Compilação

```sh
swift test
./scripts/build-local.sh
```

## Links

- [Versão mais recente](https://github.com/MisterBrookT/kaji/releases/latest)
- [AGENTS.md](AGENTS.md): notas para contributors / agents
- [dev_docs/](dev_docs/README.md): specs internas

## Licença

MIT. Consulte [LICENSE](LICENSE).
