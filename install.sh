#!/bin/bash

# Crear la estructura de directorios
mkdir -p measure-tool_1.0-1/DEBIAN
mkdir -p measure-tool_1.0-1/usr/local/bin
mkdir -p measure-tool_1.0-1/usr/share/applications
mkdir -p measure-tool_1.0-1/usr/share/icons/hicolor/64x64/apps

# Compilar el programa
valac --pkg gtk+-3.0 measure_tool.vala -o measure_tool

# Copiar archivos a la estructura del paquete
cp measure_tool measure-tool_1.0-1/usr/local/bin/
cp measure-tool.desktop measure-tool_1.0-1/usr/share/applications/
cp measure-tool.png measure-tool_1.0-1/usr/share/icons/hicolor/64x64/apps/

# Establecer permisos
chmod 755 measure-tool_1.0-1/usr/local/bin/measure_tool
chmod 644 measure-tool_1.0-1/usr/share/applications/measure-tool.desktop
chmod 644 measure-tool_1.0-1/usr/share/icons/hicolor/64x64/apps/measure-tool.png

# Crear el paquete
dpkg-deb --build measure-tool_1.0-1