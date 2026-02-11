# Documentación Técnica: CI/CD y Compilación Automática

El proyecto utiliza **GitHub Actions** para automatizar el proceso de síntesis y generación de binarios para MiSTer FPGA.

## Pipeline de Compilación (`.github/workflows/ci_build.yml`)

Cada vez que se realiza un `push` a cualquier rama del repositorio, se activa un flujo de trabajo que realiza los siguientes pasos:

1.  **Entorno**: Se utiliza un contenedor `ubuntu-latest`.
2.  **Checkout**: Se descarga el código fuente y los submódulos.
3.  **Soporte de Automatización**: Se descarga el script de compilación remota de `MiSTer-unstable-nightlies/Build-Automation_MiSTer`.
4.  **Síntesis**: El script invoca a Quartus para realizar la síntesis, el placement y el routing del diseño.
5.  **Artefactos**: El archivo final `.rbf` (compilado como `PGM.rbf`) se sube como un artefacto de GitHub.

## Cómo Descargar el Core Compilado
1. Ve a la pestaña **Actions** en tu repositorio de GitHub.
2. Selecciona el último "workflow run" exitoso.
3. Al final de la página, en la sección **Artifacts**, encontrarás el archivo `PGM_Core.zip` con el binario listo para usar.

## Configuración de Entorno Local
Si deseas compilar localmente en tu ordenador personal:
- **Software**: Quartus Prime Lite Edition v17.0.
- **Archivo de Proyecto**: `PGM.qpf`.
- **Archivos Fuente**: Gestionados a través de `files.qip`.

---
*Este sistema garantiza que cada cambio sea validado por el sintetizador de Quartus antes de ser probado en hardware real.*
