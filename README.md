# MiSTer PGM Core Development

![MiSTer PGM](https://img.shields.io/badge/Platform-MiSTer_FPGA-orange)
![Build Status](https://github.com/siuildransi/MiSTer_PGM/workflows/Build%20MiSTer%20Core/badge.svg)

Núcleo para la placa arcade **PolyGame Master (PGM)** de IGS, implementado para la plataforma **MiSTer FPGA** (Cyclone V).

---

## 📌 Documentación Detallada

| Documento | Contenido |
| :--- | :--- |
| 🏗️ [Arquitectura y Memoria](docs/memory.md) | Mapa de direcciones, arbitraje SDRAM, buses y CDC |
| 📺 [Motor de Video](docs/video.md) | Sprites con zoom, capas TX/BG, line buffers y mixer |
| 🔊 [Sistema de Sonido](docs/audio.md) | Z80, ICS2115, latches de comunicación y TDM |
| 🕹️ [Controles e I/O](docs/io.md) | Mapeo de joysticks, botones, monedas y sistema |
| ⚙️ [CI/CD y Compilación](docs/ci_cd.md) | GitHub Actions, compilación local con Quartus |

---

## 🛠️ Resumen Técnico

### Componentes Implementados

| Componente | Módulo | Reloj | Estado |
| :--- | :--- | :--- | :--- |
| CPU principal | `fx68k` (68000) | ~12.5 MHz (CLK_50M/4) | ✅ Funcional |
| CPU de sonido | `T80s` (Z80) | ~6.25 MHz (CLK_50M/8) | ✅ Funcional |
| Sintetizador | `ics2115.sv` | clk_8m | ✅ 32 voces TDM |
| Motor de video | `pgm_video.sv` | clk_vid (~25.175 MHz) | ✅ Sprites + TX + BG |
| Árbitro SDRAM | en `PGM.sv` | CLK_50M | ✅ CPU > Video > Audio |
| RAM de trabajo | `dpram_dc.sv` × 2 | 20MHz / video_clk | ✅ True Dual-Port |

> **⚠️ NOTA SOBRE RELOJES**: Los relojes de CPU son divisores simples de 50MHz, no frecuencias exactas del hardware PGM original (20MHz y 8.468MHz). Para una implementación ciclo-exacta futura, se necesitaría un PLL adicional con estas frecuencias.

### Árbol de Archivos del Proyecto

```
PGM/
├── emu.sv                          # Top-level MiSTer (relojes, HPS, routing)
├── PGM.sv                          # Módulo principal (CPUs, memoria, árbitro)
├── PGM.qpf / PGM.qsf              # Proyecto Quartus
├── files.qip                       # Lista de archivos fuente para síntesis
├── Demon Front.mra                 # Archivo MRA de ejemplo
├── rtl/
│   ├── pll.v                       # PLL: 50MHz → 25.175MHz (video)
│   ├── dpram_dc.sv                 # True Dual-Port RAM (dual clock)
│   ├── audio/
│   │   └── ics2115.sv              # Sintetizador wavetable 32 voces
│   ├── video/
│   │   ├── pgm_video.sv            # Motor de video completo
│   │   └── dpram.sv                # Single-clock DPRAM (line buffers)
│   └── cpu/
│       ├── fx68k/                  # Core 68000 (submódulo git)
│       └── T80/                    # Core Z80 (submódulo git)
├── docs/                           # Documentación técnica
└── .github/workflows/ci_build.yml  # Pipeline CI/CD
```

### Carga de Software (MRA/ioctl)

El core utiliza carga segmentada controlada por `ioctl_index`:

| `ioctl_index` | Destino | Descripción |
| :--- | :--- | :--- |
| `0` | SDRAM (DDRAM) | BIOS + P-ROM + datos gráficos y de sonido |
| `1` | Sound RAM (dpram_dc) | Firmware Z80 (cargado a RAM privada del Z80) |

> **⚠️ IMPORTANTE**: La Sound RAM se carga vía Puerto A del `dpram_dc` a 50MHz (`ioctl_download && ioctl_wr && ioctl_index == 1`). El Z80 accede por Puerto B a clk_8m. **NO cambiar** el orden de los puertos en `sound_ram` sin actualizar ambos lados.

## 🚀 Cómo Empezar

1. Clonar recursivamente: `git clone --recursive <url>`
2. Abrir en **Quartus Prime Lite Edition 17.0** → `PGM.qpf`
3. Compilar o usar el pipeline de **GitHub Actions**

> **⚠️ SUBMÓDULOS**: Los cores de CPU (`fx68k`, `T80`) son submódulos git. Sin `--recursive`, la compilación fallará por archivos faltantes.

---

## ⚠️ Notas Críticas para Desarrollo Futuro

### Señales que NO deben modificarse sin cuidado

| Señal/Módulo | Razón |
| :--- | :--- |
| `DDRAM_CLK` en `emu.sv` | **DEBE ser `CLK_50M`**. Si se pone a `1'b0`, el controlador DDR no funciona |
| `CLK_VIDEO` en `emu.sv` | **DEBE ser salida de PLL** (requisito Quartus para clock switching) |
| Puertos I/O del ICS2115 | Son **`0x02`/`0x03`** del Z80, NO `0x80`. Ver `PGM.sv` líneas 257-258 |
| `sound_ack_hold` en `PGM.sv` | Handshake CDC crítico (50MHz→8MHz). No simplificar a pulso simple |
| `dpram_dc` puertos A/B | Puerto A = loader/CPU (50MHz/20MHz), Puerto B = Z80/video. No intercambiar |

### Errores Comunes Ya Resueltos
1. **Multiple drivers**: No crear dos bloques `always @(posedge clk)` que escriban a la misma señal (ejemplo: `ics2115.sv` tenía escritura duplicada a `cur_reg_addr`).
2. **Variables combinacionales en bloques secuenciales**: Usar `wire`/`assign` para cálculos intermedios, no `reg` con `=` dentro de `always @(posedge clk)`.
3. **Asignaciones faltantes**: `CLK_VIDEO`, `CE_PIXEL`, `VGA_SL`, `VIDEO_ARX`, `VIDEO_ARY` deben estar definidas en `emu.sv` o Quartus generará errores de puertos sin conectar.

---
## 📜 Créditos
Desarrollado para la comunidad MiSTer FPGA. Basado en la documentación técnica de MAME y el esfuerzo de ingeniería inversa de la arquitectura IGS.
