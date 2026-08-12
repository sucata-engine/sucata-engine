> This repository has only the installer of the sucata engine, if you want to learn more about it you can see [sucata-player](https://github.com/sucata-engine/sucata-player) and [sucata-cli](https://github.com/sucata-engine/sucata-cli)

<div align="center">
    <img src="assets/sucata.png" height="150" width="150" />
</div>

<h1 align="center">Sucata</h1>

<p align="center">
    Gather your scraps and recycle into a game! <br/>
</p>

An open-source 2D game engine made with Odin programming language and Lua as scripting language, inspired by Love2D and Godot Engine.

[Website/Documentation](https://sucata.dev) | [Discord](https://discord.com/invite/Rv9EavmaJQ)

### ✨ Features ✨

- Render images and texts with GPU acceleration (using native libraries like D11X, Metal, OpenGL)
- Audio playback and manipulation
- Input handling (keyboard, mouse)
- Gamepad support
- Scene management
- Lua scripting
- Cross-platform support (Windows, macOS, Linux)
- Simple and intuitive file system for asset management
- Simple Custom Shader support
- Native call support for C/C++ functions

#### Future plans

- More animation features
- Network multiplayer support
- Particle system
- Maybe 3D support in the future
- Support with [Tiled](https://www.mapeditor.org)

<br>

## Table of Contents

- [🔩 What is Sucata?](#what-is-sucata)
- [🔧 Installation](#installation)
- [📝 Getting Started](#getting-started)
- [🌱 Examples](#examples)
- [📚 Libraries](#libraries)
- [🙏 Special Thanks](#special-thanks)
- [🤔 FAQ](#faq)

<br>
<a id="what-is-sucata"></a>

## 🔩 What is Sucata?

Sucata game engine is a 2D game engine made to be simple and easy to use, with a lot of features to make your game development experience better.

The goal is to make a create game experience similar good and smooth using only Lua scripting language.


<a id="installation"></a>

## 🔧 Installation

### MacOS/Linux
```sh
curl -fsSL https://raw.githubusercontent.com/sucata-engine/sucata-engine/refs/heads/main/install_unix.sh | bash
```

### Windows
```sh
irm https://raw.githubusercontent.com/sucata-engine/sucata-engine/refs/heads/main/install_windows.ps1 | iex
```

### Installing the Sucata Addon
1. Install the [sumneko lua extension](https://luals.github.io/) on your favorite IDE
2. Open the Addon Manager
3. Search for 'sucata' and install
> You can see the manual instalation [here](https://github.com/sucata-engine/meteors-sucata)

<br>
<a id="getting-started"></a>

## 📝 Getting Started

Read more at [sucata.dev](https://www.sucata.dev/getting-started/first-project/overview/)

<br>
<a id="examples"></a>

## 🌱 Examples

### Meteors

A game inspired by the classic Asteroids game, where you need to survive as long as possible avoiding meteors.

[Link](https://github.com/sucata-engine/meteors-sucata)

<br>
<a id="libraries"></a>

## 📚 Libraries

Some libraries used in Sucata Game Engine:

- [odin](https://odin-lang.org/) - Programming language used to build the engine
- [lua](https://www.lua.org/) - Scripting language used in the engine
- [sokol](https://github.com/floooh/sokol) - Cross-platform development libraries for graphics, audio, and input handling
- [sokol-tools](https://github.com/floooh/sokol-tools) - Cross-platform shader tools for building shader
- [miniaudio](https://github.com/mackron/miniaudio) - Single file audio playback and capture library
- [lz4](https://github.com/lz4/lz4) - Fast compression algorithm for asset compression
- [SDL3](https://github.com/libsdl-org/SDL) - Simple DirectMedia Layer for gamepad support

<br>
<a id="special-thanks"></a>

## 🙏 Special Thanks

- [Ellora](https://github.com/elloramir)
- [ThornDuck](https://github.com/MuriloMGrosso)
- [Randy](https://github.com/randyprime)

<br>
<a id="faq"></a>

## 🤔 FAQ

- **I Found a BUG!** _[Click here](https://github.com/sucata-engine/sucata-engine/issues) and open an issue_
- **Can I help with the project?** _Sure! just send your PR or idea_
- **Can I contact you?** _Yep, send email to contact@gump.dev_
