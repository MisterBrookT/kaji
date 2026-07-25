<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**La barra de menús que merece quedarse en la era de la IA.**

Consulta la presión de tus cuotas de un vistazo y vuelve al agent.

[English](README.md) · [中文](README.zh.md) · [Português](README.pt-BR.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="Estrellas en GitHub"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Licencia MIT"></a>
<img src="https://img.shields.io/github/v/release/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Última versión">

<br />
<br />

<img src="dev_docs/assets/readme-hero-20260724.jpg" width="860" alt="Popover de Kaji en la barra de menús" />

</div>

## Qué es

Una app de barra de menús para macOS que controla las **cuotas de AI coding** (Claude Code / Cursor / Codex y otros). Los anillos de la barra muestran el uso y los tiempos de reinicio para que detectes la presión antes de que una ejecución se detenga a mitad de camino.

Sin dashboard. Sin icono en el Dock. Módulos opcionales para enfoque y descansos, carga del sistema y objetivos diarios — desactivados hasta que los habilites en Ajustes.

`Kaji` viene del japonés `舵 / かじ` — timón.

## Instalación

```sh
curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
```

Requiere macOS 13+ (Apple Silicon), `git` y `swift`. Clona la etiqueta de la versión más reciente, compila localmente, elimina la cuarentena e instala en `/Applications`.

Las Releases no incluyen `.app.zip`: Gatekeeper bloquea las descargas sin firma realizadas desde el navegador. También puedes ejecutar `./scripts/build-local.sh` desde un clon.

## Módulos

| Módulo | Predeterminado | Qué incluye |
| --- | --- | --- |
| **Quota** | activado | Uso de 5h / 7d, reinicio, tendencia de tokens, coste estimado y proveedores |
| **Work / Break** | desactivado | Temporizador de enfoque, cuenta regresiva en la barra y superposición de descanso |
| **System** | desactivado | CPU / memoria / disco, procesos principales y Auto Reclaim conservador |
| **Goals** | desactivado | Objetivos diarios + mapa de calor |
| **Pet** | puente | Navi opcional mediante `~/Library/Application Support/Kaji/pet-state.json` |

Tema: solo **Mono** (negro / blanco / gris, claro y oscuro).

## Compilación

```sh
swift test
./scripts/build-local.sh
```

## Enlaces

- [Última versión](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md) — notas para contributors / agents
- [dev_docs/](dev_docs/README.md) — specs internas

## Licencia

MIT. Consulta [LICENSE](LICENSE).
