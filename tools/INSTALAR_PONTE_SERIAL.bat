@echo off
title Punch Challenge - Instalacao da ponte serial
echo.
echo ================================================
echo     PUNCH CHALLENGE - INSTALADOR SERIAL
echo ================================================
echo.
py -m pip install --upgrade pyserial
if errorlevel 1 python -m pip install --upgrade pyserial
echo.
echo Instalacao concluida. Feche esta janela e abra o jogo.
pause

