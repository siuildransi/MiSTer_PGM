# Documentación Técnica: CI/CD y Compilación Automática

Este documento detalla el pipeline de integración continua y los procedimientos para compilar el core PGM manualmente.

## 🚀 Pipeline de GitHub Actions

**Archivo**: `.github/workflows/ci_build.yml`

El flujo de trabajo se activa en cada `push` (excepto si solo se modifican archivos `.md`).

### Pasos del Proceso:
1.  **Setup**: Instala un entorno Ubuntu limpio.
2.  **Submódulos**: Clona recursivamente los repositorios de las CPUs (`fx68k`, `T80`).
    - **⚠️ ERROR COMÚN**: Si los submódulos no están actualizados, la compilación fallará en Quartus porque faltarán los archivos `.sv` de la 68k o `.vhd` del Z80.
3.  **Build Automation**: Utiliza el script `build.sh` de los MiSTer Nightlies. Este script descarga dinámicamente una versión de **Quartus Prime Lite 17.0** y realiza la síntesis.
4.  **Artifacts**: Sube el archivo `.rbf` generado.

## 🛠️ Compilación Local (Quartus Prime)

### Requisitos:
- **Versión**: Quartus Prime Lite Edition **17.0** (obligatorio para compatibilidad con MiSTer).
- **Dispositivo**: Cyclone V SE (5CSEBA6U23I7).

### Procedimiento:
1. Abrir `PGM.qpf`.
2. Verificar `files.qip`: Este archivo debe listar **todos** los módulos RTL. Si creas un archivo `.sv` nuevo y no lo añades aquí, Quartus no lo incluirá en el diseño.
3. Ejecutar "Start Compilation".

## ⚠️ Guía de Resolución de Errores (Troubleshooting)

| Error en logs de Actions | Causa Probable | Solución |
| :--- | :--- | :--- |
| `Module 'fx68k' not found` | Submódulo git vacío | Ejecutar `git submodule update --init --recursive` |
| `Critical Warning: Synopsys Design Constraints File not found` | Falta archivo `.sdc` | Crear un archivo `.sdc` con `create_clock` para 50MHz y 25MHz |
| `Error: Port "xxx" does not exist` | Desajuste entre `emu.sv` y `PGM.sv` | Verificar que la instancia en `emu.sv` coincide con la declaración en `PGM.sv` |
| `Multiple drivers for signal...` | Varias asignaciones a un `reg` | Buscar bloques `always` duplicados que escriban a la misma variable |

## 📦 Gestión de Versiones y Ramas

- **`main`**: Rama estable. Solo debe contener código verificado y funcional.
- **`dev-macbook-pgm-core`**: Rama de desarrollo activo. Aquí es donde se prueban nuevas funcionalidades del video, audio o controles.

> **⚠️ REGLA DE ORO**: Antes de hacer un merge de `dev` a `main`, verificar que la síntesis en GitHub Actions ha terminado en verde (éxito). No integrar código que no compile.
