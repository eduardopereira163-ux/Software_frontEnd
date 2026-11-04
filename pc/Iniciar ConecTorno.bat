@echo off
rem ConecTorno no PC do professor: liga o Hotspot movel, sobe o servidor e abre o painel no navegador.
rem Nao instala nada: usa o Python portatil da pasta "python" e o conversor de PDF da pasta "poppler".
chcp 65001 >nul
title ConecTorno - servidor (NAO FECHE ESTA JANELA)
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
set PORTA=8080

if not exist "python\python.exe" (
  echo ERRO: a pasta "python" nao foi encontrada ao lado deste arquivo.
  echo Copie a pasta ConecTorno-PC inteira, nao so este arquivo.
  pause
  exit /b 1
)

echo ==^> Ligando o Hotspot movel do Windows...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ligar-hotspot.ps1"
echo.
echo ==^> Iniciando o ConecTorno
echo    Painel neste computador:         http://localhost:%PORTA%
echo    Painel no celular (no hotspot):  http://192.168.137.1:%PORTA%
echo    Telas dos tornos (Raspberry):    entram sozinhas em http://192.168.137.1:%PORTA%
echo.
echo    Se o Windows perguntar sobre o Firewall, clique em "Permitir acesso".
echo    Deixe esta janela aberta durante a aula. Para encerrar, feche-a.
echo.

rem Abre o painel no navegador alguns segundos depois, quando o servidor ja estiver no ar.
start "" /min cmd /c "timeout /t 3 /nobreak >nul & start "" http://localhost:%PORTA%"

python\python.exe servidor\servidor.py --porta %PORTA% --dados dados

echo.
echo O servidor parou. Se apareceu um erro acima (ex.: porta em uso), feche outras janelas do ConecTorno e abra de novo.
pause
