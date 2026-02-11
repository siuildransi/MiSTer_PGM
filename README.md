# MiSTer PGM Core Development

![MiSTer PGM](https://img.shields.io/badge/Platform-MiSTer_FPGA-orange)
![Build Status](https://github.com/siuildransi/MiSTer_PGM/workflows/Build%20MiSTer%20Core/badge.svg)

Este repositorio alberga el desarrollo del núcleo para la placa arcade **PolyGame Master (PGM)** de IGS. Diseñado para ofrecer una emulación ciclo-exacta aprovechando la potencia de la FPGA Cyclone V.

## 📌 Documentación Detallada

Para comprender a fondo el funcionamiento del núcleo, consulta los manuales específicos:

- 🏗️ **[Arquitectura y Memoria](docs/memory.md)**: Mapa de direcciones, arbitraje de SDRAM y gestión de buses.
- 📺 **[Motor de Video](docs/video.md)**: Detalles sobre el motor de sprites con zoom, capas de scroll y timings.
- 🔊 **[Infraestructura de Sonido](docs/audio.md)**: Implementación del Z80, latches de comunicación e ICS2115.
- 🕹️ **[Controles e I/O](docs/io.md)**: Mapeo de joysticks, botones y sistemas de entrada.

---

## 🛠️ Resumen Técnico Preliminar

### Componentes Clave
- **Main CPU**: 68000 @ 20MHz (Core `fx68k`).
- **Sound CPU**: Z80 @ 8.4MHz (Core `T80s`).
- **GPU**: Custom IGS Video System con Zoom por hardware.
- **Audio**: ICS2115 Wavefront Synthesizer.

### Carga de Software (MRA/ioctl)
El core utiliza una carga segmentada para optimizar la memoria:
- **ID 0**: Datos de juego cargados en la SDRAM externa.
- **ID 1**: Firmware de audio cargado directamente en la RAM privada del Z80.

## 🚀 Cómo Empezar
1. Clona el repositorio recursivamente para obtener los submódulos de las CPUs.
2. Abre el proyecto en **Quartus Prime 17.0**.
3. Compila el archivo `PGM.qpf` o usa el pipeline de **GitHub Actions**.

---
## 📜 Créditos
Desarrollado para la comunidad MiSTer FPGA. Basado en la documentación técnica de MAME y el esfuerzo de ingeniería inversa de la arquitectura IGS.
