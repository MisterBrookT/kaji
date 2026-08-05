<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**La capa personal de estado y control para un Mac nativo de IA.**

Lo que importa hoy, a un vistazo de distancia.

[English](README.md) · [中文](README.zh.md) · [Português](README.pt-BR.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="Estrellas en GitHub"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Licencia MIT"></a>
<img src="https://img.shields.io/github/v/release/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Última versión">

</div>

https://github.com/user-attachments/assets/a345bc3f-d74e-4092-8e8f-5730b154d39c

## Qué es

Kaji lleva a la **barra de menús** los estados vivos que te importan. Esto incluye cuotas de IA, enfoque, objetivos y tu Mac.

¿Por qué la barra de menús? Porque permanece junto a lo que ya estás haciendo: mira para saber, pasa el cursor para obtener contexto y haz clic para actuar. Sin cambiar de app ni recibir una notificación que exija atención.

Kaji empieza pequeño. Quota está activado. Los demás módulos son opcionales. Un solo shell. Únicamente las señales que eliges mantener cerca.

`Kaji` viene del japonés `舵 / かじ`. Significa timón.

[Lee la visión](dev_docs/product/vision.md).

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
| **System** | desactivado | CPU / memoria, categorías de disco y procesos principales |
| **Goals** | desactivado | Today / Week / Vision / Schedule, notas, etiquetas y mapa de calor |
| **AI News** | desactivado | Top 10 de AI HOT, resúmenes al pasar el cursor y contexto de fuentes |
| **Pet** | puente | Navi opcional mediante `~/Library/Application Support/Kaji/pet-state.json` |

Tema: solo **Mono** (negro / blanco / gris, claro y oscuro).

## Compilación

```sh
swift test
./scripts/build-local.sh
```

## Enlaces

- [Última versión](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md): notas para contributors / agents
- [dev_docs/](dev_docs/README.md): specs internas

## Licencia

MIT. Consulta [LICENSE](LICENSE).
